import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/az_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/contact.dart';
import 'package:tencent_cloud_chat_demo/src/provider/custom_sticker_package.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/home_tab_activity.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/contact_list_with_presence.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

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

  testWidgets(
      'large directory pump pauses hidden, resumes its cursor, and rejects replaced session rows',
      (tester) async {
    final directory = ImSdkRelationshipDirectory.instance;
    directory.reset();
    addTearDown(directory.reset);
    RelationshipFriendEntry entry(int index) => RelationshipFriendEntry(
        userId: 'person-$index',
        displayName: 'Person $index',
        faceUrl: '',
        remark: 'Person $index',
        sortKey: index.toString().padLeft(5, '0'));
    directory.applyFriendSnapshot(
        captureId: directory.beginFriendCapture(),
        entries: List.generate(2500, entry));
    const list = ContactListWithPresence(isShowOnlineStatus: false);
    await tester.pumpWidget(host(list, active: false));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AZListViewContainer), findsNothing);
    await tester.pumpWidget(host(list));
    await tester.pump();
    int rows() => tester
        .widget<AZListViewContainer>(find.byType(AZListViewContainer))
        .memberList!
        .length;
    final visible = rows();
    expect(visible, greaterThan(0));
    expect(visible, lessThan(2500));
    await tester.pumpWidget(host(list, active: false));
    final paused = rows();
    await tester.pump(const Duration(seconds: 2));
    expect(rows(), paused);
    directory.applyFriendRemoves(['person-0']);
    directory.applyFriendAdds([entry(3000)]);
    await tester.pumpWidget(host(list));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    final ids = tester
        .widget<AZListViewContainer>(find.byType(AZListViewContainer))
        .memberList!
        .map((row) => (row.memberInfo as V2TimFriendInfo).userID)
        .toList();
    expect(ids.length, 2500);
    expect(ids.toSet().length, 2500);
    expect(ids, isNot(contains('person-0')));
    expect(ids, contains('person-3000'));
    SessionIdentityService.instance.invalidate();
    directory.reset();
    directory.applyFriendSnapshot(
        captureId: directory.beginFriendCapture(), entries: [entry(4000)]);
    await tester.pump(const Duration(milliseconds: 120));
    expect(rows(), 1);
    expect(
        tester
            .widget<AZListViewContainer>(find.byType(AZListViewContainer))
            .memberList!
            .single
            .memberInfo
            .userID,
        'person-4000');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
