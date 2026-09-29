import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_content_patch.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation_result.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

V2TimConversation _row(int unread, {int recvOpt = 0}) => V2TimConversation(
      conversationID: 'c2c_followup',
      userID: 'followup',
      type: 1,
      unreadCount: unread,
      recvOpt: recvOpt,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final aggregate = ConversationUnreadAggregate.instance;
  final tabs = ConversationTabStore.instance;
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() {
    ChatSessionController.instance.clearSessionProjection();
    aggregate.resetForTest();
    aggregate.sdkPageForTest = (_) async =>
        V2TimConversationResult(conversationList: [], isFinished: true);
  });
  tearDown(() {
    ConversationTabStore.debugFetchOverride = null;
    ChatSessionController.instance.clearSessionProjection();
    aggregate.resetForTest();
  });

  test('100 unchanged SDK unread snapshots publish no folder refresh', () {
    aggregate.applySdkConversations([_row(4)]);
    final revision = aggregate.sdkUnreadRevision.value;
    final pageRevision = aggregate.sdkPageRevision;
    for (var i = 0; i < 100; i++) {
      aggregate.applySdkConversations([_row(4)..showName = 'name $i']);
    }
    expect(aggregate.sdkUnreadRevision.value, revision);
    // Even identical counts must still fence a page that started earlier.
    expect(aggregate.sdkPageRevision, greaterThan(pageRevision));
  });

  test('mute changes tab sums without changing raw folder unread', () {
    aggregate.applySdkConversations([_row(4)]);
    final revision = aggregate.sdkUnreadRevision.value;
    aggregate.applySdkConversations([_row(4, recvOpt: 1)]);
    expect(aggregate.c2cNotifiableUnreadSum, 0);
    expect(aggregate.sdkUnreadRevision.value, revision);
  });

  test('unchanged callback still beats a stale SDK page', () {
    aggregate.applySdkConversations([_row(4)]);
    final started = aggregate.sdkPageRevision;
    aggregate.applySdkConversations([_row(4)]);
    aggregate.applySdkPage([_row(1)], startedAtRevision: started);
    expect(aggregate.c2cNotifiableUnreadSum, 4);
  });

  test('content deltas preserve a canonical group ID across SDK aliases', () {
    V2TimConversation group(String id, int unread) => V2TimConversation(
          conversationID: id,
          groupID: '@TGS#delta_alias',
          type: 2,
          unreadCount: unread,
          orderkey: 1700000000000,
        );
    tabs.setItemsForTest(
        convType: 2, items: [group('group_@TGS#delta_alias', 1)]);
    final current = tabs.conversations;
    final revision = tabs.contentRevision;
    tabs.applyPatches([group('@TGS#delta_alias', 3)],
        preserveOrder: true, explicitUnreadIds: {'@TGS#delta_alias'});
    final changed = tabs.contentChangesSince(revision);
    final patched = changed == null
        ? null
        : patchConversationContents(
            current: current,
            positions: {'group_@TGS#delta_alias': 0},
            changedIds: changed,
            lookup: tabs.displayConversationForId,
          );
    // A null result asks the page to rebuild; it must never return stale data.
    if (patched != null) expect(patched.single.unreadCount, 3);
    expect(tabs.conversationForId('group_@TGS#delta_alias')!.unreadCount, 3);
  });

  test('raw unread change history keeps deletion identity and resets consumers',
      () {
    aggregate.applySdkConversations([_row(4)]);
    final revision = aggregate.sdkUnreadRevision.value;
    aggregate.removeSdkConversations(['c2c_followup']);
    expect(aggregate.rawUnreadChangesSince(revision), {'c2c_followup'});
    final beforeReset = aggregate.sdkUnreadRevision.value;
    aggregate.clearSession();
    expect(aggregate.rawUnreadChangesSince(beforeReset), isNull);
  });

  test('account reset publishes raw invalidation after sums are cleared', () {
    aggregate.applySdkConversations([_row(4)]);
    final sumsAtInvalidation = <int>[];
    void onRevision() =>
        sumsAtInvalidation.add(aggregate.c2cNotifiableUnreadSum);
    aggregate.sdkUnreadRevision.addListener(onRevision);
    try {
      aggregate.clearSession();
      expect(sumsAtInvalidation, [0]);
    } finally {
      aggregate.sdkUnreadRevision.removeListener(onRevision);
    }
  });

  test('all default first-page callers request the same bounded size',
      () async {
    final requested = <int>[];
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async {
      requested.add(count);
      return (
        conversationList: <V2TimConversation>[],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: ''
      );
    };
    await tabs.ensurePrimed(convType: 1, caller: 'restoreProjection');
    tabs.clear();
    await tabs.ensurePrimed(convType: 1, coldStart: true, caller: 'bootstrap');
    expect(requested, [30, 30]);
  });

  test('explicit first-page size is preserved when sharing cold-start entry',
      () async {
    final requested = <int>[];
    final release = Completer<void>();
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async {
      requested.add(count);
      await release.future;
      return (
        conversationList: <V2TimConversation>[],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: ''
      );
    };
    final explicit = tabs.ensurePrimed(convType: 1, count: 50, coldStart: true);
    final joined = tabs.ensurePrimed(convType: 1);
    release.complete();
    await Future.wait([explicit, joined]);
    expect(requested, [50]);
  });
}
