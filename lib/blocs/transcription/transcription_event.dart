import 'package:equatable/equatable.dart';

/// Events for the TranscriptionBloc.
abstract class TranscriptionEvent extends Equatable {
  const TranscriptionEvent();

  @override
  List<Object?> get props => [];
}

/// User selected a video file.
class SelectVideo extends TranscriptionEvent {
  final String videoPath;
  const SelectVideo(this.videoPath);

  @override
  List<Object?> get props => [videoPath];
}

/// Start the transcription process.
class StartTranscription extends TranscriptionEvent {
  final String modelName;
  final String? language;

  const StartTranscription({
    required this.modelName,
    this.language,
  });

  @override
  List<Object?> get props => [modelName, language];
}

/// Cancel an ongoing transcription.
class CancelTranscription extends TranscriptionEvent {
  const CancelTranscription();
}

/// Reset to initial state.
class ResetTranscription extends TranscriptionEvent {
  const ResetTranscription();
}
