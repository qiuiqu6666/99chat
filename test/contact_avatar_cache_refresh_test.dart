import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/contact_list_with_presence.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const peer = 'avatar_cache_peer';
  const url = 'https://avatar.test/fixed.png';
  final profiles = UserProfileLocalService.instance;
  late Interceptor interceptor;
  late DefaultThemeData theme;
  late PresenceProvider presence;

  Future<void> saveVersion(int version) =>
      profiles.saveFriendRecord(MeFriendRecord(
          friendUserId: peer,
          remark: '',
          friendNickname: 'Peer',
          friendAvatarUrl: url,
          friendAvatarVersion: version,
          addedAt: 0,
          peerDeletedMe: false,
          canMessage: true));

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    setupServiceLocator();
    interceptor = InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: {'items': <dynamic>[]}));
    });
    ApiClient.instance.dio.interceptors.insert(0, interceptor);
  });
  tearDownAll(() => ApiClient.instance.dio.interceptors.remove(interceptor));
  setUp(() async {
    await profiles.clearSession();
    theme = DefaultThemeData();
    presence = PresenceProvider();
  });
  tearDown(() async {
    presence.dispose();
    theme.dispose();
    await profiles.clearSession();
  });

  for (final showPresence in [false, true]) {
    testWidgets(
        'same URL switches avatar cache after profile event, presence=$showPresence',
        (tester) async {
      final errorHandler = FlutterError.onError;
      try {
        await tester.runAsync(() => saveVersion(1));
        await tester.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: theme),
              ChangeNotifierProvider.value(value: presence),
            ],
            child: MaterialApp(
                home: Scaffold(
                    body: ContactListWithPresence(
              friends: [V2TimFriendInfo(userID: peer)],
              isShowOnlineStatus: showPresence,
            )))));
        await tester.pump(const Duration(milliseconds: 300));
        FlutterError.onError = errorHandler;
        Avatar avatar() => tester
            .widgetList<Avatar>(find.byType(Avatar))
            .singleWhere((widget) => widget.faceUrl == url);
        final oldKey = avatar().avatarCacheKey;
        await tester.runAsync(() => saveVersion(2));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(avatar().faceUrl, url);
        expect(avatar().avatarCacheKey, isNotNull);
        expect(avatar().avatarCacheKey, isNot(oldKey));
      } finally {
        FlutterError.onError = errorHandler;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }
}
