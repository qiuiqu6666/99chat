// ignore_for_file: unnecessary_getters_setters, avoid_print

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_filter_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_role.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_role_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/receive_message_opt_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_operation_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_operation_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_search_param.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_search_param.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_search_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_search_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/life_cycle/group_profile_life_cycle.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_conversation_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_uikit/data_services/conversation/conversation_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/core_services_implements.dart';
import 'package:tencent_cloud_chat_uikit/data_services/friendShip/friendship_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/self_hosted_group_bridge.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/self_hosted_group_invite_bridge.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/group_role_policy.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/picker_user_filter.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_group_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/utils/group_invite_member_page_meta.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

class TUIGroupProfileModel extends ChangeNotifier {
  TUIGroupProfileModel() {
    GroupMemberLocalStore.instance.commitListenable
        .addListener(_onLocalMemberCommit);
    GroupLocalStore.instance.commitListenable.addListener(_onLocalGroupCommit);
  }

  final CoreServicesImpl _coreServices = serviceLocator<CoreServicesImpl>();
  final GroupServices _groupServices = serviceLocator<GroupServices>();
  final ConversationService _conversationService =
      serviceLocator<ConversationService>();
  final MessageService _messageService = serviceLocator<MessageService>();
  final FriendshipServices _friendshipServices =
      serviceLocator<FriendshipServices>();
  GroupProfileLifeCycle? _lifeCycle;

  V2TimConversation? _conversation;
  String _groupID = "";
  List<V2TimFriendInfo>? _contactList;
  List<V2TimGroupMemberFullInfo?>? _groupMemberList;
  String _groupMemberListSeq = "0";
  bool _groupMemberListLoading = false;
  bool _groupMemberListLoadingMore = false;
  bool _groupMemberListComplete = false;
  bool _entryMemberPages = false;
  bool _entryMemberHasMore = false;
  bool _entryMemberError = false;
  int _entryMemberOffset = 0;
  int _memberPageGeneration = 0;
  Future<void>? _memberEntryTask;
  Future<void>? _entryPageTask;
  bool _hasCompleteMemberSnapshot = false;
  int? _completeSnapshotMemberCount;
  Future<void>? _memberCountRead;
  bool _memberCountReadPending = false;
  Future<void>? _groupMemberFullSyncInFlight;
  Future<void>? _remainingMemberLoadInFlight;
  int _successfulMemberPageRevision = 0;
  int _memberMembershipRevision = 0;
  ({
    SessionIdentity identity,
    int generation,
    int membershipRevision,
    DateTime at
  })? _memberListConfirmed;
  int _localProjectionGeneration = 0;
  bool _localProjectionInFlight = false;
  bool _localProjectionDirty = false;
  bool _disposed = false;
  static const memberPreviewSize = 10;

  /// 资料页预览只拉后端成员快照第一页。默认 50，且不带 role。
  static const memberPreviewRestPageSize = 50;
  static const localMemberWindowSize = 200;
  Future<void>? _memberPageTask;
  int _memberWindowRevision = 0;
  bool _projectionSnapshot = false;
  Map<String, V2TimGroupMemberFullInfo> _localManagementPreview =
      <String, V2TimGroupMemberFullInfo>{};
  Map<String, V2TimGroupMemberFullInfo>? _managementMembers;
  List<V2TimGroupMemberFullInfo> _previewOrdinaryMembers =
      <V2TimGroupMemberFullInfo>[];
  bool _previewMembersReady = false;
  // Reopening a route reuses management members, never a group-name snapshot.
  // Entries are bounded, short-lived and valid only in the same login session.
  static final _recentProfiles = <String,
      ({
    SessionIdentity identity,
    DateTime confirmedAt,
    Map<String, V2TimGroupMemberFullInfo> members,
  })>{};
  int _managementLoadGeneration = 0;
  int? _profileManagementGeneration;
  ({SessionIdentity identity, int generation, Future<void> task})?
      _managementRequest;
  bool _managementLoading = false;
  bool _managementLoadError = false;
  bool _groupDetailLoading = false;
  bool _groupDetailLoadError = false;
  bool get isGroupDetailLoading => _groupDetailLoading;
  bool get hasGroupDetailLoadError => _groupDetailLoadError;
  ({
    SessionIdentity identity,
    int generation,
    MeGroupRecord record
  })? _activeDetail;

  // Cache expiry controls reuse by a new route, not the identity already
  // confirmed for a mounted page. Account/group changes still invalidate it.
  MeGroupRecord? get _confirmedSelfDetail {
    final fresh = MeGroupApi.instance.confirmedGroupDetail(_groupID);
    if (fresh != null) {
      _activeDetail = (
        identity: SessionIdentityService.instance.capture(),
        generation: _localProjectionGeneration,
        record: fresh,
      );
    }
    final active = _activeDetail;
    return active != null &&
            active.generation == _localProjectionGeneration &&
            SessionIdentityService.instance.isCurrent(active.identity)
        ? active.record
        : null;
  }

  SessionIdentity? _managementIdentity;
  bool get hasLoadedManagementMembers =>
      _managementMembers != null &&
      _managementIdentity != null &&
      SessionIdentityService.instance.isCurrent(_managementIdentity!);
  bool get isManagementMemberListLoading => _managementLoading;
  bool get hasManagementMemberListError => _managementLoadError;
  List<V2TimGroupMemberFullInfo?> get managementMemberList =>
      hasLoadedManagementMembers
          ? _managementMembers!.values
              .where((member) => !_isTombstonedMember(_groupID, member.userID))
              .toList()
          : [];

  /// Display-only owner/admin rows from disk. Never authorizes writes.
  bool get hasLocalManagementPreview => _localManagementPreview.isNotEmpty;

  List<V2TimGroupMemberFullInfo> get localManagementPreview =>
      _localManagementPreview.values.toList();

  bool get isProfilePreviewPending => !_previewMembersReady;

  /// Profile avatar grid: owner + admins first, then ordinary members to fill
  /// [memberPreviewSize]. Ordinary rows come from a dedicated members page,
  /// not the mixed `groupMemberList` window. Empty until that set is complete
  /// so the grid does not paint managers first and ordinary members later.
  List<V2TimGroupMemberFullInfo> get profilePreviewMembers {
    if (!_previewMembersReady) {
      return const <V2TimGroupMemberFullInfo>[];
    }
    final managers = _profilePreviewManagers();
    if (managers.length >= memberPreviewSize) {
      return managers.take(memberPreviewSize).toList();
    }
    final seen = <String>{
      for (final member in managers) _normalizeMemberUserId(member.userID),
    }..removeWhere((id) => id.isEmpty);
    final padded = <V2TimGroupMemberFullInfo>[...managers];
    for (final member in _previewOrdinaryMembers) {
      if (padded.length >= memberPreviewSize) {
        break;
      }
      final id = _normalizeMemberUserId(member.userID);
      if (id.isEmpty ||
          seen.contains(id) ||
          _isTombstonedMember(_groupID, member.userID) ||
          GroupRolePolicy.isManagerRole(member.role)) {
        continue;
      }
      seen.add(id);
      padded.add(member);
    }
    return padded;
  }

  List<V2TimGroupMemberFullInfo> _profilePreviewManagers() {
    final source = hasLoadedManagementMembers
        ? managementMemberList.whereType<V2TimGroupMemberFullInfo>()
        : _localManagementPreview.values;
    return [
      for (final member in source)
        if (GroupRolePolicy.isManagerRole(member.role) &&
            member.userID.trim().isNotEmpty &&
            !_isTombstonedMember(_groupID, member.userID))
          member,
    ];
  }

  /// Own identity comes from REST detail; other members use management pages.
  /// SDK roles never grant management permission.
  int? backendRoleForMember(String? userId) {
    final id = ChatIdFormat.rawUserUid(userId);
    if (id.isNotEmpty &&
        id == SessionIdentityService.instance.capture().ownerUserId) {
      final detail = _confirmedSelfDetail;
      if (detail != null) return detail.myRole;
    }
    if (id.isEmpty) return null;
    if (hasLoadedManagementMembers) {
      for (final member in managementMemberList) {
        if (member != null && ChatIdFormat.rawUserUid(member.userID) == id) {
          return member.role;
        }
      }
      return GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER;
    }
    if (GroupRolePolicy.canKickMemberEntry(
      selfRole: _confirmedSelfDetail?.myRole,
      groupType: _groupInfo?.groupType,
    )) {
      for (final member
          in groupMemberList.whereType<V2TimGroupMemberFullInfo>()) {
        if (ChatIdFormat.rawUserUid(member.userID) == id &&
            member.role ==
                GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER) {
          return GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER;
        }
      }
    }
    return null;
  }

  int? get backendSelfRole => backendRoleForMember(
      SessionIdentityService.instance.capture().ownerUserId);

  /// Custom profile builders receive the same backend identity as built-in UI.
  /// Keep the original SDK/local metadata object intact.
  V2TimGroupInfo? get groupInfoWithBackendRole {
    final info = groupInfo;
    if (info == null) return null;
    // SDK native JSON is not round-trippable (groupType is encoded differently).
    final view = V2TimGroupInfo(
      groupID: info.groupID,
      groupType: info.groupType,
      groupName: info.groupName,
      notification: info.notification,
      introduction: info.introduction,
      faceUrl: info.faceUrl,
      isAllMuted: info.isAllMuted,
      createTime: info.createTime,
      groupAddOpt: info.groupAddOpt,
      lastInfoTime: info.lastInfoTime,
      lastMessageTime: info.lastMessageTime,
      memberCount: info.memberCount,
      onlineCount: info.onlineCount,
      role: backendSelfRole,
      owner: info.owner,
      recvOpt: info.recvOpt,
      joinTime: info.joinTime,
      isSupportTopic: info.isSupportTopic,
      customInfo: info.customInfo,
      approveOpt: info.approveOpt,
      isEnablePermissionGroup: info.isEnablePermissionGroup,
      memberMaxCount: info.memberMaxCount,
      defaultPermissions: info.defaultPermissions,
    );
    for (final member in view.owner?.isNotEmpty == true
        ? <V2TimGroupMemberFullInfo?>[]
        : managementMemberList) {
      if (GroupRolePolicy.isOwnerRole(member?.role)) {
        view.owner = member!.userID;
        break;
      }
    }
    return view;
  }

