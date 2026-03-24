import 'package:caption_trans/services/alist/alist_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AListService.normalizeBaseUrl', () {
    final service = AListService();

    test('plain root url', () {
      final target = service.normalizeBaseUrl('http://localhost:5244');
      expect(target.baseUrl, 'http://localhost:5244');
      expect(target.suggestedPath, '/');
    });

    test('webdav root url', () {
      final target = service.normalizeBaseUrl('http://localhost:5244/dav');
      expect(target.baseUrl, 'http://localhost:5244');
      expect(target.suggestedPath, '/');
    });

    test('webdav mounted path', () {
      final target = service.normalizeBaseUrl('http://localhost:5244/dav/115');
      expect(target.baseUrl, 'http://localhost:5244');
      expect(target.suggestedPath, '/115');
    });

    test('subpath deployment', () {
      final target = service.normalizeBaseUrl(
        'http://localhost:5244/alist/dav/115/movies',
      );
      expect(target.baseUrl, 'http://localhost:5244/alist');
      expect(target.suggestedPath, '/115/movies');
    });

    test('api url', () {
      final target = service.normalizeBaseUrl('http://localhost:5244/api');
      expect(target.baseUrl, 'http://localhost:5244');
      expect(target.suggestedPath, '/');
    });
  });

  group('AListService.normalizePath', () {
    final service = AListService();

    test('adds root slash when missing', () {
      expect(service.normalizePath('115/nana'), '/115/nana');
    });

    test('normalizes dot segments', () {
      expect(service.normalizePath('/115/./nana/../movies'), '/115/movies');
    });
  });

  group('AListService.buildWebDavInput', () {
    final service = AListService();

    test('builds root webdav url with basic auth', () {
      final link = service.buildWebDavInput(
        baseUrl: 'http://localhost:5244',
        username: 'user',
        password: 'pass',
        remotePath: '/115/nana/demo.mp4',
      );

      expect(link.url, 'http://localhost:5244/dav/115/nana/demo.mp4');
      expect(link.headers['Authorization'], 'Basic dXNlcjpwYXNz');
      expect(link.headers['User-Agent'], isNotEmpty);
    });

    test('builds subpath webdav url', () {
      final link = service.buildWebDavInput(
        baseUrl: 'http://localhost:5244/alist',
        username: '',
        password: '',
        remotePath: '/115/nana/demo.mp4',
      );

      expect(link.url, 'http://localhost:5244/alist/dav/115/nana/demo.mp4');
      expect(link.headers.containsKey('Authorization'), isFalse);
    });
  });
}
