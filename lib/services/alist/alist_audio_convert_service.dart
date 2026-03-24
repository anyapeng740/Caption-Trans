import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart'
    as ffmpeg_windows;
import 'package:path/path.dart' as p;

import 'alist_service.dart';

enum AListAudioFormat { mp3, m4a, wav, flac }

extension AListAudioFormatX on AListAudioFormat {
  String get id {
    switch (this) {
      case AListAudioFormat.mp3:
        return 'mp3';
      case AListAudioFormat.m4a:
        return 'm4a';
      case AListAudioFormat.wav:
        return 'wav';
      case AListAudioFormat.flac:
        return 'flac';
    }
  }

  String get displayName {
    switch (this) {
      case AListAudioFormat.mp3:
        return 'MP3';
      case AListAudioFormat.m4a:
        return 'M4A';
      case AListAudioFormat.wav:
        return 'WAV 16k 单声道';
      case AListAudioFormat.flac:
        return 'FLAC 16k 单声道';
    }
  }
}

class AListAudioConvertService {
  static const String _ffmpegProgressPrefix = 'out_time=';

  String buildOutputPath({
    required String outputDir,
    required String remotePath,
    required AListAudioFormat format,
  }) {
    final String cleanRemote = p.posix.normalize(remotePath.trim());
    final String baseName = p.basenameWithoutExtension(cleanRemote);
    if (baseName.isEmpty || baseName == '.' || baseName == '/') {
      throw const AListError('无法从远端路径推导输出文件名。');
    }
    final String subDir = p.posix.dirname(cleanRemote);
    String localDir = outputDir;
    if (subDir != '/') {
      localDir = p.join(
        outputDir,
        p.posix.normalize(subDir).replaceFirst('/', ''),
      );
    }
    return p.join(localDir, '$baseName.${format.id}');
  }

  Future<void> convertFromRemote({
    required String inputUrl,
    required Map<String, String> headers,
    required String outputPath,
    required AListAudioFormat format,
    void Function(AListAudioProgress progress)? onProgress,
  }) {
    return startConversion(
      inputUrl: inputUrl,
      headers: headers,
      outputPath: outputPath,
      format: format,
      onProgress: onProgress,
    ).done;
  }

  AListAudioConversionHandle startConversion({
    required String inputUrl,
    required Map<String, String> headers,
    required String outputPath,
    required AListAudioFormat format,
    void Function(AListAudioProgress progress)? onProgress,
  }) {
    if (Platform.isMacOS) {
      return _startMacOSConversion(
        inputUrl: inputUrl,
        headers: headers,
        outputPath: outputPath,
        format: format,
        onProgress: onProgress,
      );
    }

    if (Platform.isWindows) {
      return _startWindowsConversion(
        inputUrl: inputUrl,
        headers: headers,
        outputPath: outputPath,
        format: format,
        onProgress: onProgress,
      );
    }

    return AListAudioConversionHandle(
      done: Future<void>.error(
        AListError('当前平台暂不支持转换：${Platform.operatingSystem}'),
      ),
      cancel: () {},
    );
  }

