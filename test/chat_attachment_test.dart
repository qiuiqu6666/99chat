import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/chat_attachment_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment_task.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_service_io.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_transfer.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_external_message_sender.dart';
import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_diagnostics.dart';

const target = ChatAttachmentTarget(isGroup: false, id: 'bob');
const attachment = ChatAttachment(
    attachmentId: 'att',
    referenceId: 'ref',
    kind: 'file',
    name: 'sample.bin',
    sizeBytes: 10,
    mimeType: 'application/octet-stream');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late ChatAttachmentStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('chat-attachment-test-');
    store = ChatAttachmentStore(rootProvider: () async => root);
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('history video without wire cover ID fetches and persists server cover',
      () async {
    const historical = ChatAttachment(
        attachmentId: 'att',
        referenceId: 'ref',
        kind: 'video',
        name: 'old.mp4',
        sizeBytes: 10,
        mimeType: 'video/mp4');
    final api = _FakeApi();
    final service = _service(api, store,
        transfer: ChatAttachmentTransfer(
            api: api, storageDio: _dio((o) => _bytes(o, [1, 2, 3]))));
    final cover = await service.videoThumbnail(historical);
    expect(await File(cover!).readAsBytes(), [1, 2, 3]);
    expect(api.accessCount, 1);
    service.dispose();
    final reopenedStore = ChatAttachmentStore(rootProvider: () async => root);
    final reopened = _service(api, reopenedStore);
    expect(await reopened.videoThumbnail(historical), cover);
    expect(api.accessCount, 1);
    reopened.dispose();
  });

  for (final contentType in <String?>[null, 'image/jpeg']) {
    test('cover upload preserves signed content type $contentType', () async {
      final source = await File('${root.path}/original.mp4')
          .writeAsBytes(List.filled(10, 7));
      final cover =
          await File('${root.path}/cover.jpg').writeAsBytes([1, 2, 3]);
      final api = _CoverApi(contentType);
      var puts = 0;
      final storage = _dio((o) async {
        puts++;
        expect(o.contentType, contentType);
        expect(o.headers['Content-Length'], 3);
        final bytes = await (o.data as Stream<List<int>>)
            .expand((chunk) => chunk)
            .toList();
        expect(bytes, [1, 2, 3]);
        return Response(requestOptions: o, statusCode: 200, data: '');
      });
      final service = _service(api, store,
          transfer: _FakeTransfer(api, storageDio: storage),
          dispatch: (task) async {
        return const ExternalMessageSendResult(
            state: ExternalMessageSendState.succeeded);
      });
      await service.start(
          path: source.path,
          target: target,
          nativeMessageKind: 'video',
          snapshotPath: cover.path,
          width: 100,
          height: 100);
      expect(puts, 1);
      expect(api.nativeSendCount, 1);
      expect(api.coverCompleted, isTrue);
      service.dispose();
    });
  }

  test('native video gate fails closed before upload or custom dispatch',
      () async {
    final source =
        await File('${root.path}/v.mp4').writeAsBytes(List.filled(10, 7));
    final api = _FakeApi()..nativeEnabled = false;
    final service = _service(api, store,
        dispatch: (_) => throw StateError('custom video forbidden'));
    await service.start(
        path: source.path, target: target, nativeMessageKind: 'video');
    expect(api.nativeSendCount, 0);
    expect(service.tasksFor(target).single.uploadId, isNull);
    expect(service.tasksFor(target).single.state, 'failed');
    service.dispose();
  });

  test('native video posts stable IDs and never invokes custom dispatch',
      () async {
    final source =
        await File('${root.path}/v.mp4').writeAsBytes(List.filled(10, 7));
    final api = _CoverApi(null);
    final cover = await File('${root.path}/cover.jpg').writeAsBytes([1, 2, 3]);
    final transfer = _FakeTransfer(api,
        storageDio: _dio(
            (o) => Response(requestOptions: o, statusCode: 200, data: '')));
    final service = _service(api, store,
        transfer: transfer,
        dispatch: (_) => throw StateError('custom video forbidden'));
    await service.start(
        path: source.path,
        target: target,
        nativeMessageKind: 'video',
        snapshotPath: cover.path,
        width: 100,
        height: 100,
        durationMs: 120000);
    expect(api.nativeSendCount, 1);
    expect(api.lastNativeDurationMs, 120000);
    expect(service.tasksFor(target), isEmpty);
    service.dispose();
  });

  test('native result validates identity and cannot accept upload-only success',
      () {
    final task = _task('/unused')
      ..attachmentId = 'att'
      ..referenceId = 'ref';
    final data = {
      'clientOperationId': task.taskId,
      'attachmentId': 'att',
      'referenceId': 'ref',
      'status': 'sent'
    };
    expect(ChatAttachmentService.nativeVideoResult(task, data).state,
        ExternalMessageSendState.outcomeUnknown);
    expect(
        () => ChatAttachmentService.nativeVideoResult(
            task, {...data, 'referenceId': 'other'}),
        throwsA(isA<ChatAttachmentException>()));
    expect(
        ChatAttachmentService.nativeVideoResult(task, {
          ...data,
          'messageType': 'TIMVideoFileElem',
          'msgKey': 'key'
        }).succeeded,
        isTrue);
  });

  test('restart resolves native outcome by GET without sending again',
      () async {
    final task = ChatAttachmentTask.fromJson({
      ..._task('/unused').toJson(),
      'kind': 'video',
      'nativeMessageKind': 'video',
      'attachmentId': 'att',
      'referenceId': 'ref',
      'state': 'outcomeUnknown'
    });
    await store.saveTask('alice', task.taskId, task.toJson());
    final api = _FakeApi()
      ..nativeStatusData = {
        'clientOperationId': task.taskId,
        'attachmentId': 'att',
        'referenceId': 'ref',
        'status': 'sent',
        'messageType': 'TIMVideoFileElem',
        'msgKey': 'confirmed'
      };
    final service = _service(api, store);
    final settled = Completer<void>();
    var seenPending = false;
    service.addListener(() {
      if (service.tasksFor(target).isNotEmpty) seenPending = true;
      if (seenPending &&
          service.tasksFor(target).isEmpty &&
          !settled.isCompleted) settled.complete();
    });
    await service.load();
    await settled.future.timeout(const Duration(seconds: 5));
    expect(api.nativeSendCount, 0);
    service.dispose();
  });

  test('strict byte boundaries and recording versus audio file', () {
    const policy = ChatAttachmentPolicy();
    expect(policy.sendEnabled, isFalse);
    expect(policy.uploadEnabled, isFalse);
    for (final kind in ['image', 'sound']) {
      expect(policy.routesToBackend(29360128, kind), isFalse);
      expect(policy.routesToBackend(29360129, kind), isTrue);
    }
    for (final kind in ['video', 'file']) {
      expect(policy.routesToBackend(100000000, kind), isFalse);
      expect(policy.routesToBackend(104857600, kind), isFalse);
      expect(policy.routesToBackend(104857601, kind), isTrue);
    }
    expect(policy.routesToBackend(30 * 1024 * 1024, 'sound'), isTrue);
    expect(policy.routesToBackend(30 * 1024 * 1024, 'file'), isFalse);
  });

  test(
      'backend lower native cap takes precedence and incomplete policy fails closed',
      () {
    final json = _policyJson()
      ..['nativeMaxBytes'] = {
        'image': 10,
        'sound': 20,
        'video': 30,
        'file': 40
      };
    final policy = ChatAttachmentPolicy.fromJson(json);
    expect(policy.routesToBackend(31, 'video'), isTrue);
    expect(() => ChatAttachmentPolicy.fromJson({}),
        throwsA(isA<ChatAttachmentException>()));
    expect(ChatAttachmentPolicy.fromJson(_policyJson()).sendEnabled, isFalse);
  });

  test('wire payload contains stable IDs only and rejects unknown protocol',
      () {
    final json = attachment.toJson();
    expect(ChatAttachment.tryParse(jsonEncode(json))!.referenceId, 'ref');
    expect(json.keys, isNot(contains('url')));
    expect(json.keys, isNot(contains('path')));
    expect(
        ChatAttachment.tryParse(jsonEncode({...json, 'version': 2})), isNull);
    expect(ChatAttachment.tryParse(jsonEncode({...json, 'referenceId': ''})),
        isNull);
    expect(ChatAttachment.tryParse(jsonEncode({...json, 'sizeBytes': -1})),
        isNull);
    expect(ChatAttachment.tryParse('{invalid'), isNull);
    expect(target.toJson(), {'conversationType': 'c2c', 'peerUserId': 'bob'});
    expect(const ChatAttachmentTarget(isGroup: true, id: '@g').toJson(),
        {'conversationType': 'group', 'groupId': '@g'});
  });

  test(
      'API uses JWT client route, protocol header and strict response envelope',
      () async {
    final api = ChatAttachmentApi(dio: _dio((o) {
      expect(o.path, '/me/chat/attachment-policy');
      expect(o.headers['X-Chat-Attachment-Protocol-Version'], '1');
      return _json(o, _policyJson());
    }));
    expect((await api.policy()).routingThresholdBytes, 104857600);
    final malformed = ChatAttachmentApi(
        dio: _dio((o) => Response(
            requestOptions: o,
            statusCode: 200,
            data: {'uploadEnabled': true})));
    await expectLater(malformed.policy(), throwsA(_code('INVALID_RESPONSE')));
  });

  test('API preserves string errors and retryAfter', () async {
    final api = ChatAttachmentApi(dio: _dio((o) {
      throw DioError(
          requestOptions: o,
          type: DioErrorType.response,
          response: Response(
              requestOptions: o,
              statusCode: 429,
              headers: Headers.fromMap({
                'retry-after': ['7']
              }),
              data: {'code': 'RATE_LIMITED', 'message': 'slow down'}));
    }));
    await expectLater(
        api.policy(),
        throwsA(isA<ChatAttachmentException>()
            .having((e) => e.code, 'code', 'RATE_LIMITED')
            .having((e) => e.retryAfter, 'retryAfter',
                const Duration(seconds: 7))));
  });

  test(
      'accepts a complete direct policy DTO as well as the documented envelope',
      () async {
    final api = ChatAttachmentApi(
        dio: _dio((o) => Response(requestOptions: o, statusCode: 200, data: {
              ..._policyJson(),
              'uploadEnabled': false,
              'sendEnabled': false
            })));
    final policy = await api.policy();
    expect(policy.routingThresholdBytes, 104857600);
    expect(policy.uploadEnabled, isFalse);
    expect(policy.sendEnabled, isFalse);
  });

  test('decodes JSON text when a server uses a non-JSON content type',
      () async {
    final api = ChatAttachmentApi(
        dio: _dio((o) => Response(
            requestOptions: o,
            statusCode: 200,
            data: jsonEncode({'code': 0, 'data': _policyJson()}))));
    expect((await api.policy()).nativeMaxBytes['file'], 104857600);
  });

  test('explicit business failure cannot be mistaken for a direct DTO',
      () async {
    final api = ChatAttachmentApi(
        dio: _dio((o) => Response(requestOptions: o, statusCode: 200, data: {
              'code': 'ATTACHMENT_DISABLED',
              'data': {..._policyJson(), 'sendEnabled': true}
            })));
    await expectLater(api.policy(), throwsA(_code('ATTACHMENT_DISABLED')));
  });

  test('HTTP 200 HTML is a format error rather than an enabled policy',
      () async {
    final api = ChatAttachmentApi(
        dio: _dio((o) => Response(
            requestOptions: o,
            statusCode: 200,
            data: '<html>Gateway page</html>')));
    await expectLater(
        api.policy(),
        throwsA(isA<ChatAttachmentException>()
            .having((e) => e.code, 'code', 'INVALID_RESPONSE')
            .having((e) => e.userMessage, 'message', contains('有效 JSON'))));
  });

  test('reference is idempotent and scoped to the upload target', () async {
    final api = ChatAttachmentApi(dio: _dio((o) {
      expect(o.path, '/me/chat/attachments/att/references');
      expect(o.data, {
        'clientOperationId': 'operation',
        'conversationType': 'c2c',
        'peerUserId': 'bob'
      });
      return _json(o, {'referenceId': 'ref'});
    }));
    expect(await api.reference('att', target, 'operation'), 'ref');
  });

  test(
      'signed grants reject unsafe URLs and never forward business credentials',
      () {
    for (final url in [
      'http://oss.test/a',
      'file:///secret',
      'https://user:pw@oss.test/a'
    ]) {
      expect(() => ChatAttachmentTransfer.signedUrl({'url': url}),
          throwsA(_code('INVALID_RESPONSE')));
    }
    final headers = ChatAttachmentTransfer.signedHeaders({
      'headers': {
        'Authorization': 'jwt',
        'Cookie': 'secret',
        'X-Device-Id': 'device',
        'X-App-Version': '3',
        'Content-Type': 'image/jpeg'
      }
    });
    expect(headers, {'Content-Type': 'image/jpeg'});
  });

  test('full local copy opens without access API even after cloud removal',
      () async {
    final file = await store.downloadFile('alice', 'att', 'sample.bin');
    await file.writeAsBytes(List.generate(10, (i) => i));
    await store.registerLocal('alice', 'att', file, expectedSize: 10);
    final api = _FakeApi()..gone = true;
    final service = _service(api, store);
    expect(await service.resolveFile(attachment), file.path);
    expect((await service.playback(attachment)).local, isTrue);
    expect(api.accessCount, 0);
    service.dispose();
  });

  test(
      'truncated, partial and other-account files never count as local originals',
      () async {
    final file = await store.downloadFile('alice', 'att', '../sample.bin');
    expect(file.path, startsWith((await store.accountDirectory('alice')).path));
    await file.writeAsBytes(List.filled(10, 1));
    await store.registerLocal('alice', 'att', file, expectedSize: 10);
    expect(await store.localFile('bob', 'att', expectedSize: 10), isNull);
    await file.writeAsBytes([1]);
    expect(await store.localFile('alice', 'att', expectedSize: 10), isNull);
    final partial =
        await File('${file.path}.part').writeAsBytes(List.filled(10, 1));
    await expectLater(
        store.registerLocal('alice', 'att', partial, expectedSize: 10),
        throwsA(_code('LOCAL_FILE_MISSING')));
    final service = _service(_FakeApi()..gone = true, store);
    await expectLater(
        service.resolveFile(attachment), throwsA(_code('ATTACHMENT_GONE')));
    service.dispose();
  });

  test(
      'download resumes only matching Range and persists a complete local file',
      () async {
    final dest = await store.downloadFile('alice', 'att', attachment.name);
    await File('${dest.path}.part').writeAsBytes([0, 1, 2, 3]);
    final api = _FakeApi();
    final storage = _dio((o) {
      expect(o.headers['Range'], 'bytes=4-');
      expect(o.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')));
      return _bytes(o, [4, 5, 6, 7, 8, 9], status: 206, range: 'bytes 4-9/10');
    });
    final service = _service(api, store,
        transfer: ChatAttachmentTransfer(api: api, storageDio: storage));
    final path = await service.resolveFile(attachment);
    expect(await File(path).readAsBytes(), List.generate(10, (i) => i));
    expect(api.accessCount, 1);
    expect(await service.localPath(attachment), path);
    expect(await File('$path.part').exists(), isFalse);
    service.dispose();
  });

  test('server ignoring Range restarts instead of appending a duplicate',
      () async {
    final dest = await store.downloadFile('alice', 'att', attachment.name);
    await File('${dest.path}.part').writeAsBytes([0, 1]);
    final api = _FakeApi();
    final service = _service(api, store,
        transfer: ChatAttachmentTransfer(
            api: api,
            storageDio: _dio((o) => _bytes(o, List.generate(10, (i) => i)))));
    expect(await File(await service.resolveFile(attachment)).length(), 10);
    service.dispose();
  });

  test('wrong Range never registers a corrupt cache entry', () async {
    final dest = await store.downloadFile('alice', 'att', attachment.name);
    await File('${dest.path}.part').writeAsBytes([0, 1]);
    final api = _FakeApi();
    final service = _service(api, store,
        transfer: ChatAttachmentTransfer(
            api: api,
            storageDio: _dio((o) => _bytes(o, [5, 6, 7, 8, 9],
                status: 206, range: 'bytes 5-9/10'))));
    await expectLater(
        service.resolveFile(attachment), throwsA(_code('INVALID_RESPONSE')));
    expect(await service.localPath(attachment), isNull);
    service.dispose();
  });

  test('account switch while requesting access discards the returned grant',
      () async {
    var owner = 'alice';
    final api = _FakeApi()
      ..onAccess = () {
        owner = 'bob';
      };
    final service = ChatAttachmentService(
        api: api,
        store: store,
        ownerProvider: () => owner,
        generationProvider: () => 1);
    await expectLater(
        service.resolveFile(attachment), throwsA(_code('SESSION_CHANGED')));
    service.dispose();
  });

  test('multipart uses confirmed OSS sizes and bounded streams, then completes',
      () async {
    final source = await File('${root.path}/source.bin')
        .writeAsBytes(List.generate(10, (i) => i));
    final task = _task(source.path);
    final parts = <int, List<int>>{};
    var initialized = 0;
    var metadataReads = 0;
    var expiredGrant = false;
    final signedRequests = <int, int>{};
    final api = ChatAttachmentApi(dio: _dio((o) {
      if (o.path.endsWith('/uploads')) {
        initialized++;
        expect(o.data['clientUploadKey'], task.taskId);
        expect(o.data['peerUserId'], 'bob');
        expect(o.data.containsKey('durationMs'), isFalse);
        return _json(o, {
          'uploadId': 'up',
          'attachmentId': 'att',
          'partSizeBytes': 4,
          'expectedPartCount': 3
        });
      }
      if (o.path.endsWith('/part-urls')) {
        final number = o.data['partNumbers'].single as int;
        signedRequests[number] = (signedRequests[number] ?? 0) + 1;
        return _json(o, {
          'parts': [
            {
              'partNumber': number,
              'method': 'PUT',
              'url': 'https://oss.test/$number'
            }
          ]
        });
      }
      if (o.path.endsWith('/complete')) {
        expect(o.data, isEmpty);
        return _json(o, {'attachmentId': 'att', 'status': 'ready'});
      }
      if (o.path.endsWith('/attachments/att')) {
        metadataReads++;
        return _json(o, {
          'attachmentId': 'att',
          'status': 'ready',
          'sizeBytes': 10,
          'expiresAt':
              DateTime.now().add(const Duration(days: 30)).toIso8601String()
        });
      }
      return _json(o, {
        'status': 'uploading',
        'hasMore': false,
        'parts': [
          {'partNumber': 1, 'sizeBytes': 4},
          {'partNumber': 2, 'sizeBytes': 1}
        ]
      });
    }));
    final storage = _dio((o) async {
      expect(o.method, 'PUT');
      expect(o.data, isA<Stream<List<int>>>());
      expect(o.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')));
      final data =
          await (o.data as Stream<List<int>>).expand((e) => e).toList();
      expect(data.length, o.headers['Content-Length']);
      if (o.uri.pathSegments.last == '2' && !expiredGrant) {
        expiredGrant = true;
        throw DioError(
            requestOptions: o,
            type: DioErrorType.response,
            response: Response(requestOptions: o, statusCode: 403));
      }
      parts[int.parse(o.uri.pathSegments.last)] = data;
      return Response(requestOptions: o, statusCode: 200);
    });
    final transfer = ChatAttachmentTransfer(api: api, storageDio: storage);
    await transfer.upload(task,
        cancelToken: CancelToken(),
        checkSession: () {},
        persist: () async {},
        onProgress: (_) {});
    expect(initialized, 1);
    expect(metadataReads, 1);
    expect(signedRequests, {2: 2, 3: 1});
    expect(parts, {
      2: [4, 5, 6, 7],
      3: [8, 9]
    });
    expect(task.state, 'ready');
    expect(task.expiresAt!.difference(DateTime.now()).inDays,
        inInclusiveRange(29, 30));
  });

  test('malformed upload initialization never poisons resumable task IDs',
      () async {
    final source =
        await File('${root.path}/source.bin').writeAsBytes(List.filled(10, 1));
    final task = _task(source.path);
    final api =
        ChatAttachmentApi(dio: _dio((o) => _json(o, {'uploadId': 'up'})));
    await expectLater(
        ChatAttachmentTransfer(api: api).upload(task,
            cancelToken: CancelToken(),
            checkSession: () {},
            persist: () async {},
            onProgress: (_) {}),
        throwsA(_code('INVALID_RESPONSE')));
    expect(task.uploadId, isNull);
    expect(task.attachmentId, isNull);
  });

  test('disabled policy leaves visible failure without uploading or sending',
      () async {
    final source =
        await File('${root.path}/source.bin').writeAsBytes(List.filled(10, 1));
    final api = _FakeApi()..enabled = false;
    var sends = 0;
    final service = _service(api, store, dispatch: (_) async {
      sends++;
      return const ExternalMessageSendResult(
          state: ExternalMessageSendState.succeeded);
    });
    await service.start(
        path: source.path, target: target, nativeMessageKind: 'file');
    final task = service.tasksFor(target).single;
    expect(task.state, 'failed');
    expect(task.error, '大附件发送暂未开放');
    expect(task.uploadId, isNull);
    expect(sends, 0);
    expect((await store.tasks('alice')).single['error'], task.error);
    api.enabled = true;
    await service.resume(task);
    expect(sends, 1);
    expect(service.tasksFor(target), isEmpty);
    service.dispose();
  });

  test('HTTP 200 with incompatible policy leaves a visible parse failure',
      () async {
    final source =
        await File('${root.path}/source.bin').writeAsBytes(List.filled(10, 1));
    final api =
        ChatAttachmentApi(dio: _dio((o) => _json(o, {'uploadEnabled': true})));
    final service = ChatAttachmentService(
        api: api,
        store: store,
        transfer: _FakeTransfer(api),
        ownerProvider: () => 'alice',
        generationProvider: () => 1,
        platformSupported: () => true,
        dispatch: (_) async => throw StateError('must not dispatch'));
    await service.start(
        path: source.path, target: target, nativeMessageKind: 'file');
    final task = service.tasksFor(target).single;
    expect(task.error, '附件大小策略不兼容');
    expect(task.state, 'failed');
    expect(task.uploadId, isNull);
    service.dispose();
  });

  test('task is observable while the policy request is still pending',
      () async {
    final source =
        await File('${root.path}/source.bin').writeAsBytes(List.filled(10, 1));
    final response = Completer<Response<dynamic>>();
    final entered = Completer<RequestOptions>();
    final api = ChatAttachmentApi(dio: _dio((o) {
      entered.complete(o);
      return response.future;
    }));
    final service = ChatAttachmentService(
        api: api,
        store: store,
        transfer: _FakeTransfer(api),
        ownerProvider: () => 'alice',
        generationProvider: () => 1,
        platformSupported: () => true);
    final send = service.start(
        path: source.path, target: target, nativeMessageKind: 'file');
    final request = await entered.future;
    expect(service.tasksFor(target).single.state, 'preparing');
    response.complete(_json(request, _policyJson()));
    await send;
    expect(service.tasksFor(target).single.state, 'failed');
    service.dispose();
  });

  test(
      'policy diagnostics expose flags and capability without credentials or IDs',
      () {
    final previous = debugPrint;
    final lines = <String>[];
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) lines.add(message);
    };
    try {
      ChatAttachmentDiagnostics.policyResponse(status: 200, headers: {
        'Authorization': 'secret-jwt',
        'X-Device-Id': 'secret-device',
        'X-Client-Platform': 'android',
        'X-App-Version': '3.0.2',
        'X-App-Version-Code': '7',
        'X-Chat-Attachment-Protocol-Version': '1',
      }, payload: {
        ..._policyJson(),
        'uploadEnabled': false,
        'sendEnabled': false,
        'url': 'secret-url',
        'userId': 'secret-user'
      });
    } finally {
      debugPrint = previous;
    }
    final log = lines.single;
    expect(log, contains('"uploadEnabled":false'));
    expect(log, contains('"platform":"android"'));
    expect(log, contains('"buildNumber":"7"'));
    expect(log, contains('"deviceIdPresent":true'));
    expect(log, isNot(contains('secret')));
  });

  test('unknown IM result survives restart and cannot be retried or cancelled',
      () async {
    final source =
        await File('${root.path}/source.bin').writeAsBytes(List.filled(10, 1));
    final api = _FakeApi();
    var sends = 0;
    final service = _service(api, store, dispatch: (task) async {
      sends++;
      expect(task.message.referenceId, 'ref');
      return const ExternalMessageSendResult(
          state: ExternalMessageSendState.outcomeUnknown);
    });
    await service.start(
        path: source.path, target: target, nativeMessageKind: 'file');
    final pending = service.tasksFor(target).single;
    expect(pending.state, 'outcomeUnknown');
    await service.resume(pending);
    await service.cancel(pending);
    expect(sends, 1);
    expect(api.cancelCount, 0);
    service.dispose();
    final restored = _service(api, store);
    await restored.load();
    expect(restored.tasksFor(target).single.state, 'outcomeUnknown');
    expect(restored.tasksFor(target).single.canResume, isFalse);
    await restored.observeSent(attachment);
    expect(restored.tasksFor(target), isEmpty);
    restored.dispose();
  });

  test('crash at dispatch boundary never replays a fresh message', () async {
    final task = _task('unused')..state = 'dispatching';
    await store.saveTask('alice', task.taskId, task.toJson());
    final service = _service(_FakeApi(), store);
    await service.load();
    expect(service.tasksFor(target).single.state, 'outcomeUnknown');
    service.dispose();
  });

  test('early IM confirmation wins over a later uncertain dispatch result',
      () async {
    final source =
        await File('${root.path}/source.bin').writeAsBytes(List.filled(10, 1));
    late ChatAttachmentService service;
    service = _service(_FakeApi(), store, dispatch: (task) async {
      await service.observeSent(task.message);
      return const ExternalMessageSendResult(
          state: ExternalMessageSendState.outcomeUnknown);
    });
    await service.start(
        path: source.path, target: target, nativeMessageKind: 'file');
    expect(service.tasksFor(target), isEmpty);
    expect((await store.tasks('alice')).single['state'], 'sent');
    service.dispose();
  });

  test(
      'known IM failure leaves retry ownership with the existing outbox bubble',
      () async {
    final source =
        await File('${root.path}/source.bin').writeAsBytes(List.filled(10, 1));
    final service = _service(_FakeApi(), store,
        dispatch: (_) async => const ExternalMessageSendResult(
            state: ExternalMessageSendState.failed));
    await service.start(
        path: source.path, target: target, nativeMessageKind: 'file');
    expect(service.tasksFor(target), isEmpty);
    expect((await store.tasks('alice')).single['state'], 'handedOff');
    service.dispose();
  });
}

