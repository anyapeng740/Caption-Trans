import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/constants.dart';
import '../../models/translation_config.dart';
import '../../services/settings_service.dart';
import '../../services/subtitle/subtitle_batch_path_planner.dart';
import '../../services/subtitle/subtitle_batch_task_manager.dart';
import '../../services/translation/translation_service.dart';
import 'background_job_center_dialog.dart';
import 'translation_panel.dart' show defaultLlmBaseUrls;

Future<void> showSubtitleBatchDialog(
  BuildContext context, {
  required SettingsService settingsService,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SubtitleBatchDialog(settingsService: settingsService),
  );
}

class _SubtitleBatchDialog extends StatefulWidget {
  const _SubtitleBatchDialog({required this.settingsService});

  final SettingsService settingsService;

  @override
  State<_SubtitleBatchDialog> createState() => _SubtitleBatchDialogState();
}

class _SubtitleBatchDialogState extends State<_SubtitleBatchDialog> {
  late final TextEditingController _inputRootController;
  late final TextEditingController _outputRootController;
  late final TextEditingController _searchController;
  late final TextEditingController _minMediaSizeController;
  late final TextEditingController _llmBaseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _targetModelController;

  final Set<String> _selectedPaths = <String>{};
  final List<_LocalNode> _nodes = <_LocalNode>[];

  Map<String, ProviderCredential> _savedProviderCredentials =
      <String, ProviderCredential>{};
  List<String> _availableModels = <String>[];

  bool _loadingRoot = false;
  bool _isLoadingModels = false;
  bool _showOnlyUnprocessed = true;
  bool _enableTranslation = true;
  bool _bilingual = true;

  String _selectedModel = AppConstants.defaultWhisperModel;
  String _sourceLanguage = 'ja';
  String _llmProvider = 'Gemini (Google)';
  String _targetLanguage = 'zh';
  int _batchSize = 25;
  int _concurrency = 1;
  int _minMediaSizeMB = 50;

  String? _errorMessage;

  List<String> get _whisperModelOptions =>
      AppConstants.whisperModels.keys.toList(growable: false);

  String get _safeSelectedModel => _whisperModelOptions.contains(_selectedModel)
      ? _selectedModel
      : AppConstants.defaultWhisperModel;

  List<String> get _sourceLanguageOptions =>
      AppConstants.supportedLanguages.keys.toList(growable: false);

  String get _safeSourceLanguage =>
      _sourceLanguageOptions.contains(_sourceLanguage) ? _sourceLanguage : 'ja';

  List<String> get _targetLanguageOptions => AppConstants
      .supportedLanguages
      .keys
      .where((String code) => code != 'auto')
      .toList(growable: false);

  String get _safeTargetLanguage =>
      _targetLanguageOptions.contains(_targetLanguage) ? _targetLanguage : 'zh';

  List<String> get _providerOptions =>
      defaultLlmBaseUrls.keys.toList(growable: false);

  String get _safeProvider => _providerOptions.contains(_llmProvider)
      ? _llmProvider
      : 'Gemini (Google)';

  List<int> get _batchSizeOptions {
    final Set<int> values = <int>{10, 15, 20, 25, 30, 40};
    if (_batchSize > 0) {
      values.add(_batchSize);
    }
    final List<int> result = values.toList()..sort();
    return result;
  }

  int get _safeBatchSize => _batchSize > 0 ? _batchSize : 25;

