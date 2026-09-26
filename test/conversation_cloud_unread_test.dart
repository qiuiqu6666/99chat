import 'dart:async';

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
import 'package:tencent_cloud_chat_demo/src/services/group_conversation_unread_helper.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation_result.dart';
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

  test('remote read wins even when its preview is older', () {
    sdk(_row(40, seq: 50));
    sdk(_row(0, seq: 10));
    expectUnread(0);
    expect(tabs.conversationForId(_id)?.lastMessage?.msgID, 'message_50');
    sdk(_row(3, seq: 51));
    expectUnread(3);
  });

  test('a local read marker cannot suppress an SDK count', () {
    sdk(_row(4));
    store.recordReadClearedAnchor(_id,
        lastMessageId: 'message_10',
        lastMessageTimestamp: 1800000010,
        lastMessageSeq: 10);
    sdk(_row(4));
    expectUnread(4);
  });

  test('metadata and preview projections do not invent unread counts', () {
    sdk(_row(4));
    tabs.applyPatches([_row(0)..isPinned = true]);
    expectUnread(4);
    aggregate.updateSdkProjectionIfActive([_row(17, seq: 11)]);
    expectUnread(4);
    session.applyLastMessageLocally(
        conversationID: _id,
        message: _row(17, seq: 12).lastMessage!,
        bumpUnread: true);
    expectUnread(4);
  });

  test('SDK bursts across many conversations retain one batched publication',
      () {
    var notifications = 0;
    void changed() => notifications++;
    tabs.addListener(changed);
    try {
      for (var i = 0; i < 50; i++) {
        session.applyPendingRealtimeProjection([
          _row(1)
            ..conversationID = 'group_@TGS#burst_$i'
            ..groupID = '@TGS#burst_$i',
        ], reason: 'sdk_realtime');
      }
      expect(notifications, 0);
      tabs.flushRealtimePatches();
      expect(notifications, 1);
      expect(aggregate.groupNotifiableUnreadSum, 50);
      expect(tabs.itemsForType(2), hasLength(50));
    } finally {
      tabs.removeListener(changed);
    }
  });

  test('missing SDK unread field preserves the previous count', () {
    sdk(_row(4));
    sdk(_row(null, seq: 11));
    expectUnread(4);
  });

  test('a count-only SDK update does not temporarily unmute the badge', () {
    sdk(_row(4)..recvOpt = 1);
    session.applyPendingRealtimeProjection([_row(5)..recvOpt = null],
        reason: 'sdk_realtime');
    expect(aggregate.groupNotifiableUnreadSum, 0);
    tabs.flushRealtimePatches();
    expect(tabs.conversationForId(_id)?.unreadCount, 5);
    expect(aggregate.groupNotifiableUnreadSum, 0);
  });

  test('local metadata cannot advance the SDK read watermark', () {
    sdk(_row(4));
    aggregate.updateSdkProjectionIfActive([_row(4, seq: 99)..recvOpt = 1]);
    expect(aggregate.sdkSnapshotFor(_id)?.lastMessage?.seq, '10');
  });

  test('calibration refreshes the SDK total used by the desktop badge',
      () async {
    sdk(_row(4));
    aggregate.applySdkTotalUnreadCount(4);
    aggregate.sdkPageForTest = (_) async =>
        V2TimConversationResult(conversationList: [], isFinished: true);
    aggregate.sdkTotalForTest = () async => 0;
    await aggregate.refreshFromStore();
    expectUnread(0);
    expect(aggregate.sdkTotalUnreadCount, 0);
  });

  test('late total query cannot replace a newer SDK total callback', () async {
    sdk(_row(4));
    aggregate.applySdkTotalUnreadCount(4);
    final started = Completer<void>();
    final total = Completer<int>();
    aggregate.sdkPageForTest = (_) async =>
        V2TimConversationResult(conversationList: [_row(4)], isFinished: true);
    aggregate.sdkTotalForTest = () {
      started.complete();
      return total.future;
    };
    final refreshing = aggregate.refreshFromStore();
    await started.future;
    aggregate.applySdkTotalUnreadCount(8);
    total.complete(4);
    await refreshing;
    expect(aggregate.sdkTotalUnreadCount, 8);
  });

  for (final fast in [false, true]) {
    test('offline read retains counts and a durable bounded intent: fast=$fast',
        () async {
      final called = Completer<void>();
      TencentConversationReadService.cleanUnreadForTesting = ({
        required conversationID,
        required cleanTimestamp,
        required cleanSequence,
      }) async {
        expect(conversationID, _id);
        expect(cleanSequence, 10);
        if (!called.isCompleted) called.complete();
        return V2TimCallback(code: 6017, desc: 'offline');
      };
      final row = _row(40);
      sdk(row);
      var syntheticClears = 0;
      if (fast) {
        await ConversationUnreadClearService.clearLocalForOpenFast(
            conversation: row,
            markViewModelReadLocally: (_) => syntheticClears++);
        await called.future.timeout(const Duration(seconds: 5));
      } else {
        await ConversationUnreadClearService.clearLocalForOpen(
            conversation: row,
            markViewModelReadLocally: (_) => syntheticClears++);
      }
      await ConversationUnreadClearService.scheduleSdkUnreadClean(
          conversationID: _id, trigger: SdkUnreadCleanTrigger.open);
      expectUnread(40);
      expect(row.unreadCount, 40);
      expect(syntheticClears, 0);
      final pending = await ConversationReadOutboxStore.instance
          .find(ownerUserId: _owner, conversationId: _id);
      expect(pending?.cleanSequence, 10);
      sdk(_row(0)); // SDK reports that another device has read it.
      expectUnread(0);
    });
  }

  test('delayed SDK page cannot undo a newer remote read callback', () async {
    final page = Completer<void>();
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async {
      await page.future;
      return (
        conversationList: [_row(40)],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: ''
      );
    };
    sdk(_row(40));
    final loading = tabs.loadFirstPage(convType: 2);
    await Future<void>.delayed(Duration.zero);
    sdk(_row(0, seq: 9));
    page.complete();
    await loading;
    expectUnread(0);
  });

  test('SDK page accepts remote read without needing a changed callback',
      () async {
    sdk(_row(40));
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async => (
              conversationList: [_row(0, seq: 9)],
              nextSeq: '0',
              isFinished: true,
              code: 0,
              desc: ''
            );
    await tabs.loadFirstPage(convType: 2);
    expectUnread(0);
  });

  test('reconnect calibration updates loaded rows even without callbacks',
      () async {
    sdk(_row(40));
    aggregate.sdkPageForTest = (_) async =>
        V2TimConversationResult(conversationList: [], isFinished: true);
    await aggregate.refreshFromStore();
    expectUnread(0);
  });

  test('new SDK callback wins over an in-flight reconnect calibration',
      () async {
    sdk(_row(40));
    final page = Completer<V2TimConversationResult>();
    aggregate.sdkPageForTest = (_) => page.future;
    final refreshing = aggregate.refreshFromStore();
    sdk(_row(2, seq: 12));
    page.complete(
        V2TimConversationResult(conversationList: [], isFinished: true));
    await refreshing;
    expectUnread(2);
  });

  test(
      'complete SDK calibration fences older queries for previously unseen rows',
      () async {
    final oldRevision = aggregate.sdkPageRevision;
    aggregate.applySdkConversations([]);
    aggregate.sdkPageForTest = (_) async =>
        V2TimConversationResult(conversationList: [], isFinished: true);
    await aggregate.refreshFromStore();
    aggregate.applySdkPage([_row(40)], startedAtRevision: oldRevision);
    expect(aggregate.sdkUnreadCountFor(_id), 0);
    expect(aggregate.groupNotifiableUnreadSum, 0);
  });

  test('SDK deletion fences a pending query before the initial seed finishes',
      () {
    final before = aggregate.sdkPageRevision;
    aggregate.removeSdkConversations([_id]);
    aggregate.applySdkPage([_row(40)], startedAtRevision: before);
    expect(aggregate.sdkUnreadCountFor(_id), 0);
    expect(aggregate.groupNotifiableUnreadSum, 0);
  });

  test('late UI page also respects a completed SDK calibration', () async {
    sdk(_row(40));
    final page = Completer<void>();
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async {
      await page.future;
      return (
        conversationList: [_row(40)],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: ''
      );
    };
    final loading = tabs.loadFirstPage(convType: 2);
    await Future<void>.delayed(Duration.zero);
    aggregate.sdkPageForTest = (_) async =>
        V2TimConversationResult(conversationList: [], isFinished: true);
    await aggregate.refreshFromStore();
    page.complete();
    await loading;
    expectUnread(0);
  });

  test('local database read commits cannot overwrite synchronized counts',
      () async {
    await store.upsertBatch(conversations: [_row(40)], ownerUserId: _owner);
    sdk(_row(40));
    await sync.markConversationReadLocally(_id, forceImmediateUi: true);
    expectUnread(40);
  });

  test('selected SDK-only conversation can be read without a SQLite row',
      () async {
    sdk(_row(40));
    expect(await store.conversationById(_id, ownerUserId: _owner), isNull);
    final preview =
        await ConversationUnreadClearService.previewMarkReadForEditAction(
            mode: MarkReadEditMode.selected,
            listScope: MarkReadListScope.group,
            selectedIds: {_id});
    expect(preview.clearedIds, [_id]);
    expect(preview.unreadSumBefore, 40);
    final called = Completer<void>();
    TencentConversationReadService.cleanUnreadForTesting = ({
      required conversationID,
      required cleanTimestamp,
      required cleanSequence,
    }) async {
      expect(cleanSequence, 10);
      if (!called.isCompleted) called.complete();
      return V2TimCallback(code: 6017, desc: 'offline');
    };
    final result = await ConversationUnreadClearService.markReadForEditAction(
        mode: MarkReadEditMode.selected,
        listScope: MarkReadListScope.group,
        selectedIds: {_id});
    expect(result.sdkPath, 'queue');
    await called.future.timeout(const Duration(seconds: 5));
    await ConversationUnreadClearService.enqueueSdkUnreadClean(_id);
    expectUnread(40);
    expect(
        (await ConversationReadOutboxStore.instance
                .find(ownerUserId: _owner, conversationId: _id))
            ?.cleanSequence,
        10);
  });

  test('silent group tips do not subtract from cloud unread', () async {
    sdk(_row(4));
    aggregate.sdkPageForTest = (_) async =>
        V2TimConversationResult(conversationList: [_row(4)], isFinished: true);
    await GroupConversationUnreadHelper.absorbOneUnreadBump(_id,
        effectId: 'silent_tip');
    await aggregate.refreshFromStore();
    expectUnread(4);
  });

  test('bulk failure retains counts and bounded targets for retry', () async {
    sdk(_row(40));
    aggregate.sdkPageForTest = (_) async =>
        V2TimConversationResult(conversationList: [_row(40)], isFinished: true);
    final preview =
        await ConversationUnreadClearService.previewMarkReadForEditAction(
            mode: MarkReadEditMode.scopeAll,
            listScope: MarkReadListScope.group);
    expect(preview.clearedIds, [_id]);
    expect(preview.unreadSumBefore, 40);
    await ConversationReadOutboxStore.instance.enqueue(
        ownerUserId: _owner,
        conversationId: _id,
        cleanSequence: 10,
        lastReadAtMs: 123);
    TencentConversationReadService.cleanUnreadForTesting = ({
      required conversationID,
      required cleanTimestamp,
      required cleanSequence,
    }) async {
      expect(conversationID, 'group');
      return V2TimCallback(code: 6017, desc: 'offline');
    };
    await ConversationUnreadClearService.cleanSdkUnreadForType(
        isGroup: true,
        durableConversationIds: [_id],
        durableOwnerUserId: _owner,
        durableReadAtMs: 123);
    expectUnread(40);
    final pending = await ConversationReadOutboxStore.instance
        .find(ownerUserId: _owner, conversationId: _id);
    expect(pending?.cleanSequence, 10);
    expect(pending?.attemptCount, 1);
    expect(pending?.nextRetryAtMs, lessThan(0));
  });

  test('account change discards an old unread calibration', () async {
    sdk(_row(40));
    final page = Completer<V2TimConversationResult>();
    aggregate.sdkPageForTest = (_) => page.future;
    final refreshing = aggregate.refreshFromStore();
    session.clearSessionProjection();
    page.complete(V2TimConversationResult(
        conversationList: [_row(40)], isFinished: true));
    await refreshing;
    expect(tabs.conversationForId(_id), isNull);
    expect(aggregate.groupNotifiableUnreadSum, 0);
    expect(aggregate.usesSdkUnread, isFalse);
  });
}
