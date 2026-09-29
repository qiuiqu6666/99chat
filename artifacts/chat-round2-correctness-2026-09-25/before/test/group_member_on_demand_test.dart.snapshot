import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_filter_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_role_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

GroupMemberRecord member(int n, {int role = 200, String? name}) =>
    GroupMemberRecord(
      userId: 'user${n.toString().padLeft(4, '0')}',
      nickname: name ?? 'Member $n',
      avatarUrl: '',
      friendRemark: '',
      nameCard: '',
      role: role,
      joinedAt: n * 1000,
      isSelf: false,
    );

V2TimGroupMemberFullInfo v2Member(GroupMemberRecord record) =>
    V2TimGroupMemberFullInfo(
      userID: record.userId,
      nickName: record.nickname,
      role: record.role,
    );

class PagingGroups implements GroupServices {
  PagingGroups(this.sync);
  final GroupMembershipSyncService sync;
  @override
  Future<V2TimValueCallback<V2TimGroupMemberInfoResult>> getGroupMemberList({
    required String groupID,
    required GroupMemberFilterTypeEnum filter,
    required String nextSeq,
    int count = 15,
    int offset = 0,
  }) =>
      sync.loadGroupMemberPage(
          groupID: groupID, filter: filter, count: count, nextSeq: nextSeq);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SdkMemberSource {
  SdkMemberSource(this.members);
  final List<GroupMemberRecord> members;
  final cursors = <String>[];
  var fail = false;
  Completer<void>? entered;
  Completer<void>? gate;

  Future<V2TimValueCallback<V2TimGroupMemberInfoResult>> load(
    String groupID,
    int count,
    String nextSeq,
    GroupMemberFilterTypeEnum filter,
  ) async {
    cursors.add(nextSeq);
    final enter = entered;
    if (enter != null && !enter.isCompleted) {
      enter.complete();
    }
    final pending = gate?.future;
    if (pending != null) await pending;
    if (fail) {
      return V2TimValueCallback(code: -1, desc: 'offline');
    }
    var rows = members;
    if (filter == GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_OWNER) {
      rows = members.where((item) => item.role == 400).toList();
    } else if (filter ==
        GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ADMIN) {
      rows = members.where((item) => item.role == 300).toList();
    }
    final offset = int.tryParse(nextSeq) ?? 0;
    final page = rows.skip(offset).take(count).toList();
    final next = offset + page.length;
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: V2TimGroupMemberInfoResult(
        nextSeq: next < rows.length ? '$next' : '0',
        memberInfoList: page.map(v2Member).toList(),
      ),
    );
  }
}

class MuteResultGroups implements GroupServices {
  int code = 1;
  bool throwRequest = false;
  int requests = 0;
  Completer<void>? entered;
  Completer<void>? gate;
  @override
  Future<V2TimCallback> muteGroupMember({required String groupID,
      required String userID, required int seconds}) async {
    requests++;
    entered?.complete();
    if (gate != null) await gate!.future;
    if (throwRequest) throw StateError('offline');
    return V2TimCallback(code: code, desc: code == 0 ? 'ok' : 'denied');
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RoleChangingGroups implements GroupServices {
  RoleChangingGroups(this.save);
  final void Function(bool grant) save;
  @override
  Future<V2TimCallback> setGroupMemberRoles({required String groupID,
      required List<String> userIDList, required GroupMemberRoleTypeEnum role}) async {
    save(true);
    return V2TimCallback(code: 0, desc: 'ok');
  }
  @override
  Future<V2TimCallback> setGroupMemberRole({required String groupID,
      required String userID, required GroupMemberRoleTypeEnum role}) async {
    save(false);
    return V2TimCallback(code: 0, desc: 'ok');
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class KickGroups implements GroupServices {
  KickGroups(this.inner, {this.kickDesc = 'ok'});
  final GroupServices inner;
  String kickDesc;
  @override
  Future<V2TimCallback> kickGroupMember({
    required String groupID,
    required List<String> memberList,
    String? reason,
  }) async {
    return V2TimCallback(code: 0, desc: kickDesc);
  }

  @override
  Future<V2TimValueCallback<V2TimGroupMemberInfoResult>> getGroupMemberList({
    required String groupID,
    required GroupMemberFilterTypeEnum filter,
    required String nextSeq,
    int count = 15,
    int offset = 0,
  }) =>
      inner.getGroupMemberList(
        groupID: groupID,
        filter: filter,
        nextSeq: nextSeq,
        count: count,
        offset: offset,
      );

  @override
  Future<List<V2TimGroupInfoResult>?> getGroupsInfo({
    required List<String> groupIDList,
  }) async {
    return <V2TimGroupInfoResult>[
      V2TimGroupInfoResult(resultCode: -1, resultMessage: 'empty'),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = GroupMemberLocalStore.instance;
  final requests = <RequestOptions>[];
  var account = 0;
  late String owner;
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  late GroupMembershipSyncService sync;
  const group = '@TGS#ondemand';

  Future<void> bindSync(GroupMembershipSyncService next) async {
    sync = next;
    await serviceLocator.unregister<GroupServices>();
    serviceLocator.registerSingleton<GroupServices>(PagingGroups(sync));
  }

  Future<SdkMemberSource> useSdkMembers(List<GroupMemberRecord> members) async {
    final source = SdkMemberSource(members);
    await bindSync(
        GroupMembershipSyncService.forTest(memberPageLoader: source.load));
    return source;
  }

  void pageResponse(RequestOptions request, RequestInterceptorHandler handler,
      {int total = 203, int? returned, bool? hasMore}) {
    final offset = request.queryParameters['offset'] as int? ?? 0;
    final limit = request.queryParameters['limit'] as int? ?? 10;
    final size = returned ?? (total - offset).clamp(0, limit);
    handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
      'data': {
        'items': List.generate(
            size,
            (i) => {
                  'userId': member(offset + i).userId,
                  'nickname': 'Member ${offset + i}',
                  'role': 200,
                  'joinedAt': (offset + i) * 1000,
                }),
        'total': total,
        if (hasMore != null) 'hasMore': hasMore
      }
    }));
  }

  Map<String, dynamic> memberJson(GroupMemberRecord record) => {
        'userId': record.userId,
        'nickname': record.nickname,
        'role': record.role,
        'joinedAt': record.joinedAt,
      };

  List<GroupMemberRecord> scopedMembers(
    RequestOptions request,
    List<GroupMemberRecord> members,
  ) {
    final role = request.queryParameters['role']?.toString();
    if (role == 'admins') {
      return members.where((item) => item.role >= 300).toList();
    }
    if (role == 'members') {
      return members.where((item) => item.role < 300).toList();
    }
    return members;
  }

  void rolePageResponse(
    RequestOptions request,
    RequestInterceptorHandler handler,
    List<GroupMemberRecord> members,
  ) {
    final offset = request.queryParameters['offset'] as int? ?? 0;
    final limit = request.queryParameters['limit'] as int? ?? 10;
    final scoped = scopedMembers(request, members);
    final page = scoped.skip(offset).take(limit).toList();
    handler.resolve(Response(
      requestOptions: request,
      statusCode: 200,
      data: {
        'data': {
          'items': page.map(memberJson).toList(),
          'total': scoped.length,
          'hasMore': offset + page.length < scoped.length,
        }
      },
    ));
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (r, h) {
      requests.add(r);
      respond(r, h);
    }));
  });
  setUp(() async {
    requests.clear();
    GroupMemberStore.instance.clear(notify: false);
    SessionIdentityService.instance.invalidate();
    owner = 'ondemand${account++}';
    await ApiClient.instance.saveToken('test-token', userId: owner);
    await bindSync(GroupMembershipSyncService.forTest());
    respond = (r, h) => pageResponse(r, h);
  });
  tearDown(() async => store.clearForOwner(owner));

