import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/pages/profile_nickname_edit_page.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/group_name_card_policy.dart';
import 'package:tencent_cloud_chat_demo/utils/group_name_card_save_failure.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/core_services_implements.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/self_hosted_group_bridge.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_recovery_trace.dart';

class _Groups implements GroupServices {
  final requests = <({String group, String user, String value})>[];
  Future<V2TimCallback> Function() save =
      () async => V2TimCallback(code: 0, desc: 'ok');
  int reads = 0;
  @override
  Future<V2TimCallback> setGroupMemberInfo(
      {required String groupID,
      required String userID,
      String? nameCard,
      Map<String, String>? customInfo}) {
    requests.add((group: groupID, user: userID, value: nameCard ?? ''));
    return save();
  }

  @override
  Future<V2TimValueCallback<List<V2TimGroupMemberFullInfo>>>
      getGroupMembersInfo(
          {required String groupID, required List<String> memberList}) async {
    reads++;
    throw StateError('member refresh unavailable');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Theme extends ChangeNotifier implements DefaultThemeData {
  @override
  TUITheme get theme => TUITheme();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Core extends CoreServicesImpl {
  _Core(this.user);
  final String user;
  @override
  V2TimUserFullInfo? get loginUserInfo => V2TimUserFullInfo(userID: user);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'name-card-owner';
  const group = '@TGS#_mcNameCardRecovery';
  late _Groups groups;
  late TUIGroupProfileModel model;
  var disposed = false;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() async {
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance.saveToken('test-token', userId: owner);
    ApiClient.instance.dio.interceptors.clear();
    SelfHostedGroupBridge.configure(loadGroupsInfo: (_) async => []);
    GroupMemberStore.instance.clear();
    groups = _Groups();
    await serviceLocator.unregister<GroupServices>();
    serviceLocator.registerSingleton<GroupServices>(groups);
    model = TUIGroupProfileModel()..groupID = group;
    disposed = false;
    await GroupLocalStore.instance.clearForOwner(owner);
    await GroupLocalStore.instance.upsert(
        ownerUserId: owner,
        record: MeGroupRecord.fromJson({
          'groupId': group,
          'groupType': 'Community',
          'groupName': 'Group',
          'notice': 'Keep notice',
          'avatarUrl': 'https://example.test/a.png',
          'myNameCard': 'Old name',
          'myRole': 200,
        }));
  });
  tearDown(() async {
    if (!disposed) model.dispose();
    SelfHostedGroupBridge.clear();
    GroupMemberStore.instance.clear();
    ApiClient.instance.dio.interceptors.clear();
    await GroupLocalStore.instance.clearForOwner(owner);
  });

  test('screenshot text is valid; byte and grapheme boundaries are consistent',
      () {
    const screenshot = '京东🌇公平公正/16.35元红包金额';
    expect(utf8.encode(screenshot).length, 43);
    expect(GroupNameCardPolicy.validationMessage(screenshot), isNull);
    expect(GroupNameCardPolicy.isLengthValid('${'中' * 16}ab'), isTrue);
    expect(GroupNameCardPolicy.isLengthValid('中' * 17), isFalse);
    expect(GroupNameCardPolicy.isLengthValid('👨‍👩‍👧‍👦' * 2), isTrue);
    expect(GroupNameCardPolicy.isLengthValid('👨‍👩‍👧‍👦' * 3), isFalse);
    expect(GroupNameCardPolicy.isLengthValid('a' * 21), isFalse);
  });

  test('business login saves even while SDK full profile is unavailable',
      () async {
    expect(serviceLocator<CoreServicesImpl>().loginUserInfo, isNull);
    final result = await model.setNameCard('New name');
    expect(result?.code, 0);
    expect(groups.requests.single.user, owner);
    expect(groups.reads, 0);
    expect(model.getSelfNameCard(), 'New name');
    expect(
        GroupMemberStore.instance.memberOf(group, owner)?.nameCard, 'New name');
    expect(
        ChatRecoveryTrace.recentEvents
            .any((e) => e.contains('name_card_ui_notified')),
        isTrue);
    expect(ChatRecoveryTrace.recentEvents.any((e) => e.contains('New name')),
        isFalse);
  });

  test('write failure and timeout both allow a later save', () async {
    groups.save = () async => throw StateError('temporary failure');
    expect((await model.setNameCard('First name'))?.code, isNot(0));
    final late = Completer<V2TimCallback>();
    groups.save = () => late.future;
    model.nameCardSaveTimeout = const Duration(milliseconds: 15);
    final timedOut = await model.setNameCard('Old pending');
    expect(timedOut?.code, isNot(0));
    expect(timedOut?.desc, contains('could not be confirmed'));
    groups.save = () async => V2TimCallback(code: 0, desc: 'ok');
    expect((await model.setNameCard('Latest name'))?.code, 0);
    late.complete(V2TimCallback(code: 0, desc: 'ok'));
    await Future<void>.delayed(Duration.zero);
    expect(model.getSelfNameCard(), 'Latest name');
  });

  for (final sdkOwner in [owner, 'old-account']) {
    test('native SDK dispatch requires matching identity: $sdkOwner', () async {
      SelfHostedGroupBridge.clear();
      model.dispose();
      final original = serviceLocator<CoreServicesImpl>();
      await serviceLocator.unregister<CoreServicesImpl>();
      serviceLocator.registerSingleton<CoreServicesImpl>(_Core(sdkOwner));
      addTearDown(() async {
        await serviceLocator.unregister<CoreServicesImpl>();
        serviceLocator.registerSingleton<CoreServicesImpl>(original);
      });
      model = TUIGroupProfileModel()..groupID = group;
      final result = await model.setNameCard('SDK nickname');
      if (sdkOwner == owner) {
        expect(result?.code, 0);
        expect(groups.requests.single.user, owner);
        expect(groups.reads, 0);
        expect(model.getSelfNameCard(), 'SDK nickname');
      } else {
        expect(result?.code, isNot(0));
        expect(groups.requests, isEmpty);
      }
    });
  }

  test('invalid byte length never sends a request', () async {
    final result = await model.setNameCard('中' * 17);
    expect(result?.code, isNot(0));
    expect(groups.requests, isEmpty);
  });

  test('generic numeric API error preserves a safe server explanation', () {
    final request = RequestOptions(path: '/group/g/members/me');
    final failure = GroupNameCardSaveFailure.fromError(DioError(
      requestOptions: request,
      type: DioErrorType.response,
      response: Response(
          requestOptions: request,
          statusCode: 400,
          data: {'code': 400, 'message': '请缩短群昵称'}),
    ));
    expect(failure.message, '请缩短群昵称');
  });

  for (final boundary in ['account', 'group', 'dispose']) {
    test('late save cannot update after $boundary changes', () async {
      final pending = Completer<V2TimCallback>();
      groups.save = () => pending.future;
      final saving = model.setNameCard('Late name');
      if (boundary == 'account') SessionIdentityService.instance.invalidate();
      if (boundary == 'group') model.groupID = 'other-group';
      if (boundary == 'dispose') {
        model.dispose();
        disposed = true;
      }
      pending.complete(V2TimCallback(code: 0, desc: 'ok'));
      expect((await saving)?.code, isNot(0));
      expect(
          GroupMemberStore.instance.memberOf(group, owner)?.nameCard, isNull);
    });
  }

  test('reversed responses cannot replace a newer confirmed nickname',
      () async {
    final old = Completer<V2TimCallback>();
    groups.save = () => old.future;
    final first = model.setNameCard('First name');
    groups.save = () async => V2TimCallback(code: 0, desc: 'ok');
    expect((await model.setNameCard('Second name'))?.code, 0);
    old.complete(V2TimCallback(code: 0, desc: 'ok'));
    expect((await first)?.code, isNot(0));
    expect(model.getSelfNameCard(), 'Second name');
  });

  test('REST business errors remain readable and a second attempt succeeds',
      () async {
    var calls = 0;
    ApiClient.instance.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (r, h) {
      calls++;
      h.resolve(Response(
          requestOptions: r,
          statusCode: 200,
          data: calls == 1
              ? {'code': 'IM_REST_ERROR', 'message': 'IM_REST_ERROR'}
              : {
                  'data': {'groupId': group, 'myNameCard': 'New name'}
                }));
    }));
    final sync = GroupMembershipSyncService.forTest();
    final failed = await sync.updateMyNameCard(
        groupId: group, userId: owner, nameCard: 'New name');
    expect(failed.code, isNot(0));
    expect(failed.desc, contains('service is unavailable'));
    final saved = await sync.updateMyNameCard(
        groupId: group, userId: owner, nameCard: 'New name');
    expect(saved.code, 0);
    final stored = GroupLocalStore.instance.readCached(groupId: group)!;
    expect(stored.myNameCard, 'New name');
    expect(stored.notice, 'Keep notice');
    expect(stored.groupName, 'Group');
  });

