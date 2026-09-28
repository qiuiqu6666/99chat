import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_recovery_diagnostics.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'export contains live pending operation without waiting for its completion',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/package_info'),
            (_) async => {
                  'appName': 'test',
                  'packageName': 'test',
                  'version': '1',
                  'buildNumber': '1'
                });
    final coordinator = MessagePersistCoordinator.instance;
    coordinator.resetForTest();
    final hold = Completer<void>();
    final entered = Completer<void>();
    final pending = coordinator.enqueue<void>(
        priority: MessagePersistPriority.userHistory,
        source: MessagePersistSource.userHistory,
        run: () {
          entered.complete();
          return hold.future;
        });
    await entered.future;
    try {
      final report = await ChatRecoveryDiagnostics.export()
          .timeout(const Duration(seconds: 5));
      final jsonLine = report
          .split('--- Message persistence (live snapshot) ---\n')[1]
          .split('\n')
          .first;
      final snapshot = jsonDecode(jsonLine) as Map;
      expect(snapshot['writerHeld'], true);
      expect(snapshot['active']['stage'], 'transaction');
      expect(snapshot['completedJobs'], 0);
    } finally {
      hold.complete();
      await pending;
    }
    expect(coordinator.diagnosticSnapshot['active'], isNull);
  });
}
