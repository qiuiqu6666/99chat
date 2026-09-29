import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/chat_attachment_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment_task.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_transfer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ChatAttachmentTask task;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('attachment-transport-');
    final source = await File('${directory.path}/sample.bin')
        .writeAsBytes(List.generate(10, (index) => index));
    task = ChatAttachmentTask(
        taskId: 'task',
        ownerUserId: 'alice',
        target: const ChatAttachmentTarget(isGroup: false, id: 'bob'),
        sourcePath: source.path,
        name: 'sample.bin',
        kind: 'file',
        nativeMessageKind: 'file',
        mimeType: 'application/octet-stream',
        sizeBytes: 10,
        createdAt: 1);
  });
  tearDown(() => directory.delete(recursive: true));

  for (final contentType in <String?>[null, 'application/octet-stream']) {
    test('wire preserves signed Content-Type: $contentType', () async {
      final storage = Dio();
      // Reproduce the Dio default that must not leak into a signed file PUT.
      expect(
          Options(method: 'PUT')
              .compose(storage.options, 'https://oss.test')
              .contentType,
          Headers.jsonContentType);
      var puts = 0;
      storage.httpClientAdapter = _Adapter((options, bytes) async {
        puts++;
        expect(options.method, 'PUT');
        expect(options.contentType, contentType);
        expect(
            options.headers.containsKey('content-type'), contentType != null);
        expect(options.headers['Content-Length'], 10);
        expect(options.headers['x-oss-meta-test'], 'signed-value');
        expect(options.headers.containsKey('Authorization'), isFalse);
        expect(options.headers.containsKey('Cookie'), isFalse);
        expect(options.followRedirects, isFalse);
        expect(bytes, List.generate(10, (index) => index));
        return ResponseBody.fromString('', 200);
      });
      await _upload(task, storage, headers: {
        if (contentType != null) 'CoNtEnT-TyPe': contentType,
        'x-oss-meta-test': 'signed-value',
        'Authorization': 'must-not-forward',
        'Cookie': 'must-not-forward',
      });
      expect(puts, 1);
      expect(task.state, 'ready');
      storage.close(force: true);
    });
  }

  test(
      'OSS signature failure is specific, not retried, and diagnostic is redacted',
      () async {
    final lines = <String>[];
    final originalPrint = debugPrint;
    debugPrint =
        (String? message, {int? wrapWidth}) => lines.add(message ?? '');
    addTearDown(() => debugPrint = originalPrint);
    var puts = 0;
    final storage = Dio()
      ..httpClientAdapter = _Adapter((options, bytes) async {
        puts++;
        return ResponseBody.fromString(
            '<Error><Code>SignatureDoesNotMatch</Code>'
            '<AccessKeyId>secret-key</AccessKeyId><Signature>secret-signature</Signature>'
            '<Resource>private-object-name</Resource></Error>',
            403,
            headers: {
              'content-type': ['application/xml']
            });
      });
    await expectLater(
        _upload(task, storage),
        throwsA(isA<ChatAttachmentException>().having(
            (error) => error.code, 'code', 'STORAGE_SIGNATURE_MISMATCH')));
    expect(puts, 1);
    expect(task.state, isNot('ready'));
    final log = lines.join('\n');
    expect(log, contains('SignatureDoesNotMatch'));
    expect(log, contains('"httpStatus":403'));
    for (final secret in [
      'secret-key',
      'secret-signature',
      'private-object-name',
      'https://'
    ]) {
      expect(log, isNot(contains(secret)));
    }
    storage.close(force: true);
  });

  test('expired storage token gets fresh grant and succeeds', () async {
    var puts = 0, grants = 0;
    final storage = Dio()
      ..httpClientAdapter = _Adapter((options, bytes) async {
        puts++;
        return puts == 1
            ? ResponseBody.fromString(
                '<Error><Code>ExpiredToken</Code></Error>', 403)
            : ResponseBody.fromString('', 200);
      });
    await _upload(task, storage, onGrant: () => grants++);
    expect(grants, 2);
    expect(puts, 2);
    expect(task.state, 'ready');
    storage.close(force: true);
  });

  test('non-XML HTTP failure preserves status without exposing response body',
      () async {
    final storage = Dio()
      ..httpClientAdapter = _Adapter((options, bytes) async =>
          ResponseBody.fromString('private proxy error body', 400));
    await expectLater(
        _upload(task, storage),
        throwsA(isA<ChatAttachmentException>()
            .having((error) => error.code, 'code', 'STORAGE_HTTP_ERROR')
            .having((error) => error.userMessage, 'message',
                contains('HTTP 400'))));
    storage.close(force: true);
  });
}

Future<void> _upload(ChatAttachmentTask task, Dio storage,
    {Map<String, dynamic> headers = const {}, void Function()? onGrant}) async {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    Map<String, dynamic> data;
    if (options.path.endsWith('/uploads')) {
      data = {
        'uploadId': 'up',
        'attachmentId': 'att',
        'partSizeBytes': 10,
        'expectedPartCount': 1
      };
    } else if (options.path.endsWith('/part-urls')) {
      onGrant?.call();
      data = {
        'parts': [
          {
            'partNumber': 1,
            'method': 'PUT',
            'url': 'https://oss.test/part?Signature=secret',
            'headers': headers
          }
        ]
      };
    } else if (options.path.endsWith('/complete')) {
      data = {
        'attachmentId': 'att',
        'status': 'ready',
        'sizeBytes': 10,
        'expiresAt':
            DateTime.now().add(const Duration(days: 30)).toIso8601String()
      };
    } else {
      data = {'status': 'uploading', 'parts': [], 'hasMore': false};
    }
    handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {'code': 0, 'data': data}));
  }));
  try {
    await ChatAttachmentTransfer(
            api: ChatAttachmentApi(dio: dio), storageDio: storage)
        .upload(task,
            cancelToken: CancelToken(),
            checkSession: () {},
            persist: () async {},
            onProgress: (_) {});
  } finally {
    dio.close(force: true);
  }
}

// Inspect the transport boundary after Dio's request composition and stream
// transformation. An onRequest mock alone would miss implicit wire headers.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions, List<int>) respond;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<dynamic>? cancelFuture) async {
    final bytes = await stream!.expand((chunk) => chunk).toList();
    return respond(options, bytes);
  }

  @override
  void close({bool force = false}) {}
}
