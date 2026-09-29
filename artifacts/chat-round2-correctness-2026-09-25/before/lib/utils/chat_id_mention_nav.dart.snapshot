import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/api/user_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_join_source.dart';
import 'package:tencent_cloud_chat_demo/src/pages/join_group_application_page.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_hud.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_mention_local_lookup.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_add_source.dart';
import 'package:tencent_cloud_chat_demo/utils/group_at_mention.dart';
import 'package:tencent_cloud_chat_demo/utils/group_join_lookup.dart';
import 'package:tencent_cloud_chat_demo/utils/group_privacy_guard.dart';
import 'package:tencent_cloud_chat_demo/utils/navigation_routes.dart';
import 'package:tencent_cloud_chat_demo/utils/profile_page_nav.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/profile/user_profile_local_bridge.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';

/// 点击消息中的 UID / 群别名：先查本地成员关系，未命中再按 UID 拉资料。
class ChatIdMentionNavigator {
  ChatIdMentionNavigator._();

  static String userOrGroupNotFoundMessage(AppI18n i18n) {
    return i18n.t(
      zhHans: '该用户或群聊不存在',
      zhHant: '該用戶或群聊不存在',
      en: 'This user or group chat does not exist',
      ja: 'このユーザーまたはグループチャットは存在しません',
      ko: '해당 사용자 또는 그룹 채팅이 존재하지 않습니다',
    );
  }

  static bool isUsablePublicNickname(String userId, String? name) {
    final text = name?.trim() ?? '';
    return text.isNotEmpty &&
        !DisplayNameStore.isRawUserIdDisplayName(userId, text);
  }

  static ({String? nickname, String? faceUrl}) localGroupMemberPublicProfile({
    required String groupId,
    required String userId,
    List<V2TimGroupMemberFullInfo> chatMembers = const [],
  }) {
    final id = ChatIdFormat.rawUserUid(userId);
    if (id.isEmpty) {
      return (nickname: null, faceUrl: null);
    }
    V2TimGroupMemberFullInfo? member;
    for (final item in chatMembers) {
      if (ChatIdFormat.rawUserUid(item.userID) == id) {
        member = item;
        break;
      }
    }
    member ??= GroupMemberStore.instance.memberOf(groupId, id);
    final shown = groupMemberAtShowName(
      member ?? V2TimGroupMemberFullInfo(userID: id),
    );
    final nickname =
        isUsablePublicNickname(id, shown) ? shown.trim() : null;
    final memberFace = member?.faceUrl?.trim() ?? '';
    final cachedFace = UserProfileLocalBridge.cachedAvatarUrl(id).trim();
    final faceUrl = memberFace.isNotEmpty
        ? memberFace
        : (cachedFace.isEmpty ? null : cachedFace);
    return (nickname: nickname, faceUrl: faceUrl);
  }

