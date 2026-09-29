import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/listener_model/tui_group_listener_model.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'rejoin-owner';
  const groupId = '@TGS#_rejoin';
  late GroupMembershipSyncService service;
  final store = GroupLocalStore.instance;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() async {
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance.saveToken('test-token', userId: owner);
    store.debugOwnerUserIdOverride = owner;
    service = GroupMembershipSyncService.forTest();
    await store.clearForOwner(owner);
    await store.upsert(
        ownerUserId: owner,
        record: MeGroupRecord.fromJson({
          'groupId': groupId,
          'groupName': 'Rejoined group',
          'groupType': 'Public',
        }));
    ConversationSyncService.instance.debugGetConversationOverride =
        (_) async => null;
    service.markExplicitGroupRemovalForTest(groupId);
  });
  tearDown(() async {
    TUIGroupListenerModelHooks.onMemberEnter = null;
    TUIGroupListenerModelHooks.onMemberInvited = null;
    await service.clearSession();
    await ConversationSyncService.instance.clearSession();
    ConversationSyncService.instance.debugGetConversationOverride = null;
    await store.clearForOwner(owner);
    store.debugOwnerUserIdOverride = null;
    await ApiClient.instance.clearToken();
  });
  for (final invited in [false, true]) {
    test('SDK ${invited ? "invite" : "enter"} restores a removed cached group',
        () async {
      service.install();
      final members = [V2TimGroupMemberInfo(userID: owner)];
      if (invited) {
        TUIGroupListenerModelHooks.onMemberInvited!(
            groupId, V2TimGroupMemberInfo(userID: 'inviter'), members);
      } else {
        TUIGroupListenerModelHooks.onMemberEnter!(groupId, members);
      }
      for (var i = 0;
          i < 100 && service.isExplicitlyRemovedGroup(groupId);
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(service.isExplicitlyRemovedGroup(groupId), isFalse);
      expect(service.isJoinedGroup(groupId), isTrue);
    });
  }
  test('confirmed rejoin clears removal even with an existing joined row',
      () async {
    expect(service.isJoinedGroup(groupId), isTrue);
    expect(service.isExplicitlyRemovedGroup(groupId), isTrue);
    expect(
        await service.admitGroupMembershipFromImHint(
            groupId: groupId, confirmedMembership: true),
        isTrue);
    expect(service.isExplicitlyRemovedGroup(groupId), isFalse);
  });
  test('cached conversation cannot revive an explicitly removed group',
      () async {
    expect(await service.admitGroupMembershipFromImHint(groupId: groupId),
        isFalse);
    expect(service.isExplicitlyRemovedGroup(groupId), isTrue);
  });
  test('another leave supersedes a pending confirmed rejoin', () async {
    final admission = service.admitGroupMembershipFromImHint(
        groupId: groupId, confirmedMembership: true);
    service.markExplicitGroupRemovalForTest(groupId);
    expect(await admission, isFalse);
    expect(service.isExplicitlyRemovedGroup(groupId), isTrue);
  });
  test('account boundary supersedes a pending confirmed rejoin', () async {
    final admission = service.admitGroupMembershipFromImHint(
        groupId: groupId, confirmedMembership: true);
    SessionIdentityService.instance.invalidate();
    expect(await admission, isFalse);
    expect(service.isExplicitlyRemovedGroup(groupId), isTrue);
  });
}
