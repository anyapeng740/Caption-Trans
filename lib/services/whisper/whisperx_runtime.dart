import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class WhisperXRuntimeInfo {
  final String pythonExecutable;
  final String workerScriptPath;

  const WhisperXRuntimeInfo({
    required this.pythonExecutable,
    required this.workerScriptPath,
  });
}

class _PythonCommand {
  final String executable;
  final List<String> prefixArgs;

  const _PythonCommand({required this.executable, this.prefixArgs = const []});
}

class _ManagedRuntimeSpec {
  final String id;
  final Uri url;
  final String sha256Hex;
  final String archiveType;
  final String pythonRelativePath;

  const _ManagedRuntimeSpec({
    required this.id,
    required this.url,
    required this.sha256Hex,
    required this.archiveType,
    required this.pythonRelativePath,
  });
}

/// Ensures local Python runtime for WhisperX sidecar execution.
///
/// Runtime resolution order:
/// 1) Managed runtime package (download + verify + extract) if configured.
/// 2) System Python fallback (for development environments).
class WhisperXRuntime {
  static const String _runtimeDirName = 'whisperx_sidecar';
  static const String _workerAssetPath = 'assets/sidecar/whisperx_worker.py';
  static const String _workerFileName = 'whisperx_worker.py';
  static const String _manifestAssetPath =
      'assets/sidecar/runtime_manifest.json';
  static const String _runtimeVersion = '2';
  static const String _venvMarkerFile = '.runtime_ready_v2';
  static const String _managedMarkerFile = '.managed_runtime_v1';
  static const String _targetWhisperxVersion = '3.8.2';

  WhisperXRuntime._();

  static final WhisperXRuntime instance = WhisperXRuntime._();

  WhisperXRuntimeInfo? _cachedInfo;

  Future<WhisperXRuntimeInfo> ensureReady({
    void Function(int percent)? onProgress,
    void Function(int received, int total)? onDownloadProgress,
  }) async {
    if (_cachedInfo != null) {
      onProgress?.call(100);
      return _cachedInfo!;
    }

    onProgress?.call(2);
    final Directory supportDir = await getApplicationSupportDirectory();
    final Directory runtimeDir = Directory(
      p.join(supportDir.path, _runtimeDirName),
    );
    await runtimeDir.create(recursive: true);

    onProgress?.call(6);
    final String workerPath = await _ensureWorkerScript(runtimeDir);

    onProgress?.call(10);
    final String basePythonExecutable = await _resolveBasePython(
      runtimeDir,
      onProgress: onProgress,
      onDownloadProgress: onDownloadProgress,
    );

    onProgress?.call(62);
    final Directory venvDir = Directory(p.join(runtimeDir.path, 'venv'));
    await _ensureVenv(venvDir, basePythonExecutable);

    final String venvPythonPath = _resolveVenvPython(venvDir);
    if (!File(venvPythonPath).existsSync()) {
      throw Exception('Python venv is missing executable: $venvPythonPath');
    }

    onProgress?.call(72);
    final File marker = File(p.join(runtimeDir.path, _venvMarkerFile));
    if (!await _isWhisperxInstalled(venvPythonPath) || !await marker.exists()) {
      await _installDependencies(venvPythonPath, onProgress: onProgress);
      await marker.writeAsString(
        jsonEncode({
          'runtimeVersion': _runtimeVersion,
          'whisperxVersion': _targetWhisperxVersion,
          'createdAt': DateTime.now().toIso8601String(),
        }),
      );
    } else {
      onProgress?.call(94);
    }

    final info = WhisperXRuntimeInfo(
      pythonExecutable: venvPythonPath,
      workerScriptPath: workerPath,
    );
    _cachedInfo = info;
    onProgress?.call(100);
    return info;
  }

  Future<String> _ensureWorkerScript(Directory runtimeDir) async {
    final File scriptFile = File(p.join(runtimeDir.path, _workerFileName));
    final ByteData data = await rootBundle.load(_workerAssetPath);
    final String scriptContent = utf8.decode(data.buffer.asUint8List());

    if (!scriptFile.existsSync()) {
      await scriptFile.writeAsString(scriptContent);
      return scriptFile.path;
    }

    final String existing = await scriptFile.readAsString();
    if (existing != scriptContent) {
      await scriptFile.writeAsString(scriptContent);
    }
    return scriptFile.path;
  }

  Future<String> _resolveBasePython(
    Directory runtimeDir, {
    void Function(int percent)? onProgress,
    void Function(int received, int total)? onDownloadProgress,
  }) async {
    final _ManagedRuntimeSpec? managedSpec = await _loadManagedSpec();
    if (managedSpec != null) {
      final String managedPython = await _ensureManagedRuntime(
        runtimeDir,
        managedSpec,
        onProgress: onProgress,
        onDownloadProgress: onDownloadProgress,
      );
      if (File(managedPython).existsSync()) {
        return managedPython;
      }
    }

    final _PythonCommand systemPython = await _findSystemPython();
    return systemPython.executable;
  }

