import 'package:tencent_cloud_chat_demo/src/api/me_group_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/group_member_join_meta.dart';

/// 资料页加载「入群时间 / 入群方式」成员记录。
class GroupMemberJoinMetaLoader {
  GroupMemberJoinMetaLoader._();

  /// 可见性不通过时返回 null；可见时返回本地（必要时补拉）记录。
  static Future<GroupMemberRecord?> loadVisible({
    required String groupId,
    required String userId,
  }) async {
    final gid = groupId.trim();
    final uid = ChatIdFormat.rawUserUid(userId);
    if (gid.isEmpty || uid.isEmpty) {
      return null;
    }
    final session = SessionIdentityService.instance;
    final identity = session.capture();
    if (!await GroupMemberJoinMeta.canView(groupId: gid)) {
      return null;
    }
    if (!session.isCurrent(identity)) return null;

    final store = GroupMemberLocalStore.instance;
    var record = await store.readRecord(
      groupId: gid,
      userId: uid,
      ownerUserId: identity.ownerUserId,
    );
    if (!session.isCurrent(identity)) return null;

    if (record == null || !GroupMemberJoinMeta.hasAnyDisplayRow(record)) {
      try {
        await GroupMembershipSyncService.instance.loadGroupMembersInfo(
          groupID: gid,
          memberList: <String>[uid],
        );
        if (!session.isCurrent(identity)) return null;
        record = await store.readRecord(
          groupId: gid,
          userId: uid,
          ownerUserId: identity.ownerUserId,
        );
      } catch (_) {
        // SDK 仅补入群时间；失败也继续查询业务邀请来源。
      }
    }
    if (!session.isCurrent(identity)) return null;
    if (record != null &&
        (record.joinChannel == GroupMemberJoinMeta.joinChannelGroupId ||
            GroupMemberJoinMeta.inviterDisplayName(record) != null)) {
      return record;
    }

    // 有入群时间不代表邀请来源完整。只查目标成员，不拉成员列表。
    try {
      final inviter = await MeGroupApi.instance.fetchGroupMemberInviter(
        groupId: gid,
        userId: uid,
      );
      if (!session.isCurrent(identity)) return null;
      final current = await store.readRecord(
        groupId: gid,
        userId: uid,
        ownerUserId: identity.ownerUserId,
      );
      if (!session.isCurrent(identity)) return null;
      record = current?.copyWith(
            invitedByUserId: inviter.invitedByUserId,
            invitedByNickname: inviter.invitedByNickname,
            joinChannel: inviter.joinChannel,
          ) ??
          inviter;
      // 邀请接口不是完整成员快照；无本地成员时仅展示，不新增残缺记录。
      if (current != null) {
        await store.upsertMany(
          ownerUserId: identity.ownerUserId,
          groupId: gid,
          records: <GroupMemberRecord>[record],
        );
      }
    } catch (_) {
      // 无权限、目标已退群或网络失败时，保留已有的入群时间。
    }
    return session.isCurrent(identity) ? record : null;
  }
}
