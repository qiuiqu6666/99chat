import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_group_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'detail-persistence-owner';
  const group = '@TGS#_mcPersistence';
  final store = GroupLocalStore.instance;
  final dio = ApiClient.instance.dio;
  late Map<String, dynamic> payload;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() async {
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance.saveToken('test-token', userId: owner);
    await store.clearForOwner(owner);
    payload = {
      'groupId': group,
      'groupType': 'Community',
      'groupName': '新的群名称',
      'displayAlias': '群备注',
      'avatarUrl': 'https://example.com/avatar.jpg',
      'avatarPreviewUrl': 'https://example.com/preview.jpg',
      'avatarVersion': 2,
      'notice': '公告',
      'memberCount': 128,
      'myRole': 300,
      'myNameCard': '我的群昵称',
      'joinedAt': 1710000000000,
      'updatedAt': 1710000001000,
      'ownerUserId': 'group-owner',
      'noticeUpdatedAt': 1710000000500,
      'noticeUpdatedBy': 'editor',
      'gameEnabled': true,
    };
    dio.interceptors.clear();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      expect(request.method, 'GET');
      expect(request.path, '/group/${Uri.encodeComponent(group)}');
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: {'code': 0, 'message': 'ok', 'data': payload}));
    }));
  });
  tearDown(() async {
    dio.interceptors.clear();
    await store.clearForOwner(owner);
  });

  test('direct detail request persists every detail field and updates memory',
      () async {
    await MeGroupApi.instance.fetchGroupDetail(group);
    final record = (await store.read(ownerUserId: owner, groupId: group))!;
    expect(record.groupName, '新的群名称');
    expect(record.groupType, 'Community');
    expect(record.displayAlias, '群备注');
    expect(record.avatarUrl, payload['avatarUrl']);
    expect(record.avatarPreviewUrl, payload['avatarPreviewUrl']);
    expect(record.avatarVersion, 2);
    expect(record.notice, '公告');
    expect(record.memberCount, 128);
    expect(record.myRole, 300);
    expect(record.myNameCard, '我的群昵称');
    expect(record.joinedAt, payload['joinedAt']);
    expect(record.updatedAt, payload['updatedAt']);
    expect(record.ownerUserId, 'group-owner');
    expect(record.noticeUpdatedAt, payload['noticeUpdatedAt']);
    expect(record.noticeUpdatedBy, 'editor');
    expect(record.gameEnabled, isTrue);
    expect(store.readCached(ownerUserId: owner, groupId: group)?.myNameCard,
        '我的群昵称');
  });

  test('explicit clearing replaces old values and omitted fields survive',
      () async {
    await store.upsert(
        ownerUserId: owner,
        record: MeGroupRecord.fromJson({...payload, 'isAllMuted': true}));
    payload.addAll({
      'displayAlias': null,
      'myNameCard': '',
      'notice': '',
      'noticeUpdatedAt': null,
      'noticeUpdatedBy': null,
      'joinedAt': null,
      'gameEnabled': false,
      'updatedAt': 1710000002000
    });
    await MeGroupApi.instance.fetchGroupDetail(group);
    final record = (await store.read(ownerUserId: owner, groupId: group))!;
    expect(record.displayAlias, isEmpty);
    expect(record.myNameCard, isEmpty);
    expect(record.notice, isEmpty);
    expect(record.noticeUpdatedBy, isEmpty);
    expect(record.noticeUpdatedAt, 0);
    expect(record.joinedAt, 0);
    expect(record.gameEnabled, isFalse);
    expect(record.isAllMuted, isTrue);
  });

  test('late response cannot overwrite a newer local edit', () async {
    final pending = Completer<void>();
    final started = Completer<void>();
    dio.interceptors.clear();
    dio.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) async {
      started.complete();
      await pending.future;
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0,
        'data': {...payload}..remove('updatedAt')
      }));
    }));
    final request = MeGroupApi.instance.fetchGroupDetail(group);
    await started.future;
    await store.upsert(
        ownerUserId: owner,
        record: MeGroupRecord.fromJson({...payload, 'groupName': '刚修改的名称'}));
    pending.complete();
    await request;
    expect((await store.read(ownerUserId: owner, groupId: group))?.groupName,
        '刚修改的名称');
  });
}
