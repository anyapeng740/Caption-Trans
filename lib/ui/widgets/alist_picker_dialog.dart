import 'package:caption_trans/services/alist/alist_service.dart';
import 'package:caption_trans/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class AListPickResult {
  final String localPath;
  final String remotePath;
  final String baseUrl;
  final String username;
  final String password;
  final String browsePath;

  const AListPickResult({
    required this.localPath,
    required this.remotePath,
    required this.baseUrl,
    required this.username,
    required this.password,
    required this.browsePath,
  });
}

Future<AListPickResult?> showAListPickerDialog(
  BuildContext context, {
  required String initialBaseUrl,
  required String initialUsername,
  required String initialPassword,
  required String initialBrowsePath,
  required SettingsService settingsService,
}) {
  return showDialog<AListPickResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AListPickerDialog(
      initialBaseUrl: initialBaseUrl,
      initialUsername: initialUsername,
      initialPassword: initialPassword,
      initialBrowsePath: initialBrowsePath,
      settingsService: settingsService,
    ),
  );
}

class _AListPickerDialog extends StatefulWidget {
  final String initialBaseUrl;
  final String initialUsername;
  final String initialPassword;
  final String initialBrowsePath;
  final SettingsService settingsService;

  const _AListPickerDialog({
    required this.initialBaseUrl,
    required this.initialUsername,
    required this.initialPassword,
    required this.initialBrowsePath,
    required this.settingsService,
  });

  @override
  State<_AListPickerDialog> createState() => _AListPickerDialogState();
}

class _AListPickerDialogState extends State<_AListPickerDialog> {
  final AListService _service = AListService();
  late final TextEditingController _baseUrlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _pathController;

  bool _connecting = false;
  bool _loading = false;
  bool _downloading = false;
  int _downloadReceived = 0;
  int _downloadTotal = -1;

  String? _token;
  String _currentPath = '/';
  String? _errorMessage;
  List<AListEntry> _entries = const <AListEntry>[];

