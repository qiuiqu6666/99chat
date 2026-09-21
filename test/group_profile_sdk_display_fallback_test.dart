import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info_result.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class _SdkDisplayGroupServices implements GroupServices {
  _SdkDisplayGroupServices(this.groupInfo);

  final V2TimGroupInfo groupInfo;

  @override
  Future<List<V2TimGroupInfoResult>?> getGroupsInfo({
    required List<String> groupIDList,
  }) async {
    return <V2TimGroupInfoResult>[
      V2TimGroupInfoResult(
        resultCode: 0,
        resultMessage: '',
        groupInfo: groupInfo,
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'profile-sdk-display-owner';
  const group = '@TGS#_mcProfileDisplay';

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
    setupServiceLocator();
    await ApiClient.instance.saveToken('test-token', userId: owner);
  });

  setUp(() async {
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance.saveToken('test-token', userId: owner);
    await GroupLocalStore.instance.clearForOwner(owner);
    ApiClient.instance.dio.interceptors.clear();
  });

  tearDown(() async {
    ApiClient.instance.dio.interceptors.clear();
    await GroupLocalStore.instance.clearForOwner(owner);
  });

  Future<void> seedShell() => GroupLocalStore.instance.upsert(
        ownerUserId: owner,
        record: MeGroupRecord.fromJson(<String, dynamic>{
          'groupId': group,
          'updatedAt': 2000,
        }),
      );

  test('SDK identity fills name and count after an ID-only detail', () async {
    await seedShell();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) => handler.resolve(
          Response(
            requestOptions: request,
            statusCode: 200,
            data: <String, dynamic>{
              'data': <String, dynamic>{'groupId': group, 'updatedAt': 2001},
            },
          ),
        ),
      ),
    );
    await serviceLocator.unregister<GroupServices>();
    serviceLocator.registerSingleton<GroupServices>(
      _SdkDisplayGroupServices(
        V2TimGroupInfo(
          groupID: group,
          groupType: 'Community',
          groupName: 'SDK display name',
          memberCount: 1403,
        ),
      ),
    );

    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    await model.loadGroupInfo(group);

    expect(model.groupInfo?.groupName, 'SDK display name');
    expect(model.groupInfo?.memberCount, 1403);
  });

  test('SDK non-empty name and count win over REST empty identity', () async {
    await seedShell();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) => handler.resolve(
          Response(
            requestOptions: request,
            statusCode: 200,
            data: <String, dynamic>{
              'data': <String, dynamic>{
                'groupId': group,
                'groupName': '',
                'memberCount': 0,
                'updatedAt': 2001,
              },
            },
          ),
        ),
      ),
    );
    await serviceLocator.unregister<GroupServices>();
    serviceLocator.registerSingleton<GroupServices>(
      _SdkDisplayGroupServices(
        V2TimGroupInfo(
          groupID: group,
          groupType: 'Community',
          groupName: 'SDK live name',
          memberCount: 1403,
        ),
      ),
    );

    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    await model.loadGroupInfo(group);

    expect(model.groupInfo?.groupName, 'SDK live name');
    expect(model.groupInfo?.memberCount, 1403);
  });

  test('stored SDK identity is not clobbered by REST name', () async {
    await GroupLocalStore.instance.upsert(
      ownerUserId: owner,
      record: MeGroupRecord.fromJson(<String, dynamic>{
        'groupId': group,
        'groupName': 'Stored SDK name',
        'avatarUrl': 'https://stored.test/a.png',
        'memberCount': 9,
        'updatedAt': 2000,
      }),
    );
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) => handler.resolve(
          Response(
            requestOptions: request,
            statusCode: 200,
            data: <String, dynamic>{
              'data': <String, dynamic>{
                'groupId': group,
                'groupName': 'REST name',
                'avatarUrl': 'https://rest.test/a.png',
                'updatedAt': 2001,
              },
            },
          ),
        ),
      ),
    );
    await serviceLocator.unregister<GroupServices>();
    serviceLocator.registerSingleton<GroupServices>(
      _SdkDisplayGroupServices(
        V2TimGroupInfo(
          groupID: group,
          groupType: 'Community',
          groupName: 'SDK live name',
          faceUrl: 'https://sdk.test/a.png',
          memberCount: 11,
        ),
      ),
    );

    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    await model.loadGroupInfo(group);

    expect(model.groupInfo?.groupName, 'SDK live name');
    expect(model.groupInfo?.faceUrl, 'https://sdk.test/a.png');
    expect(model.groupInfo?.memberCount, 11);
  });

  test('SDK zero count cannot wipe a stored or REST member total', () async {
    await GroupLocalStore.instance.upsert(
      ownerUserId: owner,
      record: MeGroupRecord.fromJson(<String, dynamic>{
        'groupId': group,
        'groupName': 'Stored group',
        'memberCount': 14733,
        'updatedAt': 2000,
      }),
    );
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) => handler.resolve(
          Response(
            requestOptions: request,
            statusCode: 200,
            data: <String, dynamic>{
              'data': <String, dynamic>{
                'groupId': group,
                'groupName': 'REST group',
                'memberCount': 14733,
                'updatedAt': 2001,
              },
            },
          ),
        ),
      ),
    );
    await serviceLocator.unregister<GroupServices>();
    serviceLocator.registerSingleton<GroupServices>(
      _SdkDisplayGroupServices(
        V2TimGroupInfo(
          groupID: group,
          groupType: 'Community',
          groupName: 'SDK live name',
          memberCount: 0,
        ),
      ),
    );

    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    await model.loadGroupInfo(group);

    expect(model.displayedMemberCount(), 14733);
    expect(
      GroupLocalStore.instance.readCached(groupId: group)?.memberCount,
      14733,
    );
    expect(model.groupInfo?.memberCount, 14733);
  });
}
