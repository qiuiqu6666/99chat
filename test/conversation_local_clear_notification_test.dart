import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/archived_conversation_store.dart';

V2TimConversation _row(String id,
        {int unread = 0, int recvOpt = 0, String? name}) =>
    V2TimConversation(
      conversationID: 'c2c_$id',
      type: 1,
      userID: id,
      showName: name ?? 'Peer $id',
      unreadCount: unread,
      recvOpt: recvOpt,
      orderkey: 1700000000000,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final session = ChatSessionController.instance;
  final store = ConversationTabStore.instance;
  final aggregate = ConversationUnreadAggregate.instance;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  setUp(() {
    session.clearSessionProjection();
    aggregate.resetForTest();
    ActiveChatRegistry.instance.reset();
    clearArchivedConversationSessionState();
    session.isFeedScrolling = () => false;
    session.ensureTabStoreBridgeAttached();
    store.notifyColdStartEnded();
  });

  tearDown(() {
    session.clearSessionProjection();
    aggregate.resetForTest();
    clearArchivedConversationSessionState();
  });

  test('SDK deletion publishes IDs even outside the main loaded window', () {
    final controller = ChatSessionController.instance;
    final events = <List<String>>[];
    void onDeleted() => events.add(controller.sdkDeletedConversationIds.value);
    controller.sdkDeletedConversationIds.addListener(onDeleted);
    try {
      controller.applyPendingRealtimeDeletion(['c2c_outside']);
      expect(events, [
        ['c2c_outside']
      ]);
      expect(() => events.single.clear(), throwsUnsupportedError);
      controller.clearSessionProjection();
      expect(controller.sdkDeletedConversationIds.value, isEmpty);
    } finally {
      controller.sdkDeletedConversationIds.removeListener(onDeleted);
    }
  });

  for (final recvOpt in [0, 2]) {
    testWidgets(
        'local read notifies its row after another row patch, mute=$recvOpt',
        (tester) async {
      const targetId = 'c2c_read_target';
      store.setItemsForTest(
        convType: 1,
        items: [
          _row('other'),
          _row('read_target', unread: 7, recvOpt: recvOpt)
        ],
        finished: true,
      );
      final targetRevision = session.rowRevisionOf(targetId);
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder<int>(
          valueListenable: targetRevision,
          builder: (_, __, ___) => Text(
              'unread:${session.currentConversationById(targetId)?.unreadCount}'),
        ),
      ));
      expect(find.text('unread:7'), findsOneWidget);

      store.applyPatches(
          [_row('other')..faceUrl = 'https://example.test/other-updated.png'],
          reason: 'preceding_local_patch', preserveOrder: true);
      expect(store.lastNotificationChangedIds, {'c2c_other'});
      final beforeTargetRevision = targetRevision.value;
      final beforeFeedRevision = session.feedRevision.value;

      session.zeroUnreadLocally(targetId);
      await tester.pump();

      expect(store.lastApplyPatchesReason, 'zero_unread_local');
      expect(store.lastNotificationChangedIds, {targetId});
      expect(targetRevision.value, beforeTargetRevision + 1);
      expect(session.feedRevision.value, beforeFeedRevision);
      expect(find.text('unread:0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('silent archive purge invalidates the cached combined read', () {
    archivedConversationC2cIDsNotifier.value = {'c2c_archived'};
    store.setItemsForTest(
      convType: 1,
      items: [_row('kept'), _row('archived')],
      finished: true,
    );
    expect(store.conversations.map((row) => row.conversationID),
        contains('c2c_archived'));
    var notifications = 0;
    void listener() => notifications++;
    store.addListener(listener);
    try {
      store.purgeArchived(notify: false);

      expect(notifications, 0);
      expect(store.lastApplyPatchesReason, 'archive_purge');
      expect(store.lastNotificationChangedIds, {'c2c_archived'});
      expect(
          store.conversations.map((row) => row.conversationID), ['c2c_kept']);
      expect(store.countForType(1), 1);
    } finally {
      store.removeListener(listener);
    }
  });
}
