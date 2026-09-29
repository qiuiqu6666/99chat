import 'package:tencent_cloud_chat_demo/src/models/user_profile_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/platform_official_account_service.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/group_display_resolver.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';

/// C2C 展示名：好友备注优先。未确认的空备注不是清空，公开昵称不得盖掉备注。
class FriendDisplayName {
  FriendDisplayName._();

  static final Expando<_FriendIndexSnapshot> _friendIndexCache =
      Expando<_FriendIndexSnapshot>();

  static String _friendLookupKey(String? input) {
    final trimmed = input?.trim() ?? '';
    if (trimmed.isEmpty) {
      return '';
    }
    // Normal C2C IDs are already canonical. Avoid the community-ID regex
    // chain for every visible row.
    if (!trimmed.startsWith('@') && !trimmed.contains('TGS#')) {
      return trimmed;
    }
    return ChatIdFormat.rawUserUid(trimmed);
  }

  static String fromFriend(V2TimFriendInfo item) {
    final remark = item.friendRemark?.trim() ?? '';
    if (remark.isNotEmpty) {
      return remark;
    }
    final nick = item.userProfile?.nickName?.trim() ?? '';
    if (nick.isNotEmpty) {
      return nick;
    }
    return item.userID;
  }

  static V2TimFriendInfo? findFriend(
    List<V2TimFriendInfo>? friendList,
    String? userId,
  ) {
    final id = _friendLookupKey(userId);
    if (id.isEmpty || friendList == null) {
      return null;
    }
    var snapshot = _friendIndexCache[friendList];
    if (snapshot == null || !snapshot.matches(friendList)) {
      final byId = <String, V2TimFriendInfo>{};
      for (final item in friendList) {
        final key = _friendLookupKey(item.userID);
        if (key.isNotEmpty) {
          byId[key] = item;
        }
      }
      snapshot = _FriendIndexSnapshot(
        length: friendList.length,
        first: friendList.isEmpty ? null : friendList.first,
        last: friendList.isEmpty ? null : friendList.last,
        byId: byId,
      );
      _friendIndexCache[friendList] = snapshot;
    }
    return snapshot.byId[id];
  }

  static String _resolveC2cShowName({
    UserProfileRecord? localProfile,
    String? userId,
    String? conversationShowName,
    List<V2TimFriendInfo>? friendList,
    String? imRemark,
    String? imNickName,
  }) {
    if (PlatformOfficialAccountService.prefersImProfileDisplayName(userId)) {
      return PlatformOfficialAccountService.resolveShowName(
        userId: userId,
        conversationShowName: conversationShowName,
      );
    }
    final lookupId = _friendLookupKey(userId);
    final local =
        UserProfileLocalService.instance.readCached(lookupId) ?? localProfile;
    final localRemark = local?.friendRemark.trim() ?? '';
    if (localRemark.isNotEmpty) {
      return localRemark;
    }

    final remarkConfirmed = local?.friendRemarkConfirmed == true;
    final localNickname = local?.nickname.trim() ?? '';
    final conversationName = conversationShowName?.trim() ?? '';
    final fromConversation = DisplayNameStore.isRawUserIdDisplayName(
      lookupId,
      conversationName,
    )
        ? ''
        : conversationName;
    final friend = findFriend(friendList, lookupId);
    final directory = ImSdkRelationshipDirectory.instance.friend(lookupId);
    final friendRemark = imRemark?.trim() ??
        friend?.friendRemark?.trim() ??
        directory?.remark ??
        '';
    final friendNick = imNickName?.trim() ??
        friend?.userProfile?.nickName?.trim() ??
        directory?.nickname ??
        '';
    final storeName = DisplayNameStore.instance.c2c(lookupId)?.trim() ?? '';

    String nicknameFallback() {
      if (localNickname.isNotEmpty) {
        return localNickname;
      }
      if (friendNick.isNotEmpty) {
        return friendNick;
      }
      if (remarkConfirmed) {
        return userId?.trim() ?? '';
      }
      if (fromConversation.isNotEmpty) {
        return fromConversation;
      }
      return userId?.trim() ?? '';
    }

    if (remarkConfirmed) {
      return nicknameFallback();
    }

    if (storeName.isNotEmpty) {
      if (friendRemark.isNotEmpty &&
          friendNick.isNotEmpty &&
          storeName == friendNick &&
          storeName != friendRemark) {
        return friendRemark;
      }
      if (localNickname.isNotEmpty &&
          storeName == localNickname &&
          fromConversation.isNotEmpty &&
          fromConversation != storeName &&
          !DisplayNameStore.isRawUserIdDisplayName(
            lookupId,
            fromConversation,
          )) {
        return fromConversation;
      }
      return storeName;
    }
    if (friendRemark.isNotEmpty) {
      return friendRemark;
    }
    if (fromConversation.isNotEmpty) {
      return fromConversation;
    }
    return nicknameFallback();
  }

