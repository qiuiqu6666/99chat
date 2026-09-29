import 'dart:async';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/conversation.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_scope_unread_badge.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_unread_utils.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation_result.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/archived_conversation_store.dart';

V2TimConversation group(String id, int unread, {int recvOpt = 0}) =>
    V2TimConversation(
      conversationID: 'group_$id',
      groupID: id,
      type: 2,
      unreadCount: unread,
      recvOpt: recvOpt,
      groupType: 'Public',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final aggregate = ConversationUnreadAggregate.instance;
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() {
    aggregate.resetForTest();
    ConversationTabStore.instance.clear();
    ConversationTabStore.instance.notifyColdStartEnded();
  });

  test('one unread update evaluates one row in a 5000-conversation account',
      () {
    aggregate.applySdkConversations(
        List.generate(5000, (i) => group('@TGS#perf$i', 1)));
    expect(aggregate.groupNotifiableUnreadSum, 5000);
    final before = aggregate.sdkRowsEvaluatedForTest;
    aggregate.applySdkConversations([group('@TGS#perf0', 2)]);
    expect(aggregate.groupNotifiableUnreadSum, 5001);
    expect(aggregate.sdkRowsEvaluatedForTest - before, 1);
    aggregate.removeSdkConversations(['group_@TGS#perf0']);
    expect(aggregate.groupNotifiableUnreadSum, 4999);
  });
  tearDown(() {
    ChatSessionController.instance.clearSessionProjection();
    aggregate.resetForTest();
    clearArchivedConversationSessionState();
    ConversationTabStore.debugFetchOverride = null;
  });

  testWidgets('SDK callback renders group tab badge without any SQLite commit',
      (tester) async {
    final errorHandler = FlutterError.onError;
    final rows = [group('@TGS#a', 4), group('@TGS#b', 1)];
    aggregate.sdkPageForTest = (_) async => V2TimConversationResult(
          conversationList: rows,
          isFinished: true,
        );
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      bottomNavigationBar: BottomNavigationBar(items: const [
        BottomNavigationBarItem(icon: Icon(Icons.chat), label: '消息'),
        BottomNavigationBarItem(
            icon: Stack(clipBehavior: Clip.none, children: [
              Icon(Icons.group),
              Positioned(
                  top: -5,
                  left: 12,
                  child: UnconstrainedBox(
                    child: ConversationScopeUnreadBadge(
                        scope: ConversationListScope.group),
                  )),
            ]),
            label: '群聊'),
      ]),
    )));
    expect(find.text('5'), findsNothing);
    ChatSessionController.instance.applyPendingRealtimeProjection(rows,
        reason: 'sdk_realtime_authoritative');
    await tester.pump();
    FlutterError.onError = errorHandler;
    expect(aggregate.groupNotifiableUnreadSum, 5);
    expect(find.text('5'), findsOneWidget);
    expect(tester.takeException(), isNull);
    ChatSessionController.instance.applyPendingRealtimeProjection(
      [group('@TGS#a', 0), group('@TGS#b', 0)],
      reason: 'sdk_realtime_authoritative',
    );
    await tester.pump();
    FlutterError.onError = errorHandler;
    expect(find.text('5'), findsNothing);
    expect(aggregate.groupNotifiableUnreadSum, 0);
    aggregate.resetForTest();
    ChatSessionController.instance.clearSessionProjection();
    await tester.pump(const Duration(milliseconds: 100));
    FlutterError.onError = errorHandler;
  });

  test('SDK calibration includes unloaded pages and preserves newer callbacks',
      () async {
    final second = Completer<V2TimConversationResult>();
    aggregate.sdkPageForTest = (cursor) async => cursor == '0'
        ? V2TimConversationResult(
            conversationList: [group('@TGS#a', 4)],
            nextSeq: '1',
            isFinished: false)
        : await second.future;
    aggregate.applySdkConversations([group('@TGS#a', 4)]);
    final refresh = aggregate.refreshFromStore();
    await Future<void>.delayed(Duration.zero);
    aggregate.applySdkConversations([group('@TGS#a', 6)]);
    aggregate.removeSdkConversations(['group_@TGS#deleted']);
    second.complete(V2TimConversationResult(conversationList: [
      group('@TGS#unloaded', 2),
      group('@TGS#muted', 9, recvOpt: 1),
      group('@TGS#deleted', 10),
    ], isFinished: true));
    await refresh;
    expect(aggregate.groupNotifiableUnreadSum, 8);
    archivedConversationGroupIDsNotifier.value = {'group_@TGS#a'};
    expect(aggregate.groupNotifiableUnreadSum, 2);
    aggregate.clearSession();
    expect(aggregate.groupNotifiableUnreadSum, 0);
  });

  test('SDK local mute, unmute, read and deletion keep the badge aligned', () {
    final controller = ChatSessionController.instance;
    controller.applyPendingRealtimeProjection([group('@TGS#local', 4)],
        reason: 'sdk_realtime');
    expect(aggregate.groupNotifiableUnreadSum, 4);
    ConversationTabStore.instance
        .applyPatches([group('@TGS#local', 4, recvOpt: 1)]);
    expect(aggregate.groupNotifiableUnreadSum, 0);
    ConversationTabStore.instance.applyPatches([group('@TGS#local', 4)]);
    expect(aggregate.groupNotifiableUnreadSum, 4);
    ConversationTabStore.instance.zeroUnreadLocallyMany(['group_@TGS#local']);
    expect(aggregate.groupNotifiableUnreadSum, 0);
    controller.applyPendingRealtimeProjection([group('@TGS#local', 1)],
        reason: 'sdk_realtime');
    expect(aggregate.groupNotifiableUnreadSum, 1);
    ConversationTabStore.instance.applyDeleted(['group_@TGS#local']);
    expect(aggregate.groupNotifiableUnreadSum, 0);
  });

  test('left pinned group cannot return through SDK push or pagination',
      () async {
    const id = '@TGS#left_pinned';
    final membership = GroupMembershipSyncService.instance;
    addTearDown(() => membership.clearExplicitGroupRemovalForTest(id));
    final row = group(id, 4)..isPinned = true;
    aggregate.sdkPageForTest = (_) async =>
        V2TimConversationResult(conversationList: [row], isFinished: true);
    final controller = ChatSessionController.instance;
    controller.applyPendingRealtimeProjection([row], reason: 'sdk_realtime');
    expect(ConversationTabStore.instance.itemsForType(2), hasLength(1));
    membership.markExplicitGroupRemovalForTest(id);
    expect(ConversationTabStore.instance.itemsForType(2), isEmpty);
    expect(aggregate.groupNotifiableUnreadSum, 0);
    controller.applyPendingRealtimeProjection([row], reason: 'sdk_realtime');
    expect(ConversationTabStore.instance.itemsForType(2), isEmpty);
    expect(aggregate.groupNotifiableUnreadSum, 0);
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async => (
              conversationList: [row],
              nextSeq: '0',
              isFinished: true,
              code: 0,
              desc: '',
            );
    await ConversationTabStore.instance.loadFirstPage(convType: 2);
    expect(ConversationTabStore.instance.itemsForType(2), isEmpty);
    await aggregate.refreshFromStore();
    expect(aggregate.groupNotifiableUnreadSum, 0);
    membership.clearExplicitGroupRemovalForTest(id);
    controller.applyPendingRealtimeProjection([row], reason: 'sdk_realtime');
    expect(ConversationTabStore.instance.itemsForType(2), hasLength(1));
  });

  test('folders reuse unloaded SDK unread rows and retain muted raw counts',
      () async {
    var fetches = 0;
    aggregate.sdkPageForTest = (_) async {
      fetches++;
      return V2TimConversationResult(conversationList: [
        group('@TGS#outside', 8, recvOpt: 1),
        V2TimConversation(
            conversationID: 'c2c_peer',
            type: 1,
            userID: 'peer',
            unreadCount: 3),
      ], isFinished: true);
    };
    final counts = await aggregate.readSdkUnreadCountsForIds(
        ['group_@TGS#outside', 'c2c_peer', 'peer', 'c2c_absent']);
    expect(counts,
        {'group_@TGS#outside': 8, 'c2c_peer': 3, 'peer': 3, 'c2c_absent': 0});
    expect(aggregate.groupNotifiableUnreadSum, 0);
    aggregate.applySdkConversations([group('@TGS#outside', 11, recvOpt: 1)]);
    expect(await aggregate.readSdkUnreadCountsForIds(['group_@TGS#outside']),
        {'group_@TGS#outside': 11});
    expect(fetches, 1);
    aggregate.applyNotifiableDeltas([
      ConversationUnreadDelta(
          conversationKey: 'group_@TGS#outside',
          isGroup: true,
          oldNotifiable: 11,
          newNotifiable: 0)
    ]);
    expect(await aggregate.readSdkUnreadCountsForIds(['group_@TGS#outside']),
        {'group_@TGS#outside': 11});
    ConversationTabStore.instance.zeroUnreadLocallyMany(['group_@TGS#outside']);
    expect(await aggregate.readSdkUnreadCountsForIds(['group_@TGS#outside']),
        {'group_@TGS#outside': 0});
  });

  test('a failed initial folder seed is unavailable rather than zero',
      () async {
    aggregate.sdkPageForTest = (_) async => throw StateError('offline');
    await expectLater(
        aggregate.readSdkUnreadCountsForIds(['c2c_peer']), throwsStateError);
  });

  test('late first page cannot revive a deleted row or undo realtime unread',
      () async {
    final releasePage = Completer<void>();
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async {
      await releasePage.future;
      return (
        conversationList: [group('@TGS#deleted', 7), group('@TGS#read', 9)],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: ''
      );
    };
    final tab = ConversationTabStore.instance;
    final request = tab.loadFirstPage(convType: 2);
    tab.applyDeleted(['group_@TGS#deleted']);
    tab.applyPatches([group('@TGS#read', 0)],
        explicitUnreadIds: {'group_@TGS#read'});
    releasePage.complete();
    await request;
    expect(tab.itemsForType(2).map((row) => row.conversationID),
        ['group_@TGS#read']);
    expect(tab.itemsForType(2).single.unreadCount, 0);
  });

  test('a new callback after deletion legitimately recreates the row',
      () async {
    final releasePage = Completer<void>();
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async {
      await releasePage.future;
      return (
        conversationList: [group('@TGS#recreated', 7)],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: ''
      );
    };
    final tab = ConversationTabStore.instance;
    final request = tab.loadFirstPage(convType: 2);
    tab.applyDeleted(['group_@TGS#recreated']);
    tab.applyPatches([group('@TGS#recreated', 2)]);
    releasePage.complete();
    await request;
    expect(tab.itemsForType(2).single.unreadCount, 2);
  });

  test('explicit read while a page loads overrides its stale unread', () async {
    final releasePage = Completer<void>();
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async {
      await releasePage.future;
      return (
        conversationList: [group('read_during_load', 7)],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: ''
      );
    };
    final tab = ConversationTabStore.instance;
    final request = tab.loadFirstPage(convType: 2);
    tab.zeroUnreadLocallyMany(['group_read_during_load']);
    releasePage.complete();
    await request;
    expect(tab.itemsForType(2).single.unreadCount, 0);
  });

  test('metadata during a page does not erase its draft', () async {
    final releasePage = Completer<void>();
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async {
      await releasePage.future;
      return (
        conversationList: [group('draft', 0)..draftText = 'keep draft'],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: ''
      );
    };
    final tab = ConversationTabStore.instance;
    final request = tab.loadFirstPage(convType: 2);
    tab.applyPatches([group('draft', 0)..faceUrl = 'updated']);
    releasePage.complete();
    await request;
    expect(tab.itemsForType(2).single.draftText, 'keep draft');
    expect(tab.itemsForType(2).single.faceUrl, 'updated');
  });

  test('deleting a C2C does not filter a group with the same suffix', () async {
    final releasePage = Completer<void>();
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async {
      await releasePage.future;
      return (
        conversationList: [group('peer', 7)],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: ''
      );
    };
    final tab = ConversationTabStore.instance;
    final request = tab.loadFirstPage(convType: 2);
    tab.applyDeleted(['c2c_peer']);
    releasePage.complete();
    await request;
    expect(tab.itemsForType(2).single.conversationID, 'group_peer');
  });
}