Matcher _code(String code) =>
    isA<ChatAttachmentException>().having((e) => e.code, 'code', code);
Map<String, dynamic> _policyJson() => {
      'sizeComparison': 'strictGreaterThan',
      'routingThresholdBytes': 104857600,
      'nativeMaxBytes': {
        'image': 29360128,
        'sound': 29360128,
        'video': 104857600,
        'file': 104857600
      }
    };
Response<dynamic> _json(RequestOptions o, dynamic data) => Response(
    requestOptions: o,
    statusCode: 200,
    data: {'code': 0, 'message': 'ok', 'data': data});
Response<dynamic> _bytes(RequestOptions o, List<int> bytes,
        {int status = 200, String? range}) =>
    Response<ResponseBody>(
        requestOptions: o,
        statusCode: status,
        headers: Headers.fromMap({
          if (range != null) 'content-range': [range]
        }),
        data: ResponseBody(Stream.value(Uint8List.fromList(bytes)), status));
Dio _dio(FutureOr<Response<dynamic>> Function(RequestOptions) handler) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
    try {
      h.resolve(await handler(o));
    } catch (e) {
      h.reject(e is DioError ? e : DioError(requestOptions: o, error: e));
    }
  }));
  return dio;
}

ChatAttachmentTask _task(String path) => ChatAttachmentTask(
    taskId: 'task',
    ownerUserId: 'alice',
    target: target,
    sourcePath: path,
    name: attachment.name,
    kind: 'file',
    nativeMessageKind: 'file',
    mimeType: attachment.mimeType,
    sizeBytes: 10,
    createdAt: 1);