  @override
  void initState() {
    super.initState();
    final SettingsService settings = widget.settingsService;
    final Map<String, ProviderCredential> savedCredentials =
        settings.llmProviderCredentials;
    final String provider = settings.llmProvider;
    final ProviderCredential? savedCredential = savedCredentials[provider];

    _inputRootController = TextEditingController(
      text: settings.subtitleBatchInputRoot,
    );
    _outputRootController = TextEditingController(
      text: settings.subtitleBatchOutputRoot,
    );
    _searchController = TextEditingController();
    _minMediaSizeMB = settings.subtitleBatchMinMediaSizeMB;
    _minMediaSizeController = TextEditingController(text: '$_minMediaSizeMB');
    _llmBaseUrlController = TextEditingController(
      text: savedCredential?.baseUrl ?? settings.llmBaseUrl,
    );
    _apiKeyController = TextEditingController(
      text: savedCredential?.apiKey ?? settings.geminiApiKey,
    );
    _targetModelController = TextEditingController(text: settings.geminiModel);

    _savedProviderCredentials = savedCredentials;
    _selectedModel = settings.whisperModel;
    _sourceLanguage = settings.sourceVideoLanguage;
    _llmProvider = provider;
    _targetLanguage = settings.targetLanguage;
    _batchSize = settings.batchSize;
    _bilingual = settings.bilingual;
    _enableTranslation = settings.subtitleBatchEnableTranslation;
    _showOnlyUnprocessed = settings.subtitleBatchOnlyUnprocessed;
    _concurrency = settings.subtitleBatchConcurrency.clamp(1, 4);

    _selectedModel = _safeSelectedModel;
    _sourceLanguage = _safeSourceLanguage;
    _llmProvider = _safeProvider;
    _targetLanguage = _safeTargetLanguage;
    _batchSize = _safeBatchSize;

    if (_llmProvider != provider) {
      final ProviderCredential? normalizedSaved =
          savedCredentials[_llmProvider];
      _llmBaseUrlController.text =
          normalizedSaved?.baseUrl ??
          (defaultLlmBaseUrls[_llmProvider] ?? settings.llmBaseUrl);
      _apiKeyController.text = normalizedSaved?.apiKey ?? settings.geminiApiKey;
    }

    SubtitleBatchTaskManager.instance.setConcurrency(_concurrency);

    if (_inputRootController.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadRoot();
      });
    }
  }

  @override
  void dispose() {
    _inputRootController.dispose();
    _outputRootController.dispose();
    _searchController.dispose();
    _minMediaSizeController.dispose();
    _llmBaseUrlController.dispose();
    _apiKeyController.dispose();
    _targetModelController.dispose();
    super.dispose();
  }

  Future<void> _persistSettings() async {
    final SettingsService settings = widget.settingsService;
    await settings.setSubtitleBatchInputRoot(_inputRootController.text.trim());
    await settings.setSubtitleBatchOutputRoot(
      _outputRootController.text.trim(),
    );
    await settings.setSubtitleBatchConcurrency(_concurrency);
    await settings.setSubtitleBatchMinMediaSizeMB(_minMediaSizeMB);
    await settings.setSubtitleBatchOnlyUnprocessed(_showOnlyUnprocessed);
    await settings.setSubtitleBatchEnableTranslation(_enableTranslation);
    await settings.setWhisperModel(_selectedModel);
    await settings.setSourceVideoLanguage(_sourceLanguage);
    await settings.setLlmProvider(_llmProvider);
    await settings.setLlmBaseUrl(_llmBaseUrlController.text.trim());
    await settings.setGeminiApiKey(_apiKeyController.text.trim());
    await settings.setGeminiModel(_targetModelController.text.trim());
    await settings.setTargetLanguage(_targetLanguage);
    await settings.setBatchSize(_batchSize);
    await settings.setBilingual(_bilingual);
    if (_llmBaseUrlController.text.trim().isNotEmpty ||
        _apiKeyController.text.trim().isNotEmpty) {
      await settings.saveLlmProviderCredential(
        _llmProvider,
        ProviderCredential(
          baseUrl: _llmBaseUrlController.text.trim(),
          apiKey: _apiKeyController.text.trim(),
        ),
      );
    }
  }

  Future<void> _pickInputRoot() async {
    final String? picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择媒体目录',
    );
    if (picked == null || picked.trim().isEmpty) return;
    setState(() {
      _inputRootController.text = picked.trim();
      _selectedPaths.clear();
      _nodes.clear();
      _errorMessage = null;
    });
    if (_outputRootController.text.trim().isEmpty) {
      _outputRootController.text = picked.trim();
    }
    await _persistSettings();
    await _loadRoot();
  }

  Future<void> _pickOutputRoot() async {
    final String? picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择字幕输出目录',
    );
    if (picked == null || picked.trim().isEmpty) return;
    setState(() => _outputRootController.text = picked.trim());
    await _persistSettings();
  }

  Future<void> _loadRoot() async {
    final String inputRoot = _inputRootController.text.trim();
    if (inputRoot.isEmpty) {
      setState(() => _errorMessage = '请先选择本地媒体目录。');
      return;
    }
    final Directory rootDir = Directory(inputRoot);
    if (!await rootDir.exists()) {
      setState(() => _errorMessage = '目录不存在：$inputRoot');
      return;
    }

    setState(() {
      _loadingRoot = true;
      _errorMessage = null;
      _selectedPaths.clear();
      _nodes.clear();
    });
    try {
      final List<_LocalEntry> entries = await _listDirectory(inputRoot);
      if (!mounted) return;
      setState(() {
        _nodes.addAll(entries.map(_LocalNode.new));
      });
      await _persistSettings();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loadingRoot = false);
      }
    }
  }

  Future<List<_LocalEntry>> _listDirectory(String dirPath) async {
    final List<_LocalEntry> entries = <_LocalEntry>[];
    final Directory directory = Directory(dirPath);
    await for (final FileSystemEntity entity in directory.list(
      followLinks: false,
    )) {
      final String name = p.basename(entity.path);
      if (name.isEmpty || name.startsWith('.')) {
        continue;
      }
      if (entity is Directory) {
        entries.add(_LocalEntry.directory(path: entity.path, name: name));
        continue;
      }
      if (entity is! File) {
        continue;
      }
      final String extension = p
          .extension(name)
          .replaceFirst('.', '')
          .toLowerCase();
      if (!AppConstants.mediaExtensions.contains(extension)) {
        continue;
      }
      entries.add(
        _LocalEntry.file(
          path: entity.path,
          name: name,
          sizeBytes: await entity.length(),
        ),
      );
    }
    entries.sort((a, b) {
      if (a.isDir != b.isDir) {
        return a.isDir ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  Future<void> _toggleDir(_LocalNode node) async {
    if (!node.entry.isDir) return;
    setState(() => node.expanded = !node.expanded);
    if (!node.expanded || node.loaded || node.loading) {
      return;
    }
    await _loadChildren(node);
  }

  Future<void> _loadChildren(_LocalNode node) async {
    setState(() => node.loading = true);
    try {
      final List<_LocalEntry> entries = await _listDirectory(node.entry.path);
      if (!mounted) return;
      setState(() {
        node.children = entries.map(_LocalNode.new).toList();
        node.loaded = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) {
        setState(() => node.loading = false);
      }
    }
  }

  Future<void> _ensureDirLoadedDeep(_LocalNode node) async {
    if (!node.entry.isDir) return;
    if (!node.loaded && !node.loading) {
      await _loadChildren(node);
    }
    for (final _LocalNode child in node.children.where(
      (_LocalNode item) => item.entry.isDir,
    )) {
      await _ensureDirLoadedDeep(child);
    }
  }

  Future<void> _toggleSelection(_LocalNode node, bool selected) async {
    if (!node.entry.isDir) {
      if (!_matchesSelectableFile(node.entry)) {
        return;
      }
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
    final List<_LocalEntry> files = _collectFiles(<_LocalNode>[
      node,
    ]).where(_matchesSelectableFile).toList();
    if (!mounted) return;
    setState(() {
      for (final _LocalEntry file in files) {
        if (selected) {
          _selectedPaths.add(file.path);
        } else {
          _selectedPaths.remove(file.path);
        }
      }
    });
  }

  Future<void> _selectAllVisible() async {
    for (final _LocalNode node in _nodes.where(
      (_LocalNode item) => item.entry.isDir,
    )) {
      if (node.expanded) {
        await _ensureDirLoadedDeep(node);
      }
    }
    final List<_LocalEntry> files = _collectFiles(
      _nodes,
    ).where(_matchesVisibleFile).toList();
    setState(() {
      _selectedPaths.addAll(files.map((_LocalEntry file) => file.path));
    });
  }

  void _clearSelection() {
    setState(() => _selectedPaths.clear());
  }

  Future<void> _fetchModels() async {
    final String apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) return;
    setState(() => _isLoadingModels = true);
    try {
      final TranslationService service = TranslationService();
      final List<String> models = await service.listModels(
        TranslationConfig(
          providerId: _llmProvider,
          apiKey: apiKey,
          baseUrl: _llmBaseUrlController.text.trim(),
          sourceLanguage: _sourceLanguage,
          targetLanguage: _targetLanguage,
        ),
      );
      if (!mounted) return;
      setState(() {
        _availableModels = models;
        if (_availableModels.isNotEmpty &&
            !_availableModels.contains(_targetModelController.text.trim())) {
          _targetModelController.text = _availableModels.first;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = '获取模型失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isLoadingModels = false);
      }
    }
  }

  void _handleProviderChanged(String provider) {
    final ProviderCredential? saved = _savedProviderCredentials[provider];
    setState(() {
      _llmProvider = provider;
      _llmBaseUrlController.text =
          saved?.baseUrl ?? (defaultLlmBaseUrls[provider] ?? '');
      _apiKeyController.text = saved?.apiKey ?? '';
      _availableModels = <String>[];
      _errorMessage = null;
    });
  }

  List<_LocalEntry> _collectFiles(List<_LocalNode> nodes) {
    final List<_LocalEntry> files = <_LocalEntry>[];
    for (final _LocalNode node in nodes) {
      if (node.entry.isDir) {
        files.addAll(_collectFiles(node.children));
      } else {
        files.add(node.entry);
      }
    }
    return files;
  }

  bool _matchesSelectableFile(_LocalEntry entry) {
    if (entry.isDir) return true;
    if (_minMediaSizeMB > 0) {
      final int minBytes = _minMediaSizeMB * 1024 * 1024;
      if (entry.sizeBytes < minBytes) {
        return false;
      }
    }
    if (_showOnlyUnprocessed && _isProcessed(entry.path)) {
      return false;
    }
    return true;
  }

  bool _matchesVisibleFile(_LocalEntry entry) {
    if (!_matchesSelectableFile(entry)) {
      return false;
    }
    final String query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    final String relative = _relativePath(entry.path).toLowerCase();
    return entry.name.toLowerCase().contains(query) || relative.contains(query);
  }

  bool _shouldShowNode(_LocalNode node) {
    if (!node.entry.isDir) {
      return _matchesVisibleFile(node.entry);
    }

    final String query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    final String relative = _relativePath(node.entry.path).toLowerCase();
    if (node.entry.name.toLowerCase().contains(query) ||
        relative.contains(query)) {
      return true;
    }
    if (!node.loaded) {
      return false;
    }
    return node.children.any(_shouldShowNode);
  }

  _SelectionState _selectionStateForDir(_LocalNode node) {
    final List<_LocalEntry> files = _collectFiles(<_LocalNode>[
      node,
    ]).where(_matchesSelectableFile).toList();
    if (files.isEmpty) {
      return const _SelectionState(
        allSelected: false,
        partiallySelected: false,
      );
    }
    int selectedCount = 0;
    for (final _LocalEntry file in files) {
      if (_selectedPaths.contains(file.path)) {
        selectedCount++;
      }
    }
    return _SelectionState(
      allSelected: selectedCount == files.length,
      partiallySelected: selectedCount > 0 && selectedCount < files.length,
    );
  }

  bool _isProcessed(String mediaPath) {
    final String outputRoot = _outputRootController.text.trim();
    if (outputRoot.isEmpty) {
      return false;
    }
    final SubtitleBatchOutputPlan plan = buildSubtitleBatchOutputPlan(
      inputRoot: _inputRootController.text.trim(),
      mediaPath: mediaPath,
      outputRoot: outputRoot,
      enableTranslation: _enableTranslation,
      bilingual: _bilingual,
    );
    return File(plan.primaryOutputPath).existsSync();
  }

  String _relativePath(String path) {
    final String inputRoot = _inputRootController.text.trim();
    if (inputRoot.isEmpty) {
      return path;
    }
    return p.relative(path, from: inputRoot);
  }

  List<_LocalEntry> get _selectedFiles {
    final Map<String, _LocalEntry> fileMap = <String, _LocalEntry>{};
    for (final _LocalEntry file in _collectFiles(_nodes)) {
      fileMap[file.path] = file;
    }
    return _selectedPaths
        .map((String path) => fileMap[path])
        .whereType<_LocalEntry>()
        .toList()
      ..sort(
        (_LocalEntry a, _LocalEntry b) =>
            _relativePath(a.path).compareTo(_relativePath(b.path)),
      );
  }

  Future<void> _startBatch() async {
    final String inputRoot = _inputRootController.text.trim();
    final String outputRoot = _outputRootController.text.trim();
    if (inputRoot.isEmpty || outputRoot.isEmpty) {
      setState(() => _errorMessage = '请先选择输入目录和输出目录。');
      return;
    }
    final List<_LocalEntry> selectedFiles = _selectedFiles;
    if (selectedFiles.isEmpty) {
      setState(() => _errorMessage = '请先至少选择一个媒体文件。');
      return;
    }
    if (_enableTranslation) {
      if (_apiKeyController.text.trim().isEmpty ||
          _llmBaseUrlController.text.trim().isEmpty ||
          _targetModelController.text.trim().isEmpty) {
        setState(() => _errorMessage = '开启翻译时，请补全 Base URL、API Key 和模型。');
        return;
      }
    }

    final TranslationConfig? translationConfig = _enableTranslation
        ? TranslationConfig(
            providerId: _llmProvider,
            apiKey: _apiKeyController.text.trim(),
            baseUrl: _llmBaseUrlController.text.trim(),
            model: _targetModelController.text.trim(),
            sourceLanguage: _sourceLanguage,
            targetLanguage: _targetLanguage,
            batchSize: _batchSize,
          )
        : null;

    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final BuildContext navigatorContext = navigator.context;

    await _persistSettings();
    SubtitleBatchTaskManager.instance.setConcurrency(_concurrency);
    await SubtitleBatchTaskManager.instance.enqueueBatch(
      settingsService: widget.settingsService,
      inputRoot: inputRoot,
      outputRoot: outputRoot,
      modelName: _selectedModel,
      sourceLanguage: _sourceLanguage,
      enableTranslation: _enableTranslation,
      bilingual: _bilingual,
      translationConfig: translationConfig,
      files: selectedFiles
          .map(
            (_LocalEntry file) => SubtitleBatchSourceFile(
              path: file.path,
              relativePath: _relativePath(file.path),
              sizeBytes: file.sizeBytes,
            ),
          )
          .toList(),
    );

    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text('已将 ${selectedFiles.length} 个文件加入后台任务。'),
        action: SnackBarAction(
          label: '查看任务',
          onPressed: () => showBackgroundJobCenterDialog(
            navigatorContext,
            initialTab: BackgroundJobTab.subtitles,
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _inputRootController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: '媒体目录',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _pickInputRoot,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('选择目录'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _loadingRoot ? null : _loadRoot,
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
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _outputRootController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: '字幕输出目录',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _pickOutputRoot,
                icon: const Icon(Icons.save_alt_rounded),
                label: const Text('选择目录'),
              ),
            ],
          ),
          if (_inputRootController.text.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _inputRootController.text
                    .split(RegExp(r'[\\/]'))
                    .where((String item) => item.isNotEmpty)
                    .map(
                      (String item) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                        child: Text(item),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFileBrowserPanel(ThemeData theme) {
    final int loadedCount = _collectFiles(_nodes).length;
    final int visibleCount = _collectFiles(
      _nodes,
    ).where(_matchesVisibleFile).length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '目录树',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '已加载 $loadedCount 个，当前可见 $visibleCount 个，已选 ${_selectedPaths.length} 个',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.68),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    labelText: '搜索文件名或路径',
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                value: _showOnlyUnprocessed,
                onChanged: (bool value) async {
                  setState(() => _showOnlyUnprocessed = value);
                  await _persistSettings();
                },
              ),
              const Text('仅显示未处理'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              SizedBox(
                width: 190,
                child: TextField(
                  controller: _minMediaSizeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '屏蔽小于多少 MB',
                    isDense: true,
                  ),
                  onChanged: (String value) {
                    final int parsed = int.tryParse(value.trim()) ?? 0;
                    setState(() => _minMediaSizeMB = parsed < 0 ? 0 : parsed);
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _selectAllVisible,
                child: const Text('全选可见'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _clearSelection,
                child: const Text('清空选择'),
              ),
            ],
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
                        '请选择本地媒体目录，或当前目录没有可处理的媒体文件。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    )
                  : ListView(
                      children: _nodes
                          .where(_shouldShowNode)
                          .map((_LocalNode node) => _buildNodeRow(node, 0))
                          .toList(),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeRow(_LocalNode node, int depth) {
    final bool isDir = node.entry.isDir;
    final _SelectionState state = isDir
        ? _selectionStateForDir(node)
        : _SelectionState(
            allSelected: _selectedPaths.contains(node.entry.path),
            partiallySelected: false,
          );

    final Widget tile = Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: Column(
        children: <Widget>[
          ListTile(
            dense: true,
            leading: isDir
                ? IconButton(
                    onPressed: () => _toggleDir(node),
                    icon: Icon(
                      node.expanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.chevron_right_rounded,
                    ),
                  )
                : const SizedBox(
                    width: 40,
                    child: Icon(Icons.movie_creation_outlined),
                  ),
            title: Text(
              node.entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              isDir
                  ? _relativePath(node.entry.path)
                  : '${_relativePath(node.entry.path)}  |  ${(node.entry.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
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
      return tile;
    }

    final List<Widget> children = <Widget>[tile];
    for (final _LocalNode child in node.children.where(_shouldShowNode)) {
      children.add(_buildNodeRow(child, depth + 1));
    }
    return Column(children: children);
  }

  Widget _buildQueuePanel(ThemeData theme) {
    final List<_LocalEntry> selectedFiles = _selectedFiles;
    final String queueSummary = _enableTranslation
        ? '$_selectedModel · $_sourceLanguage -> $_targetLanguage'
        : '$_selectedModel · $_sourceLanguage · 仅识别原文';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '待处理队列',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '已选 ${selectedFiles.length} 个',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.68),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: selectedFiles.isEmpty
                  ? Center(
                      child: Text(
                        '在左侧勾选文件或文件夹后，这里会显示待处理队列。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: selectedFiles.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final _LocalEntry file = selectedFiles[index];
                        final SubtitleBatchOutputPlan outputPlan =
                            buildSubtitleBatchOutputPlan(
                              inputRoot: _inputRootController.text.trim(),
                              mediaPath: file.path,
                              outputRoot: _outputRootController.text.trim(),
                              enableTranslation: _enableTranslation,
                              bilingual: _bilingual,
                            );
                        return ListTile(
                          dense: true,
                          title: Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${_relativePath(file.path)}\n${(file.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB · 输出到 ${outputPlan.primaryOutputPath}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.66),
                              height: 1.35,
                            ),
                          ),
                          trailing: IconButton(
                            onPressed: () => setState(
                              () => _selectedPaths.remove(file.path),
                            ),
                            icon: const Icon(Icons.close_rounded),
                            tooltip: '移除',
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withValues(alpha: 0.04),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '已选 ${selectedFiles.length} 个文件',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  queueSummary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _startBatch,
                      icon: const Icon(Icons.rocket_launch_rounded),
                      label: const Text('加入后台任务'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => showBackgroundJobCenterDialog(
                        context,
                        initialTab: BackgroundJobTab.subtitles,
                      ),
                      icon: const Icon(Icons.bubble_chart_rounded),
                      label: const Text('查看任务中心'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigPanel(ThemeData theme) {
    final SubtitleBatchTaskManager manager = SubtitleBatchTaskManager.instance;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '批量配置',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _safeSelectedModel,
                          decoration: const InputDecoration(
                            labelText: 'Whisper 模型',
                            isDense: true,
                          ),
                          items: _whisperModelOptions
                              .map(
                                (String value) => DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                          onChanged: (String? value) {
                            if (value == null) return;
                            setState(() => _selectedModel = value);
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
                          items: <int>[1, 2, 3, 4]
                              .map(
                                (int value) => DropdownMenuItem<int>(
                                  value: value,
                                  child: Text('$value'),
                                ),
                              )
                              .toList(),
                          onChanged: (int? value) {
                            if (value == null) return;
                            setState(() => _concurrency = value);
                            manager.setConcurrency(value);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _safeSourceLanguage,
                    decoration: const InputDecoration(
                      labelText: '源媒体语言',
                      isDense: true,
                    ),
                    items: AppConstants.supportedLanguages.entries
                        .map(
                          (MapEntry<String, String> entry) =>
                              DropdownMenuItem<String>(
                                value: entry.key,
                                child: Text('${entry.value} (${entry.key})'),
                              ),
                        )
                        .toList(),
                    onChanged: (String? value) {
                      if (value == null) return;
                      setState(() => _sourceLanguage = value);
                    },
                  ),
                  const SizedBox(height: 14),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _enableTranslation,
                    onChanged: (bool value) =>
                        setState(() => _enableTranslation = value),
                    title: const Text('识别完成后自动翻译'),
                    subtitle: const Text('关闭后仅输出原文字幕'),
                  ),
                  if (_enableTranslation) ...<Widget>[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _safeProvider,
                      decoration: const InputDecoration(
                        labelText: '大模型服务商',
                        isDense: true,
                      ),
                      items: _providerOptions
                          .map(
                            (String provider) => DropdownMenuItem<String>(
                              value: provider,
                              child: Text(provider),
                            ),
                          )
                          .toList(),
                      onChanged: (String? value) {
                        if (value == null) return;
                        _handleProviderChanged(value);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _llmBaseUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Base URL',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _apiKeyController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'API Key',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _isLoadingModels ? null : _fetchModels,
                          child: Text(_isLoadingModels ? '检测中' : '检测模型'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_availableModels.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue:
                            _availableModels.contains(
                              _targetModelController.text.trim(),
                            )
                            ? _targetModelController.text.trim()
                            : _availableModels.first,
                        decoration: const InputDecoration(
                          labelText: '翻译模型',
                          isDense: true,
                        ),
                        items: _availableModels
                            .map(
                              (String model) => DropdownMenuItem<String>(
                                value: model,
                                child: Text(
                                  model,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (String? value) {
                          if (value == null) return;
                          setState(() => _targetModelController.text = value);
                        },
                      )
                    else
                      TextField(
                        controller: _targetModelController,
                        decoration: const InputDecoration(
                          labelText: '翻译模型',
                          hintText: '未检测到模型时可手动输入',
                          isDense: true,
                        ),
                      ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _safeTargetLanguage,
                      decoration: const InputDecoration(
                        labelText: '目标语言',
                        isDense: true,
                      ),
                      items: AppConstants.supportedLanguages.entries
                          .where(
                            (MapEntry<String, String> entry) =>
                                _targetLanguageOptions.contains(entry.key),
                          )
                          .map(
                            (MapEntry<String, String> entry) =>
                                DropdownMenuItem<String>(
                                  value: entry.key,
                                  child: Text('${entry.value} (${entry.key})'),
                                ),
                          )
                          .toList(),
                      onChanged: (String? value) {
                        if (value == null) return;
                        setState(() => _targetLanguage = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: _safeBatchSize,
                      decoration: const InputDecoration(
                        labelText: '每批字幕条数',
                        isDense: true,
                      ),
                      items: _batchSizeOptions
                          .map(
                            (int value) => DropdownMenuItem<int>(
                              value: value,
                              child: Text('$value'),
                            ),
                          )
                          .toList(),
                      onChanged: (int? value) {
                        if (value == null) return;
                        setState(() => _batchSize = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _bilingual,
                      onChanged: (bool value) =>
                          setState(() => _bilingual = value),
                      title: const Text('输出双语字幕'),
                      subtitle: const Text('关闭后输出纯译文字幕'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    '输出会保持原目录结构。已存在的输出文件可通过“仅显示未处理”开关过滤。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 10),
                  Text(
                    '后台预览',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedBuilder(
                    animation: manager,
                    builder: (BuildContext context, _) {
                      final List<SubtitleBatchTask> activeBatches = manager
                          .batches
                          .where(
                            (SubtitleBatchTask batch) =>
                                batch.status == SubtitleBatchStatus.queued ||
                                batch.status == SubtitleBatchStatus.running,
                          )
                          .toList();
                      if (activeBatches.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: Colors.white.withValues(alpha: 0.03),
                          ),
                          child: Text(
                            '当前没有进行中的批量字幕任务。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.68),
                            ),
                          ),
                        );
                      }
                      return Column(
                        children: activeBatches.map((SubtitleBatchTask batch) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: Colors.white.withValues(alpha: 0.03),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '${batch.items.length} 个文件 · 完成 ${batch.completedCount}/${batch.items.length}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                LinearProgressIndicator(value: batch.progress),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 1460,
        height: 860,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.subtitles_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '本地目录批量字幕',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showBackgroundJobCenterDialog(
                      context,
                      initialTab: BackgroundJobTab.subtitles,
                    ),
                    icon: const Icon(Icons.bubble_chart_rounded),
                    label: const Text('任务中心'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () async {
                      await _persistSettings();
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildToolbar(theme),
              if (_errorMessage != null) ...<Widget>[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(flex: 3, child: _buildFileBrowserPanel(theme)),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: _buildQueuePanel(theme)),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: _buildConfigPanel(theme)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalEntry {
  const _LocalEntry.directory({required this.path, required this.name})
    : isDir = true,
      sizeBytes = 0;

  const _LocalEntry.file({
    required this.path,
    required this.name,
    required this.sizeBytes,
  }) : isDir = false;

  final String path;
  final String name;
  final bool isDir;
  final int sizeBytes;
}

class _LocalNode {
  _LocalNode(this.entry);

  final _LocalEntry entry;
  bool expanded = false;
  bool loaded = false;
  bool loading = false;
  List<_LocalNode> children = <_LocalNode>[];
}

class _SelectionState {
  const _SelectionState({
    required this.allSelected,
    required this.partiallySelected,
  });

  final bool allSelected;
  final bool partiallySelected;
}
