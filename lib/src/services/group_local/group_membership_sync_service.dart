import 'dart:async';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_removal_work.dart';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/constants/group_governance_limits.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_incremental_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_join_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_group_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime/friend_realtime_event.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_leave_diag_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_governance_trace.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_history_warm_scheduler.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_tips_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_tip_custom_sender.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_role_pending.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_self_involvement.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/my_group_list_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lock_profile_log.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_filter_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_role.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_info_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/utils/group_conversation_visibility.dart';
import 'package:tencent_cloud_chat_demo/src/utils/group_tip_custom_message.dart';
import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';
import 'package:tencent_cloud_chat_demo/utils/group_display_resolver.dart';
import 'package:tencent_cloud_chat_demo/utils/group_tips_message_helper.dart';
import 'package:tencent_cloud_chat_demo/utils/object_url_normalize.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/listener_model/tui_group_listener_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_conversation_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/conversation/conversation_services.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_search_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/self_hosted_group_bridge.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/archive_history_provider.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/group_role_policy.dart';

/// IMSDK 明确表示不在群 / 群不存在。
class ImSdkGroupMembershipDenied implements Exception {
  const ImSdkGroupMembershipDenied(this.groupId, this.code);

  final String groupId;
  final int code;

  @override
  String toString() => 'ImSdkGroupMembershipDenied($groupId, $code)';
}

/// HTTP 全量 + TCP `group_changed` 增量，统一写入群本地库。
class GroupMembershipSyncService {
  final Set<String> _purgeInFlight = <String>{};
  final GroupRemovalWork _removalWork = GroupRemovalWork();
  GroupMembershipSyncService._();

  @visibleForTesting
  GroupMembershipSyncService.forTest({
    Future<V2TimValueCallback<List<V2TimGroupMemberFullInfo>>> Function(
            String, List<String>)?
        memberInfoLoader,
    Future<V2TimValueCallback<V2TimGroupMemberInfoResult>> Function(
            String, int, String, GroupMemberFilterTypeEnum)?
        memberPageLoader,
  })  : _memberInfoLoader = memberInfoLoader,
        _memberPageLoader = memberPageLoader;

  Future<V2TimValueCallback<List<V2TimGroupMemberFullInfo>>> Function(
      String, List<String>)? _memberInfoLoader;
  Future<V2TimValueCallback<V2TimGroupMemberInfoResult>> Function(
      String, int, String, GroupMemberFilterTypeEnum)? _memberPageLoader;

  static final GroupMembershipSyncService instance =
      GroupMembershipSyncService._();

  bool _installed = false;
  Future<void>? _syncInFlight;
  bool _syncInFlightRefresh = false;
  int _syncGeneration = 0;
  final Set<String> _explicitlyRemovedGroupKeys = <String>{};
  final Map<String, int> _snapshotMissingCounts = <String, int>{};
  static const int _snapshotMissingConfirmations = 3;
  final Set<String> _activeConversationEvidenceKeys = <String>{};

  @visibleForTesting
  static bool shouldRetainGroupFromSnapshotSafety({
    required bool explicitlyRemoved,
    required int consecutiveMissingSnapshots,
  }) {
    return !explicitlyRemoved &&
        consecutiveMissingSnapshots < _snapshotMissingConfirmations;
  }

  bool _groupListSyncedOnce = false;
  final Map<String, Future<void>> _groupDetailRefreshInFlight = {};
  final Map<String, bool> _groupDetailRefreshForcesRemote = {};
  // A successful metadata commit briefly suppresses duplicate non-forced
  // refreshes. Failed/empty/rejected requests never populate this map.
  final Map<String, int> _groupDetailLastSuccessAtMs = <String, int>{};
  final Map<String, Future<void>> _membershipSnapshotInFlight = {};
  final Map<String, int> _membershipSnapshotCooldownUntilMs = <String, int>{};
  final Map<String, Future<V2TimValueCallback<V2TimGroupMemberInfoResult>>>
      _groupMemberPageInFlight = {};
  final Set<String> _inboundDisplayTipKeys = <String>{};
  DateTime? _lastMeGroupsNetworkAt;
  Timer? _deferredSyncFullTimer;
  String? _deferredSyncFullReason;
  bool _deferredSyncFullRefresh = false;
  Timer? _revisionCoalesceTimer;
  bool _revisionCoalesceScheduled = false;
  Timer? _idleReconcileTimer;
  int _idleReconcileGeneration = 0;
  Timer? _groupListBackgroundSyncTimer;

  /// 对齐服务端 `/me/groups` 约 10s 短缓存：非 refresh 短时重复拉直接跳过。
  static const Duration _meGroupsNetworkCooldown = Duration(seconds: 10);

  /// A persisted row is reusable for UIKit even when the server deliberately
  /// returns an empty avatar or a zero member count. An identity-only row
  /// (including one whose alias is merely its own ID) still needs detail.
  @visibleForTesting
  static bool isReusableCachedGroupMetadata(MeGroupRecord record) {
    return record.updatedAt > 0 &&
        (record.groupType.trim().isNotEmpty ||
            record.groupName.trim().isNotEmpty ||
            record.memberCount > 0 ||
            record.avatarUrl.trim().isNotEmpty);
  }

  static bool _sameGroupMetadata(MeGroupRecord left, MeGroupRecord right) {
    return left.groupId == right.groupId &&
        left.groupType == right.groupType &&
        left.groupName == right.groupName &&
        left.displayAlias == right.displayAlias &&
        left.avatarUrl == right.avatarUrl &&
        left.avatarPreviewUrl == right.avatarPreviewUrl &&
        left.avatarVersion == right.avatarVersion &&
        left.notice == right.notice &&
        left.memberCount == right.memberCount &&
        left.myRole == right.myRole &&
        left.myNameCard == right.myNameCard &&
        left.joinedAt == right.joinedAt &&
        left.updatedAt == right.updatedAt &&
        left.ownerUserId == right.ownerUserId &&
        left.noticeUpdatedAt == right.noticeUpdatedAt &&
        left.noticeUpdatedBy == right.noticeUpdatedBy &&
        left.isAllMuted == right.isAllMuted &&
        left.gameEnabled == right.gameEnabled;
  }

  /// 已加群集合变更时递增，供消息列表重建过滤。
  final ValueNotifier<int> joinedGroupsRevision = ValueNotifier<int>(0);

  bool get hasSyncedGroupListOnce => _groupListSyncedOnce;

  bool isJoinedGroup(String groupId) {
    final id = ChatIdFormat.normalizeGroupId(groupId);
    if (id.isEmpty) {
      return false;
    }
    return GroupLocalStore.instance.readCached(groupId: id) != null;
  }

  bool shouldShowConversation(V2TimConversation conversation) {
    return shouldShowConversationForMembership(
      conversation: conversation,
      // A SQLite count proves rows exist, not that readCached can decide
      // membership yet. Unknown cached membership must not hide SDK messages.
      groupListSyncedOnce:
          _groupListSyncedOnce && GroupLocalStore.instance.isOwnerFullyCached(),
      isJoinedGroup: isJoinedGroup,
      hasActiveConversationEvidence: (groupId) {
        final key = GroupLocalStore.groupEquivalenceKey(groupId);
        return key.isNotEmpty &&
            _activeConversationEvidenceKeys.contains(key) &&
            !_explicitlyRemovedGroupKeys.contains(key);
      },
      isExplicitlyRemoved: (groupId) {
        final key = GroupLocalStore.groupEquivalenceKey(groupId);
        return key.isNotEmpty && _explicitlyRemovedGroupKeys.contains(key);
      },
    );
  }

  bool isExplicitlyRemovedConversation(V2TimConversation conversation) {
    final groupId = resolveGroupIdFromConversation(
      conversationId: conversation.conversationID,
      groupId: conversation.groupID,
    );
    final key = GroupLocalStore.groupEquivalenceKey(groupId);
    return key.isNotEmpty && _explicitlyRemovedGroupKeys.contains(key);
  }

  bool isExplicitlyRemovedGroup(String groupId) => _explicitlyRemovedGroupKeys
      .contains(GroupLocalStore.groupEquivalenceKey(groupId));

  /// 用户已从 SDK 会话列表成功打开该群，说明它至少在本次会话中有效。
  ///
  /// `/me/groups` 首次快照可能受缓存或分页影响暂时缺群；在明确退群、被踢或
  /// 解散事件到达前，不能因此在返回列表时把刚打开的会话过滤掉。
  void noteActiveGroupConversation(V2TimConversation conversation) {
    if (!isGroupConversation(conversation)) {
      return;
    }
    final groupId = resolveGroupIdFromConversation(
      conversationId: conversation.conversationID,
      groupId: conversation.groupID,
    );
    final key = GroupLocalStore.groupEquivalenceKey(groupId);
    if (key.isEmpty || _explicitlyRemovedGroupKeys.contains(key)) {
      return;
    }
    _activeConversationEvidenceKeys.add(key);
    unawaited(refreshGroupDetail(groupId));
  }

  void _bumpJoinedGroupsRevision() {
    final coalesce = ConversationPerfFlags.joinedGroupsRevisionCoalesce;
    if (coalesce <= Duration.zero) {
      joinedGroupsRevision.value++;
      return;
    }
    _revisionCoalesceScheduled = true;
    _revisionCoalesceTimer?.cancel();
    _revisionCoalesceTimer = Timer(coalesce, () {
      _revisionCoalesceTimer = null;
      if (!_revisionCoalesceScheduled) {
        return;
      }
      _revisionCoalesceScheduled = false;
      joinedGroupsRevision.value++;
    });
  }

  // ignore: avoid_print
  static void _log(String message) {
    // Verbose sync tracing disabled.
  }

  void install() {
    if (_installed) {
      return;
    }
    _installed = true;
    // Older clients can deliver an invite through the native IM group
    // callback without emitting the app's TCP `group_changed` event.  Keep
    // the existing UIKit listener as the SDK boundary and bridge only the
    // callback that explicitly contains this account.
    TUIGroupListenerModelHooks.onMemberInvited = (
      groupId,
      _,
      members,
    ) {
      _handleSdkMembershipHint(
        groupId,
        members.map((member) => member.userID),
        reason: 'sdk_member_invited',
      );
    };
    TUIGroupListenerModelHooks.onMemberEnter = (groupId, members) {
      _handleSdkMembershipHint(
        groupId,
        members.map((member) => member.userID),
        reason: 'sdk_member_enter',
      );
    };
    TUIGroupListenerModelHooks.onGroupIdentityChanged = (
      groupId, {
      groupName,
      faceUrl,
    }) {
      unawaited(
        applySdkGroupIdentity(
          groupId: groupId,
          groupName: groupName,
          faceUrl: faceUrl,
        ),
      );
    };
    GroupMemberRolePending.instance.onReconcileDue = (groupId) {
      unawaited(_reconcilePendingMemberRoles(groupId));
    };
  }

  void _handleSdkMembershipHint(
    String groupId,
    Iterable<String?> memberUserIds, {
    required String reason,
  }) {
    final owner = _ownerUserId();
    final id = ChatIdFormat.normalizeGroupId(groupId);
    if (owner.isEmpty || id.isEmpty) {
      return;
    }
    if (isJoinedGroup(id)) {
      return;
    }
    final hasSelf = memberUserIds
        .map(ChatIdFormat.rawUserUid)
        .any((userId) => userId == owner);
    unawaited(
      _resolveSdkMembershipHint(
        groupId: id,
        hasSelfInCallback: hasSelf,
        reason: reason,
      ),
    );
  }