  Future<_ManagedRuntimeSpec?> _loadManagedSpec() async {
    final String raw = await rootBundle.loadString(_manifestAssetPath);
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final dynamic packagesRaw = decoded['packages'];
    if (packagesRaw is! Map<String, dynamic>) {
      return null;
    }

    final String platformKey = _currentPlatformKey();
    final dynamic specRaw = packagesRaw[platformKey];
    if (specRaw is! Map<String, dynamic>) {
      return null;
    }

    final String urlText = (specRaw['url'] as String? ?? '').trim();
    if (urlText.isEmpty) {
      return null;
    }

    final String sha256Hex = (specRaw['sha256'] as String? ?? '').trim();
    final String archiveType = (specRaw['archive_type'] as String? ?? 'zip')
        .trim()
        .toLowerCase();
    final String pythonRelativePath =
        (specRaw['python_relative_path'] as String? ?? '').trim();
    if (pythonRelativePath.isEmpty) {
      throw Exception(
        'Invalid runtime manifest for "$platformKey": '
        'python_relative_path is required.',
      );
    }

    final Uri? uri = Uri.tryParse(urlText);
    if (uri == null) {
      throw Exception('Invalid runtime URL in manifest: $urlText');
    }

    return _ManagedRuntimeSpec(
      id: platformKey,
      url: uri,
      sha256Hex: sha256Hex.toLowerCase(),
      archiveType: archiveType,
      pythonRelativePath: pythonRelativePath,
    );
  }

  String _currentPlatformKey() {
    final version = Platform.version.toLowerCase();
    final bool isArm64 =
        version.contains('arm64') || version.contains('aarch64');

    if (Platform.isMacOS) {
      return isArm64 ? 'macos-arm64' : 'macos-x64';
    }
    if (Platform.isWindows) {
      return 'windows-x64';
    }

    throw UnsupportedError(
      'Managed runtime is unsupported on ${Platform.operatingSystem}',
    );
  }