  AListAudioConversionHandle _startMacOSConversion({
    required String inputUrl,
    required Map<String, String> headers,
    required String outputPath,
    required AListAudioFormat format,
    void Function(AListAudioProgress progress)? onProgress,
  }) {
    final Completer<void> completer = Completer<void>();
    Process? process;
    Timer? killTimer;
    bool cancelled = false;

    final List<String> args = _buildFfmpegArgs(
      inputUrl: inputUrl,
      headers: headers,
      outputPath: outputPath,
      format: format,
    );

    () async {
      StreamSubscription<String>? stdoutSub;
      StreamSubscription<String>? stderrSub;
      final StringBuffer stderrBuffer = StringBuffer();
      try {
        await Directory(p.dirname(outputPath)).create(recursive: true);
        final Duration? totalDuration = await _probeDuration(
          inputUrl: inputUrl,
          headers: headers,
        );
        if (cancelled) {
          throw const AListAudioCancelledError();
        }
        onProgress?.call(
          AListAudioProgress(
            progress: totalDuration == null ? null : 0,
            current: Duration.zero,
            total: totalDuration,
          ),
        );

        final String executable = await _findSystemFfmpeg();
        process = await Process.start(executable, args, runInShell: false);

        stdoutSub = process!.stdout
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())
            .listen((String line) {
              if (!line.startsWith(_ffmpegProgressPrefix)) return;
              final Duration? current = _parseFfmpegTimestamp(
                line.substring(_ffmpegProgressPrefix.length).trim(),
              );
              if (current == null) return;
              final double? progress = _calculateProgress(
                current,
                totalDuration,
              );
              onProgress?.call(
                AListAudioProgress(
                  progress: progress,
                  current: current,
                  total: totalDuration,
                ),
              );
            });
        stderrSub = process!.stderr
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())
            .listen((String line) {
              stderrBuffer.writeln(line);
            });

        final int exitCode = await process!.exitCode;
        await stdoutSub.cancel();
        await stderrSub.cancel();
        killTimer?.cancel();

        if (cancelled) {
          throw const AListAudioCancelledError();
        }
        if (exitCode != 0) {
          final String logs = stderrBuffer.toString().trim();
          throw AListError(
            'macOS 上 FFmpeg 转换失败（代码：$exitCode）。${logs.isEmpty ? '未返回详细日志。' : logs}',
          );
        }

        onProgress?.call(
          AListAudioProgress(
            progress: 1,
            current: totalDuration ?? Duration.zero,
            total: totalDuration,
          ),
        );
        if (!completer.isCompleted) {
          completer.complete();
        }
      } catch (error, stackTrace) {
        if (cancelled && error is! AListAudioCancelledError) {
          if (!completer.isCompleted) {
            completer.completeError(
              const AListAudioCancelledError(),
              stackTrace,
            );
          }
          return;
        }
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      } finally {
        killTimer?.cancel();
      }
    }();

    return AListAudioConversionHandle(
      done: completer.future,
      cancel: () {
        if (cancelled) return;
        cancelled = true;
        final Process? current = process;
        if (current == null) {
          return;
        }
        current.kill(ProcessSignal.sigterm);
        killTimer = Timer(const Duration(seconds: 2), () {
          current.kill(ProcessSignal.sigkill);
        });
      },
    );
  }

  List<String> _buildFfmpegArgs({
    required String inputUrl,
    required Map<String, String> headers,
    required String outputPath,
    required AListAudioFormat format,
  }) {
    final List<String> args = <String>[
      '-hide_banner',
      '-loglevel',
      'error',
      '-nostats',
      '-nostdin',
      '-y',
      '-progress',
      'pipe:1',
    ];

    final String headerArg = _buildHeaderArg(headers);
    if (headerArg.isNotEmpty) {
      args.addAll(<String>['-headers', headerArg]);
    }

    args.addAll(<String>['-i', inputUrl]);
    args.addAll(_formatAudioArgs(format));
    args.add(outputPath);
    return args;
  }

  List<String> _formatAudioArgs(AListAudioFormat format) {
    switch (format) {
      case AListAudioFormat.mp3:
        return const <String>['-vn', '-c:a', 'libmp3lame', '-q:a', '2'];
      case AListAudioFormat.m4a:
        return const <String>['-vn', '-c:a', 'aac', '-b:a', '192k'];
      case AListAudioFormat.wav:
        return const <String>[
          '-vn',
          '-ac',
          '1',
          '-ar',
          '16000',
          '-c:a',
          'pcm_s16le',
        ];
      case AListAudioFormat.flac:
        return const <String>[
          '-vn',
          '-ac',
          '1',
          '-ar',
          '16000',
          '-c:a',
          'flac',
        ];
    }
  }

  String _buildHeaderArg(Map<String, String> headers) {
    if (headers.isEmpty) return '';
    final List<String> keys = headers.keys.toList()..sort();
    final StringBuffer buffer = StringBuffer();
    for (final String key in keys) {
      final String value = headers[key]?.trim() ?? '';
      if (key.trim().isEmpty || value.isEmpty) continue;
      buffer.write('$key: $value\r\n');
    }
    return buffer.toString();
  }

  String _buildCommandString(List<String> args) {
    return args.map(_escapeArg).join(' ');
  }

  AListAudioConversionHandle _startWindowsConversion({
    required String inputUrl,
    required Map<String, String> headers,
    required String outputPath,
    required AListAudioFormat format,
    void Function(AListAudioProgress progress)? onProgress,
  }) {
    final Completer<void> completer = Completer<void>();
    ffmpeg_windows.FFmpegSession? session;
    final List<String> args = _buildFfmpegArgs(
      inputUrl: inputUrl,
      headers: headers,
      outputPath: outputPath,
      format: format,
    );
    final String command = _buildCommandString(args);

    Future<void>(() async {
      try {
        session = ffmpeg_windows.FFmpegKit.execute(command);
        final int rc = session!.getReturnCode();
        if (rc == 0) {
          onProgress?.call(
            const AListAudioProgress(progress: 1, current: Duration.zero),
          );
          completer.complete();
          return;
        }
        completer.completeError(
          AListError(
            'Windows 上 FFmpeg 转换失败（代码：$rc）。${session!.getOutput() ?? ''}',
          ),
        );
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    return AListAudioConversionHandle(
      done: completer.future,
      cancel: () {
        session?.cancel();
      },
    );
  }

  Future<String> _findSystemFfmpeg() async {
    const List<String> absoluteCandidates = <String>[
      '/opt/homebrew/bin/ffmpeg',
      '/usr/local/bin/ffmpeg',
    ];
    for (final String candidate in absoluteCandidates) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }
    return 'ffmpeg';
  }

  Future<String> _findSystemFfprobe() async {
    const List<String> absoluteCandidates = <String>[
      '/opt/homebrew/bin/ffprobe',
      '/usr/local/bin/ffprobe',
    ];
    for (final String candidate in absoluteCandidates) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }
    return 'ffprobe';
  }

  Future<Duration?> _probeDuration({
    required String inputUrl,
    required Map<String, String> headers,
  }) async {
    try {
      final String executable = await _findSystemFfprobe();
      final List<String> args = <String>['-v', 'error'];
      final String headerArg = _buildHeaderArg(headers);
      if (headerArg.isNotEmpty) {
        args.addAll(<String>['-headers', headerArg]);
      }
      args.addAll(<String>[
        '-show_entries',
        'format=duration',
        '-of',
        'default=noprint_wrappers=1:nokey=1',
        inputUrl,
      ]);
      final ProcessResult result = await Process.run(
        executable,
        args,
        runInShell: false,
      );
      if (result.exitCode != 0) {
        return null;
      }
      final double? seconds = double.tryParse(
        (result.stdout ?? '').toString().trim(),
      );
      if (seconds == null || !seconds.isFinite || seconds <= 0) {
        return null;
      }
      return Duration(microseconds: (seconds * 1000000).round());
    } catch (_) {
      return null;
    }
  }

  Duration? _parseFfmpegTimestamp(String raw) {
    final List<String> parts = raw.split(':');
    if (parts.length != 3) {
      return null;
    }
    final double? hours = double.tryParse(parts[0]);
    final double? minutes = double.tryParse(parts[1]);
    final double? seconds = double.tryParse(parts[2]);
    if (hours == null || minutes == null || seconds == null) {
      return null;
    }
    final double totalSeconds = hours * 3600 + minutes * 60 + seconds;
    if (!totalSeconds.isFinite || totalSeconds < 0) {
      return null;
    }
    return Duration(microseconds: (totalSeconds * 1000000).round());
  }

  double? _calculateProgress(Duration current, Duration? total) {
    if (total == null || total.inMicroseconds <= 0) {
      return null;
    }
    final double progress = current.inMicroseconds / total.inMicroseconds;
    if (progress.isNaN || progress.isInfinite) {
      return null;
    }
    if (progress < 0) return 0;
    if (progress > 0.999) return 0.999;
    return progress;
  }

  String _escapeArg(String value) {
    if (value.isEmpty) return '""';
    final bool needsQuote =
        value.contains(' ') ||
        value.contains('\t') ||
        value.contains('\n') ||
        value.contains('\r') ||
        value.contains('"');
    final String escaped = value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', r'\"');
    return needsQuote ? '"$escaped"' : escaped;
  }
}

class AListAudioProgress {
  final double? progress;
  final Duration current;
  final Duration? total;

  const AListAudioProgress({
    required this.progress,
    required this.current,
    this.total,
  });
}

class AListAudioConversionHandle {
  final Future<void> done;
  final void Function() cancel;

  const AListAudioConversionHandle({required this.done, required this.cancel});
}

class AListAudioCancelledError implements Exception {
  const AListAudioCancelledError();

  @override
  String toString() => '已取消';
}