  bool canKickMember(String userId) =>
      !_isTombstonedMember(_groupID, userId) &&
      backendRoleForMember(userId) != null &&
      canKickOffMember() &&
      ChatIdFormat.rawUserUid(userId) !=
          SessionIdentityService.instance.capture().ownerUserId &&
      GroupRolePolicy.canKickTargetMember(
        selfRole: backendSelfRole,
        targetRole: backendRoleForMember(userId),
      );

  bool canMuteMember(String userId) =>
      !_isTombstonedMember(_groupID, userId) &&
      backendRoleForMember(userId) != null &&
      GroupRolePolicy.canMuteTargetMember(
        selfRole: backendSelfRole,
        targetRole: backendRoleForMember(userId),
        groupType: groupInfo?.groupType,
        isAllMuted: groupInfo?.isAllMuted ?? false,
      );

  /// Display the complete backend management subset alongside the current SDK
  /// window. Never mutate SDK/cache records or advance their pagination cursor.
  List<V2TimGroupMemberFullInfo?> membersWithBackendRoles(
      List<V2TimGroupMemberFullInfo?> source) {
    final byId = <String, V2TimGroupMemberFullInfo>{};
    final managers = hasLoadedManagementMembers
        ? managementMemberList.whereType<V2TimGroupMemberFullInfo>()
        : _localManagementPreview.values;
    for (final member in managers) {
      final id = member.userID.trim();
      if (id.isNotEmpty && !_isTombstonedMember(_groupID, id))
        byId[id] = member;
    }
    for (final member in source.whereType<V2TimGroupMemberFullInfo>()) {
      final id = member.userID.trim();
      if (id.isEmpty ||
          byId.containsKey(id) ||
          _isTombstonedMember(_groupID, id)) continue;
      // Absence only means ordinary membership after a backend snapshot exists.
      final role = hasLoadedManagementMembers
          ? GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER
          : member.role;
      byId[id] = member.role == role
          ? member
          : (V2TimGroupMemberFullInfo.fromJson(member.toJson())..role = role);
    }
    return byId.values.toList();
  }

  V2TimGroupInfo? _groupInfo;
  int _groupInfoLoadGeneration = 0;
  Function(V2TimGroupMemberFullInfo groupMemberFullInfo,
      TapDownDetails? tapDetails)? onClickUser;

  GroupProfileLifeCycle? get lifeCycle => _lifeCycle;

  set lifeCycle(GroupProfileLifeCycle? value) {
    _lifeCycle = value;
  }

  V2TimConversation? get conversation => _conversation;

  set conversation(V2TimConversation? value) {
    _conversation = value;
  }

  String get groupID => _groupID;

  set groupID(String value) {
    if (value == _groupID) return;
    _entryMemberPages = false;
    _entryMemberHasMore = false;
    _entryMemberError = false;
    _memberEntryTask = null;
    _entryPageTask = null;
    _localProjectionGeneration++;
    _groupInfoLoadGeneration++;
    _memberPageTask = null;
    _groupMemberFullSyncInFlight = null;
    _remainingMemberLoadInFlight = null;
    _localManagementPreview = <String, V2TimGroupMemberFullInfo>{};
    _managementMembers = null;
    _previewOrdinaryMembers = <V2TimGroupMemberFullInfo>[];
    _previewMembersReady = false;
    _managementLoadGeneration++;
    _managementLoading = false;
    _managementLoadError = false;
    _groupDetailLoading = false;
    _groupDetailLoadError = false;
    _groupMemberList = [];
    _groupMemberListSeq = '0';
    _groupMemberListComplete = false;
    _hasCompleteMemberSnapshot = false;
    _groupID = value;
    _completeSnapshotMemberCount = null;
    unawaited(refreshMemberCountFromLocalSnapshot());
  }

  List<V2TimFriendInfo> get contactList => _contactList ?? [];

  set contactList(List<V2TimFriendInfo> value) {
    _contactList = value;
  }

  List<V2TimGroupMemberFullInfo?> get groupMemberList => _groupMemberList ?? [];

  bool get isGroupMemberListLoading => _groupMemberListLoading;

  bool get isGroupMemberListLoadingMore => _groupMemberListLoadingMore;

  // Role collection can continue after the first member page is visible.
  bool get isMemberEntryLoading =>
      _memberEntryTask != null && _groupMemberListLoading;
  bool get hasMemberEntryError => _entryMemberError;

  bool get hasCompleteMemberSnapshot => _hasCompleteMemberSnapshot;

  int displayedMemberCount({int? cachedCount}) {
    final storeCount =
        GroupLocalStore.instance.readCached(groupId: _groupID)?.memberCount ??
            0;
    if (storeCount > 0) {
      return storeCount;
    }
    final sdkCount = _groupInfo?.memberCount ?? 0;
    if (sdkCount > 0) {
      return sdkCount;
    }
    if (cachedCount != null && cachedCount > 0) {
      return cachedCount;
    }
    return 0;
  }

  /// A completed durable snapshot owns the total, independently of the
  /// currently loaded member page. This never fetches or decodes all members.
  Future<void> refreshMemberCountFromLocalSnapshot() {
    _memberCountReadPending = true;
    return _memberCountRead ??= (() async {
      try {
        while (_memberCountReadPending && !_disposed) {
          _memberCountReadPending = false;
          final generation = _localProjectionGeneration;
          final group = _groupID;
          final store = GroupMemberLocalStore.instance;
          final owner = store.currentOwnerUserId();
          final count = await store.readCompleteSnapshotCount(
              groupId: group, ownerUserId: owner);
          if (_disposed ||
              generation != _localProjectionGeneration ||
              group != _groupID ||
              owner != store.currentOwnerUserId()) {
            continue;
          }
          if (_completeSnapshotMemberCount != count) {
            _completeSnapshotMemberCount = count;
            notifyListeners();
          }
        }
      } catch (error) {
        debugPrint('[GroupMemberList] local_count_failed error=$error');
      } finally {
        _memberCountRead = null;
      }
    })();
  }

  /// 当前分页窗口是否还有下一页（非「全群已齐」语义）。
  bool get hasMoreGroupMembers {
    if (_entryMemberPages) return _entryMemberHasMore;
    final seq = _groupMemberListSeq.trim();
    if (seq.isNotEmpty && seq != '0') {
      return true;
    }
    return _listedMemberCount < _expectedMemberCount;
  }

  int get _listedMemberCount =>
      groupMemberList.whereType<V2TimGroupMemberFullInfo>().length;

  int get _expectedMemberCount {
    final local =
        GroupLocalStore.instance.readCached(groupId: _groupID)?.memberCount ??
            0;
    if (local > 0) {
      return local;
    }
    return _groupInfo?.memberCount ?? 0;
  }

  set groupMemberList(List<V2TimGroupMemberFullInfo?> value) {
    _groupMemberList = value;
  }

  void _onLocalMemberCommit() {
    if (_disposed || _groupID.trim().isEmpty) return;
    final commit = GroupMemberLocalStore.instance.commitListenable.value;
    final owner = GroupMemberLocalStore.instance.currentOwnerUserId();
    if (commit.ownerUserId.isNotEmpty && commit.ownerUserId != owner) return;
    if (commit.groupId.isNotEmpty &&
        GroupLocalStore.groupEquivalenceKey(commit.groupId) !=
            GroupLocalStore.groupEquivalenceKey(_groupID)) {
      return;
    }
    unawaited(refreshMemberCountFromLocalSnapshot());
    // SDK/local member commits only update the ordinary member window.
    // The management snapshot is owned exclusively by the role endpoint.
    final visibleIds = groupMemberList
        .whereType<V2TimGroupMemberFullInfo>()
        .map((m) => m.userID)
        .toSet();
    if (commit.kind == GroupMemberStoreMutationKind.upsert &&
        !commit.upserted.any((m) => visibleIds.contains(m.userId))) return;
    // A complete disk snapshot does not make the visible page a full list.
    if (commit.kind == GroupMemberStoreMutationKind.reset) {
      _hasCompleteMemberSnapshot = false;
      _groupMemberList = [];
      if (commit.ownerUserId.isEmpty) _localProjectionGeneration++;
      _memberWindowRevision++;
      notifyListeners();
      return;
    }
    if (commit.kind == GroupMemberStoreMutationKind.snapshot)
      _projectionSnapshot = true;
    if (commit.deletedUserIds.isNotEmpty) {
      final deleted = commit.deletedUserIds
          .map(_normalizeMemberUserId)
          .where((id) => id.isNotEmpty)
          .toSet();
      GroupMemberStore.instance.removeMembers(_groupID, deleted);
      _stripRemovedMembersFromProfile(deleted);
      _memberWindowRevision++;
      _memberMembershipRevision++;
      notifyListeners();
    }
    _localProjectionDirty = true;
    if (!_localProjectionInFlight) {
      unawaited(_drainDurableMemberProjection());
    }
  }

  void _onLocalGroupCommit() {
    if (_disposed || _groupID.isEmpty) return;
    final owner = GroupMemberLocalStore.instance.currentOwnerUserId();
    final commit = GroupLocalStore.instance.commitListenable.value;
    if (commit.ownerUserId != owner ||
        !commit.upserted.any((row) =>
            GroupLocalStore.groupEquivalenceKey(row.groupId) ==
            GroupLocalStore.groupEquivalenceKey(_groupID))) return;
    final stored = GroupLocalStore.instance
        .readCached(groupId: _groupID, ownerUserId: owner);
    if (stored != null) {
      _groupInfo = stored.toV2TimGroupInfo();
      notifyListeners();
    }
  }

