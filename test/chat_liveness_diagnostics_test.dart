import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_liveness_diagnostics.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_recovery_trace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'bounded batches retain previous process evidence without overwriting it',
      () async {
    SharedPreferences.setMockInitialValues({
      ChatLivenessDiagnostics.lastRunKey: jsonEncode(['previous-process-stall'])
    });
    for (var i = 0; i < 300; i++) {
      ChatRecoveryTrace.log('bounded_$i', conversationID: 'conv');
    }
    expect(ChatRecoveryTrace.recentEvents.length, ChatRecoveryTrace.capacity);
    final diagnostics = ChatLivenessDiagnostics.instance;
    await diagnostics.flush();
    expect(diagnostics.previousRunEvents, ['previous-process-stall']);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString(ChatLivenessDiagnostics.lastRunKey)!),
        hasLength(80));
    await diagnostics.flush();
    expect(jsonDecode(prefs.getString(ChatLivenessDiagnostics.previousRunKey)!),
        ['previous-process-stall']);
  });

  testWidgets('stall observation does not finish or cancel the operation',
      (tester) async {
    final op = ChatTraceOperation('diagnostic-test',
        conversationID: 'c', generation: 3, stallAfter: Duration.zero);
    op.enter('start');
    op.enter('native_wait', nativeRequest: 'test-native-id');
    await tester.pump(const Duration(seconds: 6));
    final logs =
        ChatRecoveryTrace.recentEvents.where((s) => s.contains(op.operationID));
    expect(logs.any((s) => s.contains('queue_stall')), isTrue);
    expect(logs.any((s) => s.contains('queue_finish')), isFalse);
    expect(logs.last, contains('nativeRequestID=test-native-id'));
    expect(logs.last, contains('stageElapsedMs='));
    op.finish(error: StateError('controlled'));
    expect(ChatRecoveryTrace.recentEvents.last, contains('queue_fail'));
  });

  testWidgets('UI/frame, touch and memory signals have bounded lifetime',
      (tester) async {
    final diagnostics = ChatLivenessDiagnostics.instance;
    final route = Object();
    diagnostics.attach(route, 'c');
    await tester.pumpWidget(const SizedBox(width: 100, height: 100));
    await tester.tapAt(const Offset(20, 20));
    diagnostics.sample();
    await tester.pump();
    diagnostics.didHaveMemoryPressure();
    diagnostics.routeState(route, 'c', 'covered');
    diagnostics.detach(route);
    await tester.runAsync(diagnostics.flush);
    final logs = ChatRecoveryTrace.recentEvents;
    expect(
        logs.any((s) => s.contains('ui_heartbeat') && s.contains('touches=2')),
        isTrue);
    expect(
        logs.any(
            (s) => s.contains('ui_heartbeat') && s.contains('mediaOverlay=')),
        isTrue);
    expect(logs.any((s) => s.contains('frame_heartbeat')), isTrue);
    expect(logs.any((s) => s.contains('memory_pressure')), isTrue);
  });
}
