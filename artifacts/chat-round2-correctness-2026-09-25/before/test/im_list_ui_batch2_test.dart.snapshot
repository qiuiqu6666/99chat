import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme_view_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/contact_list.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/group_member_list.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/directory_list_row.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/radio_button.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/recent_conversation_list.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/pureUI/tim_uikit_search_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/group_member/group_member_picker_search_bar.dart';

void Function(FlutterErrorDetails)? testErrorHandler;

Future<void> pumpPage(WidgetTester tester, Widget child,
    {double scale = 1,
    double width = 390,
    Brightness brightness = Brightness.light}) async {
  final errorHandler = testErrorHandler;
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: serviceLocator<TUIThemeViewModel>(),
    child: MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: MediaQuery(
          data: MediaQueryData(
              size: Size(width, 1000), textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: SizedBox(width: width, child: child))),
    ),
  ));
  await tester.pumpAndSettle();
  FlutterError.onError = errorHandler;
}

void main() {
  setUp(() => testErrorHandler = FlutterError.onError);
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('notice actions fit a narrow row at text scale $scale',
        (tester) async {
      var accepted = 0;
      await pumpPage(
          tester,
          SingleChildScrollView(
              child: DirectoryListRow(
            avatar: const ColoredBox(color: Colors.blue),
            title: const Text('A very long translated contact and group name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, height: 1.25)),
            subtitle: const Text(
                'A request with additional details that can occupy two lines.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, height: 1.35)),
            trailing: Wrap(children: [
              TextButton(
                  onPressed: () => accepted++, child: const Text('Approve')),
              TextButton(onPressed: () {}, child: const Text('Reject')),
            ]),
          )),
          scale: scale,
          width: 320);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Approve'));
      expect(accepted, 1);
      final row = tester.getRect(find.byType(DirectoryListRow));
      expect(row.contains(tester.getCenter(find.text('Reject'))), isTrue);
    });
  }

  testWidgets('contact picker preserves disabled users, limit and deselection',
      (tester) async {
    final friends = [
      for (final name in ['Alice', 'Bob', 'Carol'])
        V2TimFriendInfo(userID: name, friendRemark: name)
    ];
    var selected = <String>[];
    await pumpPage(
        tester,
        ContactList(
          contactList: friends,
          isCanSelectMemberItem: true,
          disabledUserIds: const {'Carol'},
          maxSelectNum: 1,
          trailingStatusLabelBuilder: (id) =>
              id == 'Carol' ? 'Awaiting approval' : null,
          onSelectedMemberItemChange: (items) =>
              selected = items.map((e) => e.userID).toList(),
        ),
        scale: 2,
        width: 320);
    await tester.tap(find.text('Alice'));
    await tester.pump();
    FlutterError.onError = testErrorHandler;
    expect(selected, ['Alice']);
    await tester.tap(find.text('Bob'));
    await tester.pump();
    FlutterError.onError = testErrorHandler;
    expect(selected, ['Alice']);
    await tester.tap(find.text('Alice'));
    await tester.pump();
    FlutterError.onError = testErrorHandler;
    expect(selected, isEmpty);
    await tester.tap(find.text('Carol'));
    await tester.pump();
    FlutterError.onError = testErrorHandler;
    expect(selected, isEmpty);
    await tester.tap(find.byType(CheckBoxButton).at(1));
    await tester.pump();
    FlutterError.onError = testErrorHandler;
    expect(selected, ['Bob']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('member picker keeps role labels and selection limits',
      (tester) async {
    var selected = <String>[];
    await pumpPage(
        tester,
        GroupProfileMemberList(
          memberList: [
            V2TimGroupMemberFullInfo(
                userID: 'Alice', nickName: 'Alice', role: 400),
            V2TimGroupMemberFullInfo(userID: 'Bob', nickName: 'Bob', role: 200),
          ],
          isShowOnlineStatus: false,
          canSlideDelete: false,
          canSelectMember: true,
          maxSelectNum: 1,
          onSelectedMemberChange: (items) =>
              selected = items.map((e) => e.userID).toList(),
        ),
        scale: 2,
        width: 320);
    expect(find.byType(DirectoryStatusLabel), findsOneWidget);
    await tester.tap(find.text('Alice'));
    await tester.pump();
    FlutterError.onError = testErrorHandler;
    expect(selected, ['Alice']);
    await tester.tap(find.text('Bob'));
    await tester.pump();
    FlutterError.onError = testErrorHandler;
    expect(selected, ['Alice']);
    await tester.tap(find.text('Alice'));
    await tester.pump();
    FlutterError.onError = testErrorHandler;
    expect(selected, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'member list refreshes when a reused member changes display fields',
      (tester) async {
    final members = <V2TimGroupMemberFullInfo?>[
      V2TimGroupMemberFullInfo(userID: 'Alice', nickName: 'Alice'),
    ];
    late void Function(void Function()) rebuild;
    await pumpPage(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return GroupProfileMemberList(
            memberList: members,
            isShowOnlineStatus: false,
            canSlideDelete: false,
          );
        },
      ),
      width: 320,
    );
    expect(find.text('Alice'), findsOneWidget);

    members.single!.nickName = 'Alice updated';
    rebuild(() {});
    await tester.pump();
    FlutterError.onError = testErrorHandler;

    expect(find.text('Alice'), findsNothing);
    expect(find.text('Alice updated'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'search result keeps rich highlight, two-line preview and navigation',
      (tester) async {
    var taps = 0;
    await pumpPage(
        tester,
        SingleChildScrollView(
            child: TIMUIKitSearchItem(
          faceUrl: '',
          showName: 'Alice',
          lineOne: 'Alice',
          lineOneWidget: const Text.rich(TextSpan(children: [
            TextSpan(text: 'Ali', style: TextStyle(color: Colors.blue)),
            TextSpan(text: 'ce')
          ])),
          lineTwo: 'A long matching message preview ' * 10,
          lineOneRight: 'Yesterday',
          onClick: () => taps++,
        )),
        scale: 3,
        width: 320);
    final preview =
        tester.widget<Text>(find.text('A long matching message preview ' * 10));
    expect(preview.maxLines, 2);
    expect(find.text('Alice'), findsOneWidget);
    await tester.tap(find.text('Alice'));
    await tester.pump();
    FlutterError.onError = testErrorHandler;
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('member search grows and clears at large text scale',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pumpPage(
        tester,
        StatefulBuilder(
            builder: (context, setState) => GroupMemberPickerSearchBar(
                controller: controller,
                keyword: controller.text,
                onClear: () => setState(controller.clear))),
        scale: 3,
        width: 320);
    await tester.enterText(find.byType(TextField), 'Alice');
    // Controller listeners are owned by the picker page; rebuild that page.
    await pumpPage(
        tester,
        GroupMemberPickerSearchBar(
            controller: controller,
            keyword: controller.text,
            onClear: controller.clear),
        scale: 3,
        width: 320);
    expect(tester.getSize(find.byType(TextField)).height,
        greaterThanOrEqualTo(54));
    await tester.tap(find.byIcon(Icons.cancel));
    await tester.pump();
    FlutterError.onError = testErrorHandler;
    expect(controller.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'forward picker selects once and suppresses conversation metadata',
      (tester) async {
    final handler = FlutterError.onError;
    final global = serviceLocator<TUIChatGlobalModel>();
    FlutterError.onError = handler;
    final previous = global.appForwardRecentConversations;
    addTearDown(() => global.appForwardRecentConversations = previous);
    global.appForwardRecentConversations = () => [
          V2TimConversation(
            conversationID: 'c2c_Alice',
            userID: 'Alice',
            type: 1,
            showName: 'Alice',
            unreadCount: 99,
            isPinned: true,
            recvOpt: 1,
            draftText: 'Private draft',
          )
        ];
    var calls = 0;
    var count = 0;
    await pumpPage(
        tester,
        RecentForwardList(
            showSectionHeader: false,
            onChanged: (items) {
              calls++;
              count = items.length;
            }),
        scale: 2,
        width: 320);
    expect(find.text('Private draft'), findsNothing);
    expect(find.text('99'), findsNothing);
    expect(find.byIcon(Icons.notifications_off), findsNothing);
    await tester.tap(find.byType(CheckBoxButton));
    await tester.pump();
    FlutterError.onError = testErrorHandler;
    expect(calls, 1);
    expect(count, 1);
    await tester.tap(find.text('Alice'));
    await tester.pump();
    FlutterError.onError = testErrorHandler;
    expect(calls, 2);
    expect(count, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RecentForwardList renders without ancestor TUIThemeViewModel',
      (tester) async {
    final handler = FlutterError.onError;
    final global = serviceLocator<TUIChatGlobalModel>();
    FlutterError.onError = handler;
    final previous = global.appForwardRecentConversations;
    addTearDown(() => global.appForwardRecentConversations = previous);
    global.appForwardRecentConversations = () => [
          V2TimConversation(
            conversationID: 'c2c_Alice',
            userID: 'Alice',
            type: 1,
            showName: 'Alice',
          )
        ];
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: RecentForwardList(
          isMultiSelect: false,
          showSectionHeader: false,
        ),
      ),
    ));
    await tester.pump();
    FlutterError.onError = testErrorHandler;
    expect(find.text('Alice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