  Future<String> _ensureManagedRuntime(
    Directory runtimeDir,
    _ManagedRuntimeSpec spec, {
    void Function(int percent)? onProgress,
    void Function(int received, int total)? onDownloadProgress,
  }) async {
    final Directory managedDir = Directory(
      p.join(runtimeDir.path, 'managed_python_${spec.id}'),
    );
    final File marker = File(p.join(managedDir.path, _managedMarkerFile));
    final String pythonPath = p.join(managedDir.path, spec.pythonRelativePath);

    if (managedDir.existsSync() &&
        File(pythonPath).existsSync() &&
        await _isManagedRuntimeValid(marker, spec)) {
      if (await _canExecutePython(pythonPath)) {
        onProgress?.call(55);
        return pythonPath;
      }
      await managedDir.delete(recursive: true);
    }

    final Directory tempDir = Directory(
      p.join(runtimeDir.path, 'tmp_${DateTime.now().microsecondsSinceEpoch}'),
    );
    await tempDir.create(recursive: true);

    try {
      onProgress?.call(14);
      final String archiveExt = spec.archiveType == 'tar.gz' ? 'tar.gz' : 'zip';
      final File archiveFile = File(
        p.join(tempDir.path, 'runtime.$archiveExt'),
      );

      await _downloadFile(
        spec.url,
        archiveFile,
        onProgress: (received, total) {
          onDownloadProgress?.call(received, total);
          if (total > 0) {
            final int mapped = 14 + ((received * 20) ~/ total);
            onProgress?.call(mapped.clamp(14, 34));
          }
        },
      );

      onProgress?.call(36);
      if (spec.sha256Hex.isNotEmpty) {
        final String hash = await _sha256OfFile(archiveFile);
        if (hash != spec.sha256Hex) {
          throw Exception(
            'Managed runtime checksum mismatch.\n'
            'Expected: ${spec.sha256Hex}\nActual:   $hash',
          );
        }
      }

      onProgress?.call(40);
      final Directory stageDir = Directory(p.join(tempDir.path, 'stage'));
      await stageDir.create(recursive: true);
      await _extractArchive(archiveFile, stageDir, spec.archiveType);

      onProgress?.call(50);
      if (managedDir.existsSync()) {
        await managedDir.delete(recursive: true);
      }
      await stageDir.rename(managedDir.path);

      if (!File(pythonPath).existsSync()) {
        throw Exception(
          'Managed runtime installed but python executable is missing: $pythonPath',
        );
      }
      if (!await _canExecutePython(pythonPath)) {
        throw Exception(
          'Managed runtime installed but python is not executable: $pythonPath',
        );
      }

      await marker.writeAsString(
        jsonEncode({
          'id': spec.id,
          'url': spec.url.toString(),
          'sha256': spec.sha256Hex,
          'archive_type': spec.archiveType,
          'python_relative_path': spec.pythonRelativePath,
          'installedAt': DateTime.now().toIso8601String(),
        }),
      );

      onProgress?.call(55);
      return pythonPath;
    } finally {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<bool> _isManagedRuntimeValid(
    File marker,
    _ManagedRuntimeSpec spec,
  ) async {
    if (!await marker.exists()) {
      return false;
    }

    try {
      final dynamic decoded = jsonDecode(await marker.readAsString());
      if (decoded is! Map<String, dynamic>) return false;
      return (decoded['id'] as String? ?? '') == spec.id &&
          (decoded['url'] as String? ?? '') == spec.url.toString() &&
          (decoded['sha256'] as String? ?? '').toLowerCase() ==
              spec.sha256Hex &&
          (decoded['archive_type'] as String? ?? '').toLowerCase() ==
              spec.archiveType.toLowerCase() &&
          (decoded['python_relative_path'] as String? ?? '') ==
              spec.pythonRelativePath;
    } catch (_) {
      return false;
    }
  }

  Future<void> _downloadFile(
    Uri url,
    File output, {
    void Function(int received, int total)? onProgress,
  }) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(url);
      final HttpClientResponse response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('Download failed: HTTP ${response.statusCode} ($url)');
      }

      final int total = response.contentLength;
      int received = 0;
      final IOSink sink = output.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.close();
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _sha256OfFile(File file) async {
    final Digest digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase();
  }

  Future<void> _extractArchive(
    File archiveFile,
    Directory destination,
    String archiveType,
  ) async {
    final String type = archiveType.toLowerCase();
    if (type != 'zip' && type != 'tar.gz') {
      throw Exception('Unsupported archive_type: $archiveType');
    }
    await extractFileToDisk(archiveFile.path, destination.path);
  }

  Future<bool> _canExecutePython(String pythonPath) async {
    try {
      final result = await Process.run(pythonPath, ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<_PythonCommand> _findSystemPython() async {
    final List<_PythonCommand> candidates = Platform.isWindows
        ? const [
            _PythonCommand(executable: 'py', prefixArgs: ['-3']),
            _PythonCommand(executable: 'python'),
            _PythonCommand(executable: 'python3'),
          ]
        : const [
            _PythonCommand(executable: 'python3'),
            _PythonCommand(executable: 'python'),
          ];

    for (final candidate in candidates) {
      final result = await Process.run(candidate.executable, [
        ...candidate.prefixArgs,
        '--version',
      ]);
      if (result.exitCode == 0) {
        return candidate;
      }
    }

    throw Exception(
      'No managed runtime configured and no system Python found.\n'
      'Please configure assets/sidecar/runtime_manifest.json for '
      '${_currentPlatformKey()}, or install Python 3.10+ into PATH.',
    );
  }

  Future<void> _ensureVenv(
    Directory venvDir,
    String basePythonExecutable,
  ) async {
    if (venvDir.existsSync()) {
      return;
    }

    final result = await Process.run(basePythonExecutable, [
      '-m',
      'venv',
      venvDir.path,
    ]);
    if (result.exitCode != 0) {
      throw Exception(
        'Failed to create Python venv.\n'
        '${result.stdout}\n${result.stderr}',
      );
    }
  }

  String _resolveVenvPython(Directory venvDir) {
    if (Platform.isWindows) {
      return p.join(venvDir.path, 'Scripts', 'python.exe');
    }

    final String python3 = p.join(venvDir.path, 'bin', 'python3');
    if (File(python3).existsSync()) {
      return python3;
    }
    return p.join(venvDir.path, 'bin', 'python');
  }

  Future<bool> _isWhisperxInstalled(String pythonExecutable) async {
    final result = await Process.run(pythonExecutable, [
      '-c',
      'import whisperx, numpy; print(whisperx.__version__)',
    ]);
    if (result.exitCode != 0) {
      return false;
    }

    final String version = (result.stdout as String).trim();
    return version.isNotEmpty;
  }

  Future<void> _installDependencies(
    String pythonExecutable, {
    void Function(int percent)? onProgress,
  }) async {
    onProgress?.call(78);
    await _runOrThrow(pythonExecutable, [
      '-m',
      'pip',
      'install',
      '--upgrade',
      'pip',
    ], errorPrefix: 'Failed to upgrade pip for WhisperX runtime.');

    onProgress?.call(86);
    await _runOrThrow(
      pythonExecutable,
      ['-m', 'pip', 'install', 'whisperx==$_targetWhisperxVersion', 'numpy'],
      errorPrefix: 'Failed to install WhisperX runtime dependencies.',
    );

    onProgress?.call(94);
  }

  Future<void> _runOrThrow(
    String executable,
    List<String> args, {
    required String errorPrefix,
  }) async {
    final result = await Process.run(executable, args);
    if (result.exitCode == 0) {
      return;
    }

    throw Exception(
      '$errorPrefix\nCommand: $executable ${args.join(' ')}\n'
      'STDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}',
    );
  }
}
