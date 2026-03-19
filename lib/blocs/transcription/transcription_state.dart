import 'package:equatable/equatable.dart';
import '../../models/transcription_result.dart';

/// States for the TranscriptionBloc.
abstract class TranscriptionState extends Equatable {
  const TranscriptionState();

  @override
  List<Object?> get props => [];
}

/// Initial state — no video selected.
class TranscriptionInitial extends TranscriptionState {
  const TranscriptionInitial();
}

/// A video file has been selected.
class VideoSelected extends TranscriptionState {
  final String videoPath;
  final String fileName;

  const VideoSelected({required this.videoPath, required this.fileName});

  @override
  List<Object?> get props => [videoPath, fileName];
}

/// Sidecar runtime assets are being prepared/downloaded.
class RuntimePreparing extends TranscriptionState {
  final String videoPath;
  final String fileName;
  final double progress;

  const RuntimePreparing({
    required this.videoPath,
    required this.fileName,
    required this.progress,
  });

  @override
  List<Object?> get props => [videoPath, fileName, progress];
}

/// Media is being transcoded to WAV.
class AudioTranscoding extends TranscriptionState {
  final String videoPath;
  final String fileName;

  const AudioTranscoding({required this.videoPath, required this.fileName});

  @override
  List<Object?> get props => [videoPath, fileName];
}

/// WhisperX is transcribing.
enum TranscribingPhase {
  loadingAudio,
  preparingModel,
  transcribing,
  aligning,
  finalizing,
}

class Transcribing extends TranscriptionState {
  final String videoPath;
  final String fileName;
  final TranscribingPhase phase;
  final String? statusDetail;

  const Transcribing({
    required this.videoPath,
    required this.fileName,
    this.phase = TranscribingPhase.transcribing,
    this.statusDetail,
  });

  @override
  List<Object?> get props => [videoPath, fileName, phase, statusDetail];
}

/// Transcription completed successfully.
class TranscriptionComplete extends TranscriptionState {
  final String videoPath;
  final String fileName;
  final TranscriptionResult result;

  const TranscriptionComplete({
    required this.videoPath,
    required this.fileName,
    required this.result,
  });

  @override
  List<Object?> get props => [videoPath, fileName, result];
}

/// Transcription failed.
class TranscriptionError extends TranscriptionState {
  final String videoPath;
  final String fileName;
  final String message;

  const TranscriptionError({
    required this.videoPath,
    required this.fileName,
    required this.message,
  });

  @override
  List<Object?> get props => [videoPath, fileName, message];
}
