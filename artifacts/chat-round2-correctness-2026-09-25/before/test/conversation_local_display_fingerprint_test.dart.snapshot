import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/conversation_projection_fingerprint.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'local-display-fp-owner';
  const group = '@TGS#_fpGroupName';
  const peer = 'fp_peer_u1';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
    setupServiceLocator();
  });

  setUp(() async {
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance.saveToken('test-token', userId: owner);
    await GroupLocalStore.instance.clearForOwner(owner);
    await UserProfileLocalService.instance.clearSession();
    ChatSessionController.instance.clearSessionProjection(notify: false);
  });

  tearDown(() async {
    await GroupLocalStore.instance.clearForOwner(owner);
    await UserProfileLocalService.instance.clearSession();
    ChatSessionController.instance.clearSessionProjection(notify: false);
  });

  V2TimConversation groupConv() => V2TimConversation(
        conversationID: 'group_$group',
        type: 2,
        groupID: group,
        showName: 'SDK stale name',
        faceUrl: 'https://sdk.test/old.png',
      );

  V2TimConversation c2cConv() => V2TimConversation(
        conversationID: 'c2c_$peer',
        type: 1,
        userID: peer,
        showName: 'SDK stale nick',
        faceUrl: 'https://sdk.test/peer-old.png',
      );

  test('group fingerprint changes when GroupLocalStore groupName changes',
      () async {
    await GroupLocalStore.instance.upsert(
      ownerUserId: owner,
      record: MeGroupRecord.fromJson(<String, dynamic>{
        'groupId': group,
        'groupType': 'Work',
        'groupName': 'Old name',
        'avatarUrl': 'https://old.test/a.png',
        'updatedAt': 1000,
      }),
    );
    final conversation = groupConv();
    final beforeHash = ConversationProjectionFingerprint.hash(conversation);
    final beforeString = ConversationProjectionFingerprint.string(conversation);
    expect(
      ConversationProjectionFingerprint.localDisplayIdentityFragment(
        conversation,
      ),
      contains('Old name'),
    );

    await GroupLocalStore.instance.upsert(
      ownerUserId: owner,
      record: MeGroupRecord.fromJson(<String, dynamic>{
        'groupId': group,
        'groupType': 'Work',
        'groupName': 'New name',
        'avatarUrl': 'https://old.test/a.png',
        'updatedAt': 2000,
      }),
    );

    expect(
      ConversationProjectionFingerprint.localDisplayIdentityFragment(
        conversation,
      ),
      contains('New name'),
    );
    expect(
      ConversationProjectionFingerprint.hash(conversation),
      isNot(beforeHash),
    );
    expect(
      ConversationProjectionFingerprint.string(conversation),
      isNot(beforeString),
    );
  });

  test('c2c fingerprint changes when UserProfileLocal nickname changes',
      () async {
    await UserProfileLocalService.instance.saveBackendProfile(
      userId: peer,
      nickname: 'Old nick',
      avatarUrl: 'https://peer.test/a.png',
    );
    final conversation = c2cConv();
    final beforeHash = ConversationProjectionFingerprint.hash(conversation);

    await UserProfileLocalService.instance.saveBackendProfile(
      userId: peer,
      nickname: 'New nick',
      avatarUrl: 'https://peer.test/a.png',
    );

    expect(
      ConversationProjectionFingerprint.localDisplayIdentityFragment(
        conversation,
      ),
      contains('New nick'),
    );
    expect(
      ConversationProjectionFingerprint.hash(conversation),
      isNot(beforeHash),
    );
  });

  test('bumpRowRevisions increments existing visible-row notifiers', () {
    const id = 'group_visible_row';
    final notifier = ChatSessionController.instance.rowRevisionOf(id);
    expect(notifier.value, 0);
    ChatSessionController.instance.bumpRowRevisions(<String>[id]);
    expect(notifier.value, 1);
  });
}
