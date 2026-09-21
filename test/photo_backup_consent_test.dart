import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/photo_backup_consent.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'device_sync_permission_prompted_v1': true,
      'photos_permission_startup_prompted_v1': true,
    });
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.instance.saveToken(
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        userId: 'backup-a');
  });

  test('legacy permission flags never grant full library backup', () async {
    final identity = SessionIdentityService.instance.capture();
    expect(await PhotoBackupConsent.instance.enabled(identity), isFalse);
    expect(PhotoBackupConsent.instance.enabledForCurrentAccount, isFalse);
  });

  test(
      'explicit setting change persists and disabling immediately notifies work',
      () async {
    final identity = SessionIdentityService.instance.capture();
    final consent = PhotoBackupConsent.instance;
    await consent.setEnabled(identity, true);
    expect(await consent.enabled(identity), isTrue);
    var notifications = 0;
    void onChanged() => notifications++;
    consent.addListener(onChanged);
    await consent.setEnabled(identity, false);
    expect(consent.enabledForCurrentAccount, isFalse);
    expect(await consent.enabled(identity), isFalse);
    expect(notifications, 1);
    consent.removeListener(onChanged);
  });

  test('another account does not inherit consent or accept a late confirmation',
      () async {
    final first = SessionIdentityService.instance.capture();
    await PhotoBackupConsent.instance.setEnabled(first, true);
    await ApiClient.instance.saveToken(
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        userId: 'backup-b');
    final second = SessionIdentityService.instance.capture();
    expect(PhotoBackupConsent.instance.enabledForCurrentAccount, isFalse);
    expect(await PhotoBackupConsent.instance.enabled(second), isFalse);
    await PhotoBackupConsent.instance.setEnabled(first, true);
    expect(await PhotoBackupConsent.instance.enabled(second), isFalse);
  });

  test('an expired session cannot authorize even the same account', () async {
    final identity = SessionIdentityService.instance.capture();
    SessionIdentityService.instance.invalidate();
    await PhotoBackupConsent.instance.setEnabled(identity, true);
    expect(
        await PhotoBackupConsent.instance
            .enabled(SessionIdentityService.instance.capture()),
        isFalse);
  });
  testWidgets('request does not show a purpose dialog or enable backup',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Text('picker')),
    ));
    final context = tester.element(find.text('picker'));
    expect(await PhotoBackupConsent.instance.request(context), isFalse);
    expect(find.text('Photo library backup'), findsNothing);
    expect(PhotoBackupConsent.instance.enabledForCurrentAccount, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });
}
