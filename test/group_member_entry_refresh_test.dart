import 'dart:async';

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
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_search_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/group_member_cloud_search.dart';

import 'group_member_on_demand_test.dart'
    show member, v2Member, PagingGroups, SdkMemberSource;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const group = '@TGS#100123';
  final disk = GroupMemberLocalStore.instance;
  final memory = GroupMemberStore.instance;
  final requests = <RequestOptions>[];
  late List<GroupMemberRecord> rows;
  late String owner;
  late SdkMemberSource sdk;
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  var sequence = 0;

  void page(RequestOptions request, RequestInterceptorHandler handler) {
    final role = request.queryParameters['role']?.toString();
    final offset = request.queryParameters['offset'] as int;
    final limit = request.queryParameters['limit'] as int;
    final scoped = role == 'admins'
        ? rows.where((m) => m.role >= 300).toList()
        : role == 'members'
            ? rows.where((m) => m.role < 300).toList()
            : rows;
    final result = scoped.skip(offset).take(limit).toList();
    handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
      'data': {
        'items': result
            .map((m) => {
                  'userId': m.userId,
                  'nickname': m.nickname,
                  'role': m.role,
                })
            .toList(),
        'total': scoped.length,
        'hasMore': offset + result.length < scoped.length,
      },
    }));
  }

  List<RequestOptions> ordinaryRequests() =>
      requests.where((r) => r.queryParameters['role'] == 'members').toList();
  TUIGroupProfileModel model() {
    final result = TUIGroupProfileModel()..groupID = group;
    addTearDown(result.dispose);
    return result;
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
    memory.clear(notify: false);
    SessionIdentityService.instance.invalidate();
    owner = 'entry-refresh-${sequence++}';
    await ApiClient.instance.saveToken('token', userId: owner);
    sdk = SdkMemberSource([member(999)]);
    await serviceLocator.unregister<GroupServices>();
    serviceLocator.registerSingleton<GroupServices>(PagingGroups(
      GroupMembershipSyncService.forTest(memberPageLoader: sdk.load),
    ));
    requests.clear();
    rows = List.generate(
        123,
        (i) => member(i,
            role: i == 0
                ? 400
                : i == 1
                    ? 300
                    : 200));
    respond = page;
  });
  tearDown(() async {
    await disk.clearForOwner(owner);
    memory.clear(notify: false);
  });

  test('entry fetches one fresh business page; further pages require demand',
      () async {
    final profile = model();
    await profile.loadMemberPageOnEntry();
    expect(profile.groupMemberList.length, 50);
    expect(ordinaryRequests().length, 1);
    expect(ordinaryRequests().single.queryParameters['refresh'], isNull);
    expect(sdk.cursors, isEmpty);
    expect(profile.hasMoreGroupMembers, isTrue);
    await profile.loadMoreGroupMembers();
    expect(profile.groupMemberList.length, 100);
    expect(ordinaryRequests().last.queryParameters['offset'], 50);
    await profile.loadMoreGroupMembers();
    expect(profile.groupMemberList.length, 121);
    expect(profile.hasMoreGroupMembers, isFalse);
    await profile.loadMoreGroupMembers();
    expect(ordinaryRequests().length, 3);
  });

  test(
      'reentry discards old membership and resets pagination even within five minutes',
      () async {
    final profile = model();
    await profile.loadMemberPageOnEntry();
    await profile.loadMoreGroupMembers();
    rows = [member(501), member(502)];
    await profile.loadMemberPageOnEntry();
    expect(profile.groupMemberList.map((m) => m!.userID),
        [member(501).userId, member(502).userId]);
    expect(ordinaryRequests().last.queryParameters['offset'], 0);
    expect(profile.hasMoreGroupMembers, isFalse);
  });

  test('successful empty first page replaces old rows', () async {
    final profile = model()..groupMemberList = [v2Member(member(999))];
    rows = [];
    await profile.loadMemberPageOnEntry();
    expect(profile.groupMemberList, isEmpty);
    expect(profile.membersWithBackendRoles(profile.groupMemberList), isEmpty);
    expect(profile.hasMoreGroupMembers, isFalse);
    expect(profile.hasMemberEntryError, isFalse);
  });

  test('overlapping entries share a request while later entry refreshes',
      () async {
    final profile = model();
    final held = Completer<void>();
    final entered = Completer<void>();
    respond = (r, h) async {
      if (r.queryParameters['role'] == 'members') {
        if (!entered.isCompleted) entered.complete();
        await held.future;
      }
      page(r, h);
    };
    final first = profile.loadMemberPageOnEntry();
    await entered.future;
    final second = profile.loadMemberPageOnEntry();
    expect(identical(first, second), isTrue);
    expect(profile.isMemberEntryLoading, isTrue);
    held.complete();
    await Future.wait([first, second]);
    expect(ordinaryRequests().length, 1);
    await profile.loadMemberPageOnEntry();
    expect(ordinaryRequests().length, 2);
  });

  test('failed first page stays empty and explicit retry succeeds', () async {
    final profile = model()..groupMemberList = [v2Member(member(999))];
    respond = (r, h) {
      if (r.queryParameters['role'] == 'members') {
        h.reject(DioError(requestOptions: r, error: 'offline'));
      } else {
        page(r, h);
      }
    };
    await profile.loadMemberPageOnEntry();
    expect(profile.hasMemberEntryError, isTrue);
    expect(profile.isMemberEntryLoading, isFalse);
    expect(profile.groupMemberList, isEmpty);
    respond = page;
    await profile.loadMemberPageOnEntry();
    expect(profile.hasMemberEntryError, isFalse);
    expect(profile.groupMemberList.length, 50);
  });

  test('failed next page preserves cursor and retries the same offset',
      () async {
    final profile = model();
    await profile.loadMemberPageOnEntry();
    respond = (r, h) => h.reject(DioError(requestOptions: r, error: 'offline'));
    await profile.loadMoreGroupMembers();
    expect(profile.groupMemberList.length, 50);
    expect(profile.hasMoreGroupMembers, isTrue);
    respond = page;
    await profile.loadMoreGroupMembers();
    expect(ordinaryRequests().map((r) => r.queryParameters['offset']),
        [0, 50, 50]);
    expect(profile.groupMemberList.length, 100);
  });

  test('failed role refresh cannot merge previous managers into a new entry', () async {
    final profile = model();
    await profile.loadMemberPageOnEntry();
    expect(profile.managementMemberList, hasLength(2));
    rows = [member(501)];
    respond = (r, h) {
      if (r.queryParameters['role'] == 'admins') {
        h.reject(DioError(requestOptions: r, error: 'offline'));
      } else {
        page(r, h);
      }
    };
    await profile.loadMemberPageOnEntry();
    expect(profile.managementMemberList, isEmpty);
    expect(profile.membersWithBackendRoles(profile.groupMemberList)
        .map((m) => m!.userID), [member(501).userId]);
    expect(profile.hasManagementMemberListError, isTrue);
  });

  test('removed rows do not shift raw pagination offset or reappear', () async {
    memory.removeMembers(group, [member(7).userId], notify: false);
    final profile = model();
    await profile.loadMemberPageOnEntry();
    expect(profile.groupMemberList.length, 49);
    await profile.loadMoreGroupMembers();
    expect(ordinaryRequests().last.queryParameters['offset'], 50);
    expect(profile.groupMemberList.map((m) => m!.userID),
        isNot(contains(member(7).userId)));
    expect(profile.groupMemberList.length, 99);
  });

  for (final changeSession in [false, true]) {
    test(
        'late entry response is ignored after ${changeSession ? 'session' : 'group'} change',
        () async {
      final profile = model();
      final entered = Completer<void>();
      final held = Completer<void>();
      respond = (r, h) async {
        if (!entered.isCompleted) entered.complete();
        await held.future;
        page(r, h);
      };
      final pending = profile.loadMemberPageOnEntry();
      await entered.future;
      if (changeSession) {
        SessionIdentityService.instance.invalidate();
      } else {
        profile.groupID = '@TGS#other';
      }
      held.complete();
      await pending;
      expect(profile.groupMemberList, isEmpty);
      expect(profile.managementMemberList, isEmpty);
    });
  }

  test(
      'invite membership refresh bypasses named cache without changing default display lookups',
      () async {
    final cached = member(7);
    await disk
        .upsertMany(ownerUserId: owner, groupId: group, records: [cached]);
    var lookups = 0;
    final sync =
        GroupMembershipSyncService.forTest(memberInfoLoader: (_, __) async {
      lookups++;
      return V2TimValueCallback(
          code: 0, desc: 'ok', data: <V2TimGroupMemberFullInfo>[]);
    });
    final display = await sync
        .loadGroupMembersInfo(groupID: group, memberList: [cached.userId]);
    expect(display.data, hasLength(1));
    expect(lookups, 0);
    final membership = await sync.loadGroupMembersInfo(
        groupID: group, memberList: [cached.userId], refresh: true);
    expect(membership.data, isEmpty);
    expect(lookups, 1);
  });

  test('removal survives delay and group aliases, confirmed join clears it',
      () async {
    final removed = member(7);
    memory.removeMembers(group, [removed.userId], notify: false);
    await Future<void>.delayed(const Duration(seconds: 5));
    expect(memory.isRemovalTombstoned('group_$group', removed.userId), isTrue);
    final sync = GroupMembershipSyncService.forTest(
        memberInfoLoader: (_, __) async =>
            V2TimValueCallback(code: 0, desc: 'ok', data: [v2Member(removed)]));
    await sync.applyTargetedMemberCorrection(
        groupId: group,
        action: 'member_added',
        memberUserIds: [removed.userId]);
    expect(memory.isRemovalTombstoned(group, removed.userId), isFalse);
    expect(await disk.readByUserIds(groupId: group, userIds: [removed.userId]),
        hasLength(1));
  });

  test('fresh membership cannot inherit an active role from cached profiles',
      () async {
    final cached = [member(7), member(8), member(9, role: 300)];
    await disk.upsertMany(
        ownerUserId: owner, groupId: group, records: cached);
    final sync = GroupMembershipSyncService.forTest(
      memberInfoLoader: (_, __) async => V2TimValueCallback(
        code: 0,
        desc: 'ok',
        data: [
          V2TimGroupMemberFullInfo(userID: cached[0].userId, role: 0),
          V2TimGroupMemberFullInfo(userID: cached[1].userId),
          V2TimGroupMemberFullInfo(userID: cached[2].userId, role: 200),
        ],
      ),
    );
    final result = await sync.loadGroupMembersInfo(
      groupID: group,
      memberList: cached.map((m) => m.userId).toList(),
      refresh: true,
    );
    expect(result.code, 0);
    expect(result.data!.map((m) => m.userID), [cached[2].userId]);
    expect(result.data!.single.role, 200);
    final display = await sync.loadGroupMembersInfo(
      groupID: group,
      memberList: cached.map((m) => m.userId).toList(),
    );
    expect(display.data, hasLength(3));
    expect(display.data!.map((m) => m.nickName),
        cached.map((m) => m.nickname));
  });

  test('local removal publishes picker invalidation and blocks late lookup',
      () async {
    final removed = member(7);
    final retained = member(8);
    await disk.upsertMany(
        ownerUserId: owner, groupId: group, records: [removed, retained]);
    final profile = model();
    profile.groupMemberList = [v2Member(removed), v2Member(retained)];
    final entered = Completer<void>();
    final response = Completer<V2TimValueCallback<List<V2TimGroupMemberFullInfo>>>();
    final sync = GroupMembershipSyncService.forTest(
      memberInfoLoader: (_, __) {
        entered.complete();
        return response.future;
      },
    );
    final lookup = sync.loadGroupMembersInfo(
        groupID: group,
        memberList: [removed.userId, retained.userId],
        refresh: true);
    await entered.future;
    final removal = memory.removals.first;
    await disk.deleteUsers(
        ownerUserId: owner,
        groupId: 'group_$group',
        userIds: [removed.userId]);
    expect(memory.isRemovalTombstoned(group, removed.userId), isTrue);
    expect((await removal).userIDs, {removed.userId});
    expect(profile.groupMemberList.map((m) => m?.userID), [retained.userId]);
    response.complete(V2TimValueCallback(
        code: 0, desc: 'ok', data: [v2Member(removed), v2Member(retained)]));
    expect((await lookup).data!.map((m) => m.userID), [retained.userId]);
  });

  test('failed fresh lookup is not reported as a successful empty membership',
      () async {
    final sync = GroupMembershipSyncService.forTest(
        memberInfoLoader: (_, __) async =>
            V2TimValueCallback(code: -1, desc: 'offline'));
    final result = await sync.loadGroupMembersInfo(
        groupID: group, memberList: [member(7).userId], refresh: true);
    expect(result.code, isNot(0));
  });

  test('late SDK pages and search cannot resurrect confirmed removals',
      () async {
    final removed = member(7);
    memory.removeMembers(group, [removed.userId], notify: false);
    final sync = GroupMembershipSyncService.forTest(
      memberPageLoader: SdkMemberSource([removed]).load,
      memberInfoLoader: (_, __) async =>
          V2TimValueCallback(code: 0, desc: 'ok', data: [v2Member(removed)]),
    );
    final sdkPage =
        await sync.loadGroupMemberPage(groupID: group, count: 50, nextSeq: '0');
    expect(sdkPage.data!.memberInfoList, isEmpty);
    final exact = await sync
        .loadGroupMembersInfo(groupID: group, memberList: [removed.userId]);
    expect(exact.data, isEmpty);
    expect(await disk.readByUserIds(groupId: group, userIds: [removed.userId]),
        isEmpty);
    final search = await GroupMemberCloudSearch.searchPage(
      groupId: group,
      keyword: 'Member',
      invoke: (_) async => V2TimValueCallback(
          code: 0,
          desc: 'ok',
          data: V2GroupMemberInfoSearchResult(groupMemberSearchResultItems: {
            group: [v2Member(removed)]
          })),
    );
    expect(search.members, isEmpty);
  });
}
