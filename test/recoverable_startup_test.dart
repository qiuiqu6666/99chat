import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/bootstrap/recoverable_startup.dart';

void main() {
  testWidgets(
      'first frame precedes pending storage; wait cannot start another operation',
      (tester) async {
    final storage = Completer<Widget>();
    var calls = 0;
    await tester.pumpWidget(RecoverableStartup(
        waitBudget: const Duration(seconds: 1),
        bootstrap: () {
          calls++;
          return storage.future;
        }));
    expect(find.text('99chat'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('继续等待'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    for (var i = 0; i < 10; i++) {
      if (i > 0) await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('继续等待'));
      await tester.pump();
    }
    expect(calls, 1);
    storage.complete(const MaterialApp(home: Text('ready')));
    await tester.pump();
    expect(find.text('ready'), findsOneWidget);
  });

  testWidgets(
      'storage failure is retryable and completed dependencies are not repeated',
      (tester) async {
    final steps = StartupTasks();
    var nodeCalls = 0;
    var storageCalls = 0;
    await tester.pumpWidget(RecoverableStartup(bootstrap: () async {
      await steps.run('node', () async {
        nodeCalls++;
      });
      await steps.run('identity', () async {
        if (++storageCalls == 1) throw StateError('secure storage unavailable');
      });
      return const MaterialApp(home: Text('authenticated'));
    }));
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('authenticated'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('authenticated'), findsOneWidget);
    expect(nodeCalls, 1);
    expect(storageCalls, 2);
  });
}