ChatAttachmentService _service(_FakeApi api, ChatAttachmentStore store,
        {ChatAttachmentTransfer? transfer,
        AttachmentMessageDispatch? dispatch}) =>
    ChatAttachmentService(
        api: api,
        store: store,
        transfer: transfer ?? _FakeTransfer(api),
        ownerProvider: () => 'alice',
        generationProvider: () => 1,
        platformSupported: () => true,
        dispatch: dispatch ??
            (_) async => const ExternalMessageSendResult(
                state: ExternalMessageSendState.succeeded));

class _FakeApi extends ChatAttachmentApi {
  bool gone = false, enabled = true, nativeEnabled = true;
  int nativeSendCount = 0;
  int? lastNativeDurationMs;
  String nativeSendStatus = 'sent';
  Map<String, dynamic>? nativeStatusData;
  @override
  Future<Map<String, dynamic>> nativeVideoStatus(String id,
          {CancelToken? cancelToken}) async =>
      nativeStatusData ?? {};
  int accessCount = 0, cancelCount = 0;
  void Function()? onAccess;
  @override
  Future<ChatAttachmentPolicy> policy({CancelToken? cancelToken}) async =>
      ChatAttachmentPolicy(
          sendEnabled: enabled,
          nativeVideoMessageEnabled: nativeEnabled,
          uploadEnabled: enabled,
          routingThresholdBytes: 1);
  @override
  Future<Map<String, dynamic>> sendNativeVideo(
      {required String attachmentId,
      required String referenceId,
      required String operationId,
      required ChatAttachmentTarget target,
      int? durationMs,
      CancelToken? cancelToken}) async {
    nativeSendCount++;
    lastNativeDurationMs = durationMs;
    return {
      'clientOperationId': operationId,
      'attachmentId': attachmentId,
      'referenceId': referenceId,
      'status': nativeSendStatus,
      'messageType': 'TIMVideoFileElem',
      if (target.isGroup) 'msgSeq': 12 else 'msgKey': 'native-key'
    };
  }

