import 'package:caption_trans/services/alist/alist_audio_convert_service.dart';
import 'package:caption_trans/services/alist/alist_audio_task_manager.dart';
import 'package:flutter/material.dart';

Future<void> showAListAudioTaskCenterDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _AListAudioTaskCenterDialog(),
  );
}

class _AListAudioTaskCenterDialog extends StatelessWidget {
  const _AListAudioTaskCenterDialog();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 980,
        height: 720,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.bubble_chart_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '后台任务',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
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
              const Expanded(child: AListAudioTaskCenterPanel()),
            ],
          ),
        ),
      ),
    );
  }
}

class AListAudioTaskCenterPanel extends StatelessWidget {
  const AListAudioTaskCenterPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final AListAudioTaskManager manager = AListAudioTaskManager.instance;
    final ThemeData theme = Theme.of(context);

    return AnimatedBuilder(
      animation: manager,
      builder: (BuildContext context, _) {
        final List<AListAudioBatchTask> batches = manager.batches;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Text(
                  'AList 转音频任务',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
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
                    '当前没有音频转换任务。',
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
                    final AListAudioBatchTask batch = batches[index];
                    return _BatchCard(batch: batch, manager: manager);
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BatchCard extends StatelessWidget {
  const _BatchCard({required this.batch, required this.manager});

  final AListAudioBatchTask batch;
  final AListAudioTaskManager manager;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String statusText = switch (batch.status) {
      AListAudioBatchStatus.queued => '排队中',
      AListAudioBatchStatus.running => '执行中',
      AListAudioBatchStatus.completed => '已完成',
      AListAudioBatchStatus.canceled => '已取消',
      AListAudioBatchStatus.failed => '有失败',
    };
    final Color statusColor = switch (batch.status) {
      AListAudioBatchStatus.queued => Colors.white70,
      AListAudioBatchStatus.running => Colors.lightBlueAccent,
      AListAudioBatchStatus.completed => Colors.greenAccent,
      AListAudioBatchStatus.canceled => Colors.orangeAccent,
      AListAudioBatchStatus.failed => Colors.redAccent,
    };

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
                  '${batch.items.length} 个文件 · ${batch.outputDir}',
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
            '格式 ${batch.format.displayName} · 并发 ${batch.concurrency} · 完成 ${batch.completedCount}/${batch.items.length} · 失败 ${batch.failedCount} · 取消 ${batch.canceledCount}',
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
              if (batch.status == AListAudioBatchStatus.running ||
                  batch.status == AListAudioBatchStatus.queued)
                FilledButton.tonal(
                  onPressed: () => manager.cancelBatch(batch.id),
                  child: Text(batch.cancelRequested ? '停止中...' : '取消任务'),
                ),
              if (batch.status == AListAudioBatchStatus.completed ||
                  batch.status == AListAudioBatchStatus.canceled ||
                  batch.status == AListAudioBatchStatus.failed) ...<Widget>[
                FilledButton.tonal(
                  onPressed: () => manager.removeBatch(batch.id),
                  child: const Text('移除'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          ...batch.items.map(
            (AListAudioTaskItem item) => _TaskItemRow(item: item),
          ),
        ],
      ),
    );
  }
}

class _TaskItemRow extends StatelessWidget {
  const _TaskItemRow({required this.item});

  final AListAudioTaskItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String statusText = switch (item.status) {
      AListAudioTaskStatus.queued => '排队中',
      AListAudioTaskStatus.running => '转换中',
      AListAudioTaskStatus.completed => '已完成',
      AListAudioTaskStatus.canceled => '已取消',
      AListAudioTaskStatus.failed => '失败',
    };
    final Color statusColor = switch (item.status) {
      AListAudioTaskStatus.queued => Colors.white70,
      AListAudioTaskStatus.running => Colors.lightBlueAccent,
      AListAudioTaskStatus.completed => Colors.greenAccent,
      AListAudioTaskStatus.canceled => Colors.orangeAccent,
      AListAudioTaskStatus.failed => Colors.redAccent,
    };
    final double progressValue = switch (item.status) {
      AListAudioTaskStatus.queued => 0,
      AListAudioTaskStatus.running => item.progress ?? 0,
      AListAudioTaskStatus.completed => 1,
      AListAudioTaskStatus.canceled => item.progress ?? 1,
      AListAudioTaskStatus.failed => item.progress ?? 1,
    };

    final List<String> meta = <String>[statusText];
    if (item.progress != null) {
      meta.add('进度 ${(item.progress! * 100).toStringAsFixed(1)}%');
    }
    if (item.mediaDuration != null) {
      meta.add(
        '${_formatDuration(item.currentPosition ?? Duration.zero)} / ${_formatDuration(item.mediaDuration!)}',
      );
    }
    if (item.elapsed != null) {
      meta.add('已耗时 ${_formatDuration(item.elapsed!)}');
    }
    if (item.eta != null) {
      meta.add('预计剩余 ${_formatDuration(item.eta!)}');
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Colors.white.withValues(alpha: 0.03),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    item.remotePath,
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
            const SizedBox(height: 4),
            Text(
              meta.join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progressValue,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            if ((item.message ?? item.outputPath)?.trim().isNotEmpty ==
                true) ...[
              const SizedBox(height: 6),
              Text(
                item.message ?? item.outputPath!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.58),
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
