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

/// Model/runtime assets are being downloaded.
class ModelDownloading extends TranscriptionState {
  final String videoPath;
  final String fileName;
  final String modelName;
  final double progress;

  const ModelDownloading({
    required this.videoPath,
    required this.fileName,
    required this.modelName,
    required this.progress,
  });

  @override
  List<Object?> get props => [videoPath, fileName, modelName, progress];
}

/// Model is being loaded into WhisperX runtime.
class ModelLoading extends TranscriptionState {
  final String videoPath;
  final String fileName;
  final String modelName;

  const ModelLoading({
    required this.videoPath,
    required this.fileName,
    required this.modelName,
  });

  @override
  List<Object?> get props => [videoPath, fileName, modelName];
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
class Transcribing extends TranscriptionState {
  final String videoPath;
  final String fileName;
  final String statusMessage;

  const Transcribing({
    required this.videoPath,
    required this.fileName,
    this.statusMessage = 'Transcribing...',
  });

  @override
  List<Object?> get props => [videoPath, fileName, statusMessage];
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