  Future<void> _resolveSdkMembershipHint({
    required String groupId,
    required bool hasSelfInCallback,
    required String reason,
  }) async {
    var isMember = hasSelfInCallback;
    if (!isMember) {
      // Native GroupTips callbacks may strip the current user from
      // `memberList`. Confirm membership through the SDK before admitting the
      // group, so an invite for someone else cannot create a local row.
      final owner = _ownerUserId();
      for (var attempt = 0; attempt < 3 && !isMember; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(
            Duration(milliseconds: attempt == 1 ? 250 : 750),
          );
        }
        for (final candidate in ChatIdFormat.imGroupIdCandidates(groupId)) {
          try {
            final result = await TencentImSDKPlugin.v2TIMManager
                .getGroupManager()
                .getGroupMembersInfo(
              groupID: candidate,
              memberList: <String>[owner],
            );
            if (result.code == 0 &&
                (result.data ?? const []).any(
                  (member) => ChatIdFormat.rawUserUid(member.userID) == owner,
                )) {
              isMember = true;
              break;
            }
          } catch (_) {
            // The next candidate may be the canonical @TGS# identifier.
          }
        }
      }
    }
    if (!isMember) {
      return;
    }
    await _admitSdkMembershipHint(groupId, reason: reason);
  }

  Future<void> _admitSdkMembershipHint(
    String groupId, {
    required String reason,
  }) async {
    try {
      await admitGroupMembershipFromImHint(
        groupId: groupId,
        groupName: '',
        avatarUrl: '',
      );
      // The optimized list is store-driven; the legacy UIKit group list still
      // needs an explicit reload after a new SDK-only membership callback.
      await refreshUIKitGroupList();
      SqfliteLockProfileLog.event(
        'sdk_membership_admitted',
        extras: <String, Object?>{'groupId': groupId, 'reason': reason},
      );
    } catch (error) {
      _log(
        'sdk membership admission failed groupId=$groupId '
        'reason=$reason error=$error',
      );
    }
  }

  String _ownerUserId() {
    return ChatIdFormat.rawUserUid(ContactSocialCacheStore.safeLoginUserId());
  }

  bool _isAnyGroupListOrConversationScrolling() {
    return MyGroupListController.instance.isScrolling ||
        (ChatSessionController.instance.isFeedScrolling?.call() ?? false);
  }

  /// 「我的群聊」进页：只刷新 IMSDK joined list，不再打 `/me/groups`。
  void scheduleGroupListBackgroundSync() {
    unawaited(refreshUIKitGroupList());
  }

  Future<List<V2TimGroupInfo>> loadJoinedGroupsForUIKit() async {
    final res = await TencentImSDKPlugin.v2TIMManager
        .getGroupManager()
        .getJoinedGroupList();
    if (res.code != 0) {
      _log(
        'loadJoinedGroupsForUIKit sdk failed code=${res.code} desc=${res.desc}',
      );
      return const <V2TimGroupInfo>[];
    }
    return res.data ?? const <V2TimGroupInfo>[];
  }

  MeGroupRecord? _existingRecordForSdkGroup(
    V2TimGroupInfo info,
    Map<String, MeGroupRecord> existingById,
    Map<String, MeGroupRecord> existingByEquivalentId,
  ) {
    final id = info.groupID.trim();
    if (id.isEmpty) return null;
    final direct = existingById[id];
    if (direct != null) return direct;
    final key = GroupLocalStore.groupEquivalenceKey(id);
    if (key.isEmpty) return null;
    return existingByEquivalentId[key];
  }

  /// `null` 表示 SDK 调用失败，调用方不得用空列表覆盖本地成员关系。
  Future<List<MeGroupRecord>?> _fetchJoinedGroupsFromImSdk({
    required Map<String, MeGroupRecord> existingById,
  }) async {
    final res = await TencentImSDKPlugin.v2TIMManager
        .getGroupManager()
        .getJoinedGroupList();
    if (res.code != 0) {
      _log(
        'getJoinedGroupList failed code=${res.code} desc=${res.desc}',
      );
      return null;
    }
    final existingByEquivalentId = <String, MeGroupRecord>{};
    for (final entry in existingById.entries) {
      final key = GroupLocalStore.groupEquivalenceKey(entry.key);
      if (key.isNotEmpty)
        existingByEquivalentId.putIfAbsent(key, () => entry.value);
    }
    final list = res.data ?? const <V2TimGroupInfo>[];
    return list
        .map(
          (info) => MeGroupRecord.fromV2TimGroupInfo(
            info,
            preserveFrom: _existingRecordForSdkGroup(
                info, existingById, existingByEquivalentId),
          ),
        )
        .toList(growable: false);
  }

  static bool _isImSdkNotGroupMemberCode(int code) {
    return code == 10007 || code == 10010 || code == 10013 || code == 6011;
  }

  Future<MeGroupRecord?> _fetchGroupDetailFromImSdk({
    required String groupId,
    MeGroupRecord? preserveFrom,
    bool throwIfDenied = false,
  }) async {
    final candidates = ChatIdFormat.imGroupIdCandidates(groupId);
    var deniedCode = 0;
    for (final id in candidates) {
      try {
        final res = await TencentImSDKPlugin.v2TIMManager
            .getGroupManager()
            .getGroupsInfo(groupIDList: <String>[id]);
        if (res.code != 0) {
          if (_isImSdkNotGroupMemberCode(res.code)) {
            deniedCode = res.code;
          }
          continue;
        }
        for (final item in res.data ?? const <V2TimGroupInfoResult>[]) {
          final resultCode = item.resultCode ?? 0;
          if (resultCode != 0) {
            if (_isImSdkNotGroupMemberCode(resultCode)) {
              deniedCode = resultCode;
            }
            continue;
          }
          final info = item.groupInfo;
          if (info == null) continue;
          return MeGroupRecord.fromV2TimGroupInfo(
            info,
            preserveFrom: preserveFrom,
          );
        }
      } catch (e) {
        _log('getGroupsInfo failed groupId=$id error=$e');
      }
    }
    if (throwIfDenied && deniedCode != 0) {
      throw ImSdkGroupMembershipDenied(groupId, deniedCode);
    }
    return null;
  }

  Future<MeGroupRecord?> fetchJoinedGroupFromImSdk(
    String groupId, {
    bool throwIfDenied = false,
  }) async {
    final current = await GroupLocalStore.instance.read(groupId: groupId);
    return _fetchGroupDetailFromImSdk(
      groupId: groupId,
      preserveFrom: current,
      throwIfDenied: throwIfDenied,
    );
  }

  Future<List<MeGroupRecord>> listJoinedGroupsFromImSdk({
    Map<String, MeGroupRecord> existingById = const <String, MeGroupRecord>{},
  }) async {
    return await _fetchJoinedGroupsFromImSdk(existingById: existingById) ??
        const <MeGroupRecord>[];
  }

  Future<List<V2TimGroupInfoResult>> loadGroupsInfoForUIKit(
    List<String> groupIDList,
  ) async {
    final owner = _ownerUserId();
    final identity =
        SessionIdentityService.instance.capture(ownerUserId: owner);
    final requestedIds =
        groupIDList.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final ids = <String>[];
    final seenIds = <String>{};
    for (final id in requestedIds) {
      if (seenIds.add(id)) ids.add(id);
    }
    if (requestedIds.isEmpty) {
      return const <V2TimGroupInfoResult>[];
    }
    List<V2TimGroupInfoResult> unavailable() => requestedIds
        .map(
          (_) => V2TimGroupInfoResult(
            resultCode: -1,
            resultMessage: 'GROUP_NOT_FOUND',
            groupInfo: null,
          ),
        )
        .toList(growable: false);
    bool isCurrent() => SessionIdentityService.instance.isCurrent(identity);
    if (!isCurrent()) return unavailable();
    final byId = <String, MeGroupRecord>{};
    final needsDetail = <String>{};
    for (final groupId in ids) {
      final cached = await GroupLocalStore.instance.read(
        groupId: groupId,
        ownerUserId: owner,
      );
      if (!isCurrent()) return unavailable();
      if (cached != null) {
        byId[groupId] = cached;
        if (isReusableCachedGroupMetadata(cached) &&
            MeGroupApi.instance.confirmedGroupDetail(groupId) != null) {
          unawaited(refreshGroupDetail(groupId));
          continue;
        }
      }
      // 会话误用 @TGS#_@TGS#m2… 时，按 displayAlias 找回 @TGS#_mc… 真源。
      final resolvedIm = await GroupLocalStore.instance.resolveImGroupId(
        groupId,
        ownerUserId: owner,
      );
      if (!isCurrent()) return unavailable();
      if (resolvedIm.isNotEmpty) {
        final byResolved = await GroupLocalStore.instance.read(
          groupId: resolvedIm,
          ownerUserId: owner,
        );
        if (!isCurrent()) return unavailable();
        if (byResolved != null) {
          byId[groupId] = byResolved;
          if (!isReusableCachedGroupMetadata(byResolved) ||
              MeGroupApi.instance.confirmedGroupDetail(groupId) == null) {
            needsDetail.add(groupId);
          } else {
            unawaited(refreshGroupDetail(groupId));
          }
          continue;
        }
      }
      needsDetail.add(groupId);
    }
    for (final groupId in needsDetail) {
      try {
        if (!isCurrent()) return unavailable();
        // Route this bridge through the keyed detail flight. This shares the
        // result with noteActiveGroupConversation/profile refresh callers.
        await refreshGroupDetail(groupId);
        if (!isCurrent()) return unavailable();
        final refreshed = await GroupLocalStore.instance.read(
          groupId: groupId,
          ownerUserId: owner,
        );
        if (!isCurrent()) return unavailable();
        if (refreshed != null) {
          byId[groupId] = refreshed;
        }
      } catch (e) {
        _log('fetchGroupDetail failed groupId=$groupId error=$e');
      }
    }
    if (!isCurrent()) return unavailable();
    return requestedIds.map((id) {
      final record = byId[id];
      if (record != null) {
        return record.toV2TimGroupInfoResult();
      }
      return V2TimGroupInfoResult(
        resultCode: -1,
        resultMessage: 'GROUP_NOT_FOUND',
        groupInfo: null,
      );
    }).toList(growable: false);
  }

  Future<V2TimValueCallback<V2TimGroupMemberInfoResult>> loadGroupMemberPage({
    required String groupID,
    required int count,
    required String nextSeq,
    GroupMemberFilterTypeEnum filter =
        GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ALL,
  }) async {
    final owner = _ownerUserId();
    final identity = SessionIdentityService.instance.capture();
    final offset = _parseOffset(
        nextSeq.startsWith('rest:') ? nextSeq.substring(5) : nextSeq);
    final limit = count.clamp(1, 100);
    final groupKey =
        ChatIdFormat.groupEquivalenceToken(groupID) ?? groupID.trim();
    final key =
        '$owner|${identity.generation}|$groupKey|$nextSeq|$limit|${filter.index}';
    final active = _groupMemberPageInFlight[key];
    if (active != null) {
      SqfliteLockProfileLog.event(
        'groupMemberPage_coalesced',
        extras: <String, Object?>{
          'groupId': groupID,
          'offset': offset,
          'limit': limit,
        },
      );
      return active;
    }
    late final Future<V2TimValueCallback<V2TimGroupMemberInfoResult>> tracked;
    tracked = _loadGroupMemberPageImpl(
      owner: owner,
      identity: identity,
      groupID: groupID,
      offset: offset,
      limit: limit,
      sdkNextSeq: nextSeq.trim().isEmpty ? '0' : nextSeq.trim(),
      filter: filter,
    )
        .then((result) => SessionIdentityService.instance.isCurrent(identity)
            ? result
            : V2TimValueCallback<V2TimGroupMemberInfoResult>(
                code: -1, desc: 'Account changed'))
        .whenComplete(() {
      if (identical(_groupMemberPageInFlight[key], tracked)) {
        _groupMemberPageInFlight.remove(key);
      }
    });
    _groupMemberPageInFlight[key] = tracked;
    return tracked;
  }

  Future<V2TimValueCallback<V2TimGroupMemberInfoResult>>
      _loadGroupMemberPageImpl({
    required String owner,
    required SessionIdentity identity,
    required String groupID,
    required int offset,
    required int limit,
    required String sdkNextSeq,
    required GroupMemberFilterTypeEnum filter,
  }) async {
    if (filter == GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_OWNER ||
        filter == GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ADMIN) {
      if (sdkNextSeq.startsWith('local:')) {
        return _loadLocalMemberPage(
            owner: owner,
            groupID: groupID,
            limit: limit,
            offset: int.tryParse(sdkNextSeq.substring(6)) ?? 0,
            filter: filter);
      }
      return _loadOwnerAdminMemberPageFromRest(
        owner: owner,
        identity: identity,
        groupID: groupID,
        offset: offset,
        limit: limit,
        filter: filter,
      );
    }
    try {
      // Prefix cursors so SDK cursors (including small integers) are never
      // interpreted as REST offsets, or switched to another source mid-list.
      if (sdkNextSeq.startsWith('local:')) {
        return _loadLocalMemberPage(
            owner: owner,
            groupID: groupID,
            limit: limit,
            offset: int.tryParse(sdkNextSeq.substring(6)) ?? 0,
            filter: filter);
      }
      final storageGroupId = ChatIdFormat.canonicalGroupStorageId(groupID);
      final localGroupId = storageGroupId.isNotEmpty ? storageGroupId : groupID;
      final sdkSeq = sdkNextSeq.startsWith('sdk:')
          ? sdkNextSeq.substring(4)
          : (sdkNextSeq.startsWith('rest:') ||
                  sdkNextSeq.isEmpty ||
                  sdkNextSeq == '0')
              ? '0'
              : sdkNextSeq;
      final sdkPage = await _loadGroupMemberPageFromImSdk(
        groupID: groupID,
        count: limit,
        nextSeq: sdkSeq,
        filter: filter,
      );
      if (sdkPage == null) {
        throw StateError('SDK member page unavailable');
      }
      if (_ownerUserId() != owner ||
          !SessionIdentityService.instance.isCurrent(identity)) {
        throw StateError('Account changed');
      }
      final members = sdkPage.data?.memberInfoList ?? const [];
      await GroupMemberLocalStore.instance.upsertMany(
        ownerUserId: owner,
        groupId: localGroupId,
        records: members
            .whereType<V2TimGroupMemberFullInfo>()
            .map(
              (member) => GroupMemberRecord.fromV2Tim(
                member,
                selfUserId: owner,
              ),
            )
            .toList(growable: false),
      );
      return sdkPage;
    } catch (e) {
      _log('loadGroupMemberPage failed groupId=$groupID error=$e');
      if (_ownerUserId() != owner ||
          !SessionIdentityService.instance.isCurrent(identity)) {
        return V2TimValueCallback(code: -1, desc: 'Account changed');
      }
      // Once paging starts, failures keep the existing cursor for a retry.
      final imFallback = offset <= 0 &&
              !sdkNextSeq.startsWith('sdk:') &&
              !GroupMemberIncrementalSyncService.isMembershipDenied(e)
          ? await _loadGroupMemberPageFromImSdk(
              groupID: groupID, count: limit, nextSeq: '0', filter: filter)
          : null;
      if (imFallback != null) {
        return imFallback;
      }
      if (sdkNextSeq == '0' &&
          !GroupMemberIncrementalSyncService.isMembershipDenied(e)) {
        final cached = await _loadLocalMemberPage(
            owner: owner,
            groupID: groupID,
            limit: limit,
            offset: 0,
            filter: filter);
        if (cached.data?.memberInfoList?.isNotEmpty == true) return cached;
      }
      return V2TimValueCallback(
        code: -1,
        desc: e.toString(),
        data: V2TimGroupMemberInfoResult(
          nextSeq: '0',
          memberInfoList: const [],
        ),
      );
    }
  }

  Future<V2TimValueCallback<V2TimGroupMemberInfoResult>>
      _loadOwnerAdminMemberPageFromRest({
    required String owner,
    required SessionIdentity identity,
    required String groupID,
    required int offset,
    required int limit,
    required GroupMemberFilterTypeEnum filter,
  }) async {
    final role = _restRoleForFilter(filter);
    if (role == null) {
      return _loadLocalMemberPage(
        owner: owner,
        groupID: groupID,
        limit: limit,
        offset: offset,
        filter: filter,
      );
    }
    try {
      final page = await MeGroupApi.instance.fetchGroupMembersPage(
        groupId: groupID,
        limit: limit,
        offset: offset,
        role: role,
      );
      if (_ownerUserId() != owner ||
          !SessionIdentityService.instance.isCurrent(identity)) {
        return V2TimValueCallback(code: -1, desc: 'Account changed');
      }
      final storageGroupId = ChatIdFormat.canonicalGroupStorageId(groupID);
      final localGroupId = storageGroupId.isNotEmpty ? storageGroupId : groupID;
      await GroupMemberLocalStore.instance.upsertMany(
        ownerUserId: owner,
        groupId: localGroupId,
        records: page.items,
      );
      final nextOffset = offset + page.items.length;
      final hasMore = page.hasMore ??
          (page.items.length >= limit &&
              (page.total <= 0 || nextOffset < page.total));
      final scoped = page.items.where((item) {
        if (filter == GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_OWNER) {
          return item.role == GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER;
        }
        if (filter == GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ADMIN) {
          return item.role == GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_ADMIN;
        }
        return true;
      });
      return V2TimValueCallback(
        code: 0,
        desc: 'ok',
        data: V2TimGroupMemberInfoResult(
          nextSeq: hasMore ? 'rest:$nextOffset' : '0',
          memberInfoList: scoped.map(_toV2TimMember).toList(),
        ),
      );
    } catch (e) {
      _log('loadOwnerAdminMemberPage failed groupId=$groupID error=$e');
      if (_ownerUserId() != owner ||
          !SessionIdentityService.instance.isCurrent(identity)) {
        return V2TimValueCallback(code: -1, desc: 'Account changed');
      }
      return _loadLocalMemberPage(
        owner: owner,
        groupID: groupID,
        limit: limit,
        offset: offset,
        filter: filter,
      );
    }
  }

  Future<V2TimValueCallback<V2TimGroupMemberInfoResult>> _loadLocalMemberPage({
    required String owner,
    required String groupID,
    required int limit,
    required int offset,
    required GroupMemberFilterTypeEnum filter,
  }) async {
    final rows = await GroupMemberLocalStore.instance.readWindow(
        groupId: groupID,
        ownerUserId: owner,
        limit: limit + 1,
        offset: offset,
        role: _localStoreRoleForFilter(filter));
    return V2TimValueCallback(
        code: 0,
        desc: 'cached_page',
        data: V2TimGroupMemberInfoResult(
            nextSeq: rows.length > limit ? 'local:${offset + limit}' : '0',
            memberInfoList: rows.take(limit).map(_toV2TimMember).toList()));
  }

  String? _restRoleForFilter(GroupMemberFilterTypeEnum filter) {
    switch (filter) {
      case GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_OWNER:
      case GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ADMIN:
        return GroupMembersRoleQuery.admins;
      case GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_COMMON:
        return GroupMembersRoleQuery.members;
      default:
        return null;
    }
  }

  int? _localStoreRoleForFilter(GroupMemberFilterTypeEnum filter) {
    switch (filter) {
      case GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_OWNER:
        return GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER;
      case GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ADMIN:
        return GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_ADMIN;
      case GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_COMMON:
        return GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER;
      default:
        return null;
    }
  }

  /// 国内腾讯云 IM：社群成员列表走 SDK `getGroupMemberList`。
  /// 群 ID 须与控制台一致（常见 `@TGS#_mc…`，或默认 `@TGS#_@TGS#…`）。
  Future<V2TimValueCallback<V2TimGroupMemberInfoResult>?>
      _loadGroupMemberPageFromImSdk({
    required String groupID,
    required int count,
    required String nextSeq,
    required GroupMemberFilterTypeEnum filter,
  }) async {
    final candidates = ChatIdFormat.imGroupIdCandidates(groupID);
    for (final imGroupId in candidates) {
      try {
        final res = _memberPageLoader != null
            ? await _memberPageLoader!(imGroupId, count, nextSeq, filter)
            : await TencentImSDKPlugin.v2TIMManager
                .getGroupManager()
                .getGroupMemberList(
                  groupID: imGroupId,
                  filter: filter,
                  nextSeq: nextSeq,
                  count: count.clamp(1, 100),
                );
        final members =
            (res.data?.memberInfoList ?? const <V2TimGroupMemberFullInfo>[])
                .where((member) => !GroupMemberStore.instance
                    .isRemovalTombstoned(groupID, member.userID))
                .toList();
        if (res.code == 0) {
          debugPrint(
            'GroupMembership: IM members ok id=$imGroupId '
            'count=${members.length} nextSeq=${res.data?.nextSeq ?? '0'}',
          );
          final cursor = res.data?.nextSeq ?? '0';
          return V2TimValueCallback(
              code: 0,
              desc: res.desc,
              data: V2TimGroupMemberInfoResult(
                  nextSeq:
                      cursor.isEmpty || cursor == '0' ? '0' : 'sdk:$cursor',
                  memberInfoList: members));
        }
        if (res.code != 0) {
          debugPrint(
            'GroupMembership: IM members fail id=$imGroupId code=${res.code} desc=${res.desc}',
          );
        }
      } catch (e) {
        debugPrint(
            'GroupMembership: IM members exception id=$imGroupId err=$e');
      }
    }
    return null;
  }

  final Map<String, Future<V2TimValueCallback<List<V2TimGroupMemberFullInfo>>>>
      _memberInfoInFlight = {};

  Future<V2TimValueCallback<List<V2TimGroupMemberFullInfo>>>
      loadGroupMembersInfo({
    required String groupID,
    required List<String> memberList,
    bool refresh = false,
  }) {
    final owner = _ownerUserId();
    final identity = SessionIdentityService.instance.capture();
    final ids = memberList
        .map(ChatIdFormat.rawUserUid)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final key =
        '$owner|${identity.generation}|${ChatIdFormat.canonicalGroupStorageId(groupID)}|$refresh|${ids.join(",")}';
    final active = _memberInfoInFlight[key];
    if (active != null) return active;
    late final Future<V2TimValueCallback<List<V2TimGroupMemberFullInfo>>> task;
    task =
        _loadRequestedMembers(owner, groupID, ids, identity, refresh: refresh)
            .whenComplete(() {
      if (identical(_memberInfoInFlight[key], task))
        _memberInfoInFlight.remove(key);
    });
    _memberInfoInFlight[key] = task;
    return task;
  }

  Future<V2TimValueCallback<List<V2TimGroupMemberFullInfo>>>
      _loadRequestedMembers(String owner, String groupID, List<String> ids,
          SessionIdentity identity,
          {bool refresh = false}) async {
    bool removed(String uid) =>
        GroupMemberStore.instance.isRemovalTombstoned(groupID, uid);
    ids = ids.where((id) => !removed(id)).toList();
    if (owner.isEmpty || ids.isEmpty) {
      return V2TimValueCallback(code: 0, desc: 'ok', data: []);
    }
    final cached = refresh
        ? <V2TimGroupMemberFullInfo>[]
        : await GroupMemberLocalStore.instance
            .readByUserIds(groupId: groupID, userIds: ids, ownerUserId: owner);
    final byId = {
      for (final member in cached)
        ChatIdFormat.rawUserUid(member.userID): member
    };
    final missing = ids.where((id) {
      final cached = byId[id];
      return cached == null ||
          ((cached.nickName?.trim().isEmpty ?? true) &&
              (cached.nameCard?.trim().isEmpty ?? true));
    }).toList();
    // The business API has no verified batch-by-ID endpoint. Use the SDK's
    // exact member lookup; never fetch arbitrary page 0 to resolve a sender.
    for (var start = 0; start < missing.length; start += 50) {
      final batch = missing.skip(start).take(50).toList();
      var resolvedBatch = false;
      for (final gid in ChatIdFormat.imGroupIdCandidates(groupID)) {
        if (_ownerUserId() != owner ||
            !SessionIdentityService.instance.isCurrent(identity))
          return V2TimValueCallback(code: -1, desc: 'Account changed');
        try {
          final response = _memberInfoLoader != null
              ? await _memberInfoLoader!(gid, batch)
              : await TencentImSDKPlugin.v2TIMManager
                  .getGroupManager()
                  .getGroupMembersInfo(groupID: gid, memberList: batch);
          if (_ownerUserId() != owner ||
              !SessionIdentityService.instance.isCurrent(identity))
            return V2TimValueCallback(code: -1, desc: 'Account changed');
          if (response.code != 0) continue;
          final found = (response.data ?? <V2TimGroupMemberFullInfo>[])
              .where((m) =>
                  batch.contains(ChatIdFormat.rawUserUid(m.userID)) &&
                  !removed(m.userID))
              .toList();
          final current = await GroupMemberLocalStore.instance
              .readRecordsByUserIds(
                  groupId: groupID, userIds: batch, ownerUserId: owner);
          final currentById = {for (final m in current) m.userId: m};
          if (!SessionIdentityService.instance.isCurrent(identity)) {
            return V2TimValueCallback(code: -1, desc: 'Account changed');
          }
          found.removeWhere((m) => removed(m.userID));
          await GroupMemberLocalStore.instance.upsertMany(
              ownerUserId: owner,
              groupId: groupID,
              records: found.map((m) {
                final existing = currentById[ChatIdFormat.rawUserUid(m.userID)];
                if (existing != null) {
                  // Fill a local shell's public display fields without
                  // replacing business role, mute, name-card or join data.
                  return existing.copyWith(
                      nickname: existing.nickname.isEmpty ? m.nickName : null,
                      avatarUrl: existing.avatarUrl.isEmpty ? m.faceUrl : null);
                }
                return GroupMemberRecord(
                    userId: ChatIdFormat.rawUserUid(m.userID),
                    nickname: m.nickName ?? '',
                    avatarUrl: m.faceUrl ?? '',
                    friendRemark: m.friendRemark ?? '',
                    nameCard: m.nameCard ?? '',
                    role: m.role ?? 200,
                    joinedAt: (m.joinTime ?? 0) * 1000,
                    isSelf: ChatIdFormat.rawUserUid(m.userID) == owner,
                    muteUntil: m.muteUntil ?? 0);
              }).toList());
          final resolved = await GroupMemberLocalStore.instance.readByUserIds(
              groupId: groupID, ownerUserId: owner, userIds: batch);
          if (!SessionIdentityService.instance.isCurrent(identity)) {
            return V2TimValueCallback(code: -1, desc: 'Account changed');
          }
          for (final m in resolved) {
            if (!removed(m.userID) &&
                (!refresh ||
                    found.any((f) =>
                        ChatIdFormat.rawUserUid(f.userID) ==
                        ChatIdFormat.rawUserUid(m.userID)))) {
              byId[ChatIdFormat.rawUserUid(m.userID)] = m;
            }
          }
          resolvedBatch = true;
          break;
        } catch (error) {
          _log('member lookup failed group=$groupID error=$error');
        }
      }
      if (refresh && !resolvedBatch) {
        return V2TimValueCallback(code: -1, desc: 'Member lookup failed');
      }
    }
    return V2TimValueCallback(
        code: 0,
        desc: 'ok',
        data: ids
            .where((id) => !removed(id))
            .map((id) => byId[id])
            .whereType<V2TimGroupMemberFullInfo>()
            .toList());
  }

  Future<V2TimCallback> updateGroupInfo({required V2TimGroupInfo info}) async {
    final groupId = info.groupID.trim();
    if (groupId.isEmpty) {
      return MeGroupApi.failureCallback('INVALID_INPUT');
    }
    final hasName = info.groupName != null;
    final hasNotice = info.notification != null;
    final hasAvatar = info.faceUrl != null && info.faceUrl!.trim().isNotEmpty;
    final hasMuteAll = info.isAllMuted != null;
    if (!hasName && !hasNotice && !hasAvatar && !hasMuteAll) {
      return MeGroupApi.successCallback();
    }
    if (hasMuteAll && !hasName && !hasNotice && !hasAvatar) {
      final res = await MeGroupApi.instance.muteAllMembers(
        groupId: groupId,
        shutUpAllMember: info.isAllMuted!,
      );
      if (res.code != 0) {
        return res;
      }
      await _patchGroupFields(
        owner: _ownerUserId(),
        groupId: groupId,
        isAllMuted: info.isAllMuted,
      );
      notifyProfileRefresh(groupId, memberList: true);
      unawaited(
        GroupTipCustomSender.instance.send(
          groupId: groupId,
          action: info.isAllMuted! ? 'group_mute_all_on' : 'group_mute_all_off',
          detail: <String, dynamic>{
            'shutUpAllMember': info.isAllMuted,
            'isAllMuted': info.isAllMuted,
          },
        ),
      );
      return MeGroupApi.successCallback();
    }
    if (hasAvatar && !hasName && !hasNotice && !hasMuteAll) {
      await applyOptimisticAvatar(
        groupId: groupId,
        avatarUrl: info.faceUrl!.trim(),
      );
      unawaited(
        GroupTipCustomSender.instance.send(
          groupId: groupId,
          action: 'group_avatar_changed',
          detail: <String, dynamic>{'avatarUrl': info.faceUrl!.trim()},
        ),
      );
      return MeGroupApi.successCallback();
    }
    final write = await MeGroupApi.instance.updateGroup(
      groupId: groupId,
      groupName: hasName ? info.groupName : null,
      notice: hasNotice ? info.notification : null,
    );
    if (!write.committed) {
      return MeGroupApi.failureCallback(
        write.errorCode.isNotEmpty ? write.errorCode : 'REQUEST_FAILED',
      );
    }
    try {
      final authoritative = write.group;
      if (authoritative != null && authoritative.groupId.trim().isNotEmpty) {
        final owner = _ownerUserId();
        if (owner.isNotEmpty) {
          final existing = await GroupLocalStore.instance.read(
            groupId: groupId,
            ownerUserId: owner,
          );
          await GroupLocalStore.instance.upsert(
            ownerUserId: owner,
            record: authoritative.resolvingMissingFieldsFrom(existing),
          );
        }
      }
      if (hasNotice) {
        // The profile renders the committed Store row. Publish the successful
        // edit (including an explicit clear) before any secondary SDK work.
        await applyOptimisticNotice(
          groupId: groupId,
          notice: info.notification!,
        );
      }
      if (hasName) {
        // REST has confirmed the edit. Publish to the open profile and chat
        // list now, before waiting for SDK synchronization or a remote read.
        await applyOptimisticGroupName(
          groupId: groupId,
          groupName: info.groupName ?? '',
        );
        await _syncIdentityToNativeSdk(
          groupId: groupId,
          groupName: info.groupName,
        );
      }
      // Identity is owned by IM SDK. Re-read getGroupsInfo after the native
      // set so memberCount and remaining fields enter the Store. The
      // confirmed name is re-applied after that snapshot so a stale
      // getGroupsInfo cannot leave the previous display name in the Store.
      if (hasName || hasAvatar || hasMuteAll) {
        await refreshGroupDetail(groupId, refresh: true);
      }
      if (hasName) {
        await applyOptimisticGroupName(
          groupId: groupId,
          groupName: info.groupName ?? '',
        );
        unawaited(
          GroupTipCustomSender.instance.send(
            groupId: groupId,
            action: 'group_name_changed',
            detail: <String, dynamic>{
              if (info.groupName != null) 'groupName': info.groupName,
            },
          ),
        );
      }
      if (hasNotice) {
        unawaited(
          GroupTipCustomSender.instance.send(
            groupId: groupId,
            action: 'group_notice_changed',
            detail: <String, dynamic>{
              if (info.notification != null) 'notice': info.notification,
            },
          ),
        );
      }
      if (hasAvatar) {
        await applyOptimisticAvatar(
          groupId: groupId,
          avatarUrl: info.faceUrl!.trim(),
        );
        unawaited(
          GroupTipCustomSender.instance.send(
            groupId: groupId,
            action: 'group_avatar_changed',
            detail: <String, dynamic>{'avatarUrl': info.faceUrl!.trim()},
          ),
        );
      }
      if (hasMuteAll) {
        final muteRes = await MeGroupApi.instance.muteAllMembers(
          groupId: groupId,
          shutUpAllMember: info.isAllMuted!,
        );
        if (muteRes.code != 0) {
          return muteRes;
        }
        await _patchGroupFields(
          owner: _ownerUserId(),
          groupId: groupId,
          isAllMuted: info.isAllMuted,
        );
        unawaited(
          GroupTipCustomSender.instance.send(
            groupId: groupId,
            action:
                info.isAllMuted! ? 'group_mute_all_on' : 'group_mute_all_off',
            detail: <String, dynamic>{
              'shutUpAllMember': info.isAllMuted,
              'isAllMuted': info.isAllMuted,
            },
          ),
        );
      }
      if (hasMuteAll) {
        notifyProfileRefresh(groupId, memberList: true);
      }
      return MeGroupApi.successCallback();
    } catch (e) {
      debugPrint(
        'group_update_committed_but_sync_failed groupId=$groupId error=$e',
      );
      try {
        if (hasNotice) {
          await applyOptimisticNotice(
            groupId: groupId,
            notice: info.notification!,
          );
        }
        if (hasName) {
          await applyOptimisticGroupName(
            groupId: groupId,
            groupName: info.groupName ?? '',
          );
        }
      } catch (retryError) {
        debugPrint(
          'group_update_committed_but_sync_failed groupId=$groupId error=$retryError',
        );
      }
      return MeGroupApi.successCallback();
    }
  }

  Future<V2TimCallback> updateMyNameCard({
    required String groupId,
    required String userId,
    required String nameCard,
  }) async {
    final selfId = _ownerUserId();
    if (selfId.isEmpty || userId.trim() != selfId) {
      return MeGroupApi.failureCallback('NOT_SELF');
    }
    try {
      await MeGroupApi.instance.updateMyNameCard(
        groupId: groupId,
        nameCard: nameCard,
      );
      await applyOptimisticMyNameCard(groupId: groupId, nameCard: nameCard);
      // This endpoint may return only the changed member fields. Never persist
      // that partial response as a complete group row: doing so clears notice,
      // name and avatar. The field-level optimistic patch above is sufficient.
      await GroupMemberLocalStore.instance.patchUser(
        ownerUserId: selfId,
        groupId: groupId,
        userId: selfId,
        transform: (current) =>
            current.copyWith(nameCard: nameCard, isSelf: true),
      );
      return MeGroupApi.successCallback();
    } catch (e) {
      return MeGroupApi.failureCallback(e.toString());
    }
  }

  Future<void> upsertCreatedGroup(MeGroupRecord record) async {
    final owner = _ownerUserId();
    if (owner.isEmpty || record.groupId.isEmpty) {
      return;
    }
    await GroupLocalStore.instance.upsert(ownerUserId: owner, record: record);
    await refreshUIKitGroupList();
  }

  Future<V2TimCallback> leaveGroup(String groupId) async {
    GroupLeaveDiagLog.log(
      'service_leave_start',
      groupId: groupId,
      extras: const <String, Object?>{'route': 'rest'},
    );
    final id = groupId.trim();
    final self = _ownerUserId();
    // 退出请求优先完成，提示消息放到后台，避免消息发送/重试阻塞退出。
    final result = await MeGroupApi.instance.leaveGroup(groupId);
    if (result.code == 0 && id.isNotEmpty && self.isNotEmpty) {
      unawaited(GroupTipCustomSender.instance.send(
        groupId: id,
        action: 'member_left',
        memberUserIds: <String>[self],
      ));
    }
    return result;
  }

  Future<V2TimCallback> dismissGroup(String groupId) {
    GroupLeaveDiagLog.log(
      'service_dismiss_start',
      groupId: groupId,
      extras: const <String, Object?>{'route': 'rest'},
    );
    return MeGroupApi.instance.dismissGroup(groupId);
  }

  Future<V2TimCallback> kickGroupMember({
    required String groupID,
    required List<String> memberList,
  }) async {
    final id = groupID.trim();
    final owner = _ownerUserId();
    final normalized = memberList
        .map(ChatIdFormat.rawUserUid)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (id.isEmpty || normalized.isEmpty) {
      return MeGroupApi.failureCallback('INVALID_INPUT');
    }

    final removedUserIds = <String>[];
    String? firstFailureCode;

    for (var offset = 0; offset < normalized.length; offset += 100) {
      final end =
          offset + 100 > normalized.length ? normalized.length : offset + 100;
      final chunk = normalized.sublist(offset, end);
      final response = await MeGroupApi.instance.kickMembers(
        groupId: id,
        userIds: chunk,
      );
      if (!response.hasRemoved &&
          response.topLevelCode != null &&
          response.topLevelCode!.isNotEmpty &&
          response.topLevelCode != 'ok') {
        return MeGroupApi.failureCallback(response.topLevelCode!);
      }
      removedUserIds.addAll(response.removedUserIds);
      for (final item in response.results) {
        if (item.status == GroupKickMemberStatus.failed) {
          firstFailureCode ??= item.code?.trim();
        }
      }
    }

    if (removedUserIds.isEmpty) {
      return MeGroupApi.failureCallback(firstFailureCode ?? 'KICK_FAILED');
    }

    // 先发 tip（读本地成员公开名），再删库；tip 成败都不阻塞删人。
    try {
      await GroupTipCustomSender.instance.send(
        groupId: id,
        action: 'member_removed',
        memberUserIds: removedUserIds,
      );
    } catch (_) {}
    await _forgetRemovedMembers(
      groupId: id,
      userIds: removedUserIds,
    );
    // memberCount from the mutation response is not a metadata authority.
    // GroupSyncService will trigger a fresh group detail after the member
    // list sync completes; only that detail may update GroupLocalStore.
    unawaited(
      GroupSyncService.instance.notifyGroupMembersChanged(
        id,
        action: 'member_removed',
        memberUserIds: removedUserIds,
      ),
    );
    if (removedUserIds.length < normalized.length) {
      return V2TimCallback(code: 0, desc: 'PARTIAL_SUCCESS');
    }
    return MeGroupApi.successCallback();
  }

  Future<void> _forgetRemovedMembers({
    required String groupId,
    required List<String> userIds,
  }) async {
    final owner = _ownerUserId();
    final id = groupId.trim();
    final normalized = userIds
        .map(ChatIdFormat.rawUserUid)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (owner.isEmpty || id.isEmpty || normalized.isEmpty) {
      return;
    }
    await GroupMemberLocalStore.instance.deleteUsers(
      ownerUserId: owner,
      groupId: id,
      userIds: normalized,
    );
    GroupMemberStore.instance.removeMembers(id, normalized, notify: true);
  }

  Future<V2TimCallback> setGroupMemberRole({
    required String groupID,
    required String userID,
    required int role,
  }) {
    return setGroupMemberRoles(
      groupID: groupID,
      userIDs: <String>[userID],
      role: role,
    );
  }

  Future<V2TimCallback> setGroupMemberRoles({
    required String groupID,
    required List<String> userIDs,
    required int role,
  }) async {
    final groupId = groupID.trim();
    final owner = _ownerUserId();
    final seen = <String>{};
    final memberIds = <String>[];
    for (final raw in userIDs) {
      final uid = ChatIdFormat.rawUserUid(raw);
      if (uid.isEmpty || !seen.add(uid)) {
        continue;
      }
      memberIds.add(uid);
    }
    if (groupId.isEmpty || memberIds.isEmpty) {
      return MeGroupApi.failureCallback('INVALID_INPUT');
    }
    if (role != GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_ADMIN &&
        role != GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER) {
      return MeGroupApi.failureCallback('INVALID_INPUT');
    }

    // The picker counts the backend management snapshot. The server validates
    // the limit at write time; stale SDK/cache roles must not veto this request.
    final response = await MeGroupApi.instance.setMemberRoles(
      groupId: groupId,
      role: role,
      userIds: memberIds,
    );
    if (response.topLevelCode != null &&
        response.topLevelCode!.isNotEmpty &&
        response.topLevelCode != 'ok' &&
        !response.hasAccepted) {
      return MeGroupApi.failureCallback(response.topLevelCode!);
    }
    final accepted = response.acceptedUserIds;
    if (accepted.isEmpty) {
      final firstCode =
          response.results.map((item) => item.code?.trim()).firstWhere(
                (code) => code != null && code.isNotEmpty,
                orElse: () => null,
              );
      return MeGroupApi.failureCallback(firstCode ?? 'INVALID_RESPONSE');
    }

    final previousByUser = <String, int>{};
    final locals = await GroupMemberLocalStore.instance.readRecordsByUserIds(
      groupId: groupId,
      ownerUserId: owner,
      userIds: accepted.toList(growable: false),
    );
    for (final item in locals) {
      previousByUser[item.userId] = item.role;
    }

    for (final memberId in accepted) {
      final previous = previousByUser[memberId] ??
          GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER;
      GroupMemberRolePending.instance.register(
        groupId: groupId,
        userId: memberId,
        expectedRole: role,
        previousRole: previous,
        operatorUserId: owner,
      );
      await GroupMemberLocalStore.instance.patchUser(
        ownerUserId: owner,
        groupId: groupId,
        userId: memberId,
        transform: (current) => current.copyWith(role: role),
      );
      if (memberId == owner) {
        await _patchGroupFields(owner: owner, groupId: groupId, myRole: role);
      }
    }

    notifyProfileRefresh(groupId, memberList: true);

    final tipAction = role == GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_ADMIN
        ? 'member_set_admin'
        : 'member_cancel_admin';
    unawaited(
      GroupTipCustomSender.instance.send(
        groupId: groupId,
        action: tipAction,
        memberUserIds: accepted,
        detail: <String, dynamic>{'role': role, 'myRole': role},
      ),
    );
    return MeGroupApi.successCallback();
  }

  Future<void> _reconcilePendingMemberRoles(String groupId) async {
    final id = groupId.trim();
    final owner = _ownerUserId();
    final expired = GroupMemberRolePending.instance.takeExpiredForGroup(id);
    if (id.isEmpty || owner.isEmpty || expired.isEmpty) {
      return;
    }
    try {
      final sdkPage = await _loadGroupMemberPageFromImSdk(
        groupID: id,
        count: 100,
        nextSeq: '0',
        filter: GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ALL,
      );
      final members = sdkPage?.data?.memberInfoList ?? const [];
      final records = members
          .whereType<V2TimGroupMemberFullInfo>()
          .map(
            (member) => GroupMemberRecord.fromV2Tim(
              member,
              selfUserId: owner,
            ),
          )
          .toList(growable: false);
      await GroupMemberLocalStore.instance.upsertMany(
        ownerUserId: owner,
        groupId: id,
        records: records,
      );
      final byUser = <String, int>{
        for (final item in records) item.userId: item.role,
      };
      for (final entry in expired) {
        final serverRole = byUser[entry.userId];
        if (serverRole == null || serverRole <= 0) {
          continue;
        }
        await GroupMemberLocalStore.instance.patchUser(
          ownerUserId: owner,
          groupId: id,
          userId: entry.userId,
          transform: (current) => current.copyWith(role: serverRole),
        );
        if (entry.userId == owner) {
          await _patchGroupFields(
            owner: owner,
            groupId: id,
            myRole: serverRole,
          );
        }
      }
      notifyProfileRefresh(id, memberList: true);
    } catch (e) {
      _log('reconcilePendingMemberRoles failed groupId=$id error=$e');
    }
  }

  Future<V2TimCallback> transferGroupOwner({
    required String groupID,
    required String userID,
  }) async {
    final groupId = groupID.trim();
    final newOwnerId = ChatIdFormat.rawUserUid(userID);
    final owner = _ownerUserId();
    GroupGovernanceTrace.log(
      'transfer_owner_service_start',
      extras: <String, Object?>{
        'groupId': groupId,
        'oldOwnerUserId': owner,
        'newOwnerUserId': newOwnerId,
      },
    );
    if (groupId.isEmpty || newOwnerId.isEmpty) {
      GroupGovernanceTrace.log(
        'transfer_owner_service_invalid_input',
        extras: <String, Object?>{
          'groupId': groupId,
          'oldOwnerUserId': owner,
          'newOwnerUserId': newOwnerId,
        },
      );
      return MeGroupApi.failureCallback('INVALID_INPUT');
    }
    if (owner.isEmpty) {
      GroupGovernanceTrace.log(
        'transfer_owner_service_auth_not_ready',
        extras: <String, Object?>{
          'groupId': groupId,
          'newOwnerUserId': newOwnerId,
        },
      );
      return MeGroupApi.failureCallback('AUTH_NOT_READY');
    }
    final res = await MeGroupApi.instance.transferOwner(
      groupId: groupId,
      newOwnerUserId: newOwnerId,
    );
    if (res.code != 0) {
      GroupGovernanceTrace.log(
        'transfer_owner_service_failed',
        extras: <String, Object?>{
          'groupId': groupId,
          'oldOwnerUserId': owner,
          'newOwnerUserId': newOwnerId,
          'code': res.code,
          'desc': res.desc,
        },
      );
      return res;
    }
    if (newOwnerId == owner) {
      await _patchGroupFields(
        owner: owner,
        groupId: groupId,
        ownerUserId: newOwnerId,
        myRole: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER,
      );
    } else {
      await _patchGroupFields(
        owner: owner,
        groupId: groupId,
        ownerUserId: newOwnerId,
        myRole: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER,
      );
    }
    await GroupMemberLocalStore.instance.patchUser(
      ownerUserId: owner,
      groupId: groupId,
      userId: owner,
      transform: (current) => current.copyWith(
        role: newOwnerId == owner
            ? GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER
            : GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER,
      ),
    );
    await GroupMemberLocalStore.instance.patchUser(
      ownerUserId: owner,
      groupId: groupId,
      userId: newOwnerId,
      transform: (current) => current.copyWith(
        role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER,
      ),
    );
    notifyProfileRefresh(groupId, memberList: true);
    await refreshUIKitGroupList();
    GroupGovernanceTrace.log(
      'transfer_owner_service_success',
      extras: <String, Object?>{
        'groupId': groupId,
        'oldOwnerUserId': owner,
        'newOwnerUserId': newOwnerId,
      },
    );
    unawaited(
      GroupTipCustomSender.instance.send(
        groupId: groupId,
        action: 'owner_changed',
        memberUserIds: <String>[newOwnerId],
        detail: <String, dynamic>{
          'ownerUserId': newOwnerId,
          'previousOwnerUserId': owner,
        },
      ),
    );
    return res;
  }

  Future<V2TimCallback> muteGroupMember({
    required String groupID,
    required String userID,
    required int seconds,
  }) async {
    final groupId = groupID.trim();
    final memberId = ChatIdFormat.rawUserUid(userID);
    final owner = _ownerUserId();
    if (groupId.isEmpty || memberId.isEmpty) {
      return MeGroupApi.failureCallback('INVALID_INPUT');
    }
    final res = await MeGroupApi.instance.muteMember(
      groupId: groupId,
      userId: memberId,
      muteSeconds: seconds,
    );
    if (res.code != 0) {
      return res;
    }
    final muteUntil = seconds > 0
        ? DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + seconds
        : 0;
    await GroupMemberLocalStore.instance.patchUser(
      ownerUserId: owner,
      groupId: groupId,
      userId: memberId,
      transform: (current) => current.copyWith(muteUntil: muteUntil),
    );
    _patchMemoryMemberMuteUntil(
      groupId: groupId,
      userId: memberId,
      muteUntil: muteUntil,
    );
    notifyProfileRefresh(groupId, memberList: true);
    unawaited(
      GroupTipCustomSender.instance.send(
        groupId: groupId,
        action: seconds > 0 ? 'member_muted' : 'member_unmuted',
        memberUserIds: <String>[memberId],
        detail: <String, dynamic>{
          'userId': memberId,
          'muteUntil': muteUntil,
          'muteSeconds': seconds,
        },
      ),
    );
    return res;
  }

  /// [refresh] 仅建群失败 recovery 等显式场景传 true；会话列表 / 常规同步必须 false。
  Future<void> syncFull({
    String reason = 'manual',
    bool refresh = false,
    bool startupLocalFirst = false,
  }) {
    final owner = _ownerUserId();
    if (owner.isEmpty) {
      return Future<void>.value();
    }
    final active = _syncInFlight;
    if (active != null) {
      if (refresh && !_syncInFlightRefresh) {
        return active.then((_) => syncFull(
              reason: reason,
              refresh: true,
              startupLocalFirst: startupLocalFirst,
            ));
      }
      return active;
    }
    // 手势滚动中推迟非 refresh 全量同步，避免与列表抢主线程。
    if (!refresh &&
        GroupLocalPerfFlags.deferSyncFullWhileFeedScrolling &&
        _isAnyGroupListOrConversationScrolling()) {
      _scheduleDeferredSyncFull(reason: reason, refresh: refresh);
      return Future<void>.value();
    }
    // resume quiet 内推迟非 refresh，错开会话首屏 loadUiWindow。
    if (!refresh &&
        GroupLocalPerfFlags.deferSyncFullWhileResumeQuiet &&
        ConversationSyncService.instance.isInResumeQuietWindow) {
      _scheduleDeferredSyncFullAfterResumeQuiet(
        reason: reason,
        refresh: refresh,
      );
      return Future<void>.value();
    }
    // 服务端约 10s 短缓存；非 refresh 时短时间重复拉无意义。
    if (!refresh &&
        _groupListSyncedOnce &&
        _lastMeGroupsNetworkAt != null &&
        DateTime.now().difference(_lastMeGroupsNetworkAt!) <
            _meGroupsNetworkCooldown) {
      _log('syncFull skip reason=$reason cooldown=10s');
      SqfliteLockProfileLog.event(
        'syncFull_skip',
        extras: <String, Object?>{
          'reason': reason,
          'cause': 'network_cooldown',
        },
      );
      return Future<void>.value();
    }

    final generation = _syncGeneration;
    late final Future<void> task;
    _syncInFlightRefresh = refresh;
    task = _runSyncFull(
      owner: owner,
      generation: generation,
      reason: reason,
      refresh: refresh,
      startupLocalFirst: startupLocalFirst,
    ).whenComplete(() {
      if (identical(_syncInFlight, task)) {
        _syncInFlight = null;
        _syncInFlightRefresh = false;
      }
    });
    _syncInFlight = task;
    return task;
  }

  void _scheduleDeferredSyncFullAfterResumeQuiet({
    required String reason,
    required bool refresh,
  }) {
    _deferredSyncFullReason = reason;
    _deferredSyncFullRefresh = _deferredSyncFullRefresh || refresh;
    _deferredSyncFullTimer?.cancel();
    final settle = _resumeQuietSyncFullSettle(reason: reason);
    _deferredSyncFullTimer = Timer(
      settle,
      () {
        _deferredSyncFullTimer = null;
        final pendingReason = _deferredSyncFullReason ?? reason;
        final pendingRefresh = _deferredSyncFullRefresh;
        _deferredSyncFullReason = null;
        _deferredSyncFullRefresh = false;
        if (ConversationSyncService.instance.isInResumeQuietWindow) {
          _scheduleDeferredSyncFullAfterResumeQuiet(
            reason: pendingReason,
            refresh: pendingRefresh,
          );
          return;
        }
        if (_isAnyGroupListOrConversationScrolling()) {
          _scheduleDeferredSyncFull(
            reason: pendingReason,
            refresh: pendingRefresh,
          );
          return;
        }
        unawaited(
          syncFull(
            reason: '${pendingReason}_after_quiet',
            refresh: pendingRefresh,
          ),
        );
      },
    );
    _log(
      'syncFull deferred reason=$reason resume_quiet=true settleMs='
      '${settle.inMilliseconds}',
    );
    SqfliteLockProfileLog.event(
      'syncFull_defer_quiet',
      extras: <String, Object?>{
        'reason': reason,
        'settleMs': settle.inMilliseconds,
      },
    );
  }

  Duration _resumeQuietSyncFullSettle({required String reason}) {
    final base = GroupLocalPerfFlags.syncFullAfterResumeQuietSettle;
    final postHome = GroupLocalPerfFlags.postHomeSyncFullMinDelayAfterQuiet;
    if (_isPostHomeReason(reason) && postHome > base) {
      return postHome;
    }
    return base;
  }

  static bool _isPostHomeReason(String reason) {
    return reason.contains('native_post_home') ||
        reason.contains('tcp_auth_ok');
  }

  static bool _isSkipNetworkEligibleReason(String reason) {
    return _isPostHomeReason(reason) || reason.contains('my_group_list');
  }

  static bool _isGroupListReconcileReason(String reason) {
    return reason.contains('my_group_list');
  }

  void _scheduleDeferredSyncFull({
    required String reason,
    required bool refresh,
  }) {
    _deferredSyncFullReason = reason;
    _deferredSyncFullRefresh = _deferredSyncFullRefresh || refresh;
    _deferredSyncFullTimer?.cancel();
    _deferredSyncFullTimer = Timer(
      GroupLocalPerfFlags.syncFullAfterScrollSettle,
      () {
        _deferredSyncFullTimer = null;
        final pendingReason = _deferredSyncFullReason ?? reason;
        final pendingRefresh = _deferredSyncFullRefresh;
        _deferredSyncFullReason = null;
        _deferredSyncFullRefresh = false;
        if (_isAnyGroupListOrConversationScrolling()) {
          _scheduleDeferredSyncFull(
            reason: pendingReason,
            refresh: pendingRefresh,
          );
          return;
        }
        unawaited(
          syncFull(
              reason: '${pendingReason}_after_scroll', refresh: pendingRefresh),
        );
      },
    );
    _log('syncFull deferred reason=$reason scrolling=true');
    SqfliteLockProfileLog.event(
      'syncFull_defer_scroll',
      extras: <String, Object?>{'reason': reason},
    );
  }

  Future<void> _runSyncFull({
    required String owner,
    required int generation,
    required String reason,
    required bool refresh,
    required bool startupLocalFirst,
  }) async {
    final pauseWarm = GroupLocalPerfFlags.syncFullExclusiveWithHistoryWarm;
    if (pauseWarm) {
      ConversationHistoryWarmScheduler.instance.setPausedForMembershipSync(
        true,
        reason: 'sync_full_$reason',
      );
    }
    try {
      _log('syncFull start reason=$reason refresh=$refresh');
      SqfliteLockProfileLog.event(
        'syncFull_start',
        extras: <String, Object?>{'reason': reason, 'refresh': refresh},
      );

      final localCount = await GroupLocalStore.instance.countGroups(
        ownerUserId: owner,
      );
      if (startupLocalFirst && !refresh && localCount > 0) {
        _groupListSyncedOnce = true;
        _log(
          'syncFull skip startup network reason=$reason '
          'localCount=$localCount',
        );
        SqfliteLockProfileLog.event(
          'syncFull_skip',
          extras: <String, Object?>{
            'reason': reason,
            'cause': 'startup_local_first',
            'localCount': localCount,
          },
        );
        return;
      }
      if (await _shouldSkipNetworkSyncFull(
        owner: owner,
        reason: reason,
        refresh: refresh,
        localCount: localCount,
      )) {
        _groupListSyncedOnce = true;
        _log(
          'syncFull skip network reason=$reason localCount=$localCount',
        );
        SqfliteLockProfileLog.event(
          'syncFull_skip',
          extras: <String, Object?>{
            'reason': reason,
            'cause': 'local_complete',
            'localCount': localCount,
          },
        );
        scheduleIdleReconcile(reason: 'after_skip_$reason');
        return;
      }

      final existing = await GroupLocalStore.instance.readAll(
        ownerUserId: owner,
        caller: 'syncFull',
      );
      final existingById = {for (final item in existing) item.groupId: item};
      final records = await _fetchJoinedGroupsFromImSdk(
        existingById: existingById,
      );
      if (!_isCurrentSync(owner, generation)) {
        return;
      }
      if (records == null) {
        _log('syncFull sdk unavailable reason=$reason');
        SqfliteLockProfileLog.event(
          'syncFull_skip',
          extras: <String, Object?>{
            'reason': reason,
            'cause': 'imsdk_unavailable',
          },
        );
        return;
      }
      _lastMeGroupsNetworkAt = DateTime.now();
      final joinedIds = records
          .map((item) => item.groupId.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      final removedGroupIds = removedGroupIdsByEquivalence(
        existingIds: existing.map((item) => item.groupId),
        joinedIds: joinedIds,
      );
      final incomingKeys = records
          .map((record) => GroupLocalStore.groupEquivalenceKey(record.groupId))
          .where((key) => key.isNotEmpty)
          .toSet();
      for (final key in incomingKeys) {
        _snapshotMissingCounts.remove(key);
      }
      for (final groupId in removedGroupIds) {
        final key = GroupLocalStore.groupEquivalenceKey(groupId);
        if (key.isNotEmpty) {
          _snapshotMissingCounts[key] = (_snapshotMissingCounts[key] ?? 0) + 1;
        }
      }
      // 群快照缺失不是退群证据：网络缓存/分页漏页时必须保留本地成员关系，
      // 否则 shouldShowConversation 会把 SDK 后续返回的真实会话继续隐藏。
      // 明确退群、被踢、解散事件仍会走各自的 delete 路径。
      final safeRecords = GroupLocalStore.dedupeGroupRecords(
        <MeGroupRecord>[...existing, ...records],
      ).where((record) {
        final key = GroupLocalStore.groupEquivalenceKey(record.groupId);
        return shouldRetainGroupFromSnapshotSafety(
          explicitlyRemoved: _explicitlyRemovedGroupKeys.contains(key),
          consecutiveMissingSnapshots: _snapshotMissingCounts[key] ?? 0,
        );
      }).toList(growable: false);
      await GroupLocalStore.instance.replaceAll(
        ownerUserId: owner,
        records: safeRecords,
        // 同一次 syncFull 内复用上方 readAll，避免二次全表过 Channel。
        existingSnapshot: existing,
      );
      if (!_isCurrentSync(owner, generation)) {
        await _reapplyExplicitRemovalTombstones(owner);
        return;
      }
      await GroupLocalStore.instance.writeFullSyncMeta(
        ownerUserId: owner,
        // 记录服务端本轮真实数量。只要仍有待确认缺失项，本地数与 meta
        // 不一致，后续 syncFull 就不会被“本地完整”优化永久跳过。
        count: records.length,
      );
      _groupListSyncedOnce = true;
      _bumpJoinedGroupsRevision();
      // /me/groups 快照差异只能更新可见性，不能作为删除 SDK 会话的证据。
      // 分页缺页、缓存或短暂网络异常都可能让真实群暂时不在 records 中。
      for (final groupId in removedGroupIds) {
        if (!_isCurrentSync(owner, generation)) {
          return;
        }
        await _purgeGroupConversation(
          groupId,
          explicitMembershipEvent: false,
          reason: 'sync_full_snapshot_missing',
        );
      }
      if (!_isCurrentSync(owner, generation)) {
        return;
      }
      await pruneStaleGroupConversations(reason: 'sync_full_$reason');
      if (!_isCurrentSync(owner, generation)) {
        return;
      }
      // 全量成员对齐后冲刷「先到会话、后到成员」挂起项。
      unawaited(
        ConversationSyncService.instance.onLocalGroupMembershipExpanded(),
      );
      // 用 REST 群名盖掉会话列表里误显示的完整 IM ID。
      unawaited(
        ConversationSyncService.instance.applyGroupDisplayNames(safeRecords),
      );
      _log(
        'syncFull done count=${records.length} removed=${removedGroupIds.length}',
      );
      SqfliteLockProfileLog.event(
        'syncFull_done',
        extras: <String, Object?>{
          'reason': reason,
          'count': records.length,
          'removed': removedGroupIds.length,
        },
      );
      // Post-snapshot reconciliation is owned by HomePostImSyncService.
      // Do not fan out unawaited work here: callers need one visible queue so
      // session generations, retries, and request budgets remain effective.
      scheduleIdleReconcile(reason: 'after_full_$reason');
    } catch (e) {
      _log('syncFull failed: $e');
      SqfliteLockProfileLog.event(
        'syncFull_fail',
        extras: <String, Object?>{'reason': reason, 'error': '$e'},
      );
      rethrow;
    } finally {
      if (pauseWarm) {
        ConversationHistoryWarmScheduler.instance.setPausedForMembershipSync(
          false,
          reason: 'sync_full_done_$reason',
        );
      }
    }
  }

  Future<bool> _shouldSkipNetworkSyncFull({
    required String owner,
    required String reason,
    required bool refresh,
    required int localCount,
  }) async {
    if (!GroupLocalPerfFlags.skipNetworkSyncFullWhenLocalComplete) {
      return false;
    }
    final meta = await GroupLocalStore.instance.readFullSyncMeta(
      ownerUserId: owner,
    );
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    return shouldSkipNetworkSyncFullDecision(
      refresh: refresh,
      reason: reason,
      localCount: localCount,
      // A startup local-first pass may intentionally be partial. The group
      // page must still be allowed to request its delayed completion even if
      // that pass marked the process as locally usable.
      groupListSyncedOnce:
          _isGroupListReconcileReason(reason) ? false : _groupListSyncedOnce,
      metaAtMs: meta.atMs,
      metaCount: meta.count,
      nowMs: nowMs,
    );
  }

  /// 纯决策：供单测与 [_shouldSkipNetworkSyncFull] 共用。
  @visibleForTesting
  static bool shouldSkipNetworkSyncFullDecision({
    required bool refresh,
    required String reason,
    required int localCount,
    required bool groupListSyncedOnce,
    required int metaAtMs,
    required int metaCount,
    required int nowMs,
    bool flagEnabled = GroupLocalPerfFlags.skipNetworkSyncFullWhenLocalComplete,
    int localCompleteMinCount = GroupLocalPerfFlags.localCompleteMinCount,
    int maxAgeMs = -1,
  }) {
    if (!flagEnabled) {
      return false;
    }
    if (refresh) {
      return false;
    }
    if (!_isSkipNetworkEligibleReason(reason)) {
      return false;
    }
    if (localCount < localCompleteMinCount) {
      return false;
    }
    if (groupListSyncedOnce && !_isGroupListReconcileReason(reason)) {
      return true;
    }
    if (metaAtMs <= 0 || metaCount <= 0) {
      return false;
    }
    if (metaCount != localCount) {
      return false;
    }
    final ageCap = maxAgeMs >= 0
        ? maxAgeMs
        : GroupLocalPerfFlags.fullSyncMaxAge.inMilliseconds;
    final ageMs = nowMs - metaAtMs;
    if (ageMs < 0 || ageMs > ageCap) {
      return false;
    }
    return true;
  }

  /// 空闲轻量对账：先比 `/me/groups` total 与本地 count，不匹配再全量。
  void scheduleIdleReconcile({String reason = 'idle'}) {
    if (!GroupLocalPerfFlags.idleReconcileEnabled) {
      return;
    }
    _idleReconcileTimer?.cancel();
    final generation = ++_idleReconcileGeneration;
    _idleReconcileTimer = Timer(GroupLocalPerfFlags.idleReconcileDelay, () {
      _idleReconcileTimer = null;
      unawaited(_runIdleReconcile(generation: generation, reason: reason));
    });
    _log(
      'idle_reconcile scheduled reason=$reason delayMs='
      '${GroupLocalPerfFlags.idleReconcileDelay.inMilliseconds}',
    );
  }

  Future<void> _runIdleReconcile({
    required int generation,
    required String reason,
  }) async {
    if (generation != _idleReconcileGeneration) {
      return;
    }
    final owner = _ownerUserId();
    if (owner.isEmpty) {
      return;
    }
    if (_isAnyGroupListOrConversationScrolling()) {
      _idleReconcileTimer?.cancel();
      _idleReconcileTimer = Timer(
        GroupLocalPerfFlags.syncFullAfterScrollSettle,
        () {
          unawaited(
            _runIdleReconcile(generation: generation, reason: reason),
          );
        },
      );
      return;
    }
    if (ConversationSyncService.instance.isInResumeQuietWindow) {
      scheduleIdleReconcile(reason: '${reason}_quiet');
      return;
    }
    try {
      final localCount = await GroupLocalStore.instance.countGroups(
        ownerUserId: owner,
      );
      final sdkGroups = await _fetchJoinedGroupsFromImSdk(
        existingById: const <String, MeGroupRecord>{},
      );
      if (generation != _idleReconcileGeneration || _ownerUserId() != owner) {
        return;
      }
      if (sdkGroups == null) {
        _log('idle_reconcile sdk unavailable reason=$reason');
        return;
      }
      final remoteTotal = sdkGroups.length;
      if (remoteTotal == localCount) {
        await GroupLocalStore.instance.writeFullSyncMeta(
          ownerUserId: owner,
          count: localCount,
        );
        _groupListSyncedOnce = true;
        _log(
          'idle_reconcile ok reason=$reason total=$remoteTotal',
        );
        SqfliteLockProfileLog.event(
          'idle_reconcile_ok',
          extras: <String, Object?>{
            'reason': reason,
            'total': remoteTotal,
          },
        );
        return;
      }
      _log(
        'idle_reconcile mismatch reason=$reason local=$localCount '
        'remote=$remoteTotal',
      );
      SqfliteLockProfileLog.event(
        'idle_reconcile_total_mismatch',
        extras: <String, Object?>{
          'reason': reason,
          'local': localCount,
          'remote': remoteTotal,
        },
      );
      await syncFull(reason: 'idle_reconcile', refresh: false);
    } catch (e) {
      _log('idle_reconcile failed: $e');
      SqfliteLockProfileLog.event(
        'idle_reconcile_fail',
        extras: <String, Object?>{'reason': reason, 'error': '$e'},
      );
    }
  }

  bool _isCurrentSync(String owner, int generation) {
    return generation == _syncGeneration && _ownerUserId() == owner;
  }

  void _markExplicitGroupRemoval(String groupId) {
    final key = GroupLocalStore.groupEquivalenceKey(groupId);
    if (key.isNotEmpty) {
      _explicitlyRemovedGroupKeys.add(key);
      _activeConversationEvidenceKeys.remove(key);
      _snapshotMissingCounts.remove(key);
      // Remove the visible SDK projection before waiting for history/network
      // cleanup. Pinned rows must not survive a confirmed membership removal.
      final id = ChatIdFormat.canonicalGroupStorageId(groupId);
      ConversationTabStore.instance.applyDeleted(['group_$id', id]);
    }
    _syncGeneration++;
  }

  void _clearExplicitGroupRemoval(String groupId) {
    _removalWork.invalidate(_removalWorkKey(groupId));
    final key = GroupLocalStore.groupEquivalenceKey(groupId);
    if (key.isNotEmpty) {
      _explicitlyRemovedGroupKeys.remove(key);
      _snapshotMissingCounts.remove(key);
    }
  }

  Future<void> _reapplyExplicitRemovalTombstones(String owner) async {
    if (owner.isEmpty || _explicitlyRemovedGroupKeys.isEmpty) {
      return;
    }
    final rows = await GroupLocalStore.instance.readAll(ownerUserId: owner);
    for (final row in rows) {
      final key = GroupLocalStore.groupEquivalenceKey(row.groupId);
      if (_explicitlyRemovedGroupKeys.contains(key)) {
        await GroupLocalStore.instance.delete(
          ownerUserId: owner,
          groupId: row.groupId,
        );
      }
    }
  }

  /// 在线入站 `group_tip`：只对当前群打 IM SDK `getGroupsInfo` 更新群资料。
  /// 不扫历史、不刷全部群、不拉群成员。
  Future<void> applyInboundGroupDisplayFromMessage(
    V2TimMessage message,
  ) async {
    if (message.isSelf == true) {
      return;
    }
    if (GroupTipsMessageHelper.isLocalGroupTips(message)) {
      return;
    }
    final map = parseGroupTipPayload(message.customElem, message: message);
    if (map == null) {
      return;
    }
    final action = map['action']?.toString().trim().toLowerCase() ?? '';
    final isProfileTip = isGroupProfileRefreshTipAction(action);
    final isMembershipTip = isGroupMembershipTipAction(action);
    if (!isProfileTip && !isMembershipTip) {
      return;
    }
    final groupId = _groupIdFromInboundMessage(message);
    if (groupId.isEmpty || isForbiddenGroupStorageId(groupId)) {
      return;
    }
    if (isMembershipTip) {
      await GroupLocalTipsService.instance.syncVisibleTipsForGroup(groupId);
      return;
    }
    final clientMsgId = map['clientMsgId']?.toString().trim() ?? '';
    final msgId = message.msgID?.trim() ?? '';
    final dedupeKey =
        msgId.isNotEmpty ? 'msg:$msgId' : 'tip:$groupId|$action|$clientMsgId';
    if (!_inboundDisplayTipKeys.add(dedupeKey)) {
      return;
    }
    try {
      await refreshGroupDetail(groupId, refresh: true);
      await _applyLiveCustomTipGroupIdentity(
        groupId: groupId,
        action: action,
        map: map,
      );
      notifyProfileRefresh(groupId);
    } catch (e) {
      _log(
          'applyInboundGroupDisplayFromMessage failed groupId=$groupId error=$e');
    } finally {
      _inboundDisplayTipKeys.remove(dedupeKey);
    }
  }

  String _groupIdFromInboundMessage(V2TimMessage message) {
    final fromGroup = ChatIdFormat.normalizeGroupId(message.groupID ?? '');
    if (fromGroup.isNotEmpty) {
      return fromGroup;
    }
    return ChatIdFormat.normalizeGroupId(
      message.groupTipsElem?.groupID ?? '',
    );
  }

  /// IM `getGroupsInfo` 可能仍是旧快照。同一条在线 custom tip 里的展示字段
  /// 后写，避免被过期 SDK 详情挡住。不拉群成员。
  Future<void> _applyLiveCustomTipGroupIdentity({
    required String groupId,
    required String action,
    required Map<String, dynamic> map,
  }) async {
    final owner = _ownerUserId();
    final id = ChatIdFormat.normalizeGroupId(groupId);
    if (owner.isEmpty || id.isEmpty) {
      return;
    }
    final fields = extractGroupTipDisplayFields(map);
    final detail = map['detail'] is Map
        ? Map<String, dynamic>.from(map['detail'] as Map)
        : const <String, dynamic>{};
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    switch (action) {
      case 'group_name_changed':
        if (fields.groupName.isNotEmpty) {
          await applyOptimisticGroupName(
            groupId: id,
            groupName: fields.groupName,
          );
        }
        return;
      case 'group_avatar_changed':
        if (fields.avatarUrl.isNotEmpty) {
          final existing = await GroupLocalStore.instance.read(
            groupId: id,
            ownerUserId: owner,
          );
          if (existing == null) {
            return;
          }
          final nextUrl = normalizeObjectUrl(fields.avatarUrl);
          await GroupLocalStore.instance.upsert(
            ownerUserId: owner,
            record: existing.copyWith(
              avatarUrl: nextUrl,
              avatarVersion: existing.avatarVersion + 1,
              updatedAt: now,
            ),
          );
          await publishGroupConversationDisplay(
            groupId: id,
            avatarUrl: nextUrl,
          );
        }
        return;
      case 'group_notice_changed':
        final notice = (detail['notice'] ??
                detail['notification'] ??
                detail['groupNotice'] ??
                '')
            .toString();
        final current = await GroupLocalStore.instance.read(
          groupId: id,
          ownerUserId: owner,
        );
        if (current != null) {
          await GroupLocalStore.instance.upsert(
            ownerUserId: owner,
            record: current.copyWith(
              notice: notice,
              noticeUpdatedAt: now,
              updatedAt: now,
            ),
          );
        }
        return;
      case 'group_mute_all_on':
      case 'group_mute_all_off':
        await _patchGroupFields(
          owner: owner,
          groupId: id,
          isAllMuted: action == 'group_mute_all_on',
          updatedAt: now,
        );
        return;
      default:
        return;
    }
  }

  /// 入站拉人/踢人/退群 tip（App Custom 或 IM 原生 GroupTips）→ 定向成员校正。
  /// 与 TCP 路径共用 `applyTargetedMemberCorrection`，不拉全群。
  Future<void> applyInboundMembershipTipFromMessage(
    V2TimMessage message,
  ) async {
    String action = '';
    List<String> memberUserIds = const <String>[];
    final map = parseGroupTipPayload(message.customElem);
    if (map != null) {
      action = map['action']?.toString().trim().toLowerCase() ?? '';
      final detail = map['detail'];
      if (detail is Map) {
        final raw = detail['memberUserIds'] ?? detail['member_user_ids'];
        if (raw is List) {
          memberUserIds = raw
              .map((e) => ChatIdFormat.rawUserUid(e?.toString() ?? ''))
              .where((id) => id.isNotEmpty)
              .toList(growable: false);
        }
      }
    } else {
      action = GroupTipsMessageHelper.actionForTipsType(
            message.groupTipsElem?.type,
          ) ??
          '';
      final tipMembers = message.groupTipsElem?.memberList;
      if (tipMembers != null && tipMembers.isNotEmpty) {
        memberUserIds = tipMembers
            .map((m) => ChatIdFormat.rawUserUid(m?.userID ?? ''))
            .where((id) => id.isNotEmpty)
            .toList(growable: false);
      }
    }
    if (!isGroupMembershipTipAction(action)) {
      return;
    }
    final groupId = ChatIdFormat.normalizeGroupId(message.groupID ?? '');
    if (groupId.isEmpty || isForbiddenGroupStorageId(groupId)) {
      return;
    }
    final clientMsgId = map?['clientMsgId']?.toString().trim() ?? '';
    final msgId = message.msgID?.trim() ?? '';
    final dedupeKey = msgId.isNotEmpty
        ? 'membership_msg:$msgId'
        : 'membership_tip:$groupId|$action|$clientMsgId';
    if (!_inboundDisplayTipKeys.add(dedupeKey)) {
      return;
    }
    try {
      await applyTargetedMemberCorrection(
        groupId: groupId,
        action: action,
        memberUserIds: memberUserIds,
      );
      // This fallback path may not have a GroupSyncService event. The
      // notification below invalidates the canonical metadata coordinator;
      // do not start a second direct detail request here.
      // 不走 notifyGroupMembersChanged（会再 sync 一次）；仅通知其他聊天 UI。
      notifyMembershipChatHeader(
        groupId,
        action: action,
        memberUserIds: memberUserIds,
      );
    } catch (e) {
      _log(
        'applyInboundMembershipTipFromMessage failed groupId=$groupId '
        'action=$action error=$e',
      );
    } finally {
      _inboundDisplayTipKeys.remove(dedupeKey);
    }
  }

  /// 成员名单变更后通知打开中的群聊处理列表、灰字等非资料 UI。
  void notifyMembershipChatHeader(
    String groupId, {
    String action = 'member_added',
    List<String> memberUserIds = const <String>[],
  }) {
    final id = ChatIdFormat.normalizeGroupId(groupId);
    if (id.isEmpty) {
      return;
    }
    GroupSyncService.instance.notifyMemberMetadataChanged(
      groupId: id,
      action: action,
      memberUserIds: memberUserIds,
    );
  }

  Future<void> refreshGroupDetail(
    String groupId, {
    bool refresh = false,
  }) {
    final owner = _ownerUserId();
    final id = groupId.trim();
    if (owner.isEmpty || id.isEmpty) {
      return Future<void>.value();
    }
    final identity = SessionIdentityService.instance.capture(
      ownerUserId: owner,
    );
    if (!SessionIdentityService.instance.isCurrent(identity)) {
      return Future<void>.value();
    }
    final syncGeneration = _syncGeneration;
    final key = '${identity.ownerUserId}|${identity.generation}|'
        '$syncGeneration|${GroupLocalStore.groupEquivalenceKey(id)}';
    final active = _groupDetailRefreshInFlight[key];
    if (active != null) {
      if (!refresh || (_groupDetailRefreshForcesRemote[key] ?? false)) {
        return active;
      }
      return _refreshGroupDetailAfterExisting(
        id,
        active,
        identity,
        syncGeneration,
      );
    }
    if (!refresh) {
      final lastSuccessAt = _groupDetailLastSuccessAtMs[key];
      if (lastSuccessAt != null &&
          DateTime.now().millisecondsSinceEpoch - lastSuccessAt < 1000) {
        return Future<void>.value();
      }
    }
    late final Future<void> tracked;
    tracked = _refreshGroupDetailImpl(
      owner: owner,
      groupId: id,
      refresh: refresh,
      identity: identity,
      syncGeneration: syncGeneration,
    ).then<void>((committed) {
      if (committed &&
          SessionIdentityService.instance.isCurrent(identity) &&
          identical(_groupDetailRefreshInFlight[key], tracked)) {
        _groupDetailLastSuccessAtMs[key] =
            DateTime.now().millisecondsSinceEpoch;
      }
    }).whenComplete(() {
      if (identical(_groupDetailRefreshInFlight[key], tracked)) {
        _groupDetailRefreshInFlight.remove(key);
        _groupDetailRefreshForcesRemote.remove(key);
      }
    });
    _groupDetailRefreshInFlight[key] = tracked;
    _groupDetailRefreshForcesRemote[key] = refresh;
    return tracked;
  }

  Future<void> _refreshGroupDetailAfterExisting(
    String groupId,
    Future<void> existing,
    SessionIdentity identity,
    int syncGeneration,
  ) async {
    try {
      await existing;
    } catch (_) {
      // The forced request must still get its own authoritative attempt.
    }
    // The original forced request belongs to the identity that observed the
    // existing flight. If that identity was cleared while waiting, do not
    // turn its continuation into a forced request for the next account.
    if (_syncGeneration != syncGeneration ||
        !SessionIdentityService.instance.isCurrent(identity)) {
      return;
    }
    await refreshGroupDetail(groupId, refresh: true);
  }

  Future<bool> _refreshGroupDetailImpl({
    required String owner,
    required String groupId,
    required bool refresh,
    required SessionIdentity identity,
    required int syncGeneration,
  }) async {
    bool isCurrent() =>
        _syncGeneration == syncGeneration &&
        SessionIdentityService.instance.isCurrent(identity);
    if (!isCurrent()) return false;
    final id = groupId;
    final writeGeneration = GroupLocalStore.instance.beginMetadataWrite(
      ownerUserId: owner,
      groupId: id,
    );
    try {
      final current = await GroupLocalStore.instance.read(
        groupId: id,
        ownerUserId: owner,
      );
      if (!isCurrent()) return false;
      final detail = await MeGroupApi.instance.fetchGroupDetail(
        id,
        refresh: refresh,
        preserveIsAllMutedFrom: current,
        persistLocally: false, // Commit below with this refresh's generation.
      );
      if (!isCurrent()) return false;
      if (detail == null) return false;
      final committed = await GroupLocalStore.instance.upsert(
        ownerUserId: owner,
        record: detail,
        writeGeneration: writeGeneration,
      );
      if (!isCurrent()) return false;
      if (!committed) {
        // An older detail response was rejected by the metadata gate.
        // Never publish that rejected snapshot into SDK conversations.
        if (current != null &&
            _sameGroupMetadata(
              current,
              detail.resolvingMissingFieldsFrom(current),
            )) {
          // The detail response was a successful no-op against the current
          // row; allow the short duplicate-refresh window to apply.
          return true;
        }
        return false;
      }
      if (!isCurrent()) return false;
      final stored = await GroupLocalStore.instance.read(
        groupId: id,
        ownerUserId: owner,
      );
      if (stored == null) return false;
      if (!isCurrent()) return false;
      final prevName = current?.groupName.trim() ?? '';
      final prevAvatar = current?.avatarUrl.trim() ?? '';
      final nextName = stored.groupName.trim();
      final nextAvatar = stored.avatarUrl.trim();
      final nameChanged = nextName.isNotEmpty && nextName != prevName;
      final avatarChanged = nextAvatar.isNotEmpty && nextAvatar != prevAvatar;
      if (nameChanged || avatarChanged) {
        if (!isCurrent()) return false;
        await publishGroupConversationDisplay(
          groupId: id,
          groupName: nameChanged ? nextName : null,
          avatarUrl: avatarChanged ? nextAvatar : null,
        );
      }
      return isCurrent();
    } catch (e) {
      _log('refreshGroupDetail failed groupId=$id error=$e');
      return false;
    }
  }

  /// Applies only the affected members. Never pages the whole group.
  Future<void> applyTargetedMemberCorrection({
    required String groupId,
    required String action,
    required List<String> memberUserIds,
  }) async {
    final owner = _ownerUserId();
    final id = ChatIdFormat.normalizeGroupId(groupId);
    if (owner.isEmpty || id.isEmpty || isExplicitlyRemovedGroup(id)) {
      return;
    }
    final ids = memberUserIds
        .map(ChatIdFormat.rawUserUid)
        .where((uid) => uid.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final normalizedAction = action.trim().toLowerCase();
    if (normalizedAction == 'member_added') {
      GroupMemberStore.instance.clearRemovalTombstones(id, ids);
    }
    final needsMemberLookup = ids.isNotEmpty &&
        (normalizedAction.contains('added') ||
            normalizedAction.contains('profile') ||
            normalizedAction.contains('role') ||
            normalizedAction.contains('muted') ||
            normalizedAction.contains('invite'));
    if (needsMemberLookup) {
      await loadGroupMembersInfo(groupID: id, memberList: ids);
      notifyProfileRefresh(id, memberList: true);
      return;
    }
    notifyProfileRefresh(id);
  }

  /// 拉人/踢人/退群后同步成员首屏，供成员列表实时对齐。
  ///
  /// 人数由独立的群详情刷新写入 GroupLocalStore，成员分页的 total 不参与。
  /// 邀请本地增量后短窗内同群 member_added 族 reason 会 cooldown 跳过，避免双拉。
  Future<void> syncMembersAfterMembershipChange(
    String groupId, {
    String reason = 'manual',
  }) {
    final owner = _ownerUserId();
    final id = ChatIdFormat.normalizeGroupId(groupId);
    if (owner.isEmpty || id.isEmpty || isExplicitlyRemovedGroup(id)) {
      return Future<void>.value();
    }
    if (_shouldSkipMembershipSnapshotForCooldown(id, reason)) {
      SqfliteLockProfileLog.event(
        'membership_snapshot_cooldown_skip',
        extras: <String, Object?>{'groupId': id, 'reason': reason},
      );
      return Future<void>.value();
    }
    final key = '$owner|$id';
    final active = _membershipSnapshotInFlight[key];
    if (active != null) {
      SqfliteLockProfileLog.event(
        'membership_snapshot_coalesced',
        extras: <String, Object?>{'groupId': id, 'reason': reason},
      );
      return active;
    }
    late final Future<void> tracked;
    tracked = _syncMembersAfterMembershipChangeImpl(
      owner: owner,
      groupId: id,
      reason: reason,
    ).whenComplete(() {
      if (identical(_membershipSnapshotInFlight[key], tracked)) {
        _membershipSnapshotInFlight.remove(key);
      }
    });
    _membershipSnapshotInFlight[key] = tracked;
    return tracked;
  }

  /// 邀请成功热路径：只 upsert 新成员壳 + 本地人数 +N，禁止整页 refresh 快照。
  Future<void> applyMembersAddedLocally({
    required String groupId,
    required List<String> addedUserIds,
  }) async {
    final owner = _ownerUserId();
    final id = ChatIdFormat.normalizeGroupId(groupId);
    final normalized = addedUserIds
        .map(ChatIdFormat.rawUserUid)
        .where((uid) => uid.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (owner.isEmpty || id.isEmpty || normalized.isEmpty) {
      return;
    }

    final existing = await GroupMemberLocalStore.instance.readRecordsByUserIds(
      groupId: id,
      userIds: normalized,
      ownerUserId: owner,
    );
    final existingIds = existing.map((e) => e.userId).toSet();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final shells = <GroupMemberRecord>[];
    Map<String, V2TimFriendInfo>? friendById;
    try {
      final friendship = serviceLocator<TUIFriendShipViewModel>();
      friendById = <String, V2TimFriendInfo>{
        for (final f in friendship.friendList ?? const <V2TimFriendInfo>[])
          if (ChatIdFormat.rawUserUid(f.userID).isNotEmpty)
            ChatIdFormat.rawUserUid(f.userID): f,
      };
    } catch (_) {
      friendById = null;
    }

    for (final uid in normalized) {
      if (existingIds.contains(uid)) {
        continue;
      }
      final friend = friendById?[uid];
      final profile = friend?.userProfile;
      final nick = (profile?.nickName ?? '').trim();
      final face = (profile?.faceUrl ?? '').trim();
      final remark = (friend?.friendRemark ?? '').trim();
      shells.add(
        GroupMemberRecord(
          userId: uid,
          nickname: nick,
          avatarUrl: face,
          friendRemark: remark,
          nameCard: '',
          role: 200,
          joinedAt: nowMs,
          isSelf: false,
          joinChannel: 'invite',
        ),
      );
    }

    GroupMemberStore.instance.clearRemovalTombstones(id, normalized);
    if (shells.isNotEmpty) {
      await GroupMemberLocalStore.instance.upsertMany(
        ownerUserId: owner,
        groupId: id,
        records: shells,
      );
      final v2 = shells.map(_toV2TimMember).toList(growable: false);
      GroupMemberStore.instance.putMembers(id, v2);
    }

    markMembershipSyncCooldown(id);
    if (shells.isNotEmpty) {
      try {
        final listenerModel = serviceLocator<TUIGroupListenerModel>();
        listenerModel.requestProfileRefresh(
          NeedUpdate(
            id,
            UpdateType.memberEnter,
            shells
                .map(
                  (s) => V2TimGroupMemberInfo(
                    userID: s.userId,
                    nickName: s.nickname,
                    faceUrl: s.avatarUrl,
                    friendRemark: s.friendRemark,
                  ),
                )
                .toList(growable: false),
          ),
        );
      } catch (_) {
        notifyProfileRefresh(id, memberList: false);
      }
    } else {
      notifyProfileRefresh(id, memberList: false);
    }
    _log(
      'applyMembersAddedLocally groupId=$id added=${normalized.length} '
      'shells=${shells.length}',
    );
  }

  void markMembershipSyncCooldown(String groupId) {
    final id = ChatIdFormat.normalizeGroupId(groupId);
    if (id.isEmpty) {
      return;
    }
    _membershipSnapshotCooldownUntilMs[id] =
        DateTime.now().millisecondsSinceEpoch +
            GroupGovernanceLimits.membershipSyncCooldown.inMilliseconds;
  }

  @visibleForTesting
  static bool shouldSkipMembershipSnapshotForCooldownDecision({
    required int nowMs,
    required int cooldownUntilMs,
    required String reason,
  }) {
    if (nowMs >= cooldownUntilMs) {
      return false;
    }
    return _isMembershipAddedReasonFamily(reason);
  }

  bool _shouldSkipMembershipSnapshotForCooldown(String groupId, String reason) {
    final until = _membershipSnapshotCooldownUntilMs[groupId] ?? 0;
    return shouldSkipMembershipSnapshotForCooldownDecision(
      nowMs: DateTime.now().millisecondsSinceEpoch,
      cooldownUntilMs: until,
      reason: reason,
    );
  }

  static bool _isMembershipAddedReasonFamily(String reason) {
    final r = reason.trim().toLowerCase();
    if (r.isEmpty) {
      return false;
    }
    return r.contains('member_added') ||
        r.contains('invite_members') ||
        r.contains('invite');
  }

  Future<void> _syncMembersAfterMembershipChangeImpl({
    required String owner,
    required String groupId,
    required String reason,
  }) async {
    try {
      await applyTargetedMemberCorrection(
        groupId: groupId,
        action: reason,
        memberUserIds: const <String>[],
      );
      if (_isMembershipAddedReasonFamily(reason)) {
        markMembershipSyncCooldown(groupId);
      }
      _log(
        'syncMembersAfterMembershipChange ok groupId=$groupId reason=$reason',
      );
    } catch (e) {
      _log(
        'syncMembersAfterMembershipChange failed groupId=$groupId '
        'reason=$reason error=$e',
      );
    }
  }

  final Map<String, Future<bool>> _admitFromImInFlight =
      <String, Future<bool>>{};

  /// IM 已推送群会话/入群 tip，但本地成员库尚未写入时：先写入乐观成员壳上屏，
  /// 再拉详情校验；网络失败时保留壳（与杀进程重开一致，依赖后续 syncFull）。
  Future<bool> admitGroupMembershipFromImHint({
    required String groupId,
    String groupName = '',
    String avatarUrl = '',
  }) async {
    final owner = _ownerUserId();
    final id = ChatIdFormat.normalizeGroupId(groupId);
    if (owner.isEmpty || id.isEmpty) {
      return false;
    }
    if (isForbiddenGroupStorageId(id)) {
      _log('admit_reject_forbidden_id groupId=$id');
      GroupLeaveDiagLog.log(
        'admit_reject_forbidden_id',
        groupId: id,
      );
      SqfliteLockProfileLog.event(
        'admit_reject_forbidden_id',
        extras: <String, Object?>{'groupId': id},
      );
      return false;
    }
    final active = _admitFromImInFlight[id];
    if (active != null) {
      return active;
    }
    final task = _admitGroupMembershipFromImHintImpl(
      owner: owner,
      groupId: id,
      groupName: groupName,
      avatarUrl: avatarUrl,
    );
    _admitFromImInFlight[id] = task;
    try {
      return await task;
    } finally {
      if (identical(_admitFromImInFlight[id], task)) {
        _admitFromImInFlight.remove(id);
      }
    }
  }

  Future<bool> _admitGroupMembershipFromImHintImpl({
    required String owner,
    required String groupId,
    required String groupName,
    required String avatarUrl,
  }) async {
    if (isJoinedGroup(groupId)) {
      unawaited(
        ConversationSyncService.instance.onLocalGroupMembershipExpanded(
          groupId: groupId,
        ),
      );
      return true;
    }
    final optimisticShell = await _upsertOptimisticJoinedShell(
      ownerUserId: owner,
      groupId: groupId,
      groupName: groupName,
      avatarUrl: avatarUrl,
    );
    _bumpJoinedGroupsRevision();
    unawaited(
      ConversationSyncService.instance.onLocalGroupMembershipExpanded(
        groupId: groupId,
      ),
    );
    try {
      final current = await GroupLocalStore.instance.read(
        groupId: groupId,
        ownerUserId: owner,
      );
      final detail = await _fetchGroupDetailFromImSdk(
        groupId: groupId,
        preserveFrom: current,
        throwIfDenied: true,
      );
      if (detail != null && detail.groupId.isNotEmpty) {
        await GroupLocalStore.instance.upsert(
          ownerUserId: owner,
          record: detail,
        );
        _bumpJoinedGroupsRevision();
        unawaited(
          ConversationSyncService.instance.onLocalGroupMembershipExpanded(
            groupId: groupId,
          ),
        );
        return true;
      }
      // Only undo the shell created by this operation. A concurrent confirmed
      // detail, or a record that already existed, belongs to the Store.
      if (optimisticShell == null) return true;
      await GroupLocalStore.instance.delete(
        ownerUserId: owner,
        groupId: groupId,
        onlyIfUnchanged: optimisticShell,
      );
      _bumpJoinedGroupsRevision();
      return false;
    } catch (e) {
      if (e is ImSdkGroupMembershipDenied) {
        if (optimisticShell != null) {
          await GroupLocalStore.instance.delete(
            ownerUserId: owner,
            groupId: groupId,
            onlyIfUnchanged: optimisticShell,
          );
          _bumpJoinedGroupsRevision();
        }
        return false;
      }
      _log(
          'admitGroupMembershipFromImHint verify failed groupId=$groupId error=$e');
      // SDK 失败保留乐观壳，等待后续 syncFull / TCP 对齐。
      return true;
    }
  }

  Future<MeGroupRecord?> _upsertOptimisticJoinedShell({
    required String ownerUserId,
    required String groupId,
    required String groupName,
    required String avatarUrl,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final trimmedName = groupName.trim();
    final safeName = GroupDisplayResolver.looksLikeGroupIdLabel(
      trimmedName,
      groupId: groupId,
    )
        ? ''
        : trimmedName;
    final safeAvatar = normalizeObjectUrl(avatarUrl.trim());
    final shell = MeGroupRecord(
      groupId: groupId,
      groupType: 'Work',
      groupName: safeName,
      displayAlias: '',
      avatarUrl: safeAvatar,
      notice: '',
      memberCount: 0,
      myRole: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER,
      myNameCard: '',
      joinedAt: now,
      updatedAt: now,
    );
    final inserted = await GroupLocalStore.instance.upsert(
      ownerUserId: ownerUserId,
      onlyIfAbsent: true,
      record: shell,
    );
    return inserted ? shell : null;
  }

  Future<bool> applyGroupChanged(FriendRealtimeEvent event) async {
    if (event.event.trim() != 'group_changed') {
      return false;
    }
    final groupId = event.groupId?.trim() ?? '';
    final action = event.action?.trim().toLowerCase() ?? '';
    if (groupId.isEmpty || action.isEmpty) {
      return false;
    }
    final owner = _ownerUserId();
    if (owner.isEmpty) {
      return false;
    }
    final detail = event.detail ?? const <String, dynamic>{};
    final memberIds = _memberIds(event, detail);
    final detailUserId =
        detail['userId']?.toString() ?? detail['user_id']?.toString();
    final selfRemoved = _isSelfRemovedFromGroupEvent(
      action: action,
      owner: owner,
      memberIds: memberIds,
      event: event,
    );
    final selfAdded = isSelfAddedToGroupMembershipEvent(
      action: action,
      ownerUserId: owner,
      memberUserIds: memberIds,
      detailUserId: detailUserId,
    );

    switch (action) {
      case 'group_dismissed':
        await onSelfRemovedFromGroup(groupId);
        return true;
      case 'member_left':
      case 'member_removed':
        if (selfRemoved) {
          await onSelfRemovedFromGroup(groupId);
        } else {
          await _forgetRemovedMembers(
            groupId: groupId,
            userIds: memberIds,
          );
        }
        return true;
      case 'member_added':
        if (selfAdded) {
          _clearExplicitGroupRemoval(groupId);
          // Event payloads are hints only; group detail owns the joined
          // group's name and member count.
          await refreshGroupDetail(groupId, refresh: true);
          _bumpJoinedGroupsRevision();
          // IM 会话常早于成员库：补拉会话 + 冲刷挂起项，避免列表要杀进程才出现。
          unawaited(
            ConversationSyncService.instance.onLocalGroupMembershipExpanded(
              groupId: groupId,
            ),
          );
        } else {
          // TCP 常漏带被邀请人 ID：若 IM 已挂起该群会话，仍走入群恢复。
          if (!isJoinedGroup(groupId)) {
            unawaited(
              ConversationSyncService.instance
                  .recoverPendingGroupMembershipIfNeeded(groupId: groupId),
            );
          }
        }
        return true;
      case 'group_name_changed':
        // The event only invalidates the cached metadata. Do not write its
        // optional name directly because it may be stale or out of order.
        return true;
      case 'group_notice_changed':
        // Event payloads are invalidation hints only. GroupSyncService starts
        // the authoritative GET /group/{id} refresh after this returns.
        return true;
      case 'group_avatar_changed':
        // Event payloads are invalidation hints only. GroupSyncService starts
        // the authoritative GET /group/{id} refresh after this returns.
        return true;
      case 'member_profile_changed':
        final userId = ChatIdFormat.rawUserUid(
          detail['userId']?.toString() ?? memberIds.firstOrNull ?? '',
        );
        final nameCard = detail['nameCard']?.toString();
        if (userId.isEmpty) {
          return false;
        }
        if (userId == owner && nameCard != null) {
          await applyOptimisticMyNameCard(groupId: groupId, nameCard: nameCard);
        }
        if (nameCard != null) {
          await GroupMemberLocalStore.instance.patchUser(
            ownerUserId: owner,
            groupId: groupId,
            userId: userId,
            transform: (current) => current.copyWith(nameCard: nameCard),
          );
        }
        return true;
      case 'member_role_changed':
        final userId = ChatIdFormat.rawUserUid(
          detail['userId']?.toString() ?? '',
        );
        final role = _readInt(detail['myRole'] ?? detail['role']);
        if (userId.isNotEmpty && role > 0) {
          GroupMemberRolePending.instance.acknowledgeTcp(
            groupId: groupId,
            userId: userId,
            role: role,
          );
        }
        if (userId == owner && role > 0) {
          await _patchGroupFields(owner: owner, groupId: groupId, myRole: role);
        }
        if (userId.isNotEmpty && role > 0) {
          await GroupMemberLocalStore.instance.patchUser(
            ownerUserId: owner,
            groupId: groupId,
            userId: userId,
            transform: (current) => current.copyWith(role: role),
          );
        }
        notifyProfileRefresh(groupId, memberList: true);
        return true;
      case 'owner_changed':
        await _patchGroupFields(
          owner: owner,
          groupId: groupId,
          ownerUserId: detail['ownerUserId']?.toString(),
          updatedAt: _readInt(detail['updatedAt']),
        );
        return true;
      case 'group_mute_all_changed':
        final isAllMuted = _readBool(
          detail['shutUpAllMember'] ?? detail['isAllMuted'],
        );
        await _patchGroupFields(
          owner: owner,
          groupId: groupId,
          isAllMuted: isAllMuted,
        );
        return true;
      case 'member_muted':
        final userId = ChatIdFormat.rawUserUid(
          detail['userId']?.toString() ?? memberIds.firstOrNull ?? '',
        );
        final muteUntil = _readInt(detail['muteUntil']);
        if (userId.isNotEmpty) {
          await GroupMemberLocalStore.instance.patchUser(
            ownerUserId: owner,
            groupId: groupId,
            userId: userId,
            transform: (current) =>
                current.copyWith(muteUntil: muteUntil > 0 ? muteUntil : 0),
          );
          _patchMemoryMemberMuteUntil(
            groupId: groupId,
            userId: userId,
            muteUntil: muteUntil > 0 ? muteUntil : 0,
          );
        }
        return true;
      default:
        return false;
    }
  }

  Future<void> afterGroupChangedApplied(String action) async {
    final normalized = action.trim().toLowerCase();
    const membershipActions = <String>{
      'member_added',
      'member_removed',
      'member_left',
      'group_dismissed',
      'group_name_changed',
      'group_avatar_changed',
    };
    if (membershipActions.contains(normalized)) {
      await refreshUIKitGroupList();
    }
    if (normalized == 'member_added') {
      unawaited(
        ConversationSyncService.instance
            .flushPendingGroupConversationsAfterMembershipChange(),
      );
    }
  }

  Future<void> upsertGroupAvatar({
    required String groupId,
    required String avatarUrl,
    String? avatarPreviewUrl,
    int? avatarVersion,
  }) async {
    final id = groupId.trim();
    final normalized = normalizeObjectUrl(avatarUrl.trim());
    if (id.isEmpty || normalized.isEmpty) {
      return;
    }
    final owner = _ownerUserId();
    if (owner.isEmpty || id.isEmpty) {
      return;
    }

    // 头像上传成功后的本地上传响应（thumbUrl + avatarVersion）必须立即
    // 落地 GroupLocalStore，否则 Avatar 的 avatarCacheKey 永远命中旧值，
    // CachedNetworkImage 显示旧头像（参见 conversation-list-notifier
    // 头像缓存键契约 `avatar|group|$id|$avatarVersion|thumb`）。
    final existing = await GroupLocalStore.instance.read(
      groupId: id,
      ownerUserId: owner,
    );
    final incomingVersion = avatarVersion != null && avatarVersion > 0
        ? avatarVersion
        : (existing?.avatarVersion ?? 0) + 1;
    final base = existing ??
        MeGroupRecord(
          groupId: id,
          groupType: '',
          groupName: '',
          displayAlias: '',
          avatarUrl: '',
          notice: '',
          memberCount: 0,
          myRole: 200,
          myNameCard: '',
          joinedAt: 0,
          updatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
        );
    final next = base.copyWith(
      avatarUrl: normalized,
      avatarPreviewUrl: avatarPreviewUrl ?? base.avatarPreviewUrl,
      avatarVersion: incomingVersion,
      updatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    await GroupLocalStore.instance.upsert(
      ownerUserId: owner,
      record: next,
    );
    await _syncIdentityToNativeSdk(groupId: id, faceUrl: normalized);
    await publishGroupConversationDisplay(
      groupId: id,
      avatarUrl: normalized,
    );
    await refreshGroupDetail(id, refresh: true);
    notifyProfileRefresh(id);
    await refreshUIKitGroupList();
  }

  Future<void> applyOptimisticAvatar({
    required String groupId,
    required String avatarUrl,
    String? avatarPreviewUrl,
    int? avatarVersion,
  }) async {
    await upsertGroupAvatar(
      groupId: groupId,
      avatarUrl: avatarUrl,
      avatarPreviewUrl: avatarPreviewUrl,
      avatarVersion: avatarVersion,
    );
  }

  Future<void> applyOptimisticMyNameCard({
    required String groupId,
    required String nameCard,
  }) async {
    await _patchGroupFields(
      owner: _ownerUserId(),
      groupId: groupId,
      myNameCard: nameCard,
    );
  }

  Future<void> applyOptimisticGroupName({
    required String groupId,
    required String groupName,
  }) async {
    final owner = _ownerUserId();
    final id = ChatIdFormat.normalizeGroupId(groupId);
    final name = groupName.trim();
    if (owner.isEmpty || id.isEmpty || name.isEmpty) {
      return;
    }
    if (GroupDisplayResolver.looksLikeGroupIdLabel(name, groupId: id)) {
      return;
    }
    final existing = await GroupLocalStore.instance.read(
      groupId: id,
      ownerUserId: owner,
    );
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final base = existing ??
        MeGroupRecord(
          groupId: id,
          groupType: '',
          groupName: '',
          displayAlias: '',
          avatarUrl: '',
          notice: '',
          memberCount: 0,
          myRole: 200,
          myNameCard: '',
          joinedAt: 0,
          updatedAt: now,
        );
    await GroupLocalStore.instance.upsert(
      ownerUserId: owner,
      record: base.copyWith(
        groupName: name,
        updatedAt: now,
      ),
    );
    await publishGroupConversationDisplay(
      groupId: id,
      groupName: name,
    );
    notifyProfileRefresh(id);
    await refreshUIKitGroupList();
  }

  Future<void> applyOptimisticNotice({
    required String groupId,
    required String notice,
  }) async {
    final owner = _ownerUserId();
    if (owner.isEmpty || groupId.trim().isEmpty) return;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await GroupLocalStore.instance.patch(
      ownerUserId: owner,
      groupId: groupId,
      transform: (current) => current.copyWith(
        notice: notice,
        noticeUpdatedAt: now,
        noticeUpdatedBy: owner,
        updatedAt: current.updatedAt > now ? current.updatedAt : now,
      ),
    );
  }

  Future<void> refreshUIKitGroupList() async {
    try {
      await serviceLocator<TUIFriendShipViewModel>().loadGroupListData();
    } catch (e) {
      _log('refreshUIKitGroupList failed: $e');
    }
  }

  String _removalWorkKey(String groupId) {
    final identity = SessionIdentityService.instance.capture();
    return '${identity.ownerUserId}|${identity.generation}|'
        '${GroupLocalStore.groupEquivalenceKey(groupId)}';
  }

  /// Navigation awaits only the group row deletion, never member/history cleanup.
  Future<void> onSelfRemovedFromGroup(String groupId) {
    final owner = _ownerUserId();
    final id = ChatIdFormat.canonicalGroupStorageId(groupId);
    if (owner.isEmpty || id.isEmpty || isForbiddenGroupStorageId(id)) {
      return Future<void>.value();
    }
    final identity =
        SessionIdentityService.instance.capture(ownerUserId: owner);
    final watch = Stopwatch()..start();
    return _removalWork.run(
      key: _removalWorkKey(id),
      isCurrent: () => SessionIdentityService.instance.isCurrent(identity),
      hide: () async {
        _markExplicitGroupRemoval(id);
        _bumpJoinedGroupsRevision();
        GroupMemberRolePending.instance.clearGroup(id);
        try {
          final model = serviceLocator<TUIFriendShipViewModel>();
          for (final group in model.groupList.toList()) {
            if (ChatIdFormat.groupIdsEquivalent(group.groupID, id)) {
              model.removeGroupLocally(group.groupID);
            }
          }
        } catch (_) {}
        await GroupLocalStore.instance.delete(ownerUserId: owner, groupId: id);
        GroupLeaveDiagLog.log('local_hide_done',
            groupId: id, extras: {'elapsedMs': watch.elapsedMilliseconds});
      },
      cleanup: (isCurrent) async {
        final cleanupWatch = Stopwatch()..start();
        if (!isCurrent()) return;
        await GroupMemberLocalStore.instance
            .clearGroup(ownerUserId: owner, groupId: id);
        if (!isCurrent()) return;
        await _purgeGroupConversation(id,
            explicitMembershipEvent: true,
            reason: 'confirmed_self_removed',
            isCurrent: isCurrent);
        GroupLeaveDiagLog.log('local_cleanup_done',
            groupId: id,
            extras: {'elapsedMs': cleanupWatch.elapsedMilliseconds});
      },
      onError: (error, stack) => GroupLeaveDiagLog.log('local_cleanup_fail',
          groupId: id,
          extras: {'error': '$error', 'elapsedMs': watch.elapsedMilliseconds}),
    );
  }

  /// 从 IM SDK 与本地会话库移除群会话，并通知消息列表刷新。
  @visibleForTesting
  static bool shouldDestructivelyPurgeGroupConversation({
    required bool explicitMembershipEvent,
  }) {
    return explicitMembershipEvent;
  }

  Future<void> _purgeGroupConversation(
    String groupId, {
    required bool explicitMembershipEvent,
    required String reason,
    bool Function()? isCurrent,
  }) async {
    final id = groupId.trim();
    if (id.isEmpty) {
      return;
    }
    final identity = SessionIdentityService.instance.capture();
    bool valid() =>
        SessionIdentityService.instance.isCurrent(identity) &&
        (isCurrent?.call() ?? true);
    if (!valid()) return;
    final purgeKey = '${identity.ownerUserId}|${identity.generation}|$id';
    // 主动退出回调与 SDK 的 member_left/group_dismissed 事件可能同时到达。
    // 同一群的重型清理只允许一个实例执行，避免重复删库、清历史和刷新。
    if (!_purgeInFlight.add(purgeKey)) {
      GroupLeaveDiagLog.log(
        'purge_conversation_deduped',
        groupId: id,
        extras: <String, Object?>{'reason': reason},
      );
      return;
    }
    try {
      await _purgeGroupConversationImpl(
        id,
        explicitMembershipEvent: explicitMembershipEvent,
        reason: reason,
        isCurrent: valid,
      );
    } finally {
      _purgeInFlight.remove(purgeKey);
    }
  }

  Future<void> _purgeGroupConversationImpl(
    String id, {
    required bool explicitMembershipEvent,
    required String reason,
    required bool Function() isCurrent,
  }) async {
    if (!shouldDestructivelyPurgeGroupConversation(
      explicitMembershipEvent: explicitMembershipEvent,
    )) {
      // 普通列表差异只让 shouldShowConversation 暂时过滤；保留 SDK 与
      // SQLite 会话，待后续完整群列表/成员事件恢复，绝不清消息历史。
      GroupLeaveDiagLog.log(
        'purge_conversation_suppressed_unverified',
        groupId: id,
        extras: <String, Object?>{'reason': reason},
      );
      SqfliteLockProfileLog.event(
        'purge_conversation_suppressed_unverified',
        extras: <String, Object?>{'groupId': id, 'reason': reason},
      );
      return;
    }
    // 禁止把 c2c_ 当群清历史/删会话（会误伤真单聊）。
    if (isForbiddenGroupStorageId(id)) {
      _log('purge_reject_forbidden_id groupId=$id');
      GroupLeaveDiagLog.log(
        'purge_reject_forbidden_id',
        groupId: id,
        extras: const <String, Object?>{'path': 'purge'},
      );
      SqfliteLockProfileLog.event(
        'purge_reject_forbidden_id',
        extras: <String, Object?>{'groupId': id, 'path': 'purge'},
      );
      return;
    }
    final conversationId = 'group_$id';
    // 清历史路径会故意「保壳」；退群/幽灵清理必须强制删掉会话行。
    ArchiveHistoryProvider.clearHistoryClearPending(id);
    ArchiveHistoryProvider.clearHistoryClearPending(conversationId);
    try {
      await ConversationSyncService.instance.onViewModelConversationsDeleted(
        <String>[conversationId],
        force: true,
        immediate: true,
      );
    } catch (e) {
      _log('purgeGroupConversation local delete failed groupId=$id error=$e');
      GroupLeaveDiagLog.log(
        'purge_conversation_local_fail',
        groupId: id,
        extras: <String, Object?>{'error': e.toString()},
      );
    }
    if (!isCurrent()) return;
    // Clear the separate pin projection before slow history/SDK cleanup.
    await ConversationPinSyncService.instance.removeDeletedConversation(
      conversationId,
    );
    if (!isCurrent()) return;
    await _clearGroupChatHistory(id, isCurrent: isCurrent);
    if (!isCurrent()) return;
    try {
      await serviceLocator<ConversationService>().deleteConversation(
        conversationID: conversationId,
      );
    } catch (e) {
      _log('purgeGroupConversation sdk delete failed groupId=$id error=$e');
      GroupLeaveDiagLog.log(
        'purge_conversation_sdk_fail',
        groupId: id,
        extras: <String, Object?>{'error': e.toString()},
      );
    }
    if (!isCurrent()) return;
    ConversationRefreshBus.instance.requestRefresh(
      reason: 'group_self_removed',
      conversationId: conversationId,
      delay: const Duration(milliseconds: 200),
    );
  }

  /// 退群/被踢后清空本端 IM 记录、归档兜底与内存消息列表。
  Future<void> _clearGroupChatHistory(String groupId,
      {required bool Function() isCurrent}) async {
    final id = groupId.trim();
    if (id.isEmpty || !isCurrent()) {
      return;
    }
    if (isForbiddenGroupStorageId(id)) {
      _log('purge_reject_forbidden_id groupId=$id path=clear');
      GroupLeaveDiagLog.log(
        'purge_reject_forbidden_id',
        groupId: id,
        extras: const <String, Object?>{'path': 'clear'},
      );
      SqfliteLockProfileLog.event(
        'purge_reject_forbidden_id',
        extras: <String, Object?>{'groupId': id, 'path': 'clear'},
      );
      return;
    }
    GroupLeaveDiagLog.log('clear_history_start', groupId: id);

    final globalModel = serviceLocator<TUIChatGlobalModel>();
    for (final key in <String>{id, 'group_$id'}) {
      globalModel.clearLocalHistoryAsEmptyLoaded(key);
    }

    ArchiveHistoryProvider.markHistoryClearPending(id);
    try {
      if (kIsWeb) {
        await ArchiveHistoryProvider.completeHistoryClear(
          isGroup: true,
          conversationID: id,
        );
        GroupLeaveDiagLog.log(
          'clear_history_done',
          groupId: id,
          extras: const <String, Object?>{'route': 'web_archive_only'},
        );
        return;
      }

      final result = await serviceLocator<MessageService>()
          .clearGroupHistoryMessage(groupID: id);
      if (!isCurrent()) return;
      if (result.code == 0) {
        await ArchiveHistoryProvider.completeHistoryClear(
          isGroup: true,
          conversationID: id,
        );
        GroupLeaveDiagLog.log('clear_history_done', groupId: id);
        return;
      }

      ArchiveHistoryProvider.clearHistoryClearPending(id);
      GroupLeaveDiagLog.log(
        'clear_history_sdk_fail',
        groupId: id,
        extras: <String, Object?>{'code': result.code, 'desc': result.desc},
      );
    } catch (e) {
      ArchiveHistoryProvider.clearHistoryClearPending(id);
      _log('clearGroupChatHistory failed groupId=$id error=$e');
      GroupLeaveDiagLog.log(
        'clear_history_fail',
        groupId: id,
        extras: <String, Object?>{'error': e.toString()},
      );
    }
  }

  /// 已退群但 IM 会话仍残留在列表时，按本地群成员表对齐剔除。
  Future<void> pruneStaleGroupConversations({String reason = 'manual'}) async {
    if (!SelfHostedGroupBridge.governanceEnabled) {
      return;
    }
    final owner = _ownerUserId();
    if (owner.isEmpty || !_groupListSyncedOnce) {
      return;
    }
    final joinedIds =
        (await GroupLocalStore.instance.readAll(ownerUserId: owner))
            .map((group) => group.groupId.trim())
            .where((id) => id.isNotEmpty)
            .toSet();
    final conversations = await ConversationLocalStore.instance
        .listGroupConversationIds(ownerUserId: owner);
    final conversationGroupIds = <String>[];
    for (final conversationId in conversations) {
      if (!conversationId.startsWith('group_')) {
        continue;
      }
      final groupId = conversationId.substring(6);
      if (groupId.isNotEmpty) {
        conversationGroupIds.add(groupId);
      }
    }
    final staleGroupIds = removedGroupIdsByEquivalence(
      existingIds: conversationGroupIds,
      joinedIds: joinedIds,
    );
    if (staleGroupIds.isEmpty) {
      return;
    }
    _log(
      'pruneStaleGroupConversations reason=$reason count=${staleGroupIds.length}',
    );
    for (final groupId in staleGroupIds) {
      await _purgeGroupConversation(
        groupId,
        explicitMembershipEvent: false,
        reason: 'membership_snapshot_prune:$reason',
      );
    }
  }

  @visibleForTesting
  static List<String> removedGroupIdsByEquivalence({
    required Iterable<String> existingIds,
    required Iterable<String> joinedIds,
  }) {
    final joinedKeys = joinedIds
        .map(GroupLocalStore.groupEquivalenceKey)
        .where((key) => key.isNotEmpty)
        .toSet();
    return existingIds
        .map((id) => id.trim())
        .where(
          (id) =>
              id.isNotEmpty &&
              !joinedKeys.contains(GroupLocalStore.groupEquivalenceKey(id)),
        )
        .toList(growable: false);
  }

  bool _isSelfRemovedFromGroupEvent({
    required String action,
    required String owner,
    required List<String> memberIds,
    required FriendRealtimeEvent event,
  }) {
    final detail = event.detail ?? const <String, dynamic>{};
    return isSelfRemovedFromGroupMembershipEvent(
      action: action,
      ownerUserId: owner,
      memberUserIds: memberIds,
      fromUserId: event.fromUserId,
      detailUserId:
          detail['userId']?.toString() ?? detail['user_id']?.toString(),
    );
  }

  Future<void> clearSession() async {
    MeGroupApi.instance.clearConfirmedGroupDetails();
    _removalWork.clear();
    _deferredSyncFullTimer?.cancel();
    _deferredSyncFullTimer = null;
    _groupListBackgroundSyncTimer?.cancel();
    _groupListBackgroundSyncTimer = null;
    _deferredSyncFullReason = null;
    _deferredSyncFullRefresh = false;
    _revisionCoalesceTimer?.cancel();
    _revisionCoalesceTimer = null;
    _revisionCoalesceScheduled = false;
    _syncGeneration++;
    _explicitlyRemovedGroupKeys.clear();
    _activeConversationEvidenceKeys.clear();
    _snapshotMissingCounts.clear();
    _syncInFlight = null;
    _syncInFlightRefresh = false;
    _groupListSyncedOnce = false;
    _lastMeGroupsNetworkAt = null;
    _groupDetailRefreshInFlight.clear();
    _groupDetailRefreshForcesRemote.clear();
    _groupDetailLastSuccessAtMs.clear();
    _membershipSnapshotInFlight.clear();
    _groupMemberPageInFlight.clear();
    await GroupLocalStore.instance.clearSession();
    await GroupMemberLocalStore.instance.clearSession();
    MyGroupListController.instance.clearSession();
    joinedGroupsRevision.value++;
  }

  @visibleForTesting
  void bumpJoinedGroupsRevisionForTest() => _bumpJoinedGroupsRevision();

  @visibleForTesting
  void markExplicitGroupRemovalForTest(String id) =>
      _markExplicitGroupRemoval(id);

  @visibleForTesting
  void clearExplicitGroupRemovalForTest(String id) =>
      _clearExplicitGroupRemoval(id);

  @visibleForTesting
  void flushJoinedGroupsRevisionCoalesceForTest() {
    _revisionCoalesceTimer?.cancel();
    _revisionCoalesceTimer = null;
    if (_revisionCoalesceScheduled) {
      _revisionCoalesceScheduled = false;
      joinedGroupsRevision.value++;
    }
  }

  Future<List<String>> adminSelfHostedGroupIds() async {
    final owner = _ownerUserId();
    final groups = await GroupLocalStore.instance.readAll(ownerUserId: owner);
    return groups
        .where((group) {
          if (!GroupJoinApi.isSelfHostedJoinGroupType(group.groupType)) {
            return false;
          }
          return GroupRolePolicy.isManagerRole(group.myRole);
        })
        .map((group) => group.groupId)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<String>> adminGroupIds() async {
    final owner = _ownerUserId();
    final groups = await GroupLocalStore.instance.readAll(ownerUserId: owner);
    return groups
        .where((group) {
          return GroupRolePolicy.isManagerRole(group.myRole);
        })
        .map((group) => group.groupId)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _patchGroupFields({
    required String owner,
    required String groupId,
    int? myRole,
    String? myNameCard,
    int? updatedAt,
    String? ownerUserId,
    bool? isAllMuted,
  }) async {
    final current = await GroupLocalStore.instance.read(
      groupId: groupId,
      ownerUserId: owner,
    );
    if (current == null) {
      await refreshGroupDetail(groupId);
      return;
    }
    await GroupLocalStore.instance.upsert(
      ownerUserId: owner,
      record: current.copyWith(
        // memberCount is owned exclusively by refreshGroupDetail().
        memberCount: current.memberCount,
        myRole: myRole ?? current.myRole,
        myNameCard: myNameCard ?? current.myNameCard,
        updatedAt: updatedAt ?? current.updatedAt,
        ownerUserId: ownerUserId ?? current.ownerUserId,
        isAllMuted: isAllMuted ?? current.isAllMuted,
      ),
    );
  }

  /// SDK 群名/头像回调的本地投影。失败不抛给 UIKit。
  Future<void> applySdkGroupIdentity({
    required String groupId,
    String? groupName,
    String? faceUrl,
  }) async {
    final owner = _ownerUserId();
    final id = groupId.trim();
    final name = groupName?.trim();
    final face = faceUrl?.trim();
    if (owner.isEmpty || id.isEmpty) {
      return;
    }
    if ((name == null || name.isEmpty) && (face == null || face.isEmpty)) {
      return;
    }
    await GroupLocalStore.instance.patch(
      ownerUserId: owner,
      groupId: id,
      transform: (current) => current.copyWith(
        groupName: (name != null && name.isNotEmpty) ? name : current.groupName,
        avatarUrl: (face != null && face.isNotEmpty) ? face : current.avatarUrl,
      ),
    );
    await publishGroupConversationDisplay(
      groupId: id,
      groupName: (name != null && name.isNotEmpty) ? name : null,
      avatarUrl: (face != null && face.isNotEmpty) ? face : null,
    );
  }

  Future<void> _syncIdentityToNativeSdk({
    required String groupId,
    String? groupName,
    String? faceUrl,
  }) async {
    final id = groupId.trim();
    final name = groupName?.trim();
    final face = faceUrl?.trim();
    if (id.isEmpty) {
      return;
    }
    if ((name == null || name.isEmpty) && (face == null || face.isEmpty)) {
      return;
    }
    final cached = GroupLocalStore.instance.readCached(groupId: id);
    final info = V2TimGroupInfo(
      groupID: id,
      groupType: cached?.groupType.trim() ?? '',
    );
    if (name != null && name.isNotEmpty) {
      info.groupName = name;
    }
    if (face != null && face.isNotEmpty) {
      info.faceUrl = face;
    }
    try {
      final res = await TencentImSDKPlugin.v2TIMManager
          .getGroupManager()
          .setGroupInfo(info: info);
      if (res.code != 0) {
        _log(
          'syncIdentityToNativeSdk failed groupId=$id '
          'code=${res.code} desc=${res.desc}',
        );
      }
    } catch (e) {
      _log('syncIdentityToNativeSdk failed groupId=$id error=$e');
    }
  }

  /// 群名/头像写入群资料库后，双写会话列表内存与本地库（展示仍以群库为准）。
  Future<void> publishGroupConversationDisplay({
    required String groupId,
    String? groupName,
    String? avatarUrl,
  }) async {
    final id = groupId.trim();
    if (id.isEmpty) {
      return;
    }
    final cached = GroupLocalStore.instance.readCached(groupId: id);
    var name = (groupName ?? cached?.groupName ?? '').trim();
    if (name.isNotEmpty &&
        GroupDisplayResolver.looksLikeGroupIdLabel(name, groupId: id)) {
      name = '';
    }
    var face =
        normalizeObjectUrl((avatarUrl ?? cached?.avatarUrl ?? '').trim());
    if (name.isEmpty && face.isEmpty) {
      return;
    }

    final conversationId = id.startsWith('group_') ? id : 'group_$id';
    final canonical = ChatIdFormat.canonicalGroupStorageId(id);
    if (name.isNotEmpty) {
      DisplayNameStore.instance.setGroup(id, name);
      if (canonical.isNotEmpty && canonical != id) {
        DisplayNameStore.instance.setGroup(canonical, name);
      }
      try {
        serviceLocator<TUIConversationViewModel>()
            .updateGroupShowName(id, name);
      } catch (e) {
        _log('publishGroupConversationDisplay updateGroupShowName failed: $e');
      }
      try {
        serviceLocator<TUIFriendShipViewModel>().updateGroupNameLocal(id, name);
      } catch (e) {
        _log('publishGroupConversationDisplay updateGroupNameLocal failed: $e');
      }
    }
    if (face.isNotEmpty) {
      try {
        serviceLocator<TUIConversationViewModel>().updateGroupFaceUrl(id, face);
      } catch (e) {
        _log('publishGroupConversationDisplay updateGroupFaceUrl failed: $e');
      }
    }

    V2TimConversation? match;
    for (final item in ChatSessionController.instance.conversations) {
      final gid = item.groupID?.trim() ?? '';
      if (MessageConversationId.sameConversation(
            item.conversationID,
            conversationId,
          ) ||
          (gid.isNotEmpty && ChatIdFormat.groupIdsEquivalent(gid, id))) {
        match = item;
        break;
      }
    }
    if (match == null) {
      final candidates = <String>{
        conversationId,
        id,
        if (!id.startsWith('group_')) 'group_$id',
        if (canonical.isNotEmpty) canonical,
        if (canonical.isNotEmpty && !canonical.startsWith('group_'))
          'group_$canonical',
      };
      for (final candidate in candidates) {
        try {
          final row = await ConversationLocalStore.instance.conversationById(
            candidate,
          );
          if (row != null) {
            match = row;
            break;
          }
        } catch (_) {}
      }
    }

    if (match != null) {
      try {
        await ConversationSyncService.instance.applyConversationMetadataPatch(
          conversationID: match.conversationID,
          showName: name.isEmpty ? null : name,
          faceUrl: face.isEmpty ? null : face,
          snapshot: match,
          remoteAuthority: true,
        );
      } catch (e) {
        _log('publishGroupConversationDisplay commit failed: $e');
      }
    }

    if (name.isNotEmpty) {
      try {
        serviceLocator<TUISearchViewModel>().patchGroupShowNameLocally(
          groupId: id,
          showName: name,
        );
      } catch (e) {
        _log('publishGroupConversationDisplay patchSearch failed: $e');
      }
    }
  }

  List<String> _memberIds(
    FriendRealtimeEvent event,
    Map<String, dynamic> detail,
  ) {
    final fromDetail = detail['memberUserIds'] ?? detail['member_user_ids'];
    if (fromDetail is List) {
      return fromDetail
          .map((e) => ChatIdFormat.rawUserUid(e?.toString() ?? ''))
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return event.memberUserIds
        .map(ChatIdFormat.rawUserUid)
        .where((e) => e.isNotEmpty)
        .toList();
  }

  int _parseOffset(String nextSeq) {
    final normalized = nextSeq.trim();
    if (normalized.isEmpty || normalized == '0') {
      return 0;
    }
    return int.tryParse(normalized) ?? 0;
  }

  bool _readBool(dynamic value) => MeGroupRecord.parseBoolLikeIM(value);

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  V2TimGroupMemberFullInfo _toV2TimMember(GroupMemberRecord record) {
    return V2TimGroupMemberFullInfo(
      userID: record.userId,
      role: record.role,
      joinTime: record.joinedAt > 0 ? record.joinedAt ~/ 1000 : null,
      nickName: record.nickname,
      nameCard: record.nameCard,
      friendRemark: record.friendRemark,
      faceUrl: record.avatarUrl,
      muteUntil: record.muteUntil > 0 ? record.muteUntil : null,
    );
  }

  void _patchMemoryMemberMuteUntil({
    required String groupId,
    required String userId,
    required int muteUntil,
  }) {
    final current = GroupMemberStore.instance.memberOf(groupId, userId);
    if (current == null) {
      return;
    }
    GroupMemberStore.instance.putMember(
      groupId,
      V2TimGroupMemberFullInfo(
        userID: current.userID,
        role: current.role,
        nickName: current.nickName,
        nameCard: current.nameCard,
        friendRemark: current.friendRemark,
        faceUrl: current.faceUrl,
        joinTime: current.joinTime,
        muteUntil: muteUntil,
        customInfo: current.customInfo,
      ),
    );
  }

  void notifyProfileRefresh(String groupId, {bool memberList = false}) {
    try {
      final listenerModel = serviceLocator<TUIGroupListenerModel>();
      listenerModel.requestProfileRefresh(
        NeedUpdate(
          groupId,
          memberList ? UpdateType.memberListReload : UpdateType.groupInfo,
          '',
        ),
      );
    } catch (_) {}
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
