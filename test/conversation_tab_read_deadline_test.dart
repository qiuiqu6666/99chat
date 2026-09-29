import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';

typedef _Page = ({
  List<V2TimConversation> conversationList,
  String nextSeq,
  bool isFinished,
  int code,
  String desc
});
_Page _page(String id) => (
      conversationList: [
        V2TimConversation(conversationID: id, type: 1, userID: id.substring(4))
      ],
      nextSeq: 'next-$id',
      isFinished: false,
      code: 0,
      desc: 'ok'
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  tearDown(() {
    ConversationTabStore.debugFetchOverride = null;
    ConversationTabStore.instance.clear();
  });
  test('SDK wait expires for all joiners without opening competing reads', () {
    fakeAsync((clock) {
      final store = ConversationTabStore.instance..clear();
      final pending = Completer<_Page>();
      var calls = 0;
      ConversationTabStore.debugFetchOverride = (
          {required int convType,
          required String nextSeq,
          required int count}) {
        calls++;
        return calls == 1
            ? pending.future
            : Future.value(_page('c2c_after_retries'));
      };
      var completed = 0;
      store.ensurePrimed(convType: 1).then((_) => completed++);
      store.ensurePrimed(convType: 1).then((_) => completed++);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 9));
      final doneAtDeadline = completed;
      final loadingAtDeadline = store.isLoading;
      final failedAtDeadline = store.lastLoadFailedForType(1);
      for (var i = 0; i < 100; i++) {
        store.ensurePrimed(convType: 1);
      }
      clock.flushMicrotasks();
      final callsWhilePending = calls;
      pending.complete(_page('c2c_stale'));
      clock.flushMicrotasks();
      expect(doneAtDeadline, 2);
      expect(loadingAtDeadline, isFalse);
      expect(failedAtDeadline, isTrue);
      expect(callsWhilePending, 1,
          reason: 'retry intent must not open competing SDK reads');
      expect(calls, 2, reason: 'retry intents coalesce after native completion');
      expect(store.primedForType(1), isTrue);
      expect(store.nextSeqForType(1), 'next-c2c_after_retries');
      expect(store.countForType(1), 1);
    });
  });
  test('a new read succeeds after a timed out SDK operation actually settles',
      () {
    fakeAsync((clock) {
      final store = ConversationTabStore.instance..clear();
      final pending = Completer<_Page>();
      var calls = 0;
      ConversationTabStore.debugFetchOverride = (
              {required int convType,
              required String nextSeq,
              required int count}) =>
          ++calls == 1 ? pending.future : Future.value(_page('c2c_fresh'));
      store.ensurePrimed(convType: 1);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 9));
      pending.complete(_page('c2c_stale'));
      clock.flushMicrotasks();
      store.ensurePrimed(convType: 1);
      clock.flushMicrotasks();
      expect(calls, 2);
      expect(store.primedForType(1), isTrue);
      expect(store.nextSeqForType(1), 'next-c2c_fresh');
      expect(store.countForType(1), 1);
      expect(store.lastLoadFailedForType(1), isFalse);
    });
  });
  test('clear fences old pages while retaining the actual SDK slot', () {
    fakeAsync((clock) {
      final store = ConversationTabStore.instance..clear();
      final pending = Completer<_Page>();
      var calls = 0;
      ConversationTabStore.debugFetchOverride = (
          {required int convType,
          required String nextSeq,
          required int count}) {
        calls++;
        return calls == 1
            ? pending.future
            : Future.value(_page('c2c_new_account'));
      };
      store.ensurePrimed(convType: 1);
      clock.flushMicrotasks();
      store.clear();
      store.ensurePrimed(convType: 1);
      clock.flushMicrotasks();
      expect(calls, 1);
      pending.complete(_page('c2c_old_account'));
      clock.flushMicrotasks();
      expect(calls, 2);
      expect(store.countForType(1), 1);
      expect(store.primedForType(1), isTrue);
      expect(store.conversationForId('c2c_new_account'), isNotNull);
      expect(store.conversationForId('c2c_old_account'), isNull);
    });
  });
  test('new account first page is retried after old SDK read releases its slot',
      () {
    fakeAsync((clock) {
      final store = ConversationTabStore.instance..clear();
      final pendingOldAccount = Completer<_Page>();
      var calls = 0;
      ConversationTabStore.debugFetchOverride = (
          {required int convType,
          required String nextSeq,
          required int count}) {
        calls++;
        return calls == 1
            ? pendingOldAccount.future
            : Future.value(_page('c2c_new_account'));
      };

      store.ensurePrimed(convType: 1, caller: 'old-account');
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 9));

      store.clear();
      store.ensurePrimed(convType: 1, caller: 'new-account');
      clock.flushMicrotasks();
      expect(calls, 1, reason: 'do not overlap a still-running SDK read');

      pendingOldAccount.complete(_page('c2c_old_account'));
      clock.flushMicrotasks();

      expect(calls, 2,
          reason: 'retry the newest account request automatically');
      expect(store.primedForType(1), isTrue);
      expect(store.countForType(1), 1);
      expect(store.conversationForId('c2c_new_account'), isNotNull);
      expect(store.conversationForId('c2c_old_account'), isNull);
    });
  });
  test('late SDK failure is observed and releases its physical slot', () {
    fakeAsync((clock) {
      final store = ConversationTabStore.instance..clear();
      final pending = Completer<_Page>();
      var calls = 0;
      ConversationTabStore.debugFetchOverride = (
              {required int convType,
              required String nextSeq,
              required int count}) =>
          ++calls == 1
              ? pending.future
              : Future.value(_page('c2c_after_error'));
      store.ensurePrimed(convType: 1);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 9));
      pending.completeError(StateError('late SDK error'));
      clock.flushMicrotasks();
      store.ensurePrimed(convType: 1);
      clock.flushMicrotasks();
      expect(calls, 2);
      expect(store.primedForType(1), isTrue);
    });
  });
}
