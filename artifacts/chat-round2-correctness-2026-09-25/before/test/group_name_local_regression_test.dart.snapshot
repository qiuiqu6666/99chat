import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_group_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/search_conversation_display.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_demo/src/utils/group_tip_custom_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'group-name-regression-owner';
  const group = '@TGS#_mcNameRegression';
  final store = GroupLocalStore.instance;
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
    await store.clearForOwner(owner);
    ApiClient.instance.dio.interceptors.clear();
    await store.upsert(
        ownerUserId: owner,
        record: MeGroupRecord.fromJson({
          'groupId': group,
          'groupType': 'Community',
          'groupName': 'Local old name',
          'notice': 'Keep notice',
          'memberCount': 12,
          'updatedAt': DateTime.now().millisecondsSinceEpoch + 86400000,
        }));
  });
  tearDown(() async {
    ApiClient.instance.dio.interceptors.clear();
    debugSearchConversationLookup = null;
    debugSearchGetGroupsInfo = null;
    await store.clearForOwner(owner);
  });
  test('latest detail repairs name despite a newer local row timestamp',
      () async {
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (request, handler) => handler.resolve(Response(
        requestOptions: request,
        statusCode: 200,
        data: {
          'data': {
            'groupId': group,
            'groupName': 'Remote current name',
            'updatedAt': DateTime.now().millisecondsSinceEpoch - 1000,
          }
        },
      )),
    ));
    await MeGroupApi.instance.fetchGroupDetail(group, refresh: true);
    final row = store.readCached(groupId: group)!;
    expect(row.groupName, 'Remote current name');
    expect(row.notice, 'Keep notice');
    expect(row.memberCount, 12);
  });
  test('confirmed edit is persisted with a future local timestamp', () async {
    await GroupMembershipSyncService.instance.applyOptimisticGroupName(
      groupId: group,
      groupName: 'Confirmed new name',
    );
    expect(store.readCached(groupId: group)?.groupName, 'Confirmed new name');
  });
  test('profile detail repairs name despite a newer local row timestamp',
      () async {
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (request, handler) => handler.resolve(Response(
        requestOptions: request,
        statusCode: 200,
        data: {
          'data': {
            'groupId': group,
            'groupName': 'Profile current name',
            'myRole': 400,
            'updatedAt': DateTime.now().millisecondsSinceEpoch - 1000,
          }
        },
      )),
    ));
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    await model.loadGroupInfo(group);
    expect(store.readCached(groupId: group)?.groupName, 'Profile current name');
    expect(model.groupInfo?.groupName, 'Profile current name');
    expect(store.readCached(groupId: group)?.notice, 'Keep notice');
  });
  test('display cache and old conversation cannot hide a committed name',
      () async {
    final names = DisplayNameStore.instance;
    names.setGroup(group, 'Stale list name');
    await GroupMembershipSyncService.instance.applyOptimisticGroupName(
      groupId: group,
      groupName: 'Confirmed new name',
    );
    names.setGroup(group, 'Late stale list name');
    final conversation = V2TimConversation(
      conversationID: 'group_$group',
      groupID: group,
      type: 2,
      showName: 'Stale conversation name',
    );
    names.applyToConversation(conversation);
    expect(names.group(group), 'Confirmed new name');
    expect(conversation.showName, 'Confirmed new name');
  });
  test('search avatar hydration cannot write an old conversation name back',
      () async {
    debugSearchConversationLookup = (id) async => V2TimConversation(
          conversationID: id,
          groupID: group,
          type: 2,
          showName: 'Stale conversation name',
          faceUrl: 'https://example.com/group.png',
        );
    debugSearchGetGroupsInfo = (_) async => [];
    await hydrateAppSearchConversationDisplays(['group_$group']);
    expect(store.readCached(groupId: group)?.groupName, 'Local old name');
  });
  test('delayed rename tip cannot overwrite the refreshed REST name', () async {
    var requests = 0;
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (request, handler) {
        requests++;
        handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: {
            'data': {'groupId': group, 'groupName': 'Latest REST name'}
          },
        ));
      },
    ));
    final message = V2TimMessage.fromJson(<String, dynamic>{
      'message_server_time': 1700000000,
      'message_msg_id': 'delayed-name-tip',
      'message_is_from_self': false,
      'message_status': 2,
      'message_custom_str': '',
      'message_risk_type_identified': 0,
      'message_sender_group_member_info': <String, dynamic>{},
      'message_group_at_user_array': <String>[],
    })
      ..groupID = group
      ..elemType = MessageElemType.V2TIM_ELEM_TYPE_CUSTOM
      ..customElem = V2TimCustomElem(
          data: jsonEncode(buildGroupTipPayload(
        action: 'group_name_changed',
        opUserId: 'other',
        opUserName: 'Other',
        clientMsgId: 'delayed-name-tip',
        detail: {'groupName': 'Old tip name'},
      )));
    await GroupMembershipSyncService.instance
        .applyInboundGroupDisplayFromMessage(message);
    expect(requests, 1);
    expect(store.readCached(groupId: group)?.groupName, 'Latest REST name');
  });
  test('search uses committed name before a stale group hint', () {
    final display = resolveAppSearchConversationDisplay(
      conversationId: 'group_$group',
      groupHint: V2TimGroupInfo(
        groupID: group,
        groupType: 'Community',
        groupName: 'Stale hint name',
      ),
    );
    expect(display.showName, 'Local old name');
  });

  test('coordinated refresh repairs only the name of a newer local row',
      () async {
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (request, handler) => handler.resolve(Response(
        requestOptions: request,
        statusCode: 200,
        data: {
          'data': {
            'groupId': group,
            'groupName': 'Coordinated current name',
            'notice': 'Older notice',
            'memberCount': 1,
            'updatedAt': DateTime.now().millisecondsSinceEpoch - 1000,
          }
        },
      )),
    ));
    await GroupMembershipSyncService.instance
        .refreshGroupDetail(group, refresh: true);
    final row = store.readCached(groupId: group)!;
    expect(row.groupName, 'Coordinated current name');
    expect(row.notice, 'Keep notice');
    expect(row.memberCount, 12);
  });

  test('search fallback cannot cancel an in-flight authoritative refresh',
      () async {
    final started = Completer<void>();
    final release = Completer<void>();
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (request, handler) async {
        started.complete();
        await release.future;
        handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: {
            'data': {
              'groupId': group,
              'groupName': 'Remote current name',
              'updatedAt': DateTime.now().millisecondsSinceEpoch - 1000,
            }
          },
        ));
      },
    ));
    final refresh = MeGroupApi.instance.fetchGroupDetail(group, refresh: true);
    await started.future;
    debugSearchConversationLookup = (id) async => V2TimConversation(
          conversationID: id,
          groupID: group,
          type: 2,
          showName: 'Stale conversation name',
          faceUrl: 'https://example.com/group.png',
        );
    debugSearchGetGroupsInfo = (_) async => [];
    try {
      await hydrateAppSearchConversationDisplays(['group_$group']);
    } finally {
      release.complete();
      await refresh;
    }
    expect(store.readCached(groupId: group)?.groupName, 'Remote current name');
  });

  test('detail started before a confirmed edit cannot revert it', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (request, handler) async {
        started.complete();
        await release.future;
        handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: {
            'data': {
              'groupId': group,
              'groupName': 'Delayed old name',
              'updatedAt': DateTime.now().millisecondsSinceEpoch - 1000,
            }
          },
        ));
      },
    ));
    final refresh = MeGroupApi.instance.fetchGroupDetail(group, refresh: true);
    await started.future;
    try {
      await GroupMembershipSyncService.instance.applyOptimisticGroupName(
        groupId: group,
        groupName: 'Confirmed new name',
      );
    } finally {
      release.complete();
      await refresh;
    }
    expect(store.readCached(groupId: group)?.groupName, 'Confirmed new name');
  });

  test('search still fills a missing group name and avatar', () async {
    await store.clearForOwner(owner);
    debugSearchConversationLookup = (id) async => V2TimConversation(
          conversationID: id,
          groupID: group,
          type: 2,
          showName: 'Fallback name',
          faceUrl: 'https://example.com/group.png',
        );
    debugSearchGetGroupsInfo = (_) async => [];
    await hydrateAppSearchConversationDisplays(['group_$group']);
    final row = store.readCached(groupId: group)!;
    expect(row.groupName, 'Fallback name');
    expect(row.avatarUrl, 'https://example.com/group.png');
  });
}
