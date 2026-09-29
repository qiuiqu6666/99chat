import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.tekartik.sqflite');
  test('native close failure survives common mixin and the lifecycle guard',
      () async {
    var closes = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'openDatabase') return {'id': 10001};
      if (call.method == 'closeDatabase') {
        closes++;
        throw PlatformException(
            code: 'sqlite_error', message: 'native close failed');
      }
      if (call.method == 'getDatabasesPath') return 'D:/codex-task-cache';
      throw StateError('Unexpected ${call.method}');
    });
    try {
      final db = await databaseFactorySqflitePlugin.openDatabase(
        'D:/codex-task-cache/close-contract.db',
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await expectLater(
          SqfliteLifecycleGuard.closeDatabase(db), throwsA(isA<Exception>()));
      expect(closes, 1);
      // A second close must not silently convert an unconfirmed native close
      // into a successful lifecycle acknowledgment.
      await expectLater(
          SqfliteLifecycleGuard.closeDatabase(db), throwsA(isA<Exception>()));
      expect(closes, 1);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
}
