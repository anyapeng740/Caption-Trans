import 'dart:io';

import '../../models/subtitle_segment.dart';
import '../../models/transcription_result.dart';
import '../audio/media_to_wav_converter.dart';
import 'whisperx_sidecar.dart';

/// Service for transcribing media using WhisperX through a local Python sidecar.
class WhisperService {
  static const Map<String, String> modelMap = {
    'tiny': 'tiny',
    'base': 'base',
    'small': 'small',
    'medium': 'medium',
    'large-v3': 'large-v3',
    'large-v3-turbo': 'large-v3-turbo',
  };

  static const String _defaultDevice = 'cpu';
  static const String _defaultComputeType = 'int8';
  static const int _defaultBatchSize = 4;

  final WhisperXSidecar _sidecar = WhisperXSidecar();
  final MediaToWavConverter _wavConverter = MediaToWavConverter();

  String? _currentModel;

  /// Download sidecar runtime resources with byte-accurate progress.
  ///
  /// If resources are already cached, the callback receives an immediate 100%.
  Future<void> downloadModel(
    String modelName, {
    void Function(int received, int total)? onDownloadProgress,
  }) async {
    final String? whisperxModel = modelMap[modelName];
    if (whisperxModel == null) {
      throw ArgumentError('Unknown model: $modelName');
    }

    bool progressUpdated = false;
    await _sidecar.ensureStarted(
      onRuntimeDownloadProgress: (received, total) {
        progressUpdated = true;
        onDownloadProgress?.call(received, total);
      },
    );

    if (!progressUpdated) {
      onDownloadProgress?.call(1, 1);
    }
  }

  /// Ensure sidecar is ready and mark the selected model for next transcription.
  ///
  /// WhisperX model weights are loaded lazily on the first transcribe request.
  Future<void> loadModel(String modelName) async {
    final String? whisperxModel = modelMap[modelName];
    if (whisperxModel == null) {
      throw ArgumentError('Unknown model: $modelName');
    }

    await _sidecar.ensureStarted();
    _currentModel = modelName;
  }

  /// Convert input media into WhisperX-ready WAV.
  Future<String> transcodeToWav(String mediaPath) {
    return _wavConverter.ensureWhisperxWav(mediaPath);
  }

  /// Transcribe already-prepared WAV using loaded model (no fake progress).
  Future<TranscriptionResult> transcribeWav(
    String wavPath, {
    String language = 'auto',
    void Function(String status, String? detail)? onStatus,
    void Function(String line)? onLog,
  }) async {
    final String? selectedModel = _currentModel;
    if (selectedModel == null) {
      throw StateError('No model loaded. Call loadModel() first.');
    }

    final String whisperxModel = modelMap[selectedModel]!;
    final Map<String, dynamic> payload = await _sidecar.transcribe(
      wavPath: wavPath,
      modelName: whisperxModel,
      language: language == 'auto' ? null : language,
      device: _defaultDevice,
      computeType: _defaultComputeType,
      batchSize: _defaultBatchSize,
      noAlign: false,
      onStatus: onStatus,
      onLog: onLog,
    );
    return _parseTranscriptionPayload(payload, requestedLanguage: language);
  }

  Future<void> cleanupTempWav(
    String wavPath, {
    required String originalMediaPath,
  }) async {
    if (wavPath == originalMediaPath) return;
    final File file = File(wavPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  TranscriptionResult _parseTranscriptionPayload(
    Map<String, dynamic> payload, {
    required String requestedLanguage,
  }) {
    final List<dynamic> rawSegments =
        (payload['segments'] as List<dynamic>?) ?? [];
    final List<SubtitleSegment> segments = <SubtitleSegment>[];
    for (int i = 0; i < rawSegments.length; i++) {
      final dynamic raw = rawSegments[i];
      if (raw is! Map<String, dynamic>) {
        continue;
      }

      final int startMs = (((raw['start'] as num?) ?? 0).toDouble() * 1000)
          .round();
      final int endMs = (((raw['end'] as num?) ?? 0).toDouble() * 1000).round();
      final String text = ((raw['text'] as String?) ?? '').trim();
      if (text.isEmpty) continue;

      segments.add(
        SubtitleSegment(
          index: i + 1,
          startTime: Duration(milliseconds: startMs),
          endTime: Duration(milliseconds: endMs < startMs ? startMs : endMs),
          text: text,
        ),
      );
    }

    final String detectedLanguage =
        (payload['language'] as String?)?.trim().isNotEmpty == true
        ? (payload['language'] as String)
        : (requestedLanguage == 'auto' ? 'unknown' : requestedLanguage);

    final Duration duration = (() {
      final num? value = payload['duration_sec'] as num?;
      if (value == null) {
        if (segments.isEmpty) return Duration.zero;
        return segments.last.endTime;
      }
      return Duration(milliseconds: (value.toDouble() * 1000).round());
    })();

    return TranscriptionResult(
      language: detectedLanguage,
      duration: duration,
      segments: segments,
    );
  }

  bool get isModelLoaded => _currentModel != null;
  String? get loadedModelName => _currentModel;

  Future<void> dispose() async {
    await _sidecar.dispose();
    _currentModel = null;
  }
}
