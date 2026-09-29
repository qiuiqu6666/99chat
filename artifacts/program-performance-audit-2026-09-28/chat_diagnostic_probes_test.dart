// Read-only diagnostics: injected SDK results, no network or production data.
// ignore_for_file: avoid_print, depend_on_referenced_packages
import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_mailbox.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import '../../test/chat_runtime_ingress_order_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  test('diagnostic: conversation first page remains occupied after 60 seconds', () {
    fakeAsync((clock) {
      final tab = ConversationTabStore.instance..clear();
      final pending = Completer<({List<V2TimConversation> conversationList,
          String nextSeq, bool isFinished, int code, String desc})>();
      var calls = 0;
      ConversationTabStore.debugFetchOverride = ({required int convType,
          required String nextSeq, required int count}) {
        calls++;
        return pending.future;
      };
      var firstDone = false;
      var retryDone = false;
      tab.ensurePrimed(convType: 1).then((_) => firstDone = true);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 60));
      tab.ensurePrimed(convType: 1).then((_) => retryDone = true);
      clock.flushMicrotasks();
      print('CHAT_AUDIT pending-sdk virtualSeconds=60 calls=$calls '
          'loading=${tab.isLoading} firstDone=$firstDone retryDone=$retryDone '
          'rows=${tab.countForType(1)}');
      expect(calls, 1);
      expect(tab.isLoading, isTrue);
      expect(firstDone || retryDone, isFalse);
      pending.complete((conversationList: <V2TimConversation>[], nextSeq: '0',
          isFinished: true, code: 0, desc: ''));
      clock.flushMicrotasks();
      expect(firstDone && retryDone, isTrue);
      ConversationTabStore.debugFetchOverride = null;
      tab.clear();
    });
  });

  test('diagnostic: bounded mailbox retains every excess callback in admissions', () async {
    final gate = Completer<void>();
    final router = ImMailboxRouter(maxConcurrentWorkers: 1, maxQueuedEvents: 8,
        handler: (event) async {
          if (event.eventId == '0') await gate.future;
        });
    final jobs = [for (var i = 0; i < 10000; i++)
      router.dispatch(fixture.ingress('$i'))];
    final all = Future.wait(jobs);
    await Future<void>.delayed(Duration.zero);
    print('CHAT_AUDIT mailbox maxQueued=8 callbacks=10000 '
        'active=${router.activeWorkerCount} retainedPending=${router.pendingEventCount}');
    expect(router.pendingEventCount, 9999);
    expect(router.activeWorkerCount, 1);
    gate.complete();
    await all;
    await router.drain();
    expect(router.pendingEventCount, 0);
  });
}
