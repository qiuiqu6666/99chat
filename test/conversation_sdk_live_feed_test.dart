import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_list_sync_notifier.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_feed_sync_gate.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

V2TimConversation row(int type, int id, {int unread = 0}) => V2TimConversation(
      conversationID: type == 2 ? 'group_@TGS#live$id' : 'c2c_live$id',
      type: type,
      userID: type == 1 ? 'live$id' : null,
      groupID: type == 2 ? '@TGS#live$id' : null,
      showName: 'row $type $id',
      unreadCount: unread,
    );

void main() {
  final session = ChatSessionController.instance;
  final store = ConversationTabStore.instance;
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() {
    ActiveChatRegistry.instance.reset();
    session.clearSessionProjection();
    session.isFeedScrolling = () => false;
    session.ensureTabStoreBridgeAttached();
    ConversationListSyncNotifier.instance.clearSession();
  });
  tearDown(() {
    session.clearSessionProjection();
    session.isFeedScrolling = null;
    ConversationListSyncNotifier.instance.clearSession();
  });

  // Uses the same narrow feed/row subscriptions as ConversationFeedBody and
  // its row slots; the parent route is never rebuilt after mounting.
  Widget feed(int type) => ValueListenableBuilder<int>(
        valueListenable: session.feedRevision,
        builder: (_, revision, child) {
          final rows =
              session.conversations.where((r) => r.type == type).toList();
          return Column(children: [
            Text('count $type: ${rows.length}'),
            for (final r in rows.take(3))
              ValueListenableBuilder<int>(
                key: ValueKey(r.conversationID),
                valueListenable: session.rowRevisionOf(r.conversationID),
                builder: (_, rev, child) => Text(
                  '${r.conversationID}: ${session.currentConversationById(r.conversationID)?.unreadCount}',
                ),
              ),
          ]);
        },
      );

  testWidgets('first login publishes every SDK page to both mounted tabs',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Row(children: [
      Expanded(child: feed(1)),
      Expanded(child: feed(2))
    ]))));
    for (final count in [3, 40, 120, 300]) {
      for (final type in [1, 2]) {
        store.setItemsForTest(
            convType: type, items: List.generate(count, (i) => row(type, i)));
      }
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump();
      expect(find.text('count 1: $count'), findsOneWidget);
      expect(find.text('count 2: $count'), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('SDK content changes update only the affected row channel',
      (tester) async {
    store.setItemsForTest(convType: 1, items: [row(1, 0), row(1, 1)]);
    await tester.pumpWidget(MaterialApp(home: feed(1)));
    final feedRev = session.feedRevision.value;
    final otherRev = session.rowRevisionOf('c2c_live1').value;
    store.applyPatches([row(1, 0, unread: 7)], reason: 'sdk_realtime');
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('c2c_live0: 7'), findsOneWidget);
    expect(session.feedRevision.value, feedRev);
    expect(session.rowRevisionOf('c2c_live1').value, otherRev);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('suppressed insertion survives a later content patch',
      (tester) async {
    store.setItemsForTest(convType: 1, items: [row(1, 0)]);
    await tester.pumpWidget(MaterialApp(home: feed(1)));
    final before = session.feedRevision.value;
    session.beginSuppressNotify();
    store.applyPatches([row(1, 1)],
        reason: 'insert_test',
        forceAdmitIds: {'c2c_live1'},
        preserveOrder: true);
    store.applyPatches([row(1, 1, unread: 9)],
        reason: 'content_test', preserveOrder: true);
    expect(session.feedRevision.value, before);
    session.endSuppressNotify();
    await tester.pump(const Duration(milliseconds: 120));
    expect(session.feedRevision.value, greaterThan(before));
    expect(find.text('count 1: 2'), findsOneWidget);
    expect(find.text('c2c_live1: 9'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('continuous SDK batches publish before the stream stops',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: feed(1)));
    final initial = session.feedRevision.value;
    for (var i = 0; i < 15; i++) {
      store.applyPatches([row(1, i)], reason: 'sdk_realtime');
      await tester.pump(const Duration(milliseconds: 10));
      if (i == 6) expect(session.feedRevision.value, greaterThan(initial));
    }
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('count 1: 15'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('deferred SDK updates publish when reading gesture ends',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: feed(2)));
    final before = session.feedRevision.value;
    session.isFeedScrolling = () => true;
    store.setItemsForTest(convType: 2, items: [row(2, 0), row(2, 1)]);
    await tester.pump(const Duration(milliseconds: 60));
    expect(session.feedRevision.value, before);
    expect(find.text('count 2: 0'), findsOneWidget);
    session.isFeedScrolling = () => false;
    session.flushDeferredUiNotifyIfNeeded();
    await tester.pump();
    expect(find.text('count 2: 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('first SDK data replaces cached feed while sync is still running',
      (tester) async {
    ConversationListSyncNotifier.instance.setSyncing(true);
    final scroll = ScrollController();
    await tester.pumpWidget(MaterialApp(
        home: ConversationFeedSyncGate(
      theme: TUITheme(),
      feedScrollController: scroll,
      cachedFeedBuilder: (_, theme) => const Text('cached'),
      feedBuilder: (_) => feed(1),
    )));
    expect(find.text('cached'), findsOneWidget);
    store.setItemsForTest(convType: 1, items: [row(1, 0)]);
    await tester.pumpAndSettle();
    expect(ConversationListSyncNotifier.instance.isSyncing, isTrue);
    expect(find.text('cached'), findsNothing);
    expect(find.text('count 1: 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
  });
}
