import 'package:tencent_cloud_chat_demo/utils/friend_display_name.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/contact.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const peer = 'loadingfeedbackpeer';
  late DefaultThemeData theme;
  late LocalSetting settings;
  late PresenceProvider presence;
  late Interceptor starredResponse;
  final snapshot = [
    MeFriendRecord(
      friendUserId: peer,
      remark: 'Saved Remark',
      friendNickname: 'Public Nick',
      friendAvatarUrl: '',
      addedAt: 0,
      peerDeletedMe: false,
      canMessage: true,
    )
  ];

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    setupServiceLocator();
    starredResponse = InterceptorsWrapper(onRequest: (options, handler) {
      if (options.path == '/me/starred-friends') {
        handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'items': <dynamic>[]}));
      } else {
        handler.reject(DioError(
            requestOptions: options,
            error: 'Unexpected request in contact loading test'));
      }
    });
    ApiClient.instance.dio.interceptors.insert(0, starredResponse);
  });
  tearDownAll(
      () => ApiClient.instance.dio.interceptors.remove(starredResponse));
  setUp(() async {
    await UserProfileLocalService.instance.clearSession();
    DisplayNameStore.instance.clear(notify: false);
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

  Widget host() => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: presence),
        ],
        child: const MaterialApp(home: Scaffold(body: Contact())),
      );


  testWidgets('contact SDK remark is available to profile with empty UIKit data',
      (tester) async {
    final errorHandler = FlutterError.onError;
    Contact.debugLoadImFriends = () async => [
      V2TimFriendInfo(userID: peer, friendRemark: 'Contact Remark'),
    ];
    try {
      await tester.pumpWidget(host());
      await tester.pump(const Duration(milliseconds: 300));
      FlutterError.onError = errorHandler;
      expect(find.text('Contact Remark'), findsOneWidget);
      expect(FriendDisplayName.resolveFriendRemark(
        userId: peer, imRemark: '', friendList: const [],
      ), 'Contact Remark');
    } finally {
      FlutterError.onError = errorHandler;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  test('SDK fallback cannot replace confirmed remark or resurrect cleared remark', () async {
    final service = UserProfileLocalService.instance;
    service.hydrateFromFriendRecords(snapshot);
    final sdk = [V2TimFriendInfo(userID: peer, friendRemark: 'Stale SDK Remark')];
    service.hydrateImFriendRemarkFallbacks(sdk);
    expect(FriendDisplayName.resolveFriendRemark(userId: peer), 'Saved Remark');
    await service.clearSession();
    service.hydrateFromFriendRecords([snapshot.single.copyWith(remark: '')]);
    service.hydrateImFriendRemarkFallbacks(sdk);
    expect(FriendDisplayName.resolveFriendRemark(
      userId: peer, imRemark: 'Stale SDK Remark', friendList: sdk,
    ), isEmpty);
  });

  test('nickname cache is never promoted to a profile remark', () {
    DisplayNameStore.instance.setC2C(peer, 'Public Nick', notify: false);
    UserProfileLocalService.instance.hydrateImFriendRemarkFallbacks([
      V2TimFriendInfo(userID: peer, friendRemark: ''),
    ]);
    expect(FriendDisplayName.resolveFriendRemark(userId: peer), isEmpty);
  });

  test('SDK fallback does not emit friendship refresh feedback', () {
    final model = serviceLocator<TUIFriendShipViewModel>();
    final revision = model.friendListRevision;
    final sdk = [V2TimFriendInfo(userID: peer, friendRemark: 'Contact Remark')];
    UserProfileLocalService.instance.hydrateImFriendRemarkFallbacks(sdk);
    UserProfileLocalService.instance.hydrateImFriendRemarkFallbacks(sdk);
    expect(model.friendListRevision, revision);
    expect(UserProfileLocalService.instance.readCached(peer)!.friendRemarkConfirmed,
      isFalse);
  });
}
