import 'package:flutter/foundation.dart';
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

const _owner = 'received_preview_owner';
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

  for (final isSelf in [false, true]) {
    test(
        'SDK already contains new message but local preview is old: self=$isSelf',
        () async {
      await seed();
      final incoming = _message('new preview', 200, isSelf: isSelf);
      sync.debugGetConversationOverride = (_) async => _row(
            _message('new preview', 200, isSelf: isSelf),
            unread: isSelf ? 0 : 1,
          );
      await sync.patchConversationLastMessage(
        conversationID: _conversationId,
        message: incoming,
      );
      await sync.flushPersistChangedForTest();
      expect(tabs.conversationForId(_conversationId)?.lastMessage?.msgID,
          'new preview');
      expect(
          (await local.conversationById(_conversationId))?.lastMessage?.msgID,
          'new preview');

      // Receiving both message and conversation callbacks must not add unread
      // twice, and repeating the fallback must not write the same row again.
      final flushes = sync.persistFlushInvocationCount;
      for (var i = 0; i < 3; i++) {
        await sync.patchConversationLastMessage(
          conversationID: _conversationId,
          message: incoming,
        );
      }
      await sync.flushPersistChangedForTest();
      expect(
          tabs.conversationForId(_conversationId)?.unreadCount, isSelf ? 0 : 1);
      expect(sync.persistFlushInvocationCount, flushes);
    });
  }

  test('pending sync replay commits even when SDK already has the message',
      () async {
    await seed();
    sync.debugGetConversationOverride =
        (_) async => _row(_message('replayed preview', 200), unread: 1);
    sync.queuePendingPreviewPatchForTest(
      conversationId: _conversationId,
      message: _message('replayed preview', 200),
    );
    await sync.forceFlushPendingPatchesForTest();
    expect(tabs.conversationForId(_conversationId)?.lastMessage?.msgID,
        'replayed preview');
    expect((await local.conversationById(_conversationId))?.lastMessage?.msgID,
        'replayed preview');
  });

  test('SDK ordinary message updates preview without conversation callback',
      () async {
    await seed();
    await startRealtime();
    await deliver(_message('received preview', 200));
    expect(tabs.conversationForId(_conversationId)?.lastMessage?.msgID,
        'received preview');
    // Preview repair does not invent unread authority.
    expect(tabs.conversationForId(_conversationId)?.unreadCount, 0);
  });

  for (final group in [false, true]) {
    test(
        'late SDK callback preserves received preview and authoritative unread: group=$group',
        () async {
      await seed(group: group);
      await startRealtime();
      final incoming = _message('newest', 200, group: group, seq: '12');
      final id = _row(incoming).conversationID;
      await deliver(incoming);
      session.applyPendingRealtimeProjection(
          [_row(_message('late old snapshot', 100, group: group), unread: 1)],
          reason: 'sdk_realtime_authoritative');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(tabs.conversationForId(id)?.lastMessage?.msgID, 'newest');
      expect(tabs.conversationForId(id)?.unreadCount, 1);

      session.applyPendingRealtimeProjection([_row(incoming, unread: 1)],
          reason: 'sdk_realtime_authoritative');
      await deliver(incoming);
      expect(tabs.conversationForId(id)?.unreadCount, 1);
      expect(tabs.conversationForId(id)?.lastMessage?.msgID, 'newest');
    });

    test(
        '100 same-second SDK messages advance preview without per-message I/O: group=$group',
        () async {
      await seed(group: group);
      await startRealtime();
      final id = group ? 'group_$_group' : _conversationId;
      for (var i = 1; i <= 100; i++) {
        messages.listener!.onRecvNewMessage(
            _message('burst-$i', 200, group: group, seq: '$i'));
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(tabs.conversationForId(id)?.lastMessage?.msgID, 'burst-100');
      expect(tabs.conversationForId(id)?.lastMessage?.timestamp, 200);
      expect(tabs.conversationForId(id)?.unreadCount, 0);
      expect(sync.persistFlushInvocationCount, 0);
      expect(platformCalls.where((method) => method == 'getConversation'),
          isEmpty);
      await deliver(_message('late-burst-50', 200, group: group, seq: '50'));
      expect(tabs.conversationForId(id)?.lastMessage?.msgID, 'burst-100');
    });
  }

  test('previous account callback cannot change preview', () async {
    await seed();
    await startRealtime();
    SessionIdentityService.instance.invalidate(reason: 'preview_test');
    await deliver(_message('stale account preview', 200));
    expect(tabs.conversationForId(_conversationId)?.lastMessage?.msgID,
        'old preview');
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final covered in [false, true]) {
      testWidgets(
          '${platform.name} visible feed catches up with covered=$covered',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final scroll = ScrollController();
        final controller = TIMUIKitConversationController();
        Widget feed(bool visible) => MaterialApp(
              home: TickerMode(
                enabled: visible,
                child: ConversationFeedBody(
                  workEnabled: visible,
                  isGroupTab: false,
                  previewCacheScopeKey: 'received-preview',
                  archiveScope: ConversationArchiveScope.c2c,
                  theme: TUITheme(),
                  feedScrollController: scroll,
                  scrollPhysics: const ClampingScrollPhysics(),
                  controller: controller,
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
                ),
              ),
            );
        try {
          await tester.runAsync(() async {
            await seed();
            await startRealtime();
          });
          await tester.pumpWidget(feed(true));
          expect(find.text('old preview'), findsOneWidget);
          if (covered) {
            ActiveChatRegistry.instance.enter(_conversationId);
            await tester.pumpWidget(feed(false));
          }
          await tester
              .runAsync(() => deliver(_message('visible new preview', 200)));
          ActiveChatRegistry.instance.reset();
          if (covered) {
            await tester.runAsync(
                () => session.patchConversationAfterChatLeave(_conversationId));
          }
          await tester.pumpWidget(feed(true));
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('visible new preview'), findsOneWidget);
          expect(find.text('old preview'), findsNothing);
        } finally {
          await tester.runAsync(sync.detachRealtimeListeners);
          await tester.pumpWidget(const SizedBox.shrink());
          scroll.dispose();
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