  Future<void> _drainDurableMemberProjection() async {
    if (_localProjectionInFlight) return;
    _localProjectionInFlight = true;
    try {
      while (_localProjectionDirty && !_disposed) {
        _localProjectionDirty = false;
        final generation = _localProjectionGeneration;
        final groupID = _groupID;
        final groupKey = GroupLocalStore.groupEquivalenceKey(groupID);
        final snapshot = _projectionSnapshot;
        _projectionSnapshot = false;
        final revision = _memberWindowRevision;
        final ids = groupMemberList
            .whereType<V2TimGroupMemberFullInfo>()
            .map((m) => m.userID)
            .toList();
        if (ids.isEmpty) continue;
        final durable = await GroupMemberLocalStore.instance
            .readByUserIds(groupId: _groupID, userIds: ids);
        if (_disposed ||
            generation != _localProjectionGeneration ||
            revision != _memberWindowRevision ||
            GroupLocalStore.groupEquivalenceKey(_groupID) != groupKey) continue;
        final byId = {for (final member in durable) member.userID: member};
        // Preserve the loaded order. A background page must not expand,
        // shrink to page zero, or re-sort the user's current scroll window.
        final oldById = {
          for (final m in groupMemberList.whereType<V2TimGroupMemberFullInfo>())
            m.userID: m
        };
        _groupMemberList = ids
            .map((id) => byId[id] ?? (snapshot ? null : oldById[id]))
            .whereType<V2TimGroupMemberFullInfo>()
            .toList();
        GroupMemberStore.instance.putMembers(_groupID, durable, notify: true);
        notifyListeners();
      }
    } finally {
      _localProjectionInFlight = false;
      if (_localProjectionDirty && !_disposed) {
        unawaited(_drainDurableMemberProjection());
      }
    }
  }

  V2TimGroupInfo? get groupInfo => _groupInfo;

  set groupInfo(V2TimGroupInfo? value) {
    _groupInfo = value;
  }

  void loadData(String groupID) {
    _entryMemberPages = false;
    _entryMemberHasMore = false;
    _entryMemberError = false;
    _memberEntryTask = null;
    _entryPageTask = null;
    _managementMembers = null;
    _managementIdentity = null;
    _previewOrdinaryMembers = <V2TimGroupMemberFullInfo>[];
    _previewMembersReady = false;
    final identity = SessionIdentityService.instance.capture();
    final now = DateTime.now();
    _recentProfiles.removeWhere((_, snapshot) =>
        !SessionIdentityService.instance.isCurrent(snapshot.identity) ||
        now.difference(snapshot.confirmedAt) > const Duration(minutes: 5));
    final recent =
        _recentProfiles[GroupLocalStore.groupEquivalenceKey(groupID)];
    if (recent != null && recent.identity == identity) {
      _managementIdentity = recent.identity;
      _managementMembers = recent.members.map((id, member) =>
          MapEntry(id, V2TimGroupMemberFullInfo.fromJson(member.toJson())));
    }
    _managementLoadGeneration++;
    _managementLoading = false;
    _managementLoadError = false;
    _groupInfoLoadGeneration++;
    _localProjectionGeneration++;
    _localProjectionDirty = false;
    _groupID = groupID;
    _profileManagementGeneration = _localProjectionGeneration;
    _groupInfo = GroupLocalStore.instance
            .readCached(groupId: groupID, ownerUserId: identity.ownerUserId)
            ?.toV2TimGroupInfo();
    _groupMemberList = [];
    _groupMemberListSeq = '0';
    _groupMemberListComplete = false;
    _hasCompleteMemberSnapshot = false;
    _groupMemberListLoading = false;
    _completeSnapshotMemberCount = null;
    unawaited(refreshMemberCountFromLocalSnapshot());
    _groupMemberListLoadingMore = false;
    _memberPageTask = null;
    _groupMemberFullSyncInFlight = null;
    _memberWindowRevision++;
    if (hasLoadedManagementMembers &&
        _profilePreviewManagers().length >= memberPreviewSize) {
      _previewMembersReady = true;
    }
    unawaited(loadProfileMemberPreviewPage(groupID: groupID));
    unawaited(loadGroupInfo(groupID));
    unawaited(loadManagementMembers());
    unawaited(_loadSelfMember(groupID, _localProjectionGeneration));
    _loadConversation();
  }

  Future<void> _loadSelfMember(String groupID, int generation) async {
    final self = _coreServices.loginUserInfo?.userID?.trim() ?? '';
    if (self.isEmpty) return;
    final result = await _groupServices
        .getGroupMembersInfo(groupID: groupID, memberList: [self]);
    if (_disposed || generation != _localProjectionGeneration) return;
    if (result.code == 0) {
      GroupMemberStore.instance
          .putMembers(groupID, result.data ?? [], notify: false);
      notifyListeners();
    }
  }

  Future<void> loadGroupInfo(String groupID) async {
    final identity = SessionIdentityService.instance.capture();
    final requestGeneration = ++_groupInfoLoadGeneration;
    final requestedGroupKey = GroupLocalStore.groupEquivalenceKey(groupID);
    bool isCurrentRequest() {
      return !_disposed &&
          SessionIdentityService.instance.isCurrent(identity) &&
          requestGeneration == _groupInfoLoadGeneration &&
          GroupLocalStore.groupEquivalenceKey(_groupID) == requestedGroupKey;
    }

    _groupDetailLoading = true;
    _groupDetailLoadError = false;
    notifyListeners();
    try {
      // Prefer a known positive count. IM SDK often reports 0 for large /
      // Community groups; that zero must not erase Store or REST totals.
      // Reserve before the request: an unversioned response must not overwrite
      // a successful edit committed while this request was in flight.
      final detailWriteGeneration = GroupLocalStore.instance.beginMetadataWrite(
        ownerUserId: identity.ownerUserId,
        groupId: groupID,
      );
      try {
        final detail = await MeGroupApi.instance.fetchGroupDetail(
          groupID,
          refresh: true,
          persistLocally:
              false, // This route commits with detailWriteGeneration.
        );
        if (!isCurrentRequest()) return;
        if (detail != null && detail.groupId.trim().isNotEmpty) {
          // The detail contract supplies the current user's role and metadata in
          // one response. Publish it without waiting for SDK or manager pages.
          if (detail.hasSuppliedField('myRole') &&
              const [200, 300, 400].contains(detail.myRole)) {
            await GroupLocalStore.instance.upsert(
              ownerUserId: identity.ownerUserId,
              record: detail,
              writeGeneration: detailWriteGeneration,
              authoritativeGroupName: true,
            );
            if (!isCurrentRequest()) return;
            final stored = await GroupLocalStore.instance.read(
              ownerUserId: identity.ownerUserId,
              groupId: groupID,
            );
            if (!isCurrentRequest()) return;
            _groupInfo =
                stored?.toV2TimGroupInfo() ?? detail.toV2TimGroupInfo();
            notifyListeners();
            return;
          }
          final existingForCount = await GroupLocalStore.instance.read(
            ownerUserId: identity.ownerUserId,
            groupId: groupID,
          );
          if (!isCurrentRequest()) return;
          final existingAvatar = existingForCount?.avatarUrl.trim() ?? '';
          final existingCount = existingForCount?.memberCount ?? 0;
          final restCount = detail.memberCount;
          final restRecord = detail.copyWith(
            memberCount: existingCount > 0
                ? existingCount
                : (restCount > 0 ? restCount : 0),
            avatarUrl:
                existingAvatar.isNotEmpty ? existingAvatar : detail.avatarUrl,
            avatarPreviewUrl:
                existingForCount?.avatarPreviewUrl ?? detail.avatarPreviewUrl,
            avatarVersion:
                existingForCount?.avatarVersion ?? detail.avatarVersion,
          );
          final committed = await GroupLocalStore.instance.upsert(
            ownerUserId: identity.ownerUserId,
            record: restRecord,
            writeGeneration: detailWriteGeneration,
            authoritativeGroupName: true,
            // The REST group-detail response is the trusted source for this
            // identity repair path.
            allowIdentityOnlyRepair: true,
          );
          if (!isCurrentRequest()) return;
          if (!committed && detail.notice.trim().isNotEmpty) {
            // Older builds could persist a name-card-only response as a complete
            // group row. Repair only an unknown empty notice; never overwrite an
            // explicitly cleared notice (noticeUpdatedAt > 0).
            await GroupLocalStore.instance.patch(
              ownerUserId: identity.ownerUserId,
              groupId: groupID,
              transform: (current) {
                if (current.notice.trim().isNotEmpty ||
                    current.noticeUpdatedAt > 0) {
                  return current;
                }
                return current.copyWith(
                  notice: detail.notice,
                  noticeUpdatedAt: detail.noticeUpdatedAt,
                  noticeUpdatedBy: detail.noticeUpdatedBy,
                );
              },
            );
            if (!isCurrentRequest()) return;
          }
          // The Store may reject an older response or merge omitted fields.
          // Publish that committed record, never the raw transport payload.
          final stored = await GroupLocalStore.instance.read(
            ownerUserId: identity.ownerUserId,
            groupId: groupID,
          );
          if (!isCurrentRequest()) return;
          if (stored != null) {
            final effective = stored.toV2TimGroupInfo();
            try {
              final sdkResult =
                  await _groupServices.getGroupsInfo(groupIDList: [groupID]);
              if (isCurrentRequest() && sdkResult != null) {
                V2TimGroupInfo? sdkInfo;
                for (final item in sdkResult) {
                  if (item.resultCode == 0 && item.groupInfo != null) {
                    sdkInfo = item.groupInfo;
                    break;
                  }
                }
                if (sdkInfo != null) {
                  final sdkName = sdkInfo.groupName?.trim() ?? '';
                  final sdkFace = sdkInfo.faceUrl?.trim() ?? '';
                  if (sdkName.isNotEmpty && stored.groupName.trim().isEmpty) {
                    effective.groupName = sdkName;
                  }
                  if (sdkFace.isNotEmpty) {
                    effective.faceUrl = sdkFace;
                  }
                  final sdkCount = sdkInfo.memberCount ?? 0;
                  final keptCount = sdkCount > 0
                      ? sdkCount
                      : (stored.memberCount > 0 ? stored.memberCount : 0);
                  effective.memberCount = keptCount;
                  await GroupLocalStore.instance.patch(
                    ownerUserId: identity.ownerUserId,
                    groupId: groupID,
                    // A save can commit while the SDK request is in flight.
                    // Only refresh identity fields that have not changed since
                    // this request started. A zero SDK count must not wipe Store.
                    transform: (current) => current.copyWith(
                      groupName: sdkName.isNotEmpty &&
                              current.groupName.trim().isEmpty
                          ? sdkName
                          : current.groupName,
                      avatarUrl: sdkFace.isNotEmpty &&
                              current.avatarUrl == stored.avatarUrl
                          ? sdkFace
                          : current.avatarUrl,
                      memberCount:
                          sdkCount > 0 ? sdkCount : current.memberCount,
                    ),
                  );
                }
              }
            } catch (_) {
              // Keep the Store's existing SDK count (or 0). Do not write REST
              // memberCount back onto _groupInfo.
            }
            // Do not re-publish the snapshot captured before the SDK await:
            // local commits may already contain a newer notice/name/avatar.
            final latest = await GroupLocalStore.instance.read(
              ownerUserId: identity.ownerUserId,
              groupId: groupID,
            );
            if (isCurrentRequest()) {
              _groupInfo = latest?.toV2TimGroupInfo() ?? effective;
            }
          }
          await _ensureCommunityInviteApprovalEnabled();
          if (!isCurrentRequest()) return;
          notifyListeners();
          return;
        }
      } catch (_) {
        // Fall through to the SDK bridge when the backend detail is temporarily
        // unavailable; the next background full sync will retry it.
      }

      final groupInfo =
          await _groupServices.getGroupsInfo(groupIDList: [groupID]);
      if (!isCurrentRequest()) return;
      if (groupInfo != null) {
        final groupRes = groupInfo.first;
        if (groupRes.resultCode == 0) {
          _groupInfo = groupRes.groupInfo;
          final sdkCount = groupRes.groupInfo?.memberCount ?? 0;
          await GroupLocalStore.instance.patch(
            ownerUserId: identity.ownerUserId,
            groupId: groupID,
            transform: (current) => current.copyWith(
              memberCount: sdkCount > 0 ? sdkCount : current.memberCount,
            ),
          );
          final latest = await GroupLocalStore.instance.read(
            ownerUserId: identity.ownerUserId,
            groupId: groupID,
          );
          if (!isCurrentRequest()) return;
          _groupInfo = latest?.toV2TimGroupInfo() ?? groupRes.groupInfo;
          await _ensureCommunityInviteApprovalEnabled();
          if (!isCurrentRequest()) return;
        }
      }
      if (isCurrentRequest()) {
        notifyListeners();
      }
    } finally {
      if (isCurrentRequest()) {
        _groupDetailLoading = false;
        _groupDetailLoadError = backendSelfRole == null;
        notifyListeners();
      }
    }
  }

