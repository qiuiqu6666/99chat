import 'dart:async';
import 'package:tencent_cloud_chat_uikit/business_logic/services/bounded_lru_map.dart';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_jitter_diag.dart';

class GroupMemberChange {
  final String groupID;
  final String userID;
  final V2TimGroupMemberFullInfo? member;

  const GroupMemberChange({
    required this.groupID,
    required this.userID,
    this.member,
  });
}

class GroupMemberStore extends ChangeNotifier {
  GroupMemberStore._();

  static final GroupMemberStore instance = GroupMemberStore._();

  static const int groupCapacity = 32;
  static const int membersPerGroupCapacity = 256;
  static const int profileOverrideCapacity = 8192;
  final Map<String, Map<String, V2TimGroupMemberFullInfo>> _data =
      BoundedLruMap(groupCapacity,
          normalize: (members) =>
              members is BoundedLruMap<String, V2TimGroupMemberFullInfo>
                  ? members
                  : (BoundedLruMap<String, V2TimGroupMemberFullInfo>(
                      membersPerGroupCapacity)
                    ..addAll(members)));
  final Map<String, Map<String, String>> _nameCardOverrides = BoundedLruMap(
      groupCapacity,
      normalize: (cards) => cards is BoundedLruMap<String, String>
          ? cards
          : (BoundedLruMap<String, String>(membersPerGroupCapacity)
            ..addAll(cards)));
  final Map<String, String> _friendRemarkOverrides =
      BoundedLruMap(profileOverrideCapacity);
  final Map<String, String> _nicknameOverrides =
      BoundedLruMap(profileOverrideCapacity);
  final Map<String, String> _faceUrlOverrides =
      BoundedLruMap(profileOverrideCapacity);
  // Inbound traffic never creates avatar listeners. Only UI subscriptions do.
  final Map<String, Set<_AvatarRevision>> _activeAvatars = {};
  final Map<String, _AvatarRevision> _avatarRevisions = BoundedLruMap(256);
  int get cachedGroupCount => _data.length;
  int get cachedMemberCount =>
      _data.values.fold(0, (sum, group) => sum + group.length);
  int get avatarSubscriptionCount =>
      _activeAvatars.values.fold(0, (sum, entries) => sum + entries.length);
  int get dormantAvatarCount => _avatarRevisions.length;
  // Synchronous, unbuffered membership removals are distinct from cache eviction.
  final _removals =
      StreamController<({String groupID, Set<String> userIDs})>.broadcast(
          sync: true);
  Stream<({String groupID, Set<String> userIDs})> get removals =>
      _removals.stream;
  GroupMemberChange? _lastChange;
  Timer? _notifyCoalesceTimer;
  final Map<String, Map<String, DateTime>> _removalTombstones =
      <String, Map<String, DateTime>>{};

  /// Push / 入群成员一条条 put 时合并成一帧通知，避免会话列表 lastMsg 跟着抖。
  static const Duration _notifyCoalesce = Duration(milliseconds: 48);

  GroupMemberChange? get lastChange => _lastChange;

  String _avatarRevisionKey(String groupID, String userID) =>
      '${groupID.trim()}|${userID.trim()}';

  ValueListenable<int> avatarListenable(String groupID, String userID) {
    final key = _avatarRevisionKey(groupID, userID);
    final active = _activeAvatars[key];
    if (active != null && active.isNotEmpty) return active.first;
    return _avatarRevisions.putIfAbsent(
        key,
        () => _AvatarRevision(
              onActive: (revision) {
                _avatarRevisions.remove(key);
                (_activeAvatars[key] ??= <_AvatarRevision>{}).add(revision);
              },
              onIdle: (revision) {
                final active = _activeAvatars[key];
                active?.remove(revision);
                if (active?.isEmpty == true) _activeAvatars.remove(key);
              },
            ));
  }

  void _scheduleCoalescedNotify() {
    if (_notifyCoalesceTimer?.isActive == true) return;
    _notifyCoalesceTimer = Timer(_notifyCoalesce, () {
      _notifyCoalesceTimer = null;
      notifyListeners();
    });
  }

