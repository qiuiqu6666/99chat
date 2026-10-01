import 'dart:async';
import 'dart:io';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_unread_clear_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/read_outbox_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/tencent_conversation_read_service.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

const _owner = 'cloud_unread_owner';
const _id = 'group_@TGS#cloud_unread';

V2TimConversation _row(int? unread, {int seq = 10}) => V2TimConversation(
      conversationID: _id,
      groupID: '@TGS#cloud_unread',
      type: 2,
      recvOpt: 0,
      unreadCount: unread,
      lastMessage: V2TimMessage.fromJson({
        'message_msg_id': 'message_$seq',
        'message_server_time': 1800000000 + seq,
        'message_conv_type': 2,
        'message_conv_id': '@TGS#cloud_unread',
        'message_seq': '$seq',
        'message_is_from_self': false,
        'message_risk_type_identified': 0,
      })
        ..seq = '$seq',
    );

class _ReadSdkProbe extends MessageService {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<V2TimCallback> markGroupMessageAsRead(
      {required String groupID}) async {
    calls++;
    return V2TimCallback(code: 0, desc: 'ok');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final aggregate = ConversationUnreadAggregate.instance;
  final tabs = ConversationTabStore.instance;
  final store = ConversationLocalStore.instance;
  final session = ChatSessionController.instance;
  final sync = ConversationSyncService.instance;

  void sdk(V2TimConversation row) {
    session.applyPendingRealtimeProjection([row], reason: 'sdk_realtime');
    tabs.flushRealtimePatches();
  }

  void expectUnread(int count) {
    expect(tabs.conversationForId(_id)?.unreadCount, count);
    expect(aggregate.groupNotifiableUnreadSum, count);
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() async {
    store.debugOwnerUserId = _owner;
    sync.debugOwnerUserId = _owner;
    await store.clearForOwner(_owner);
    await ConversationReadOutboxStore.instance.clearOwner(_owner);
    aggregate.resetForTest();
    tabs.clear();
    tabs.notifyColdStartEnded();
    aggregate.sdkPageForTest = (_) async => throw StateError('offline');
  });
  tearDown(() async {
    ConversationUnreadClearService.resetCoordinatorStateForTesting();
    sync.resetChatTransitionStateForTesting();
    sync.debugGetConversationOverride = null;
    TencentConversationReadService.cleanUnreadForTesting = null;
    ConversationTabStore.debugFetchOverride = null;
    session.clearSessionProjection();
    aggregate.resetForTest();
    await store.flushReadBarrierWritesForTest();
    store.resetAnchorStateForTest();
    await ConversationReadOutboxStore.instance.clearOwner(_owner);
    await store.clearForOwner(_owner);
    store.debugOwnerUserId = null;
    sync.debugOwnerUserId = null;
  });

  test(
      'visible ACK persists a provider intent before publishing a read projection',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('chat-visible-diagnostic-');
    final history =
        HistoryWindowStore(debugDatabasePath: '${directory.path}/history.db');
    HistoryWindowRepositoryProvider.repository = history;
    final global = serviceLocator<TUIChatGlobalModel>();
    final conv = _id.substring('group_'.length);
    global.configureMessageWriterScope(
        ownerUserID: _owner, accountGeneration: 43, domainGeneration: 1);
    global.setCurrentConversation(CurrentConversation(conv, ConvType.group));
    global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
        notify: false);
    var sdkRequests = 0;
    TencentConversationReadService.cleanUnreadForTesting = ({
      required conversationID,
      required cleanTimestamp,
      required cleanSequence,
    }) async {
      sdkRequests++;
      return V2TimCallback(code: 0, desc: 'ok');
    };
    try {
      await global.beginHistoryUnreadVisit(conv);
      final incoming = _row(1).lastMessage!
        ..groupID = conv
        ..status = 2
        ..elemType = 1
        ..isRead = false;
      sdk(_row(1));
      await global.applyAppRealtimeMessage(incoming,
          ingressEventID: 'diagnostic-visible-arrival', ingressSequence: 101);
      final scope = global.historyWindowScopeFor(conv)!;
      expect((await history.deferredState(scope)).unreadCount, 1);
      final receipt = await global.acknowledgeVisibleHistoryMessagesDetailed(
          conv, [incoming],
          isCurrent: () => true);
      expect(receipt.processed, isTrue);
      expect((await history.deferredState(scope)).unreadCount, 0);
      // The provider can acknowledge immediately; either the durable row or
      // the request must be observable, not just a local capsule decrement.
      final intent = await ConversationReadOutboxStore.instance
          .find(ownerUserId: _owner, conversationId: _id);
      expect(intent != null || sdkRequests > 0, isTrue);
      session.flushDeferredListUiBeforeChatLeave(conversationId: _id);
      expectUnread(0);
      // The viewport proof is supplied directly; this is not a physical screen test.
    } finally {
      global.clearCurrentConversation();
      global.invalidateBoundedHistorySessions();
      HistoryWindowRepositoryProvider.repository = null;
      await history.closeIfOpen();
      await directory.delete(recursive: true);
    }
  });

  test('DIAGNOSTIC: legacy markAsRead reports no SDK request without watermark',
      () async {
    final probe = _ReadSdkProbe();
    final result = await TencentConversationReadService.markRead(
        messageService: probe,
        conversationID: _id,
        isGroup: true,
        capturedIdentity: SessionIdentityService.instance.capture());
    expect(result.code, -1);
    expect(result.desc, 'read_watermark_unavailable');
    expect(probe.calls, 0);
  });

  test('acknowledged zero never rolls back on an exact older SDK callback', () {
    sdk(_row(1));
    store.recordReadClearedAnchor(_id,
        reliableReadTarget: true,
        lastMessageId: 'message_10',
        lastMessageTimestamp: 1800000010,
        lastMessageSeq: 10);
    sdk(_row(0));
    expectUnread(0);
    // Inject replay of the very same read message, not a genuinely new arrival.
    sdk(_row(1));
    expectUnread(0);
    expect(aggregate.sdkUnreadCountFor(_id), 1); // Raw authority is unchanged.
    sdk(_row(0));
    expectUnread(0);
  });

  test(
      'durable intent projects read while request ACK does not erase watermark',
      () async {
    final requested = Completer<void>();
    final reply = Completer<V2TimCallback>();
    TencentConversationReadService.cleanUnreadForTesting = ({
      required conversationID,
      required cleanTimestamp,
      required cleanSequence,
    }) {
      expect(cleanSequence, 10);
      requested.complete();
      return reply.future;
    };
    final row = _row(1);
    sdk(row);
    await ConversationUnreadClearService.clearLocalForOpen(conversation: row);
    final cleaning = ConversationUnreadClearService.scheduleSdkUnreadClean(
        conversationID: _id,
        trigger: SdkUnreadCleanTrigger.open,
        hadUnread: true);
    await requested.future;
    expect(
        await ConversationReadOutboxStore.instance
            .find(ownerUserId: _owner, conversationId: _id),
        isNotNull);
    session.flushDeferredListUiBeforeChatLeave(conversationId: _id);
    expectUnread(0);
    reply.complete(V2TimCallback(code: 0, desc: 'controlled success'));
    await cleaning;
    expect(
        await ConversationReadOutboxStore.instance
            .find(ownerUserId: _owner, conversationId: _id),
        isNull);
    expectUnread(0);
    expect(store.readBarrierFor(_id), isNotNull);
    expect(aggregate.awaitingReadSnapshot(_id), isTrue);
    sdk(_row(0));
    expectUnread(0);
    expect(aggregate.awaitingReadSnapshot(_id), isFalse);
    sdk(_row(1));
    expectUnread(0);
  });

  test('group target allows newer seq and retains it across an old replay', () {
    sdk(_row(1));
    store.recordReadClearedAnchor(_id,
        reliableReadTarget: true,
        lastMessageId: 'message_10',
        lastMessageTimestamp: 1800000010,
        lastMessageSeq: 10);
    sdk(_row(1));
    expectUnread(0);
    sdk(_row(41, seq: 11)); // Includes the provider's still-uncleared prefix.
    expectUnread(1);
    sdk(_row(1));
    expectUnread(1);
    sdk(_row(42, seq: 12));
    expectUnread(2);
  });

  test('C2C same second different identity is never covered by timestamp', () {
    V2TimConversation c2c(String message, int unread) => V2TimConversation(
        conversationID: 'c2c_peer',
        type: 1,
        userID: 'peer',
        unreadCount: unread,
        lastMessage: _row(1).lastMessage!
          ..msgID = message
          ..timestamp = 1800000010);
    store.recordReadClearedAnchor('c2c_peer',
        reliableReadTarget: true,
        lastMessageId: 'seen',
        lastMessageTimestamp: 1800000010);
    sdk(c2c('seen', 1));
    expect(tabs.conversationForId('c2c_peer')?.unreadCount, 0);
    sdk(c2c('unseen-same-second', 1));
    expect(tabs.conversationForId('c2c_peer')?.unreadCount, 1);
    sdk(c2c('seen', 1));
    expect(tabs.conversationForId('c2c_peer')?.unreadCount, 1);
  });

  test('reconnect retains watermark; clearing owner removes it', () async {
    sdk(_row(1));
    await ConversationUnreadClearService.clearLocalForOpen(
        conversation: _row(1));
    await aggregate.refreshFromStore(reason: 'reconnect');
    sdk(_row(1));
    expectUnread(0);
    await store.clearForOwner(_owner);
    sdk(_row(1));
    expectUnread(1);
  });

  test('another account cannot inherit the old owner watermark', () {
    store.recordReadClearedAnchor(_id,
        reliableReadTarget: true,
        lastMessageId: 'message_10',
        lastMessageSeq: 10,
        lastMessageTimestamp: 1800000010);
    sdk(_row(1));
    expectUnread(0);
    aggregate.clearSession();
    store.debugOwnerUserId = 'other_owner';
    sdk(_row(1));
    expectUnread(1);
  });

  test('count-only callback has no proof and cannot hide new unread', () async {
    sdk(_row(1));
    await ConversationUnreadClearService.clearLocalForOpen(
        conversation: _row(1));
    sdk(V2TimConversation(conversationID: _id, unreadCount: 2));
    expectUnread(2);
  });

  test('legacy leave anchor without reading proof cannot suppress unread', () {
    sdk(_row(1));
    store.recordReadClearedAnchor(_id,
        lastMessageId: 'message_10',
        lastMessageSeq: 10,
        lastMessageTimestamp: 1800000010);
    sdk(_row(1));
    expectUnread(1);
  });

  test('SDK failure keeps durable target; explicit retry ACK keeps watermark', () async {
    var calls = 0;
    TencentConversationReadService.cleanUnreadForTesting = ({
      required conversationID, required cleanTimestamp, required cleanSequence,
    }) async => V2TimCallback(code: ++calls == 1 ? 6017 : 0, desc: 'controlled');
    sdk(_row(1));
    await ConversationUnreadClearService.clearLocalForOpen(conversation: _row(1));
    await ConversationUnreadClearService.scheduleSdkUnreadClean(
        conversationID: _id, trigger: SdkUnreadCleanTrigger.open);
    final failed = await ConversationReadOutboxStore.instance
        .find(ownerUserId: _owner, conversationId: _id);
    expect(failed?.attemptCount, 1);
    expectUnread(0);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await ConversationUnreadClearService.clearLocalForOpen(conversation: _row(1));
    await ConversationUnreadClearService.scheduleSdkUnreadClean(
        conversationID: _id, trigger: SdkUnreadCleanTrigger.open);
    expect(calls, 2);
    expect(await ConversationReadOutboxStore.instance
        .find(ownerUserId: _owner, conversationId: _id), isNull);
    expect(aggregate.awaitingReadSnapshot(_id), isTrue);
    sdk(_row(0));
    expect(aggregate.awaitingReadSnapshot(_id), isFalse);
  });

  test('history clear cannot cover a genuinely newer group message', () async {
    sdk(_row(1));
    await ConversationUnreadClearService.clearLocalForOpen(conversation: _row(1));
    await store.clearConversationLastMessage(_id, ownerUserId: _owner);
    sdk(_row(1, seq: 11));
    expectUnread(1);
    sdk(_row(1));
    expectUnread(1);
  });

  test('covering group read sequence releases pending phase, not watermark', () async {
    sdk(_row(1));
    await ConversationUnreadClearService.clearLocalForOpen(conversation: _row(1));
    sdk(_row(2, seq: 12)..groupReadSequence = 10);
    expectUnread(2);
    expect(aggregate.awaitingReadSnapshot(_id), isFalse);
    expect(store.readBarrierFor(_id)?.projectionEligible, isTrue);
  });

  test('C2C covering zero rejects a larger replay for the exact confirmed target', () {
    V2TimConversation row(int count, String msg) => V2TimConversation(
        conversationID: 'c2c_peer', userID: 'peer', type: 1, unreadCount: count,
        lastMessage: _row(1).lastMessage!..msgID = msg);
    store.recordReadClearedAnchor('c2c_peer', reliableReadTarget: true,
        lastMessageId: 'seen', lastMessageTimestamp: 1800000010);
    sdk(row(0, 'seen'));
    sdk(row(4, 'seen'));
    expect(tabs.conversationForId('c2c_peer')?.unreadCount, 0);
    sdk(row(1, 'different-same-second'));
    expect(tabs.conversationForId('c2c_peer')?.unreadCount, 1);
  });

  test('C2C retains both explicitly read identities at the same second', () {
    for (final id in ['seen-a', 'seen-b']) {
      store.recordReadClearedAnchor('c2c_peer', reliableReadTarget: true,
          lastMessageId: id, lastMessageTimestamp: 1800000010);
    }
    sdk(V2TimConversation(conversationID: 'c2c_peer', userID: 'peer', type: 1,
        unreadCount: 1, lastMessage: _row(1).lastMessage!..msgID = 'seen-a'));
    expect(tabs.conversationForId('c2c_peer')?.unreadCount, 0);
    sdk(V2TimConversation(conversationID: 'c2c_peer', userID: 'peer', type: 1,
        unreadCount: 1, lastMessage: _row(1).lastMessage!..msgID = 'unseen-c'));
    expect(tabs.conversationForId('c2c_peer')?.unreadCount, 1);
  });

  test('advancing a same-second target retains the earlier snapshot proof', () {
    store.recordReadClearedAnchor('c2c_peer', reliableReadTarget: true,
        lastMessageId: 'seen-a', lastMessageTimestamp: 1800000010);
    sdk(V2TimConversation(conversationID: 'c2c_peer', userID: 'peer', type: 1,
        unreadCount: 0, lastMessage: _row(1).lastMessage!..msgID = 'seen-a'));
    store.recordReadClearedAnchor('c2c_peer', reliableReadTarget: true,
        lastMessageId: 'seen-b', lastMessageTimestamp: 1800000010);
    sdk(V2TimConversation(conversationID: 'c2c_peer', userID: 'peer', type: 1,
        unreadCount: 4, lastMessage: _row(1).lastMessage!..msgID = 'seen-a'));
    expect(tabs.conversationForId('c2c_peer')?.unreadCount, 0);
  });
}
