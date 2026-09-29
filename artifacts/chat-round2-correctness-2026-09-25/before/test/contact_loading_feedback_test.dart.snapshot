import 'dart:async';

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
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/contact_list_with_presence.dart';
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

  test('unchanged remark warmup does not announce another friendship revision',
      () async {
    final model = serviceLocator<TUIFriendShipViewModel>();
    await FriendSyncService.instance
        .seedC2cDisplayNamesFromFriendRecords(snapshot);
    final revision = model.friendListRevision;
    await FriendSyncService.instance
        .seedC2cDisplayNamesFromFriendRecords(snapshot);
    expect(model.friendListRevision, revision);
    expect(DisplayNameStore.instance.c2c(peer), 'Saved Remark');
  });

  test('clearing the last cached name still notifies when no named rows remain',
      () async {
    final model = serviceLocator<TUIFriendShipViewModel>();
    DisplayNameStore.instance.setC2C(peer, 'Old Remark', notify: false);
    final revision = model.friendListRevision;
    await FriendSyncService.instance.seedC2cDisplayNamesFromFriendRecords([
      snapshot.single.copyWith(remark: '', friendNickname: ''),
    ]);
    expect(DisplayNameStore.instance.c2c(peer), isNull);
    expect(model.friendListRevision, revision + 1);
  });

  testWidgets(
      'remark warmup reaches the real contact list without a reload loop',
      (tester) async {
    final errorHandler = FlutterError.onError;
    var loads = 0;
    final blocked = Completer<List<V2TimFriendInfo>>();
    Contact.debugLoadImFriends = () async {
      loads++;
      // Bound the broken loop so the test can assert instead of hanging.
      if (loads > 3) return blocked.future;
      await Future<void>.value();
      await FriendSyncService.instance
          .seedC2cDisplayNamesFromFriendRecords(snapshot);
      return [V2TimFriendInfo(userID: peer)];
    };
    try {
      await tester.pumpWidget(host());
      await tester.pump(const Duration(milliseconds: 300));
      FlutterError.onError = errorHandler;
      expect(find.byType(ContactListWithPresence), findsOneWidget);
      expect(find.text('Saved Remark'), findsOneWidget);
      expect(loads, lessThanOrEqualTo(2));
    } finally {
      FlutterError.onError = errorHandler;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
      'first loaded list is visible while a requested refresh is still pending',
      (tester) async {
    final errorHandler = FlutterError.onError;
    var loads = 0;
    final next = Completer<List<V2TimFriendInfo>>();
    Contact.debugLoadImFriends = () async {
      if (++loads > 1) return next.future;
      await Future<void>.value();
      PeerProfileRefreshBus.instance.notify(peer);
      return [V2TimFriendInfo(userID: peer, friendRemark: 'First Result')];
    };
    try {
      await tester.pumpWidget(host());
      await tester.pump(const Duration(milliseconds: 300));
      FlutterError.onError = errorHandler;
      expect(loads, 2);
      expect(find.byType(ContactListWithPresence), findsOneWidget);
      expect(find.text('First Result'), findsOneWidget);
      next.complete([]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          tester
              .widget<ContactListWithPresence>(
                  find.byType(ContactListWithPresence))
              .friends,
          isEmpty);
      expect(find.text('First Result'), findsNothing);
    } finally {
      FlutterError.onError = errorHandler;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}