  void _notifyAvatarUsers(String groupID, Iterable<String> userIDs) {
    final groupKey = groupID.trim();
    if (groupKey.isEmpty) {
      return;
    }
    for (final rawUserID in userIDs.toSet()) {
      final userID = rawUserID.trim();
      if (userID.isEmpty) {
        continue;
      }
      final key = _avatarRevisionKey(groupKey, userID);
      final revisions = <_AvatarRevision>{
        ...?_activeAvatars[key],
        if (_avatarRevisions[key] case final revision?) revision,
      };
      for (final revision in revisions) revision.value++;
    }
  }

  String _tombstoneUserId(String? userID) => ChatIdFormat.rawUserUid(userID);

  bool isRemovalTombstoned(String groupID, String userID) {
    final key = ChatIdFormat.canonicalGroupStorageId(groupID);
    final uid = _tombstoneUserId(userID);
    if (key.isEmpty || uid.isEmpty) {
      return false;
    }
    final group = _removalTombstones[key];
    if (group == null) {
      return false;
    }
    final removedAt = group[uid];
    if (removedAt == null) {
      return false;
    }
    // Elapsed time is not evidence of rejoining. Clear on a confirmed join
    // or session reset, so late page/search responses cannot revive a kick.
    return true;
  }

  void clearRemovalTombstones(String groupID, Iterable<String> userIds) {
    final key = ChatIdFormat.canonicalGroupStorageId(groupID);
    if (key.isEmpty) {
      return;
    }
    final group = _removalTombstones[key];
    if (group == null) {
      return;
    }
    for (final raw in userIds) {
      final uid = _tombstoneUserId(raw);
      if (uid.isNotEmpty) {
        group.remove(uid);
      }
    }
    if (group.isEmpty) {
      _removalTombstones.remove(key);
    }
  }

  void putMembers(String groupID, Iterable<V2TimGroupMemberFullInfo?> members,
      {bool notify = false}) {
    final key = groupID.trim();
    if (key.isEmpty) {
      return;
    }
    final changedUserIDs = <String>{};
    for (final member in members) {
      final userID = (member?.userID ?? '').trim();
      if (member == null || userID.isEmpty) {
        continue;
      }
      if (isRemovalTombstoned(key, userID)) {
        continue;
      }
      _applyOverrides(key, member);
      final bucket =
          _data.putIfAbsent(key, () => <String, V2TimGroupMemberFullInfo>{});
      final prev = bucket[userID];
      // 仅在真正新增或头像/名片变化时算 changed，避免进页重复 hydrate 空通知。
      if (prev == null ||
          prev.faceUrl != member.faceUrl ||
          prev.nickName != member.nickName ||
          prev.nameCard != member.nameCard ||
          prev.friendRemark != member.friendRemark) {
        changedUserIDs.add(userID);
      }
      bucket[userID] = member;
    }
    if (changedUserIDs.isNotEmpty && notify) {
      ChatJitterDiag.logGroupMemberStore(
        action: 'putMembers',
        groupId: key,
        memberCount: _data[key]?.length,
        notify: true,
      );
      _notifyAvatarUsers(key, changedUserIDs);
      _scheduleCoalescedNotify();
    }
  }

  Set<String> avatarRefreshUserIDs(
    String groupID,
    Iterable<V2TimGroupMemberFullInfo?> members,
  ) {
    final key = groupID.trim();
    if (key.isEmpty) {
      return const <String>{};
    }
    final changedUserIDs = <String>{};
    final bucket = _data[key];
    for (final member in members) {
      final userID = (member?.userID ?? '').trim();
      if (member == null || userID.isEmpty) {
        continue;
      }
      final prev = bucket?[userID];
      if (prev == null ||
          prev.faceUrl != member.faceUrl ||
          prev.nickName != member.nickName ||
          prev.nameCard != member.nameCard ||
          prev.friendRemark != member.friendRemark) {
        changedUserIDs.add(userID);
      }
    }
    return changedUserIDs;
  }

