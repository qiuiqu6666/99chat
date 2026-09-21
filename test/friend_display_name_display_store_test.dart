import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/models/user_profile_record.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_display_name.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';

void main() {
  tearDown(() {
    DisplayNameStore.instance.clear(notify: false);
  });

  group('DisplayNameStore.resolveImSyncShowName', () {
    test('non-empty IM remark always wins', () {
      expect(
        DisplayNameStore.resolveImSyncShowName(
          imRemark: '新备注',
          imNickName: '昵称',
          userID: 'u1',
          existingStoreName: '旧备注',
        ),
        '新备注',
      );
    });

    test('empty IM remark keeps existing store (no nick downgrade)', () {
      expect(
        DisplayNameStore.resolveImSyncShowName(
          imRemark: '',
          imNickName: '昵称',
          userID: 'u1',
          existingStoreName: '本地备注',
        ),
        isNull,
      );
    });

    test('empty store + empty remark does not fill nick', () {
      expect(
        DisplayNameStore.resolveImSyncShowName(
          imRemark: '',
          imNickName: '昵称',
          userID: 'u1',
          existingStoreName: null,
        ),
        isNull,
      );
    });

    test('empty remark and nick does not persist userID', () {
      expect(
        DisplayNameStore.resolveImSyncShowName(
          imRemark: '',
          imNickName: '',
          userID: 'u1',
          existingStoreName: null,
        ),
        isNull,
      );
      expect(
        DisplayNameStore.instance.applyImFriendShowName(
          userID: 'u1',
          imRemark: '',
          imNickName: '',
          notify: false,
        ),
        isFalse,
      );
      expect(DisplayNameStore.instance.c2c('u1'), isNull);
    });

    test('store equal to userID plus empty remark does not fill nick', () {
      expect(
        DisplayNameStore.resolveImSyncShowName(
          imRemark: '',
          imNickName: '张三',
          userID: 'u1',
          existingStoreName: 'u1',
        ),
        isNull,
      );
    });

    test('setC2C rejects userID as display name', () {
      DisplayNameStore.instance.setC2C('alice', 'alice', notify: false);
      expect(DisplayNameStore.instance.c2c('alice'), isNull);
      DisplayNameStore.instance.setC2C('alice', '张三', notify: false);
      expect(DisplayNameStore.instance.c2c('alice'), '张三');
      DisplayNameStore.instance.setC2C('alice', 'alice', notify: false);
      expect(DisplayNameStore.instance.c2c('alice'), isNull);
      expect(DisplayNameStore.instance.snapshotC2C().containsKey('alice'), isFalse);
    });

    test('applyImFriendShowName does not overwrite existing with nick', () {
      DisplayNameStore.instance.setC2C('u1', '本地备注', notify: false);
      final changed = DisplayNameStore.instance.applyImFriendShowName(
        userID: 'u1',
        imRemark: '',
        imNickName: '昵称',
        notify: false,
      );
      expect(changed, isFalse);
      expect(DisplayNameStore.instance.c2c('u1'), '本地备注');
    });
  });

  group('FriendDisplayName.resolveC2C', () {
    test('prefers DisplayNameStore over friendRemark', () {
      DisplayNameStore.instance.setC2C('alice', 'Store备注', notify: false);
      final friend = V2TimFriendInfo(
        userID: 'alice',
        friendRemark: '旧备注',
        userProfile: V2TimUserFullInfo(userID: 'alice', nickName: '昵称'),
      );
      expect(
        FriendDisplayName.resolveC2C(
          userId: 'alice',
          conversationShowName: '会话名',
          friendList: <V2TimFriendInfo>[friend],
        ),
        'Store备注',
      );
    });

    test('falls back to friendRemark when Store empty', () {
      final friend = V2TimFriendInfo(
        userID: 'bob',
        friendRemark: '好友备注',
        userProfile: V2TimUserFullInfo(userID: 'bob', nickName: '昵称'),
      );
      expect(
        FriendDisplayName.resolveC2C(
          userId: 'bob',
          conversationShowName: '会话名',
          friendList: <V2TimFriendInfo>[friend],
        ),
        '好友备注',
      );
    });

    test('insurance: store equals nick while friend has remark → remark', () {
      DisplayNameStore.instance.setC2C('carol', '昵称X', notify: false);
      final friend = V2TimFriendInfo(
        userID: 'carol',
        friendRemark: '备注X',
        userProfile: V2TimUserFullInfo(userID: 'carol', nickName: '昵称X'),
      );
      expect(
        FriendDisplayName.resolveC2C(
          userId: 'carol',
          conversationShowName: '会话名',
          friendList: <V2TimFriendInfo>[friend],
        ),
        '备注X',
      );
    });

    test('local nickname does not beat Store remark', () {
      DisplayNameStore.instance.setC2C('dave', 'Store备注', notify: false);
      expect(
        FriendDisplayName.resolveLocalFirst(
          localProfile: UserProfileRecord(userId: 'dave', nickname: '公开昵称'),
          userId: 'dave',
          conversationShowName: '会话名',
        ),
        'Store备注',
      );
      expect(
        FriendDisplayName.resolveC2C(
          userId: 'dave',
          conversationShowName: '会话名',
        ),
        'Store备注',
      );
    });

    test('local nickname does not beat IM friend remark', () {
      final friend = V2TimFriendInfo(
        userID: 'erin',
        friendRemark: '好友备注',
        userProfile: V2TimUserFullInfo(userID: 'erin', nickName: '昵称'),
      );
      expect(
        FriendDisplayName.resolveLocalFirst(
          localProfile: UserProfileRecord(userId: 'erin', nickname: '昵称'),
          userId: 'erin',
          conversationShowName: '会话名',
          friendList: <V2TimFriendInfo>[friend],
        ),
        '好友备注',
      );
    });

    test('resolveLocalFirst matches resolveC2C when Store has remark', () {
      DisplayNameStore.instance.setC2C('frank', 'Store备注', notify: false);
      const conversation = '会话名';
      expect(
        FriendDisplayName.resolveLocalFirst(
          localProfile: UserProfileRecord(userId: 'frank', nickname: '昵称'),
          userId: 'frank',
          conversationShowName: conversation,
        ),
        FriendDisplayName.resolveC2C(
          userId: 'frank',
          conversationShowName: conversation,
        ),
      );
    });

    test('store nick does not beat conversation remark', () {
      DisplayNameStore.instance.setC2C('gina', '公开昵称', notify: false);
      expect(
        FriendDisplayName.resolveLocalFirst(
          localProfile: UserProfileRecord(userId: 'gina', nickname: '公开昵称'),
          userId: 'gina',
          conversationShowName: '好友备注',
        ),
        '好友备注',
      );
    });
  });

  group('FriendDisplayName.resolveFriendRemark', () {
    test('local nonempty remark wins over IM remark', () {
      expect(
        FriendDisplayName.resolveFriendRemark(
          localProfile: UserProfileRecord(
            userId: 'alice',
            friendRemark: '本地备注',
            nickname: '公开昵称',
          ),
          userId: 'alice',
          imRemark: 'IM备注',
        ),
        '本地备注',
      );
    });

    test('falls back to IM remark when local remark empty', () {
      expect(
        FriendDisplayName.resolveFriendRemark(
          localProfile: UserProfileRecord(
            userId: 'bob',
            nickname: '公开昵称',
          ),
          userId: 'bob',
          imRemark: 'IM备注',
        ),
        'IM备注',
      );
    });

    test('falls back to friendList remark when local and IM empty', () {
      final friend = V2TimFriendInfo(
        userID: 'carol',
        friendRemark: '好友列表备注',
        userProfile: V2TimUserFullInfo(userID: 'carol', nickName: '昵称'),
      );
      expect(
        FriendDisplayName.resolveFriendRemark(
          localProfile: UserProfileRecord(
            userId: 'carol',
            nickname: '公开昵称',
          ),
          userId: 'carol',
          imRemark: '',
          friendList: <V2TimFriendInfo>[friend],
        ),
        '好友列表备注',
      );
    });

    test('does not use DisplayNameStore or nickname as remark', () {
      DisplayNameStore.instance.setC2C('dave', 'Store展示名', notify: false);
      expect(
        FriendDisplayName.resolveFriendRemark(
          localProfile: UserProfileRecord(
            userId: 'dave',
            nickname: '公开昵称',
          ),
          userId: 'dave',
          imRemark: '',
        ),
        '',
      );
    });
  });
}
