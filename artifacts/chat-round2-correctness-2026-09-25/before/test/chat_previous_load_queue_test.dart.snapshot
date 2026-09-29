import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/chat_list_pagination_ui_gate.dart';

void main() {
  testWidgets('updates the cursor without postponing the first deadline',
      (tester) async {
    final queue = ChatPreviousLoadQueue();
    addTearDown(queue.dispose);
    final loaded = <int>[];
    void request(int cursor) => queue.request(
          userGesture: false,
          evaluate: () => ChatPreviousLoadDecision.ready,
          load: () async => loaded.add(cursor),
          onDecision: (_) {},
        );
    request(100);
    await tester.pump(const Duration(milliseconds: 80));
    request(80);
    await tester.pump(const Duration(milliseconds: 40));
    expect(loaded, [80]);
    await tester.pump(const Duration(seconds: 2));
    expect(loaded, [80], reason: 'completion cannot generate another intent');
  });

  testWidgets('waiting owns no trim lock and releases exactly one request',
      (tester) async {
    final queue = ChatPreviousLoadQueue();
    addTearDown(queue.dispose);
    var trimming = true;
    var loads = 0;
    queue.request(
      userGesture: true,
      evaluate: () => trimming
          ? ChatPreviousLoadDecision.wait
          : ChatPreviousLoadDecision.ready,
      load: () async => loads++,
      onDecision: (_) {},
    );
    await tester.pump(const Duration(seconds: 1));
    expect(queue.isPending, isTrue);
    expect(queue.isAdmitted, isFalse,
        reason: 'a waiting intent must not prevent the trim it needs');
    trimming = false;
    await tester.pump(ChatPreviousLoadQueue.retryDelay);
    expect(loads, 1);
    expect(queue.isPending, isFalse);
  });

  testWidgets('automatic fill cannot downgrade a promoted user intent',
      (tester) async {
    final queue = ChatPreviousLoadQueue();
    addTearDown(queue.dispose);
    final loaded = <String>[];
    void request(String name, bool userGesture) => queue.request(
          userGesture: userGesture,
          evaluate: () => ChatPreviousLoadDecision.ready,
          load: () async => loaded.add(name),
          onDecision: (_) {},
        );
    request('silent fill', false);
    await tester.pump(const Duration(milliseconds: 40));
    request('user gesture', true);
    await tester.pump(const Duration(milliseconds: 40));
    request('later silent fill', false);
    await tester.pump(const Duration(milliseconds: 40));
    expect(loaded, ['user gesture']);
  });

  testWidgets('a retired user owner cannot swallow new automatic fill',
      (tester) async {
    final queue = ChatPreviousLoadQueue();
    addTearDown(queue.dispose);
    var ownerIsCurrent = true;
    final loaded = <String>[];
    queue.request(
      userGesture: true,
      evaluate: () => ownerIsCurrent
          ? ChatPreviousLoadDecision.wait
          : ChatPreviousLoadDecision.discard,
      load: () async => loaded.add('old owner'),
      onDecision: (_) {},
    );
    ownerIsCurrent = false;
    queue.request(
      userGesture: false,
      evaluate: () => ChatPreviousLoadDecision.ready,
      load: () async => loaded.add('new owner'),
      onDecision: (_) {},
    );
    await tester.pump(ChatPreviousLoadQueue.retryDelay);
    expect(loaded, ['new owner']);
    expect(queue.isPending, isFalse);
  });

  testWidgets('failure and cancellation discard pending authorization',
      (tester) async {
    final queue = ChatPreviousLoadQueue();
    addTearDown(queue.dispose);
    var decision = ChatPreviousLoadDecision.wait;
    var loads = 0;
    void request() => queue.request(
          userGesture: true,
          evaluate: () => decision,
          load: () async => loads++,
          onDecision: (_) {},
        );
    request();
    decision = ChatPreviousLoadDecision.needsGesture;
    await tester.pump(ChatPreviousLoadQueue.retryDelay);
    decision = ChatPreviousLoadDecision.ready;
    await tester.pump(const Duration(seconds: 2));
    expect(loads, 0);
    request();
    queue.cancel();
    await tester.pump(ChatPreviousLoadQueue.retryDelay);
    expect(loads, 0);
    request();
    await tester.pump(ChatPreviousLoadQueue.retryDelay);
    expect(loads, 1);
  });
}