  /// 供调用方判断静默 putMembers 后是否还需要主动 notify。
  bool wouldAvatarRefreshMatter(
    String groupID,
    Iterable<V2TimGroupMemberFullInfo?> members,
  ) {
    return avatarRefreshUserIDs(groupID, members).isNotEmpty;
  }

  void putMember(String groupID, V2TimGroupMemberFullInfo? member,
      {bool notify = true}) {
    final key = groupID.trim();
    final userID = (member?.userID ?? '').trim();
    if (key.isEmpty || member == null || userID.isEmpty) {
      return;
    }
    if (isRemovalTombstoned(key, userID)) {
      return;
    }
    _applyOverrides(key, member);
    final bucket =
        _data.putIfAbsent(key, () => <String, V2TimGroupMemberFullInfo>{});
    final previous = bucket[userID];
    final changed = previous == null ||
        previous.faceUrl != member.faceUrl ||
        previous.nickName != member.nickName ||
        previous.nameCard != member.nameCard ||
        previous.friendRemark != member.friendRemark;
    bucket[userID] = member;
    _lastChange =
        GroupMemberChange(groupID: key, userID: userID, member: member);
    if (notify && changed) {
      ChatJitterDiag.logGroupMemberStore(
        action: 'putMember',
        groupId: key,
        memberCount: _data[key]?.length,
        notify: true,
      );
      _notifyAvatarUsers(key, <String>[userID]);
      _scheduleCoalescedNotify();
    }
  }

  void _applyOverrides(String groupID, V2TimGroupMemberFullInfo member) {
    final userID = member.userID.trim();
    if (userID.isEmpty) {
      return;
    }
    final groupOverrides = _nameCardOverrides[groupID];
    if (groupOverrides != null && groupOverrides.containsKey(userID)) {
      member.nameCard = groupOverrides[userID];
    }
    if (_friendRemarkOverrides.containsKey(userID)) {
      member.friendRemark = _friendRemarkOverrides[userID];
    }
    if (_nicknameOverrides.containsKey(userID)) {
      member.nickName = _nicknameOverrides[userID];
    }
    if (_faceUrlOverrides.containsKey(userID)) {
      member.faceUrl = _faceUrlOverrides[userID];
    }
  }

  /// 将资料页拿到的最新公开资料覆盖到所有群成员快照。
  ///
  /// 覆盖值同时保留给后续 [putMember]/[putMembers]，避免 SDK 的旧成员
  /// 快照在退出聊天后再次把新头像、昵称顶回去。
  void putProfileForUser({
    required String userID,
    String? nickName,
    String? faceUrl,
    bool notify = true,
  }) {
    final uid = userID.trim();
    if (uid.isEmpty) {
      return;
    }
    final nicknameValue = nickName?.trim();
    final faceUrlValue = faceUrl?.trim();
    if (nicknameValue != null && nicknameValue.isNotEmpty) {
      _nicknameOverrides[uid] = nicknameValue;
    }
    if (faceUrlValue != null && faceUrlValue.isNotEmpty) {
      _faceUrlOverrides[uid] = faceUrlValue;
    }
    if ((nicknameValue == null || nicknameValue.isEmpty) &&
        (faceUrlValue == null || faceUrlValue.isEmpty)) {
      return;
    }

    final changedGroups = <String>[];
    for (final entry in _data.entries) {
      final member = entry.value[uid];
      if (member == null) {
        continue;
      }
      final previousNickname = member.nickName;
      final previousFaceUrl = member.faceUrl;
      _applyOverrides(entry.key, member);
      if (previousNickname != member.nickName ||
          previousFaceUrl != member.faceUrl) {
        entry.value[uid] = member;
        changedGroups.add(entry.key);
      }
    }
    if (changedGroups.isNotEmpty) {
      _lastChange = GroupMemberChange(groupID: '', userID: uid);
    }
    if (notify && changedGroups.isNotEmpty) {
      for (final groupID in changedGroups) {
        _notifyAvatarUsers(groupID, <String>[uid]);
      }
      _scheduleCoalescedNotify();
    }
  }

