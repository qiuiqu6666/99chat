import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/contact.dart';
import 'package:tencent_cloud_chat_demo/src/conversation.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/provider/custom_sticker_package.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_feed_body.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_conversation_controller.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/home_tab_activity.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/contact_list_with_presence.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/contact_list.dart';

class ObservedFriend extends V2TimFriendInfo {
  ObservedFriend(int index) : super(userID: 'friend_$index');
  int nameReads = 0;
  @override
  String? get friendRemark {
    nameReads++;
    return 'Person $userID';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DefaultThemeData theme;
  late LocalSetting settings;
  late PresenceProvider presence;
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() {
    theme = DefaultThemeData();
    settings = LocalSetting(autoLoad: false)..isShowOnlineStatus = false;
    presence = PresenceProvider();
  });
  tearDown(() {
    Contact.debugLoadImFriends = null;
    presence.dispose();
    settings.dispose();
    theme.dispose();
  });

  Widget host(Widget child, {bool active = true}) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: presence),
          ChangeNotifierProvider(create: (_) => CustomStickerPackageData()),
        ],
        child: MaterialApp(
          home: HomeTabActivity(
            isActive: active,
            child: TickerMode(
              enabled: active,
              child: Scaffold(body: child),
            ),
          ),
        ),
      );

  testWidgets('real contact page keeps list and deep scroll state across tabs',
      (tester) async {
    Contact.debugLoadImFriends =
        () async => List.generate(120, (i) => ObservedFriend(i));
    const page = Contact();
    await tester.pumpWidget(host(page));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final listState = tester.state(find.byType(ContactListWithPresence));
    final scrollState =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    scrollState.position.jumpTo(1500);
    await tester.pump(const Duration(milliseconds: 300));
    final offset = scrollState.position.pixels;
    expect(offset, greaterThan(1000));
    for (var i = 0; i < 4; i++) {
      await tester.pumpWidget(host(page, active: false));
      expect(
          tester.state(find.byType(ContactListWithPresence)), same(listState));
      expect(scrollState.mounted, isTrue);
      await tester.pumpWidget(host(page));
      expect(
          tester.state(find.byType(ContactListWithPresence)), same(listState));
      expect(tester.state<ScrollableState>(find.byType(Scrollable).first),
          same(scrollState));
      expect(scrollState.position.pixels, closeTo(offset, 0.01));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(listState.mounted, isFalse);
    expect(scrollState.mounted, isFalse);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('hidden contact list applies friend add and delete on return',
      (tester) async {
    final directory = ImSdkRelationshipDirectory.instance;
    directory.reset();
    addTearDown(directory.reset);
    RelationshipFriendEntry friend(String id, String name) =>
        RelationshipFriendEntry(
          userId: id,
          displayName: name,
          faceUrl: '',
          remark: name,
          sortKey: ImSdkRelationshipDirectory.sortKeyFor(
            id: id,
            displayName: name,
            azTag: name[0],
          ),
        );
    directory.applyFriendSnapshot(
      captureId: directory.beginFriendCapture(),
      entries: [friend('contact_a', 'Ann'), friend('contact_b', 'Ben')],
    );

    const list = ContactListWithPresence(isShowOnlineStatus: false);
    await tester.pumpWidget(host(list));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ann'), findsOneWidget);
    expect(find.text('Ben'), findsOneWidget);

    await tester.pumpWidget(host(list, active: false));
    directory.applyFriendRemoves(const ['contact_b']);
    directory.applyFriendAdds([friend('contact_c', 'Cara')]);
    await tester.pumpWidget(host(list));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Ann'), findsOneWidget);
    expect(find.text('Ben'), findsNothing);
    expect(find.text('Cara'), findsOneWidget);
  });

  testWidgets('visible contact list applies friend add and delete immediately',
      (tester) async {
    final directory = ImSdkRelationshipDirectory.instance;
    directory.reset();
    addTearDown(directory.reset);
    RelationshipFriendEntry friend(String id, String name) =>
        RelationshipFriendEntry(
          userId: id,
          displayName: name,
          faceUrl: '',
          remark: name,
          sortKey: ImSdkRelationshipDirectory.sortKeyFor(
            id: id,
            displayName: name,
            azTag: name[0],
          ),
        );
    directory.applyFriendSnapshot(
      captureId: directory.beginFriendCapture(),
      entries: [friend('contact_a', 'Ann')],
    );

    await tester.pumpWidget(host(
      const ContactListWithPresence(isShowOnlineStatus: false),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ann'), findsOneWidget);

    directory.applyFriendAdds([friend('contact_b', 'Ben')]);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ben'), findsOneWidget);

    directory.applyFriendRemoves(const ['contact_a']);
    await tester.pump();
    expect(find.text('Ann'), findsNothing);
    expect(find.text('Ben'), findsOneWidget);
  });

  testWidgets('contacts appear when first friend snapshot arrives after mount',
      (tester) async {
    final directory = ImSdkRelationshipDirectory.instance;
    directory.reset();
    addTearDown(directory.reset);

    await tester.pumpWidget(host(ContactListWithPresence(
      isShowOnlineStatus: false,
      topList: [TopListItem(id: 'new', name: 'New Friends')],
    )));
    expect(find.text('New Friends'), findsOneWidget);
    expect(find.text('Ann'), findsNothing);

    directory.applyFriendSnapshot(
      captureId: directory.beginFriendCapture(),
      entries: [
        RelationshipFriendEntry(
          userId: 'contact_a',
          displayName: 'Ann',
          faceUrl: '',
          remark: 'Ann',
          sortKey: ImSdkRelationshipDirectory.sortKeyFor(
            id: 'contact_a',
            displayName: 'Ann',
            azTag: 'A',
          ),
        ),
      ],
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Ann'), findsOneWidget);
  });

  testWidgets(
      'contacts appear when an initially empty directory gains a friend',
      (tester) async {
    final directory = ImSdkRelationshipDirectory.instance;
    directory.reset();
    addTearDown(directory.reset);
    directory.applyFriendSnapshot(
      captureId: directory.beginFriendCapture(),
      entries: const [],
    );

    await tester.pumpWidget(host(ContactListWithPresence(
      isShowOnlineStatus: false,
      topList: [TopListItem(id: 'new', name: 'New Friends')],
    )));
    expect(find.text('New Friends'), findsOneWidget);

    directory.applyFriendAdds([
      RelationshipFriendEntry(
        userId: 'contact_b',
        displayName: 'Ben',
        faceUrl: '',
        remark: 'Ben',
        sortKey: ImSdkRelationshipDirectory.sortKeyFor(
          id: 'contact_b',
          displayName: 'Ben',
          azTag: 'B',
        ),
      ),
    ]);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Ben'), findsOneWidget);
  });

  testWidgets(
      'new top entries update callbacks without sorting offline friends',
      (tester) async {
    final friends = List.generate(120, (i) => ObservedFriend(i));
    var oldTaps = 0;
    var newTaps = 0;
    Widget list(String title, VoidCallback onTap) => ContactListWithPresence(
          friends: friends,
          isShowOnlineStatus: false,
          showContactCount: true,
          topList: [TopListItem(id: 'entry', name: title, onTap: onTap)],
        );
    await tester.pumpWidget(host(list('Old entry', () => oldTaps++)));
    await tester.pump(const Duration(milliseconds: 300));
    final state = tester.state(find.byType(ContactListWithPresence));
    final offscreenReads = friends.last.nameReads;
    expect(offscreenReads, greaterThan(0));
    await tester.pumpWidget(host(list('New entry', () => newTaps++)));
    expect(tester.state(find.byType(ContactListWithPresence)), same(state));
    expect(friends.last.nameReads, offscreenReads);
    expect(find.text('Old entry'), findsNothing);
    await tester.tap(find.text('New entry'));
    expect(oldTaps, 0);
    expect(newTaps, 1);
    await tester
        .pumpWidget(host(list('Hidden entry', () => newTaps++), active: false));
    final hiddenReads = friends.last.nameReads;
    presence.notifyListeners();
    await tester.pump();
    expect(friends.last.nameReads, hiddenReads);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('real conversation feed survives hiding and consumes SDK updates',
      (tester) async {
    final errorHandler = FlutterError.onError;
    addTearDown(() => FlutterError.onError = errorHandler);
    final session = ChatSessionController.instance;
    final tabs = ConversationTabStore.instance;
    session.clearSessionProjection();
    session.ensureTabStoreBridgeAttached();
    V2TimConversation row(int i, {int unread = 0}) => V2TimConversation(
          conversationID: 'c2c_tab_$i',
          type: 1,
          userID: 'tab_$i',
          showName: 'Conversation $i',
          unreadCount: unread,
        );
    tabs.setItemsForTest(convType: 1, items: List.generate(100, (i) => row(i)));
    final page = Conversation(
      conversationController: TIMUIKitConversationController(),
      listScope: ConversationListScope.c2c,
    );
    await tester.pumpWidget(host(page));
    await tester.pump(const Duration(milliseconds: 150));
    final feed = find.byType(ConversationFeedBody);
    final feedState = tester.state(feed);
    final scrollFinder =
        find.descendant(of: feed, matching: find.byType(Scrollable));
    final scrollState = tester.state<ScrollableState>(scrollFinder.first);
    scrollState.position.jumpTo(1500);
    await tester.pump(const Duration(milliseconds: 300));
    final offset = scrollState.position.pixels;
    FlutterError.onError = errorHandler;
    expect(offset, greaterThan(1000));
    await tester.pumpWidget(host(page, active: false));
    FlutterError.onError = errorHandler;
    expect(tester.state(feed), same(feedState));
    final updated = row(0, unread: 7)
      ..lastMessage =
          (V2TimMessage.fromJson({'message_risk_type_identified': 0})
            ..msgID = 'hidden-tab-message'
            ..elemType = 1
            ..timestamp = 100
            ..textElem = V2TimTextElem(text: 'Arrived while tab hidden'));
    tabs.applyPatches([updated], reason: 'sdk_realtime');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpWidget(host(page));
    await tester.pump(const Duration(milliseconds: 150));
    FlutterError.onError = errorHandler;
    expect(tester.state(feed), same(feedState));
    expect(
        tester.state<ScrollableState>(scrollFinder.first), same(scrollState));
    expect(scrollState.position.pixels, closeTo(offset, 0.01));
    expect(session.currentConversationById('c2c_tab_0')?.unreadCount, 7);
    scrollState.position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 300));
    FlutterError.onError = errorHandler;
    expect(find.text('7'), findsWidgets);
    expect(find.textContaining('Arrived while tab hidden'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    session.clearSessionProjection();
  });
}
