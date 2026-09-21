import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/chat_latest_load_intent.dart';

void main() {
  testWidgets('released edge gesture survives overlapping gates and runs once',
      (tester) async {
    final intent = ChatLatestLoadIntent();
    addTearDown(intent.dispose);
    var previousLoading = true;
    var compensating = true;
    var trimming = true;
    var loads = 0;
    var cursor = 'before older page';
    String? requestedCursor;
    intent.request(
      evaluate: () => previousLoading || compensating || trimming
          ? ChatLatestLoadDecision.blocked
          : ChatLatestLoadDecision.ready,
      onReady: () {
        loads++;
        requestedCursor = cursor;
      },
    );
    // No more request() calls: the user has released the gesture.
    await tester.pump(const Duration(seconds: 1));
    previousLoading = false;
    await tester.pump(const Duration(seconds: 1));
    compensating = false;
    await tester.pump(const Duration(seconds: 1));
    expect(loads, 0);
    expect(intent.isPending, isTrue);
    cursor = 'after trim';
    trimming = false;
    await tester.pump(ChatLatestLoadIntent.retryDelay);
    expect(loads, 1);
    expect(requestedCursor, 'after trim');
    expect(intent.isPending, isFalse);
    await tester.pump(const Duration(seconds: 10));
    expect(loads, 1,
        reason: 'one gesture must not drain or retry failed pages');
  });

  testWidgets('continuous scroll does not postpone the first request',
      (tester) async {
    final intent = ChatLatestLoadIntent();
    addTearDown(intent.dispose);
    var loads = 0;
    void request() => intent.request(
          evaluate: () => ChatLatestLoadDecision.ready,
          onReady: () => loads++,
        );
    request();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      request();
    }
    expect(loads, 0);
    await tester.pump(const Duration(milliseconds: 20));
    expect(loads, 1);
  });

  for (final reason in ['away from edge', 'window/account changed', 'no gap']) {
    testWidgets('drops a waiting gesture when $reason', (tester) async {
      final intent = ChatLatestLoadIntent();
      addTearDown(intent.dispose);
      var valid = true;
      var blocked = true;
      var loads = 0;
      intent.request(
        evaluate: () => !valid
            ? ChatLatestLoadDecision.discard
            : blocked
                ? ChatLatestLoadDecision.blocked
                : ChatLatestLoadDecision.ready,
        onReady: () => loads++,
      );
      await tester.pump(ChatLatestLoadIntent.retryDelay);
      valid = false;
      await tester.pump(ChatLatestLoadIntent.retryDelay);
      blocked = false;
      valid = true;
      await tester.pump(const Duration(seconds: 2));
      expect(loads, 0);
      expect(intent.isPending, isFalse);
    });
  }

  testWidgets('reverse gesture cancels old work but a later gesture can load',
      (tester) async {
    final intent = ChatLatestLoadIntent();
    addTearDown(intent.dispose);
    var blocked = true;
    var oldLoads = 0;
    var newLoads = 0;
    intent.request(
      evaluate: () => blocked
          ? ChatLatestLoadDecision.blocked
          : ChatLatestLoadDecision.ready,
      onReady: () => oldLoads++,
    );
    await tester.pump(ChatLatestLoadIntent.retryDelay);
    intent.cancel();
    blocked = false;
    intent.request(
      evaluate: () => ChatLatestLoadDecision.ready,
      onReady: () => newLoads++,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(oldLoads, 0);
    expect(newLoads, 1);
  });

  testWidgets('dispose prevents retries and new requests', (tester) async {
    final intent = ChatLatestLoadIntent();
    var evaluations = 0;
    var loads = 0;
    intent.request(
      evaluate: () {
        evaluations++;
        return ChatLatestLoadDecision.blocked;
      },
      onReady: () => loads++,
    );
    await tester.pump(ChatLatestLoadIntent.retryDelay);
    intent.dispose();
    intent.request(
      evaluate: () => ChatLatestLoadDecision.ready,
      onReady: () => loads++,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(evaluations, 1);
    expect(loads, 0);
    expect(intent.isPending, isFalse);
  });
}
