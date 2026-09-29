import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_shadow_bridge.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_feed_body.dart';
import 'package:tencent_cloud_chat_demo/utils/avatar_image_warm.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_conversation_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/archived_conversation_store.dart';

const _owner = 'live_recovery_owner';
const _peer = 'received_preview_peer';
const _conversationId = 'c2c_$_peer';
const _group = '@TGS#received_preview';

V2TimMessage _message(String id, int timestamp,
        {bool isSelf = false, bool group = false, String seq = ''}) =>
    V2TimMessage.fromJson({
      'message_msg_id': id,
      'message_server_time': timestamp,
      'message_sender': isSelf ? _owner : _peer,
      'message_conv_type': group ? 2 : 1,
      'message_conv_id': group ? _group : _peer,
      'message_seq': seq,
      'message_is_from_self': isSelf,
      'message_status': 2,
      'message_risk_type_identified': 0,
      'message_elem_array': <Object?>[],
    })
      ..elemType = 1
      ..seq = seq
      ..isSelf = isSelf
      ..textElem = V2TimTextElem(text: id);

V2TimConversation _row(V2TimMessage message, {int unread = 0}) =>
    V2TimConversation(
      conversationID:
          message.groupID == _group ? 'group_$_group' : _conversationId,
      type: message.groupID == _group ? 2 : 1,
      userID: message.groupID == _group ? null : _peer,
      groupID: message.groupID,
      showName: 'Preview peer',
      unreadCount: unread,
      recvOpt: 0,
      orderkey: message.timestamp,
      lastMessage: message,
    );

class _Messages implements MessageService {
  V2TimAdvancedMsgListener? listener;

  @override
  Future<void> addAdvancedMsgListener(
      {required V2TimAdvancedMsgListener listener}) async {
    this.listener = listener;
  }

