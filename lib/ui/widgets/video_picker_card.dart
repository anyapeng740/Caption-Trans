import 'package:flutter/material.dart';
import 'package:caption_trans/l10n/app_localizations.dart';

/// Card for selecting a media file with drag-and-drop style UI.
class VideoPickerCard extends StatelessWidget {
  static const double _desktopCardHeight = 175;

  final String? selectedFileName;
  final VoidCallback onPickVideo;
  final VoidCallback? onClear;

  const VideoPickerCard({
    super.key,
    this.selectedFileName,
    required this.onPickVideo,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasFile = selectedFileName != null;
    final theme = Theme.of(context);
    final platform = theme.platform;
    final isMobilePlatform =
        platform == TargetPlatform.iOS || platform == TargetPlatform.android;

    return Card(
      margin: EdgeInsets.zero,
      child: SizedBox(
        width: double.infinity,
        height: isMobilePlatform
            ? null
            : _desktopCardHeight,
        child: InkWell(
          onTap: onPickVideo,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: hasFile
                  ? _buildSelectedState(context, theme)
                  : _buildEmptyState(context, theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.upload_file_outlined,
            size: 15,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.clickToSelectVideo,
          style: theme.textTheme.titleSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.supportedFormats,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedState(BuildContext context, ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.perm_media_rounded,
            color: Colors.greenAccent,
            size: 24,
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                selectedFileName!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                l10n.videoSelected,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.greenAccent.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        if (onClear != null)
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: onClear,
            tooltip: l10n.clear,
          ),
        IconButton(
          icon: const Icon(Icons.folder_open_rounded),
          onPressed: onPickVideo,
          tooltip: l10n.changeFile,
        ),
      ],
    );
  }
}
