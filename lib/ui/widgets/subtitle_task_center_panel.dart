import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/subtitle/subtitle_batch_task_manager.dart';
import 'subtitle_batch_preview_dialog.dart';

class SubtitleTaskCenterPanel extends StatelessWidget {
  const SubtitleTaskCenterPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SubtitleBatchTaskManager manager = SubtitleBatchTaskManager.instance;

    return AnimatedBuilder(
      animation: manager,
      builder: (BuildContext context, _) {
        final List<SubtitleBatchTask> batches = manager.batches;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Text(
                  '批量字幕任务',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  onPressed: manager.concurrency > 1
                      ? () => manager.setConcurrency(manager.concurrency - 1)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  tooltip: '降低并发',
                ),
                Text('并发 ${manager.concurrency}'),
                IconButton(
                  onPressed: manager.concurrency < 4
                      ? () => manager.setConcurrency(manager.concurrency + 1)
                      : null,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  tooltip: '提高并发',
                ),
                const SizedBox(width: 8),
                if (batches.isNotEmpty)
                  TextButton(
                    onPressed: manager.clearFinished,
                    child: const Text('清理已完成'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (batches.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    '当前没有批量字幕任务。',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: batches.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (BuildContext context, int index) {
                    final SubtitleBatchTask batch = batches[index];
                    return _SubtitleBatchCard(batch: batch, manager: manager);
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SubtitleBatchCard extends StatelessWidget {
  const _SubtitleBatchCard({required this.batch, required this.manager});

  final SubtitleBatchTask batch;
  final SubtitleBatchTaskManager manager;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String statusText = subtitleBatchStatusLabel(batch.status);
    final Color statusColor = switch (batch.status) {
      SubtitleBatchStatus.queued => Colors.white70,
      SubtitleBatchStatus.running => Colors.lightBlueAccent,
      SubtitleBatchStatus.completed => Colors.greenAccent,
      SubtitleBatchStatus.canceled => Colors.orangeAccent,
      SubtitleBatchStatus.failed => Colors.redAccent,
    };

    final String subtitleLanguage = batch.enableTranslation
        ? '${batch.sourceLanguage} -> ${batch.translationConfig?.targetLanguage ?? ''}'
        : batch.sourceLanguage;
    final bool hasPreviewableOutput = batch.items.any(
      (SubtitleBatchTaskItem item) => item.outputPaths.isNotEmpty,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${batch.items.length} 个文件 · ${batch.modelName} · $subtitleLanguage',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '输入 ${batch.inputRoot} · 输出 ${batch.outputRoot} · 完成 ${batch.completedCount}/${batch.items.length} · 失败 ${batch.failedCount} · 取消 ${batch.canceledCount}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          if (batch.elapsed != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '已耗时 ${_formatDuration(batch.elapsed!)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.65),
              ),
            ),
          ],
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: batch.progress,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              if (hasPreviewableOutput)
                OutlinedButton.icon(
                  onPressed: () =>
                      showSubtitleBatchPreviewDialog(context, batch: batch),
                  icon: const Icon(Icons.preview_rounded),
                  label: const Text('结果预览'),
                ),
              if (hasPreviewableOutput) const SizedBox(width: 8),
              if (batch.status == SubtitleBatchStatus.running ||
                  batch.status == SubtitleBatchStatus.queued)
                FilledButton.tonal(
                  onPressed: () => manager.cancelBatch(batch.id),
                  child: Text(batch.cancelRequested ? '停止中...' : '取消任务'),
                ),
              if (batch.status == SubtitleBatchStatus.completed ||
                  batch.status == SubtitleBatchStatus.canceled ||
                  batch.status == SubtitleBatchStatus.failed)
                FilledButton.tonal(
                  onPressed: () => manager.removeBatch(batch.id),
                  child: const Text('移除'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ...batch.items.map(
            (SubtitleBatchTaskItem item) => _SubtitleTaskItemRow(item: item),
          ),
        ],
      ),
    );
  }
}

class _SubtitleTaskItemRow extends StatelessWidget {
  const _SubtitleTaskItemRow({required this.item});

  final SubtitleBatchTaskItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String statusText = subtitleTaskPhaseLabel(item.phase);
    final Color statusColor = switch (item.phase) {
      SubtitleTaskPhase.queued => Colors.white70,
      SubtitleTaskPhase.preparingRuntime => Colors.lightBlueAccent,
      SubtitleTaskPhase.transcoding => Colors.orangeAccent,
      SubtitleTaskPhase.transcribing => Colors.cyanAccent,
      SubtitleTaskPhase.translating => Colors.deepPurpleAccent,
      SubtitleTaskPhase.exporting => Colors.amberAccent,
      SubtitleTaskPhase.completed => Colors.greenAccent,
      SubtitleTaskPhase.canceled => Colors.orangeAccent,
      SubtitleTaskPhase.failed => Colors.redAccent,
    };

    final List<String> meta = <String>[
      statusText,
      '进度 ${(item.progress * 100).toStringAsFixed(1)}%',
      '${(item.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
      if (item.elapsed != null) '已耗时 ${_formatDuration(item.elapsed!)}',
      if (item.eta != null) '预计剩余 ${_formatDuration(item.eta!)}',
    ];

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withValues(alpha: 0.03),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          title: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  p.basename(item.filePath),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 4),
              Text(
                item.relativePath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                meta.join('  ·  '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: item.phase == SubtitleTaskPhase.queued
                      ? 0
                      : item.progress.clamp(0, 1),
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ],
          ),
          children: <Widget>[
            if ((item.message ?? '').trim().isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  item.message!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.76),
                  ),
                ),
              ),
            if (item.outputPaths.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              ...item.outputPaths.map(
                (String path) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    path,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.greenAccent.withValues(alpha: 0.82),
                    ),
                  ),
                ),
              ),
            ],
            if (item.logs.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.black.withValues(alpha: 0.18),
                ),
                child: SelectableText(
                  item.logs.join('\n'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.45,
                    color: Colors.white.withValues(alpha: 0.74),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration value) {
  final int totalSeconds = value.inSeconds;
  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