  Future<void> _persistSettings() async {
    final String browsePath = _pathController.text.trim().isEmpty
        ? '/'
        : _service.normalizePath(_pathController.text);
    await widget.settingsService.setAListBaseUrl(
      _baseUrlController.text.trim(),
    );
    await widget.settingsService.setAListUsername(
      _usernameController.text.trim(),
    );
    await widget.settingsService.setAListPassword(_passwordController.text);
    await widget.settingsService.setAListBrowsePath(browsePath);
  }

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: widget.initialBaseUrl);
    _usernameController = TextEditingController(text: widget.initialUsername);
    _passwordController = TextEditingController(text: widget.initialPassword);
    _pathController = TextEditingController(
      text: widget.initialBrowsePath.trim().isEmpty
          ? '/'
          : widget.initialBrowsePath.trim(),
    );
  }

  @override
  void dispose() {
    _service.dispose();
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _connectAndLoad() async {
    if (_connecting || _loading || _downloading) return;
    setState(() {
      _connecting = true;
      _errorMessage = null;
    });

    try {
      await _persistSettings();
      final AListTarget target = _service.normalizeBaseUrl(
        _baseUrlController.text,
      );
      final String browsePath = _pathController.text.trim().isEmpty
          ? target.suggestedPath
          : _service.normalizePath(_pathController.text);
      final String token = await _service.login(
        baseUrl: target.baseUrl,
        username: _usernameController.text,
        password: _passwordController.text,
      );

      if (!mounted) return;
      setState(() {
        _token = token;
        _baseUrlController.text = target.baseUrl;
        _currentPath = browsePath;
        _pathController.text = browsePath;
      });
      await _loadPath(browsePath);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _connecting = false;
        });
      }
    }
  }

  Future<void> _loadPath(String path) async {
    final String? token = _token;
    if (token == null || token.isEmpty) {
      setState(() {
        _errorMessage = '请先连接 AList。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final String normalizedPath = _service.normalizePath(path);
      final List<AListEntry> list = await _service.list(
        baseUrl: _baseUrlController.text.trim(),
        token: token,
        remotePath: normalizedPath,
      );
      if (!mounted) return;
      setState(() {
        _entries = list;
        _currentPath = normalizedPath;
        _pathController.text = normalizedPath;
      });
      await _persistSettings();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openEntry(AListEntry entry) async {
    if (_loading || _downloading || _connecting) return;
    if (entry.isDir) {
      await _loadPath(entry.path);
      return;
    }

    setState(() {
      _downloading = true;
      _downloadReceived = 0;
      _downloadTotal = -1;
      _errorMessage = null;
    });

    try {
      final String localPath = await _service.downloadToTemp(
        baseUrl: _baseUrlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        remotePath: entry.path,
        onProgress: (int received, int total) {
          if (!mounted) return;
          setState(() {
            _downloadReceived = received;
            _downloadTotal = total;
          });
        },
      );
      if (!mounted) return;
      await _persistSettings();
      if (!mounted) return;
      Navigator.of(context).pop(
        AListPickResult(
          localPath: localPath,
          remotePath: entry.path,
          baseUrl: _baseUrlController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          browsePath: _currentPath,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
        });
      }
    }
  }

  void _goParent() {
    final String parent = _currentPath == '/'
        ? '/'
        : _service.normalizePath(p.posix.dirname(_currentPath));
    _loadPath(parent);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool busy = _connecting || _loading || _downloading;
    final double? progressValue = _downloadTotal > 0
        ? (_downloadReceived / _downloadTotal).clamp(0.0, 1.0)
        : null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.cloud_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '从 AList 选择媒体',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: busy
                        ? null
                        : () async {
                            await _persistSettings();
                            if (!context.mounted) return;
                            Navigator.of(context).pop();
                          },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildFieldRow(
                label: 'AList 地址',
                child: TextField(
                  controller: _baseUrlController,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    hintText:
                        'http://127.0.0.1:5244 或 http://host/alist/dav/115',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _buildFieldRow(
                      label: '用户名',
                      child: TextField(
                        controller: _usernameController,
                        enabled: !busy,
                        decoration: const InputDecoration(isDense: true),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildFieldRow(
                      label: '密码',
                      child: TextField(
                        controller: _passwordController,
                        enabled: !busy,
                        obscureText: true,
                        decoration: const InputDecoration(isDense: true),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _buildFieldRow(
                      label: '浏览路径',
                      child: TextField(
                        controller: _pathController,
                        enabled: !busy,
                        decoration: const InputDecoration(
                          hintText: '/115/nana',
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: busy ? null : _connectAndLoad,
                    icon: _connecting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link_rounded),
                    label: const Text('连接'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: busy ? null : _goParent,
                    icon: const Icon(Icons.arrow_upward_rounded),
                    label: const Text('上一级'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => _loadPath(_pathController.text),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('刷新'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _currentPath,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              if (_downloading) ...<Widget>[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progressValue),
                const SizedBox(height: 4),
                Text(
                  _downloadTotal > 0
                      ? '下载中... ${((_downloadReceived / _downloadTotal) * 100).toStringAsFixed(1)}%'
                      : '下载中...',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_errorMessage != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _entries.isEmpty
                      ? const Center(
                          child: Text(
                            '当前目录没有媒体文件。',
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _entries.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          itemBuilder: (BuildContext context, int index) {
                            final AListEntry entry = _entries[index];
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                entry.isDir
                                    ? Icons.folder_rounded
                                    : Icons.perm_media_rounded,
                                color: entry.isDir
                                    ? Colors.amberAccent
                                    : theme.colorScheme.primary,
                              ),
                              title: Text(
                                entry.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                entry.path,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.55),
                                ),
                              ),
                              trailing: Icon(
                                entry.isDir
                                    ? Icons.chevron_right_rounded
                                    : Icons.download_rounded,
                              ),
                              onTap: busy ? null : () => _openEntry(entry),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFieldRow({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}
