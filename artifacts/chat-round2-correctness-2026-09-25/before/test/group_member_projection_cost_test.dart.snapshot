import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_uikit/data_services/profile/user_profile_local_bridge.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/az_list_view.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/group_member_list.dart';

V2TimGroupMemberFullInfo _member(String id, String name, {int role = 200}) =>
    V2TimGroupMemberFullInfo(userID: id, nickName: name, role: role);

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  tearDown(UserProfileLocalBridge.clear);

  Future<void> pump(WidgetTester tester, Widget child) async {
    final handler = FlutterError.onError;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: child),
    ));
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
  }

  Future<void> settle(WidgetTester tester) async {
    final handler = FlutterError.onError;
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
  }

  testWidgets('paged members do not resolve offscreen names for sorting',
      (tester) async {
    final reads = <String, int>{};
    UserProfileLocalBridge.configure(readCached: (id) {
      reads.update(id, (count) => count + 1, ifAbsent: () => 1);
      return null;
    });
    var members = <V2TimGroupMemberFullInfo?>[
      for (var i = 0; i < 1000; i++)
        _member('member_$i', 'Member ${i.toString().padLeft(4, '0')}'),
    ];
    late StateSetter rebuild;
    await pump(tester, StatefulBuilder(builder: (_, setState) {
      rebuild = setState;
      return GroupProfileMemberList(
        memberList: members,
        canSlideDelete: false,
        isShowOnlineStatus: false,
      );
    }));
    expect(reads['member_700'], isNull,
        reason: 'Alphabet sorting must not read an offscreen member name.');

    reads.clear();
    rebuild(() {
      members = [
        ...members,
        for (var i = 1000; i < 1050; i++)
          _member('member_$i', 'Member ${i.toString().padLeft(4, '0')}'),
      ];
    });
    await settle(tester);
    expect(reads['member_700'], isNull);
    expect(reads['member_1049'], isNull);
    final list =
        tester.widget<AZListViewContainer>(find.byType(AZListViewContainer));
    expect(list.memberList, hasLength(1050));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'page append keeps role priority and server order without letters',
      (tester) async {
    var members = <V2TimGroupMemberFullInfo?>[
      _member('zoey', 'Zoey'),
      _member('owner', 'Zed Owner', role: 400),
      _member('digits', '12345'),
    ];
    late StateSetter rebuild;
    await pump(tester, StatefulBuilder(builder: (_, setState) {
      rebuild = setState;
      return GroupProfileMemberList(
        memberList: members,
        canSlideDelete: false,
        isShowOnlineStatus: false,
        canAtAll: true,
        groupType: 'Public',
      );
    }));
    List<String> displayedIds() => tester
        .widget<AZListViewContainer>(find.byType(AZListViewContainer))
        .memberList!
        .map((item) => (item.memberInfo as V2TimGroupMemberFullInfo).userID)
        .toList();
    rebuild(() => members = [
          ...members,
          _member('alice', 'Alice'),
          _member('admin', 'Aaron Admin', role: 300),
        ]);
    await settle(tester);
    expect(displayedIds(), [
      GroupProfileMemberList.AT_ALL_USER_ID,
      'owner',
      'admin',
      'zoey',
      'digits',
      'alice',
    ]);
    final full = members;
    rebuild(() => members = filterGroupMembersByKeyword(full, 'alice'));
    await settle(tester);
    expect(displayedIds(), [GroupProfileMemberList.AT_ALL_USER_ID, 'alice']);
    rebuild(() => members = full);
    await settle(tester);
    expect(
        displayedIds().skip(1), ['owner', 'admin', 'zoey', 'digits', 'alice']);
    expect(tester.takeException(), isNull);
  });
}
