import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_profile_host.dart';
import 'package:tencent_cloud_chat_demo/src/pages/join_group_application_page.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/pages/add_friend_page.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_mention_nav.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_mention_local_lookup.dart';
import 'package:tencent_cloud_chat_demo/utils/group_privacy_guard.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class _QuietPresence extends PresenceProvider {
  @override
  void ensure(Iterable<String> userIds, {bool includeVisibility = true}) {}
  @override
  void refresh(Iterable<String> userIds, {bool urgent = false, bool includeVisibility = true}) {}
}

class _PushObserver extends NavigatorObserver {
  Completer<void>? nextPush;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    nextPush?.complete();
    nextPush = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'mentionlocalowner';
  const peer = 'hnyzbsbhw5';
  const gid = '@TGS#2LOCAL123';
  const alias = '@myjoinedalias';
  final friends = FriendLocalStore.instance;
  final groups = GroupLocalStore.instance;
  late Interceptor rejectNetwork;
  final requests = <String>[];
  late DefaultThemeData theme;
  late PresenceProvider presence;

  MeGroupRecord group({int role = 200}) => MeGroupRecord(
        groupId: gid,
        groupType: 'Public',
        groupName: 'Local Joined Group',
        displayAlias: alias,
        avatarUrl: '',
        notice: '',
        memberCount: 8,
        myRole: role,
        myNameCard: '',
        joinedAt: 1,
        updatedAt: 1,
      );

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(Directory.systemTemp.createTempSync('mention-local-test-').path);
    setupServiceLocator();
  });
  setUp(() async {
    await ApiClient.instance.saveToken('test-token', userId: owner);
    await friends.clearForOwner(owner);
    await friends.upsert(
        ownerUserId: owner,
        record: MeFriendRecord(
          friendUserId: peer,
          remark: 'Local Remark',
          friendNickname: 'Local Nick',
          friendAvatarUrl: '',
          addedAt: 1,
          peerDeletedMe: false,
          canMessage: true,
        ));
    groups.debugOwnerUserIdOverride = owner;
    groups.debugPutCachedRecord(ownerUserId: owner, record: group());
    GroupMemberStore.instance.clear(notify: false);
    GroupPrivacyCache.set(gid, false);
    DesktopProfileHost.close();
    theme = DefaultThemeData();
    presence = _QuietPresence();
    requests.clear();
    rejectNetwork = InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options.path);
      handler.reject(DioError(requestOptions: options, error: 'offline'));
    });
    ApiClient.instance.dio.interceptors.insert(0, rejectNetwork);
  });
  tearDown(() async {
    ApiClient.instance.dio.interceptors.remove(rejectNetwork);
    await friends.clearForOwner(owner);
    groups.debugRemoveCachedRecord(ownerUserId: owner, groupId: gid);
    groups.debugClearOwnerOverride();
    GroupPrivacyCache.invalidate(gid);
    GroupMemberStore.instance.clear(notify: false);
    DesktopProfileHost.close();
    presence.dispose();
    theme.dispose();
  });

  Widget host({NavigatorObserver? observer}) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: presence)
        ],
        child: MaterialApp(
          navigatorObservers: [if (observer != null) observer],
          home: const Scaffold(body: SizedBox(key: Key('entry'))),
        ),
      );

  testWidgets('standalone add-friend details has no more action',
      (tester) async {
    final originalHandler = FlutterError.onError;
    try {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: presence),
        ],
        child: MaterialApp(
          home: AddFriendPage(
            userID: 'profile-preview',
            nickname: 'Preview',
            useLocalProfile: true,
            initialUserInfo: V2TimUserFullInfo(
              userID: 'profile-preview',
              nickName: 'Preview',
            ),
          ),
        ),
      ));
      await tester.pump();
      FlutterError.onError = originalHandler;
      expect(find.byType(AddFriendPage), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
    } finally {
      FlutterError.onError = originalHandler;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }
  });

  test('disk friend lookup and exact joined alias need no network', () async {
    await friends.clearSession();
    expect((await ChatMentionLocalLookup.friend('@$peer'))?.userID, peer);
    expect((await ChatMentionLocalLookup.joinedGroup(alias))?.groupID, gid);
    expect((await ChatMentionLocalLookup.joinedGroup(gid))?.groupID, gid);
    expect(requests, isEmpty);
  });

  test('non-member metadata cannot enable a joined group shortcut', () async {
    groups.debugPutCachedRecord(ownerUserId: owner, record: group(role: 0));
    expect(await ChatMentionLocalLookup.joinedGroup(alias), isNull);
    expect(requests, isEmpty);
  });

  test('explicit non-friend record cannot be used as a friend', () async {
    await friends.upsert(
        ownerUserId: owner,
        record: MeFriendRecord(
          friendUserId: peer,
          remark: 'Old Remark',
          friendNickname: '',
          friendAvatarUrl: '',
          addedAt: 0,
          peerDeletedMe: true,
          canMessage: false,
          isFriend: false,
          inMyFriendList: false,
        ));
    expect(await ChatMentionLocalLookup.friend(peer), isNull);
    expect(requests, isEmpty);
  });

  testWidgets('UID click opens local friend even when APIs are unavailable',
      (tester) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host());
    try {
      await tester.runAsync(() => ChatIdMentionNavigator.open(
          tester.element(find.byKey(const Key('entry'))), '@$peer'));
      expect(DesktopProfileHost.userId, peer);
      expect(requests, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'cached group member click uses local friend without relation search',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    GroupMemberStore.instance.putMember(
        gid, V2TimGroupMemberFullInfo(userID: peer, nickName: 'Member Name'),
        notify: false);
    await tester.pumpWidget(host());
    try {
      await tester.runAsync(() => ChatIdMentionNavigator.open(
          tester.element(find.byKey(const Key('entry'))), '@Member Name',
          groupId: gid));
      expect(DesktopProfileHost.userId, peer);
      expect(DesktopProfileHost.groupId, gid);
      expect(requests, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'joined alias renders local group immediately without detail requests',
      (tester) async {
    final observer = _PushObserver();
    final originalHandler = FlutterError.onError;
    await tester.pumpWidget(host(observer: observer));
    try {
      observer.nextPush = Completer<void>();
      await tester.runAsync(() async {
        unawaited(ChatIdMentionNavigator.open(
            tester.element(find.byKey(const Key('entry'))), alias));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      FlutterError.onError = originalHandler;
      expect(find.byType(JoinGroupApplicationPage), findsOneWidget);
      expect(find.text('Local Joined Group'), findsOneWidget);
      expect(
          tester
              .widget<JoinGroupApplicationPage>(
                  find.byType(JoinGroupApplicationPage))
              .locallyJoined,
          isTrue);
      expect(requests, isEmpty);
    } finally {
      FlutterError.onError = originalHandler;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
      'non-friend cached member opens from initial profile without user lookup',
      (tester) async {
    const member = 'localnonfriend';
    GroupPrivacyCache.set(gid, true);
    GroupMemberStore.instance.putMember(gid,
        V2TimGroupMemberFullInfo(userID: member, nickName: 'Cached Member', role: 300),
        notify: false);
    final originalHandler = FlutterError.onError;
    await tester.pumpWidget(host());
    try {
      await tester.runAsync(() async {
        unawaited(ChatIdMentionNavigator.open(
            tester.element(find.byKey(const Key('entry'))), '@Cached Member',
            groupId: gid));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      FlutterError.onError = originalHandler;
      expect(find.byType(AddFriendPage), findsOneWidget);
      final page = tester.widget<AddFriendPage>(find.byType(AddFriendPage));
      expect(page.useLocalProfile, isTrue);
      expect(page.initialUserInfo?.nickName, 'Cached Member');
      expect(
          requests.where(
              (path) => path == '/users/search' || path.endsWith('/relation')),
          isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      FlutterError.onError = originalHandler;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
      'structured groupMemberUserId opens profile even when token looks like community short',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host());
    try {
      await tester.runAsync(() => ChatIdMentionNavigator.open(
            tester.element(find.byKey(const Key('entry'))),
            'C',
            groupId: gid,
            groupMemberUserId: peer,
          ));
      expect(DesktopProfileHost.userId, peer);
      expect(find.byType(JoinGroupApplicationPage), findsNothing);
      expect(requests, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'UID member click fills public nick without user lookup',
      (tester) async {
    const member = 'k862n7jezw';
    GroupPrivacyCache.set(gid, true);
    GroupMemberStore.instance.putMember(
        gid,
        V2TimGroupMemberFullInfo(
            userID: member, nickName: 'Public Nick', role: 300),
        notify: false);
    final originalHandler = FlutterError.onError;
    await tester.pumpWidget(host());
    try {
      await tester.runAsync(() async {
        unawaited(ChatIdMentionNavigator.open(
            tester.element(find.byKey(const Key('entry'))), member,
            groupId: gid, groupMemberUserId: member));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      FlutterError.onError = originalHandler;
      expect(find.byType(AddFriendPage), findsOneWidget);
      final page = tester.widget<AddFriendPage>(find.byType(AddFriendPage));
      expect(page.useLocalProfile, isTrue);
      expect(page.initialUserInfo?.nickName, 'Public Nick');
      expect(page.nickname, 'Public Nick');
      expect(
          requests.where(
              (path) => path == '/users/search' || path.endsWith('/relation')),
          isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      FlutterError.onError = originalHandler;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  test(
      'openUserProfileOrAddFriend still fetches public profile when using local mention data',
      () {
    final source =
        File('lib/utils/profile_page_nav.dart').readAsStringSync();
    final start =
        source.indexOf('static Future<bool> openUserProfileOrAddFriend(');
    expect(start, greaterThanOrEqualTo(0));
    final next = source.indexOf('\n  static ', start + 10);
    final body =
        next > start ? source.substring(start, next) : source.substring(start);
    expect(body.contains('getUsersInfo'), isTrue);
    expect(
      RegExp(
        r'if\s*\(\s*!useLocalMentionData\s*\)[\s\S]{0,160}getUsersInfo',
      ).hasMatch(body),
      isFalse,
    );
  });

  testWidgets('unknown UID still falls back to remote profile by id',
      (tester) async {
    await tester.pumpWidget(host());
    try {
      await tester.runAsync(() => ChatIdMentionNavigator.open(
          tester.element(find.byKey(const Key('entry'))), '@unknownlocaluid'));
      expect(requests, contains('/users/unknownlocaluid/profile'));
      expect(requests, isNot(contains('/users/search')));
      expect(DesktopProfileHost.isOpen, isFalse);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
      'group manager opens in-group non-friend profile without uid search',
      (tester) async {
    const member = 'groupnonfriend';
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    groups.debugPutCachedRecord(ownerUserId: owner, record: group(role: 400));
    GroupMemberStore.instance.putMember(
        gid,
        V2TimGroupMemberFullInfo(
            userID: member, nickName: 'Hidden Member', role: 200),
        notify: false);
    await tester.pumpWidget(host());
    try {
      await tester.runAsync(() => ChatIdMentionNavigator.open(
          tester.element(find.byKey(const Key('entry'))), '@$member',
          groupId: gid));
      expect(DesktopProfileHost.userId, member);
      expect(DesktopProfileHost.groupId, gid);
      expect(
          requests.where((path) =>
              path == '/users/search' || path.endsWith('/profile')),
          isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  test('local privacy and roles continue blocking ordinary members', () async {
    GroupPrivacyCache.set(gid, true);
    GroupMemberStore.instance.putMember(
        gid, V2TimGroupMemberFullInfo(userID: peer, role: 200),
        notify: false);
    expect(
        await GroupPrivacyGuard.blockedGroupProfileHint(
            groupId: gid, targetUserId: peer),
        isNotNull);
    expect(requests, isEmpty);
  });
}