  Future<void> _ensureCommunityInviteApprovalEnabled() async {
    // 99chat: Community 加群/邀请方式由服务端 REST `join-options` 管理。
    return;
  }

  /// 资料页首屏：GET /group/{id}/members?limit=50&offset=0，不带 role、不回源腾讯。
  /// 第一页固定群主 → 管理员 → 普通成员，因此预览前排一定是管理身份。
  Future<void> loadProfileMemberPreviewPage({required String groupID}) async {
    if (_entryMemberPages) return;
    final active = _memberPageTask;
    if (active != null) return active;
    final generation = _localProjectionGeneration;
    final pageGeneration = _memberPageGeneration;
    final owner = GroupMemberLocalStore.instance.currentOwnerUserId();
    if (_disposed || groupID != _groupID) return;
    _groupMemberListLoading = true;
    late final Future<void> task;
    task = (() async {
      try {
        if (groupMemberList.isEmpty) {
          final cached = await GroupMemberLocalStore.instance
              .loadAsV2TimMembers(
                  groupId: groupID, limit: memberPreviewRestPageSize);
          if (_disposed ||
              generation != _localProjectionGeneration ||
              pageGeneration != _memberPageGeneration ||
              owner != GroupMemberLocalStore.instance.currentOwnerUserId()) {
            return;
          }
          if (cached.isNotEmpty) {
            final visible = cached
                .where((m) => !_isTombstonedMember(groupID, m.userID))
                .toList();
            _groupMemberList = visible;
            _memberWindowRevision++;
            GroupMemberStore.instance.putMembers(groupID, visible);
            notifyListeners();
          }
        }
        final page = await MeGroupApi.instance.fetchGroupMembersPage(
          groupId: groupID,
          offset: 0,
          limit: memberPreviewRestPageSize,
        );
        if (_disposed ||
            generation != _localProjectionGeneration ||
            pageGeneration != _memberPageGeneration ||
            owner != GroupMemberLocalStore.instance.currentOwnerUserId()) {
          return;
        }
        final members = page.items
            .where((member) => member.userId.trim().isNotEmpty)
            .map(_toProfileMember)
            .where((member) => !_isTombstonedMember(groupID, member.userID))
            .toList();
        if (members.isNotEmpty || groupMemberList.isEmpty) {
          _groupMemberList = members;
          _memberWindowRevision++;
        }
        _groupMemberListSeq = '0';
        _groupMemberListComplete = !_membersPageHasMore(page, 0);
        _hasCompleteMemberSnapshot = false;
        if (page.items.isNotEmpty) {
          await GroupMemberLocalStore.instance.upsertMany(
            ownerUserId: owner,
            groupId: groupID,
            records: page.items,
          );
          if (_disposed ||
              generation != _localProjectionGeneration ||
              pageGeneration != _memberPageGeneration ||
              owner != GroupMemberLocalStore.instance.currentOwnerUserId()) {
            return;
          }
          GroupMemberStore.instance.putMembers(groupID, members);
        }
      } catch (error) {
        debugPrint(
            '[GroupMemberList] preview_page_failed group=$groupID error=$error');
      } finally {
        if (!_disposed &&
            generation == _localProjectionGeneration &&
            pageGeneration == _memberPageGeneration) {
          _groupMemberListLoading = false;
          _groupMemberListLoadingMore = false;
          notifyListeners();
        }
      }
    })()
        .whenComplete(() {
      if (identical(_memberPageTask, task)) _memberPageTask = null;
    });
    _memberPageTask = task;
    return task;
  }

  /// Load exactly one page. Full snapshots require an explicit caller.
  Future<void> loadGroupMemberList(
      {required String groupID, int count = 50, String? seq}) async {
    final active = _memberPageTask;
    if (active != null) return active;
    final generation = _localProjectionGeneration;
    final pageGeneration = _memberPageGeneration;
    final owner = GroupMemberLocalStore.instance.currentOwnerUserId();
    final first = seq == null || seq.isEmpty || seq == '0';
    if (_disposed || groupID != _groupID) return;
    if (first) {
      _groupMemberListLoading = true;
    } else {
      _groupMemberListLoadingMore = true;
    }
    late final Future<void> task;
    task = (() async {
      try {
        if (first && groupMemberList.isEmpty) {
          final cached = await GroupMemberLocalStore.instance
              .loadAsV2TimMembers(groupId: groupID, limit: count);
          if (_disposed ||
              generation != _localProjectionGeneration ||
              pageGeneration != _memberPageGeneration ||
              owner != GroupMemberLocalStore.instance.currentOwnerUserId())
            return;
          if (cached.isNotEmpty) {
            final visible = cached
                .where((m) => !_isTombstonedMember(groupID, m.userID))
                .toList();
            _groupMemberList = visible;
            _memberWindowRevision++;
            GroupMemberStore.instance.putMembers(groupID, visible);
            notifyListeners();
          }
        }
        final response = await _groupServices.getGroupMemberList(
            groupID: groupID,
            filter: GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ALL,
            count: count,
            nextSeq: first ? '0' : seq);
        if (_disposed ||
            generation != _localProjectionGeneration ||
            pageGeneration != _memberPageGeneration ||
            owner != GroupMemberLocalStore.instance.currentOwnerUserId() ||
            response.code != 0 ||
            response.data == null) return;
        final page = (response.data!.memberInfoList ?? [])
            .where((m) =>
                m.userID.trim().isNotEmpty &&
                !_isTombstonedMember(groupID, m.userID))
            .toList();
        if (response.desc != 'cached_page') _successfulMemberPageRevision++;
        final preserveExisting = first && groupMemberList.isNotEmpty;
        final byId = <String, V2TimGroupMemberFullInfo>{
          if (!first || preserveExisting)
            for (final m
                in groupMemberList.whereType<V2TimGroupMemberFullInfo>())
              if (m.userID.trim().isNotEmpty &&
                  !_isTombstonedMember(groupID, m.userID))
                m.userID: m,
          for (final m in page)
            if (m.userID.trim().isNotEmpty) m.userID: m,
        };
        // Appending preserves server order and existing row positions.
        _groupMemberList = byId.values.toList();
        _memberWindowRevision++;
        _groupMemberListSeq = response.data!.nextSeq ?? '0';
        if (!first && _groupMemberListSeq == seq) {
          // A replayed cursor must not keep requesting the same page on scroll.
          _groupMemberListSeq = '0';
        }
        _groupMemberListComplete =
            !hasMoreGroupMembers && response.desc != 'cached_page';
        _hasCompleteMemberSnapshot = false;
        GroupMemberStore.instance.putMembers(groupID, page);
      } catch (error) {
        debugPrint('[GroupMemberList] page_failed group=$groupID error=$error');
      } finally {
        if (!_disposed &&
            generation == _localProjectionGeneration &&
            pageGeneration == _memberPageGeneration) {
          _groupMemberListLoading = false;
          _groupMemberListLoadingMore = false;
          notifyListeners();
        }
      }
    })()
        .whenComplete(() {
      if (identical(_memberPageTask, task)) _memberPageTask = null;
    });
    _memberPageTask = task;
    return task;
  }

