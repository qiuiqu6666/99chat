import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/conversation.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_unread_clear_service.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_scope_unread_badge.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

V2TimConversation _row(String peer, String message, int unread,
        {int timestamp = 100, int? seq, bool group = false}) =>
    V2TimConversation(
      conversationID: '${group ? 'group' : 'c2c'}_$peer',
      userID: group ? null : peer,
      groupID: group ? peer : null,
      type: group ? 2 : 1,
      unreadCount: unread,
      lastMessage: V2TimMessage.fromJson({
        'message_msg_id': message,
        'message_server_time': timestamp,
        'message_risk_type_identified': 0,
      })
        ..elemType = 1
        ..seq = seq?.toString()
        ..userID = group ? null : peer
        ..groupID = group ? peer : null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = ConversationLocalStore.instance;
  final tabs = ConversationTabStore.instance;
  final controller = ChatSessionController.instance;
  final aggregate = ConversationUnreadAggregate.instance;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() {
    store.resetAnchorStateForTest();
    store.debugOwnerUserId = 'read_tab_consistency_owner';
    tabs.clear();
    tabs.notifyColdStartEnded();
    aggregate.resetForTest();
  });
  tearDown(() {
    controller.clearSessionProjection();
    aggregate.resetForTest();
    store.resetAnchorStateForTest();
    store.debugOwnerUserId = null;
    ConversationSyncService.instance.markReadStoreOverride = null;
    ConversationTabStore.debugFetchOverride = null;
    ConversationUnreadClearService.resetCoordinatorStateForTesting();
  });

  void markSeen({bool group = false}) {
    final id = '${group ? 'group' : 'c2c'}_read';
    store.recordReadClearedAnchor(id,
        lastMessageId: 'seen',
        lastMessageTimestamp: 100,
        lastMessageSeq: group ? 10 : 0);
    controller.zeroUnreadLocally(id);
  }

  for (final group in [false, true]) {
    test('delayed SDK callback keeps read row and tab aligned, group=$group',
        () {
      controller.applyPendingRealtimeProjection([
        _row('read', 'seen', 1, group: group, seq: group ? 10 : null),
        _row('other', 'unseen', 2, group: group),
      ], reason: 'sdk_realtime');
      tabs.flushRealtimePatches();
      markSeen(group: group);
      final replay =
          _row('read', 'seen', 1, group: group, seq: group ? 10 : null);
      controller
          .applyPendingRealtimeProjection([replay], reason: 'sdk_reconnect');
      tabs.flushRealtimePatches();

      expect(
          tabs
              .conversationForId('${group ? 'group' : 'c2c'}_read')!
              .unreadCount,
          0);
      expect(
          group
              ? aggregate.groupNotifiableUnreadSum
              : aggregate.c2cNotifiableUnreadSum,
          2);
    });

    test('post-read SDK calibration cannot restore old unread, group=$group',
        () async {
      controller.applyPendingRealtimeProjection([
        _row('read', 'seen', 1, group: group, seq: group ? 10 : null),
      ], reason: 'sdk_realtime');
      tabs.flushRealtimePatches();
      markSeen(group: group);
      final sdkRow =
          _row('read', 'seen', 1, group: group, seq: group ? 10 : null);
      aggregate.sdkPageForTest = (_) async => V2TimConversationResult(
              conversationList: [
                sdkRow,
                _row('unloaded', 'unseen', 2, group: group)
              ],
              isFinished: true);
      await aggregate.refreshFromStore(reason: 'reconnect');

      expect(
          group
              ? aggregate.groupNotifiableUnreadSum
              : aggregate.c2cNotifiableUnreadSum,
          2);
      expect(sdkRow.unreadCount, 1, reason: 'SDK input is not mutated');
      expect(
          await aggregate.readSdkUnreadCountsForIds([
            '${group ? 'group' : 'c2c'}_read',
          ]),
          {'${group ? 'group' : 'c2c'}_read': 0});
    });
  }

  test('local persistence without a snapshot preserves the exact read anchor',
      () {
    markSeen();
    final before = store.readBarrierFor('c2c_read')!;
    store.recordReadClearedAnchor('c2c_read');
    final after = store.readBarrierFor('c2c_read')!;
    expect(after.lastMessageId, 'seen');
    expect(after.lastMessageTimestamp, 100);
    expect(after.version, greaterThan(before.version));
    final replay = _row('read', 'seen', 1);
    store.resolveSdkUnreadAgainstReadBarrier(replay);
    expect(replay.unreadCount, 0);
  });

  test('read anchor survives an ID-only duplicate from leave persistence', () {
    markSeen(group: true);
    store.recordReadClearedAnchor('group_read', lastMessageId: 'seen');
    final after = store.readBarrierFor('group_read')!;
    expect(after.lastMessageTimestamp, 100);
    expect(after.lastMessageSeq, 10);
  });

  test(
      'opening an SDK-only row captures message order before local persistence',
      () async {
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async => (
              conversationList: <V2TimConversation>[],
              nextSeq: '0',
              isFinished: true,
              code: 0,
              desc: '',
            );
    ConversationSyncService.instance.markReadStoreOverride = (_) async {};
    // No unread means no SDK network dispatch; anchor capture is identical to
    // an unread open and must not depend on the absent SQLite row.
    await ConversationUnreadClearService.clearLocalForOpenFast(
        conversation: _row('read', 'seen', 0, group: true, seq: 10));
    await Future<void>.delayed(Duration.zero);
    final captured = store.readBarrierFor('group_read')!;
    expect(captured.lastMessageId, 'seen');
    expect(captured.lastMessageTimestamp, 100);
    expect(captured.lastMessageSeq, 10);
    store.recordReadClearedAnchor('group_read');
    final persisted = store.readBarrierFor('group_read')!;
    expect(persisted.lastMessageTimestamp, 100);
    expect(persisted.lastMessageSeq, 10);
  });

  test('new group sequence survives read protection within the same second',
      () async {
    aggregate
        .applySdkConversations([_row('read', 'seen', 1, group: true, seq: 10)]);
    markSeen(group: true);
    aggregate.sdkPageForTest = (_) async => V2TimConversationResult(
        conversationList: [_row('read', 'new', 1, group: true, seq: 11)],
        isFinished: true);
    await aggregate.refreshFromStore();
    expect(aggregate.groupNotifiableUnreadSum, 1);
    expect(store.readBarrierFor('group_read'), isNull);
  });

  test('in-flight SDK page cannot restore a read count after account switch',
      () async {
    final page = Completer<V2TimConversationResult>();
    aggregate.applySdkConversations([_row('read', 'seen', 1)]);
    aggregate.sdkPageForTest = (_) => page.future;
    final refresh = aggregate.refreshFromStore();
    aggregate.clearSession();
    store.debugOwnerUserId = 'another_owner';
    aggregate.applySdkConversations([_row('new-account', 'new', 2)]);
    page.complete(V2TimConversationResult(
        conversationList: [_row('read', 'seen', 1)], isFinished: true));
    await refresh;
    expect(aggregate.c2cNotifiableUnreadSum, 2);
  });

  test('new SDK page after a read keeps its visible row and tab cleared',
      () async {
    aggregate.applySdkConversations([_row('read', 'seen', 1)]);
    markSeen();
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async => (
              conversationList: [_row('read', 'seen', 1)],
              nextSeq: '0',
              isFinished: true,
              code: 0,
              desc: '',
            );
    await tabs.loadFirstPage(convType: 1);
    expect(tabs.conversationForId('c2c_read')!.unreadCount, 0);
    expect(aggregate.c2cNotifiableUnreadSum, 0);
  });

  test('different same-second message remains unread after read calibration',
      () async {
    aggregate.applySdkConversations([_row('read', 'seen', 1)]);
    markSeen();
    aggregate.sdkPageForTest = (_) async => V2TimConversationResult(
        conversationList: [_row('read', 'new-same-second', 1)],
        isFinished: true);
    await aggregate.refreshFromStore();
    expect(aggregate.c2cNotifiableUnreadSum, 1);
    expect(store.readBarrierFor('c2c_read'), isNotNull);
  });

  for (final timestamp in [100, 101]) {
    test('old read replay cannot clear a later unread at timestamp=$timestamp',
        () {
      controller.applyPendingRealtimeProjection([_row('read', 'seen', 1)],
          reason: 'sdk_realtime');
      tabs.flushRealtimePatches();
      markSeen();
      controller.applyPendingRealtimeProjection(
          [_row('read', 'new', 1, timestamp: timestamp)],
          reason: 'sdk_realtime');
      tabs.flushRealtimePatches();
      for (final oldCount in [1, 0]) {
        controller.applyPendingRealtimeProjection(
            [_row('read', 'seen', oldCount)],
            reason: 'sdk_late_read');
        tabs.flushRealtimePatches();
        expect(aggregate.c2cNotifiableUnreadSum, 1);
        expect(tabs.conversationForId('c2c_read')!.unreadCount, 1);
      }
      controller.applyPendingRealtimeProjection(
          [_row('read', 'new', 0, timestamp: timestamp)],
          reason: 'sdk_read_ack');
      tabs.flushRealtimePatches();
      expect(aggregate.c2cNotifiableUnreadSum, 0);
      expect(tabs.conversationForId('c2c_read')!.unreadCount, 0);
    });
  }

  test('preview rollback does not keep a deleted unread comparison anchor', () {
    controller.applyPendingRealtimeProjection([_row('read', 'deleted', 0)],
        reason: 'sdk_realtime');
    tabs.flushRealtimePatches();
    tabs.applyPatches([_row('read', 'previous', 0, timestamp: 90)],
        explicitLastMessageIds: {'c2c_read'}, reason: 'local_delete');
    for (final count in [1, 0]) {
      controller.applyPendingRealtimeProjection(
          [_row('read', 'new', count, timestamp: 95)],
          reason: 'sdk_realtime');
      tabs.flushRealtimePatches();
      expect(aggregate.c2cNotifiableUnreadSum, count);
      expect(tabs.conversationForId('c2c_read')!.unreadCount, count);
    }
  });

  test('count-only SDK read ACK clears an unloaded conversation', () {
    aggregate.applySdkConversations([_row('unloaded', 'latest', 2)]);
    aggregate.applySdkConversations([
      V2TimConversation(
          conversationID: 'c2c_unloaded',
          userID: 'unloaded',
          type: 1,
          unreadCount: 0),
    ]);
    expect(aggregate.c2cNotifiableUnreadSum, 0);
  });

  test('read during paginated calibration wins and leaves other chats unread',
      () async {
    final second = Completer<V2TimConversationResult>();
    aggregate.applySdkConversations([_row('read', 'seen', 1)]);
    aggregate.sdkPageForTest = (cursor) async => cursor == '0'
        ? V2TimConversationResult(
            conversationList: [_row('read', 'seen', 1)],
            nextSeq: '1',
            isFinished: false)
        : await second.future;
    final refresh = aggregate.refreshFromStore();
    await Future<void>.delayed(Duration.zero);
    markSeen();
    second.complete(V2TimConversationResult(
        conversationList: [_row('other', 'unseen', 2)], isFinished: true));
    await refresh;
    expect(aggregate.c2cNotifiableUnreadSum, 2);
  });

  testWidgets('message tab stays cleared after a delayed SDK read replay',
      (tester) async {
    final handler = FlutterError.onError;
    aggregate.sdkPageForTest = (_) async => V2TimConversationResult(
        conversationList: [_row('read', 'seen', 1)], isFinished: true);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: ConversationScopeUnreadBadge(
                scope: ConversationListScope.c2c))));
    controller.applyPendingRealtimeProjection([_row('read', 'seen', 1)],
        reason: 'sdk_realtime');
    await tester.pump();
    FlutterError.onError = handler;
    expect(find.text('1'), findsOneWidget);
    markSeen();
    await tester.pump();
    FlutterError.onError = handler;
    expect(find.text('1'), findsNothing);
    controller.applyPendingRealtimeProjection([_row('read', 'seen', 1)],
        reason: 'sdk_reconnect');
    tabs.flushRealtimePatches();
    await tester.pump();
    FlutterError.onError = handler;
    expect(find.text('1'), findsNothing);
    expect(tester.takeException(), isNull);
    aggregate.resetForTest();
    controller.clearSessionProjection();
    await tester.pump(const Duration(milliseconds: 100));
    FlutterError.onError = handler;
  });
}
