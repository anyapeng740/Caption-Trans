import 'package:caption_trans/core/constants.dart';
import 'package:caption_trans/services/alist/alist_audio_convert_service.dart';
import 'package:caption_trans/services/alist/alist_service.dart';
import 'package:caption_trans/services/alist/alist_audio_task_manager.dart';
import 'package:caption_trans/services/settings_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../widgets/background_job_center_dialog.dart';

class AListTaskPage extends StatefulWidget {
  final SettingsService settingsService;

  const AListTaskPage({super.key, required this.settingsService});

  @override
  State<AListTaskPage> createState() =>
      _AListTaskPageState();
}

class _AListTaskPageState
    extends State<AListTaskPage> {
  final AListService _alist = AListService();

  late final TextEditingController _baseUrlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _browsePathController;
  late final TextEditingController _outputDirController;
  late final TextEditingController _minVideoSizeController;
  late final TextEditingController _blockedNamesController;

  bool _connecting = false;
  bool _loadingRoot = false;

  String? _token;
  String? _errorMessage;

  AListAudioFormat _format = AListAudioFormat.flac;
  int _concurrency = 2;
  int _minVideoSizeMB = 50;

  final Set<String> _selectedPaths = <String>{};
  List<_RemoteNode> _nodes = <_RemoteNode>[];

  @override
  void initState() {
    super.initState();
    final SettingsService settings = widget.settingsService;
    _baseUrlController = TextEditingController(text: settings.alistBaseUrl);
    _usernameController = TextEditingController(text: settings.alistUsername);
    _passwordController = TextEditingController(text: settings.alistPassword);
    _browsePathController = TextEditingController(
      text: settings.alistBrowsePath,
    );
    _outputDirController = TextEditingController(
      text: settings.alistAudioOutputDir,
    );
    _minVideoSizeMB = settings.alistMinVideoSizeMB;
    _minVideoSizeController = TextEditingController(text: '$_minVideoSizeMB');
    _blockedNamesController = TextEditingController(
      text: settings.alistBlockedVideoNames,
    );

    final String formatId = settings.alistAudioFormat.trim().toLowerCase();
    _format = AListAudioFormat.values.firstWhere(
      (AListAudioFormat item) => item.id == formatId,
      orElse: () => AListAudioFormat.flac,
    );
    _concurrency = settings.alistAudioConcurrency.clamp(1, 5);
  }

  @override
  void dispose() {
    _alist.dispose();
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _browsePathController.dispose();
    _outputDirController.dispose();
    _minVideoSizeController.dispose();
    _blockedNamesController.dispose();
    super.dispose();
  }

  Set<String> get _blockedNameSet {
    return _blockedNamesController.text
        .split(RegExp(r'\r?\n'))
        .map(_normalizeBlockedName)
        .where((String item) => item.isNotEmpty)
        .toSet();
  }

  String _normalizeBlockedName(String value) {
    return value.replaceAll(RegExp(r'\s+'), '').toLowerCase().trim();
  }

  Future<void> _persistSettings() async {
    final SettingsService settings = widget.settingsService;
    await settings.setAListBaseUrl(_baseUrlController.text.trim());
    await settings.setAListUsername(_usernameController.text.trim());
    await settings.setAListPassword(_passwordController.text);
    await settings.setAListBrowsePath(_browsePathController.text.trim());
    await settings.setAListAudioOutputDir(_outputDirController.text.trim());
    await settings.setAListAudioFormat(_format.id);
    await settings.setAListAudioConcurrency(_concurrency);
    await settings.setAListMinVideoSizeMB(_minVideoSizeMB);
    await settings.setAListBlockedVideoNames(_blockedNamesController.text);
  }

  Future<void> _connectAndLoadRoot() async {
    if (_connecting || _loadingRoot) return;
    setState(() {
      _connecting = true;
      _errorMessage = null;
    });
    try {
      await _persistSettings();
      final AListTarget target = _alist.normalizeBaseUrl(
        _baseUrlController.text,
      );
      final String token = await _alist.login(
        baseUrl: target.baseUrl,
        username: _usernameController.text,
        password: _passwordController.text,
      );

      String path = _browsePathController.text.trim();
      if (path.isEmpty || path == '/') {
        path = target.suggestedPath;
      }
      path = _alist.normalizePath(path);

      if (!mounted) return;
      setState(() {
        _token = token;
        _baseUrlController.text = target.baseUrl;
        _browsePathController.text = path;
      });
      await _persistSettings();
      await _loadRoot();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  Future<void> _loadRoot() async {
    final String? token = _token;
    if (token == null || token.isEmpty) {
      setState(() => _errorMessage = '请先连接 AList。');
      return;
    }

    setState(() {
      _loadingRoot = true;
      _errorMessage = null;
    });
    try {
      final String path = _alist.normalizePath(_browsePathController.text);
      final List<AListEntry> entries = await _alist.list(
        baseUrl: _baseUrlController.text.trim(),
        token: token,
        remotePath: path,
        allowedExtensions: AppConstants.videoExtensions.toSet(),
      );
      if (!mounted) return;
      setState(() {
        _browsePathController.text = path;
        _nodes = entries.map(_RemoteNode.new).toList();
        _selectedPaths.clear();
      });
      await _persistSettings();
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loadingRoot = false);
      }
    }
  }

  Future<void> _toggleDir(_RemoteNode node) async {
    if (!node.entry.isDir) return;
    setState(() {
      node.expanded = !node.expanded;
    });
    if (!node.expanded || node.loaded || node.loading) return;

    final String? token = _token;
    if (token == null || token.isEmpty) return;

    setState(() => node.loading = true);
    try {
      final List<AListEntry> entries = await _alist.list(
        baseUrl: _baseUrlController.text.trim(),
        token: token,
        remotePath: node.entry.path,
        allowedExtensions: AppConstants.videoExtensions.toSet(),
      );
      if (!mounted) return;
      setState(() {
        node.children = entries.map(_RemoteNode.new).toList();
        node.loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) {
        setState(() => node.loading = false);
      }
    }
  }

  Future<void> _toggleSelection(_RemoteNode node, bool selected) async {
    if (!node.entry.isDir) {
      setState(() {
        if (selected) {
          _selectedPaths.add(node.entry.path);
        } else {
          _selectedPaths.remove(node.entry.path);
        }
      });
      return;
    }

    await _ensureDirLoadedDeep(node);
    final List<AListEntry> files = _collectFiles(<_RemoteNode>[
      node,
    ]).where(_matchesVideoFilters).toList();
    setState(() {
      for (final AListEntry item in files) {
        if (selected) {
          _selectedPaths.add(item.path);
        } else {
          _selectedPaths.remove(item.path);
        }
      }
    });
  }

  Future<void> _ensureDirLoadedDeep(_RemoteNode node) async {
    if (!node.entry.isDir) return;
    if (!node.loaded && !node.loading) {
      await _toggleDir(node);
    }
    for (final _RemoteNode child in node.children.where((n) => n.entry.isDir)) {
      await _ensureDirLoadedDeep(child);
    }
  }

  Future<void> _selectAllLoaded() async {
    final List<AListEntry> files = _collectFiles(
      _nodes,
    ).where(_matchesVideoFilters).toList();
    setState(() {
      for (final AListEntry item in files) {
        _selectedPaths.add(item.path);
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedPaths.clear());
  }

  bool _matchesVideoFilters(AListEntry entry) {
    if (entry.isDir) return true;

    if (_minVideoSizeMB > 0) {
      final int minBytes = _minVideoSizeMB * 1024 * 1024;
      if (entry.size < minBytes) return false;
    }

    final Set<String> blocked = _blockedNameSet;
    if (blocked.isNotEmpty &&
        blocked.contains(_normalizeBlockedName(entry.name))) {
      return false;
    }

    return true;
  }

  List<AListEntry> _collectFiles(List<_RemoteNode> nodes) {
    final List<AListEntry> files = <AListEntry>[];
    for (final _RemoteNode node in nodes) {
      if (node.entry.isDir) {
        files.addAll(_collectFiles(node.children));
      } else {
        files.add(node.entry);
      }
    }
    return files;
  }

  _SelectionState _selectionStateForDir(_RemoteNode node) {
    final List<AListEntry> files = _collectFiles(<_RemoteNode>[
      node,
    ]).where(_matchesVideoFilters).toList();
    if (files.isEmpty) return const _SelectionState(false, false);
    int selectedCount = 0;
    for (final AListEntry item in files) {
      if (_selectedPaths.contains(item.path)) {
        selectedCount++;
      }
    }
    return _SelectionState(
      selectedCount == files.length,
      selectedCount > 0 && selectedCount < files.length,
    );
  }

  int get _loadedFileCount => _collectFiles(_nodes).length;

  int get _visibleFileCount =>
      _collectFiles(_nodes).where(_matchesVideoFilters).length;

  Future<void> _pickOutputDir() async {
    final String? picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择保存目录',
    );
    if (picked == null || picked.trim().isEmpty) return;
    setState(() => _outputDirController.text = picked.trim());
    await _persistSettings();
  }

  Future<void> _startConvert() async {
    final String? token = _token;
    if (token == null || token.isEmpty) {
      setState(() => _errorMessage = '请先连接 AList。');
      return;
    }

    final String outputDir = _outputDirController.text.trim();
    if (outputDir.isEmpty) {
      setState(() => _errorMessage = '请先选择保存目录。');
      return;
    }

    final Map<String, AListEntry> fileMap = <String, AListEntry>{};
    for (final AListEntry entry in _collectFiles(_nodes)) {
      fileMap[entry.path] = entry;
    }
    final List<String> targets = _selectedPaths.where((String path) {
      final AListEntry? entry = fileMap[path];
      return entry != null && _matchesVideoFilters(entry);
    }).toList()..sort();
    if (targets.isEmpty) {
      setState(() => _errorMessage = '请先选择至少一个视频文件。');
      return;
    }

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await _persistSettings();
    await AListAudioTaskManager.instance.enqueueBatch(
      baseUrl: _baseUrlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      outputDir: outputDir,
      format: _format,
      concurrency: _concurrency,
      remotePaths: targets,
    );
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('已加入后台任务，可通过悬浮球查看进度。')),
    );
  }

  Future<void> _openTaskCenter() {
    return showBackgroundJobCenterDialog(
      context,
      initialTab: BackgroundJobTab.audio,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool busy = _connecting || _loadingRoot;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.audiotrack_rounded,
                color: theme.colorScheme.primary,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'AList 批量转音频',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => showBackgroundJobCenterDialog(
                  context,
                  initialTab: BackgroundJobTab.audio,
                ),
                icon: const Icon(Icons.bubble_chart_rounded),
                label: const Text('任务中心'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildConnectPanel(theme, busy),
          if (_errorMessage != null) ...<Widget>[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _errorMessage!,
                style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(flex: 3, child: _buildFileTreePanel(theme, busy)),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _buildConvertPanel(theme, busy)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectPanel(ThemeData theme, bool busy) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _baseUrlController,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'AList 地址',
                    hintText:
                        'http://127.0.0.1:5244 或 http://host/alist/dav/115',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _usernameController,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _passwordController,
                  enabled: !busy,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密码',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _browsePathController,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: '浏览路径',
                    hintText: '/115/nana',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: busy ? null : _connectAndLoadRoot,
                icon: _connecting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_rounded),
                label: const Text('连接'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : _loadRoot,
                icon: _loadingRoot
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: const Text('刷新'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFileTreePanel(ThemeData theme, bool busy) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '视频列表',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '已加载 $_loadedFileCount 个，筛选后 $_visibleFileCount 个，已选 ${_selectedPaths.length} 个',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _minVideoSizeController,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '屏蔽小于多少 MB 的视频',
                    isDense: true,
                  ),
                  onChanged: (String value) {
                    final int parsed = int.tryParse(value.trim()) ?? 0;
                    setState(() => _minVideoSizeMB = parsed < 0 ? 0 : parsed);
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: busy ? null : _selectAllLoaded,
                child: const Text('全选已加载'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: busy ? null : _clearSelection,
                child: const Text('取消全选'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _blockedNamesController,
            enabled: !busy,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '屏蔽文件名（每行一个，空白会忽略）'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: _loadingRoot
                  ? const Center(child: CircularProgressIndicator())
                  : _nodes.isEmpty
                  ? Center(
                      child: Text(
                        '当前目录没有可用视频，或尚未加载。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    )
                  : ListView(
                      children: _nodes
                          .where((node) => _shouldShowNode(node))
                          .map((node) => _buildNodeRow(node, 0))
                          .toList(),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeRow(_RemoteNode node, int depth) {
    final bool isDir = node.entry.isDir;
    final _SelectionState state = isDir
        ? _selectionStateForDir(node)
        : _SelectionState(_selectedPaths.contains(node.entry.path), false);

    final Widget row = Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: Column(
        children: <Widget>[
          ListTile(
            dense: true,
            leading: isDir
                ? IconButton(
                    icon: Icon(
                      node.expanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.chevron_right_rounded,
                    ),
                    onPressed: () => _toggleDir(node),
                  )
                : const SizedBox(width: 40, child: Icon(Icons.movie_rounded)),
            title: Text(
              node.entry.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              isDir
                  ? node.entry.path
                  : '${node.entry.path}  |  ${(node.entry.size / (1024 * 1024)).toStringAsFixed(1)} MB',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
            trailing: Checkbox(
              value: isDir
                  ? (state.partiallySelected ? null : state.allSelected)
                  : state.allSelected,
              tristate: isDir,
              onChanged: (bool? value) => _toggleSelection(node, value == true),
            ),
          ),
          if (isDir && node.loading)
            const Padding(
              padding: EdgeInsets.only(left: 56, bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );

    if (!isDir || !node.expanded) {
      return row;
    }

    final List<Widget> children = <Widget>[row];
    for (final _RemoteNode child in node.children.where(
      (n) => _shouldShowNode(n),
    )) {
      children.add(_buildNodeRow(child, depth + 1));
    }
    return Column(children: children);
  }

  bool _shouldShowNode(_RemoteNode node) {
    if (node.entry.isDir) return true;
    return _matchesVideoFilters(node.entry);
  }

  Widget _buildConvertPanel(ThemeData theme, bool busy) {
    final AListAudioTaskManager manager = AListAudioTaskManager.instance;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '转换音频',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _outputDirController,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: '保存目录',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: busy ? null : _pickOutputDir,
                child: const Text('选择文件夹'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<AListAudioFormat>(
                  initialValue: _format,
                  decoration: const InputDecoration(
                    labelText: '输出格式',
                    isDense: true,
                  ),
                  items: AListAudioFormat.values
                      .map(
                        (AListAudioFormat f) =>
                            DropdownMenuItem<AListAudioFormat>(
                              value: f,
                              child: Text(f.displayName),
                            ),
                      )
                      .toList(),
                  onChanged: busy
                      ? null
                      : (AListAudioFormat? value) {
                          if (value == null) return;
                          setState(() => _format = value);
                        },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<int>(
                  initialValue: _concurrency,
                  decoration: const InputDecoration(
                    labelText: '并发数',
                    isDense: true,
                  ),
                  items: <int>[1, 2, 3, 4, 5]
                      .map(
                        (int c) =>
                            DropdownMenuItem<int>(value: c, child: Text('$c')),
                      )
                      .toList(),
                  onChanged: busy
                      ? null
                      : (int? value) {
                          if (value == null) return;
                          setState(() => _concurrency = value);
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              FilledButton.icon(
                onPressed: busy ? null : _startConvert,
                icon: const Icon(Icons.rocket_launch_rounded),
                label: const Text('加入后台任务'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _openTaskCenter,
                icon: const Icon(Icons.bubble_chart_rounded),
                label: const Text('查看任务中心'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '选择完视频后会直接加入后台队列。转换过程中可以关闭这个窗口，再通过悬浮球查看详情。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: AnimatedBuilder(
              animation: manager,
              builder: (BuildContext context, _) {
                final List<AListAudioBatchTask> batches = manager.batches;
                final List<AListAudioBatchTask> activeBatches = batches
                    .where(
                      (AListAudioBatchTask batch) =>
                          batch.status == AListAudioBatchStatus.queued ||
                          batch.status == AListAudioBatchStatus.running,
                    )
                    .toList();
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: activeBatches.isEmpty
                      ? Center(
                          child: Text(
                            '当前没有进行中的后台任务。',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '进行中批次 ${activeBatches.length} 个 · 运行中文件 ${manager.runningItemCount} 个',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: ListView.separated(
                                itemCount: activeBatches.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (BuildContext context, int index) {
                                  final AListAudioBatchTask batch =
                                      activeBatches[index];
                                  return Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: Colors.white.withValues(
                                        alpha: 0.03,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          '${batch.items.length} 个文件 · ${batch.outputDir}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          child: LinearProgressIndicator(
                                            value: batch.progress,
                                            minHeight: 6,
                                            backgroundColor: Colors.white
                                                .withValues(alpha: 0.08),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '完成 ${batch.completedCount}/${batch.items.length} · 失败 ${batch.failedCount} · 取消 ${batch.canceledCount}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: Colors.white.withValues(
                                                  alpha: 0.68,
                                                ),
                                              ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteNode {
  final AListEntry entry;
  bool expanded;
  bool loading;
  bool loaded;
  List<_RemoteNode> children;

  _RemoteNode(this.entry)
    : expanded = false,
      loading = false,
      loaded = false,
      children = <_RemoteNode>[];
}

class _SelectionState {
  final bool allSelected;
  final bool partiallySelected;

  const _SelectionState(this.allSelected, this.partiallySelected);
}
