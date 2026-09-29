import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';

// Diagnostic assertions describe current behavior; these are not fix tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  tearDown(() => messenger.setMockMethodCallHandler(storage, null));

  test('secure storage failure escapes the pre-runApp bootstrap', () async {
    messenger.setMockMethodCallHandler(storage, (call) async {
      throw PlatformException(code: 'audit_storage_unavailable');
    });
    await expectLater(ApiClient.instance.bootstrap(),
        throwsA(isA<PlatformException>()));
  });

  test('a pending secure storage read keeps bootstrap pending', () async {
    final gate = Completer<Object?>();
    var firstRead = true;
    messenger.setMockMethodCallHandler(storage, (call) async {
      if (call.method == 'read' && firstRead) {
        firstRead = false;
        return gate.future;
      }
      return null;
    });
    var completed = false;
    final operation = ApiClient.instance.bootstrap().then((_) => completed = true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(firstRead, isFalse);
    expect(completed, isFalse);
    gate.complete(null);
    await operation;
    expect(completed, isTrue);
  });
}