  @override
  Future<void> removeAdvancedMsgListener(
      {V2TimAdvancedMsgListener? listener}) async {
    this.listener = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sync = ConversationSyncService.instance;
  final session = ChatSessionController.instance;
  final tabs = ConversationTabStore.instance;
  final local = ConversationLocalStore.instance;
  late _Messages messages;
  final platformCalls = <String>[];

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    setupServiceLocator();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('tencent_cloud_chat_sdk'),
            (call) async {
      platformCalls.add(call.method);
      return {'code': 0, 'desc': 'ok'};
    });
  });

  setUp(() async {
    sync.resetChatTransitionStateForTesting();
    sync.debugOwnerUserId = _owner;
    local.debugOwnerUserId = _owner;
    ConversationLocalStore.bypassUpsertCoalesceForTest = true;
    ConversationMutationShadowBridge.instance.resetForTest();
    ConversationUnreadAggregate.instance.resetForTest();
    ActiveChatRegistry.instance.reset();
    session.clearSessionProjection();
    session.ensureTabStoreBridgeAttached();
    await local.clearForOwner(_owner);
    messages = _Messages();
    serviceLocator.allowReassignment = true;
    serviceLocator.registerSingleton<MessageService>(messages);
  });

  tearDown(() async {
    await sync.detachRealtimeListeners();
    sync.resetChatTransitionStateForTesting();
    ActiveChatRegistry.instance.reset();
    session.clearSessionProjection();
    ConversationMutationShadowBridge.instance.resetForTest();
    ConversationUnreadAggregate.instance.resetForTest();
    await local.clearForOwner(_owner);
    local.debugOwnerUserId = null;
    ConversationLocalStore.bypassUpsertCoalesceForTest = false;
  });

  Future<void> seed({bool group = false}) async {
    await local.upsertBatch(
      ownerUserId: _owner,
      conversations: [_row(_message('old preview', 100, group: group))],
    );
    session.replaceProjectionForTest(
        [_row(_message('old preview', 100, group: group))]);
  }

  Future<void> startRealtime() async {
    await ApiClient.instance.saveAuthenticatedUserIdIfCurrent(
      expectedToken: null,
      userId: _owner,
    );
    await sync.ensureRealtimeActive(SessionIdentityService.instance.capture());
    expect(messages.listener, isNotNull);
    platformCalls.clear();
  }

  Future<void> deliver(V2TimMessage message) async {
    messages.listener!.onRecvNewMessage(message);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  test('mutable SDK message still publishes preview and new order', () async {
    final target = _row(_message('old preview', 100));
    final other = V2TimConversation(
        conversationID: 'c2c_other',
        type: 1,
        userID: 'other',
        lastMessage: _message('other message', 150),
        orderkey: 150);
    session.replaceProjectionForTest([other, target]);
    expect(tabs.conversations.last.conversationID, _conversationId);
    final message = tabs.conversationForId(_conversationId)!.lastMessage!;
    final before = tabs.contentRevision;
    message.msgID = 'mutated SDK preview';
    message.timestamp = 200;
    message.textElem = V2TimTextElem(text: 'mutated SDK preview');
    session.applyLastMessageLocally(
        conversationID: _conversationId, message: message);
    expect(tabs.rowViewOf(_conversationId)?.lastMessagePreview,
        'mutated SDK preview');
    expect(tabs.contentRevision, greaterThan(before));
    expect(tabs.conversations.first.conversationID, _conversationId);
  });

  test('older draft cannot pin a newer received message below older chats', () {
    final target = _row(_message('old preview', 100))
      ..draftText = 'unfinished draft'
      ..draftTimestamp = 110;
    final other = V2TimConversation(
        conversationID: 'c2c_other',
        type: 1,
        userID: 'other',
        lastMessage: _message('other message', 150),
        orderkey: 150);
    session.replaceProjectionForTest([other, target]);
    session.applyLastMessageLocally(
        conversationID: _conversationId, message: _message('new preview', 200));
    expect(tabs.conversationForId(_conversationId)?.lastMessage?.msgID,
        'new preview');
    expect(tabs.conversations.first.conversationID, _conversationId);
    expect(
        ConversationLocalStore.activeTimeForPersistedRowForTest(
            tabs.conversationForId(_conversationId)!,
            localDraftText: 'unfinished draft',
            localDraftUpdatedAtMs: 110),
        200000);
  });

  for (final page in [false, true]) {
    test(
        'message before its conversation row survives old SDK data: page=$page',
        () async {
      session.applyLastMessageLocally(
          conversationID: _conversationId,
          message: _message('message before row', 200));
      if (page) {
        ConversationTabStore.debugFetchOverride = (
                {required convType, required nextSeq, required count}) async =>
            (
              conversationList: [_row(_message('old preview', 100), unread: 1)],
              nextSeq: 'done',
              isFinished: true,
              code: 0,
              desc: 'ok'
            );
        try {
          await tabs.loadFirstPage(convType: 1);
        } finally {
          ConversationTabStore.debugFetchOverride = null;
        }
      } else {
        session.applyPendingRealtimeProjection(
            [_row(_message('old preview', 100), unread: 1)],
            reason: 'sdk_realtime_authoritative');
        tabs.flushRealtimePatches();
      }
      expect(tabs.conversationForId(_conversationId)?.lastMessage?.msgID,
          'message before row');
      expect(tabs.conversationForId(_conversationId)?.unreadCount, 1);
    });
  }

  test('message after a pending history clear survives the older page',
      () async {
    final started = Completer<void>();
    final page = Completer<
        ({
          List<V2TimConversation> conversationList,
          String nextSeq,
          bool isFinished,
          int code,
          String desc
        })>();
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) {
      started.complete();
      return page.future;
    };
    try {
      final load = tabs.loadFirstPage(convType: 1);
      await started.future;
      tabs.applyPatches([_row(_message('old', 100))..lastMessage = null],
          allowNew: false, explicitLastMessageIds: {_conversationId});
      session.applyLastMessageLocally(
          conversationID: _conversationId,
          message: _message('after clear', 200));
      page.complete((
        conversationList: [_row(_message('old', 100))],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: 'ok'
      ));
      await load;
      expect(
          tabs.conversationForId(_conversationId)?.lastMessage?.textElem?.text,
          'after clear');
    } finally {
      ConversationTabStore.debugFetchOverride = null;
    }
  });

  for (final group in [false, true]) {
    test(
        'early SDK messages retain latest preview without duplicating unread: group=$group',
        () async {
      await startRealtime();
      final id = group ? 'group_$_group' : _conversationId;
      await deliver(_message('newest', 200, group: group, seq: '12'));
      await deliver(_message('late older', 200, group: group, seq: '11'));
      session.applyPendingRealtimeProjection([
        _row(_message('old snapshot', 100, group: group), unread: 2),
      ], reason: 'sdk_realtime_authoritative');
      tabs.flushRealtimePatches();
      expect(tabs.rowViewOf(id)?.lastMessagePreview, contains('newest'));
      expect(tabs.conversationForId(id)?.unreadCount, 2);
      await deliver(_message('newest', 200, group: group, seq: '12'));
      expect(tabs.conversationForId(id)?.unreadCount, 2);
      expect(platformCalls.where((method) => method == 'getConversation'),
          isEmpty);
    });
  }

  for (final invalidate in ['account clear', 'delete', 'clear history']) {
    test('pending preview is discarded on $invalidate', () {
      session.applyLastMessageLocally(
          conversationID: _conversationId,
          message: _message('discarded preview', 200));
      if (invalidate == 'account clear') {
        session.clearSessionProjection();
        session.ensureTabStoreBridgeAttached();
      } else if (invalidate == 'delete') {
        tabs.applyDeleted([_conversationId]);
      } else {
        tabs.applyPatches(
            [_row(_message('old preview', 100))..lastMessage = null],
            explicitLastMessageIds: {_conversationId});
        expect(tabs.conversationForId(_conversationId)?.lastMessage, isNull);
      }
      tabs.applyPatches([_row(_message('new account or new row', 110))]);
      expect(tabs.conversationForId(_conversationId)?.lastMessage?.msgID,
          'new account or new row');
    });
  }

  test('scroll freeze owners release independently and settle deferred order',
      () {
    final firstOwner = Object();
    final secondOwner = Object();
    final other = V2TimConversation(
        conversationID: 'c2c_other',
        type: 1,
        userID: 'other',
        lastMessage: _message('other', 150),
        orderkey: 150);
    session.replaceProjectionForTest([other, _row(_message('old', 100))]);
    tabs.setSortFrozenByScroll(true, owner: firstOwner);
    tabs.setSortFrozenByScroll(true, owner: secondOwner);
    session.applyLastMessageLocally(
        conversationID: _conversationId, message: _message('new', 200));
    expect(tabs.rowViewOf(_conversationId)?.lastMessagePreview, 'new');
    expect(tabs.conversations.first.conversationID, 'c2c_other');
    tabs.setSortFrozenByScroll(false, owner: firstOwner);
    expect(tabs.isSortFrozenByScroll, isTrue);
    tabs.setSortFrozenByScroll(false, owner: secondOwner);
    expect(tabs.isSortFrozenByScroll, isFalse);
    expect(tabs.conversations.first.conversationID, _conversationId);
    tabs.setSortFrozenByScroll(true, owner: firstOwner);
    session.clearSessionProjection();
    expect(tabs.isSortFrozenByScroll, isFalse);
    tabs.setSortFrozenByScroll(true, owner: secondOwner);
    tabs.setSortFrozenByScroll(false, owner: secondOwner);
    expect(tabs.isSortFrozenByScroll, isFalse);
  });

  test('new activity preserves pin priority and compares mixed timestamp units',
      () {
    final target = _row(_message('new', 1800000200))
      ..draftText = 'older draft'
      ..draftTimestamp = 1800000100000;
    final pinned = V2TimConversation(
        conversationID: 'c2c_pinned',
        type: 1,
        isPinned: true,
        lastMessage: _message('pinned', 100));
    session.replaceProjectionForTest([pinned, target]);
    session.applyLastMessageLocally(
        conversationID: _conversationId,
        message: _message('newer', 1800000201));
    expect(tabs.conversations.first.conversationID, 'c2c_pinned');
    expect(ConversationLocalStore.activeTimeMs(target), 1800000200000);
    target.draftTimestamp = 1800000300;
    target.lastMessage!.timestamp = 1800000200000;
    expect(ConversationLocalStore.activeTimeMs(target), 1800000300000);
  });

  Widget feed(ScrollController scroll,
          {bool active = true,
          ScrollPhysics physics = const ClampingScrollPhysics()}) =>
      MaterialApp(
          home: TickerMode(
              enabled: active,
              child: ConversationFeedBody(
                workEnabled: active,
                isGroupTab: false,
                previewCacheScopeKey: 'live-recovery',
                archiveScope: ConversationArchiveScope.c2c,
                theme: TUITheme(),
                feedScrollController: scroll,
                scrollPhysics: physics,
                controller: TIMUIKitConversationController(),
                getVisibleConversations: () => tabs.conversations,
                getArchivedConversations: () => [],
                conversationTimestampMs: (row) =>
                    (row.lastMessage?.timestamp ?? 0) * 1000,
                buildConversationRow: (row) =>
                    Text(row.lastMessage?.textElem?.text ?? ''),
                resolveConversationAvatarUrl: (_) =>
                    const AvatarImageWarmSource(url: null),
                onArchivedTap: () {},
                onGroupNoticeTap: () {},
                onGroupNoticePin: () async {},
                onGroupNoticeToggleMute: () async {},
                onGroupNoticeDelete: () async {},
              )));

  testWidgets(
      'SDK receive changes rendered preview and order without parent rebuild',
      (tester) async {
    final scroll = ScrollController();
    await tester.runAsync(() async {
      await seed();
      final other = V2TimConversation(
          conversationID: 'c2c_other',
          type: 1,
          userID: 'other',
          lastMessage: _message('other preview', 150),
          orderkey: 150);
      session.replaceProjectionForTest(
          [other, _row(_message('old preview', 100))]);
      await startRealtime();
    });
    await tester.pumpWidget(feed(scroll));
    await tester.pump();
    expect(tester.getTopLeft(find.text('old preview')).dy,
        greaterThan(tester.getTopLeft(find.text('other preview')).dy));
    await tester.runAsync(() => deliver(_message('rendered new preview', 200)));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('old preview'), findsNothing);
    expect(tester.getTopLeft(find.text('rendered new preview')).dy,
        lessThan(tester.getTopLeft(find.text('other preview')).dy));
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
  });

  for (final replaceController in [false, true]) {
    testWidgets(
        'sorting releases after feed lifecycle change: replace=$replaceController',
        (tester) async {
      await tester.runAsync(seed);
      final old = ScrollController();
      final next = ScrollController();
      await tester.pumpWidget(feed(old));
      await tester.pump();
      old.position.isScrollingNotifier.value = true;
      expect(tabs.isSortFrozenByScroll, isTrue);
      session.applyLastMessageLocally(
          conversationID: _conversationId,
          message: _message('new preview', 200));
      await tester.pumpWidget(feed(replaceController ? next : old,
          active: replaceController,
          physics: replaceController
              ? const BouncingScrollPhysics()
              : const ClampingScrollPhysics()));
      await tester.pump();
      expect(tabs.isSortFrozenByScroll, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      old.dispose();
      next.dispose();
    });
  }
}