  /// Each member-management route requests its own fresh first page. Ordinary
  /// pages use the same business membership source as kick/invite mutations.
  /// Only an overlapping entry shares work; a later entry always revalidates.
  Future<void> loadMemberPageOnEntry() {
    final active = _memberEntryTask;
    if (active != null && isMemberEntryLoading) return active;
    final generation = _localProjectionGeneration;
    final identity = SessionIdentityService.instance.capture();
    // Supersede older member reads without waiting for their network latency.
    // Their generation guards prevent late responses/finalizers from winning.
    final pageGeneration = ++_memberPageGeneration;
    _memberPageTask = null;
    _entryPageTask = null;
    _entryMemberPages = true;
    _groupMemberListLoading = true;
    _groupMemberListLoadingMore = false;
    late final Future<void> task;
    task = (() async {
      await Future<void>.value();
      if (_disposed ||
          generation != _localProjectionGeneration ||
          pageGeneration != _memberPageGeneration ||
          !SessionIdentityService.instance.isCurrent(identity)) return;
      _groupMemberList = [];
      _localManagementPreview.clear();
      final management = _managementRequest;
      final reuseManagement =
          _profileManagementGeneration == generation &&
          management != null &&
          management.generation == generation &&
          SessionIdentityService.instance.isCurrent(management.identity) &&
          !_managementLoadError &&
          (_managementLoading || hasLoadedManagementMembers);
      if (!reuseManagement) {
        _managementMembers = null;
        _managementIdentity = null;
        _previewOrdinaryMembers = <V2TimGroupMemberFullInfo>[];
        _previewMembersReady = false;
      }
      _entryMemberOffset = 0;
      _entryMemberHasMore = false;
      _entryMemberError = false;
      _groupMemberListSeq = '0';
      _memberWindowRevision++;
      notifyListeners();
      await Future.wait<void>([
        _loadEntryMemberPage(first: true),
        reuseManagement ? management.task : loadManagementMembers(),
      ]);
    })()
        .whenComplete(() {
      if (identical(_memberEntryTask, task)) {
        _memberEntryTask = null;
        if (!_disposed) notifyListeners();
      }
    });
    _memberEntryTask = task;
    return task;
  }

  Future<void> _loadEntryMemberPage({required bool first}) {
    final active = _entryPageTask;
    if (active != null) return active;
    final group = _groupID;
    final generation = _localProjectionGeneration;
    final pageGeneration = _memberPageGeneration;
    final identity = SessionIdentityService.instance.capture();
    final offset = first ? 0 : _entryMemberOffset;
    bool isCurrent() =>
        !_disposed &&
        generation == _localProjectionGeneration &&
        pageGeneration == _memberPageGeneration &&
        group == _groupID &&
        SessionIdentityService.instance.isCurrent(identity);
    if (!isCurrent()) return Future<void>.value();
    _entryMemberError = false;
    _groupMemberListLoading = first;
    _groupMemberListLoadingMore = !first;
    late final Future<void> task;
    task = (() async {
      try {
        final page = await MeGroupApi.instance.fetchGroupMembersPage(
          groupId: group,
          limit: 50,
          offset: offset,
          role: GroupMembersRoleQuery.members,
        );
        if (!isCurrent()) return;
        final byId = <String, V2TimGroupMemberFullInfo>{
          if (!first)
            for (final member
                in groupMemberList.whereType<V2TimGroupMemberFullInfo>())
              if (!_isTombstonedMember(group, member.userID))
                member.userID: member,
          for (final record in page.items)
            if (record.userId.isNotEmpty &&
                !_isTombstonedMember(group, record.userId))
              record.userId: _toProfileMember(record),
        };
        // A successful first page replaces the previous window, including an
        // empty response. Never union yesterday's cached membership into it.
        _groupMemberList = byId.values.toList();
        _entryMemberOffset = offset + page.items.length;
        _entryMemberHasMore =
            page.items.isNotEmpty && _membersPageHasMore(page, offset);
        _groupMemberListComplete = !_entryMemberHasMore;
        _hasCompleteMemberSnapshot = false;
        _memberWindowRevision++;
        GroupMemberStore.instance.putMembers(group, _groupMemberList!);
      } catch (error) {
        if (isCurrent()) _entryMemberError = true;
        debugPrint(
            '[GroupMemberList] entry_page_failed group=$group error=$error');
      } finally {
        if (isCurrent()) {
          _groupMemberListLoading = false;
          _groupMemberListLoadingMore = false;
          notifyListeners();
        }
      }
    })()
        .whenComplete(() {
      if (identical(_entryPageTask, task)) _entryPageTask = null;
    });
    _entryPageTask = task;
    return task;
  }

  /// Expands a preview to one list page; never drains all remaining pages.
  Future<void> ensureMemberListPage({int count = 50}) async {
    final generation = _localProjectionGeneration;
    await _memberPageTask;
    if (_disposed || generation != _localProjectionGeneration) return;
    if (groupMemberList.isEmpty ||
        (!_groupMemberListComplete && !hasMoreGroupMembers)) {
      await loadGroupMemberList(groupID: _groupID, count: count);
    } else if (groupMemberList.length < count && hasMoreGroupMembers) {
      await loadMoreGroupMembers(count: count - groupMemberList.length);
    }
  }

  Future<bool> loadMoreGroupMembers({int count = 50}) async {
    if (_entryMemberPages) {
      if (isMemberEntryLoading ||
          _entryPageTask != null ||
          !_entryMemberHasMore) return false;
      await _loadEntryMemberPage(first: false);
      return _entryMemberHasMore;
    }
    if (_disposed || _memberPageTask != null || !hasMoreGroupMembers) {
      return false;
    }
    final seq = _groupMemberListSeq.trim();
    if (seq.isNotEmpty && seq != '0') {
      await loadGroupMemberList(
          groupID: _groupID, count: count, seq: _groupMemberListSeq);
      return hasMoreGroupMembers;
    }
    if (_listedMemberCount < _expectedMemberCount) {
      await _appendRestOrdinaryMembers(
        expected: _expectedMemberCount,
        generation: _localProjectionGeneration,
        maxPages: 1,
      );
      return hasMoreGroupMembers;
    }
    return false;
  }

  /// Reuse a recently loaded member page without resetting its scroll cursor.
  Future<void> loadRemainingMemberPages({int? expectedCount}) async {
    if (_disposed || _groupID.trim().isEmpty) return;
    final identity = SessionIdentityService.instance.capture();
    final generation = _localProjectionGeneration;
    final confirmed = _memberListConfirmed;
    final membershipRevision = _memberMembershipRevision;
    final sameContext = confirmed != null &&
        confirmed.generation == generation &&
        SessionIdentityService.instance.isCurrent(confirmed.identity);
    if (sameContext &&
        confirmed.membershipRevision == membershipRevision &&
        DateTime.now().difference(confirmed.at) < const Duration(minutes: 5) &&
        hasLoadedManagementMembers &&
        !_managementLoadError) return;
    final active = _remainingMemberLoadInFlight;
    if (active != null) return active;
    late final Future<void> task;
    task = (() async {
      // A preview request may still be running when the member route opens.
      await _memberPageTask;
      if (_disposed ||
          generation != _localProjectionGeneration ||
          !SessionIdentityService.instance.isCurrent(identity)) return;
      if (!sameContext) await seedLocalMemberAndManagementPreview();
      if (_disposed ||
          generation != _localProjectionGeneration ||
          !SessionIdentityService.instance.isCurrent(identity)) return;
      final before = _successfulMemberPageRevision;
      await Future.wait([
        loadManagementMembers(),
        _refreshMemberWindowFromNetwork(),
      ]);
      if (!_disposed &&
          generation == _localProjectionGeneration &&
          membershipRevision == _memberMembershipRevision &&
          SessionIdentityService.instance.isCurrent(identity) &&
          _successfulMemberPageRevision > before &&
          hasLoadedManagementMembers &&
          !_managementLoadError) {
        _memberListConfirmed = (
          identity: identity,
          generation: generation,
          membershipRevision: membershipRevision,
          at: DateTime.now()
        );
      }
    })()
        .whenComplete(() {
      if (identical(_remainingMemberLoadInFlight, task)) {
        _remainingMemberLoadInFlight = null;
      }
    });
    _remainingMemberLoadInFlight = task;
    return task;
  }

  Future<void> seedLocalMemberAndManagementPreview() async {
    if (_disposed || _groupID.trim().isEmpty) return;
    final generation = _localProjectionGeneration;
    final group = _groupID;
    final preview = <String, V2TimGroupMemberFullInfo>{};
    for (final role in <int>[
      GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER,
      GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_ADMIN,
    ]) {
      var offset = 0;
      for (var pageIndex = 0; pageIndex < 10; pageIndex++) {
        final rows = await GroupMemberLocalStore.instance.readWindow(
          groupId: group,
          role: role,
          limit: 50,
          offset: offset,
        );
        if (_disposed || generation != _localProjectionGeneration) return;
        if (rows.isEmpty) break;
        for (final row in rows) {
          if (row.userId.trim().isEmpty) continue;
          preview[row.userId] = _toProfileMember(row);
        }
        if (rows.length < 50) break;
        offset += rows.length;
      }
    }
    final probe = await GroupMemberLocalStore.instance.loadAsV2TimMembers(
      groupId: group,
      limit: localMemberWindowSize + 1,
    );
    if (_disposed || generation != _localProjectionGeneration) return;
    final window = probe.take(localMemberWindowSize).toList();
    if (window.isNotEmpty) {
      _groupMemberList = window;
      _memberWindowRevision++;
      _groupMemberListSeq = probe.length > localMemberWindowSize
          ? 'local:$localMemberWindowSize'
          : '0';
      _groupMemberListComplete = probe.length <= localMemberWindowSize;
      GroupMemberStore.instance.putMembers(group, window);
    }
    _localManagementPreview = preview;
    notifyListeners();
  }

