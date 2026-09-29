import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/conversation_projection_reason.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_gate_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';

V2TimConversation _c2c(String id, {int unread = 0, int recvOpt = 0}) {
  return V2TimConversation(
    conversationID: id,
    type: 1,
    userID: id.replaceFirst('c2c_', ''),
    unreadCount: unread,
    recvOpt: recvOpt,
    showName: id,
  );
}

V2TimConversation _group(String id, {int orderKey = 0}) {
  return V2TimConversation(
    conversationID: id,
    type: 2,
    groupID: id.replaceFirst('group_', ''),
    orderkey: orderKey,
    showName: id,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  late ConversationSyncService sync;

  setUp(() {
    // This suite exercises the SDK-primary projection only. An explicit empty
    // owner keeps the local-only C2C reconciliation path from invoking UIKit.
    ConversationLocalStore.instance.debugOwnerUserId = '';

    ConversationPerfGateLog.resetCountsForTest();
    ConversationTabStore.debugFetchOverride = null;
    ConversationTabStore.instance.clear();
    ChatSessionController.instance.clearSessionProjection();
    sync = ConversationSyncService.instance;
    sync.resetChatTransitionStateForTesting();
  });

  tearDown(() {
    ConversationLocalStore.instance.debugOwnerUserId = null;

    ConversationTabStore.debugFetchOverride = null;
    ConversationTabStore.instance.clear();
    ChatSessionController.instance.clearSessionProjection();
    sync.resetChatTransitionStateForTesting();
  });

  test('Phase4: pendingUiApply is no-op when sdk-primary', () {
    sync.notePendingUiApplyForTest(
      [_c2c('c2c_pending', unread: 2)],
      cause: 'quiet',
    );
    expect(sync.pendingUiApplyCountForTest, 0);
    expect(
      ConversationPerfGateLog.eventCountsForTest['mirror_skip_ui'] ?? 0,
      greaterThan(0),
    );
  });

  test('Phase4: flush pendingUiApply clears without DB UI when sdk-primary',
      () async {
    await sync.flushPendingUiApplyForTest(reason: 'quiet_end');
    expect(sync.pendingUiApplyCountForTest, 0);
    expect(
      ConversationPerfGateLog.eventCountsForTest['mirror_skip_ui'] ?? 0,
      greaterThan(0),
    );
  });

  test('Phase4: recvOpt patches TabStore without hydrate dual-write', () {
    ChatSessionController.instance.ensureTabStoreBridgeAttached();
    ConversationTabStore.instance.setItemsForTest(
      convType: 1,
      items: [_c2c('c2c_recv')],
      finished: true,
    );
    ConversationTabStore.instance.applyPatches(
      [_c2c('c2c_recv')],
      reason: 'seed',
    );
    ConversationPerfGateLog.resetCountsForTest();

    ChatSessionController.instance.applyRecvOptLocally(
      conversationID: 'c2c_recv',
      recvOpt: 2,
      snapshot: _c2c('c2c_recv'),
    );

    expect(
      ConversationPerfGateLog.eventCountsForTest['type_hydrate_patched'] ?? 0,
      0,
    );
    expect(
      ConversationTabStore.instance
          .itemsForType(1)
          .firstWhere((c) => c.conversationID == 'c2c_recv')
          .recvOpt,
      2,
    );
  });

  test('Phase4: TabStore remains SDK-fake source for list reads', () async {
    ConversationTabStore.debugFetchOverride = ({
      required int convType,
      required String nextSeq,
      required int count,
    }) async {
      return (
        conversationList: <V2TimConversation>[_c2c('c2c_fake_page')],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: '',
      );
    };
    addTearDown(() => ConversationTabStore.debugFetchOverride = null);

    final notifier = ChatSessionController.instance;
    notifier.ensureTabStoreBridgeAttached();
    await ConversationTabStore.instance.loadFirstPage(convType: 1);

    expect(notifier.conversationAtTypeIndex(1, 0)?.conversationID,
        'c2c_fake_page');
    expect(
      ConversationPerfGateLog.eventCountsForTest['tab_store_page'] ?? 0,
      greaterThan(0),
    );
  });

  test('Phase4: compatibility recovery preserves a deep group window',
      () async {
    var fetches = 0;
    ConversationTabStore.debugFetchOverride = ({
      required int convType,
      required String nextSeq,
      required int count,
    }) async {
      fetches++;
      return (
        conversationList: const <V2TimConversation>[],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: '',
      );
    };

    final groups = List<V2TimConversation>.generate(
      150,
      (index) => _group('group_deep_$index', orderKey: 10000 - index),
    );
    final tabStore = ConversationTabStore.instance;
    tabStore.setItemsForTest(
      convType: 1,
      items: <V2TimConversation>[_c2c('c2c_existing')],
      nextSeq: 'deep_c2c_cursor',
      finished: false,
    );
    tabStore.setItemsForTest(
      convType: 2,
      items: groups,
      nextSeq: 'deep_group_cursor',
      finished: false,
    );
    final cursorBefore = tabStore.pageCursorForType(2)?.conversationID;

    await ChatSessionController.instance.restoreProjection(
      reason: ConversationStoreProjectionReason.sdkProjectionRestore,
    );

    expect(fetches, 0);
    expect(tabStore.countForType(2), groups.length);
    expect(tabStore.nextSeqForType(2), 'deep_group_cursor');
    expect(tabStore.pageCursorForType(2)?.conversationID, cursorBefore);
    expect(
      tabStore.itemsForType(2).map((row) => row.conversationID),
      groups.map((row) => row.conversationID),
    );
    expect(
      ConversationPerfGateLog
              .eventCountsForTest['sdk_primary_restore_preserve_view'] ??
          0,
      2,
    );
  });

  test('Phase4: compatibility recovery primes an empty Store', () async {
    var fetches = 0;
    ConversationTabStore.debugFetchOverride = ({
      required int convType,
      required String nextSeq,
      required int count,
    }) async {
      fetches++;
      return (
        conversationList: convType == 1
            ? <V2TimConversation>[_c2c('c2c_primed')]
            : <V2TimConversation>[_group('group_primed')],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: '',
      );
    };

    await ChatSessionController.instance.restoreProjection(
      reason: ConversationStoreProjectionReason.sdkProjectionRestore,
    );

    expect(fetches, 2);
    expect(
      ConversationTabStore.instance.itemsForType(1).single.conversationID,
      'c2c_primed',
    );
    expect(
      ConversationTabStore.instance.itemsForType(2).single.conversationID,
      'group_primed',
    );
  });

  test('SDK realtime patch wakes a terminal empty projection', () async {
    ConversationTabStore.debugFetchOverride = (
            {required int convType,
            required String nextSeq,
            required int count}) async =>
        (
          conversationList: <V2TimConversation>[],
          nextSeq: '0',
          isFinished: true,
          code: 0,
          desc: ''
        );
    final controller = ChatSessionController.instance;
    controller.ensureTabStoreBridgeAttached();
    await ConversationTabStore.instance.ensurePrimed(convType: 1);
    ConversationTabStore.instance
        .applyPatches([_c2c('c2c_late_bootstrap')], reason: 'sdk_realtime');
    expect(
        controller.conversations.single.conversationID, 'c2c_late_bootstrap');
  });

  test('Phase4: typed group SDK page reaches TabStore without a SQLite mirror',
      () async {
    final store = ConversationLocalStore.instance;
    const owner = 'phase4_typed_group_projection_owner';
    store.debugOwnerUserId = owner;
    sync.debugOwnerUserId = owner;
    await GroupMembershipSyncService.instance.clearSession();
    await store.clearForOwner(owner);
    addTearDown(() async {
      sync.debugOwnerUserId = null;
      store.debugOwnerUserId = null;
      await store.clearForOwner(owner);
    });

    ConversationTabStore.debugFetchOverride = ({
      required int convType,
      required String nextSeq,
      required int count,
    }) async {
      expect(convType, 2);
      return (
        conversationList: <V2TimConversation>[
          _group('group_typed_projection'),
        ],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: '',
      );
    };
    addTearDown(
      () => ConversationTabStore.debugFetchOverride = null,
    );

    await sync.syncFromSdkByType(
      convType: 2,
      reason: 'test_typed_group_projection',
      reset: true,
    );

    expect(
      ConversationTabStore.instance
          .itemsForType(2)
          .any((row) => row.conversationID == 'group_typed_projection'),
      isTrue,
    );
    expect(ConversationTabStore.instance.itemsForType(1), isEmpty);
    expect(await store.countRows(ownerUserId: owner), 0);
  });

  test('Phase4: C2C bootstrap failure retries independently of groups',
      () async {
    final store = ConversationLocalStore.instance;
    const owner = 'phase4_c2c_retry_owner';
    store.debugOwnerUserId = owner;
    sync.debugOwnerUserId = owner;
    addTearDown(() async {
      sync.debugOwnerUserId = null;
      store.debugOwnerUserId = null;
      await store.clearForOwner(owner);
    });

    await store.clearForOwner(owner);
    var c2cCalls = 0;
    var groupCalls = 0;
    ConversationTabStore.debugFetchOverride = ({
      required int convType,
      required String nextSeq,
      required int count,
    }) async {
      if (convType == 1) {
        c2cCalls++;
        if (c2cCalls == 1) {
          return (
            conversationList: const <V2TimConversation>[],
            nextSeq: '0',
            isFinished: true,
            code: 70001,
            desc: 'temporary C2C failure',
          );
        }
        return (
          conversationList: <V2TimConversation>[_c2c('c2c_retry_success')],
          nextSeq: '0',
          isFinished: true,
          code: 0,
          desc: '',
        );
      }
      groupCalls++;
      return (
        conversationList: <V2TimConversation>[_group('group_bootstrap')],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: '',
      );
    };
    addTearDown(
      () => ConversationTabStore.debugFetchOverride = null,
    );

    expect(await sync.bootstrapTypedFirstScreen(reason: 'test_c2c_failure'),
        ConversationBootstrapResult.failed);
    expect(groupCalls, 1);
    expect(c2cCalls, 1);
    expect(ConversationTabStore.instance.primedForType(1), isFalse);
    expect(ConversationTabStore.instance.lastLoadFailedForType(1), isTrue);
    expect(ConversationTabStore.instance.itemsForType(2).single.conversationID,
        'group_bootstrap');

    // The next recovery joins the SDK-owned first window. Successful groups
    // stay loaded; only the failed C2C type is requested again.
    expect(await sync.bootstrapTypedFirstScreen(reason: 'test_c2c_retry'),
        ConversationBootstrapResult.success);
    expect(groupCalls, 1);
    expect(c2cCalls, 2);
    expect(ConversationTabStore.instance.primedForType(1), isTrue);
    expect(ConversationTabStore.instance.lastLoadFailedForType(1), isFalse);
    expect(ConversationTabStore.instance.itemsForType(1).single.conversationID,
        'c2c_retry_success');
    expect(await store.countRows(ownerUserId: owner), 0);
  });
}
