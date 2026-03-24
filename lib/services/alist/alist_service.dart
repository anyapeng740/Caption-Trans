import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';

class AListError implements Exception {
  final String message;

  const AListError(this.message);

  @override
  String toString() => message;
}

class AListTarget {
  final String baseUrl;
  final String suggestedPath;

  const AListTarget({required this.baseUrl, required this.suggestedPath});
}

class AListEntry {
  final String name;
  final String path;
  final bool isDir;
  final int size;
  final DateTime? modified;

  const AListEntry({
    required this.name,
    required this.path,
    required this.isDir,
    required this.size,
    required this.modified,
  });
}

class AListLink {
  final String url;
  final Map<String, String> headers;

  const AListLink({required this.url, required this.headers});
}

class AListService {
  static const String _userAgent = 'caption-trans/1.0';

  final http.Client _client;

  AListService({http.Client? client}) : _client = client ?? http.Client();

  void dispose() {
    _client.close();
  }

  AListTarget normalizeBaseUrl(String raw) {
    final input = raw.trim();
    if (input.isEmpty) {
      throw const AListError('请输入 AList 地址。');
    }

    final Uri parsed;
    try {
      parsed = Uri.parse(input);
    } on FormatException {
      throw const AListError('地址格式不正确。');
    }
    if (!parsed.hasScheme || parsed.host.isEmpty) {
      throw const AListError('请输入完整地址，例如 http://127.0.0.1:5244');
    }

    final String trimmedPath = parsed.path.replaceAll(RegExp(r'^/+|/+$'), '');
    final List<String> segments = trimmedPath.isEmpty
        ? <String>[]
        : trimmedPath.split('/');
    List<String> baseSegments = List<String>.from(segments);
    String suggestedPath = '/';

    for (int index = 0; index < segments.length; index++) {
      if (segments[index] != 'dav') continue;
      baseSegments = segments.sublist(0, index);
      if (index < segments.length - 1) {
        suggestedPath = '/${segments.sublist(index + 1).join('/')}';
      }
      break;
    }
    if (baseSegments.isNotEmpty && baseSegments.last == 'api') {
      baseSegments = baseSegments.sublist(0, baseSegments.length - 1);
    }

    final String basePath = baseSegments.isEmpty
        ? ''
        : '/${baseSegments.join('/')}';
    final Uri normalized = parsed.replace(
      path: basePath,
      query: null,
      fragment: null,
    );

    return AListTarget(
      baseUrl: normalized.toString().replaceFirst(RegExp(r'/$'), ''),
      suggestedPath: normalizePath(suggestedPath),
    );
  }

  String normalizePath(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return '/';
    String value = trimmed;
    if (!value.startsWith('/')) {
      value = '/$value';
    }
    final String normalized = p.posix.normalize(value);
    if (normalized.isEmpty || normalized == '.') {
      return '/';
    }
    return normalized.startsWith('/') ? normalized : '/$normalized';
  }