  Future<void> _refreshMemberWindowFromNetwork() async {
    final generation = _localProjectionGeneration;
    await loadGroupMemberList(groupID: _groupID, count: 50);
    if (_disposed || generation != _localProjectionGeneration) return;
  }

  /// Collect every owner and admin. Prefer role-filtered REST pages; if the
  /// server ignores `role`, walk mixed pages instead of stopping at offset 0.
  Future<void> loadManagementMembers() async {
    final identity = SessionIdentityService.instance.capture();
    final generation = _localProjectionGeneration;
    final request = ++_managementLoadGeneration;
    final group = _groupID;
    bool isCurrent() =>
        !_disposed &&
        request == _managementLoadGeneration &&
        generation == _localProjectionGeneration &&
        SessionIdentityService.instance.isCurrent(identity);
    if (!isCurrent()) return;
    final completion = Completer<void>();
    _managementRequest = (
      identity: identity,
      generation: generation,
      task: completion.future,
    );
    _managementLoading = true;
    _managementLoadError = false;
    if (_profilePreviewManagers().length < memberPreviewSize) {
      _previewMembersReady = false;
    }
    notifyListeners();
    try {
      final roles = <String, V2TimGroupMemberFullInfo>{};
      final first = await MeGroupApi.instance.fetchGroupMembersPage(
        groupId: group,
        offset: 0,
        limit: 50,
        role: GroupMembersRoleQuery.admins,
      );
      if (!isCurrent()) return;
      await _collectRoleMemberPages(
        groupId: group,
        role: GroupMembersRoleQuery.admins,
        into: roles,
        isCurrent: isCurrent,
        firstPage: first,
      );
      if (!isCurrent()) return;
      final sorted = roles.values.toList()
        ..sort((a, b) {
          final roleOrder = (b.role ?? 0).compareTo(a.role ?? 0);
          return roleOrder != 0 ? roleOrder : a.userID.compareTo(b.userID);
        });
      _managementMembers = {for (final member in sorted) member.userID: member};
      _managementIdentity = identity;
      final key = GroupLocalStore.groupEquivalenceKey(group);
      _recentProfiles.remove(key);
      _recentProfiles[key] = (
        identity: identity,
        confirmedAt: DateTime.now(),
        members: _managementMembers!.map((id, member) =>
            MapEntry(id, V2TimGroupMemberFullInfo.fromJson(member.toJson()))),
      );
      while (_recentProfiles.length > 32) {
        _recentProfiles.remove(_recentProfiles.keys.first);
      }
      GroupMembersPage? padPage;
      if (!_entryMemberPages &&
          _profilePreviewManagers().length < memberPreviewSize) {
        try {
          padPage = await MeGroupApi.instance.fetchGroupMembersPage(
            groupId: group,
            offset: 0,
            limit: memberPreviewRestPageSize,
            role: GroupMembersRoleQuery.members,
          );
        } catch (error) {
          debugPrint(
              '[GroupProfile] preview_pad_failed group=$_groupID error=$error');
        }
        if (!isCurrent()) return;
      }
      _applyPreviewOrdinaryPad(padPage);
      _previewMembersReady = true;
    } catch (error) {
      if (isCurrent()) {
        _managementLoadError = true;
        _previewMembersReady = true;
        debugPrint('[GroupManagement] load_failed error=$error');
      }
    } finally {
      completion.complete();
      if (isCurrent()) {
        _managementLoading = false;
        notifyListeners();
      }
    }
  }

  V2TimGroupMemberFullInfo _toProfileMember(GroupMemberRecord member) {
    return V2TimGroupMemberFullInfo(
      userID: member.userId,
      role: member.role,
      nickName: member.nickname,
      nameCard: member.nameCard,
      faceUrl: member.avatarUrl,
      friendRemark: member.friendRemark,
      joinTime: member.joinedAt > 0 ? member.joinedAt ~/ 1000 : null,
      muteUntil: member.muteUntil > 0 ? member.muteUntil : null,
    );
  }

  bool _isManagementRole(int role) {
    return role == GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER ||
        role == GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_ADMIN;
  }

  bool _membersPageHasMore(GroupMembersPage page, int offset) {
    final next = offset + page.items.length;
    return page.hasMore ??
        (page.items.isNotEmpty &&
            page.items.length >= 50 &&
            (page.total <= 0 || next < page.total));
  }

  void _ingestManagementMembers(
    GroupMembersPage page,
    Map<String, V2TimGroupMemberFullInfo> into,
  ) {
    for (final member in page.items) {
      if (member.userId.trim().isEmpty || !_isManagementRole(member.role)) {
        continue;
      }
      into[member.userId] = _toProfileMember(member);
    }
  }

  void _applyPreviewOrdinaryPad(GroupMembersPage? page) {
    if (_entryMemberPages ||
        _profilePreviewManagers().length >= memberPreviewSize ||
        page == null) {
      _previewOrdinaryMembers = <V2TimGroupMemberFullInfo>[];
      return;
    }
    final pad = <V2TimGroupMemberFullInfo>[];
    final seen = <String>{};
    for (final record in page.items) {
      final id = record.userId.trim();
      final normalized = _normalizeMemberUserId(id);
      if (id.isEmpty ||
          normalized.isEmpty ||
          !seen.add(normalized) ||
          _isTombstonedMember(_groupID, id) ||
          _isManagementRole(record.role)) {
        continue;
      }
      pad.add(_toProfileMember(record));
    }
    _previewOrdinaryMembers = pad;
  }

  Future<void> _collectRoleMemberPages({
    required String groupId,
    required String role,
    required Map<String, V2TimGroupMemberFullInfo> into,
    required bool Function() isCurrent,
    GroupMembersPage? firstPage,
  }) async {
    var offset = 0;
    var page = firstPage;
    for (var index = 0; index < 20; index++) {
      if (!isCurrent()) return;
      page ??= await MeGroupApi.instance.fetchGroupMembersPage(
        groupId: groupId,
        offset: offset,
        limit: 50,
        role: role,
      );
      if (!isCurrent()) return;
      _ingestManagementMembers(page, into);
      if (!_membersPageHasMore(page, offset)) return;
      offset += page.items.length;
      page = null;
    }
  }

  Future<void> _appendRestOrdinaryMembers({
    required int expected,
    required int generation,
    int maxPages = 40,
  }) async {
    final owner = GroupMemberLocalStore.instance.currentOwnerUserId();
    var offset = groupMemberList.length;
    final byId = <String, V2TimGroupMemberFullInfo>{
      for (final member
          in groupMemberList.whereType<V2TimGroupMemberFullInfo>())
        if (member.userID.trim().isNotEmpty) member.userID: member,
    };
    for (var pageIndex = 0; pageIndex < maxPages.clamp(1, 40); pageIndex++) {
      if (_disposed || generation != _localProjectionGeneration) return;
      final page = await MeGroupApi.instance.fetchGroupMembersPage(
        groupId: _groupID,
        offset: offset,
        limit: 50,
      );
      if (_disposed ||
          generation != _localProjectionGeneration ||
          owner != GroupMemberLocalStore.instance.currentOwnerUserId()) {
        return;
      }
      if (page.items.isEmpty) {
        _groupMemberListSeq = '0';
        _groupMemberListComplete = true;
        notifyListeners();
        return;
      }
      for (final member in page.items) {
        final id = member.userId.trim();
        if (id.isEmpty || byId.containsKey(id)) continue;
        byId[id] = _toProfileMember(member);
      }
      _groupMemberList = byId.values.toList();
      _memberWindowRevision++;
      notifyListeners();
      if (!_membersPageHasMore(page, offset) ||
          (expected > 0 && byId.length >= expected)) {
        _groupMemberListSeq = '0';
        _groupMemberListComplete = true;
        notifyListeners();
        return;
      }
      offset += page.items.length;
    }
  }

  /// Explicit export/full-selection or snapshot repair only. Page entry does
  /// not call this method, and partial page reads never mark the disk complete.
  /// Disk may hold the full snapshot; page memory stays a bounded window.
  Future<void> loadAllGroupMembers(
      {int count = 100, int? expectedCount}) async {
    final active = _groupMemberFullSyncInFlight;
    if (active != null) return active;
    final group = _groupID;
    final owner = GroupMemberLocalStore.instance.currentOwnerUserId();
    final generation = _localProjectionGeneration;
    final windowLimit = count.clamp(1, 100);
    late final Future<void> task;
    task = (() async {
      final complete = await GroupMemberLocalStore.instance
          .hasCompleteSnapshot(ownerUserId: owner, groupId: group);
      if (!complete) return;
      final members = await GroupMemberLocalStore.instance.loadAsV2TimMembers(
        ownerUserId: owner,
        groupId: group,
        limit: windowLimit,
      );
      if (_disposed ||
          generation != _localProjectionGeneration ||
          owner != GroupMemberLocalStore.instance.currentOwnerUserId()) return;
      _groupMemberList = members;
      _memberWindowRevision++;
      _groupMemberListSeq =
          members.length >= windowLimit ? 'local:$windowLimit' : '0';
      _groupMemberListComplete = members.length < windowLimit;
      _hasCompleteMemberSnapshot = true;
      GroupMemberStore.instance.putMembers(group, members);
      notifyListeners();
    })()
        .whenComplete(() {
      if (identical(_groupMemberFullSyncInFlight, task))
        _groupMemberFullSyncInFlight = null;
    });
    _groupMemberFullSyncInFlight = task;
    return task;
  }

