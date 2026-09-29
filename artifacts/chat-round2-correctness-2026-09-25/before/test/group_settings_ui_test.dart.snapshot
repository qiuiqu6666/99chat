import 'package:flutter/cupertino.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_slidable_plus_plus/flutter_slidable_plus_plus.dart';
import 'package:tencent_cloud_chat_sdk/native_im/adapter/tim_manager.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_member_feedback_bridge.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme_view_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/group_member_list.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/group_member/tui_group_member_list.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/group_member/tui_delete_group_member.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/group_settings_tile.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/widgets/tim_uikit_group_manage.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/pureUI/tim_uikit_search_input.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  Widget host(Widget child,
          {double scale = 1, Brightness brightness = Brightness.light}) =>
      ChangeNotifierProvider.value(
          value: serviceLocator<TUIThemeViewModel>(),
          child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: MediaQuery(
                  data: MediaQueryData(
                      size: const Size(320, 800),
                      textScaler: TextScaler.linear(scale)),
                  child: Scaffold(body: SizedBox(width: 320, child: child)))));

  testWidgets('remove picker follows backend roles and rejects a stale selection',
      (tester) async {
    final model = _RemovalPermissionModel();
    addTearDown(model.dispose);
    model.groupInfo = V2TimGroupInfo(groupID: 'group', groupType: 'Public', role: 200);
    model.groupMemberList = [
      V2TimGroupMemberFullInfo(userID: 'backendadmin', nickName: 'Backend admin', role: 200),
      V2TimGroupMemberFullInfo(userID: 'sdkadmin', nickName: 'SDK admin', role: 300),
      V2TimGroupMemberFullInfo(userID: 'ordinary', nickName: 'Ordinary', role: 200),
    ];
    final pageKey = GlobalKey<DeleteGroupMemberPageState>();
    final handler = FlutterError.onError;
    await tester.pumpWidget(host(DeleteGroupMemberPage(key: pageKey, model: model)));
    await tester.pump();
    FlutterError.onError = handler;
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(GroupProfileMemberList), findsOneWidget);
    expect(tester.widget<GroupProfileMemberList>(
        find.byType(GroupProfileMemberList)).canSelectMember, isFalse);
    expect(model.managementRequests, 1);
    model.loaded = true;
    model.loading = false;
    model.backendMembers = [
      V2TimGroupMemberFullInfo(userID: 'self', role: 300),
      V2TimGroupMemberFullInfo(userID: 'owner', role: 400),
      V2TimGroupMemberFullInfo(userID: 'backendadmin', role: 300),
    ];
    model.notifyListeners();
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
    List<String> candidateIds() => tester.widget<GroupProfileMemberList>(
        find.byType(GroupProfileMemberList)).memberList.map((m) => m!.userID).toList();
    expect(candidateIds(), ['sdkadmin', 'ordinary']);
    await tester.tap(find.text('Ordinary'));
    await tester.pump();
    FlutterError.onError = handler;
    expect(pageKey.currentState!.selectedGroupMember, hasLength(1));
    // Same SDK list object and same self role, but the selected target is promoted.
    model.backendMembers = [...model.backendMembers,
      V2TimGroupMemberFullInfo(userID: 'ordinary', role: 300)];
    model.notifyListeners();
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
    expect(find.byType(ErrorWidget), findsNothing);
    expect(candidateIds(), ['sdkadmin']);
    expect(pageKey.currentState!.selectedGroupMember, isEmpty);
    // Also guard a stale submission before the next UI reconciliation.
    pageKey.currentState!.selectedGroupMember = [model.groupMemberList.last!];
    await pageKey.currentState!.submitDelete();
    await tester.pump();
    FlutterError.onError = handler;
    expect(model.kickRequests, 0);
    expect(pageKey.currentState!.selectedGroupMember, isEmpty);
    // Demotion must remove all candidates even while SDK keeps its old roles.
    model.backendMembers = model.backendMembers.where((m) => m?.userID != 'self').toList();
    model.notifyListeners();
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
    expect(candidateIds(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final role in [200, 300, 400]) {
    for (final type in ['Public', 'Work']) {
      testWidgets('slide removal uses backend role $role in $type', (tester) async {
        final model = _RemovalPermissionModel()..loaded = true;
        addTearDown(model.dispose);
        model.groupInfo = V2TimGroupInfo(groupID: 'group', groupType: type,
            role: role == 200 ? 400 : 200);
        model.backendMembers = [
          V2TimGroupMemberFullInfo(userID: 'self', role: role),
          V2TimGroupMemberFullInfo(userID: 'owner', role: 400),
          V2TimGroupMemberFullInfo(userID: 'admin', role: 300),
        ];
        model.groupMemberList = [
          V2TimGroupMemberFullInfo(userID: 'self', nickName: 'Self', role: 200),
          V2TimGroupMemberFullInfo(userID: 'ordinary', nickName: 'Ordinary', role: 300),
        ];
        final handler = FlutterError.onError;
        await tester.pumpWidget(host(GroupProfileMemberListPage(
            model: model, memberList: model.groupMemberList,
            isShowOnlineStatus: false)));
        await tester.pumpAndSettle();
        FlutterError.onError = handler;
        final deletable = tester.widgetList<Slidable>(find.byType(Slidable))
            .where((row) => row.endActionPane != null).length;
        expect(deletable, role == 400 ? 2 : role == 300 && type == 'Public' ? 1 : 0);
        expect(find.byType(ErrorWidget), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('mute picker reports partial failure and retries only failed members', (tester) async {
    final locale = LocaleSettings.currentLocale;
    LocaleSettings.setLocale(AppLocale.zhHans);
    final deviceLocale = I18nUtils.deviceLocaleStored;
    I18nUtils(null, 'zh-Hans');
    addTearDown(() => I18nUtils(null, deviceLocale ?? 'en'));
    addTearDown(() => LocaleSettings.setLocale(locale));
    final manager = TIMManager.instance;
    TIMManager.instance = _TestClockManager();
    addTearDown(() => TIMManager.instance = manager);
    final feedback = <String>[];
    GroupMemberFeedbackBridge.onShowMessage = feedback.add;
    addTearDown(() => GroupMemberFeedbackBridge.onShowMessage = null);
    final model = _MuteResultModel();
    addTearDown(model.dispose);
    model.groupInfo = V2TimGroupInfo(groupID: '', groupType: 'Public');
    model.groupMemberList = [
      V2TimGroupMemberFullInfo(userID: 'success', nickName: 'Success', role: 200),
      V2TimGroupMemberFullInfo(userID: 'failure', nickName: 'Failure', role: 200),
    ];
    final handler = FlutterError.onError;
    await tester.pumpWidget(TranslationProvider(
        child: host(GroupProfileGroupManagePage(model: model))));
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
    expect(find.byType(ErrorWidget), findsNothing,
        reason: tester.widgetList<ErrorWidget>(find.byType(ErrorWidget))
            .map((widget) => widget.message).join('\n'));
    await tester.tap(find.byIcon(Icons.add_circle_outline).last);
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
    await tester.tap(find.text('Success'));
    await tester.tap(find.text('Failure'));
    await tester.pump();
    FlutterError.onError = handler;
    final dynamic pickerState = tester.state(find.byType(GroupProfileAddAdmin));
    await tester.tap(find.widgetWithText(FilledButton, '完成'));
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
    expect(model.requests, ['success:true', 'failure:true']);
    expect(feedback.last, contains('1 人失败'));
    expect(find.byType(GroupProfileAddAdmin), findsOneWidget);
    expect(find.descendant(of: find.byType(GroupProfileAddAdmin),
        matching: find.text('Success')), findsNothing);
    expect(find.descendant(of: find.byType(GroupProfileAddAdmin),
        matching: find.text('Failure')), findsOneWidget);
    expect(await pickerState.onSubmit(), isFalse);
    expect(model.requests.last, 'failure:true');
    expect(feedback.last, '设置禁言失败，请重试');
    model.fail = false;
    expect(await pickerState.onSubmit(), isTrue);
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
    expect(feedback.last, '设置禁言成功');
    Navigator.of(tester.element(find.byType(GroupProfileAddAdmin))).pop();
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
    expect(find.text('Success'), findsOneWidget);
    expect(find.text('Failure'), findsOneWidget);
    model.fail = true;
    await tester.tap(find.text('解除禁言').last);
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
    expect(feedback.last, '解除禁言失败，请重试');
    expect(find.text('Failure'), findsOneWidget);
    model.fail = false;
    await tester.tap(find.text('解除禁言').last);
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
    expect(feedback.last, '解除禁言成功');
    expect(find.text('Failure'), findsNothing);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets(
        'settings keep one-line labels and inline switches at scale $scale',
        (tester) async {
      var changes = 0;
      final theme = serviceLocator<TUIThemeViewModel>().theme;
      await tester.pumpWidget(host(
          SingleChildScrollView(
              child: Column(children: [
            GroupSettingsTile(
                theme: theme,
                title: 'Allow joining by a long group alias',
                trailing: GroupSettingsSwitch(
                    value: false, onChanged: (_) => changes++)),
            GroupSettingsTile(
                theme: theme,
                title: 'Privacy protection',
                subtitle: 'A long explanation that must remain on one line',
                trailing:
                    const GroupSettingsSwitch(value: false, onChanged: null)),
          ])),
          scale: scale,
          brightness: Brightness.dark));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.maxLines, 1);
        expect(text.overflow, TextOverflow.ellipsis);
      }
      final switches = find.byType(CupertinoSwitch);
      expect(tester.getRect(switches.at(0)).right,
          tester.getRect(switches.at(1)).right);
      await tester.tap(switches.at(0));
      await tester.pump();
      expect(changes, 1);
      await tester.tap(switches.at(1));
      await tester.pump();
      expect(changes, 1);
    });
  }

  testWidgets('settings value stays beside label and navigation still fires',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(
        GroupSettingsTile(
            theme: serviceLocator<TUIThemeViewModel>().theme,
            title: 'Join requests',
            onTap: () => taps++,
            trailing: const Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                  child: Text('Administrator approval',
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
              Icon(Icons.chevron_right, size: 20),
            ])),
        scale: 3));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Join requests'));
    expect(taps, 1);
    expect(tester.getCenter(find.text('Administrator approval')).dx,
        greaterThan(tester.getCenter(find.text('Join requests')).dx));
  });

  testWidgets(
      'member search is single-line, grows and clears without losing focus',
      (tester) async {
    final handler = FlutterError.onError;
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    final changes = <String>[];
    await tester.pumpWidget(host(
        TIMUIKitSearchInput(
            directoryStyle: true,
            controller: controller,
            focusNode: focus,
            isAutoFocus: false,
            onChange: changes.add),
        scale: 3));
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
    expect(tester.widget<TextField>(find.byType(TextField)).maxLines, 1);
    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.pump();
    FlutterError.onError = handler;
    expect(changes.last, 'Alice');
    await tester.tap(find.byIcon(Icons.cancel));
    await tester.pump();
    FlutterError.onError = handler;
    expect(controller.text, isEmpty);
    expect(changes.last, '');
    expect(focus.hasFocus, isTrue);
    expect(tester.getSize(find.byType(TextField)).height,
        greaterThanOrEqualTo(74));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'administrator page keeps delete button and circular single-line rows',
      (tester) async {
    final model = _BackendAdminLayoutModel();
    addTearDown(model.dispose);
    model.groupInfo = V2TimGroupInfo(groupID: 'group', groupType: 'Public');
    model.backendMembers = [
      V2TimGroupMemberFullInfo(userID: 'owner', nickName: 'Owner', role: 400),
      V2TimGroupMemberFullInfo(
          userID: 'admin', nickName: 'Long administrator name', role: 300),
    ];
    final handler = FlutterError.onError;
    await tester
        .pumpWidget(host(GroupProfileSetManagerPage(model: model), scale: 2));
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
    expect(find.byType(TextButton), findsOneWidget);
    for (final avatar in tester.widgetList<Avatar>(find.byType(Avatar))) {
      expect(avatar.borderRadius, BorderRadius.circular(999));
    }
    final name = tester.widget<Text>(find.text('Long administrator name'));
    expect(name.maxLines, 1);
    expect(name.style?.fontSize, 16);
    expect(tester.takeException(), isNull);
  });

  testWidgets('administrator page waits for fresh backend roles during refresh',
      (tester) async {
    final model = _BackendAdminStateModel();
    addTearDown(model.dispose);
    model.groupInfo = V2TimGroupInfo(groupID: 'group', groupType: 'Public');
    model.groupMemberList = [
      V2TimGroupMemberFullInfo(userID: 'sdk', nickName: 'SDK administrator', role: 300),
    ];
    final handler = FlutterError.onError;
    await tester.pumpWidget(host(GroupProfileSetManagerPage(model: model)));
    await tester.pump();
    FlutterError.onError = handler;
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.text('SDK administrator'), findsNothing);
    expect(find.byType(Avatar), findsNothing);

    model.loading = false;
    model.failed = true;
    model.notifyListeners();
    await tester.pump();
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.byType(TextButton), findsOneWidget);
    expect(find.byType(Avatar), findsNothing);

    model.backendMembers = [
      V2TimGroupMemberFullInfo(userID: 'rest', nickName: 'Backend administrator', role: 300),
    ];
    model.loaded = true;
    model.failed = false;
    model.loading = true;
    model.notifyListeners();
    await tester.pump();
    expect(find.text('Backend administrator'), findsNothing);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    model.loading = false;
    model.notifyListeners();
    await tester.pump();
    expect(find.text('Backend administrator'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.text('SDK administrator'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('member page displays 19 backend administrators with only 10 in SDK',
      (tester) async {
    final model = _MemberPageModel();
    addTearDown(model.dispose);
    model.groupInfo = V2TimGroupInfo(groupID: 'group', groupType: 'Public', memberCount: 100);
    model.groupMemberList = [
      ...List.generate(10, (i) => V2TimGroupMemberFullInfo(
          userID: 'admin${i + 1}', nickName: 'SDK admin ${i + 1}', role: 300)),
      V2TimGroupMemberFullInfo(userID: 'ordinary', nickName: 'Ordinary', role: 200),
    ];
    final handler = FlutterError.onError;
    await tester.pumpWidget(host(GroupProfileMemberListPage(
        model: model, memberList: model.groupMemberList, isShowOnlineStatus: false)));
    await tester.pump();
    FlutterError.onError = handler;
    expect(model.managementRequests, 1,
        reason: 'Opening members must request backend roles without visiting settings');
    expect(find.byType(GroupProfileMemberList), findsOneWidget);
    model.backendMembers = [
      V2TimGroupMemberFullInfo(userID: 'owner', nickName: 'Owner', role: 400),
      ...List.generate(19, (i) => V2TimGroupMemberFullInfo(
          userID: 'admin${i + 1}', nickName: 'Server admin ${i + 1}', role: 300)),
    ];
    model.loaded = true;
    model.loading = false;
    model.notifyListeners();
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
    final rows = tester.widget<GroupProfileMemberList>(
        find.byType(GroupProfileMemberList)).memberList;
    expect(rows.where((m) => m?.role == 300), hasLength(19));
    expect(rows, hasLength(21));
    expect(rows.map((m) => m?.userID).toSet(), hasLength(21));
    await tester.scrollUntilVisible(find.text('Server admin 19'), 300,
        scrollable: find.byWidgetPredicate((widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down).first);
    expect(find.text('Server admin 19'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

// This test exercises row layout with an already loaded backend snapshot.
class _BackendAdminLayoutModel extends TUIGroupProfileModel {
  List<V2TimGroupMemberFullInfo?> backendMembers = [];
  @override
  int? get backendSelfRole => 300;
  @override
  List<V2TimGroupMemberFullInfo?> get managementMemberList => backendMembers;
  @override
  bool get hasLoadedManagementMembers => true;
  @override
  Future<void> loadManagementMembers() async {}
  @override
  Future<void> ensureMemberListPage({int count = 50}) async {}
  @override
  Future<void> loadRemainingMemberPages({int? expectedCount}) async {}
  @override
  Future<void> seedLocalMemberAndManagementPreview() async {}
}

class _BackendAdminStateModel extends _BackendAdminLayoutModel {
  bool loaded = false;
  bool loading = true;
  bool failed = false;
  @override
  bool get hasLoadedManagementMembers => loaded;
  @override
  bool get isManagementMemberListLoading => loading;
  @override
  bool get hasManagementMemberListError => failed;
}

class _MemberPageModel extends _BackendAdminStateModel {
  int managementRequests = 0;
  @override
  Future<void> loadMemberPageOnEntry() => loadManagementMembers();
  @override
  Future<void> loadRemainingMemberPages({int? expectedCount}) async {
    // Production entry loads roles inside this method, once per member page.
    await loadManagementMembers();
  }
  @override
  Future<void> loadManagementMembers() async { managementRequests++; }
}

class _RemovalPermissionModel extends _MemberPageModel {
  int kickRequests = 0;
  @override
  int? get backendSelfRole => backendRoleForMember('self');
  @override
  Future<V2TimCallback> kickOffMember(List<String> userIDs) async {
    kickRequests++;
    return V2TimCallback(code: -1, desc: 'test');
  }
}

class _TestClockManager implements TIMManager {
  @override
  int getServerTime() => 1000;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MuteResultModel extends _BackendAdminLayoutModel {
  bool fail = true;
  final requests = <String>[];
  @override
  Future<V2TimCallback> muteGroupMember(String userID, bool isMute, int? time) async {
    requests.add('$userID:$isMute');
    return V2TimCallback(code: fail && userID == 'failure' ? 1 : 0, desc: 'test');
  }
}
