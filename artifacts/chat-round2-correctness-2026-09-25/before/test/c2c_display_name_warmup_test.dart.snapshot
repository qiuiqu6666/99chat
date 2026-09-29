import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_display_name.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';

MeFriendRecord _record(
  String id, {
  String remark = '',
  String nickname = '',
  bool remarkKnown = true,
}) {
  return MeFriendRecord(
    friendUserId: id,
    remark: remark,
    remarkKnown: remarkKnown,
    friendNickname: nickname,
    friendAvatarUrl: '',
    addedAt: 0,
    peerDeletedMe: false,
    canMessage: true,
  );
}

void _putImFriend(
  String id, {
  required String remark,
  String nickname = '公开昵称',
}) {
  ImSdkRelationshipDirectory.instance.applyFriendAdds([
    RelationshipFriendEntry(
      userId: id,
      displayName: remark.isNotEmpty ? remark : nickname,
      faceUrl: '',
      remark: remark,
      nickname: nickname,
      sortKey: ImSdkRelationshipDirectory.sortKeyFor(
        id: id,
        displayName: remark.isNotEmpty ? remark : nickname,
        azTag: 'A',
      ),
    ),
  ]);
}

V2TimConversation _c2c(String id, {String showName = ''}) {
  return V2TimConversation(
    conversationID: 'c2c_$id',
    type: 1,
    userID: id,
    showName: showName,
    orderkey: 100,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() {
    ConversationTabStore.debugFetchOverride = null;
    ConversationTabStore.instance.clear();
    ActiveChatRegistry.instance.reset();
    ConversationUnreadAggregate.instance.clearSession();
    ChatSessionController.instance.clearSessionProjection();
    DisplayNameStore.instance.clear(notify: false);
    PeerProfileRefreshBus.instance.clear();
    UserProfileLocalService.instance.clearSession();
    ImSdkRelationshipDirectory.instance.reset();
    FriendSyncService.instance.debugOwnerUserId = 'warmup_owner';
    ConversationLocalStore.instance.debugOwnerUserId = 'warmup_owner';
  });

  tearDown(() async {
    FriendSyncService.instance.debugOwnerUserId = null;
    ConversationLocalStore.instance.debugOwnerUserId = null;
    DisplayNameStore.instance.clear(notify: false);
    PeerProfileRefreshBus.instance.clear();
    UserProfileLocalService.instance.clearSession();
    ImSdkRelationshipDirectory.instance.reset();
    ChatSessionController.instance.clearSessionProjection();
    await FriendLocalStore.instance.delete(
      ownerUserId: 'warmup_owner',
      friendUserId: 'u1',
      force: true,
    );
    await FriendLocalStore.instance.delete(
      ownerUserId: 'warmup_owner',
      friendUserId: 'u2',
      force: true,
    );
  });

  group('applyC2cDisplayNameWarmup', () {
    test('Test A: hydrates memory mirror so resolveC2C returns remark', () {
      FriendSyncService.instance.applyC2cDisplayNameWarmup([
        _record('u1', remark: '备注A', nickname: '昵称A'),
      ]);

      final cached = UserProfileLocalService.instance.readCached('u1');
      expect(cached, isNotNull);
      expect(cached!.friendRemark, '备注A');
      expect(
        FriendDisplayName.resolveC2C(
          userId: 'u1',
          conversationShowName: '昵称A',
        ),
        '备注A',
      );
    });

    test('Test B: seeds DisplayNameStore and overwrites nick placeholder', () {
      // 模拟冷启动昵称占坑。
      DisplayNameStore.instance.setC2C('u1', '昵称A', notify: false);

      FriendSyncService.instance.applyC2cDisplayNameWarmup([
        _record('u1', remark: '备注A', nickname: '昵称A'),
      ]);

      expect(DisplayNameStore.instance.c2c('u1'), '备注A');
    });

    test('Test C: patches conversation row showName from nickname to remark',
        () async {
      ChatSessionController.instance.ensureTabStoreBridgeAttached();
      await ChatSessionController.instance.applyConversationsFromStoreForTest(
        upserted: [_c2c('u1', showName: '昵称A')],
      );
      expect(
        ChatSessionController.instance.conversations
            .firstWhere((c) => c.conversationID == 'c2c_u1')
            .showName,
        '昵称A',
      );

      FriendSyncService.instance.applyC2cDisplayNameWarmup([
        _record('u1', remark: '备注A', nickname: '昵称A'),
      ]);
      // seedC2cDisplayNamesFromFriendRecords 是 async；等微任务落完。
      await Future<void>.delayed(Duration.zero);

      expect(
        ChatSessionController.instance.conversations
            .firstWhere((c) => c.conversationID == 'c2c_u1')
            .showName,
        '备注A',
      );
    });

    test('Test D: no remark falls back to nickname; all-empty stays raw id',
        () {
      FriendSyncService.instance.applyC2cDisplayNameWarmup([
        _record('u1', nickname: '昵称A'),
      ]);
      expect(DisplayNameStore.instance.c2c('u1'), '昵称A');

      // 备注与昵称均为空：displayName 解析为 id，isRawUserIdDisplayName
      // 过滤后不得写入 Store（禁止 userId 占坑）。
      FriendSyncService.instance.applyC2cDisplayNameWarmup([
        _record('u2'),
      ]);
      expect(DisplayNameStore.instance.c2c('u2'), isNull);
    });

    test('Test E: skips ids already present in memory mirror', () async {
      await UserProfileLocalService.instance.saveFriendRemark(
        userId: 'u1',
        remark: '热数据备注',
      );
      FriendSyncService.instance.applyC2cDisplayNameWarmup([
        _record('u1', remark: '旧备注', nickname: '昵称A'),
      ]);

      expect(
        UserProfileLocalService.instance.readCached('u1')!.friendRemark,
        '热数据备注',
      );
    });
  });

  group('warmupC2cDisplayNamesFromLocalStore', () {
    test('reads local friend store and warms display names', () async {
      final owner = 'warmup_owner';
      final record = _record('u1', remark: '备注A', nickname: '昵称A');
      await FriendLocalStore.instance.upsert(
        ownerUserId: owner,
        record: record,
      );

      await FriendSyncService.instance.warmupC2cDisplayNamesFromLocalStore();

      expect(DisplayNameStore.instance.c2c('u1'), '备注A');
      expect(
        UserProfileLocalService.instance.readCached('u1')!.friendRemark,
        '备注A',
      );
    });

    test('no-op with empty owner', () async {
      FriendSyncService.instance.debugOwnerUserId = '';
      DisplayNameStore.instance.setC2C('u1', '已有名', notify: false);

      await FriendSyncService.instance.warmupC2cDisplayNamesFromLocalStore();

      // 未发生任何预热写入。
      expect(DisplayNameStore.instance.c2c('u1'), '已有名');
    });
  });

  group('warmup remark credibility', () {
    test('IM new B + local old A keeps B', () async {
      _putImFriend('u1', remark: 'B', nickname: '公开昵称');
      await FriendSyncService.instance.seedC2cDisplayNamesFromFriendRecords([
        _record('u1', remark: 'A', nickname: '公开昵称'),
      ]);
      expect(DisplayNameStore.instance.c2c('u1'), isNot('A'));
      expect(
        UserProfileLocalService.instance.readCached('u1')?.friendRemark,
        isNot('A'),
      );
      expect(FriendDisplayName.resolveC2C(userId: 'u1'), 'B');
    });

    test('conversation new B + local old A keeps B', () async {
      ChatSessionController.instance.ensureTabStoreBridgeAttached();
      await ChatSessionController.instance.applyConversationsFromStoreForTest(
        upserted: [_c2c('u1', showName: 'B')],
      );
      await FriendSyncService.instance.seedC2cDisplayNamesFromFriendRecords([
        _record('u1', remark: 'A', nickname: '公开昵称'),
      ]);
      expect(
        UserProfileLocalService.instance.readCached('u1')?.friendRemark,
        isNot('A'),
      );
      expect(
        FriendDisplayName.resolveC2C(
          userId: 'u1',
          conversationShowName: 'B',
        ),
        'B',
      );
    });

    test('hydrate also keeps IM B over local old A', () {
      _putImFriend('u1', remark: 'B', nickname: '公开昵称');
      UserProfileLocalService.instance.hydrateFromFriendRecords([
        _record('u1', remark: 'A', nickname: '公开昵称'),
      ]);
      expect(
        UserProfileLocalService.instance.readCached('u1')?.friendRemark,
        isNot('A'),
      );
      expect(FriendDisplayName.resolveC2C(userId: 'u1'), 'B');
    });

    test('no trusted display + local known A fills A', () async {
      await FriendSyncService.instance.seedC2cDisplayNamesFromFriendRecords([
        _record('u1', remark: 'A', nickname: '公开昵称'),
      ]);
      expect(DisplayNameStore.instance.c2c('u1'), 'A');
      expect(
        UserProfileLocalService.instance.readCached('u1')?.friendRemark,
        'A',
      );
      expect(FriendDisplayName.resolveC2C(userId: 'u1'), 'A');
    });

    test('Store old A + local known B corrects Store to B', () async {
      DisplayNameStore.instance.setC2C('u1', 'A', notify: false);
      await FriendSyncService.instance.seedC2cDisplayNamesFromFriendRecords([
        _record('u1', remark: 'B', nickname: '公开昵称'),
      ]);
      expect(DisplayNameStore.instance.c2c('u1'), 'B');
      expect(
        UserProfileLocalService.instance.readCached('u1')?.friendRemark,
        'B',
      );
      expect(FriendDisplayName.resolveC2C(userId: 'u1'), 'B');
    });

    test('Store/IM old A + local explicit clear does not resurrect A',
        () async {
      _putImFriend('u1', remark: 'A', nickname: '公开昵称');
      DisplayNameStore.instance.setC2C('u1', 'A', notify: false);
      await FriendSyncService.instance.seedC2cDisplayNamesFromFriendRecords([
        _record('u1', remark: '', nickname: '公开昵称'),
      ]);
      final cached = UserProfileLocalService.instance.readCached('u1');
      expect(cached?.friendRemark, '');
      expect(cached?.friendRemarkConfirmed, isTrue);
      expect(DisplayNameStore.instance.c2c('u1'), isNot('A'));
      expect(FriendDisplayName.resolveC2C(userId: 'u1'), isNot('A'));
    });

    test('hydrate explicit clear does not confirm old IM A', () {
      _putImFriend('u1', remark: 'A', nickname: '公开昵称');
      DisplayNameStore.instance.setC2C('u1', 'A', notify: false);
      UserProfileLocalService.instance.hydrateFromFriendRecords([
        _record('u1', remark: '', nickname: '公开昵称'),
      ]);
      final cached = UserProfileLocalService.instance.readCached('u1');
      expect(cached?.friendRemark, '');
      expect(cached?.friendRemarkConfirmed, isTrue);
      expect(FriendDisplayName.resolveC2C(userId: 'u1'), isNot('A'));
    });
  });
}