  for (final entering in [true, false]) {
    test('membership ${entering ? 'enter' : 'leave'} invalidates recent page', () async {
      final members = List.generate(80, (i) => member(i));
      final source = await useSdkMembers(members);
      respond = (r, h) => rolePageResponse(r, h, members);
      final model = TUIGroupProfileModel()..groupID = group;
      addTearDown(model.dispose);
      await model.loadRemainingMemberPages();
      final change = entering
          ? model.processGroupMemberListEnter
          : model.processGroupMemberListLeave;
      final event = V2TimGroupMemberInfo(userID: member(0).userId);
      final before = source.cursors.length;
      final restBefore = requests.length;
      await change(groupID: '@TGS#unrelated', memberList: [event]);
      await change(groupID: group, memberList: []);
      await model.loadRemainingMemberPages();
      expect(source.cursors.length, before);
      expect(requests.length, restBefore);
      if (!entering) members.removeAt(0);
      await change(groupID: group, memberList: [event]);
      if (!entering) {
        expect(model.groupMemberList.any((m) => m?.userID == event.userID), isFalse);
      }
      // The event itself must not start a member scan on the profile page.
      expect(source.cursors.length, before);
      expect(requests.length, restBefore);
      await model.loadRemainingMemberPages();
      expect(source.cursors.length, before + 1);
      expect(requests.length, greaterThan(restBefore));
      final restAfter = requests.length;
      await model.loadRemainingMemberPages();
      expect(source.cursors.length, before + 1);
      expect(requests.length, restAfter);
    });

    test('membership event during loading cannot confirm stale cache $entering', () async {
      final members = List.generate(80, (i) => member(i));
      final source = await useSdkMembers(members);
      source.entered = Completer<void>();
      source.gate = Completer<void>();
      respond = (r, h) => rolePageResponse(r, h, members);
      final model = TUIGroupProfileModel()..groupID = group;
      addTearDown(model.dispose);
      final loading = model.loadRemainingMemberPages();
      await source.entered!.future;
      final change = entering
          ? model.processGroupMemberListEnter
          : model.processGroupMemberListLeave;
      await change(groupID: group,
          memberList: [V2TimGroupMemberInfo(userID: member(0).userId)]);
      source.gate!.complete();
      await loading;
      final before = source.cursors.length;
      await model.loadRemainingMemberPages();
      expect(source.cursors.length, before + 1);
      await model.loadRemainingMemberPages();
      expect(source.cursors.length, before + 1);
    });
  }

  test('member reentry reuses successful pages and retains pagination', () async {
    final members = List.generate(180, (i) => member(i));
    final source = await useSdkMembers(members);
    respond = (r, h) => rolePageResponse(r, h, members);
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    await model.loadRemainingMemberPages();
    await model.loadMoreGroupMembers();
    final ids = model.groupMemberList.map((m) => m?.userID).toList();
    final restCount = requests.length;
    final pageCount = source.cursors.length;
    await model.loadRemainingMemberPages();
    await model.loadRemainingMemberPages();
    expect(requests.length, restCount);
    expect(source.cursors.length, pageCount);
    expect(model.groupMemberList.map((m) => m?.userID).toList(), ids);
    await model.loadMoreGroupMembers();
    expect(source.cursors.last, '100');
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance.saveToken('new-session', userId: owner);
    await model.loadRemainingMemberPages();
    expect(requests.length, greaterThan(restCount));
    final afterSession = requests.length;
    model.groupID = '@TGS#another';
    await model.loadRemainingMemberPages();
    expect(requests.length, greaterThan(afterSession));
  });

