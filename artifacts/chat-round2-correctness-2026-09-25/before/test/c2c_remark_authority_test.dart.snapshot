import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/user_profile_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_store.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_display_name.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final service = UserProfileLocalService.instance;
  final store = UserProfileLocalStore.instance;
  const owner = 'c2c_remark_owner';
  const peer = 'c2c_remark_peer';

  setUp(() async {
    await ApiClient.instance.saveToken('test-token', userId: owner);
    await service.clearSession();
    await store.clearForOwner(owner);
    DisplayNameStore.instance.clear(notify: false);
  });

  tearDown(() async {
    await service.clearSession();
    await store.clearForOwner(owner);
    DisplayNameStore.instance.clear(notify: false);
  });

  test('unconfirmed empty remark keeps conversation remark over local nick', () {
    expect(
      FriendDisplayName.resolveLocalFirst(
        localProfile: UserProfileRecord(userId: peer, nickname: '公开昵称'),
        userId: peer,
        conversationShowName: '会话备注',
      ),
      '会话备注',
    );
    expect(
      FriendDisplayName.resolveC2C(
        userId: peer,
        conversationShowName: '会话备注',
      ),
      '会话备注',
    );
  });

  test('confirmed remark clear falls back to nickname', () async {
    await service.saveUserFullInfo(
      V2TimUserFullInfo(userID: peer, nickName: '公开昵称'),
    );
    await service.saveFriendRemark(userId: peer, remark: '');
    expect(service.isFriendRemarkConfirmed(peer), isTrue);
    expect(
      FriendDisplayName.resolveC2C(
        userId: peer,
        conversationShowName: '旧备注',
      ),
      '公开昵称',
    );
    expect(
      FriendDisplayName.resolveLocalFirst(
        localProfile: service.readCached(peer),
        userId: peer,
        conversationShowName: '旧备注',
      ),
      '公开昵称',
    );
    expect(
      FriendDisplayName.resolveFriendRemark(
        localProfile: service.readCached(peer),
        userId: peer,
        imRemark: '旧备注',
      ),
      '',
    );
  });

  test('store nick does not beat conversation remark', () async {
    await service.saveUserFullInfo(
      V2TimUserFullInfo(userID: peer, nickName: '公开昵称'),
    );
    DisplayNameStore.instance.setC2C(peer, '公开昵称', notify: false);
    expect(
      FriendDisplayName.resolveC2C(
        userId: peer,
        conversationShowName: '好友备注',
      ),
      '好友备注',
    );
    expect(
      FriendDisplayName.resolveLocalFirst(
        localProfile: service.readCached(peer),
        userId: peer,
        conversationShowName: '好友备注',
      ),
      '好友备注',
    );
  });
}
