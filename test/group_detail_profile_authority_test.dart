import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_group_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info_result.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class _UnexpectedSdk implements GroupServices {
  int calls = 0;
  @override
  Future<List<V2TimGroupInfoResult>?> getGroupsInfo(
      {required List<String> groupIDList}) async {
    calls++;
    throw StateError('Complete REST detail must not need SDK metadata');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'rest-detail-owner';
  const group = '@TGS#_mcRestDetail';
  var role = 200;
  final requests = <RequestOptions>[];
  final sdk = _UnexpectedSdk();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    await serviceLocator.unregister<GroupServices>();
    serviceLocator.registerSingleton<GroupServices>(sdk);
  });
  setUp(() async {
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance.saveToken('token', userId: owner);
    await GroupLocalStore.instance.clearForOwner(owner);
    requests.clear();
    sdk.calls = 0;
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (r, h) {
      requests.add(r);
      h.resolve(Response(requestOptions: r, statusCode: 200, data: {
        'code': 0,
        'message': 'ok',
        'data': {
          'groupId': group,
          'groupType': 'Community',
          'groupName': 'REST group',
          'avatarUrl': '',
          'notice': '',
          'memberCount': 0,
          'myRole': role,
          'myNameCard': 'REST card',
          'ownerUserId': 'actual-owner',
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        }
      }));
    }));
  });
  tearDown(() async => GroupLocalStore.instance.clearForOwner(owner));

  for (final expectedRole in [200, 300, 400]) {
    test(
        'REST detail supplies role $expectedRole without SDK or management pages',
        () async {
      role = expectedRole;
      final model = TUIGroupProfileModel()..groupID = group;
      addTearDown(model.dispose);
      await model.loadGroupInfo(group);
      expect(model.hasLoadedManagementMembers, isFalse);
      expect(model.backendSelfRole, expectedRole);
      expect(model.groupInfoWithBackendRole?.role, expectedRole);
      expect(model.groupInfoWithBackendRole?.owner, 'actual-owner');
      expect(model.groupInfo?.groupName, 'REST group');
      expect(model.groupInfo?.memberCount, 0);
      expect(model.getSelfNameCard(), 'REST card');
      expect(sdk.calls, 0);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(requests.single.path, '/group/${Uri.encodeComponent(group)}');
      SessionIdentityService.instance.invalidate();
      expect(model.backendSelfRole, isNull);
    });
  }

  test('chat detail refresh primes the profile identity', () async {
    role = 300;
    final sync = GroupMembershipSyncService.forTest();
    await sync.refreshGroupDetail(group);
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    expect(model.backendSelfRole, 300);
    expect(GroupLocalStore.instance.readCached(groupId: group)?.myRole, 300);
    expect(requests, hasLength(1));
    expect(sdk.calls, 0);
  });

  test('detail cache never carries role across a new login generation',
      () async {
    role = 400;
    await MeGroupApi.instance.fetchGroupDetail(group);
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    expect(model.backendSelfRole, 400);
    SessionIdentityService.instance.invalidate();
    expect(model.backendSelfRole, isNull);
  });
}