  static Future<void> open(
    BuildContext context,
    String mention, {
    String? groupMemberUserId,
    String? groupMemberNickname,
    String? groupMemberAvatarUrl,
    String? groupId,
    void Function(V2TimConversation conversation)? directToChat,
  }) async {
    final trimmed = mention.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final hud = AppHud.begin();
    try {
      final gid = groupId?.trim() ?? '';
      final memberUserId = groupMemberUserId?.trim() ?? '';
      if (gid.isNotEmpty) {
        await _openGroupChatMention(
          context,
          mention: trimmed,
          groupId: gid,
          groupMemberUserId: memberUserId,
          groupMemberNickname: groupMemberNickname,
          groupMemberAvatarUrl: groupMemberAvatarUrl,
          directToChat: directToChat,
        );
        return;
      }

      if (memberUserId.isNotEmpty) {
        if (ProfilePageNav.isSelfUser(memberUserId)) {
          await ProfilePageNav.openMyProfileDetail(context);
          return;
        }
        if (!context.mounted) {
          return;
        }
        await ProfilePageNav.openUserProfileOrAddFriend(
          context,
          userID: memberUserId,
          nickname: groupMemberNickname,
          avatarUrl: groupMemberAvatarUrl,
          addSource: FriendAddSource.chat,
          useLocalMentionData: true,
        );
        return;
      }

      final normalized = ChatIdFormat.normalizeSearchKeyword(trimmed);
      if (ChatIdFormat.isIMGroupOrCommunityId(trimmed) ||
          normalized.toUpperCase().contains('TGS#')) {
        final groupKey = normalized.isNotEmpty
            ? ChatIdFormat.canonicalGroupStorageId(normalized)
            : ChatIdFormat.canonicalGroupStorageId(trimmed);
        await _openJoinGroupPage(
          context,
          groupKey.isNotEmpty ? groupKey : trimmed,
          directToChat: directToChat,
        );
        return;
      }

      final id = ChatIdFormat.rawUserUid(
        trimmed.startsWith('@') ? trimmed : '@$trimmed',
      );
      if (id.isEmpty) {
        await AppHud.settleActive();
        if (!context.mounted) return;
        ToastUtils.toast(userOrGroupNotFoundMessage(AppI18n.of(context)));
        return;
      }

      if (ProfilePageNav.isSelfUser(id)) {
        await ProfilePageNav.openMyProfileDetail(context);
        return;
      }

      final friend = await ChatMentionLocalLookup.friend(id);
      if (!context.mounted) return;
      if (friend != null) {
        await ProfilePageNav.openUserProfileOrAddFriend(
          context,
          userID: friend.userID,
          nickname: friend.userProfile?.nickName,
          avatarUrl: friend.userProfile?.faceUrl,
          addSource: FriendAddSource.chat,
          useLocalMentionData: true,
        );
        return;
      }
      final localGroup = await ChatMentionLocalLookup.joinedGroup(trimmed);
      if (!context.mounted) return;
      if (localGroup != null) {
        await _openJoinGroupPage(context, trimmed,
            localGroup: localGroup, directToChat: directToChat);
        return;
      }

      final userResolve = await _resolveExistingUserId(id);
      if (userResolve.userId != null) {
        if (!context.mounted) {
          return;
        }
        await ProfilePageNav.openUserProfileOrAddFriend(
          context,
          userID: userResolve.userId!,
          nickname: userResolve.nickname,
          avatarUrl: userResolve.avatarUrl,
          lastActiveAt: userResolve.lastActiveAt,
          lastActiveVisibility: userResolve.lastActiveVisibility,
          addSource: groupId != null && groupId.trim().isNotEmpty
              ? FriendAddSource.card
              : FriendAddSource.chat,
          groupId: groupId,
        );
        return;
      }
      if (!userResolve.tryGroup) {
        return;
      }
      if (!context.mounted) return;

      await _openJoinGroupPage(
        context,
        id,
        directToChat: directToChat,
        userOrGroupAmbiguous: true,
      );
    } finally {
      await hud.end();
    }
  }

