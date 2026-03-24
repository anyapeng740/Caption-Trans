import 'package:flutter/material.dart';

import '../../services/alist/alist_audio_task_manager.dart';
import '../../services/subtitle/subtitle_batch_task_manager.dart';
import 'alist_audio_task_center_dialog.dart';
import 'subtitle_task_center_panel.dart';

enum BackgroundJobTab { subtitles, audio }

Future<void> showBackgroundJobCenterDialog(
  BuildContext context, {
  BackgroundJobTab initialTab = BackgroundJobTab.subtitles,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _BackgroundJobCenterDialog(initialTab: initialTab),
  );
}

class _BackgroundJobCenterDialog extends StatelessWidget {
  const _BackgroundJobCenterDialog({required this.initialTab});

  final BackgroundJobTab initialTab;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Listenable merged = Listenable.merge(<Listenable>[
      SubtitleBatchTaskManager.instance,
      AListAudioTaskManager.instance,
    ]);

    return AnimatedBuilder(
      animation: merged,
      builder: (BuildContext context, _) {
        final int subtitleCount =
            SubtitleBatchTaskManager.instance.batches.length;
        final int audioCount = AListAudioTaskManager.instance.batches.length;

        return DefaultTabController(
          length: 2,
          initialIndex: initialTab == BackgroundJobTab.subtitles ? 0 : 1,
          child: Dialog(
            insetPadding: const EdgeInsets.all(20),
            child: SizedBox(
              width: 1120,
              height: 780,
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
                            '后台任务中心',
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
                    TabBar(
                      tabs: <Widget>[
                        Tab(text: '批量字幕 ($subtitleCount)'),
                        Tab(text: 'AList 转音频 ($audioCount)'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Expanded(
                      child: TabBarView(
                        children: <Widget>[
                          SubtitleTaskCenterPanel(),
                          AListAudioTaskCenterPanel(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
