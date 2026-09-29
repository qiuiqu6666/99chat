import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/sync_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/sync_contract_support.dart';
import 'package:tencent_cloud_chat_demo/src/services/photo_sync_transfer.dart';
import 'support/sync_contract_harness.dart';

void main() {
  late SyncHarness h;
  late Directory temp;
  late File file;
  late Dio oss;
  var puts = 0;
  var current = true;
  final item = PhotoSyncItemPayload(
      localAssetId: 'asset',
      contentHash: 'hash',
      sizeBytes: 3,
      mediaType: 'IMAGE',
      mimeType: 'image/jpeg');
  Map<String, Object> receipt() => {
        'photoUuid': 'p1',
        'localAssetId': 'asset',
        'contentHash': 'hash',
        'sizeBytes': 3,
        'mediaType': 'IMAGE'
      };
  Object normal(RequestOptions request) {
    if (request.path.endsWith('/check'))
      return {
        'results': [
          {'status': 'NEED_UPLOAD'}
        ]
      };
    if (request.path.endsWith('/init-upload'))
      return {
        'uploadUuid': 'u1',
        'photoUuid': 'p1',
        'presignedPutUrl': 'https://storage.invalid/put'
      };
    if (request.path.endsWith('/complete')) return receipt();
    throw StateError(request.path);
  }

  Future<PhotoSyncTransferResult> run() =>
      PhotoSyncTransfer(h.api, retryDelay: Duration.zero).upload(
          sessionId: 's1',
          item: item,
          file: file,
          ossDio: oss,
          isCurrent: () => current);
  setUp(() async {
    h = SyncHarness();
    h.respond = normal;
    puts = 0;
    current = true;
    temp = await Directory.systemTemp.createTemp('sync-contract-');
    file = await File('${temp.path}/image.jpg').writeAsBytes([1, 2, 3]);
    oss = Dio();
    oss.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      puts++;
      handler.resolve(Response(requestOptions: request, statusCode: 200));
    }));
  });
  tearDown(() async {
    oss.close();
    h.dio.close();
    await temp.delete(recursive: true);
  });

  test(
      'ALREADY_COMMITTED accepts null upload fields and never PUTs or completes',
      () async {
    h.respond = (request) => request.path.endsWith('/init-upload')
        ? {
            ...receipt(),
            'uploadState': 'ALREADY_COMMITTED',
            'uploadUuid': null,
            'presignedPutUrl': null,
            'committedAt': 1750000000
          }
        : normal(request);
    expect(await run(), PhotoSyncTransferResult.alreadyCommitted);
    expect(h.at('/init-upload').single.data['acceptAlreadyCommitted'], isTrue);
    expect(puts, 0);
    expect(h.at('/complete'), isEmpty);
  });
  test('mismatching ALREADY_COMMITTED receipt is not saved as success',
      () async {
    h.respond = (request) => request.path.endsWith('/init-upload')
        ? {
            ...receipt(),
            'uploadState': 'ALREADY_COMMITTED',
            'contentHash': 'other'
          }
        : normal(request);
    await expectLater(run(), throwsA(isA<SyncContractException>()));
    expect(puts, 0);
  });
  test('legacy init shape remains compatible', () async {
    expect(await run(), PhotoSyncTransferResult.uploaded);
    expect(puts, 1);
    expect(h.at('/complete'), hasLength(1));
  });
  test('lost completion response retries the same UUID without uploading again',
      () async {
    var completions = 0;
    h.respond = (request) {
      if (request.path.endsWith('/complete') && completions++ == 0)
        throw lostResponse(request);
      return normal(request);
    };
    expect(await run(), PhotoSyncTransferResult.uploaded);
    expect(puts, 1);
    expect(h.at('/complete').map((r) => r.data['uploadUuid']), ['u1', 'u1']);
  });
  for (final code in ['CONTENT_MISMATCH', 'OSS_OBJECT_NOT_FOUND']) {
    test('$code performs one fresh init and reupload', () async {
      var completions = 0;
      h.respond = (request) {
        if (request.path.endsWith('/complete') && completions++ == 0) {
          throw contractError(request, code, status: 400);
        }
        return normal(request);
      };
      expect(await run(), PhotoSyncTransferResult.uploaded);
      expect(puts, 2);
      expect(h.at('/init-upload'), hasLength(2));
    });
  }
  test('permanent checksum failure is bounded and never marks success',
      () async {
    h.respond = (request) {
      if (request.path.endsWith('/complete')) {
        throw contractError(request, 'CONTENT_MISMATCH', status: 400);
      }
      return normal(request);
    };
    await expectLater(run(), throwsA(isA<DioError>()));
    expect(puts, 2);
    expect(h.at('/complete'), hasLength(2));
  });
  test('DEVICE_NOT_BOUND is not retried', () async {
    h.respond = (request) =>
        throw contractError(request, 'DEVICE_NOT_BOUND', status: 403);
    await expectLater(run(), throwsA(isA<DioError>()));
    expect(h.requests, hasLength(1));
    expect(puts, 0);
  });
  test('account change while init is pending prevents storage upload',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    h.respond = (request) async {
      if (request.path.endsWith('/init-upload')) {
        entered.complete();
        await release.future;
      }
      return normal(request);
    };
    final future = run();
    final assertion =
        expectLater(future, throwsA(isA<SyncContractException>()));
    await entered.future;
    current = false;
    release.complete();
    await assertion;
    expect(puts, 0);
    expect(h.at('/complete'), isEmpty);
  });
  test('wrong media type in completion receipt fails validation', () async {
    h.respond = (request) => request.path.endsWith('/complete')
        ? {...receipt(), 'mediaType': 'VIDEO'}
        : normal(request);
    await expectLater(run(), throwsA(isA<SyncContractException>()));
    expect(puts, 1);
  });
}
