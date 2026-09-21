import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Test fake for the existing path_provider plugin interface.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/platform/permission_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/device_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform original;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('selected_photo_test_');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    await ApiClient.instance.saveToken(
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        userId: 'selected-owner');
  });
  tearDown(() async {
    await DeviceSyncService.instance.clearForOwner('selected-owner');
    PathProviderPlatform.instance = original;
    await directory.delete(recursive: true);
  });

  test('permission alone does not enable album backup', () async {
    DeviceSyncService.installPermissionHooks();
    expect(PermissionGuard.onPhotosAccessGranted, isNotNull);
    await DeviceSyncService.instance.handlePhotosAccessGranted();
    expect(await Directory('${directory.path}/selected_photo_sync').exists(),
        isFalse);
  });

  test('only the confirmed file is copied and logout clears the pending copy',
      () async {
    final picked =
        await File('${directory.path}/picked.jpg').writeAsString('selected');
    await File('${directory.path}/private.jpg').writeAsString('not selected');
    await DeviceSyncService.instance.enqueueSelectedPhoto(picked.path,
        identity: SessionIdentityService.instance.capture());
    final staging = Directory('${directory.path}/selected_photo_sync');
    final files = await staging
        .list()
        .where((file) => file is File)
        .cast<File>()
        .toList();
    expect(files, hasLength(1));
    expect(await files.single.readAsString(), 'selected');
    await DeviceSyncService.instance.clearForOwner('selected-owner');
    expect(await staging.list().toList(), isEmpty);
    expect(await picked.exists(), isTrue);
  });

  test('old account selection is rejected before reading or copying a file',
      () async {
    final identity = SessionIdentityService.instance.capture();
    SessionIdentityService.instance.invalidate();
    await DeviceSyncService.instance
        .enqueueSelectedPhoto('missing.jpg', identity: identity);
    expect(await Directory('${directory.path}/selected_photo_sync').exists(),
        isFalse);
  });

  test('album enumeration is behind the separate purpose consent gate', () {
    final source =
        File('lib/src/services/device_sync_service.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _syncAuthorizedAlbum');
    final gate =
        source.indexOf('if (!await _canSyncAlbum(identity)) return;', start);
    final enumerate = source.indexOf('PhotoSyncCollector.openAlbum(', start);
    expect(gate, greaterThan(start));
    expect(enumerate, greaterThan(gate));
    expect(source.contains('PhotoBackupConsent.instance.enabled(identity)'),
        isTrue);
  });
}