  Future<void> reloadGroupMembers(String groupID) =>
      loadProfileMemberPreviewPage(groupID: groupID);

  Future<void> processGroupMemberListEnter(
      {required String groupID,
      required List<V2TimGroupMemberInfo> memberList}) async {
    if (_disposed ||
        memberList.isEmpty ||
        GroupLocalStore.groupEquivalenceKey(groupID) !=
            GroupLocalStore.groupEquivalenceKey(_groupID)) return;
    // Keep the loaded window, but refresh on the next member-page entry.
    // A request started before this event cannot confirm the new membership.
    _memberMembershipRevision++;
    final List<V2TimGroupMemberFullInfo> fullInfoList =
        memberList.where((member) => member.userID != null).map((member) {
      return V2TimGroupMemberFullInfo(
        userID: member.userID!,
        nickName: member.nickName,
        nameCard: member.nameCard,
        friendRemark: member.friendRemark,
        faceUrl: member.faceUrl,
        onlineDevices: member.onlineDevices,
      );
    }).toList();

    for (final fullInfo in fullInfoList) {
      final exists =
          _groupMemberList?.any((e) => e?.userID == fullInfo.userID) ?? false;
      if (!exists && _hasCompleteMemberSnapshot) {
        _groupMemberList = [...?_groupMemberList, fullInfo];
      }
    }
    GroupMemberStore.instance.clearRemovalTombstones(
      groupID,
      fullInfoList.map((member) => member.userID),
    );
    GroupMemberStore.instance.putMembers(groupID, fullInfoList);
  }

  Future<void> processGroupMemberListLeave(
      {required String groupID,
      required List<V2TimGroupMemberInfo> memberList}) async {
    if (_disposed ||
        memberList.isEmpty ||
        GroupLocalStore.groupEquivalenceKey(groupID) !=
            GroupLocalStore.groupEquivalenceKey(_groupID)) return;
    _memberMembershipRevision++;
    final userIDsToRemove = memberList
        .map((member) => _normalizeMemberUserId(member.userID))
        .where((id) => id.isNotEmpty)
        .toSet();

    _stripRemovedMembersFromProfile(userIDsToRemove);
    GroupMemberStore.instance
        .removeMembers(groupID, userIDsToRemove, notify: false);
    notifyListeners();
  }

  String _normalizeMemberUserId(String? userId) {
    return ChatIdFormat.rawUserUid(userId);
  }

  bool _isTombstonedMember(String groupID, String? userID) {
    return GroupMemberStore.instance.isRemovalTombstoned(
      groupID,
      _normalizeMemberUserId(userID),
    );
  }

  void _stripRemovedMembersFromProfile(Set<String> userIDsToRemove) {
    if (userIDsToRemove.isEmpty) {
      return;
    }
    _groupMemberList?.removeWhere((member) {
      final id = _normalizeMemberUserId(member?.userID);
      return id.isNotEmpty && userIDsToRemove.contains(id);
    });
    _managementMembers?.removeWhere(
      (id, _) => userIDsToRemove.contains(_normalizeMemberUserId(id)),
    );
    _localManagementPreview.removeWhere(
      (id, _) => userIDsToRemove.contains(_normalizeMemberUserId(id)),
    );
    _previewOrdinaryMembers.removeWhere(
      (member) =>
          userIDsToRemove.contains(_normalizeMemberUserId(member.userID)),
    );
    final recent =
        _recentProfiles[GroupLocalStore.groupEquivalenceKey(_groupID)];
    recent?.members.removeWhere(
      (id, _) => userIDsToRemove.contains(_normalizeMemberUserId(id)),
    );
  }

  _loadConversation() async {
    final generation = _localProjectionGeneration;
    final raw = _groupID.trim();
    if (raw.isEmpty) {
      return;
    }
    final candidates = <String>{
      'group_$raw',
      if (raw.startsWith('group_')) raw,
    };
    for (final conversationID in candidates) {
      final loaded = await _conversationService.getConversation(
        conversationID: conversationID,
      );
      if (_disposed || generation != _localProjectionGeneration) return;
      if (loaded != null) {
        conversation = loaded;
        notifyListeners();
        return;
      }
    }
  }

