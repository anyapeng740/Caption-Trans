import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// Manages Whisper model downloading with progress reporting.
class ModelManager {
  final WhisperController _controller = WhisperController();

  /// Check if a model is already downloaded.
  Future<bool> isModelDownloaded(WhisperModel model) async {
    final path = await _controller.getPath(model);
    return File(path).existsSync();
  }

  /// Download a model with progress reporting.
  ///
  /// [onProgress] reports (receivedBytes, totalBytes). totalBytes may be -1
  /// if the server does not provide Content-Length.
  Future<String> downloadModel(
    WhisperModel model, {
    void Function(int received, int total)? onProgress,
  }) async {
    final path = await _controller.getPath(model);
    final file = File(path);

    if (file.existsSync()) {
      return path;
    }

    // Download with progress tracking
    final url = model.modelUri;
    final request = http.Request('GET', url);
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to download model: HTTP ${response.statusCode}');
    }

    final totalBytes = response.contentLength ?? -1;
    var receivedBytes = 0;

    // Ensure directory exists
    final dir = file.parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final sink = file.openWrite();

    await for (final chunk in response.stream) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      onProgress?.call(receivedBytes, totalBytes);
    }

    await sink.close();
    return path;
  }

  /// Get list of available models with their download status.
  Future<Map<WhisperModel, bool>> getAvailableModels() async {
    final result = <WhisperModel, bool>{};
    for (final model in WhisperModel.values) {
      if (model.modelName.endsWith('.en')) continue;
      result[model] = await isModelDownloaded(model);
    }
    return result;
  }

  /// Delete a downloaded model.
  Future<void> deleteModel(WhisperModel model) async {
    final path = await _controller.getPath(model);
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
  }
}