  Future<String> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final Uri uri = Uri.parse('$baseUrl/api/auth/login');
    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': _userAgent,
      },
      body: jsonEncode(<String, String>{
        'username': username.trim(),
        'password': password,
      }),
    );

    final Map<String, dynamic> payload = _decodeEnvelope(response);
    final String token = (payload['token'] as String? ?? '').trim();
    if (token.isEmpty) {
      throw const AListError('登录成功，但返回的令牌为空。');
    }
    return token;
  }

  Future<List<AListEntry>> list({
    required String baseUrl,
    required String token,
    required String remotePath,
    Set<String>? allowedExtensions,
  }) async {
    final String normalizedPath = normalizePath(remotePath);
    final Uri uri = Uri.parse('$baseUrl/api/fs/list');
    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': token,
        'User-Agent': _userAgent,
      },
      body: jsonEncode(<String, dynamic>{
        'path': normalizedPath,
        'page': 1,
        'per_page': 500,
        'refresh': false,
      }),
    );

    final Map<String, dynamic> payload = _decodeEnvelope(response);
    final List<dynamic> content = (payload['content'] as List<dynamic>?) ?? [];
    final Set<String> allowedExts =
        (allowedExtensions ?? AppConstants.mediaExtensions.toSet())
            .map((String ext) => '.${ext.toLowerCase()}')
            .toSet();
    final List<AListEntry> entries = <AListEntry>[];

    for (final dynamic item in content) {
      if (item is! Map<String, dynamic>) continue;
      final bool isDir = item['is_dir'] == true;
      final String name = (item['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;

      if (!isDir) {
        final String ext = p.extension(name).toLowerCase();
        if (!allowedExts.contains(ext)) continue;
      }

      String fullPath = normalizePath((item['path'] as String? ?? '').trim());
      if (fullPath == '/' || fullPath == '.') {
        fullPath = normalizePath('$normalizedPath/$name');
      }

      final String modifiedRaw = (item['modified'] as String? ?? '').trim();
      entries.add(
        AListEntry(
          name: name,
          path: fullPath,
          isDir: isDir,
          size: (item['size'] as num?)?.toInt() ?? 0,
          modified: modifiedRaw.isEmpty ? null : DateTime.tryParse(modifiedRaw),
        ),
      );
    }

    entries.sort((AListEntry left, AListEntry right) {
      if (left.isDir != right.isDir) {
        return left.isDir ? -1 : 1;
      }
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });

    return entries;
  }

  Future<AListLink> getLink({
    required String baseUrl,
    required String token,
    required String remotePath,
  }) async {
    final Uri uri = Uri.parse('$baseUrl/api/fs/link');
    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': token,
        'User-Agent': _userAgent,
      },
      body: jsonEncode(<String, String>{'path': normalizePath(remotePath)}),
    );
    final Map<String, dynamic> payload = _decodeEnvelope(response);
    final String url = (payload['url'] as String? ?? '').trim();
    if (url.isEmpty) {
      throw const AListError('AList 返回的下载链接为空。');
    }

    final Map<String, String> headers = <String, String>{};
    final dynamic rawHeaders = payload['header'];
    if (rawHeaders is Map<String, dynamic>) {
      rawHeaders.forEach((String key, dynamic value) {
        if (key.trim().isEmpty || value == null) return;
        if (value is String) {
          final String v = value.trim();
          if (v.isNotEmpty) headers[key] = v;
          return;
        }
        if (value is List) {
          final List<String> vals = value
              .whereType<String>()
              .map((String item) => item.trim())
              .where((String item) => item.isNotEmpty)
              .toList();
          if (vals.isNotEmpty) {
            headers[key] = vals.join(', ');
          }
        }
      });
    }

    return AListLink(url: url, headers: headers);
  }

  AListLink buildWebDavInput({
    required String baseUrl,
    required String username,
    required String password,
    required String remotePath,
  }) {
    final String normalizedPath = normalizePath(remotePath);
    final Uri baseUri = Uri.parse(baseUrl);
    final String webdavPath =
        '${baseUri.path.replaceFirst(RegExp(r'/$'), '')}/dav$normalizedPath';
    final Uri inputUri = baseUri.replace(
      path: webdavPath,
      query: null,
      fragment: null,
    );

    final Map<String, String> headers = <String, String>{
      'User-Agent': _userAgent,
    };
    if (username.trim().isNotEmpty) {
      final String basic = base64Encode(utf8.encode('$username:$password'));
      headers['Authorization'] = 'Basic $basic';
    }

    return AListLink(url: inputUri.toString(), headers: headers);
  }

  Future<String> downloadToTemp({
    required String baseUrl,
    required String username,
    required String password,
    required String remotePath,
    void Function(int received, int total)? onProgress,
  }) async {
    final AListLink input = buildWebDavInput(
      baseUrl: baseUrl,
      username: username,
      password: password,
      remotePath: remotePath,
    );
    final String normalizedPath = normalizePath(remotePath);

    final http.Request request = http.Request('GET', Uri.parse(input.url));
    request.headers.addAll(input.headers);

    final http.StreamedResponse response = await _client.send(request);
    if (response.statusCode >= 400) {
      final String body = await response.stream.bytesToString();
      throw AListError(
        '下载失败：HTTP ${response.statusCode}${body.trim().isEmpty ? '' : ' - ${body.trim()}'}',
      );
    }

    final Directory tempDir = await getTemporaryDirectory();
    final Directory outDir = Directory(
      p.join(tempDir.path, 'caption_trans', 'alist'),
    );
    await outDir.create(recursive: true);

    String fileName = p.basename(normalizedPath);
    if (fileName.isEmpty || fileName == '/' || fileName == '.') {
      fileName = 'alist_media_${DateTime.now().millisecondsSinceEpoch}.bin';
    }
    final String outputPath = p.join(
      outDir.path,
      '${DateTime.now().microsecondsSinceEpoch}_$fileName',
    );
    final File outFile = File(outputPath);
    final IOSink sink = outFile.openWrite();

    int received = 0;
    final int total = response.contentLength ?? -1;
    try {
      await for (final List<int> chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    return outputPath;
  }

  Future<void> ensureRemoteDir({
    required String baseUrl,
    required String token,
    required String remoteDir,
  }) async {
    final String normalized = normalizePath(remoteDir);
    if (normalized == '/') return;

    final List<String> parts = normalized
        .split('/')
        .where((String part) => part.isNotEmpty)
        .toList();
    String current = '';
    for (final String part in parts) {
      current = normalizePath('$current/$part');
      try {
        await _mkdir(baseUrl: baseUrl, token: token, remoteDir: current);
      } on AListError catch (error) {
        if (_isRemoteExistsError(error)) {
          continue;
        }
        final bool exists = await _isDir(
          baseUrl: baseUrl,
          token: token,
          remotePath: current,
        );
        if (!exists) rethrow;
      }
    }
  }

  Future<void> uploadLocalFile({
    required String baseUrl,
    required String token,
    required String localPath,
    required String remotePath,
    void Function(double percent)? onProgress,
  }) async {
    final File file = File(localPath);
    if (!await file.exists()) {
      throw const AListError('本地文件不存在。');
    }

    final int size = await file.length();
    final int modifiedMillis =
        (await file.lastModified()).millisecondsSinceEpoch;
    final String normalizedPath = normalizePath(remotePath);
    int sent = 0;

    final http.StreamedRequest request = http.StreamedRequest(
      'PUT',
      Uri.parse('$baseUrl/api/fs/put'),
    );
    request.contentLength = size;
    request.headers.addAll(<String, String>{
      'Authorization': token,
      'User-Agent': _userAgent,
      'File-Path': Uri.encodeComponent(normalizedPath),
      'Content-Type': 'application/octet-stream',
      'Overwrite': 'true',
      'Last-Modified': '$modifiedMillis',
    });

    final Stream<List<int>> stream = file.openRead().map((List<int> chunk) {
      sent += chunk.length;
      if (size > 0) {
        onProgress?.call((sent / size) * 100);
      }
      return chunk;
    });
    await request.sink.addStream(stream);
    await request.sink.close();

    final http.StreamedResponse response = await _client.send(request);
    final String body = await response.stream.bytesToString();
    if (response.statusCode >= 400) {
      throw AListError(
        'HTTP ${response.statusCode}：${body.trim().isEmpty ? '上传失败。' : body.trim()}',
      );
    }

    final dynamic decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const AListError('上传响应数据格式不正确。');
    }
    final int code = (decoded['code'] as num?)?.toInt() ?? -1;
    if (code != 200) {
      final String message = (decoded['message'] as String? ?? '').trim();
      throw AListError(message.isNotEmpty ? message : 'AList 返回错误码：$code。');
    }
    onProgress?.call(100);
  }

  Future<void> _mkdir({
    required String baseUrl,
    required String token,
    required String remoteDir,
  }) async {
    final Uri uri = Uri.parse('$baseUrl/api/fs/mkdir');
    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': token,
        'User-Agent': _userAgent,
      },
      body: jsonEncode(<String, String>{'path': normalizePath(remoteDir)}),
    );
    _decodeEnvelope(response);
  }

  Future<bool> _isDir({
    required String baseUrl,
    required String token,
    required String remotePath,
  }) async {
    final Uri uri = Uri.parse('$baseUrl/api/fs/get');
    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': token,
        'User-Agent': _userAgent,
      },
      body: jsonEncode(<String, String>{'path': normalizePath(remotePath)}),
    );
    final Map<String, dynamic> payload = _decodeEnvelope(response);
    return payload['is_dir'] == true;
  }

  bool _isRemoteExistsError(AListError error) {
    final String message = error.message.toLowerCase();
    return message.contains('exists') ||
        message.contains('file exists') ||
        error.message.contains('已存在');
  }

  Map<String, dynamic> _decodeEnvelope(http.Response response) {
    if (response.statusCode >= 400) {
      throw AListError(
        'HTTP ${response.statusCode}：${response.body.trim().isEmpty ? '请求失败。' : response.body.trim()}',
      );
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const AListError('响应数据格式不正确。');
    }

    final int code = (decoded['code'] as num?)?.toInt() ?? -1;
    final String message = (decoded['message'] as String? ?? '').trim();
    if (code != 200) {
      throw AListError(message.isNotEmpty ? message : 'AList 返回错误码：$code。');
    }

    final dynamic data = decoded['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return <String, dynamic>{};
  }
}
