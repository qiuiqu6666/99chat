import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_group_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_uikit/data_services/conversation/conversation_services.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/group_member/tui_delete_group_member.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/group_member_list.dart';
import 'group_member_on_demand_test.dart'
    show member, SdkMemberSource, PagingGroups;

class _ProfileModel extends TUIGroupProfileModel {
  @override
  Future<void> loadGroupInfo(String groupID) async {}
  @override
  Future<void> loadProfileMemberPreviewPage({required String groupID}) async {}
}

class _Conversations implements ConversationService {
  @override
  Future<V2TimConversation?> getConversation(
          {required String conversationID}) async =>
      null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SlowPermissionsModel extends TUIGroupProfileModel {
  final permissions = Completer<void>();
  bool ready = false;
  bool failed = false;
  int submissions = 0;
  @override
  Future<V2TimCallback> kickOffMember(List<String> userIDs) async {
    submissions++;
    return V2TimCallback(code: -1, desc: 'test');
  }

  void failPermissions() {
    failed = true;
    notifyListeners();
  }

  @override
  String get groupID => '@TGS#paint';
  @override
  bool get isMemberEntryLoading => false;
  @override
  bool get hasLoadedManagementMembers => ready;
  @override
  bool get isManagementMemberListLoading => !ready && !failed;
  @override
  bool get hasManagementMemberListError => failed;
  @override
  int? get backendSelfRole => null;
  @override
  bool canKickOffMember() => ready;
  @override
  bool canKickMember(String id) => ready;
  @override
  List<V2TimGroupMemberFullInfo?> membersWithBackendRoles(
          List<V2TimGroupMemberFullInfo?> source) =>
      source;
  @override
  Future<void> loadMemberPageOnEntry() async {
    groupMemberList = [
      V2TimGroupMemberFullInfo(userID: 'candidate', nickName: 'Visible member'),
      V2TimGroupMemberFullInfo(userID: 'owner-role', role: 400),
      V2TimGroupMemberFullInfo(userID: 'owner-detail', role: 200),
    ];
    notifyListeners();
    await permissions.future;
    ready = true;
    notifyListeners();
  }
}

class _OwnerDeletePaintModel extends TUIGroupProfileModel {
  bool managementReady = false;
  @override
  String get groupID => '@TGS#paint';
  @override
  int? get backendSelfRole => 400;
  @override
  bool get isMemberEntryLoading => false;
  @override
  bool get hasLoadedManagementMembers => managementReady;
  @override
  bool get isManagementMemberListLoading => !managementReady;
  @override
  bool canKickOffMember() => true;
  @override
  bool canKickMember(String id) => id != 'owner';
  @override
  Future<void> loadMemberPageOnEntry() async {
    groupMemberList = [
      V2TimGroupMemberFullInfo(
          userID: 'ordinary', nickName: 'Ordinary', role: 200),
    ];
    notifyListeners();
  }

  @override
  List<V2TimGroupMemberFullInfo?> membersWithBackendRoles(
      List<V2TimGroupMemberFullInfo?> source) {
    if (!managementReady) return source;
    return [
      V2TimGroupMemberFullInfo(userID: 'admin', nickName: 'Admin', role: 300),
      ...source,
    ];
  }

