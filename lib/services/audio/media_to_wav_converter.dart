import 'dart:io';

import 'package:caption_trans/converter/ffmpeg_macos.dart';
import 'package:caption_trans/converter/ffmpeg_windows.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Converts media input into WhisperX-ready WAV audio.
class MediaToWavConverter {
  /// Convert [inputPath] to WhisperX-ready WAV (16kHz mono 16-bit PCM).
  ///
  /// We always normalize via FFmpeg, even for `.wav` input, to guarantee
  /// WhisperX loader compatibility.
  Future<String> ensureWhisperxWav(String inputPath) async {
    final tempDir = await getTemporaryDirectory();
    final outputDir = Directory(
      p.join(tempDir.path, 'caption_trans', 'whisperx'),
    );
    await outputDir.create(recursive: true);

    final outputPath = p.join(
      outputDir.path,
      '${p.basenameWithoutExtension(inputPath)}_${DateTime.now().microsecondsSinceEpoch}.wav',
    );

    if (Platform.isMacOS) {
      await FFmpegMacOsConverter.convertToWav(
        inputPath: inputPath,
        outputPath: outputPath,
      );
      return outputPath;
    }

    if (Platform.isWindows) {
      await FFmpegWindowsConverter.convertToWav(
        inputPath: inputPath,
        outputPath: outputPath,
      );
      return outputPath;
    }

    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}