  void putNameCard({
    required String groupID,
    required String userID,
    required String nameCard,
    V2TimGroupMemberFullInfo? member,
    bool notify = true,
  }) {
    final key = groupID.trim();
    final uid = userID.trim();
    if (key.isEmpty || uid.isEmpty) {
      return;
    }
    _nameCardOverrides.putIfAbsent(key, () => <String, String>{})[uid] =
        nameCard;
    final group =
        _data.putIfAbsent(key, () => <String, V2TimGroupMemberFullInfo>{});
    final current =
        member ?? group[uid] ?? V2TimGroupMemberFullInfo(userID: uid);
    final changed = current.nameCard != nameCard;
    current.nameCard = nameCard;
    group[uid] = current;
    _lastChange = GroupMemberChange(groupID: key, userID: uid, member: current);
    if (notify && changed) {
      _notifyAvatarUsers(key, <String>[uid]);
      _scheduleCoalescedNotify();
    }
  }

  /// 主动广播一次变更，供监听方（如聊天页群头像）在成员数据已就位、
  /// 但没有走 put* 写入的场景下触发局部刷新。
  void notifyChatAvatarRefresh() {
    ChatJitterDiag.logGroupMemberStore(
      action: 'notifyChatAvatarRefresh',
      notify: true,
    );
    notifyListeners();
  }

  /// 只刷新指定成员的头像监听器，避免群内所有可见头像同时 rebuild。
  void notifyChatAvatarRefreshForUsers(
    String groupID,
    Iterable<String> userIDs,
  ) {
    final users =
        userIDs.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (groupID.trim().isEmpty || users.isEmpty) {
      return;
    }
    ChatJitterDiag.logGroupMemberStore(
      action: 'notifyChatAvatarRefreshForUsers',
      groupId: groupID.trim(),
      memberCount: users.length,
      notify: true,
    );
    _notifyAvatarUsers(groupID, users);
  }

  V2TimGroupMemberFullInfo? memberOf(String groupID, String userID) {
    return _data[groupID.trim()]?[userID.trim()];
  }

  List<V2TimGroupMemberFullInfo> membersForGroup(String groupID) {
    final group = _data[groupID.trim()];
    if (group == null || group.isEmpty) {
      return const <V2TimGroupMemberFullInfo>[];
    }
    return group.values.toList(growable: false);
  }

  /// Replaces one group's in-memory projection with a durable snapshot.
  /// Unlike [putMembers], this also removes members that no longer exist.
  void replaceGroupSnapshot(
    String groupID,
    Iterable<V2TimGroupMemberFullInfo?> members, {
    bool notify = false,
  }) {
    final key = groupID.trim();
    if (key.isEmpty) return;
    final previous = _data[key] ?? const <String, V2TimGroupMemberFullInfo>{};
    final next = <String, V2TimGroupMemberFullInfo>{};
    final changedUserIDs = <String>{};
    for (final member in members.whereType<V2TimGroupMemberFullInfo>()) {
      final userID = member.userID.trim();
      if (userID.isEmpty) continue;
      _applyOverrides(key, member);
      final old = previous[userID];
      if (old == null ||
          old.faceUrl != member.faceUrl ||
          old.nickName != member.nickName ||
          old.nameCard != member.nameCard ||
          old.friendRemark != member.friendRemark ||
          old.role != member.role) {
        changedUserIDs.add(userID);
      }
      next[userID] = member;
    }
    changedUserIDs.addAll(previous.keys.where((id) => !next.containsKey(id)));
    _data[key] = next;
    if (changedUserIDs.isNotEmpty && notify) {
      _lastChange = GroupMemberChange(groupID: key, userID: '');
      _notifyAvatarUsers(key, changedUserIDs);
      _scheduleCoalescedNotify();
    }
  }

