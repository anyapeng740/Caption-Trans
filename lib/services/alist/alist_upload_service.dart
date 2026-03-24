import 'dart:io';

import 'package:path/path.dart' as p;

import 'alist_service.dart';

class AListUploadService {
  final AListService _alist;

  AListUploadService({AListService? alist}) : _alist = alist ?? AListService();

  Future<List<String>> uploadLocalFiles({
    required String baseUrl,
    required String username,
    required String password,
    required String localRoot,
    required String remoteBase,
    required List<String> localPaths,
    void Function(int current, int total, String remotePath)? onProgress,
  }) async {
    if (localPaths.isEmpty) {
      return <String>[];
    }

    final AListTarget target = _alist.normalizeBaseUrl(baseUrl);
    final String token = await _alist.login(
      baseUrl: target.baseUrl,
      username: username,
      password: password,
    );

    final String normalizedLocalRoot = p.normalize(localRoot);
    final String normalizedRemoteBase = _alist.normalizePath(remoteBase);
    final List<String> uploaded = <String>[];

    for (int index = 0; index < localPaths.length; index++) {
      final String localPath = p.normalize(localPaths[index]);
      final File localFile = File(localPath);
      if (!await localFile.exists()) {
        throw AListError('本地文件不存在：$localPath');
      }

      final String remotePath = mapLocalFileToRemote(
        localRoot: normalizedLocalRoot,
        remoteBase: normalizedRemoteBase,
        localPath: localPath,
      );
      onProgress?.call(index + 1, localPaths.length, remotePath);
      await _alist.ensureRemoteDir(
        baseUrl: target.baseUrl,
        token: token,
        remoteDir: p.posix.dirname(remotePath),
      );
      await _alist.uploadLocalFile(
        baseUrl: target.baseUrl,
        token: token,
        localPath: localPath,
        remotePath: remotePath,
      );
      uploaded.add(remotePath);
    }

    return uploaded;
  }

  String mapLocalFileToRemote({
    required String localRoot,
    required String remoteBase,
    required String localPath,
  }) {
    final String relative = p.relative(localPath, from: localRoot);
    if (relative == '.' || relative.startsWith('..')) {
      throw AListError('文件不在本地根目录下：$localPath');
    }
    final String normalizedRemoteBase = _alist.normalizePath(remoteBase);
    final String relativeUnix = p.posix.normalize(
      relative.replaceAll('\\', '/'),
    );
    final String trimmedRelative = _stripDuplicatedRemotePrefix(
      normalizedRemoteBase,
      relativeUnix,
    );
    return _alist.normalizePath(
      p.posix.join(normalizedRemoteBase, trimmedRelative),
    );
  }

  String _stripDuplicatedRemotePrefix(String remoteBase, String relativePath) {
    final List<String> baseParts = _splitRemoteParts(remoteBase);
    final List<String> relativeParts = _splitRemoteParts(relativePath);
    if (baseParts.isEmpty || relativeParts.isEmpty) {
      return relativePath;
    }
    if (relativeParts.length < baseParts.length) {
      return relativePath;
    }
    for (int index = 0; index < baseParts.length; index++) {
      if (baseParts[index] != relativeParts[index]) {
        return relativePath;
      }
    }
    final List<String> trimmed = relativeParts.sublist(baseParts.length);
    if (trimmed.isEmpty) {
      return p.posix.basename(relativePath);
    }
    return trimmed.join('/');
  }

  List<String> _splitRemoteParts(String value) {
    return value
        .split('/')
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList();
  }

  void dispose() {
    _alist.dispose();
  }
}
