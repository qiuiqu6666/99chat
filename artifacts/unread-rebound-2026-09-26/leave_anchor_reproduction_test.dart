// Runs the real leave finalizer, isolating its local anchor from SDK transport.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_unread_clear_service.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'reproduction_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final controller = ChatSessionController.instance;
  final store = ConversationLocalStore.instance;
  final tabs = ConversationTabStore.instance;
  final aggregate = ConversationUnreadAggregate.instance;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() {
    store.resetAnchorStateForTest();
    store.debugOwnerUserId = 'leave_anchor_diagnostic';
    tabs.clear();
    tabs.notifyColdStartEnded();
    aggregate.resetForTest();
    ConversationUnreadClearService.resetCoordinatorStateForTesting();
    ConversationSyncService.instance.markReadStoreOverride = (_) async {};
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async => (
          conversationList: [fixture.row('seen', 0, group: convType == 2)],
          nextSeq: '0', isFinished: true, code: 0, desc: '',
        );
  });
  tearDown(() {
    controller.clearSessionProjection();
    aggregate.resetForTest();
    store.resetAnchorStateForTest();
    store.debugOwnerUserId = null;
    ConversationUnreadClearService.resetCoordinatorStateForTesting();
    ConversationSyncService.instance.markReadStoreOverride = null;
    ConversationTabStore.debugFetchOverride = null;
  });

  for (final group in [false, true]) {
    for (final target in ['seen', 'old-history']) {
      test('first leave target=$target preserves read watermark; group=$group', () async {
        final id = group ? 'group_rebound' : 'c2c_rebound';
        controller.applyPendingRealtimeProjection(
          [fixture.row('seen', 5, group: group)], reason: 'sdk_realtime');
        tabs.flushRealtimePatches();
        store.recordReadClearedAnchor(id, lastMessageId: 'seen',
            lastMessageTimestamp: 100, lastMessageSeq: group ? 10 : 0);
        controller.zeroUnreadLocally(id);
        ConversationUnreadClearService.beginConversationChatSession(id);

        // chat.dart's newest-first list is scanned from its tail on dispose.
        // Pass that older ID into the actual finalizer; no production code is
        // copied here and no native SDK call or real account is involved.
        final first = ConversationUnreadClearService.finalizeConversationLeaveOnce(
          conversationID: id, lastMessageId: target, entryUnreadCount: 5,
          scheduleSdkUnreadCleanOnLeave: false);
        // Both Chat.dispose and the conversation page finalize this session.
        // The later caller either has the correct head or the incorrect tail.
        final second = ConversationUnreadClearService.finalizeConversationLeaveOnce(
          conversationID: id,
          lastMessageId: target == 'seen' ? 'old-history' : 'seen',
          entryUnreadCount: 5, scheduleSdkUnreadCleanOnLeave: false);
        await Future.wait([first, second]);
        final afterLeave = store.readBarrierFor(id)!;
        controller.applyPendingRealtimeProjection(
          [fixture.row('seen', 5, group: group)], reason: 'sdk_late_snapshot');
        tabs.flushRealtimePatches();
        expect({
          'anchorId': afterLeave.lastMessageId,
          'anchorTime': afterLeave.lastMessageTimestamp,
          'anchorSeq': afterLeave.lastMessageSeq,
          'row': tabs.conversationForId(id)?.unreadCount,
          'tab': group ? aggregate.groupNotifiableUnreadSum
              : aggregate.c2cNotifiableUnreadSum,
        }, {
          'anchorId': 'seen', 'anchorTime': 100, 'anchorSeq': group ? 10 : 0,
          'row': 0, 'tab': 0,
        });
      });
    }
  }
}
