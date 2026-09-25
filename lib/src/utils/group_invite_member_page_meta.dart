import 'package:tencent_cloud_chat_demo/src/api/group_join_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_join_option.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/utils/group_join_application_approval.dart';
import 'package:tencent_cloud_chat_demo/src/utils/group_member_membership.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_application.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_application.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';

/// 「添加群成员」页：邀请审批提示 / 进群审核中 userId / 已在群成员禁选。
class GroupInviteMemberPageMeta {
  GroupInviteMemberPageMeta._();

  static Future<bool> inviteNeedsApproval(String groupId) async {
    final id = groupId.trim();
    if (id.isEmpty) {
      return false;
    }
    try {
      final options = await GroupJoinApi.instance.fetchJoinOptions(id);
      return options.inviteJoinOption == GroupJoinOption.needPermission;
    } catch (_) {
      return false;
    }
  }

  /// 当前联系人里已在群的 userId（IM 定点 `getGroupMembersInfo`），供邀请选人禁选。
  ///
  /// 按候选好友查成员身份，不抽干群成员分页。
  static Future<Set<String>> existingMemberUserIds(
    String groupId, {
    required Iterable<String> candidateUserIds,
  }) async {
    final id = groupId.trim();
    if (id.isEmpty) {
      return const <String>{};
    }
    final candidates = <String>{
      for (final raw in candidateUserIds)
        ChatIdFormat.rawUserUid(raw),
    }..removeWhere((uid) => uid.isEmpty);
    if (candidates.isEmpty) {
      return const <String>{};
    }
    final res = await GroupMembershipSyncService.instance.loadGroupMembersInfo(
      groupID: id,
      memberList: candidates.toList(growable: false),
      refresh: true,
    );
    if (res.code != 0 || res.data == null) {
      throw StateError('Unable to verify group membership: ${res.desc}');
    }
    return memberUserIdsFromLookup(res.data!);
  }

  static Set<String> memberUserIdsFromLookup(
    Iterable<V2TimGroupMemberFullInfo?> found,
  ) {
    final out = <String>{};
    for (final member in found) {
      if (!isConfirmedGroupMemberRole(member?.role)) continue;
      final uid = ChatIdFormat.rawUserUid(member?.userID);
      if (uid.isNotEmpty) {
        out.add(uid);
      }
    }
    return out;
  }

  /// 优先使用 `GET /group/{id}/pending-invitees`（任意成员可读）。
  static Future<Set<String>> pendingReviewUserIds(
    String groupId, {
    Set<String> memberUserIds = const <String>{},
  }) async {
    final id = groupId.trim();
    if (id.isEmpty) {
      return const <String>{};
    }

    final pending = <String>{};
    try {
      final userIds = await GroupJoinApi.instance.fetchPendingInvitees(id);
      pending.addAll(userIds);
    } catch (_) {}

    final members = memberUserIds
        .map(ChatIdFormat.rawUserUid)
        .where((item) => item.isNotEmpty)
        .toSet();
    pending.removeWhere(members.contains);
    return pending;
  }

  static Set<String> collectPendingInviteeUserIds({
    required List<V2TimGroupApplication> applications,
    required String groupId,
  }) {
    return _collectInviteeUserIds(
      applications: applications,
      groupId: groupId,
      pendingOnly: true,
    );
  }

  static Set<String> collectHandledInviteeUserIds({
    required List<V2TimGroupApplication> applications,
    required String groupId,
  }) {
    return _collectInviteeUserIds(
      applications: applications,
      groupId: groupId,
      pendingOnly: false,
    );
  }

  static Set<String> _collectInviteeUserIds({
    required List<V2TimGroupApplication> applications,
    required String groupId,
    required bool pendingOnly,
  }) {
    final targetGroup = ChatIdFormat.normalizeGroupId(groupId);
    final result = <String>{};
    for (final application in applications) {
      final isPending = groupJoinApplicationIsPending(application);
      if (pendingOnly ? !isPending : isPending) {
        continue;
      }
      final appGroup = ChatIdFormat.normalizeGroupId(application.groupID);
      if (appGroup.isEmpty ||
          (appGroup != targetGroup && application.groupID.trim() != groupId)) {
        continue;
      }
      final invitee = groupJoinApplicationIsInviteType(application)
          ? (application.toUser?.trim().isNotEmpty == true
              ? application.toUser!
              : (application.fromUser ?? ''))
          : (application.fromUser ?? '');
      final uid = ChatIdFormat.rawUserUid(invitee);
      if (uid.isNotEmpty) {
        result.add(uid);
      }
    }
    return result;
  }
}
