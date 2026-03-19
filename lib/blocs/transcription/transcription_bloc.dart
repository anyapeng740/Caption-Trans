import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../services/whisper/whisper_service.dart';
import 'transcription_event.dart';
import 'transcription_state.dart';

/// BLoC managing the transcription workflow.
class TranscriptionBloc extends Bloc<TranscriptionEvent, TranscriptionState> {
  final WhisperService _whisperService;

  TranscriptionBloc({WhisperService? whisperService})
    : _whisperService = whisperService ?? WhisperService(),
      super(const TranscriptionInitial()) {
    on<SelectVideo>(_onSelectVideo);
    on<StartTranscription>(_onStartTranscription);
    on<ResetTranscription>(_onReset);
    on<LoadTranscriptionFromProject>(_onLoadTranscriptionFromProject);
  }

  void _onSelectVideo(SelectVideo event, Emitter<TranscriptionState> emit) {
    emit(
      VideoSelected(
        videoPath: event.videoPath,
        fileName: p.basename(event.videoPath),
      ),
    );
  }

  Future<void> _onStartTranscription(
    StartTranscription event,
    Emitter<TranscriptionState> emit,
  ) async {
    final String? videoPath = _currentVideoPath;
    final String? fileName = _currentFileName;
    if (videoPath == null || fileName == null) return;

    String wavPath = videoPath;
    try {
      // 1) Download runtime/model resources (accurate byte progress)
      emit(
        ModelDownloading(
          videoPath: videoPath,
          fileName: fileName,
          modelName: event.modelName,
          progress: 0,
        ),
      );
      await _whisperService.downloadModel(
        event.modelName,
        onDownloadProgress: (received, total) {
          if (emit.isDone) return;
          emit(
            ModelDownloading(
              videoPath: videoPath,
              fileName: fileName,
              modelName: event.modelName,
              progress: total > 0 ? received / total : 0,
            ),
          );
        },
      );

      // 2) Load model (no progress)
      emit(
        ModelLoading(
          videoPath: videoPath,
          fileName: fileName,
          modelName: event.modelName,
        ),
      );
      await _whisperService.loadModel(
        event.modelName,
        language: event.language ?? 'auto',
      );

      // 3) Transcode media to WAV (no progress)
      emit(AudioTranscoding(videoPath: videoPath, fileName: fileName));
      wavPath = await _whisperService.transcodeToWav(videoPath);

      // 4) Transcribe (no fake progress, optionally surface logs)
      emit(
        Transcribing(
          videoPath: videoPath,
          fileName: fileName,
          statusMessage: 'Transcribing...',
        ),
      );
      final result = await _whisperService.transcribeWav(
        wavPath,
        language: event.language ?? 'auto',
        onLog: (line) {
          if (emit.isDone) return;
          final normalized = _normalizeLogLine(line);
          if (normalized == null) return;
          emit(
            Transcribing(
              videoPath: videoPath,
              fileName: fileName,
              statusMessage: normalized,
            ),
          );
        },
      );

      emit(
        TranscriptionComplete(
          videoPath: videoPath,
          fileName: fileName,
          result: result,
        ),
      );
    } catch (e) {
      emit(
        TranscriptionError(
          videoPath: videoPath,
          fileName: fileName,
          message: e.toString(),
        ),
      );
    } finally {
      await _whisperService.cleanupTempWav(
        wavPath,
        originalMediaPath: videoPath,
      );
    }
  }

  String? _normalizeLogLine(String line) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    // WhisperX/PyTorch logs can be very long; keep status concise in UI.
    return trimmed.length > 140 ? '${trimmed.substring(0, 140)}...' : trimmed;
  }

  void _onReset(ResetTranscription event, Emitter<TranscriptionState> emit) {
    emit(const TranscriptionInitial());
  }

  void _onLoadTranscriptionFromProject(
    LoadTranscriptionFromProject event,
    Emitter<TranscriptionState> emit,
  ) {
    emit(
      TranscriptionComplete(
        videoPath: event.videoPath,
        fileName: event.fileName,
        result: event.result,
      ),
    );
  }

  String? get _currentVideoPath {
    final s = state;
    if (s is VideoSelected) return s.videoPath;
    if (s is ModelDownloading) return s.videoPath;
    if (s is ModelLoading) return s.videoPath;
    if (s is AudioTranscoding) return s.videoPath;
    if (s is Transcribing) return s.videoPath;
    if (s is TranscriptionComplete) return s.videoPath;
    if (s is TranscriptionError) return s.videoPath;
    return null;
  }

  String? get _currentFileName {
    final s = state;
    if (s is VideoSelected) return s.fileName;
    if (s is ModelDownloading) return s.fileName;
    if (s is ModelLoading) return s.fileName;
    if (s is AudioTranscoding) return s.fileName;
    if (s is Transcribing) return s.fileName;
    if (s is TranscriptionComplete) return s.fileName;
    if (s is TranscriptionError) return s.fileName;
    return null;
  }

  @override
  Future<void> close() async {
    await _whisperService.dispose();
    return super.close();
  }
}