  test('member reentry joins requests until network completion', () async {
    final members = List.generate(80, (i) => member(i));
    final source = await useSdkMembers(members);
    source.entered = Completer<void>();
    source.gate = Completer<void>();
    respond = (r, h) => rolePageResponse(r, h, members);
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    final first = model.loadRemainingMemberPages();
    await source.entered!.future;
    var finished = false;
    final second = model.loadRemainingMemberPages().then((_) => finished = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(finished, isFalse);
    expect(source.cursors, ['0']);
    source.gate!.complete();
    await Future.wait([first, second]);
    final restCount = requests.length;
    await model.loadRemainingMemberPages();
    expect(requests.length, restCount);
    expect(source.cursors, ['0']);
  });

  test('failed member page remains retryable on reentry', () async {
    final members = List.generate(80, (i) => member(i));
    final source = await useSdkMembers(members)..fail = true;
    respond = (r, h) => rolePageResponse(r, h, members);
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    await model.loadRemainingMemberPages();
    final failedAttempts = source.cursors.length;
    source.fail = false;
    await model.loadRemainingMemberPages();
    expect(source.cursors.length, failedAttempts + 1);
    expect(model.groupMemberList, isNotEmpty);
  });

  test('mute preserves backend errors and updates local state only after success', () async {
    final services = MuteResultGroups();
    await serviceLocator.unregister<GroupServices>();
    serviceLocator.registerSingleton<GroupServices>(services);
    respond = (r, h) => h.resolve(Response(requestOptions: r, statusCode: 200,
        data: {'data': {'items': [
          {'userId': owner, 'role': 400},
          {'userId': member(1).userId, 'role': 200},
        ], 'total': 2}}));
    final target = v2Member(member(1))..muteUntil = 0;
    final model = TUIGroupProfileModel()..groupID = group
      ..groupInfo = V2TimGroupInfo(groupID: group, groupType: 'Public', role: 200)
      ..groupMemberList = [target];
    addTearDown(model.dispose);
    // Unloaded permissions must not use the SDK role to authorize a write.
    expect((await model.muteGroupMember(target.userID, true, 1000)).code, isNot(0));
    expect(services.requests, 0);
    await model.loadManagementMembers();
    final rejected = await model.muteGroupMember(target.userID, true, 1000);
    expect(rejected.code, 1);
    expect(rejected.desc, 'denied');
    expect(target.muteUntil, 0);
    services.throwRequest = true;
    expect((await model.muteGroupMember(target.userID, true, 1000)).code, isNot(0));
    expect(target.muteUntil, 0);
    services.throwRequest = false;
    services.code = 0;
    expect((await model.muteGroupMember(target.userID, true, 1000)).code, 0);
    expect(target.muteUntil, 315361000);
    services.code = 1;
    expect((await model.muteGroupMember(target.userID, false, 1000)).code, 1);
    expect(target.muteUntil, 315361000);
    services.code = 0;
    expect((await model.muteGroupMember(target.userID, false, 1000)).code, 0);
    expect(target.muteUntil, 0);
    services.entered = Completer<void>();
    services.gate = Completer<void>();
    final pending = model.muteGroupMember(target.userID, true, 1000);
    await services.entered!.future;
    SessionIdentityService.instance.invalidate();
    services.gate!.complete();
    expect((await pending).code, isNot(0));
    expect(target.muteUntil, 0);
  });

  test(
      'local preview and search read bounded sorted windows from a large cache',
      () async {
    await store.replaceSnapshot(
        ownerUserId: owner,
        groupId: group,
        records: List.generate(1200, (i) => member(i)));
    final preview = await store.loadAsV2TimMembers(groupId: group, limit: 10);
    final next =
        await store.loadAsV2TimMembers(groupId: group, limit: 10, offset: 10);
    expect(preview.map((m) => m.userID),
        List.generate(10, (i) => member(i).userId));
    expect(next.first.userID, member(10).userId);
    final search = await store.loadAsV2TimMembers(
        groupId: group, keyword: 'Member 1199', limit: 50);
    expect(search.single.userID, member(1199).userId);
    expect(
        await store.loadAsV2TimMembers(groupId: group, keyword: '%', limit: 10),
        isEmpty);
    expect(await store.loadAsV2TimMembers(groupId: group, limit: 0), isEmpty);
    expect(requests, isEmpty);
    expect(await store.countMembers(groupId: group), 1200);
  });

  test(
      'SDK first page upserts without deleting later local pages or skipping ids',
      () async {
    await store.replaceSnapshot(
        ownerUserId: owner,
        groupId: group,
        records: List.generate(203, (i) => member(i)));
    final source = await useSdkMembers(List.generate(203, (i) => member(i)));
    final first =
        await sync.loadGroupMemberPage(groupID: group, count: 10, nextSeq: '0');
    expect(first.data!.memberInfoList, hasLength(10));
    expect(first.data!.memberInfoList!.first!.userID, member(0).userId);
    expect(first.data!.nextSeq, 'sdk:10');
    final second = await sync.loadGroupMemberPage(
        groupID: group, count: 40, nextSeq: first.data!.nextSeq!);
    expect(second.data!.memberInfoList, hasLength(40));
    expect(second.data!.memberInfoList!.first!.userID, member(10).userId);
    expect(second.data!.nextSeq, 'sdk:50');
    expect(source.cursors, ['0', '10']);
    expect(await store.readAll(groupId: group), hasLength(203));
    expect(requests, isEmpty);
  });

  test('SDK short page with a non-zero cursor continues without marking complete',
      () async {
    final source = await useSdkMembers(List.generate(13, (i) => member(i)));
    final result =
        await sync.loadGroupMemberPage(groupID: group, count: 10, nextSeq: '0');
    expect(result.data!.nextSeq, 'sdk:10');
    expect(result.data!.memberInfoList, hasLength(10));
    expect(source.cursors, ['0']);
    expect(await store.hasCompleteSnapshot(ownerUserId: owner, groupId: group),
        isFalse);
  });

  test('filtered one-page response cannot delete cached nonmatching members',
      () async {
    await store
        .upsertMany(ownerUserId: owner, groupId: group, records: [member(999)]);
    var sdkHits = 0;
    await bindSync(GroupMembershipSyncService.forTest(
        memberPageLoader: (g, c, seq, f) async {
      sdkHits++;
      return V2TimValueCallback(
          code: 0,
          desc: 'ok',
          data: V2TimGroupMemberInfoResult(
              nextSeq: '0',
              memberInfoList: [v2Member(member(1, role: 300))]));
    }));
    respond = (r, h) => rolePageResponse(r, h, [member(1, role: 300)]);
    await sync.loadGroupMemberPage(
        groupID: group,
        count: 10,
        nextSeq: '0',
        filter: GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ADMIN);
    expect(await store.readRecord(groupId: group, userId: member(999).userId),
        isNotNull);
    expect(await store.hasCompleteSnapshot(ownerUserId: owner, groupId: group),
        isFalse);
    expect(sdkHits, 0);
    expect(requests, isNotEmpty);
    expect(requests.first.queryParameters['role'], 'admins');
  });

  test(
      'SDK small numeric cursor stays with SDK; failed continuation never switches source',
      () async {
    final cursors = <String>[];
    var fail = false;
    await bindSync(GroupMembershipSyncService.forTest(
        memberPageLoader: (g, c, seq, f) async {
      cursors.add(seq);
      return V2TimValueCallback(
          code: fail ? -1 : 0,
          desc: 'test',
          data: V2TimGroupMemberInfoResult(
              nextSeq: seq == '0' ? '7' : '8',
              memberInfoList: [V2TimGroupMemberFullInfo(userID: 'sdk-user')]));
    }));
    final first =
        await sync.loadGroupMemberPage(groupID: group, count: 10, nextSeq: '0');
    expect(first.data!.nextSeq, 'sdk:7');
    final restCount = requests.length;
    final second = await sync.loadGroupMemberPage(
        groupID: group, count: 10, nextSeq: first.data!.nextSeq!);
    expect(second.data!.nextSeq, 'sdk:8');
    expect(cursors.take(2), ['0', '7']);
    fail = true;
    expect(
        (await sync.loadGroupMemberPage(
                groupID: group, count: 10, nextSeq: 'sdk:8'))
            .code,
        isNot(0));
    expect(requests, hasLength(restCount));
  });

  test('legacy rest cursor remaps to the SDK first page and never calls HTTP',
      () async {
    final source = await useSdkMembers(List.generate(30, (i) => member(i)));
    final result = await sync.loadGroupMemberPage(
        groupID: group, count: 10, nextSeq: 'rest:10');
    expect(source.cursors, ['0']);
    expect(result.data!.nextSeq, 'sdk:10');
    expect(result.data!.memberInfoList, hasLength(10));
    expect(requests, isEmpty);
  });

  test(
      'specific sender lookup shares a request and never downloads member page zero',
      () async {
    final entered = Completer<void>();
    final gate = Completer<void>();
    final batches = <List<String>>[];
    await bindSync(GroupMembershipSyncService.forTest(memberInfoLoader: (g, ids) async {
      batches.add(ids);
      entered.complete();
      await gate.future;
      return V2TimValueCallback(
          code: 0,
          desc: 'test',
          data: ids
              .map((id) =>
                  V2TimGroupMemberFullInfo(userID: id, nickName: 'Sender'))
              .toList());
    }));
    final one =
        sync.loadGroupMembersInfo(groupID: group, memberList: ['sender999']);
    final two =
        sync.loadGroupMembersInfo(groupID: group, memberList: ['sender999']);
    await entered.future;
    expect(batches, [
      ['sender999']
    ]);
    gate.complete();
    expect((await one).data!.single.nickName, 'Sender');
    await two;
    await sync.loadGroupMembersInfo(groupID: group, memberList: ['sender999']);
    expect(batches, hasLength(1));
    expect(requests, isEmpty);
  });

  test(
      'late sender lookup cannot overwrite a business member arriving meanwhile',
      () async {
    final entered = Completer<void>();
    final gate = Completer<void>();
    await bindSync(GroupMembershipSyncService.forTest(memberInfoLoader: (g, ids) async {
      entered.complete();
      await gate.future;
      return V2TimValueCallback(code: 0, desc: 'test', data: [
        V2TimGroupMemberFullInfo(userID: member(9).userId, role: 200)
      ]);
    }));
    final result = sync
        .loadGroupMembersInfo(groupID: group, memberList: [member(9).userId]);
    await entered.future;
    await store.upsertMany(
        ownerUserId: owner, groupId: group, records: [member(9, role: 300)]);
    gate.complete();
    expect((await result).data!.single.role, 300);
    expect(
        (await store.readRecord(groupId: group, userId: member(9).userId))!
            .role,
        300);
  });

  test('same-account session reset rejects late member page writes', () async {
    final source = await useSdkMembers(List.generate(20, (i) => member(i)));
    source.entered = Completer<void>();
    source.gate = Completer<void>();
    final result =
        sync.loadGroupMemberPage(groupID: group, count: 10, nextSeq: '0');
    await source.entered!.future;
    SessionIdentityService.instance.invalidate();
    source.gate!.complete();
    expect((await result).code, isNot(0));
    expect(await store.readAll(groupId: group), isEmpty);
  });

  test(
      'profile loads ten, member-page entry expands to fifty, scrolling loads one more page',
      () async {
    await store.replaceSnapshot(
        ownerUserId: owner,
        groupId: group,
        records: List.generate(203, (i) => member(i)));
    await useSdkMembers(List.generate(203, (i) => member(i)));
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    await model.loadGroupMemberList(
        groupID: group, count: TUIGroupProfileModel.memberPreviewSize);
    expect(model.groupMemberList, hasLength(10));
    expect(model.hasCompleteMemberSnapshot, isFalse);
    expect(requests, isEmpty);
    await model.ensureMemberListPage();
    expect(model.groupMemberList, hasLength(50));
    await model.loadMoreGroupMembers();
    expect(model.groupMemberList, hasLength(100));
    expect(model.groupMemberList.map((m) => m?.userID).toSet(), hasLength(100));
    await store.upsertMany(
        ownerUserId: owner, groupId: group, records: [member(1000)]);
    expect(model.groupMemberList, hasLength(100));
  });

  test('failed next page retains loaded rows and retries the same cursor',
      () async {
    final source = await useSdkMembers(List.generate(120, (i) => member(i)));
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    await model.loadGroupMemberList(groupID: group, count: 50);
    expect(model.groupMemberList, hasLength(50));
    final cursor = model.hasMoreGroupMembers;
    expect(cursor, isTrue);
    source.fail = true;
    await model.loadMoreGroupMembers();
    expect(model.groupMemberList, hasLength(50));
    expect(model.hasMoreGroupMembers, isTrue);
    source.fail = false;
    await model.loadMoreGroupMembers();
    expect(model.groupMemberList, hasLength(100));
    expect(source.cursors.where((seq) => seq == '50'), hasLength(2));
  });

  test('offline first-page fallback continues through bounded local pages',
      () async {
    await store.replaceSnapshot(
        ownerUserId: owner,
        groupId: group,
        records: List.generate(120, (i) => member(i)));
    await bindSync(GroupMembershipSyncService.forTest(
        memberPageLoader: (g, c, s, f) async =>
            V2TimValueCallback(code: -1, desc: 'offline')));
    final first =
        await sync.loadGroupMemberPage(groupID: group, count: 50, nextSeq: '0');
    expect(first.data!.memberInfoList, hasLength(50));
    expect(first.data!.nextSeq, 'local:50');
    final requestCount = requests.length;
    final second = await sync.loadGroupMemberPage(
        groupID: group, count: 50, nextSeq: 'local:50');
    expect(second.data!.memberInfoList!.first.userID, member(50).userId);
    final third = await sync.loadGroupMemberPage(
        groupID: group, count: 50, nextSeq: second.data!.nextSeq!);
    expect(third.data!.memberInfoList, hasLength(20));
    expect(third.data!.nextSeq, '0');
    expect(requests, hasLength(requestCount));
  });

  test(
      'cached sender shell fills display data without replacing business permissions',
      () async {
    await store.upsertMany(ownerUserId: owner, groupId: group, records: [
      member(88, name: '', role: 300).copyWith(muteUntil: 99999, nameCard: '')
    ]);
    await bindSync(GroupMembershipSyncService.forTest(
        memberInfoLoader: (g, ids) async =>
            V2TimValueCallback(code: 0, desc: 'ok', data: [
              V2TimGroupMemberFullInfo(
                  userID: member(88).userId,
                  nickName: 'Resolved sender',
                  role: 200,
                  faceUrl: 'https://example.com/avatar',
                  nameCard: 'Stale SDK card')
            ])));
    final result = await sync
        .loadGroupMembersInfo(groupID: group, memberList: [member(88).userId]);
    expect(result.data!.single.nickName, 'Resolved sender');
    final row =
        (await store.readRecord(groupId: group, userId: member(88).userId))!;
    expect(row.role, 300);
    expect(row.muteUntil, 99999);
    expect(row.nameCard, '');
    expect(requests, isEmpty);
  });

  test(
      'snapshot commit updates a preview without expanding it to the whole group',
      () async {
    await useSdkMembers(List.generate(10, (i) => member(i)));
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    await model.loadGroupMemberList(groupID: group, count: 10);
    final changed = Completer<void>();
    model.addListener(() {
      if (model.groupMemberList.first?.nickName == 'Updated' &&
          !changed.isCompleted) changed.complete();
    });
    await store.replaceSnapshot(ownerUserId: owner, groupId: group, records: [
      member(0, name: 'Updated'),
      ...List.generate(400, (i) => member(i + 1))
    ]);
    await changed.future.timeout(const Duration(seconds: 2));
    expect(model.groupMemberList, hasLength(10));
    expect(model.hasCompleteMemberSnapshot, isFalse);
    expect(requests, isEmpty);
  });

  test(
      'deleting a visible member updates the window without fetching all members',
      () async {
    await useSdkMembers(List.generate(10, (i) => member(i)));
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    await model.loadGroupMemberList(groupID: group, count: 10);
    await store.applyIncrementalEvent(
        ownerUserId: owner,
        groupId: group,
        memberSeq: 7,
        removeUserId: member(3).userId);
    expect(model.groupMemberList, hasLength(9));
    expect(model.groupMemberList.where((m) => m?.userID == member(3).userId),
        isEmpty);
    expect(requests, isEmpty);
  });

  test('model group switch rejects the previous page result', () async {
    final source = await useSdkMembers(List.generate(20, (i) => member(i)));
    source.entered = Completer<void>();
    source.gate = Completer<void>();
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    final pending = model.loadGroupMemberList(groupID: group, count: 10);
    await source.entered!.future;
    model.groupID = '@TGS#another';
    source.gate!.complete();
    await pending;
    expect(model.groupMemberList, isEmpty);
    expect(model.hasMoreGroupMembers, isFalse);
  });

  test('two member-page entries during preview share one expansion request',
      () async {
    final source = await useSdkMembers(List.generate(80, (i) => member(i)));
    source.entered = Completer<void>();
    source.gate = Completer<void>();
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    final preview = model.loadGroupMemberList(groupID: group, count: 10);
    await source.entered!.future;
    final first = model.ensureMemberListPage();
    final second = model.ensureMemberListPage();
    source.gate!.complete();
    await Future.wait([preview, first, second]);
    expect(source.cursors.where((seq) => seq == '0'), hasLength(1));
    expect(model.groupMemberList, hasLength(50));
  });

  test('late same-account sender response is discarded after session reset',
      () async {
    final entered = Completer<void>();
    final gate = Completer<void>();
    await bindSync(GroupMembershipSyncService.forTest(memberInfoLoader: (g, ids) async {
      entered.complete();
      await gate.future;
      return V2TimValueCallback(
          code: 0,
          desc: 'ok',
          data: [V2TimGroupMemberFullInfo(userID: 'late', nickName: 'Old')]);
    }));
    final request =
        sync.loadGroupMembersInfo(groupID: group, memberList: ['late']);
    await entered.future;
    SessionIdentityService.instance.invalidate();
    gate.complete();
    expect((await request).code, isNot(0));
    expect(await store.readRecord(groupId: group, userId: 'late'), isNull);
  });

  test('partial member window never becomes the displayed total', () async {
    await useSdkMembers(List.generate(10, (i) => member(i)));
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    model.groupInfo =
        V2TimGroupInfo(groupID: group, groupType: 'Public', memberCount: 203);
    await model.loadGroupMemberList(groupID: group, count: 10);
    expect(model.displayedMemberCount(), 203);
    expect(model.displayedMemberCount(cachedCount: 204), 203);
    expect(model.displayedMemberCount(cachedCount: 0), 203);
  });

  test(
      'management extracts first backend page without expanding the SDK member window',
      () async {
    final ownerRow = member(0, role: 400);
    final admins = List.generate(30, (i) => member(i + 1, role: 300));
    var sdkHits = 0;
    await bindSync(GroupMembershipSyncService.forTest(
        memberPageLoader: (g, c, seq, f) async {
      sdkHits++;
      return SdkMemberSource([
        ownerRow,
        ...admins,
        ...List.generate(40, (i) => member(i + 40)),
      ]).load(g, c, seq, f);
    }));
    respond = (r, h) {
      rolePageResponse(r, h, [ownerRow, ...admins,
        ...List.generate(80, (i) => member(i + 40))]);
    };
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    await model.loadGroupMemberList(groupID: group, count: 10);
    expect(model.managementMemberList, isEmpty);
    await model.loadManagementMembers();
    expect(
        model.managementMemberList.where((m) => m?.role == 300), hasLength(30));
    expect(model.groupMemberList, hasLength(10));
    expect(sdkHits, 1);
    expect(requests, hasLength(1));
    expect(requests.every((item) => item.queryParameters['limit'] == 50), isTrue);
    expect(requests.map((item) => item.queryParameters['role']).toSet(),
        {'admins'});
    await store.applyIncrementalEvent(
        ownerUserId: owner,
        groupId: group,
        memberSeq: 4,
        removeUserId: member(30).userId);
    expect(
        model.managementMemberList.where((m) => m?.role == 300), hasLength(29));
    admins.removeWhere((m) => m.userId == member(30).userId);
    await model.loadManagementMembers();
    expect(
        model.managementMemberList.where((m) => m?.role == 300), hasLength(29));
  });

  test('management pages collect admins that sit past the first admins page',
      () async {
    final ownerRow = member(0, role: 400);
    final admins = List.generate(60, (i) => member(i + 1, role: 300));
    respond = (r, h) => rolePageResponse(r, h, [ownerRow, ...admins]);
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    await model.loadManagementMembers();
    expect(
        model.managementMemberList.where((m) => m?.role == 400), hasLength(1));
    expect(
        model.managementMemberList.where((m) => m?.role == 300), hasLength(60));
  });

  test('opening members paints the local window before a silent network refresh',
      () async {
    await store.replaceSnapshot(
      ownerUserId: owner,
      groupId: group,
      records: [
        member(0, role: 400),
        ...List.generate(3, (i) => member(i + 1, role: 300)),
        ...List.generate(80, (i) => member(i + 10)),
      ],
    );
    await useSdkMembers(List.generate(50, (i) => member(i)));
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    await model.seedLocalMemberAndManagementPreview();
    expect(model.groupMemberList, hasLength(84));
    expect(model.hasLocalManagementPreview, isTrue);
    expect(
        model.localManagementPreview.where((m) => m.role == 400), hasLength(1));
    expect(
        model.localManagementPreview.where((m) => m.role == 300), hasLength(3));
    expect(model.hasLoadedManagementMembers, isFalse);
  });

  test('management waits for first page, ignores hasMore and SDK snapshots',
      () async {
    final admins = List.generate(30, (i) => member(i + 1, role: 300));
    final pendingPage = Completer<void>();
    late RequestOptions pendingRequest;
    late RequestInterceptorHandler pendingHandler;
    var holdFirst = true;
    final allMembers = [member(0, role: 400), ...admins, ...List.generate(100, (i) => member(i + 40))];
    respond = (r, h) {
      if (holdFirst) {
        pendingRequest = r;
        pendingHandler = h;
        pendingPage.complete();
        holdFirst = false;
        return;
      }
      rolePageResponse(r, h, allMembers);
    };
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    model.groupMemberList = [v2Member(member(999, role: 300))];
    final publishedSizes = <int>[];
    model.addListener(() => publishedSizes.add(model.managementMemberList.length));
    final loading = model.loadManagementMembers();
    await pendingPage.future;
    expect(model.managementMemberList, isEmpty);
    expect(model.hasLoadedManagementMembers, isFalse);
    expect(model.isManagementMemberListLoading, isTrue);
    rolePageResponse(pendingRequest, pendingHandler, allMembers);
    await loading;
    expect(requests, hasLength(1));
    expect(model.managementMemberList, hasLength(31));
    expect(publishedSizes.toSet(), {0, 31});
    expect(model.managementMemberList.any((m) => m?.userID == member(999).userId),
        isFalse);
    await store.replaceSnapshot(ownerUserId: owner, groupId: group,
        records: [member(999, role: 300), member(1, role: 200)]);
    expect(model.managementMemberList, hasLength(31));
    expect(model.managementMemberList.firstWhere((m) =>
        m?.userID == member(1).userId)?.role, 300);
    await store.clearForOwner(owner);
    expect(model.managementMemberList, hasLength(31));
  });

  test('management failures never fall back and refresh retains backend snapshot',
      () async {
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    model.groupMemberList = [v2Member(member(999, role: 300))];
    void reject(RequestOptions r, RequestInterceptorHandler h) => h.reject(
        DioError(requestOptions: r, error: 'offline'));
    respond = reject;
    await model.loadManagementMembers();
    expect(model.managementMemberList, isEmpty);
    expect(model.hasLoadedManagementMembers, isFalse);
    expect(model.hasManagementMemberListError, isTrue);
    expect(model.isManagementMemberListLoading, isFalse);
    final admins = [member(2, role: 300), member(1, role: 300)];
    respond = (r, h) => rolePageResponse(r, h,
        [member(0, role: 400), ...admins, member(9)]);
    await model.loadManagementMembers();
    final ids = model.managementMemberList.map((m) => m!.userID).toList();
    expect(ids, [member(0).userId, member(1).userId, member(2).userId]);
    expect(model.hasManagementMemberListError, isFalse);
    admins.sort((a, b) => a.userId.compareTo(b.userId));
    await model.loadManagementMembers();
    expect(model.managementMemberList.map((m) => m!.userID), ids);
    // A failed refresh keeps both owner and admin roles from the last response.
    respond = reject;
    await model.loadManagementMembers();
    expect(model.managementMemberList.map((m) => m!.userID), ids);
    expect(model.hasManagementMemberListError, isTrue);
    expect(model.hasLoadedManagementMembers, isTrue);
  });

  test('member display includes all 19 backend admins when SDK has only 10',
      () async {
    var admins = List.generate(19, (i) => member(i + 1, role: 300));
    respond = (r, h) => rolePageResponse(r, h,
        [member(0, role: 400), ...admins, ...List.generate(80, (i) => member(100 + i))]);
    final sdkRows = [
      v2Member(member(0, role: 400)),
      ...List.generate(10, (i) => v2Member(member(i + 1, role: 300))),
      ...List.generate(39, (i) => v2Member(member(100 + i))),
    ];
    sdkRows.last.role = 300; // A stale SDK-only administrator must lose its badge.
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    model.groupInfo = V2TimGroupInfo(groupID: group, groupType: 'Public', memberCount: 120);
    model.groupMemberList = sdkRows;
    expect(model.hasLoadedManagementMembers, isFalse);
    await model.loadManagementMembers();
    final display = model.membersWithBackendRoles(model.groupMemberList);
    expect(display.where((m) => m?.role == 300), hasLength(19));
    expect(display.where((m) => m?.role == 400), hasLength(1));
    expect(display, hasLength(59));
    expect(display.take(20).map((m) => m?.userID),
        List.generate(20, (i) => member(i).userId));
    expect(display.firstWhere((m) => m?.userID == sdkRows.last.userID)?.role, 200);
    expect(sdkRows.last.role, 300, reason: 'Display corrections must not mutate SDK data');
    expect(model.groupMemberList, hasLength(50));
    expect(model.displayedMemberCount(), 120);

    // A later SDK page may contain the nine admins already supplied by REST.
    final nextWindow = [...sdkRows,
      ...List.generate(9, (i) => v2Member(member(i + 11))), v2Member(member(200))];
    final nextDisplay = model.membersWithBackendRoles(nextWindow);
    expect(nextDisplay.where((m) => m?.role == 300), hasLength(19));
    expect(nextDisplay, hasLength(60));
    expect(nextDisplay.map((m) => m?.userID).toSet(), hasLength(60));
    expect(model.membersWithBackendRoles([v2Member(member(19))])
        .firstWhere((m) => m?.userID == member(19).userId)?.role, 300,
        reason: 'Local search rows use the same backend role authority');
    admins = admins.where((m) => m.userId != member(19).userId).toList();
    await model.loadManagementMembers();
    final refreshed = model.membersWithBackendRoles(nextWindow);
    expect(refreshed.where((m) => m?.role == 300), hasLength(18));
    expect(refreshed.firstWhere((m) => m?.userID == member(19).userId)?.role, 200);
  });

  test('profilePreviewMembers pads ordinary members from a members page',
      () async {
    respond = (r, h) => rolePageResponse(r, h, [
          member(0, role: 400),
          member(1, role: 300),
          member(9),
          member(10),
        ]);
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    model.groupMemberList = [
      v2Member(member(0, role: 400)),
      v2Member(member(1, role: 300)),
      v2Member(member(9)),
      v2Member(member(99)),
    ];
    await model.loadManagementMembers();
    expect(model.groupMemberList.any((m) => m?.userID == member(99).userId),
        isTrue);
    final preview = model.profilePreviewMembers;
    expect(
      preview.map((m) => m.userID).toList(),
      [
        member(0).userId,
        member(1).userId,
        member(9).userId,
        member(10).userId,
      ],
    );
    expect(preview.any((m) => m.userID == member(99).userId), isFalse);
    expect(
      requests.where((item) => item.queryParameters['role'] == 'members'),
      hasLength(1),
    );
  });

  test('profilePreviewMembers does not pad when managers fill the cap', () async {
    final managers = [
      member(0, role: 400),
      ...List.generate(12, (i) => member(i + 1, role: 300)),
    ];
    respond = (r, h) => rolePageResponse(r, h, [...managers, member(50)]);
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    await model.loadManagementMembers();
    final preview = model.profilePreviewMembers;
    expect(preview, hasLength(TUIGroupProfileModel.memberPreviewSize));
    expect(
      preview.every((m) => m.role == 400 || m.role == 300),
      isTrue,
    );
    expect(preview.any((m) => m.userID == member(50).userId), isFalse);
    expect(
      requests.where((item) => item.queryParameters['role'] == 'members'),
      isEmpty,
    );
  });

  test('profilePreviewMembers caps padded ordinary members at ten', () async {
    respond = (r, h) => rolePageResponse(r, h, [
          member(0, role: 400),
          member(1, role: 300),
          ...List.generate(20, (i) => member(i + 10)),
        ]);
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    await model.loadManagementMembers();
    final preview = model.profilePreviewMembers;
    expect(preview, hasLength(TUIGroupProfileModel.memberPreviewSize));
    expect(preview.take(2).map((m) => m.userID).toList(),
        [member(0).userId, member(1).userId]);
    expect(
      preview.skip(2).every((m) => m.role == 200),
      isTrue,
    );
  });

  test('profilePreviewMembers waits to paint managers until the pad page lands',
      () async {
    final held = Completer<void>();
    final membersEntered = Completer<void>();
    respond = (r, h) async {
      if (r.queryParameters['role'] == 'members') {
        if (!membersEntered.isCompleted) membersEntered.complete();
        await held.future;
      }
      rolePageResponse(r, h, [
        member(0, role: 400),
        member(1, role: 300),
        member(9),
      ]);
    };
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    final loading = model.loadManagementMembers();
    await membersEntered.future;
    expect(model.hasLoadedManagementMembers, isTrue);
    expect(model.profilePreviewMembers, isEmpty);
    expect(model.isProfilePreviewPending, isTrue);
    held.complete();
    await loading;
    expect(
      model.profilePreviewMembers.map((m) => m.userID).toList(),
      [member(0).userId, member(1).userId, member(9).userId],
    );
    expect(model.isProfilePreviewPending, isFalse);
  });

  test('late management response cannot replace a newer request or another group',
      () async {
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    Future<void> verifyLateResponse({required bool switchGroup}) async {
      final entered = Completer<void>();
      late RequestOptions pendingRequest;
      late RequestInterceptorHandler pendingHandler;
      respond = (r, h) {
        pendingRequest = r;
        pendingHandler = h;
        entered.complete();
      };
      final old = model.loadManagementMembers();
      await entered.future;
      if (switchGroup) {
        model.groupID = 'other-group';
        expect(model.managementMemberList, isEmpty);
      }
      respond = (r, h) => rolePageResponse(r, h,
          [member(0, role: 400), member(2, role: 300)]);
      await model.loadManagementMembers();
      rolePageResponse(pendingRequest, pendingHandler, [member(99, role: 400)]);
      await old;
      expect(model.managementMemberList.map((m) => m!.userID),
          [member(0).userId, member(2).userId]);
      expect(model.isManagementMemberListLoading, isFalse);
      expect(model.hasManagementMemberListError, isFalse);
    }
    await verifyLateResponse(switchGroup: false);
    await verifyLateResponse(switchGroup: true);
  });

  test('profile permissions use backend identities despite opposite SDK roles', () async {
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    final sdkInfo = V2TimGroupInfo(groupID: group, groupType: 'Public', role: 200);
    model.groupInfo = sdkInfo;
    final self = member(99).copyWith(userId: owner, role: 300);
    var managers = [member(0, role: 400), self, member(2, role: 300)];
    respond = (r, h) => rolePageResponse(r, h, managers);
    model.groupMemberList = [v2Member(member(2)), v2Member(member(9, role: 300))];
    expect(model.backendSelfRole, isNull);
    expect(model.canKickOffMember(), isFalse);
    await model.loadManagementMembers();
    expect(model.backendSelfRole, 300);
    expect(model.groupInfoWithBackendRole?.role, 300);
    expect(sdkInfo.role, 200, reason: 'Permission projection must not mutate metadata');
    expect(model.canKickOffMember(), isTrue);
    expect(model.canKickMember(member(2).userId), isFalse);
    expect(model.canMuteMember(member(2).userId), isFalse);
    expect(model.canKickMember(member(9).userId), isTrue);
    expect(model.canMuteMember(member(9).userId), isTrue);
    expect(model.canKickMember(owner), isFalse);
    expect(model.canKickMember(''), isFalse);
    // Search results use these same ID-based checks, independent of their roles.
    expect(model.backendRoleForMember('c2c_${member(2).userId}'), 300);
    model.groupInfo = V2TimGroupInfo(groupID: group, groupType: 'Work', role: 400);
    expect(model.canKickOffMember(), isFalse);
    managers = [self.copyWith(role: 400), member(2, role: 300)];
    await model.loadManagementMembers();
    expect(model.canKickOffMember(), isTrue);
    expect(model.canKickMember(member(2).userId), isTrue);
    expect(model.canKickMember(owner), isFalse);
    expect(model.canMuteMember(member(9).userId), isFalse);
    expect(model.groupInfoWithBackendRole?.owner, owner);
  });

  test(
      'members-first paints kickable ordinary members; owner later sees admins, admin does not',
      () async {
    for (final selfRole in [400, 300]) {
      final heldAdmins = Completer<void>();
      final painted = Completer<void>();
      final rows = [
        member(0, role: 400),
        member(1, role: 300),
        member(2),
      ];
      respond = (r, h) async {
        if (!r.path.contains('/members')) {
          h.resolve(Response(
            requestOptions: r,
            statusCode: 200,
            data: {
              'data': {
                'groupId': group,
                'groupType': 'Public',
                'groupName': 'G',
                'avatarUrl': '',
                'notice': '',
                'memberCount': 3,
                'myRole': selfRole,
                'myNameCard': '',
                'ownerUserId': member(0).userId,
                'updatedAt': 1,
              }
            },
          ));
          return;
        }
        if (r.queryParameters['role'] == 'admins') {
          await heldAdmins.future;
        }
        rolePageResponse(r, h, rows);
      };
      final model = TUIGroupProfileModel()..groupID = group;
      addTearDown(model.dispose);
      await model.loadGroupInfo(group);
      model.addListener(() {
        if (model.groupMemberList.isNotEmpty && !painted.isCompleted) {
          painted.complete();
        }
      });
      final entry = model.loadMemberPageOnEntry();
      await painted.future.timeout(const Duration(seconds: 3));
      expect(model.hasLoadedManagementMembers, isFalse);
      expect(model.canKickMember(member(2).userId), isTrue);
      expect(model.canKickMember(member(1).userId), isFalse);
      expect(model.canKickMember(member(0).userId), isFalse);
      heldAdmins.complete();
      await entry;
      expect(model.hasLoadedManagementMembers, isTrue);
      expect(model.canKickMember(member(2).userId), isTrue);
      expect(model.canKickMember(member(1).userId), selfRole == 400);
      expect(model.canKickMember(member(0).userId), isFalse);
    }
  });

  test('permission failure retains backend snapshot, demotion and account switch revoke it', () async {
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    model.groupInfo = V2TimGroupInfo(groupID: group, groupType: 'Public', role: 400);
    void fail(RequestOptions r, RequestInterceptorHandler h) =>
        h.reject(DioError(requestOptions: r));
    respond = fail;
    await model.loadManagementMembers();
    expect(model.canKickOffMember(), isFalse);
    respond = (r, h) => rolePageResponse(r, h,
        [member(1).copyWith(userId: owner, role: 300)]);
    await model.loadManagementMembers();
    expect(model.canKickOffMember(), isTrue);
    respond = fail;
    await model.loadManagementMembers();
    expect(model.backendSelfRole, 300);
    expect(model.hasManagementMemberListError, isTrue);
    respond = (r, h) => rolePageResponse(r, h, []);
    await model.loadManagementMembers();
    expect(model.backendSelfRole, 200);
    expect(model.groupInfoWithBackendRole?.role, 200);
    expect(model.canKickOffMember(), isFalse);
    expect((await model.kickOffMember([member(9).userId])).code, isNot(0));
    respond = (r, h) => rolePageResponse(r, h,
        [member(1).copyWith(userId: owner, role: 300)]);
    await model.loadManagementMembers();
    SessionIdentityService.instance.invalidate();
    expect(model.backendSelfRole, isNull);
    expect(model.canKickOffMember(), isFalse);
    expect(model.managementMemberList, isEmpty);
  });

  test('stale local admin count cannot veto the backend role decision', () async {
    await store.replaceSnapshot(ownerUserId: owner, groupId: group,
        records: List.generate(30, (i) => member(i, role: 300)));
    respond = (r, h) => h.resolve(Response(requestOptions: r, statusCode: 200,
        data: {'data': {'code': 'NOT_GROUP_OWNER_OR_ADMIN'}}));
    final result = await sync.setGroupMemberRoles(groupID: group,
        userIDs: [member(99).userId], role: 300);
    expect(requests, hasLength(1));
    expect(requests.single.method, 'PUT');
    expect(requests.single.path, endsWith('/members/roles'));
    expect(result.desc, 'NOT_GROUP_OWNER_OR_ADMIN');
  });

  test('grant and revoke reload backend roles without projecting SDK candidates',
      () async {
    var admins = [member(1, role: 300)];
    var denyRead = false;
    await serviceLocator.unregister<GroupServices>();
    serviceLocator.registerSingleton<GroupServices>(RoleChangingGroups((grant) {
      admins = grant ? [member(2, role: 300, name: 'Backend name')] : [];
    }));
    respond = (r, h) {
      if (denyRead) {
        h.reject(DioError(requestOptions: r, error: 'offline'));
      } else {
        rolePageResponse(r, h,
            [member(0, role: 400), ...admins, member(9)]);
      }
    };
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    model.groupMemberList = [v2Member(member(2, name: 'SDK name'))];
    await model.loadManagementMembers();
    expect((await model.setMembersToAdmin([member(2).userId])).code, 0);
    expect(model.managementMemberList.where((m) => m?.role == 300).single?.nickName,
        'Backend name');
    // A successful write followed by a failed read must retain the confirmed
    // snapshot, not silently splice in the selected SDK member.
    denyRead = true;
    expect((await model.setMemberToNormal(member(2).userId)).code, 0);
    expect(model.managementMemberList.where((m) => m?.role == 300), hasLength(1));
    expect(model.hasManagementMemberListError, isTrue);
    denyRead = false;
    await model.loadManagementMembers();
    expect(model.managementMemberList.where((m) => m?.role == 300), isEmpty);
  });

  test('chat open uses current senders even with thousands of cached group members', () async {
    final memory = GroupMemberStore.instance;
    memory.clear(notify: false);
    memory.putMembers(group, List.generate(3000, (i) =>
        V2TimGroupMemberFullInfo(userID: member(i).userId, nickName: 'Member $i')));
    memory.putMember(
      group,
      V2TimGroupMemberFullInfo(
          userID: member(17).userId, nickName: 'Member 17'),
      notify: false,
    );
    final global = serviceLocator<TUIChatGlobalModel>();
    final message = V2TimMessage.fromJson({'message_risk_type_identified': 0,
      'message_msg_id': 'open-test', 'message_server_time': 10})
      ..sender = member(17).userId
      ..groupID = group
      ..elemType = 1;
    global.setMessageList(group, [message],
        replace: true, needResetNewMessageCount: false);
    final chat = TUIChatSeparateViewModel()..conversationID = group;
    addTearDown(() {
      chat.dispose();
      global.removeMessageList(group);
      memory.clear(notify: false);
    });
    await chat.loadGroupMembersForOpenShell(groupID: group);
    expect(chat.groupMemberList!.map((m) => m?.userID), [member(17).userId]);
    expect(chat.groupMemberListComplete, isFalse);
    expect(requests, isEmpty);
  });

  test('normal chat and member-page entry have no automatic full-member sync',
      () {
    final chat = File('lib/src/chat.dart').readAsStringSync();
    expect(chat, isNot(contains('.syncFullForGroup(')));
    expect(chat, isNot(contains('.ensureGroupMembersLoaded(')));
    expect(chat, isNot(contains('loadGroupMembersForOpenShell')));
    expect(chat, isNot(contains('syncForGroup(')));
    for (final path in [
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitGroupProfile/group_member/tui_group_member_list.dart',
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitGroupProfile/widgets/tim_uikit_group_member_title.dart',
    ]) {
      expect(File(path).readAsStringSync(),
          isNot(contains('.loadAllGroupMembers(')));
    }
  });

  int memberListGets() => requests
      .where((item) =>
          item.method == 'GET' && item.path.contains('/members'))
      .length;

  Future<TUIGroupProfileModel> kickReadyModel() async {
    final model = TUIGroupProfileModel()..groupID = group;
    model.groupInfo =
        V2TimGroupInfo(groupID: group, groupType: 'Public', role: 200);
    respond = (r, h) => rolePageResponse(r, h, [
          member(0, role: 400),
          member(99).copyWith(userId: owner, role: 300),
        ]);
    model.groupMemberList = [
      v2Member(member(2)),
      v2Member(member(9)),
    ];
    await model.loadManagementMembers();
    return model;
  }

  test('self-hosted kickOffMember drops the member without a members homepage GET',
      () async {
    final paging = PagingGroups(sync);
    await serviceLocator.unregister<GroupServices>();
    serviceLocator.registerSingleton<GroupServices>(KickGroups(paging));
    final model = await kickReadyModel();
    addTearDown(model.dispose);
    GroupMemberStore.instance.clear(notify: false);
    GroupMemberStore.instance.putMembers(group, model.groupMemberList);
    final getsBefore = memberListGets();
    expect((await model.kickOffMember([member(9).userId])).code, 0);
    expect(
      model.groupMemberList.any((m) => m?.userID == member(9).userId),
      isFalse,
    );
    expect(GroupMemberStore.instance.memberOf(group, member(9).userId), isNull);
    expect(memberListGets(), getsBefore);
  });

  test('kick tombstone keeps network first page from restoring the member',
      () async {
    final members = List.generate(80, (i) => member(i));
    final source = await useSdkMembers(members);
    await serviceLocator.unregister<GroupServices>();
    serviceLocator.registerSingleton<GroupServices>(
        KickGroups(PagingGroups(sync)));
    respond = (r, h) => rolePageResponse(r, h, [
          member(0, role: 400),
          member(99).copyWith(userId: owner, role: 300),
          ...members,
        ]);
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    model.groupInfo =
        V2TimGroupInfo(groupID: group, groupType: 'Public', role: 200);
    await model.loadRemainingMemberPages();
    expect(model.groupMemberList.any((m) => m?.userID == member(5).userId),
        isTrue);
    expect((await model.kickOffMember([member(5).userId])).code, 0);
    expect(
      model.groupMemberList.any((m) => m?.userID == member(5).userId),
      isFalse,
    );
    await model.loadRemainingMemberPages();
    expect(
      model.groupMemberList.any((m) => m?.userID == member(5).userId),
      isFalse,
    );
    expect(source.cursors, isNotEmpty);
  });

  test('partial kick leave only follows local deleted ids', () async {
    final paging = PagingGroups(sync);
    await serviceLocator.unregister<GroupServices>();
    serviceLocator.registerSingleton<GroupServices>(
        KickGroups(paging, kickDesc: 'PARTIAL_SUCCESS'));
    final model = await kickReadyModel();
    addTearDown(model.dispose);
    expect((await model.kickOffMember([member(2).userId, member(9).userId])).code,
        0);
    expect(model.groupMemberList.map((m) => m?.userID).toSet(),
        {member(2).userId, member(9).userId});
    await store.deleteUsers(
      ownerUserId: owner,
      groupId: group,
      userIds: [member(9).userId],
    );
    expect(
      model.groupMemberList.any((m) => m?.userID == member(9).userId),
      isFalse,
    );
    expect(
      model.groupMemberList.any((m) => m?.userID == member(2).userId),
      isTrue,
    );
  });

  test('member_removed correction does not GET the members homepage', () async {
    final getsBefore = memberListGets();
    await sync.applyTargetedMemberCorrection(
      groupId: group,
      action: 'member_removed',
      memberUserIds: [member(0).userId],
    );
    expect(memberListGets(), getsBefore);
  });

  test('applyMembersAddedLocally can restore a just-kicked friend shell',
      () async {
    GroupMemberStore.instance.clear(notify: false);
    GroupMemberStore.instance.removeMembers(group, [member(3).userId]);
    expect(GroupMemberStore.instance.memberOf(group, member(3).userId), isNull);
    await sync.applyMembersAddedLocally(
      groupId: group,
      addedUserIds: [member(3).userId],
    );
    expect(
        GroupMemberStore.instance.memberOf(group, member(3).userId), isNotNull);
    GroupMemberStore.instance.clear(notify: false);
  });
}