  void completeManagement() {
    managementReady = true;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  final requests = <RequestOptions>[];
  const group = '@TGS#paint';
  var sequence = 0;
  late String owner;

  void page(RequestOptions r, RequestInterceptorHandler h, String userId) {
    final queryRole = r.queryParameters['role']?.toString();
    final itemRole = queryRole == GroupMembersRoleQuery.admins ? 400 : 200;
    h.resolve(Response(requestOptions: r, statusCode: 200, data: {
      'data': {
        'items': [
          {
            'userId': userId,
            'nickname': userId,
            'role': itemRole,
          },
        ],
        'total': 1,
        'hasMore': false,
      },
    }));
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    serviceLocator.unregister<ConversationService>();
    serviceLocator.registerSingleton<ConversationService>(_Conversations());
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (r, h) {
      requests.add(r);
      respond(r, h);
    }));
  });
  setUp(() async {
    SessionIdentityService.instance.invalidate();
    owner = 'first-paint-${sequence++}';
    await ApiClient.instance.saveToken('token', userId: owner);
    requests.clear();
    respond = (r, h) => page(r, h, 'fresh');
  });
  tearDown(() async => GroupMemberLocalStore.instance.clearForOwner(owner));

  for (final pending in [false, true]) {
    test('member entry reuses profile managers (pending: $pending)', () async {
      final model = _ProfileModel();
      addTearDown(model.dispose);
      final requested = Completer<void>();
      final held = Completer<void>();
      final ready = Completer<void>();
      respond = (r, h) async {
        if (r.queryParameters['role'] != null) {
          if (!requested.isCompleted) requested.complete();
          if (pending) await held.future;
        }
        page(r, h, 'fresh');
      };
      model.addListener(() {
        if (model.hasLoadedManagementMembers &&
            !model.isManagementMemberListLoading &&
            !ready.isCompleted) {
          ready.complete();
        }
      });
      model.loadData(group);
      await requested.future.timeout(const Duration(seconds: 3));
      if (!pending) await ready.future.timeout(const Duration(seconds: 3));
      final entry = model.loadMemberPageOnEntry();
      await Future<void>.delayed(Duration.zero);
      if (pending) held.complete();
      await entry.timeout(const Duration(seconds: 3));
      await model.loadMemberPageOnEntry();
      expect(
          requests.where(
              (r) => r.queryParameters['role'] == GroupMembersRoleQuery.admins),
          hasLength(1));
      expect(
          requests.where(
              (r) => r.queryParameters['role'] == GroupMembersRoleQuery.members),
          hasLength(pending ? 2 : 3));
      expect(model.hasLoadedManagementMembers, isTrue);

      // Changing groups invalidates the profile-scoped reuse.
      model.groupID = '@TGS#another';
      await model.loadMemberPageOnEntry();
      expect(
          requests.where(
              (r) => r.queryParameters['role'] == GroupMembersRoleQuery.admins),
          hasLength(2));
    });
  }

  test('failed profile managers retry on member entry', () async {
    final model = _ProfileModel();
    addTearDown(model.dispose);
    final failed = Completer<void>();
    respond = (r, h) => h.reject(DioError(
          requestOptions: r,
          type: DioErrorType.other,
        ));
    model.addListener(() {
      if (model.hasManagementMemberListError &&
          !model.isManagementMemberListLoading &&
          !failed.isCompleted) {
        failed.complete();
      }
    });
    model.loadData(group);
    await failed.future.timeout(const Duration(seconds: 3));
    respond = (r, h) => page(r, h, 'recovered');
    await model.loadMemberPageOnEntry();
    expect(model.hasLoadedManagementMembers, isTrue);
    expect(model.hasManagementMemberListError, isFalse);
    expect(model.managementMemberList.single!.userID, 'recovered');
  });

  test('profile managers are not reused after session change', () async {
    final model = _ProfileModel();
    addTearDown(model.dispose);
    model.loadData(group);
    await model.loadMemberPageOnEntry();
    expect(model.managementMemberList.single!.userID, 'fresh');
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance.saveToken('new-token', userId: owner);
    respond = (r, h) => page(r, h, 'new-session');
    await model.loadMemberPageOnEntry();
    expect(
        requests.where(
            (r) => r.queryParameters['role'] == GroupMembersRoleQuery.admins),
        hasLength(2));
    expect(model.managementMemberList.single!.userID, 'new-session');
  });

  test('member first paint does not wait for management responses', () async {
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    final held = Completer<void>();
    final painted = Completer<void>();
    respond = (r, h) async {
      if (r.queryParameters['role'] == GroupMembersRoleQuery.admins) {
        await held.future;
      }
      page(r, h, 'fresh');
    };
    model.addListener(() {
      if (model.groupMemberList.isNotEmpty && !painted.isCompleted)
        painted.complete();
    });
    final task = model.loadMemberPageOnEntry();
    await painted.future.timeout(const Duration(seconds: 3));
    final firstPageBlocked = model.isMemberEntryLoading;
    final rolesPending = model.isManagementMemberListLoading;
    held.complete();
    await task;
    expect(firstPageBlocked, isFalse);
    expect(rolesPending, isTrue);
  });

  test('fresh entry bypasses pending preview and ignores its late result',
      () async {
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    final previewEntered = Completer<void>();
    final freshEntered = Completer<void>();
    final held = Completer<void>();
    var first = true;
    respond = (r, h) async {
      if (first) {
        first = false;
        previewEntered.complete();
        await held.future;
        page(r, h, 'stale');
      } else {
        if (r.queryParameters['role'] == GroupMembersRoleQuery.members &&
            !freshEntered.isCompleted) {
          freshEntered.complete();
        }
        page(r, h, 'fresh');
      }
    };
    final preview = model.loadProfileMemberPreviewPage(groupID: group);
    await previewEntered.future;
    final entry = model.loadMemberPageOnEntry();
    var startedWhilePreviewPending = true;
    try {
      await freshEntered.future.timeout(const Duration(milliseconds: 500));
    } on TimeoutException {
      startedWhilePreviewPending = false;
    }
    if (startedWhilePreviewPending) await entry;
    held.complete();
    await Future.wait([entry, preview]);
    expect(startedWhilePreviewPending, isTrue);
    expect(model.groupMemberList.map((m) => m!.userID), ['fresh']);
  });

  test('successful empty role page is final, without group alias retries',
      () async {
    respond =
        (r, h) => h.resolve(Response(requestOptions: r, statusCode: 200, data: {
              'data': {'items': [], 'total': 0, 'hasMore': false}
            }));
    final result = await MeGroupApi.instance.fetchGroupMembersPage(
        groupId: group, role: GroupMembersRoleQuery.admins);
    expect(result.items, isEmpty);
    expect(requests, hasLength(1));
  });

  test('role lookup still retries an invalid group ID response', () async {
    respond = (r, h) {
      if (requests.length == 1) {
        h.reject(DioError(
            requestOptions: r,
            type: DioErrorType.response,
            response: Response(requestOptions: r, statusCode: 404)));
      } else {
        page(r, h, 'admin');
      }
    };
    final result = await MeGroupApi.instance.fetchGroupMembersPage(
        groupId: group, role: GroupMembersRoleQuery.admins);
    expect(result.items.single.userId, 'admin');
    expect(requests, hasLength(2));
  });

  test('fresh entry bypasses pending SDK page and rejects its late result',
      () async {
    final sdk = SdkMemberSource([member(999)])
      ..entered = Completer<void>()
      ..gate = Completer<void>();
    await serviceLocator.unregister<GroupServices>();
    serviceLocator.registerSingleton<GroupServices>(PagingGroups(
        GroupMembershipSyncService.forTest(memberPageLoader: sdk.load)));
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    final old = model.loadGroupMemberList(groupID: group);
    await sdk.entered!.future;
    try {
      await model.loadMemberPageOnEntry().timeout(const Duration(seconds: 3));
    } finally {
      sdk.gate!.complete();
      await old;
    }
    expect(model.groupMemberList.map((m) => m!.userID), ['fresh']);
    expect(model.isMemberEntryLoading, isFalse);
  });

  testWidgets(
      'delete page excludes unverified members and owners from candidates',
      (tester) async {
    final model = _SlowPermissionsModel();
    model.groupInfo = V2TimGroupInfo(
        groupID: group, groupType: 'Public', owner: 'owner-detail');
    final previous = FlutterError.onError;
    await tester
        .pumpWidget(MaterialApp(home: DeleteGroupMemberPage(model: model)));
    FlutterError.onError = previous;
    await tester.pump();
    FlutterError.onError = previous;
    expect(tester.takeException(), isNull);
    final pendingList = find.byType(GroupProfileMemberList);
    expect(pendingList, findsOneWidget);
    expect(find.text('正在加载群管理权限，暂不可选择成员'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
        tester.widget<GroupProfileMemberList>(pendingList).memberList, isEmpty);
    expect(tester.widget<GroupProfileMemberList>(pendingList).canSelectMember,
        isFalse);
    final state = tester
        .state<DeleteGroupMemberPageState>(find.byType(DeleteGroupMemberPage));
    state.selectedGroupMember = [V2TimGroupMemberFullInfo(userID: 'candidate')];
    await state.submitDelete();
    expect(model.submissions, 0);
    model.failPermissions();
    await tester.pump();
    FlutterError.onError = previous;
    expect(find.byType(GroupProfileMemberList), findsOneWidget);
    expect(tester.widget<GroupProfileMemberList>(pendingList).canSelectMember,
        isFalse);
    expect(find.text('群管理权限加载失败，点击重试'), findsOneWidget);
    model.failed = false;
    model.permissions.complete();
    await tester.pumpAndSettle();
    FlutterError.onError = previous;
    expect(tester.widget<GroupProfileMemberList>(pendingList).canSelectMember,
        isTrue);
    expect(
        tester
            .widget<GroupProfileMemberList>(pendingList)
            .memberList
            .map((m) => m!.userID),
        ['candidate']);
    state.selectedGroupMember = [
      V2TimGroupMemberFullInfo(userID: 'owner-detail')
    ];
    await state.submitDelete();
    expect(model.submissions, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    FlutterError.onError = previous;
    model.dispose();
  });

  testWidgets(
      'owner delete page waits for admins then paints them before members',
      (tester) async {
    final model = _OwnerDeletePaintModel();
    model.groupInfo = V2TimGroupInfo(
        groupID: group, groupType: 'Public', owner: 'owner');
    final previous = FlutterError.onError;
    await tester
        .pumpWidget(MaterialApp(home: DeleteGroupMemberPage(model: model)));
    FlutterError.onError = previous;
    await tester.pump();
    FlutterError.onError = previous;
    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(GroupProfileMemberList), findsNothing);
    model.completeManagement();
    await tester.pump();
    FlutterError.onError = previous;
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final list = find.byType(GroupProfileMemberList);
    expect(list, findsOneWidget);
    expect(
      tester.widget<GroupProfileMemberList>(list).memberList.map((m) => m!.userID),
      ['admin', 'ordinary'],
    );
    await tester.pumpWidget(const SizedBox.shrink());
    FlutterError.onError = previous;
    model.dispose();
  });
}
