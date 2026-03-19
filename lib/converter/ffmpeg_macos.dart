import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/foundation.dart';

/// FFmpeg converter for macOS.
///
/// Converts media into 16kHz mono 16-bit PCM WAV which WhisperX accepts.
class FFmpegMacOsConverter {
  FFmpegMacOsConverter._();

  static Future<void> convertToWav({
    required String inputPath,
    required String outputPath,
  }) async {
    final List<String> arguments = [
      '-y',
      '-i',
      '"$inputPath"',
      '-map',
      '0:a:0',
      '-af',
      'aresample=async=1:first_pts=0',
      '-ar',
      '16000',
      '-ac',
      '1',
      '-c:a',
      'pcm_s16le',
      '"$outputPath"',
    ];

    debugPrint('⚙️ [FFMPEG][macOS] $inputPath -> $outputPath');

    final FFmpegSession session = await FFmpegKit.execute(arguments.join(' '));
    final ReturnCode? returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode)) {
      return;
    }

    final String? logs = await session.getOutput();
    throw Exception(
      'FFmpeg conversion failed on macOS '
      '(code: ${returnCode?.getValue() ?? 'unknown'}). '
      '${logs ?? ''}',
    );
  }
}
