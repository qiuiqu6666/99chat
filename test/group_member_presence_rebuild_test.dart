import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_status.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/az_list_view.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/group_member_list.dart';

class _CountingMember extends V2TimGroupMemberFullInfo {
  _CountingMember(String id, String name)
      : super(userID: id, nickName: name, role: 200);

  int nameReads = 0;

  @override
  String? get nickName {
    nameReads++;
    return super.nickName;
  }
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    final handler = FlutterError.onError;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
  }

  Future<void> settle(WidgetTester tester) async {
    final handler = FlutterError.onError;
    await tester.pumpAndSettle();
    FlutterError.onError = handler;
  }

  testWidgets(
      'presence updates mounted status without rescanning 1403 member signatures',
      (tester) async {
    final friendship = serviceLocator<TUIFriendShipViewModel>();
    friendship.userStatusList = [];
    final members = [
      for (var i = 0; i < 1403; i++)
        _CountingMember(
            'presence_$i', 'Member ${i.toString().padLeft(4, '0')}'),
    ];
    await pump(
        tester,
        GroupProfileMemberList(
          memberList: members,
          canSlideDelete: false,
          presenceLabelBuilder: (id, online) =>
              '${online ? 'online' : 'offline'}:$id',
        ));
    final before = tester
        .widget<AZListViewContainer>(find.byType(AZListViewContainer))
        .memberList;
    final namesRevision = friendship.friendListRevision;
    members[1000].nameReads = 0;
    expect(find.text('offline:presence_0'), findsOneWidget);
    friendship.userStatusList = [
      V2TimUserStatus(userID: 'presence_0', statusType: 1)
    ];
    await settle(tester);
    expect(find.text('online:presence_0'), findsOneWidget);
    expect(find.text('offline:presence_0'), findsNothing);
    expect(friendship.friendListRevision, namesRevision);
    expect(members[1000].nameReads, 0,
        reason:
            'Even a cache-hit signature scan would read the offscreen name.');
    expect(
        identical(
            tester
                .widget<AZListViewContainer>(find.byType(AZListViewContainer))
                .memberList,
            before),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'friend display revision updates visible names without reordering',
      (tester) async {
    final friendship = serviceLocator<TUIFriendShipViewModel>();
    await pump(
        tester,
        GroupProfileMemberList(
          memberList: [
            _CountingMember('rename_alice', 'Alice'),
            _CountingMember('rename_zoey', 'Zoey'),
          ],
          canSlideDelete: false,
          isShowOnlineStatus: false,
        ));
    final before = friendship.friendListRevision;
    DisplayNameStore.instance.setC2C('rename_zoey', 'Aaron renamed');
    await settle(tester);
    expect(friendship.friendListRevision, greaterThan(before));
    expect(find.text('Aaron renamed'), findsOneWidget);
    expect(find.text('Zoey'), findsNothing);
    final rows = tester
        .widget<AZListViewContainer>(find.byType(AZListViewContainer))
        .memberList!;
    expect((rows.first.memberInfo as V2TimGroupMemberFullInfo).userID,
        'rename_alice');
    expect(tester.takeException(), isNull);
  });
}
