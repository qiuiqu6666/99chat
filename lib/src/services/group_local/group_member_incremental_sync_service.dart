import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_group_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/sync_protocol_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_realtime_cursor_policy.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

/// 群成员不再走自建全量 / pending / Difference。
/// 本类只保留拒绝判定和 TCP 成员流游标，避免重复应用同一条 realtime seq。
class GroupMemberIncrementalSyncService {
  GroupMemberIncrementalSyncService._();

  static final GroupMemberIncrementalSyncService instance =
      GroupMemberIncrementalSyncService._();

  String _ownerUserId() {
    return ChatIdFormat.rawUserUid(ContactSocialCacheStore.safeLoginUserId());
  }

  /// Only explicit membership denial is terminal; generic 403/transport
  /// failures must not remove a group or discard its pending repair.
  static bool isMembershipDenied(Object error) =>
      (error is DioError &&
          MeGroupApi.readDioCode(error).trim().toUpperCase() ==
              'NOT_GROUP_MEMBER') ||
      (error is SyncProtocolException && error.code == 'NOT_GROUP_MEMBER') ||
      error is ImSdkGroupMembershipDenied;

  Future<int> readCursor({
    required String groupId,
    String? ownerUserId,
  }) async {
    final owner = (ownerUserId ?? _ownerUserId()).trim();
    final gid = ChatIdFormat.normalizeGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty) {
      return 0;
    }
    return GroupMemberLocalStore.instance.readIncrementalCursor(
      ownerUserId: owner,
      groupId: gid,
    );
  }

  Future<void> writeCursor(
    int seq, {
    required String groupId,
    String? ownerUserId,
  }) async {
    final owner = (ownerUserId ?? _ownerUserId()).trim();
    final gid = ChatIdFormat.normalizeGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty || seq < 0) {
      return;
    }
    await GroupMemberLocalStore.instance.advanceIncrementalCursor(
      ownerUserId: owner,
      groupId: gid,
      memberSeq: seq,
    );
  }

  Future<void> clearCursor({
    required String groupId,
    String? ownerUserId,
  }) async {
    final owner = (ownerUserId ?? _ownerUserId()).trim();
    final gid = ChatIdFormat.normalizeGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty) {
      return;
    }
    await GroupMemberLocalStore.instance.clearIncrementalCursor(
      ownerUserId: owner,
      groupId: gid,
    );
  }

  Future<void> clearSession() async {
    // Cursors live with their member rows in SQLite and are cleared by the
    // account lifecycle's GroupMemberLocalStore.clearForOwner call.
  }

  Future<bool> shouldApplyRealtimeSeq({
    required String groupId,
    required int seq,
  }) async {
    if (seq <= 0) {
      return true;
    }
    final current = await readCursor(groupId: groupId);
    return GroupMemberRealtimeCursorPolicy.shouldApply(
      cursor: current,
      seq: seq,
    );
  }

  /// TCP `detail.seq`（成员流）仅连续时前进游标，不再入队全量成员同步。
  Future<void> noteRealtimeSeq({
    required String groupId,
    required int seq,
  }) async {
    if (seq <= 0) {
      return;
    }
    final owner = _ownerUserId();
    final gid = ChatIdFormat.normalizeGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty) {
      return;
    }
    final current = await readCursor(groupId: gid, ownerUserId: owner);
    if (GroupMemberRealtimeCursorPolicy.shouldAdvance(
      cursor: current,
      seq: seq,
    )) {
      await writeCursor(seq, groupId: gid, ownerUserId: owner);
    }
  }
}
