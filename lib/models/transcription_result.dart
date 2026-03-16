import 'package:equatable/equatable.dart';
import 'subtitle_segment.dart';

/// Result of a Whisper transcription operation.
class TranscriptionResult extends Equatable {
  /// The detected or specified language of the audio.
  final String language;

  /// Total duration of the audio.
  final Duration duration;

  /// All subtitle segments with timestamps.
  final List<SubtitleSegment> segments;

  /// Whether GPU acceleration was used.
  final bool? isGpu;

  /// Time taken for transcription in milliseconds.
  final int? timingMs;

  const TranscriptionResult({
    required this.language,
    required this.duration,
    required this.segments,
    this.isGpu,
    this.timingMs,
  });

  TranscriptionResult copyWith({
    String? language,
    Duration? duration,
    List<SubtitleSegment>? segments,
    bool? isGpu,
    int? timingMs,
  }) {
    return TranscriptionResult(
      language: language ?? this.language,
      duration: duration ?? this.duration,
      segments: segments ?? this.segments,
      isGpu: isGpu ?? this.isGpu,
      timingMs: timingMs ?? this.timingMs,
    );
  }

  factory TranscriptionResult.fromJson(Map<String, dynamic> json) {
    return TranscriptionResult(
      language: json['language'] as String,
      duration: Duration(milliseconds: json['durationMs'] as int),
      segments: (json['segments'] as List<dynamic>)
          .map((e) => SubtitleSegment.fromJson(e as Map<String, dynamic>))
          .toList(),
      isGpu: json['isGpu'] as bool?,
      timingMs: json['timingMs'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'language': language,
      'durationMs': duration.inMilliseconds,
      'segments': segments.map((e) => e.toJson()).toList(),
      'isGpu': isGpu,
      'timingMs': timingMs,
    };
  }

  @override
  List<Object?> get props => [language, duration, segments, isGpu, timingMs];
}