  Future<void> loadContactsForPicker() async {
    try {
      final res = await _friendshipServices.getFriendList();
      _contactList = filterFriendListForPickers(res ?? []);
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  pinedConversation(bool isPined) async {
    await _conversationService.pinConversation(
        conversationID: "group_$_groupID", isPinned: isPined);
    conversation?.isPinned = isPined;
    notifyListeners();
  }

  Future<V2TimCallback> setMessageDisturb(bool value) async {
    final groupId = _groupID.trim();
    final res = await _messageService.setGroupReceiveMessageOpt(
        groupID: groupId,
        opt: value
            ? ReceiveMsgOptEnum.V2TIM_RECEIVE_NOT_NOTIFY_MESSAGE
            : ReceiveMsgOptEnum.V2TIM_RECEIVE_MESSAGE);
    if (res.code == 0) {
      final optIndex = (value
              ? ReceiveMsgOptEnum.V2TIM_RECEIVE_NOT_NOTIFY_MESSAGE
              : ReceiveMsgOptEnum.V2TIM_RECEIVE_MESSAGE)
          .index;
      if (conversation != null) {
        conversation!.recvOpt = optIndex;
      }
    }
    notifyListeners();
    return res;
  }

  Future<V2TimValueCallback<V2GroupMemberInfoSearchResult>> searchGroupMember(
      V2TimGroupMemberSearchParam searchParam) async {
    final res =
        await _groupServices.searchGroupMembers(searchParam: searchParam);

    if (res.code == 0) {}
    return res;
  }

  Future<V2TimCallback?> setGroupName(String groupName) async {
    if (_groupInfo != null) {
      String? originalGroupName = _groupInfo?.groupName;
      _groupInfo?.groupName = groupName;
      V2TimGroupInfo v2timGroupInfo =
          V2TimGroupInfo(groupID: _groupID, groupType: _groupInfo!.groupType);
      v2timGroupInfo.groupName = groupName;
      final response = await _groupServices.setGroupInfo(info: v2timGroupInfo);
      if (response.code == 0) {
        final name = groupName.trim();
        DisplayNameStore.instance.setGroup(_groupID, name);
        serviceLocator<TUIConversationViewModel>()
            .updateGroupShowName(_groupID, name);
        serviceLocator<TUIFriendShipViewModel>()
            .updateGroupNameLocal(_groupID, name);
      } else {
        _groupInfo?.groupName = originalGroupName;
      }
      notifyListeners();
      return response;
    }
    return null;
  }

  Future<V2TimCallback?> setGroupNotification(String notification) async {
    if (_groupInfo != null) {
      final originalNotification = _groupInfo?.notification;
      final originalCustomInfo = _groupInfo?.customInfo == null
          ? null
          : Map<String, String>.from(_groupInfo!.customInfo!);
      final originalLastInfoTime = _groupInfo?.lastInfoTime;
      V2TimGroupInfo v2timGroupInfo =
          V2TimGroupInfo(groupID: _groupID, groupType: _groupInfo!.groupType);
      v2timGroupInfo.notification = notification;
      final response = await _groupServices.setGroupInfo(info: v2timGroupInfo);
      if (response.code == 0) {
        _groupInfo?.notification = notification;
        final selfId = _coreServices.loginUserInfo?.userID?.trim() ?? '';
        if (selfId.isNotEmpty) {
          final custom = Map<String, String>.from(_groupInfo?.customInfo ?? {});
          custom['noticeUpdatedBy'] = selfId;
          _groupInfo?.customInfo = custom;
        }
        _groupInfo?.lastInfoTime =
            DateTime.now().millisecondsSinceEpoch ~/ 1000;
        notifyListeners();
      } else {
        _groupInfo?.notification = originalNotification;
        _groupInfo?.customInfo = originalCustomInfo;
        _groupInfo?.lastInfoTime = originalLastInfoTime;
      }
      return response;
    }
    return null;
  }

  String getSelfNameCard() {
    final detail = _confirmedSelfDetail;
    if (detail != null && detail.hasSuppliedField('myNameCard')) {
      return GroupLocalStore.instance
              .readCached(groupId: _groupID)
              ?.myNameCard ??
          detail.myNameCard;
    }
    final self = _coreServices.loginUserInfo?.userID ?? '';
    return GroupMemberStore.instance.memberOf(_groupID, self)?.nameCard ?? '';
  }

  @override
  void dispose() {
    _disposed = true;
    // Route callbacks may capture the previous chat page while SDK work settles.
    onClickUser = null;
    _lifeCycle = null;
    _groupInfoLoadGeneration++;
    _localProjectionGeneration++;
    _localProjectionDirty = false;
    GroupMemberLocalStore.instance.commitListenable
        .removeListener(_onLocalMemberCommit);
    GroupLocalStore.instance.commitListenable
        .removeListener(_onLocalGroupCommit);
    super.dispose();
  }

  Future<V2TimCallback?> setNameCard(String nameCard) async {
    final loginUserID = _coreServices.loginUserInfo?.userID;
    if (loginUserID == null || loginUserID.isEmpty) {
      return null;
    }

    final res = await _groupServices.setGroupMemberInfo(
        groupID: _groupID, userID: loginUserID, nameCard: nameCard);
    if (res.code != 0) {
      return res;
    }

    V2TimGroupMemberFullInfo? latest;
    final infoRes = await _groupServices.getGroupMembersInfo(
      groupID: _groupID,
      memberList: [loginUserID],
    );
    if (infoRes.code == 0 && infoRes.data != null && infoRes.data!.isNotEmpty) {
      latest = infoRes.data!.first;
    }

    GroupMemberStore.instance.putNameCard(
      groupID: _groupID,
      userID: loginUserID,
      nameCard: nameCard,
      member: latest,
      notify: false,
    );

    final targetIndex = _groupMemberList
        ?.indexWhere((element) => element?.userID == loginUserID);
    if (latest != null) {
      if (targetIndex != null && targetIndex >= 0) {
        _groupMemberList![targetIndex] = latest;
      } else {
        _groupMemberList = [...?_groupMemberList, latest];
      }
      GroupMemberStore.instance.putMember(_groupID, latest);
    } else {
      if (targetIndex != null && targetIndex >= 0) {
        _groupMemberList![targetIndex]?.nameCard = nameCard;
        GroupMemberStore.instance.putNameCard(
          groupID: _groupID,
          userID: loginUserID,
          nameCard: nameCard,
          member: _groupMemberList![targetIndex],
        );
      } else {
        GroupMemberStore.instance.putNameCard(
          groupID: _groupID,
          userID: loginUserID,
          nameCard: nameCard,
        );
      }
    }
    notifyListeners();
    return res;
  }

  Future<V2TimCallback?> setGroupAddOpt(int addOpt) async {
    if (_groupInfo != null) {
      int? originalAddopt = _groupInfo?.groupAddOpt;
      _groupInfo?.groupAddOpt = addOpt;
      V2TimGroupInfo v2timGroupInfo =
          V2TimGroupInfo(groupID: _groupID, groupType: _groupInfo!.groupType);
      v2timGroupInfo.groupAddOpt = addOpt;
      final response = await _groupServices.setGroupInfo(info: v2timGroupInfo);
      if (response.code != 0) {
        _groupInfo?.groupAddOpt = originalAddopt;
      }
      notifyListeners();
      return response;
    }
    return null;
  }

  Future<V2TimCallback> setMemberToNormal(String userID) async {
    final res = await _groupServices.setGroupMemberRole(
        groupID: _groupID,
        userID: userID,
        role: GroupMemberRoleTypeEnum.V2TIM_GROUP_MEMBER_ROLE_MEMBER);
    if (res.code == 0) {
      final targetIndex = _memberIndexByUserId(userID);
      if (targetIndex != -1) {
        final targetElem = _groupMemberList![targetIndex];
        targetElem?.role = GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER;
        _groupMemberList![targetIndex] = targetElem;
      }
      notifyListeners();
      await loadManagementMembers();
    }
    return res;
  }

  Future<V2TimCallback> setMemberToAdmin(String userID) async {
    return setMembersToAdmin(<String>[userID]);
  }

  Future<V2TimCallback> setMembersToAdmin(List<String> userIDs) async {
    final normalized = userIDs
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) {
      return V2TimCallback(code: -1, desc: 'INVALID_INPUT');
    }
    final res = await _groupServices.setGroupMemberRoles(
      groupID: _groupID,
      userIDList: normalized,
      role: GroupMemberRoleTypeEnum.V2TIM_GROUP_MEMBER_ROLE_ADMIN,
    );
    if (res.code == 0) {
      for (final userID in normalized) {
        final targetIndex = _memberIndexByUserId(userID);
        if (targetIndex != -1) {
          final targetElem = _groupMemberList![targetIndex];
          targetElem?.role = GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_ADMIN;
          _groupMemberList![targetIndex] = targetElem;
        }
      }
      notifyListeners();
      await loadManagementMembers();
    }
    return res;
  }

  int _memberIndexByUserId(String userID) {
    final target = userID.trim();
    if (target.isEmpty || _groupMemberList == null) {
      return -1;
    }
    return _groupMemberList!.indexWhere((member) {
      final id = member?.userID?.trim() ?? '';
      return id.isNotEmpty && id == target;
    });
  }

  void onOwnerChanged(String? userID) {
    if (userID == null) {
      return;
    }

    // 把之前的群主更新为普通成员
    final preOwnerIndex = _groupMemberList!.indexWhere(
        (e) => e!.role == GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER);
    if (preOwnerIndex != -1) {
      final preOwnerElem = _groupMemberList![preOwnerIndex];
      preOwnerElem?.role = GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER;

      if (kDebugMode) {
        print("preOwnerUserID: ${preOwnerElem?.userID}");
      }
    }

    // 设置新的群主
    final targetIndex =
        _groupMemberList!.indexWhere((e) => e!.userID == userID);
    if (targetIndex != -1) {
      final targetElem = _groupMemberList![targetIndex];
      targetElem?.role = GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER;
      _groupMemberList![targetIndex] = targetElem;

      if (kDebugMode) {
        print("newOwnerUserID: ${targetElem?.userID}");
      }
    }

    notifyListeners();
  }

  bool canInviteMember() {
    final groupType = _groupInfo?.groupType;
    if (groupType == GroupType.Work ||
        groupType == "Private" ||
        groupType == GroupType.Public ||
        groupType == GroupType.Meeting ||
        groupType == GroupType.Community) {
      return true;
    }
    return false;
  }

  bool canKickOffMember() {
    return GroupRolePolicy.canKickMemberEntry(
      selfRole: backendSelfRole,
      groupType: _groupInfo?.groupType,
    );
  }

  Future<V2TimCallback?> setMuteAll(bool muteAll) async {
    if (_groupInfo != null) {
      final originalMuted = _groupInfo?.isAllMuted ?? false;
      _groupInfo?.isAllMuted = muteAll;
      V2TimGroupInfo v2timGroupInfo =
          V2TimGroupInfo(groupID: _groupID, groupType: _groupInfo!.groupType);
      v2timGroupInfo.isAllMuted = muteAll;
      final response = await _groupServices.setGroupInfo(info: v2timGroupInfo);
      if (response.code != 0) {
        _groupInfo?.isAllMuted = originalMuted;
      } else {
        await loadGroupInfo(_groupID);
        await reloadGroupMembers(_groupID);
      }
      notifyListeners();
      return response;
    }
    return null;
  }

  Future<V2TimCallback> muteGroupMember(
      String userID, bool isMute, int? serverTime) async {
    if (_disposed || !canMuteMember(userID)) {
      return V2TimCallback(code: -1, desc: 'NOT_GROUP_OWNER_OR_ADMIN');
    }
    final groupID = _groupID;
    final identity = SessionIdentityService.instance.capture();
    const muteTime = 315360000;
    V2TimCallback res;
    try {
      res = await _groupServices.muteGroupMember(
          groupID: groupID, userID: userID, seconds: isMute ? muteTime : 0);
    } catch (_) {
      return V2TimCallback(code: -1, desc: 'MUTE_REQUEST_FAILED');
    }
    if (_disposed ||
        _groupID != groupID ||
        !SessionIdentityService.instance.isCurrent(identity)) {
      return V2TimCallback(code: -1, desc: 'GROUP_CONTEXT_CHANGED');
    }
    if (res.code == 0) {
      final targetIndex = _memberIndexByUserId(userID);
      if (targetIndex != -1) {
        final targetElem = _groupMemberList![targetIndex];
        final now = serverTime ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (targetElem != null) {
          targetElem.muteUntil = isMute ? now + muteTime : 0;
          _groupMemberList![targetIndex] = targetElem;
          GroupMemberStore.instance.putMember(_groupID, targetElem);
        }
      }
      notifyListeners();
    }
    return res;
  }

  Future<V2TimCallback> kickOffMember(List<String> userIDs) async {
    final normalized = userIDs
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) {
      return V2TimCallback(code: -1, desc: 'INVALID_INPUT');
    }
    if (!normalized.every(canKickMember)) {
      return V2TimCallback(code: -1, desc: 'NOT_GROUP_OWNER_OR_ADMIN');
    }
    final res = await _groupServices.kickGroupMember(
      groupID: _groupID,
      memberList: normalized,
    );
    if (res.code == 0) {
      final partial = res.desc?.trim().toUpperCase() == 'PARTIAL_SUCCESS';
      if (!partial) {
        await processGroupMemberListLeave(
          groupID: _groupID,
          memberList:
              normalized.map((id) => V2TimGroupMemberInfo(userID: id)).toList(),
        );
      }
      await loadGroupInfo(_groupID);
      notifyListeners();
    }
    return res;
  }

  Future<Set<String>> existingMemberUserIdsAmong(
      List<String> candidateUserIds) async {
    final candidates = <String>{
      for (final raw in candidateUserIds) ChatIdFormat.rawUserUid(raw),
    }..removeWhere((uid) => uid.isEmpty);
    if (candidates.isEmpty || _groupID.trim().isEmpty) {
      return const <String>{};
    }
    if (SelfHostedGroupBridge.enabled) {
      return GroupInviteMemberPageMeta.existingMemberUserIds(
        _groupID,
        candidateUserIds: candidates,
      );
    }
    final res = await _groupServices.getGroupMembersInfo(
      groupID: _groupID,
      memberList: candidates.toList(growable: false),
    );
    if (res.code != 0 || res.data == null) {
      throw StateError('Unable to verify group membership: ${res.desc}');
    }
    return GroupInviteMemberPageMeta.memberUserIdsFromLookup(res.data!);
  }

  Future<V2TimValueCallback<List<V2TimGroupMemberOperationResult>>>
      inviteUserToGroup(List<String> userIDS) async {
    final normalized =
        userIDS.map((id) => id.trim()).where((id) => id.isNotEmpty).toList();
    if (SelfHostedGroupInviteBridge.enabled) {
      final bridged = await SelfHostedGroupInviteBridge.tryInvite(
        groupID: _groupID,
        groupType: _groupInfo?.groupType,
        userList: normalized,
      );
      if (bridged != null) {
        return bridged;
      }
    }
    final res = await _groupServices.inviteUserToGroup(
        groupID: _groupID, userList: normalized);
    return res;
  }
}