  /// 群聊点 @：走群隐私保护 + 资料/加好友，绝不走搜好友。
  static Future<void> _openGroupChatMention(
    BuildContext context, {
    required String mention,
    required String groupId,
    required String groupMemberUserId,
    String? groupMemberNickname,
    String? groupMemberAvatarUrl,
    void Function(V2TimConversation conversation)? directToChat,
  }) async {
    if (GroupAtMention.isAtAllToken(mention) ||
        GroupAtMention.isAtAllToken(groupMemberUserId)) {
      return;
    }

    if (groupMemberUserId.isNotEmpty) {
      await _openResolvedGroupMember(
        context,
        mention: mention,
        groupId: groupId,
        groupMemberUserId: groupMemberUserId,
        groupMemberNickname: groupMemberNickname,
        groupMemberAvatarUrl: groupMemberAvatarUrl,
      );
      return;
    }

    if (ChatIdFormat.isIMGroupOrCommunityId(mention) ||
        mention.toUpperCase().contains('TGS#')) {
      await _openJoinGroupPage(context, mention, directToChat: directToChat);
      return;
    }

    final resolved = GroupAtMention.resolveInGroup(
      groupId: groupId,
      chatMembers: const [],
      mentionToken: mention,
    );
    if (groupMemberUserId.isEmpty && resolved == null) {
      final localGroup = await ChatMentionLocalLookup.joinedGroup(mention);
      if (!context.mounted) return;
      if (localGroup != null) {
        await _openJoinGroupPage(context, mention,
            localGroup: localGroup, directToChat: directToChat);
        return;
      }
    }
    var userId = groupMemberUserId.isNotEmpty
        ? groupMemberUserId
        : (resolved?.userID ?? '');
    if (userId.isEmpty) {
      final asUid = ChatIdFormat.rawUserUid(mention);
      if (ChatIdFormat.isUserUidToken(asUid)) {
        userId = asUid;
      }
    }
    final nickname = (groupMemberNickname?.trim().isNotEmpty ?? false)
        ? groupMemberNickname
        : resolved?.displayName;
    final avatarUrl = (groupMemberAvatarUrl?.trim().isNotEmpty ?? false)
        ? groupMemberAvatarUrl
        : resolved?.faceUrl;

    if (userId.isNotEmpty && ProfilePageNav.isSelfUser(userId)) {
      await ProfilePageNav.openMyProfileDetail(context);
      return;
    }

    if (userId.isEmpty) {
      final blocked = await GroupPrivacyGuard.blockedGroupProfileHint(
        groupId: groupId,
      );
      if (!context.mounted) {
        return;
      }
      await AppHud.settleActive();
      if (!context.mounted) return;
      ToastUtils.toast(
        blocked ??
            AppI18n.of(context).t(
              zhHans: '无法查看该用户信息',
              zhHant: '無法查看該用戶資訊',
              en: 'Unable to view this user',
              ja: 'このユーザー情報を表示できません',
              ko: '이 사용자 정보를 볼 수 없습니다',
            ),
      );
      return;
    }

    if (!context.mounted) {
      return;
    }
    final localFriend = await ChatMentionLocalLookup.friend(userId);
    if (!context.mounted) return;
    final isManager =
        await GroupPrivacyGuard.isCurrentUserGroupManager(groupId);
    if (!context.mounted) return;
    if (isManager &&
        await _isMemberInGroup(groupId: groupId, userId: userId)) {
      if (!context.mounted) return;
      await ProfilePageNav.openUserProfile(
        context,
        userID: userId,
        addSource: FriendAddSource.card,
        initialAvatarUrl: avatarUrl,
        groupId: groupId,
      );
      return;
    }
    if (!context.mounted) return;
    await ProfilePageNav.openUserProfileOrAddFriend(
      context,
      userID: userId,
      nickname: nickname,
      avatarUrl: avatarUrl,
      addSource: FriendAddSource.card,
      groupId: groupId,
      useLocalMentionData: groupMemberUserId.isNotEmpty ||
          resolved != null || localFriend != null,
    );
  }

  static Future<void> _openResolvedGroupMember(
    BuildContext context, {
    required String mention,
    required String groupId,
    required String groupMemberUserId,
    String? groupMemberNickname,
    String? groupMemberAvatarUrl,
  }) async {
    final userId = groupMemberUserId.trim();
    if (userId.isEmpty) {
      return;
    }
    if (ProfilePageNav.isSelfUser(userId)) {
      await ProfilePageNav.openMyProfileDetail(context);
      return;
    }
    var nickname = groupMemberNickname?.trim();
    var avatarUrl = groupMemberAvatarUrl?.trim();
    if (!isUsablePublicNickname(userId, nickname)) {
      final local = localGroupMemberPublicProfile(
        groupId: groupId,
        userId: userId,
      );
      nickname = local.nickname;
      if (avatarUrl == null || avatarUrl.isEmpty) {
        avatarUrl = local.faceUrl;
      }
    }
    final localFriend = await ChatMentionLocalLookup.friend(userId);
    if (!context.mounted) return;
    final isManager =
        await GroupPrivacyGuard.isCurrentUserGroupManager(groupId);
    if (!context.mounted) return;
    if (isManager &&
        await _isMemberInGroup(groupId: groupId, userId: userId)) {
      if (!context.mounted) return;
      await ProfilePageNav.openUserProfile(
        context,
        userID: userId,
        addSource: FriendAddSource.card,
        initialAvatarUrl: avatarUrl,
        groupId: groupId,
      );
      return;
    }
    if (!context.mounted) return;
    await ProfilePageNav.openUserProfileOrAddFriend(
      context,
      userID: userId,
      nickname: nickname,
      avatarUrl: avatarUrl,
      addSource: FriendAddSource.card,
      groupId: groupId,
      useLocalMentionData: true,
    );
  }

