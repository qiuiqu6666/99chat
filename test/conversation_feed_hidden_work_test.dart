import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_feed_body.dart';
import 'package:tencent_cloud_chat_demo/utils/avatar_image_warm.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_conversation_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/archived_conversation_store.dart';

void main() {
  final session = ChatSessionController.instance;
  final store = ConversationTabStore.instance;
  late ScrollController scroll;
  late TIMUIKitConversationController controller;
  late TUITheme theme;
  var reads = 0;
  var rowBuilds = 0;
  var avatarResolutions = 0;
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() {
    session.clearSessionProjection();
    session.ensureTabStoreBridgeAttached();
    scroll = ScrollController();
    controller = TIMUIKitConversationController();
    theme = TUITheme();
    reads = 0;
    rowBuilds = 0;
    avatarResolutions = 0;
    store.setItemsForTest(convType: 1, items: [row('first')]);
  });
  tearDown(() {
    scroll.dispose();
    session.clearSessionProjection();
  });

  Widget host({required bool active}) => MaterialApp(
        home: TickerMode(
          enabled: active,
          child: ConversationFeedBody(
            workEnabled: active,
            isGroupTab: false,
            previewCacheScopeKey: 'hidden-work',
            archiveScope: ConversationArchiveScope.c2c,
            theme: theme,
            feedScrollController: scroll,
            scrollPhysics: const ClampingScrollPhysics(),
            controller: controller,
            getVisibleConversations: () {
              reads++;
              return store.conversations;
            },
            getArchivedConversations: () => [],
            conversationTimestampMs: (_) => 0,
            buildConversationRow: (conversation) {
              rowBuilds++;
              return Text(
                  '${conversation.showName}:${conversation.unreadCount}');
            },
            resolveConversationAvatarUrl: (_) {
              avatarResolutions++;
              return const AvatarImageWarmSource(url: null);
            },
            onArchivedTap: () {},
            onGroupNoticeTap: () {},
            onGroupNoticePin: () async {},
            onGroupNoticeToggleMute: () async {},
            onGroupNoticeDelete: () async {},
          ),
        ),
      );

  testWidgets('hidden commits and parent builds do no materialization or rows',
      (tester) async {
    await tester.pumpWidget(host(active: true));
    await tester.pump();
    final state = tester.state(find.byType(ConversationFeedBody));
    final position = scroll.position;
    await tester.pumpWidget(host(active: false));
    final hiddenReads = reads;
    final hiddenBuilds = rowBuilds;
    final hiddenAvatars = avatarResolutions;
    for (var i = 0; i < 10; i++) {
      store.applyPatches([row('first', unread: i + 2)], reason: 'sdk_realtime');
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpWidget(host(active: false));
    }
    expect(reads, hiddenReads);
    expect(rowBuilds, hiddenBuilds);
    expect(avatarResolutions, hiddenAvatars);
    await tester.pumpWidget(host(active: true));
    await tester.pump();
    expect(tester.state(find.byType(ConversationFeedBody)), same(state));
    expect(scroll.position, same(position));
    expect(find.text('first:11'), findsOneWidget,
        reason: 'store=${store.conversations.map((r) => r.showName).toList()} '
            'rendered=${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()} reads=$reads builds=$rowBuilds');
    expect(reads, greaterThan(hiddenReads));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hidden first mount skips warming, theme and account stay fresh',
      (tester) async {
    await tester.pumpWidget(host(active: false));
    expect(avatarResolutions, 0);
    final originalReads = reads;
    theme = TUITheme(primaryColor: Colors.red);
    await tester.pumpWidget(host(active: false));
    expect(reads, greaterThan(originalReads));
    expect(avatarResolutions, 0);
    session.clearSessionProjection();
    store.setItemsForTest(convType: 1, items: [row('other account')]);
    await tester.pumpWidget(host(active: false));
    expect(find.text('first:1'), findsNothing);
    expect(find.text('other account:1'), findsOneWidget);
    await tester.pumpWidget(host(active: true));
    await tester.pump();
    expect(avatarResolutions, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

V2TimConversation row(String name, {int unread = 1}) => V2TimConversation(
      conversationID: 'c2c_hidden',
      userID: 'hidden',
      type: 1,
      showName: name,
      unreadCount: unread,
    );
