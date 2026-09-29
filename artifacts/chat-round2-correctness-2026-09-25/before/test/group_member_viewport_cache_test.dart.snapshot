import 'dart:async';

import 'package:azlistview_all_platforms/azlistview_all_platforms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/widgets/tim_uikit_group_manage.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/group_member_list.dart';

List<V2TimGroupMemberFullInfo?> _members(int count) => List.generate(
      count,
      (i) => V2TimGroupMemberFullInfo(
        userID: 'member_$i',
        nickName: 'Member ${i.toString().padLeft(4, '0')}',
        role: 200,
      ),
    );

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    final handler = FlutterError.onError;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Center(child: SizedBox(width: 400, height: 640, child: child))),
    ));
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
  }

  Future<void> settle(WidgetTester tester) async {
    final handler = FlutterError.onError;
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
  }

  testWidgets(
      '1403 members create only viewport rows and bounded presence work',
      (tester) async {
    final requested = <String>[];
    final presence = ValueNotifier<int>(0);
    addTearDown(presence.dispose);
    await pump(
        tester,
        GroupProfileMemberList(
          memberList: _members(1403),
          canSlideDelete: false,
          presenceListenable: presence,
          onMemberListLoaded: requested.addAll,
        ));
    final list = tester.widget<AzListView>(find.byType(AzListView));
    expect(list.cacheExtent, 240);
    final initialAvatars =
        find.byType(Avatar, skipOffstage: false).evaluate().length;
    expect(initialAvatars, inInclusiveRange(8, 16));
    expect(requested.length, inInclusiveRange(initialAvatars, 20));
    expect(requested.toSet().length, requested.length);

    final firstRequestCount = requested.length;
    presence.value++;
    await settle(tester);
    expect(requested.length, firstRequestCount,
        reason: 'Presence updates must not request the same rows again.');

    list.itemScrollController!.jumpTo(index: 60);
    await settle(tester);
    expect(requested.length, greaterThan(firstRequestCount));
    expect(requested.toSet().length, requested.length);
    expect(find.byType(Avatar, skipOffstage: false).evaluate().length,
        lessThanOrEqualTo(22));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'deep scroll reaches real paging and keeps position across rebuild and route return',
      (tester) async {
    var members = _members(100);
    var pageRequests = 0;
    var scrollNotifications = 0;
    late StateSetter rebuild;
    await pump(tester, StatefulBuilder(builder: (context, setState) {
      rebuild = setState;
      return NotificationListener<ScrollNotification>(
        onNotification: (_) {
          scrollNotifications++;
          return false;
        },
        child: GroupProfileMemberList(
          memberList: members,
          canSlideDelete: false,
          isShowOnlineStatus: false,
          touchBottomCallBack: () {
            pageRequests++;
            setState(() => members = _members(200));
          },
        ),
      );
    }));
    final controller = tester
        .widget<AzListView>(find.byType(AzListView))
        .itemScrollController!;
    await tester.drag(find.byType(AzListView), const Offset(0, -120));
    await settle(tester);
    controller.jumpTo(index: 95);
    await settle(tester);
    expect(pageRequests, 1);
    expect(scrollNotifications, greaterThan(0));
    expect(tester.widget<AzListView>(find.byType(AzListView)).itemCount, 200);
    final before = tester.getTopLeft(find.text('Member 0095')).dy;
    rebuild(() {});
    await settle(tester);
    expect(
        tester.getTopLeft(find.text('Member 0095')).dy, closeTo(before, 0.1));

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('member detail'))));
    await settle(tester);
    navigator.pop();
    await settle(tester);
    expect(
        tester.getTopLeft(find.text('Member 0095')).dy, closeTo(before, 0.1));
    expect(pageRequests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending member page suppresses repeated near-bottom requests',
      (tester) async {
    final pendingPage = Completer<void>();
    var pageRequests = 0;
    await pump(
        tester,
        GroupProfileMemberList(
          memberList: _members(100),
          canSlideDelete: false,
          isShowOnlineStatus: false,
          touchBottomCallBack: () {
            pageRequests++;
            return pendingPage.future;
          },
        ));
    final controller = tester
        .widget<AzListView>(find.byType(AzListView))
        .itemScrollController!;
    controller.jumpTo(index: 95);
    await settle(tester);
    controller.jumpTo(index: 96);
    await settle(tester);
    controller.jumpTo(index: 97);
    await settle(tester);
    expect(pageRequests, 1);

    pendingPage.complete();
    await settle(tester);
    expect(pageRequests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin picker displays the page loaded at the bottom',
      (tester) async {
    var members = _members(100);
    final memberUpdates = ChangeNotifier();
    addTearDown(memberUpdates.dispose);
    var pageRequests = 0;
    await pump(
        tester,
        GroupProfileAddAdmin(
          groupID: 'g1',
          memberList: members,
          memberListProvider: () => members,
          memberListListenable: memberUpdates,
          appbarTitle: 'Set administrator',
          onReachBottom: () async {
            pageRequests++;
            await Future<void>.delayed(Duration.zero);
            members = _members(200);
            memberUpdates.notifyListeners();
          },
        ));
    final controller = tester
        .widget<AzListView>(find.byType(AzListView))
        .itemScrollController!;
    controller.jumpTo(index: 95);
    await settle(tester);

    expect(pageRequests, 1);
    expect(tester.widget<AzListView>(find.byType(AzListView)).itemCount, 200);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'appended members keep server order and preserve the viewport anchor',
      (tester) async {
    var members = _members(100);
    late StateSetter rebuild;
    await pump(tester, StatefulBuilder(builder: (_, setState) {
      rebuild = setState;
      return GroupProfileMemberList(
        memberList: members,
        canSlideDelete: false,
        isShowOnlineStatus: false,
      );
    }));
    tester
        .widget<AzListView>(find.byType(AzListView))
        .itemScrollController!
        .jumpTo(index: 60, alignment: 0.2);
    await settle(tester);
    final before = tester.getTopLeft(find.text('Member 0060')).dy;
    rebuild(() => members = [
          ...members,
          for (var i = 0; i < 25; i++)
            V2TimGroupMemberFullInfo(
                userID: 'new_$i', nickName: 'Aaron $i', role: 200),
        ]);
    await settle(tester);
    expect(tester.widget<AzListView>(find.byType(AzListView)).itemCount, 125);
    expect(
        tester.getTopLeft(find.text('Member 0060')).dy, closeTo(before, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('short first page still requests its next page without scrolling',
      (tester) async {
    var pages = 0;
    await pump(
        tester,
        GroupProfileMemberList(
          memberList: _members(3),
          isShowOnlineStatus: false,
          canSlideDelete: false,
          touchBottomCallBack: () => pages++,
        ));
    expect(pages, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mention picker works without alphabet index and keeps selection',
      (tester) async {
    var selected = <V2TimGroupMemberFullInfo>[];
    await pump(
        tester,
        GroupProfileMemberList(
          memberList: _members(30),
          canSlideDelete: false,
          canSelectMember: true,
          canAtAll: true,
          groupType: 'Public',
          isShowOnlineStatus: false,
          onSelectedMemberChange: (value) => selected = value,
        ));
    expect(find.byType(AzListView), findsOneWidget);
    expect(tester.widget<AzListView>(find.byType(AzListView)).cacheExtent, 240);
    await tester.tap(find.text('Member 0000'));
    await settle(tester);
    expect(selected.map((member) => member.userID), ['member_0']);
    expect(tester.takeException(), isNull);
  });
}
