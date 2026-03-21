import 'package:equatable/equatable.dart';

const Object _translatedTextNotSet = Object();

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
    Object? translatedText = _translatedTextNotSet,
  }) {
    return SubtitleSegment(
      index: index ?? this.index,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      text: text ?? this.text,
      translatedText: identical(translatedText, _translatedTextNotSet)
          ? this.translatedText
          : translatedText as String?,
    );
  }

  factory SubtitleSegment.fromJson(Map<String, dynamic> json) {
    return SubtitleSegment(
      index: json['index'] as int,
      startTime: Duration(milliseconds: json['startTimeMs'] as int),
      endTime: Duration(milliseconds: json['endTimeMs'] as int),
      text: json['text'] as String,
      translatedText: json['translatedText'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'startTimeMs': startTime.inMilliseconds,
      'endTimeMs': endTime.inMilliseconds,
      'text': text,
      'translatedText': translatedText,
    };
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