  @override
  Future<Map<String, dynamic>> access(ChatAttachment a, String purpose,
      {CancelToken? cancelToken}) async {
    accessCount++;
    onAccess?.call();
    if (gone) throw const ChatAttachmentException('ATTACHMENT_GONE', 'expired');
    return {'url': 'https://oss.test/file'};
  }

  @override
  Future<String> reference(
          String id, ChatAttachmentTarget target, String operationId,
          {CancelToken? cancelToken}) async =>
      'ref';
  @override
  Future<Map<String, dynamic>> cancel(String id) async {
    cancelCount++;
    return {};
  }
}

class _FakeTransfer extends ChatAttachmentTransfer {
  _FakeTransfer(ChatAttachmentApi api, {Dio? storageDio})
      : super(api: api, storageDio: storageDio);
  @override
  Future<void> upload(ChatAttachmentTask task,
      {required CancelToken cancelToken,
      required void Function() checkSession,
      required Future<void> Function() persist,
      required void Function(double) onProgress,
      int maxParallelParts = 2}) async {
    checkSession();
    task.uploadId = 'up';
    task.attachmentId = 'att';
    task.expiresAt = DateTime.now().add(const Duration(days: 30));
    task.state = 'ready';
    await persist();
  }
}

class _CoverApi extends _FakeApi {
  _CoverApi(this.contentType);
  final String? contentType;
  bool coverCompleted = false;
  @override
  Future<Map<String, dynamic>> thumbnailUpload(String id,
          {CancelToken? cancelToken}) async =>
      {
        'url': 'https://oss.test/cover',
        'headers': {if (contentType != null) 'Content-Type': contentType},
      };
  @override
  Future<Map<String, dynamic>> thumbnailComplete(String id,
          {CancelToken? cancelToken}) async =>
      {'thumbnailAttachmentId': 'cover-id', 'completed': coverCompleted = true};
}
