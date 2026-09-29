// Controlled platform/API doubles; uses the real device-sync service and collector.
// Formal desired-behavior regressions. Oversize length is synthetic metadata, not a throughput benchmark.
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/device_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/photo_sync_collector.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

class SizeReportedVideoFile implements File {
  int streamOpens = 0;
  @override
  String get path => 'audit-video.mp4';
  @override
  Future<bool> exists() async => true;
  @override
  Future<int> length() async => 104857601;
  @override
  Stream<List<int>> openRead([int? start, int? end]) {
    streamOpens++;
    // Small synthetic content: proves the hash operation is entered despite
    // metadata exceeding the limit. Does not benchmark a real 100 MiB file.
    return Stream.value([97, 98, 99]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AuditVideoAsset extends AssetEntity {
  AuditVideoAsset(this.auditOrigin)
      : super(
            id: 'audit-video',
            typeInt: 2,
            width: 1920,
            height: 1080,
            duration: 10,
            createDateSecond: 1,
            modifiedDateSecond: 1);
  final File auditOrigin;
  @override
  Future<File?> get originFile async => auditOrigin;
  @override
  Future<String?> get mimeTypeAsync async => 'video/mp4';
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'audit-device-sync-owner';
  const photos = MethodChannel('com.fluttercandies/photo_manager');
  const contacts = MethodChannel('github.com/QuisApp/flutter_contacts');
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  late List<Interceptor> originalInterceptors;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await ApiClient.instance.saveToken('audit-local-token', userId: owner);
    originalInterceptors = ApiClient.instance.dio.interceptors.toList();
  });
  tearDown(() async {
    await DeviceSyncService.instance.clearForOwner(owner);
    ApiClient.instance.dio.interceptors
      ..clear()
      ..addAll(originalInterceptors);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(photos, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(contacts, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(permissions, null);
    await ApiClient.instance.clearToken();
    debugDefaultTargetPlatformOverride = null;
  });

  for (final failure in ['collection', 'partial-batch', 'empty-success']) {
    test('contacts $failure preserves truthful deletion semantics', () async {
      final prefs = await SharedPreferences.getInstance();
      final key = 'device_sync_contact_snapshot_v1_$owner';
      await prefs.setString(key, '{"old-contact":"old-fingerprint"}');
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(permissions, (call) async => 1);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(contacts,
          (call) async {
        if (failure == 'collection')
          throw PlatformException(code: 'unavailable');
        if (failure == 'empty-success') return [];
        return [
          Contact(
              id: 'new-contact',
              displayName: 'New',
              phones: [Phone('+886912345678')]).toJson()
        ];
      });
      var completions = 0;
      var sessions = 0;
      ApiClient.instance.dio.interceptors
        ..clear()
        ..add(InterceptorsWrapper(onRequest: (request, handler) {
          Object payload;
          switch (request.path) {
            case '/me/sync/status':
              payload = {};
              break;
            case '/me/sync/contacts/sessions':
              sessions++;
              payload = {'syncSessionId': 'session'};
              break;
            case '/me/sync/contacts/batch':
              payload = {'uploaded': 0, 'skipped': 0, 'failed': 1};
              break;
            case '/me/sync/contacts/complete':
              completions++;
              payload = {};
              break;
            default:
              throw StateError('Unexpected request ${request.path}');
          }
          handler.resolve(Response(
              requestOptions: request,
              statusCode: 200,
              data: {'data': payload}));
        }));
      await DeviceSyncService.instance.syncAfterLogin();
      expect(completions, failure == 'empty-success' ? 1 : 0);
      if (failure == 'collection') expect(sessions, 0);
      expect(
          prefs.getString(key),
          failure == 'empty-success'
              ? '{}'
              : '{"old-contact":"old-fingerprint"}');
    });
  }

  test('oversized video is classified before opening its hash stream',
      () async {
    final file = SizeReportedVideoFile();
    final prepared = await PhotoSyncCollector.prepareOne(AuditVideoAsset(file));
    expect(prepared, isNotNull);
    expect(prepared!.sizeBytes, greaterThan(104857600));
    expect(file.streamOpens, 0);
    expect(prepared.contentHash, isEmpty);
  });

  test('same asset metadata with changed bytes gets a new source fingerprint',
      () async {
    final directory = await Directory.systemTemp.createTemp('photo-hash-');
    try {
      final file = File('${directory.path}/same-name.mp4');
      await file.writeAsBytes([1, 2, 3]);
      final asset = AuditVideoAsset(file);
      final before = await PhotoSyncCollector.sourceFingerprint(asset);
      await file.writeAsBytes([3, 2, 1], flush: true);
      final after = await PhotoSyncCollector.sourceFingerprint(asset);
      expect(before, isNotNull);
      expect(after, isNot(before));
      expect(asset.id, 'audit-video');
      expect(asset.modifiedDateTime.millisecondsSinceEpoch, 1000);
      expect(asset.width, 1920);
      expect(asset.height, 1080);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('a new account sync runs while the prior account request is pending',
      () async {
    final firstRequest = Completer<void>();
    final secondRequest = Completer<void>();
    final releaseFirst = Completer<void>();
    var statusCalls = 0;
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, (call) async => 1);
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(contacts, (call) async => []);
    ApiClient.instance.dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (request, handler) async {
        if (request.path == '/me/sync/status') {
          statusCalls++;
          if (statusCalls == 1) {
            firstRequest.complete();
            await releaseFirst.future;
          } else if (statusCalls == 2) {
            secondRequest.complete();
          }
          handler.resolve(Response(
              requestOptions: request, statusCode: 200, data: {'data': {}}));
          return;
        }
        final data = request.path.endsWith('/sessions')
            ? {'syncSessionId': 'session'}
            : <String, Object>{};
        handler.resolve(Response(
            requestOptions: request, statusCode: 200, data: {'data': data}));
      }));

    await ApiClient.instance.saveToken('account-a-token', userId: 'account-a');
    final first = DeviceSyncService.instance.syncAfterLogin();
    await firstRequest.future.timeout(const Duration(seconds: 2));
    await ApiClient.instance.saveToken('account-b-token', userId: 'account-b');
    final second = DeviceSyncService.instance.syncAfterLogin();
    await secondRequest.future.timeout(const Duration(seconds: 2));
    releaseFirst.complete();
    await Future.wait([first, second]);
    expect(statusCalls, 2);
    await DeviceSyncService.instance.clearForOwner('account-a');
    await DeviceSyncService.instance.clearForOwner('account-b');
  });

  test('session invalidation cancels all active album uploads', () {
    final service = DeviceSyncService.instance;
    final identity =
        SessionIdentityService.instance.capture(ownerUserId: 'album-owner');
    final token = CancelToken();
    final release = service.debugTrackAlbumUploadForTest(identity, token);
    try {
      SessionIdentityService.instance.invalidate(reason: 'test_kickout');
      expect(token.isCancelled, isTrue);
    } finally {
      release();
    }
  });
}
