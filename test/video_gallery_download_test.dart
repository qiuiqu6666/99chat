import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_video_utils.dart';

void main() {
  late Directory directory;
  late HttpServer server;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gallery-download-test-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });
  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });
  test('downloads remote bytes with exact signed query and headers', () async {
    server.listen((request) async {
      expect(request.uri.query, 'signature=a%2Fb');
      expect(request.headers.value('x-media-test'), 'ok');
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.contentLength = 4;
      request.response.add([1, 2, 3, 4]);
      await request.response.close();
    });
    final file = await downloadVideoForGallery(
      'http://127.0.0.1:${server.port}/token?signature=a%2Fb', directory,
      headers: {'x-media-test': 'ok'});
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
    expect(file.path, endsWith('.mp4'));
  });
  for (final status in [200, 403, 410, 206]) {
    test('rejects JSON or invalid HTTP status $status', () async {
      server.listen((request) async {
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"error":"not a video"}');
        await request.response.close();
      });
      await expectLater(downloadVideoForGallery(
        'http://127.0.0.1:${server.port}/token', directory), throwsA(isA<HttpException>()));
      expect(await directory.list().toList(), isEmpty);
    });
  }
  test('empty media body is rejected and removed', () async {
    server.listen((request) async {
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.contentLength = 0;
      await request.response.close();
    });
    await expectLater(downloadVideoForGallery(
      'http://127.0.0.1:${server.port}/token', directory), throwsA(isA<HttpException>()));
    expect(await directory.list().toList(), isEmpty);
  });
}
