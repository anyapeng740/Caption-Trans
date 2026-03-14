import '../../models/subtitle_segment.dart';

/// Utility for parsing and generating SRT subtitle files.
class SrtParser {
  SrtParser._();

  /// Parse SRT-formatted string into a list of [SubtitleSegment].
  static List<SubtitleSegment> parse(String srtContent) {
    final segments = <SubtitleSegment>[];
    final blocks = srtContent.trim().split(RegExp(r'\n\s*\n'));

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 3) continue;

      final index = int.tryParse(lines[0].trim());
      if (index == null) continue;

      final timeParts = lines[1].trim().split('-->');
      if (timeParts.length != 2) continue;

      final startTime = _parseDuration(timeParts[0].trim());
      final endTime = _parseDuration(timeParts[1].trim());
      if (startTime == null || endTime == null) continue;

      final text = lines.sublist(2).join('\n').trim();

      segments.add(SubtitleSegment(
        index: index,
        startTime: startTime,
        endTime: endTime,
        text: text,
      ));
    }

    return segments;
  }

  /// Generate SRT-formatted string from segments.
  ///
  /// If [useTranslation] is true, uses `translatedText` instead of `text`.
  /// If [bilingual] is true, outputs both original and translated text.
  static String generate(
    List<SubtitleSegment> segments, {
    bool useTranslation = false,
    bool bilingual = false,
  }) {
    final buffer = StringBuffer();

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      buffer.writeln(i + 1);
      buffer.writeln(
          '${_formatDuration(seg.startTime)} --> ${_formatDuration(seg.endTime)}');

      if (bilingual && seg.translatedText != null) {
        buffer.writeln(seg.text);
        buffer.writeln(seg.translatedText!);
      } else if (useTranslation && seg.translatedText != null) {
        buffer.writeln(seg.translatedText!);
      } else {
        buffer.writeln(seg.text);
      }

      if (i < segments.length - 1) {
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// Parse SRT timestamp format: HH:MM:SS,mmm
  static Duration? _parseDuration(String timestamp) {
    final regex = RegExp(r'(\d{2}):(\d{2}):(\d{2})[,.](\d{3})');
    final match = regex.firstMatch(timestamp);
    if (match == null) return null;

    return Duration(
      hours: int.parse(match.group(1)!),
      minutes: int.parse(match.group(2)!),
      seconds: int.parse(match.group(3)!),
      milliseconds: int.parse(match.group(4)!),
    );
  }

  /// Format duration as SRT timestamp: HH:MM:SS,mmm
  static String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    final millis = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$hours:$minutes:$seconds,$millis';
  }
}
