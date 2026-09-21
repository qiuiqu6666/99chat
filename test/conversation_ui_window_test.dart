import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/conversation_window_slide_result.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_sync_service.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

V2TimConversation _c2c({
  required String id,
  int unread = 0,
  bool pinned = false,
  int orderkey = 0,
  String showName = 'n',
}) {
  return V2TimConversation(
    conversationID: id,
    type: 1,
    userID: id.replaceFirst('c2c_', ''),
    unreadCount: unread,
    isPinned: pinned,
    orderkey: orderkey,
    showName: showName,
  );
}

V2TimConversation _group({
  required String id,
  int orderkey = 0,
  String showName = 'g',
  int unread = 0,
  bool pinned = false,
}) {
  final gid = id.replaceFirst('group_', '');
  return V2TimConversation(
    conversationID: id,
    type: 2,
    groupID: gid,
    unreadCount: unread,
    isPinned: pinned,
    orderkey: orderkey,
    showName: showName,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ui window snapshot', () {
    late ChatSessionController notifier;

    setUp(() {
      ConversationLocalStore.bypassUpsertCoalesceForTest = true;
      ConversationLocalStore.instance.debugOwnerUserId = 'window_test_user';
      notifier = ChatSessionController.instance;
    });

    tearDown(() async {
      notifier.clearSessionProjection();
      await ConversationLocalStore.instance.clearForOwner('window_test_user');
      ConversationLocalStore.instance.debugOwnerUserId = null;
      ConversationLocalStore.bypassUpsertCoalesceForTest = false;
    });

    test('cold pinned outside snapshot limit still enters loadUiWindow',
        () async {
      final seed = <V2TimConversation>[];
      for (var i = 0; i < 80; i++) {
        // 近期会话占满 snapshot；isPinned=false 模拟列未对齐。
        seed.add(_c2c(id: 'c2c_hot_$i', orderkey: 900000 - i));
      }
      // 很旧的置顶会话：按 active_time 进不了 LIMIT 40。
      seed.add(
        _c2c(id: 'c2c_cold_pinned', orderkey: 1, pinned: false),
      );
      await ConversationLocalStore.instance.upsertBatch(conversations: seed);

      ConversationPinSyncService.instance.debugReplacePinnedIdsForTest([
        'c2c_cold_pinned',
      ], markHydrated: true);
      try {
        final window = await ConversationLocalStore.instance.loadUiWindow();
        expect(
          window.any((c) => c.conversationID == 'c2c_cold_pinned'),
          isTrue,
        );
        final pinned = window.firstWhere(
          (c) => c.conversationID == 'c2c_cold_pinned',
        );
        expect(pinned.isPinned, isTrue);
      } finally {
        await ConversationPinSyncService.instance.clearSession();
      }
    });

    test('shouldAdmit: cold rows stay out; unread and pinned rows enter', () {
      notifier.setConversationsForTest([
        _c2c(id: 'c2c_in_window', orderkey: 100),
      ]);
      expect(
        notifier.shouldAdmitToUiWindow(_c2c(id: 'c2c_cold', orderkey: 1)),
        isFalse,
      );
      expect(
        notifier.shouldAdmitToUiWindow(
          _c2c(id: 'c2c_unread', unread: 2, orderkey: 1),
        ),
        isTrue,
      );
      expect(
        notifier.shouldAdmitToUiWindow(
          _c2c(id: 'c2c_pin', pinned: true, orderkey: 1),
        ),
        isTrue,
      );

      notifier.setConversationsForTest([
        for (var i = 0; i < 40; i++)
          _c2c(id: 'c2c_floor_$i', orderkey: 100000 - i),
      ]);
      expect(
        notifier.shouldAdmitToUiWindow(_c2c(id: 'c2c_over_floor', orderkey: 1)),
        isFalse,
      );
      expect(
        notifier.shouldAdmitToUiWindow(
          _c2c(id: 'c2c_unread_over', unread: 1, orderkey: 1),
        ),
        isTrue,
      );
    });

    test('shouldBlockSnapshotWindowReload when user expanded', () {
      expect(
        ChatSessionController.shouldBlockSnapshotWindowReload(
          userExpanded: true,
          scrolling: false,
          pageLoadInFlight: false,
          windowNonEmpty: true,
        ),
        isTrue,
      );
      expect(
        ChatSessionController.shouldBlockSnapshotWindowReload(
          userExpanded: false,
          scrolling: false,
          pageLoadInFlight: false,
          windowNonEmpty: true,
        ),
        isFalse,
      );
      expect(
        ChatSessionController.shouldBlockSnapshotWindowReload(
          userExpanded: false,
          scrolling: true,
          pageLoadInFlight: false,
          windowNonEmpty: true,
        ),
        isTrue,
      );
      expect(
        ChatSessionController.shouldBlockSnapshotWindowReload(
          userExpanded: true,
          scrolling: false,
          pageLoadInFlight: false,
          windowNonEmpty: false,
        ),
        isFalse,
      );
    });

    test('applyWindowPatches does not grow past type floor with cold upserts',
        () async {
      notifier.setConversationsForTest([
        for (var i = 0; i < 40; i++) _c2c(id: 'c2c_w_$i', orderkey: 100000 - i),
      ]);
      final before = notifier.conversations.length;
      await ChatSessionController.instance.applyWindowPatchesForTest(
        upserted: [
          for (var i = 0; i < 80; i++)
            _c2c(id: 'c2c_cold_$i', orderkey: 10 - (i % 10)),
        ],
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(notifier.conversations.length, before);
    });

    test('SDK patches preserve the loaded window without trimming its head',
        () async {
      final seed = <V2TimConversation>[];
      for (var i = 0; i < 350; i++) {
        seed.add(_c2c(id: 'c2c_$i', orderkey: 100000 - i));
      }
      notifier.setConversationsForTest(seed);

      await ChatSessionController.instance.applyWindowPatchesForTest(
        upserted: [
          _c2c(id: 'c2c_new_hot', unread: 5, orderkey: 200000),
        ],
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(
        notifier.conversations.length,
        greaterThanOrEqualTo(350),
      );
      expect(
        notifier.conversations.any((c) => c.conversationID == 'c2c_new_hot'),
        isTrue,
      );
    });

    test('pagingAnchorMs matches activeTimeMs for db cursor', () {
      final conversation = _group(id: 'group_anchor', orderkey: 900000);
      expect(
        ConversationLocalStore.pagingAnchorMs(conversation),
        ConversationLocalStore.activeTimeMs(conversation),
      );
      expect(ConversationLocalStore.pagingAnchorMs(conversation), 900000);
    });

    test('loadNewerPage store returns items hotter than cursor', () async {
      final seed = <V2TimConversation>[];
      for (var i = 0; i < 80; i++) {
        seed.add(_c2c(id: 'c2c_n_$i', orderkey: 700000 - i));
      }
      await ConversationLocalStore.instance.upsertBatch(conversations: seed);
      final page = await ConversationLocalStore.instance.loadNewerPage(
        afterActiveTime: 700000 - 40,
        afterConversationId: 'c2c_n_40',
        limit: 10,
        convType: 1,
      );
      expect(page.length, 10);
      expect(page.last.conversationID, 'c2c_n_39');
      expect(page.first.conversationID, 'c2c_n_30');
    });

    test('trimUiWindowWithTypeFloors is no-op when hard cap disabled', () {
      final mixed = <V2TimConversation>[];
      for (var i = 0; i < 50; i++) {
        mixed.add(_group(id: 'group_hot_$i', orderkey: 900000 - i));
        mixed.add(_c2c(id: 'c2c_cold_$i', orderkey: 100000 - i));
      }
      final trimmed = ConversationLocalStore.trimUiWindowWithTypeFloors(mixed);
      expect(trimmed.length, mixed.length);
    });

    test('searchConversations finds by showName', () async {
      await ConversationLocalStore.instance.upsertBatch(
        conversations: [
          _c2c(id: 'c2c_x', showName: '张三丰', orderkey: 1),
          _c2c(id: 'c2c_y', showName: '李四', orderkey: 2),
        ],
      );
      final hit = await ConversationLocalStore.instance.searchConversations(
        keyword: '张三',
      );
      expect(hit.length, 1);
      expect(hit.first.conversationID, 'c2c_x');
    });

    test('searchConversations finds c2c by @userId', () async {
      await ConversationLocalStore.instance.upsertBatch(
        conversations: [
          _c2c(id: 'c2c_ceh3qqoot7', showName: '小明', orderkey: 1),
          _c2c(id: 'c2c_other', showName: '李四', orderkey: 2),
        ],
      );
      final hit = await ConversationLocalStore.instance.searchConversations(
        keyword: '@ceh3qqoot7',
      );
      expect(hit.length, 1);
      expect(hit.first.conversationID, 'c2c_ceh3qqoot7');
    });

    test('searchConversations finds rows outside ui snapshot window', () async {
      final conversations = <V2TimConversation>[];
      for (var i = 0; i < 60; i++) {
        conversations.add(
          _c2c(
            id: 'c2c_user_$i',
            showName: i == 55 ? '冷门联系人甲' : '用户$i',
            orderkey: 1000 - i,
          ),
        );
      }
      await ConversationLocalStore.instance.upsertBatch(
        conversations: conversations,
      );

      final window = await ConversationLocalStore.instance.loadLocalFirstScreen(
        convType: 1,
        limit: ConversationPerfFlags.uiScrollPageSize,
      );
      expect(window.length, lessThan(conversations.length));
      expect(
        window.any((item) => item.conversationID == 'c2c_user_55'),
        isFalse,
      );

      final hit = await ConversationLocalStore.instance.searchConversations(
        keyword: '冷门联系人',
        limit: 100,
      );
      expect(hit.length, 1);
      expect(hit.first.conversationID, 'c2c_user_55');
    });

    test('searchConversationsAllPages paginates without stalling', () async {
      final conversations = <V2TimConversation>[];
      for (var i = 0; i < 120; i++) {
        conversations.add(
          _c2c(
            id: 'c2c_match_$i',
            showName: '匹配群友$i',
            orderkey: 2000 - i,
          ),
        );
      }
      conversations.add(
        _c2c(id: 'c2c_other', showName: '无关会话', orderkey: 1),
      );
      await ConversationLocalStore.instance.upsertBatch(
        conversations: conversations,
      );

      var batchCount = 0;
      final all =
          await ConversationLocalStore.instance.searchConversationsAllPages(
        keyword: '匹配群友',
        pageSize: 50,
        maxResults: 500,
        maxPages: 30,
        onBatch: (_, __) {
          batchCount++;
        },
      );
      expect(all.length, 120);
      expect(batchCount, greaterThan(1));
    });

    test('searchConversationsAllPages stops when cancelled', () async {
      final conversations = <V2TimConversation>[];
      for (var i = 0; i < 120; i++) {
        conversations.add(
          _c2c(
            id: 'c2c_cancel_$i',
            showName: '取消测试$i',
            orderkey: 3000 - i,
          ),
        );
      }
      await ConversationLocalStore.instance.upsertBatch(
        conversations: conversations,
      );

      var pages = 0;
      final partial =
          await ConversationLocalStore.instance.searchConversationsAllPages(
        keyword: '取消测试',
        pageSize: 20,
        maxResults: 500,
        maxPages: 30,
        shouldCancel: () {
          pages++;
          return pages >= 2;
        },
      );
      expect(partial.length, lessThan(120));
      expect(partial.length, greaterThanOrEqualTo(20));
    });
  });
}
