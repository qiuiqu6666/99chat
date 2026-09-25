// This lifecycle test observes existing notifier subscriptions without adding
// a production-only listener-count API.
// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_filter_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/life_cycle/group_profile_life_cycle.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/listener_model/tui_group_listener_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/conversation/conversation_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/tim_uikit_group_profile.dart';

class _Groups implements GroupServices {
  @override
  Future<List<V2TimGroupInfoResult>?> getGroupsInfo({
    required List<String> groupIDList,
  }) async =>
      null;

  @override
  Future<V2TimValueCallback<V2TimGroupMemberInfoResult>> getGroupMemberList({
    required String groupID,
    required GroupMemberFilterTypeEnum filter,
    required String nextSeq,
    int count = 15,
    int offset = 0,
  }) async =>
      V2TimValueCallback<V2TimGroupMemberInfoResult>(
        code: 0,
        desc: '',
        data: V2TimGroupMemberInfoResult(nextSeq: '0', memberInfoList: []),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conversations implements ConversationService {
  final responses = <Completer<V2TimConversation?>>[];

  @override
  Future<V2TimConversation?> getConversation({required String conversationID}) {
    final response = Completer<V2TimConversation?>();
    responses.add(response);
    return response.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Conversations conversations;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    await ApiClient.instance
        .saveToken('test-token', userId: 'profile-owned-lifetime-user');
    await serviceLocator.unregister<GroupServices>();
    serviceLocator.registerSingleton<GroupServices>(_Groups());
    await serviceLocator.unregister<ConversationService>();
    conversations = _Conversations();
    serviceLocator.registerSingleton<ConversationService>(conversations);
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) {
      final members = request.path.contains('/members');
      handler.resolve(Response(
        requestOptions: request,
        statusCode: 200,
        data: {
          'data': members
              ? {
                  'groupId': request.path,
                  'items': <Map<String, dynamic>>[],
                  'total': 0,
                  'limit': 50,
                  'offset': 0,
                }
              : {
                  'groupId': request.path.contains('channel-preview')
                      ? '@TGS#_@TGS#channel-preview'
                      : '@TGS#profile-owned-lifetime',
                  'groupType': 'Public',
                  'groupName': 'Owned',
                  if (!request.path.contains('channel-preview')) 'myRole': 200,
                  'memberCount': 1,
                },
        },
      ));
    }));
  });

  testWidgets(
      'unmount releases owned model, store subscriptions and route hooks',
      (tester) async {
    final errorHandler = FlutterError.onError;
    addTearDown(() => FlutterError.onError = errorHandler);
    final groups = GroupLocalStore.instance.commitListenable;
    final members = GroupMemberLocalStore.instance.commitListenable;
    final groupsHadListeners = groups.hasListeners;
    final membersHadListeners = members.hasListeners;
    final shared = serviceLocator<TUIGroupListenerModel>();
    const group = '@TGS#profile-owned-lifetime';
    var clicked = 0;
    final lifecycle = GroupProfileLifeCycle(didLeaveGroup: () async {
      clicked++;
    });

    Future<void> pump(Widget child) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
      FlutterError.onError = errorHandler;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      FlutterError.onError = errorHandler;
      expect(tester.takeException(), isNull);
    }

    await pump(TIMUIKitGroupProfile(
      groupID: group,
      lifeCycle: lifecycle,
      onClickUser: (_, __) => clicked++,
      builder: (_, info, __) => Text(info.groupName ?? ''),
    ));
    final dynamic state = tester.state(find.byType(TIMUIKitGroupProfile));
    final TUIGroupProfileModel model = state.model;
    expect(groups.hasListeners, isTrue);
    expect(members.hasListeners, isTrue);
    expect(model.lifeCycle, same(lifecycle));
    model.onClickUser!(V2TimGroupMemberFullInfo(userID: 'member'), null);
    expect(clicked, 1);

    // Exercise a real global commit while mounted, then the same event after
    // unmount. Retaining this model in the test makes closure release explicit.
    model.groupInfo = V2TimGroupInfo(groupID: group, groupType: 'Public');
    model.groupMemberList = [V2TimGroupMemberFullInfo(userID: 'member')];
    var notifications = 0;
    model.addListener(() => notifications++);
    members.value = const GroupMemberStoreCommit(
      version: 101,
      ownerUserId: '',
      groupId: group,
      kind: GroupMemberStoreMutationKind.reset,
    );
    expect(model.groupMemberList, isEmpty);
    expect(notifications, greaterThan(0));
    await pump(const SizedBox.shrink());

    expect(
        () => ChangeNotifier.debugAssertNotDisposed(model), throwsFlutterError);
    expect(model.onClickUser, isNull);
    expect(model.lifeCycle, isNull);
    expect(groups.hasListeners, groupsHadListeners);
    expect(members.hasListeners, membersHadListeners);
    final notificationsAtUnmount = notifications;
    groups.value = GroupStoreCommit(
        ownerUserId: '', version: 102, kind: GroupStoreMutationKind.reset);
    members.value = const GroupMemberStoreCommit(
      version: 102,
      ownerUserId: '',
      groupId: group,
      kind: GroupMemberStoreMutationKind.reset,
    );
    conversations.responses.single.complete(V2TimConversation(
      conversationID: 'group_$group',
      groupID: group,
      type: 2,
    ));
    await tester.pump();
    FlutterError.onError = errorHandler;
    expect(tester.takeException(), isNull);
    expect(notifications, notificationsAtUnmount);
    expect(model.conversation, isNull);
    expect(ChangeNotifier.debugAssertNotDisposed(shared), isTrue);
    void sharedListener() {}
    shared.addListener(sharedListener);
    shared.removeListener(sharedListener);
  });

  testWidgets('channel preview renders while REST role is unavailable',
      (tester) async {
    const group = '@TGS#_@TGS#channel-preview';
    final errorHandler = FlutterError.onError;
    addTearDown(() => FlutterError.onError = errorHandler);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TIMUIKitGroupProfile(
          groupID: group,
          scrollable: false,
          channelPreviewInfo: V2TimGroupInfo(
            groupID: 'channel-preview',
            groupType: 'Community',
            groupName: '频道资料',
          ),
          builder: (_, info, __) => ListView(
            children: [Text(info.groupName ?? '')],
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    FlutterError.onError = errorHandler;
    expect(find.text('频道资料'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    conversations.responses.last.complete(null);
    await tester.pump(const Duration(milliseconds: 50));
    FlutterError.onError = errorHandler;
    expect(tester.takeException(), isNull);
  });
}
