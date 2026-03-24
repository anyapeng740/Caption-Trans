import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/alist/alist_upload_service.dart';
import '../../services/settings_service.dart';
import '../../services/subtitle/subtitle_batch_task_manager.dart';

Future<void> showSubtitleBatchPreviewDialog(
  BuildContext context, {
  required SubtitleBatchTask batch,
  String? initialItemId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        _SubtitleBatchPreviewDialog(batch: batch, initialItemId: initialItemId),
  );
}

class _SubtitleBatchPreviewDialog extends StatefulWidget {
  const _SubtitleBatchPreviewDialog({required this.batch, this.initialItemId});

  final SubtitleBatchTask batch;
  final String? initialItemId;

  @override
  State<_SubtitleBatchPreviewDialog> createState() =>
      _SubtitleBatchPreviewDialogState();
}

class _SubtitleBatchPreviewDialogState
    extends State<_SubtitleBatchPreviewDialog> {
  String? _selectedItemId;
  String? _selectedOutputPath;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final SubtitleBatchTaskItem? initialItem = _resolveInitialItem(
      widget.batch,
      widget.initialItemId,
    );
    _selectedItemId = initialItem?.id;
    _selectedOutputPath = initialItem?.outputPaths.isNotEmpty == true
        ? initialItem!.outputPaths.first
        : null;
  }

  SubtitleBatchTaskItem? get _selectedItem {
    final String? selectedItemId = _selectedItemId;
    if (selectedItemId == null) {
      return null;
    }
    for (final SubtitleBatchTaskItem item in widget.batch.items) {
      if (item.id == selectedItemId) {
        return item;
      }
    }
    return null;
  }

  Future<void> _uploadCurrentSelectedSrt(String selectedPath) async {
    if (selectedPath.trim().isEmpty) {
      return;
    }

    final SettingsService settings = widget.batch.settingsService;
    final String savedBaseUrl = settings.alistBaseUrl.trim();
    final String savedUsername = settings.alistUsername.trim();
    final String savedPassword = settings.alistPassword;
    if (savedBaseUrl.isEmpty || savedUsername.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先填写 AList 地址和用户名。'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final TextEditingController controller = TextEditingController(
      text: settings.alistUploadRemoteBase,
    );
    final String? remoteBaseInput = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('上传到 AList'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '远端基准目录（示例：/115/nana/98tang/日本vr）',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '/115/nana',
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('上传'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (!mounted || remoteBaseInput == null || remoteBaseInput.trim().isEmpty) {
      return;
    }

    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await settings.setAListUploadRemoteBase(remoteBaseInput.trim());

    if (!mounted) return;
    setState(() => _uploading = true);
    showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('正在上传 ${p.basename(selectedPath)} 到 AList...'),
            ),
          ],
        ),
      ),
    );

    final AListUploadService uploadService = AListUploadService();
    try {
      final List<String> uploaded = await uploadService.uploadLocalFiles(
        baseUrl: savedBaseUrl,
        username: savedUsername,
        password: savedPassword,
        localRoot: widget.batch.outputRoot,
        remoteBase: remoteBaseInput.trim(),
        localPaths: <String>[selectedPath],
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('已上传到 AList：${uploaded.first}'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('上传到 AList 失败：$error'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      uploadService.dispose();
      if (navigator.canPop()) {
        navigator.pop();
      }
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<SubtitleBatchTaskItem> previewableItems = widget.batch.items
        .where(
          (SubtitleBatchTaskItem item) =>
              item.outputPaths.isNotEmpty ||
              item.phase == SubtitleTaskPhase.completed,
        )
        .toList();

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 1180,
        height: 780,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.preview_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '批量字幕结果预览',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 320,
                      child: _buildFileList(theme, previewableItems),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _buildPreview(theme)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileList(
    ThemeData theme,
    List<SubtitleBatchTaskItem> previewableItems,
  ) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: previewableItems.isEmpty
          ? Center(
              child: Text(
                '当前还没有可预览的字幕文件。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.62),
                ),
                textAlign: TextAlign.center,
              ),
            )
          : ListView.separated(
              itemCount: previewableItems.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              itemBuilder: (BuildContext context, int index) {
                final SubtitleBatchTaskItem item = previewableItems[index];
                final bool selected = item.id == _selectedItemId;
                return Material(
                  color: selected
                      ? Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.12)
                      : Colors.transparent,
                  child: ListTile(
                    dense: true,
                    selected: selected,
                    onTap: () {
                      setState(() {
                        _selectedItemId = item.id;
                        _selectedOutputPath = item.outputPaths.isNotEmpty
                            ? item.outputPaths.first
                            : null;
                      });
                    },
                    title: Text(
                      p.basename(item.filePath),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      item.relativePath,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.62),
                      ),
                    ),
                    trailing: Text(
                      subtitleTaskPhaseLabel(item.phase),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: item.phase == SubtitleTaskPhase.completed
                            ? Colors.greenAccent
                            : Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    final SubtitleBatchTaskItem? selectedItem = _selectedItem;
    if (selectedItem == null || selectedItem.outputPaths.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Center(
          child: Text(
            '左侧选择一个已生成字幕的文件后，可以在这里预览原文或译文。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.62),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final List<String> existingOutputPaths = selectedItem.outputPaths
        .where((String path) => File(path).existsSync())
        .toList();
    if (existingOutputPaths.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Center(
          child: Text(
            '字幕文件不存在，可能已被移动或删除。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.62),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final String selectedOutputPath =
        existingOutputPaths.contains(_selectedOutputPath)
        ? _selectedOutputPath!
        : existingOutputPaths.first;

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
              Expanded(
                child: Text(
                  p.basename(selectedItem.filePath),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _uploading
                    ? null
                    : () => _uploadCurrentSelectedSrt(selectedOutputPath),
                icon: const Icon(Icons.cloud_upload_rounded),
                label: const Text('上传当前已选 SRT 到 AList'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            selectedItem.relativePath,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.64),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: existingOutputPaths.map((String path) {
              final bool selected = path == selectedOutputPath;
              return ChoiceChip(
                label: Text(_labelForOutputPath(path)),
                selected: selected,
                onSelected: (_) => setState(() => _selectedOutputPath = path),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Text(
            selectedOutputPath,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Colors.black.withValues(alpha: 0.16),
              ),
              child: FutureBuilder<String>(
                future: File(selectedOutputPath).readAsString(),
                key: ValueKey<String>(selectedOutputPath),
                builder:
                    (BuildContext context, AsyncSnapshot<String> snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            '读取字幕失败：${snapshot.error}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        );
                      }
                      final String content = snapshot.data ?? '';
                      return Scrollbar(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            content,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.45,
                              color: Colors.white.withValues(alpha: 0.82),
                            ),
                          ),
                        ),
                      );
                    },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

SubtitleBatchTaskItem? _resolveInitialItem(
  SubtitleBatchTask batch,
  String? initialItemId,
) {
  if (initialItemId != null) {
    for (final SubtitleBatchTaskItem item in batch.items) {
      if (item.id == initialItemId && item.outputPaths.isNotEmpty) {
        return item;
      }
    }
  }
  for (final SubtitleBatchTaskItem item in batch.items) {
    if (item.outputPaths.isNotEmpty) {
      return item;
    }
  }
  return null;
}

String _labelForOutputPath(String path) {
  final String lower = p.basename(path).toLowerCase();
  if (lower.endsWith('.bilingual.srt')) {
    return '双语字幕';
  }
  if (lower.endsWith('.translated.srt')) {
    return '译文字幕';
  }
  return '原文字幕';
}
