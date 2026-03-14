import 'package:equatable/equatable.dart';

/// A single subtitle segment with timing and text content.
class SubtitleSegment extends Equatable {
  final int index;
  final Duration startTime;
  final Duration endTime;
  final String text;
  final String? translatedText;

  const SubtitleSegment({
    required this.index,
    required this.startTime,
    required this.endTime,
    required this.text,
    this.translatedText,
  });

  SubtitleSegment copyWith({
    int? index,
    Duration? startTime,
    Duration? endTime,
    String? text,
    String? translatedText,
  }) {
    return SubtitleSegment(
      index: index ?? this.index,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      text: text ?? this.text,
      translatedText: translatedText ?? this.translatedText,
    );
  }

  @override
  List<Object?> get props => [index, startTime, endTime, text, translatedText];

  @override
  String toString() =>
      'SubtitleSegment($index, ${_formatDuration(startTime)} --> ${_formatDuration(endTime)}, "$text")';

  static String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    final millis = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$hours:$minutes:$seconds,$millis';
  }
}
