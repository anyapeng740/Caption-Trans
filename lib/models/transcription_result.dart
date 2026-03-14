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

  const TranscriptionResult({
    required this.language,
    required this.duration,
    required this.segments,
  });

  @override
  List<Object?> get props => [language, duration, segments];
}
