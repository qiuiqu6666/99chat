// Controlled platform/API doubles; uses the real device-sync service and collector.
// Tests assert current report claims, not desired post-fix behavior.
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
import 'package:tencent_cloud_chat_demo/src/platform/permission_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/device_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/photo_backup_consent.dart';
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
      : super(id: 'audit-video', typeInt: 2, width: 1920, height: 1080,
          duration: 10, createDateSecond: 1, modifiedDateSecond: 1);
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
      ..clear()..addAll(originalInterceptors);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(photos, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(contacts, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(permissions, null);
    await ApiClient.instance.clearToken();
    debugDefaultTargetPlatformOverride = null;
  });

  for (final permission in [PermissionState.authorized, PermissionState.limited]) {
    test('A17 ${permission.name} callback enables previously unset backup', () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(photos, (call) async {
        expect(call.method, 'getPermissionState');
        return permission.index;
      });
      final identity = SessionIdentityService.instance.capture();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(PhotoBackupConsent.keyFor(owner)), isFalse);
      DeviceSyncService.installPermissionHooks();
      await PermissionGuard.onPhotosAccessGranted!();
      expect(prefs.getBool(PhotoBackupConsent.keyFor(owner)), isTrue);
      expect(await PhotoBackupConsent.instance.enabled(identity), isTrue);
      // Explicit false remains respected on a later photo permission callback.
      await PhotoBackupConsent.instance.setEnabled(identity, false);
      await PermissionGuard.onPhotosAccessGranted!();
      expect(await PhotoBackupConsent.instance.enabled(identity), isFalse);
    });
  }

  test('A11 unchanged 101-contact directory is uploaded again in INCREMENTAL mode', () async {
    final localContacts = List.generate(101, (i) => Contact(
      id: 'audit-contact-$i', displayName: 'Audit Contact $i',
      phones: [Phone('+886912345678')],
    ).toJson());
    var collects = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(permissions, (call) async {
      expect(call.method, 'checkPermissionStatus');
      return 1; // PermissionStatus.granted.
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(contacts, (call) async {
      expect(call.method, 'select');
      collects++;
      return localContacts;
    });
    final modes = <String>[];
    final batches = <List<Object?>>[];
    final completions = <List<Object?>>[];
    ApiClient.instance.dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (request, handler) {
        Object payload;
        switch (request.path) {
          case '/me/sync/status':
            payload = {'contacts': {'lastFullSyncAt': '2026-09-27T00:00:00Z'}};
            break;
          case '/me/sync/contacts/sessions':
            modes.add((request.data as Map)['mode'] as String);
            payload = {'syncSessionId': 'audit-session-${modes.length}'};
            break;
          case '/me/sync/contacts/batch':
            batches.add(List<Object?>.from((request.data as Map)['items'] as List));
            payload = {'uploaded': batches.last.length};
            break;
          case '/me/sync/contacts/complete':
            completions.add(List<Object?>.from((request.data as Map)['deletedLocalContactIds'] as List));
            payload = {};
            break;
          default:
            throw StateError('Unexpected audit request ${request.path}');
        }
        handler.resolve(Response(requestOptions: request, statusCode: 200,
          data: {'data': payload}));
      }));
    await DeviceSyncService.instance.syncAfterLogin();
    await DeviceSyncService.instance.syncAfterLogin();
    expect(collects, 2);
    expect(modes, ['INCREMENTAL', 'INCREMENTAL']);
    expect(batches.map((b) => b.length), [100, 1, 100, 1]);
    expect(batches[0], batches[2]);
    expect(batches[1], batches[3]);
    expect(completions, [[], []]);
  });

  test('A12 oversized video metadata does not stop prepareOne from hashing', () async {
    final file = SizeReportedVideoFile();
    final prepared = await PhotoSyncCollector.prepareOne(AuditVideoAsset(file));
    expect(prepared, isNotNull);
    expect(prepared!.sizeBytes, greaterThan(104857600));
    expect(file.streamOpens, 1);
    expect(prepared.contentHash,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });
}