  void putFriendRemarkForUser(String userID, String friendRemark,
      {bool notify = true}) {
    final uid = userID.trim();
    if (uid.isEmpty) {
      return;
    }
    _friendRemarkOverrides[uid] = friendRemark;
    if (_data.isEmpty) {
      return;
    }
    final changedGroups = <String>[];
    for (final entry in _data.entries) {
      final group = entry.value;
      final member = group[uid];
      if (member != null && member.friendRemark != friendRemark) {
        member.friendRemark = friendRemark;
        group[uid] = member;
        changedGroups.add(entry.key);
      }
    }
    if (changedGroups.isNotEmpty) {
      _lastChange = GroupMemberChange(groupID: '', userID: uid);
      if (notify) {
        for (final groupID in changedGroups) {
          _notifyAvatarUsers(groupID, <String>[uid]);
        }
        _scheduleCoalescedNotify();
      }
    }
  }

  /// 用户资料头像变更时，写回内存中已缓存群的该成员 faceUrl（不凭空建成员）。
  void putFaceUrlForUser(String userID, String faceUrl, {bool notify = true}) {
    final uid = userID.trim();
    final face = faceUrl.trim();
    if (uid.isEmpty || face.isEmpty || _data.isEmpty) {
      return;
    }
    final changedGroups = <String>[];
    for (final entry in _data.entries) {
      final group = entry.value;
      final member = group[uid];
      if (member == null) {
        continue;
      }
      if ((member.faceUrl ?? '').trim() == face) {
        continue;
      }
      member.faceUrl = face;
      group[uid] = member;
      changedGroups.add(entry.key);
    }
    if (changedGroups.isEmpty) {
      return;
    }
    _lastChange = GroupMemberChange(groupID: '', userID: uid);
    if (notify) {
      for (final groupID in changedGroups) {
        _notifyAvatarUsers(groupID, <String>[uid]);
      }
      _scheduleCoalescedNotify();
    }
  }

  void removeMembers(String groupID, Iterable<String?> userIDs,
      {bool notify = true}) {
    final key = groupID.trim();
    final ids = userIDs
        .map(_tombstoneUserId)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (key.isEmpty || ids.isEmpty) return;
    final group = _data[key];
    final now = DateTime.now();
    final tombstones = _removalTombstones.putIfAbsent(
        ChatIdFormat.canonicalGroupStorageId(key), () => <String, DateTime>{});
    for (final id in ids) {
      group?.remove(id);
      _nameCardOverrides[key]?.remove(id);
      tombstones[id] = now;
    }
    // Even evicted members may still be present in an open picker.
    _removals.add((groupID: key, userIDs: Set.unmodifiable(ids)));
    if (notify) {
      _notifyAvatarUsers(key, ids);
      _scheduleCoalescedNotify();
    }
  }

  /// 登出或切换账号时清空内存缓存，避免跨账号串数据。
  void clear({bool notify = true}) {
    _notifyCoalesceTimer?.cancel();
    _notifyCoalesceTimer = null;
    if (_data.isEmpty &&
        _nameCardOverrides.isEmpty &&
        _friendRemarkOverrides.isEmpty &&
        _nicknameOverrides.isEmpty &&
        _faceUrlOverrides.isEmpty &&
        _avatarRevisions.isEmpty &&
        _activeAvatars.isEmpty &&
        _removalTombstones.isEmpty &&
        _lastChange == null) {
      return;
    }
    _data.clear();
    _nameCardOverrides.clear();
    _friendRemarkOverrides.clear();
    _nicknameOverrides.clear();
    _faceUrlOverrides.clear();
    _removalTombstones.clear();
    _lastChange = null;
    if (notify) {
      final revisions = <_AvatarRevision>{
        ..._avatarRevisions.values,
        ..._activeAvatars.values.expand((entries) => entries),
      };
      for (final revision in revisions) revision.value++;
      notifyListeners();
    }
    _avatarRevisions.clear();
  }
}

/// Release the store reference on last unsubscribe, not while a widget owns it.
class _AvatarRevision extends ValueNotifier<int> {
  _AvatarRevision({required this.onActive, required this.onIdle}) : super(0);
  final void Function(_AvatarRevision) onActive;
  final void Function(_AvatarRevision) onIdle;
  @override
  void addListener(VoidCallback listener) {
    final wasActive = hasListeners;
    super.addListener(listener);
    if (!wasActive) onActive(this);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) onIdle(this);
  }
}