  static Future<bool> _isMemberInGroup({
    required String groupId,
    required String userId,
  }) async {
    final id = ChatIdFormat.rawUserUid(userId);
    if (id.isEmpty) {
      return false;
    }
    if (GroupMemberStore.instance.memberOf(groupId, id) != null) {
      return true;
    }
    try {
      final res = await serviceLocator<GroupServices>().getGroupMembersInfo(
        groupID: groupId,
        memberList: [id],
      );
      final member = res.data?.isNotEmpty == true ? res.data!.first : null;
      if (member == null) {
        return false;
      }
      GroupMemberStore.instance.putMember(groupId, member, notify: false);
      return ChatIdFormat.rawUserUid(member.userID) == id;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _openJoinGroupPage(
    BuildContext context,
    String groupKey, {
    void Function(V2TimConversation conversation)? directToChat,
    bool userOrGroupAmbiguous = false,
    V2TimGroupInfo? localGroup,
  }) async {
    final joined = localGroup ??
        await ChatMentionLocalLookup.joinedGroup(groupKey);
    if (!context.mounted) return;
    V2TimGroupInfo? groupInfo = joined;
    try {
      groupInfo ??= await GroupJoinLookup.resolve(
        groupKey: groupKey,
        joinSource: GroupJoinSource.groupAlias,
      );
    } on GroupJoinLookupDisabledException catch (error) {
      if (!context.mounted) return;
      await AppHud.settleActive();
      if (!context.mounted) return;
      ToastUtils.toast(GroupJoinLookup.disabledMessage(
        AppI18n.of(context),
        error,
      ));
      return;
    }
    if (!context.mounted) return;
    if (groupInfo == null) {
      await AppHud.settleActive();
      if (!context.mounted) return;
      ToastUtils.toast(
        userOrGroupAmbiguous
            ? userOrGroupNotFoundMessage(AppI18n.of(context))
            : AppI18n.of(context).t(
                zhHans: '群聊不存在',
                zhHant: '群聊不存在',
                en: 'Group chat not found',
                ja: 'グループチャットが見つかりません',
                ko: '그룹 채팅을 찾을 수 없습니다',
              ),
      );
      return;
    }
    if (!context.mounted) {
      return;
    }
    final resolvedGroup = groupInfo;
    await AppHud.settleActive();
    if (!context.mounted) return;
    await Navigator.push(
      context,
      NavigationRoutes.cupertino(
        builder: (context) => JoinGroupApplicationPage(
          groupInfo: resolvedGroup,
          directToChat: directToChat,
          joinSource: GroupJoinSource.groupAlias,
          locallyJoined: joined != null,
        ),
      ),
    );
  }

  /// 通过 UID 拉公开资料确认用户存在。
  static Future<
      ({
        String? userId,
        String? nickname,
        String? avatarUrl,
        int? lastActiveAt,
        String? lastActiveVisibility,
        bool tryGroup,
      })> _resolveExistingUserId(String id) async {
    final hit = await UserApi.instance.tryFetchUserById(id);
    final userId = hit?.userId.trim() ?? '';
    if (hit == null || userId.isEmpty) {
      return (
        userId: null,
        nickname: null,
        avatarUrl: null,
        lastActiveAt: null,
        lastActiveVisibility: null,
        tryGroup: true,
      );
    }
    return (
      userId: userId,
      nickname: hit.nickname,
      avatarUrl: hit.avatarUrl,
      lastActiveAt: hit.lastActiveAt,
      lastActiveVisibility: hit.lastActiveVisibility,
      tryGroup: false,
    );
  }
}
