import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/group_member_join_meta_loader.dart';
import 'package:tencent_cloud_chat_demo/utils/group_privacy_guard.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'owner-inviter-loader';
  const groupId = '@TGS#_mc2SX4NMM62CZ';
  const userId = 'jv1k2mg752';
  final store = GroupMemberLocalStore.instance;
  final requests = <RequestOptions>[];
  late void Function(RequestOptions, RequestInterceptorHandler) respond;

  Map<String, dynamic> payload({String? channel = 'invite'}) => {
        'groupId': groupId,
        'userId': userId,
        'invitedByUserId': channel == 'invite' ? 'q14gkm5swv' : null,
        'invitedByNickname': channel == 'invite' ? '邀请人昵称' : null,
        'joinChannel': channel,
      };

  Future<void> seed({String channel = '', String inviter = ''}) =>
      store.upsertMany(ownerUserId: owner, groupId: groupId, records: [
        GroupMemberRecord(
          userId: userId,
          nickname: '成员昵称',
          avatarUrl: 'avatar',
          friendRemark: 'remark',
          nameCard: 'card',
          role: 300,
          joinedAt: 1700000000000,
          isSelf: false,
          muteUntil: 1900000000,
          joinChannel: channel,
          invitedByUserId: inviter,
          invitedByNickname: inviter.isEmpty ? '' : '已缓存邀请人',
        ),
      ]);

  Future<GroupMemberRecord?> load() => GroupMemberJoinMetaLoader.loadVisible(
        groupId: groupId,
        userId: 'c2c_@$userId',
      );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(onRequest: (request, handler) {
        requests.add(request);
        respond(request, handler);
      }),
    );
  });

  setUp(() async {
    requests.clear();
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance.saveToken('test-token', userId: owner);
    GroupPrivacyCache.set(groupId, false);
    respond = (request, handler) => handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: payload(),
        ));
  });

  tearDown(() async {
    await store.clearForOwner(owner);
    await ApiClient.instance.clearToken();
  });

  test('existing join time still fetches one inviter and preserves member data',
      () async {
    await seed();
    final record = await load();
    expect(requests, hasLength(1));
    expect(requests.single.method, 'GET');
    expect(requests.single.path,
        '/group/%40TGS%23_mc2SX4NMM62CZ/members/$userId/inviter');
    expect(record!.invitedByUserId, 'q14gkm5swv');
    expect(record.invitedByNickname, '邀请人昵称');
    expect(record.joinChannel, 'invite');
    expect(record.joinedAt, 1700000000000);
    expect(record.nickname, '成员昵称');
    expect(record.role, 300);
    expect(record.muteUntil, 1900000000);
    final saved = await store.readRecord(
        groupId: groupId, userId: userId, ownerUserId: owner);
    expect(saved!.invitedByUserId, 'q14gkm5swv');
    expect(saved.nameCard, 'card');
    expect(saved.avatarUrl, 'avatar');
    expect(saved.friendRemark, 'remark');
    await load();
    expect(requests, hasLength(1));
  });

  test('invite without inviter uses the dedicated endpoint', () async {
    await seed(channel: 'invite');
    expect((await load())!.invitedByNickname, '邀请人昵称');
    expect(requests, hasLength(1));
  });

  test('known group ID join needs no inviter request', () async {
    await seed(channel: 'group_id');
    expect((await load())!.joinChannel, 'group_id');
    expect(requests, isEmpty);
  });

  for (final channel in <String?>['group_id', null]) {
    test('supports wrapped response with $channel and null inviter', () async {
      await seed();
      respond = (request, handler) => handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: {'data': payload(channel: channel)},
          ));
      final record = await load();
      expect(requests, hasLength(1));
      expect(record!.invitedByUserId, isEmpty);
      expect(record.invitedByNickname, isEmpty);
      expect(record.joinChannel, channel ?? '');
      expect(record.joinedAt, 1700000000000);
    });
  }

  for (final status in [403, 404, 500]) {
    test('HTTP $status preserves cached join time without list fallback',
        () async {
      await seed();
      respond = (request, handler) => handler.reject(DioError(
            requestOptions: request,
            type: DioErrorType.response,
            response: Response(
              requestOptions: request,
              statusCode: status,
              data: {'code': 'NOT_GROUP_MEMBER'},
            ),
          ));
      final record = await load();
      expect(requests, hasLength(1));
      expect(record!.invitedByUserId, isEmpty);
      expect(record.joinedAt, 1700000000000);
    });
  }

  test('discard response after session boundary', () async {
    await seed();
    final entered = Completer<void>();
    late RequestOptions pending;
    late RequestInterceptorHandler reply;
    respond = (request, handler) {
      pending = request;
      reply = handler;
      entered.complete();
    };
    final result = load();
    await entered.future;
    SessionIdentityService.instance.invalidate();
    reply.resolve(
        Response(requestOptions: pending, statusCode: 200, data: payload()));
    expect(await result, isNull);
    final saved = await store.readRecord(
        groupId: groupId, userId: userId, ownerUserId: owner);
    expect(saved!.invitedByUserId, isEmpty);
  });
}
