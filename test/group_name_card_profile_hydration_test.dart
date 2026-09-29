import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/auth_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/user_profile_record.dart';
import 'package:tencent_cloud_chat_demo/src/pages/profile_nickname_edit_page.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_name_card_profile_source.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_user_avatar.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_self_info_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/wide_popup.dart';

class _Theme extends ChangeNotifier implements DefaultThemeData {
  @override
  TUITheme get theme => TUITheme();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'name-card-profile-owner';
  const group = '@TGS#_mcProfileHydration';
  late TUIGroupProfileModel model;
  late GroupNameCardProfileSource source;

  MeResult me({String user = owner, String nickname = 'Recovered profile'}) =>
      MeResult(
          userId: user,
          phone: '',
          phoneMasked: '',
          nickname: nickname,
          avatarUrl: 'https://example.test/$user.png');

  GroupNameCardProfileSource create({
    required Future<MeResult> Function(CancelToken) load,
    Future<UserProfileRecord?> Function(String)? read,
    Duration timeout = const Duration(seconds: 6),
  }) =>
      source = GroupNameCardProfileSource(
          model: model,
          loadMe: load,
          readLocal: read ?? (_) async => null,
          timeout: timeout);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() async {
    TUIKitWidePopup.isShow = false;
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance.saveToken('profile-test-token', userId: owner);
    await UserProfileLocalService.instance.clearSession();
    await GroupLocalStore.instance.clearForOwner(owner);
    GroupMemberStore.instance.clear();
    serviceLocator<TUISelfInfoViewModel>().setLoginInfo(null);
    model = TUIGroupProfileModel()..groupID = group;
  });
  tearDown(() {
    // Widget tests replace the entire Navigator, rather than closing a route.
    TUIKitWidePopup.isShow = false;
    source.dispose();
    model.dispose();
    GroupMemberStore.instance.clear();
    serviceLocator<TUISelfInfoViewModel>().setLoginInfo(null);
  });

  test('own local name card works without SDK full user profile', () async {
    GroupMemberStore.instance
        .putNameCard(groupID: group, userID: owner, nameCard: 'Own group card');
    create(load: (_) async => me());
    expect(source.value.nameCard, 'Own group card');
    await source.reload();
    expect(source.value.nickname, 'Recovered profile');
  });

  test('account-scoped disk profile fills while network fails', () async {
    create(
        load: (_) async => throw StateError('offline'),
        read: (id) async {
          expect(id, owner);
          return UserProfileRecord(
              userId: owner,
              nickname: 'Local profile',
              avatarUrl: 'https://example.test/local.png');
        });
    await source.reload();
    expect(source.value.nickname, 'Local profile');
    expect(source.value.faceUrl, 'https://example.test/local.png');
    expect(source.loading, isFalse);
  });

  test('SDK profile belonging to the previous user is ignored', () async {
    serviceLocator<TUISelfInfoViewModel>().setLoginInfo(V2TimUserFullInfo(
        userID: 'previous-user',
        nickName: 'Wrong user',
        faceUrl: 'https://example.test/wrong.png'));
    create(load: (_) async => me());
    expect(source.value.nickname, isEmpty);
    await source.reload();
    expect(source.value.nickname, 'Recovered profile');
  });

  test(
      'timed out profile load releases state; retry and late response are safe',
      () async {
    final old = Completer<MeResult>();
    CancelToken? firstCancel;
    var calls = 0;
    create(
        timeout: const Duration(milliseconds: 20),
        load: (cancel) {
          if (++calls == 1) {
            firstCancel = cancel;
            return old.future;
          }
          return Future.value(me(nickname: 'New profile'));
        });
    await source.reload();
    expect(source.loading, isFalse);
    expect(source.loadFailed, isTrue);
    expect(firstCancel!.isCancelled, isTrue);
    await source.reload();
    old.complete(me(nickname: 'Stale profile'));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);
    expect(source.value.nickname, 'New profile');
  });

  test('account switch rejects late remote and disk profile', () async {
    final remote = Completer<MeResult>();
    final disk = Completer<UserProfileRecord?>();
    create(load: (_) => remote.future, read: (_) => disk.future);
    final work = source.reload();
    SessionIdentityService.instance.invalidate();
    remote.complete(me());
    disk.complete(UserProfileRecord(userId: owner, nickname: 'Old disk'));
    await work;
    expect(source.isCurrent, isFalse);
    expect(source.value.nickname, isEmpty);
    expect(source.value.faceUrl, isEmpty);
  });

  test('another user profile event does not discard own profile response',
      () async {
    final pending = Completer<MeResult>();
    create(load: (_) => pending.future);
    PeerProfileRefreshBus.instance.notify('unrelated-user');
    pending.complete(me());
    await source.reload();
    expect(source.value.nickname, 'Recovered profile');
  });

  test('late SDK self profile refreshes display before network finishes',
      () async {
    final pending = Completer<MeResult>();
    create(load: (_) => pending.future);
    serviceLocator<TUISelfInfoViewModel>().setLoginInfo(V2TimUserFullInfo(
        userID: owner,
        nickName: 'SDK profile',
        faceUrl: 'https://example.test/sdk.png'));
    expect(source.value.nickname, 'SDK profile');
    expect(source.value.faceUrl, 'https://example.test/sdk.png');
    pending.completeError(StateError('offline'));
    await source.reload();
    expect(source.value.nickname, 'SDK profile');
    expect(source.loading, isFalse);
  });

  test('closing cancels only the owned load and stops late notifications',
      () async {
    final remote = Completer<MeResult>();
    final disk = Completer<UserProfileRecord?>();
    late CancelToken cancellation;
    final closed = GroupNameCardProfileSource(
        model: model,
        loadMe: (cancel) {
          cancellation = cancel;
          return remote.future;
        },
        readLocal: (_) => disk.future);
    var notifications = 0;
    closed.addListener(() => notifications++);
    final work = closed.reload();
    closed.dispose();
    expect(cancellation.isCancelled, isTrue);
    create(load: (_) async => me());
    await source.reload();
    remote.complete(me(nickname: 'Closed page'));
    disk.complete(UserProfileRecord(userId: owner, nickname: 'Closed disk'));
    await work;
    serviceLocator<TUISelfInfoViewModel>().setLoginInfo(
        V2TimUserFullInfo(userID: owner, nickName: 'SDK profile'));
    expect(notifications, 0);
    expect(source.value.nickname, 'Recovered profile');
  });

  test('switching groups invalidates the opened editor identity', () async {
    final pending = Completer<MeResult>();
    create(load: (_) => pending.future);
    final work = source.reload();
    model.groupID = '@TGS#_anotherGroup';
    pending.complete(me());
    await work;
    expect(source.isCurrent, isFalse);
    expect(source.value.nameCard, isEmpty);
  });

  Future<void> openEditor(WidgetTester tester,
      {Future<bool> Function(String)? save}) async {
    tester.view.physicalSize = const Size(1024, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ChangeNotifierProvider<DefaultThemeData>(
        create: (_) => _Theme(),
        child: MaterialApp(home: Builder(builder: (context) {
          return Scaffold(
              body: TextButton(
                  onPressed: () {
                    unawaited(ProfileNicknameEditPage.pushGroupNameCard(context,
                        initialNameCard: '',
                        profileSource: source,
                        onSave: save ?? (_) async => true));
                  },
                  child: const Text('Open editor')));
        }))));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  for (final edited in [false, true]) {
    testWidgets(
        'late profile refreshes avatar without replacing draft: edited=$edited',
        (tester) async {
      final pending = Completer<MeResult>();
      create(load: (_) => pending.future);
      await openEditor(tester);
      if (edited) {
        await tester.enterText(find.byType(TextField), 'My draft');
        await tester.pump(const Duration(milliseconds: 350));
      }
      pending.complete(me());
      await tester.pump();
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, edited ? 'My draft' : 'Recovered profile');
      final avatar = tester.widget<AppUserAvatar>(find.byType(AppUserAvatar));
      expect(avatar.faceUrl, 'https://example.test/$owner.png');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'missing profile shows retry but does not block saving a nickname',
      (tester) async {
    var calls = 0;
    create(load: (_) async {
      calls++;
      throw StateError('offline');
    });
    await source.reload();
    String? saved;
    await openEditor(tester, save: (value) async {
      saved = value;
      return true;
    });
    expect(find.textContaining('Retry loading your profile'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Manual nickname');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(saved, 'Manual nickname');
    expect(calls, 1);
    expect(find.text('Open editor'), findsOneWidget);
  });

  testWidgets(
      'late default matching the typed draft still saves explicit input',
      (tester) async {
    final pending = Completer<MeResult>();
    create(load: (_) => pending.future);
    String? saved;
    await openEditor(tester, save: (value) async {
      saved = value;
      return true;
    });
    await tester.enterText(find.byType(TextField), 'Same nickname');
    await tester.pump(const Duration(milliseconds: 350));
    pending.complete(me(nickname: 'Same nickname'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(saved, 'Same nickname');
  });

  testWidgets('retry control refreshes the open editor after a failed load',
      (tester) async {
    var attempts = 0;
    create(load: (_) async {
      if (++attempts == 1) throw StateError('offline');
      return me(nickname: 'Retry recovered');
    });
    await source.reload();
    await openEditor(tester);
    await tester.tap(find.textContaining('Retry loading your profile'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.textContaining('Retry loading your profile'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Retry recovered');
    expect(tester.takeException(), isNull);
  });

  testWidgets('late profile does not replace active IME composition',
      (tester) async {
    serviceLocator<TUISelfInfoViewModel>()
        .setLoginInfo(V2TimUserFullInfo(userID: owner, nickName: 'ni'));
    final pending = Completer<MeResult>();
    create(load: (_) => pending.future);
    await openEditor(tester);
    await tester.showKeyboard(find.byType(TextField));
    tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2)));
    await tester.pump();
    pending.complete(me());
    await tester.pump();
    await tester.pump();
    final value =
        tester.widget<TextField>(find.byType(TextField)).controller!.value;
    expect(value.text, 'ni');
    expect(value.composing, const TextRange(start: 0, end: 2));
    expect(tester.takeException(), isNull);
  });
}
