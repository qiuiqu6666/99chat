import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/conversation.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/home_tab_activity.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/home_tab_stack.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_scope_unread_badge.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class _Probe extends StatefulWidget {
  const _Probe(this.index, this.starts);
  final int index;
  final List<int> starts;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int taps = 0;
  @override
  void initState() {
    super.initState();
    // Represents an initState-triggered database read or request.
    widget.starts.add(widget.index);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Text('active:${HomeTabActivity.isActiveOf(context)}'),
        TextButton(
            onPressed: () => setState(() => taps++),
            child: Text('tab${widget.index}:$taps')),
      ]);
}

void main() {
  testWidgets(
      'a small account starts only its visible tab even after idle frames',
      (tester) async {
    final starts = <int>[];
    var selected = 0;
    var visible = true;
    Widget host() => MaterialApp(
            home: Scaffold(
                body: HomeTabStack(
          index: selected,
          routeVisible: visible,
          builders: List.generate(5, (index) => (_) => _Probe(index, starts)),
        )));
    await tester.pumpWidget(host());
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 10));
    }
    expect(starts, [0]);
    await tester.tap(find.text('tab0:0'));
    await tester.pump();
    final first = tester.state<_ProbeState>(find.byType(_Probe));
    selected = 3;
    await tester.pumpWidget(host());
    expect(starts, [0, 3]);
    expect(find.text('tab3:0'), findsOneWidget);
    expect(first.mounted, isTrue);
    selected = 0;
    await tester.pumpWidget(host());
    expect(starts, [0, 3]);
    expect(tester.state<_ProbeState>(find.byType(_Probe)), same(first));
    expect(find.text('tab0:1'), findsOneWidget);
    visible = false;
    await tester.pumpWidget(host());
    expect(HomeTabActivity.read(first.context), isFalse);
    expect(TickerMode.valuesOf(first.context).enabled, isFalse);
    visible = true;
    await tester.pumpWidget(host());
    expect(HomeTabActivity.read(first.context), isTrue);
    expect(TickerMode.valuesOf(first.context).enabled, isTrue);
    expect(starts, [0, 3]);
  });

  testWidgets('direct entry to a non-default tab does not initialize messages',
      (tester) async {
    final starts = <int>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: HomeTabStack(
      index: 4,
      routeVisible: true,
      builders: List.generate(5, (index) => (_) => _Probe(index, starts)),
    ))));
    await tester.pumpAndSettle();
    expect(starts, [4]);
    expect(find.text('tab4:0'), findsOneWidget);
  });

  testWidgets('group unread arrives before the group tab is ever mounted',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    final store = ConversationLocalStore.instance;
    final tabs = ConversationTabStore.instance;
    final aggregate = ConversationUnreadAggregate.instance;
    final controller = ChatSessionController.instance;
    store.debugOwnerUserId = 'small-account-cold-start';
    store.resetAnchorStateForTest();
    tabs.clear();
    tabs.notifyColdStartEnded();
    aggregate.resetForTest();
    final starts = <int>[];
    try {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
        body: HomeTabStack(
            index: 0,
            routeVisible: true,
            builders:
                List.generate(5, (index) => (_) => _Probe(index, starts))),
        bottomNavigationBar: const ConversationScopeUnreadBadge(
            scope: ConversationListScope.group),
      )));
      controller.applyPendingRealtimeProjection([
        V2TimConversation(
            conversationID: 'group_only',
            groupID: 'only',
            type: 2,
            unreadCount: 2),
      ], reason: 'sdk_realtime');
      tabs.flushRealtimePatches();
      await tester.pump();
      expect(starts, [0]);
      expect(aggregate.groupNotifiableUnreadSum, 2);
      expect(find.text('2'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.clearSessionProjection();
      tabs.clear();
      aggregate.resetForTest();
      store.resetAnchorStateForTest();
      store.debugOwnerUserId = null;
    }
  });
}