  test('REST response from an old account cannot patch local nickname',
      () async {
    final started = Completer<void>();
    final response = Completer<void>();
    ApiClient.instance.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (r, h) async {
      started.complete();
      await response.future;
      h.resolve(
          Response(requestOptions: r, statusCode: 200, data: {'data': {}}));
    }));
    final saving = GroupMembershipSyncService.forTest()
        .updateMyNameCard(groupId: group, userId: owner, nameCard: 'Late name');
    await started.future;
    SessionIdentityService.instance.invalidate();
    response.complete();
    expect((await saving).code, isNot(0));
    expect(GroupLocalStore.instance.readCached(groupId: group)?.myNameCard,
        'Old name');
  });

  test(
      'REST timeout cancels transport and allows retry without late projection',
      () async {
    final pending =
        <({RequestOptions request, RequestInterceptorHandler handler})>[];
    ApiClient.instance.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (r, h) {
      pending.add((request: r, handler: h));
      if (pending.length > 1) {
        h.resolve(
            Response(requestOptions: r, statusCode: 200, data: {'data': {}}));
      }
    }));
    final sync = GroupMembershipSyncService.forTest()
      ..nameCardRequestTimeout = const Duration(milliseconds: 30);
    final result = await sync.updateMyNameCard(
        groupId: group, userId: owner, nameCard: 'Pending name');
    expect(result.code, isNot(0));
    expect(result.desc, contains('could not be confirmed'));
    expect(pending.single.request.cancelToken?.isCancelled, isTrue);
    expect(
        (await sync.updateMyNameCard(
                groupId: group, userId: owner, nameCard: 'Final name'))
            .code,
        0);
    pending.first.handler.resolve(
        Response(requestOptions: pending.first.request, statusCode: 200, data: {
      'data': {'myNameCard': 'Pending name'}
    }));
    await Future<void>.delayed(Duration.zero);
    expect(GroupLocalStore.instance.readCached(groupId: group)?.myNameCard,
        'Final name');
  });

  test('confirmed remote save survives a real local database write failure',
      () async {
    final db = await databaseFactory
        .openDatabase(p.join(await getDatabasesPath(), 'group_local_v1.db'));
    await db.execute(
        "CREATE TEMP TRIGGER name_card_test_failure BEFORE INSERT ON my_groups "
        "WHEN NEW.owner_user_id = '$owner' AND NEW.my_name_card = 'Saved remotely' "
        "BEGIN SELECT RAISE(FAIL, 'simulated disk failure'); END");
    addTearDown(
        () => db.execute('DROP TRIGGER IF EXISTS name_card_test_failure'));
    ApiClient.instance.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (r, h) {
      h.resolve(
          Response(requestOptions: r, statusCode: 200, data: {'data': {}}));
    }));
    final sync = GroupMembershipSyncService.forTest();
    groups.save = () => sync.updateMyNameCard(
        groupId: group, userId: owner, nameCard: 'Saved remotely');
    final saved = await model.setNameCard('Saved remotely');
    expect(saved?.code, 0);
    expect(model.getSelfNameCard(), 'Saved remotely');
    expect(
        ChatRecoveryTrace.recentEvents
            .any((e) => e.contains('name_card_local_refresh_deferred')),
        isTrue);
    expect(groups.reads, 0);
  });

  testWidgets('specific error stays visible; failed editor remains retryable',
      (tester) async {
    var calls = 0;
    String? finished;
    await tester.pumpWidget(ChangeNotifierProvider<DefaultThemeData>(
        create: (_) => _Theme(),
        child: MaterialApp(
            home: ProfileNicknameEditPage(
          initialNickname: 'Valid name',
          embedded: true,
          onFinish: (s) => finished = s,
          onSave: (_) async {
            if (++calls == 1) throw const GroupNameCardSaveFailure('昵称服务暂不可用');
            return true;
          },
        ))));
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(find.text('昵称服务暂不可用'), findsOneWidget);
    expect(find.text('保存失败'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(calls, 2);
    expect(finished, 'Valid name');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