  static String resolveC2C({
    String? userId,
    String? conversationShowName,
    List<V2TimFriendInfo>? friendList,
  }) {
    return _resolveC2cShowName(
      userId: userId,
      conversationShowName: conversationShowName,
      friendList: friendList,
    );
  }

  /// 与 [resolveC2C] 同一套备注优先顺序。
  static String resolveLocalFirst({
    UserProfileRecord? localProfile,
    String? userId,
    String? conversationShowName,
    List<V2TimFriendInfo>? friendList,
    String? imRemark,
    String? imNickName,
  }) {
    return _resolveC2cShowName(
      localProfile: localProfile,
      userId: userId,
      conversationShowName: conversationShowName,
      friendList: friendList,
      imRemark: imRemark,
      imNickName: imNickName,
    );
  }

  /// 资料页「备注名」行：只返回好友备注，不回退昵称或 DisplayNameStore。
  static String resolveFriendRemark({
    UserProfileRecord? localProfile,
    String? userId,
    String? imRemark,
    List<V2TimFriendInfo>? friendList,
  }) {
    final lookupId = _friendLookupKey(userId);
    final local =
        UserProfileLocalService.instance.readCached(lookupId) ?? localProfile;
    final localRemark = local?.friendRemark.trim() ?? '';
    final remarkConfirmed = local?.friendRemarkConfirmed == true;
    if (remarkConfirmed && localRemark.isEmpty) {
      return '';
    }
    if (localRemark.isNotEmpty) {
      return localRemark;
    }
    final fromIm = imRemark?.trim() ?? '';
    if (fromIm.isNotEmpty) {
      return fromIm;
    }
    final friendRemark =
        findFriend(friendList, lookupId)?.friendRemark?.trim() ?? '';
    if (friendRemark.isNotEmpty) {
      return friendRemark;
    }
    return '';
  }

  static String resolveConversation({
    required V2TimConversation conversation,
    List<V2TimFriendInfo>? friendList,
    Iterable<V2TimGroupInfo>? groupList,
    String? localGroupName,
    bool allowAliasFallback = true,
  }) {
    final groupId = conversation.groupID?.trim() ?? '';
    if (conversation.type == 2 || groupId.isNotEmpty) {
      return GroupDisplayResolver.resolveShowName(
        conversation: conversation,
        groupList: groupList,
        localGroupName: localGroupName,
        allowAliasFallback: allowAliasFallback,
      );
    }
    return resolveC2C(
      userId: conversation.userID,
      conversationShowName: conversation.showName,
      friendList: friendList,
    );
  }
}

class _FriendIndexSnapshot {
  const _FriendIndexSnapshot({
    required this.length,
    required this.first,
    required this.last,
    required this.byId,
  });

  final int length;
  final V2TimFriendInfo? first;
  final V2TimFriendInfo? last;
  final Map<String, V2TimFriendInfo> byId;

  bool matches(List<V2TimFriendInfo> list) {
    return list.length == length &&
        (list.isEmpty || identical(list.first, first)) &&
        (list.isEmpty || identical(list.last, last));
  }
}
