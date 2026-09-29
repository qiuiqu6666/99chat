// AZListView is supplied by the vendored UIKit.
// ignore: depend_on_referenced_packages
import 'package:azlistview_all_platforms/azlistview_all_platforms.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/directory_search_bar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_list_role_badge.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_role.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/directory_list_style.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/az_list_view.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('two-line directory row fits text at scale $scale',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: Builder(builder: (context) {
          return SizedBox(
            width: 320,
            height: DirectoryListStyle.rowHeight(context, desktop: false),
            child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  const SizedBox(width: 44, height: 44),
                  const SizedBox(width: 12),
                  const Expanded(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Contact or group name',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 16, height: 1.25)),
                        SizedBox(height: 4),
                        Text('Details',
                            maxLines: 1,
                            style: TextStyle(fontSize: 13, height: 1.25)),
                      ])),
                ])),
          );
        })),
      )));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ordinary members have no badge, managers retain one',
      (tester) async {
    for (final role in [
      null,
      GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER,
      GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_ADMIN,
      GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER
    ]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: GroupListSelfRoleBadge(role: role))));
      final labels = find.descendant(
          of: find.byType(GroupListSelfRoleBadge), matching: find.byType(Text));
      expect(
          labels,
          role == null ||
                  role == GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER
              ? findsNothing
              : findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'search entry does not edit and group search clears through callback',
      (tester) async {
    final theme = DefaultThemeData();
    addTearDown(theme.dispose);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var taps = 0;
    final changes = <String>[];
    Widget page(bool entry) => ChangeNotifierProvider.value(
        value: theme,
        child: MaterialApp(
            home: Scaffold(
                body: DirectorySearchBar(
          hint: entry ? 'Search contacts' : 'Search groups',
          onTap: entry ? () => taps++ : null,
          controller: entry ? null : controller,
          onChanged: changes.add,
        ))));
    final handler = FlutterError.onError;
    await tester.pumpWidget(page(true));
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
    await tester.tap(find.text('Search contacts'));
    expect(taps, 1);
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(page(false));
    await tester.enterText(find.byType(TextField), 'team');
    await tester.pump();
    expect(changes.last, 'team');
    await tester.tap(find.byIcon(Icons.cancel));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(changes.last, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('editable search accommodates large font on narrow screens',
      (tester) async {
    final theme = DefaultThemeData();
    addTearDown(theme.dispose);
    final handler = FlutterError.onError;
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: theme,
        child: MaterialApp(
            home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.5)),
          child: const Scaffold(
              body: SizedBox(
                  width: 320,
                  child: DirectorySearchBar(hint: 'Search groups'))),
        ))));
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
    await tester.enterText(find.byType(TextField), 'Large text');
    await tester.pump();
    expect(tester.getSize(find.byType(TextField)).height,
        greaterThanOrEqualTo(65));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AZ index jumps correctly with scaled directory rows and headers',
      (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rows = <ISuspensionBeanImpl>[
      for (final tag in ['A', 'B', 'C'])
        for (var i = 0; i < 10; i++)
          ISuspensionBeanImpl(tagIndex: tag, memberInfo: '$tag-$i'),
    ];
    SuspensionUtil.setShowSuspensionStatus(rows);
    final handler = FlutterError.onError;
    // The desktop host deliberately hides the wrapper's mobile index. Exercise
    // its underlying list with the same row/header metrics and index enabled.
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: serviceLocator<TUIThemeViewModel>(),
      child: MaterialApp(
          home: MediaQuery(
        data: const MediaQueryData(
            size: Size(390, 700), textScaler: TextScaler.linear(2)),
        child: Scaffold(
            body: Builder(
                builder: (context) => AzListView(
                      data: rows,
                      itemCount: rows.length,
                      indexBarData: const ['A', 'B', 'C'],
                      indexBarItemHeight: 30,
                      susItemHeight: DirectoryListStyle.sectionHeight(context),
                      susItemBuilder: (context, i) => SizedBox(
                          height: DirectoryListStyle.sectionHeight(context),
                          child: Text(rows[i].tagIndex,
                              style: const TextStyle(fontSize: 12))),
                      itemBuilder: (context, i) => SizedBox(
                          height: DirectoryListStyle.rowHeight(context,
                              desktop: false),
                          child: Text(rows[i].memberInfo as String)),
                    ))),
      )),
    ));
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
    // The non-visible C section has only its index letter built initially.
    await tester.tap(find.text('C'));
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
    expect(find.text('C-0'), findsOneWidget);
    final top = tester.getTopLeft(find.text('C-0')).dy;
    expect(top, greaterThanOrEqualTo(0));
    expect(top, lessThan(100));
    expect(tester.takeException(), isNull);
  });
}
