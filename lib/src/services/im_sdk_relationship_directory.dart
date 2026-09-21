import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_user_full_info.dart';

typedef RelationshipDirectoryListener = void Function(
  RelationshipDirectoryChange change,
);

enum RelationshipListKind { friends, groups }

enum RelationshipDeltaKind { add, remove, change }

class RelationshipFriendEntry {
  const RelationshipFriendEntry({
    required this.userId,
    required this.displayName,
    required this.faceUrl,
    required this.remark,
    required this.sortKey,
    this.nickname = '',
  });

  final String userId;
  final String displayName;
  final String faceUrl;
  final String remark;
  final String nickname;
  final String sortKey;

  String get fingerprint =>
      '$displayName\u0001$faceUrl\u0001$remark\u0001$nickname';

  String get azTag {
    final sep = sortKey.indexOf('\u0000');
    if (sep <= 0) {
      return sortKey.isEmpty ? '#' : sortKey[0];
    }
    return sortKey.substring(0, sep);
  }

  V2TimFriendInfo toV2TimFriendInfo() {
    return V2TimFriendInfo(
      userID: userId,
      friendRemark: remark.isEmpty ? null : remark,
      userProfile: V2TimUserFullInfo(
        userID: userId,
        nickName: nickname.isEmpty ? null : nickname,
        faceUrl: faceUrl.isEmpty ? null : faceUrl,
      ),
    );
  }

  RelationshipFriendEntry copyWith({
    String? displayName,
    String? faceUrl,
    String? remark,
    String? nickname,
    String? sortKey,
  }) {
    return RelationshipFriendEntry(
      userId: userId,
      displayName: displayName ?? this.displayName,
      faceUrl: faceUrl ?? this.faceUrl,
      remark: remark ?? this.remark,
      nickname: nickname ?? this.nickname,
      sortKey: sortKey ?? this.sortKey,
    );
  }
}

class RelationshipGroupEntry {
  const RelationshipGroupEntry({
    required this.groupId,
    required this.groupName,
    required this.faceUrl,
    required this.groupType,
    required this.sortKey,
    this.memberCount = 0,
    this.role = 0,
  });

  final String groupId;
  final String groupName;
  final String faceUrl;
  final String groupType;
  final String sortKey;
  final int memberCount;
  final int role;

  String get fingerprint =>
      '$groupName\u0001$faceUrl\u0001$groupType\u0001$memberCount\u0001$role';

  String get azTag {
    final sep = sortKey.indexOf('\u0000');
    if (sep <= 0) {
      return sortKey.isEmpty ? '#' : sortKey[0];
    }
    return sortKey.substring(0, sep);
  }

  V2TimGroupInfo toV2TimGroupInfo() {
    return V2TimGroupInfo(
      groupID: groupId,
      groupName: groupName,
      faceUrl: faceUrl,
      groupType: groupType,
      memberCount: memberCount,
      role: role,
    );
  }
}

class RelationshipDirectoryChange {
  const RelationshipDirectoryChange({
    required this.kind,
    required this.revision,
    required this.snapshotCompleted,
    this.addedIds = const <String>[],
    this.removedIds = const <String>[],
    this.metadataChangedIds = const <String>[],
    this.sortKeyChangedIds = const <String>[],
  });

  final RelationshipListKind kind;
  final int revision;
  final bool snapshotCompleted;
  final List<String> addedIds;
  final List<String> removedIds;
  final List<String> metadataChangedIds;
  final List<String> sortKeyChangedIds;

  bool get hasIncrementalIds =>
      addedIds.isNotEmpty ||
      removedIds.isNotEmpty ||
      metadataChangedIds.isNotEmpty ||
      sortKeyChangedIds.isNotEmpty;
}

class RelationshipDelta {
  const RelationshipDelta({
    required this.kind,
    required this.id,
    this.friend,
    this.group,
  });

  final RelationshipDeltaKind kind;
  final String id;
  final RelationshipFriendEntry? friend;
  final RelationshipGroupEntry? group;
}

class _Capture {
  _Capture(this.id);

  final int id;
  final List<RelationshipDelta> deltas = <RelationshipDelta>[];
}

/// Lightweight IM relationship truth. UI projection is a separate consumer.
class ImSdkRelationshipDirectory {
  ImSdkRelationshipDirectory();

  static final ImSdkRelationshipDirectory instance =
      ImSdkRelationshipDirectory();

  final Map<String, RelationshipFriendEntry> _friends =
      <String, RelationshipFriendEntry>{};
  final List<String> _friendOrderedIds = <String>[];
  final Map<String, RelationshipGroupEntry> _groups =
      <String, RelationshipGroupEntry>{};
  final List<String> _groupOrderedIds = <String>[];
  final List<RelationshipDirectoryListener> _listeners =
      <RelationshipDirectoryListener>[];

  final Map<int, _Capture> _friendCaptures = <int, _Capture>{};
  final Map<int, _Capture> _groupCaptures = <int, _Capture>{};
  int _friendFetchGeneration = 0;
  int _groupFetchGeneration = 0;
  int _friendRevision = 0;
  int _groupRevision = 0;
  bool _friendsComplete = false;
  bool _groupsComplete = false;

  int get friendRevision => _friendRevision;
  int get groupRevision => _groupRevision;
  bool get hasCompleteFriendSnapshot => _friendsComplete;
  bool get hasCompleteGroupSnapshot => _groupsComplete;
  int get friendCount => _friends.length;
  int get groupCount => _groups.length;
  List<String> get friendOrderedIds =>
      List<String>.unmodifiable(_friendOrderedIds);
  List<String> get groupOrderedIds => List<String>.unmodifiable(_groupOrderedIds);

  RelationshipFriendEntry? friend(String userId) => _friends[userId];
  RelationshipGroupEntry? group(String groupId) => _groups[groupId];
  Iterable<RelationshipGroupEntry> get groupEntries => _groups.values;

  void addListener(RelationshipDirectoryListener listener) {
    _listeners.add(listener);
  }

  void removeListener(RelationshipDirectoryListener listener) {
    _listeners.remove(listener);
  }

  void reset() {
    _friends.clear();
    _friendOrderedIds.clear();
    _groups.clear();
    _groupOrderedIds.clear();
    _friendCaptures.clear();
    _groupCaptures.clear();
    _friendFetchGeneration = 0;
    _groupFetchGeneration = 0;
    _friendRevision = 0;
    _groupRevision = 0;
    _friendsComplete = false;
    _groupsComplete = false;
  }

  int beginFriendCapture() {
    final id = ++_friendFetchGeneration;
    _friendCaptures[id] = _Capture(id);
    return id;
  }

  int beginGroupCapture() {
    final id = ++_groupFetchGeneration;
    _groupCaptures[id] = _Capture(id);
    return id;
  }

  void dropFriendCapture(int captureId) {
    _friendCaptures.remove(captureId);
  }

  void dropGroupCapture(int captureId) {
    _groupCaptures.remove(captureId);
  }

  void applyFriendAdds(List<RelationshipFriendEntry> entries) {
    if (entries.isEmpty) {
      return;
    }
    final deltas = <RelationshipDelta>[
      for (final entry in entries)
        RelationshipDelta(
          kind: RelationshipDeltaKind.add,
          id: entry.userId,
          friend: entry,
        ),
    ];
    _appendFriendDeltas(deltas);
    _applyFriendDeltasLive(deltas, publish: _friendsComplete);
  }

  void applyFriendRemoves(List<String> userIds) {
    if (userIds.isEmpty) {
      return;
    }
    final deltas = <RelationshipDelta>[
      for (final id in userIds)
        if (id.trim().isNotEmpty)
          RelationshipDelta(kind: RelationshipDeltaKind.remove, id: id.trim()),
    ];
    if (deltas.isEmpty) {
      return;
    }
    _appendFriendDeltas(deltas);
    _applyFriendDeltasLive(deltas, publish: _friendsComplete);
  }

  void applyFriendChanges(List<RelationshipFriendEntry> entries) {
    if (entries.isEmpty) {
      return;
    }
    final deltas = <RelationshipDelta>[
      for (final entry in entries)
        RelationshipDelta(
          kind: RelationshipDeltaKind.change,
          id: entry.userId,
          friend: entry,
        ),
    ];
    _appendFriendDeltas(deltas);
    _applyFriendDeltasLive(deltas, publish: _friendsComplete);
  }

  void applyGroupAdds(List<RelationshipGroupEntry> entries) {
    if (entries.isEmpty) {
      return;
    }
    final deltas = <RelationshipDelta>[
      for (final entry in entries)
        RelationshipDelta(
          kind: RelationshipDeltaKind.add,
          id: entry.groupId,
          group: entry,
        ),
    ];
    _appendGroupDeltas(deltas);
    _applyGroupDeltasLive(deltas, publish: _groupsComplete);
  }

  void applyGroupRemoves(List<String> groupIds) {
    if (groupIds.isEmpty) {
      return;
    }
    final deltas = <RelationshipDelta>[
      for (final id in groupIds)
        if (id.trim().isNotEmpty)
          RelationshipDelta(kind: RelationshipDeltaKind.remove, id: id.trim()),
    ];
    if (deltas.isEmpty) {
      return;
    }
    _appendGroupDeltas(deltas);
    _applyGroupDeltasLive(deltas, publish: _groupsComplete);
  }

  void applyGroupChanges(List<RelationshipGroupEntry> entries) {
    if (entries.isEmpty) {
      return;
    }
    final deltas = <RelationshipDelta>[
      for (final entry in entries)
        RelationshipDelta(
          kind: RelationshipDeltaKind.change,
          id: entry.groupId,
          group: entry,
        ),
    ];
    _appendGroupDeltas(deltas);
    _applyGroupDeltasLive(deltas, publish: _groupsComplete);
  }

  /// Atomically replace friends with [entries] then replay capture deltas.
  /// [orderedIds] is the snapshot order before replay; omit to sort locally.
  void applyFriendSnapshot({
    required int captureId,
    required List<RelationshipFriendEntry> entries,
    List<String>? orderedIds,
  }) {
    final capture = _friendCaptures.remove(captureId);
    if (capture == null) {
      return;
    }
    final wasComplete = _friendsComplete;
    final oldIds = Set<String>.from(_friends.keys);
    final oldFriends = Map<String, RelationshipFriendEntry>.from(_friends);
    final next = <String, RelationshipFriendEntry>{
      for (final entry in entries)
        if (entry.userId.isNotEmpty) entry.userId: entry,
    };
    for (final delta in capture.deltas) {
      _applyFriendDeltaToMap(next, delta);
    }
    _friends
      ..clear()
      ..addAll(next);
    _rebuildFriendOrder(
      preferredOrder: orderedIds,
      snapshotIds: <String>[
        for (final entry in entries)
          if (entry.userId.isNotEmpty) entry.userId,
      ],
    );
    _friendsComplete = true;
    if (!wasComplete) {
      _friendRevision++;
      _emit(
        RelationshipDirectoryChange(
          kind: RelationshipListKind.friends,
          revision: _friendRevision,
          snapshotCompleted: true,
        ),
      );
      return;
    }
    _publishFriendDiff(oldIds, oldFriends, snapshotCompleted: false);
  }

  void applyGroupSnapshot({
    required int captureId,
    required List<RelationshipGroupEntry> entries,
    List<String>? orderedIds,
  }) {
    final capture = _groupCaptures.remove(captureId);
    if (capture == null) {
      return;
    }
    final wasComplete = _groupsComplete;
    final oldIds = Set<String>.from(_groups.keys);
    final oldGroups = Map<String, RelationshipGroupEntry>.from(_groups);
    final next = <String, RelationshipGroupEntry>{
      for (final entry in entries)
        if (entry.groupId.isNotEmpty) entry.groupId: entry,
    };
    for (final delta in capture.deltas) {
      _applyGroupDeltaToMap(next, delta);
    }
    _groups
      ..clear()
      ..addAll(next);
    _rebuildGroupOrder(
      preferredOrder: orderedIds,
      snapshotIds: <String>[
        for (final entry in entries)
          if (entry.groupId.isNotEmpty) entry.groupId,
      ],
    );
    _groupsComplete = true;
    if (!wasComplete) {
      _groupRevision++;
      _emit(
        RelationshipDirectoryChange(
          kind: RelationshipListKind.groups,
          revision: _groupRevision,
          snapshotCompleted: true,
        ),
      );
      return;
    }
    _publishGroupDiff(oldIds, oldGroups, snapshotCompleted: false);
  }

  static String sortKeyFor({
    required String id,
    required String displayName,
    required String azTag,
  }) {
    return '$azTag\u0000$displayName\u0000$id';
  }

  void _appendFriendDeltas(List<RelationshipDelta> deltas) {
    for (final capture in _friendCaptures.values) {
      capture.deltas.addAll(deltas);
    }
  }

  void _appendGroupDeltas(List<RelationshipDelta> deltas) {
    for (final capture in _groupCaptures.values) {
      capture.deltas.addAll(deltas);
    }
  }

  void _applyFriendDeltasLive(
    List<RelationshipDelta> deltas, {
    required bool publish,
  }) {
    final oldIds = publish ? Set<String>.from(_friends.keys) : null;
    final oldFriends = publish
        ? Map<String, RelationshipFriendEntry>.from(_friends)
        : null;
    for (final delta in deltas) {
      _applyFriendDeltaToMap(_friends, delta);
      _patchFriendOrder(delta);
    }
    if (publish && oldIds != null && oldFriends != null) {
      _publishFriendDiff(oldIds, oldFriends, snapshotCompleted: false);
    }
  }

  void _applyGroupDeltasLive(
    List<RelationshipDelta> deltas, {
    required bool publish,
  }) {
    final oldIds = publish ? Set<String>.from(_groups.keys) : null;
    final oldGroups =
        publish ? Map<String, RelationshipGroupEntry>.from(_groups) : null;
    for (final delta in deltas) {
      _applyGroupDeltaToMap(_groups, delta);
      _patchGroupOrder(delta);
    }
    if (publish && oldIds != null && oldGroups != null) {
      _publishGroupDiff(oldIds, oldGroups, snapshotCompleted: false);
    }
  }

  void _applyFriendDeltaToMap(
    Map<String, RelationshipFriendEntry> map,
    RelationshipDelta delta,
  ) {
    switch (delta.kind) {
      case RelationshipDeltaKind.add:
        if (delta.friend != null) {
          map[delta.id] = delta.friend!;
        }
        break;
      case RelationshipDeltaKind.remove:
        map.remove(delta.id);
        break;
      case RelationshipDeltaKind.change:
        if (delta.friend != null) {
          map[delta.id] = delta.friend!;
        }
        break;
    }
  }

  void _applyGroupDeltaToMap(
    Map<String, RelationshipGroupEntry> map,
    RelationshipDelta delta,
  ) {
    switch (delta.kind) {
      case RelationshipDeltaKind.add:
        if (delta.group != null) {
          map[delta.id] = delta.group!;
        }
        break;
      case RelationshipDeltaKind.remove:
        map.remove(delta.id);
        break;
      case RelationshipDeltaKind.change:
        if (delta.group != null) {
          map[delta.id] = delta.group!;
        }
        break;
    }
  }

  void _rebuildFriendOrder({
    List<String>? preferredOrder,
    required List<String> snapshotIds,
  }) {
    if (_friends.isEmpty) {
      _friendOrderedIds.clear();
      return;
    }
    final remaining = Set<String>.from(_friends.keys);
    final next = <String>[];
    if (preferredOrder != null) {
      for (final id in preferredOrder) {
        if (remaining.remove(id)) {
          next.add(id);
        }
      }
    }
    final leftover = remaining.toList(growable: false);
    leftover.sort((a, b) {
      final ea = _friends[a]!;
      final eb = _friends[b]!;
      final byKey = ea.sortKey.compareTo(eb.sortKey);
      if (byKey != 0) {
        return byKey;
      }
      return a.compareTo(b);
    });
    // Replay may add ids that were not in the snapshot order.
    if (next.isEmpty) {
      next.addAll(leftover);
    } else {
      for (final id in leftover) {
        _insertOrdered(next, id, _friends[id]!.sortKey);
      }
    }
    _friendOrderedIds
      ..clear()
      ..addAll(next);
  }

  void _rebuildGroupOrder({
    List<String>? preferredOrder,
    required List<String> snapshotIds,
  }) {
    if (_groups.isEmpty) {
      _groupOrderedIds.clear();
      return;
    }
    final remaining = Set<String>.from(_groups.keys);
    final next = <String>[];
    if (preferredOrder != null) {
      for (final id in preferredOrder) {
        if (remaining.remove(id)) {
          next.add(id);
        }
      }
    }
    final leftover = remaining.toList(growable: false);
    leftover.sort((a, b) {
      final ea = _groups[a]!;
      final eb = _groups[b]!;
      final byKey = ea.sortKey.compareTo(eb.sortKey);
      if (byKey != 0) {
        return byKey;
      }
      return a.compareTo(b);
    });
    if (next.isEmpty) {
      next.addAll(leftover);
    } else {
      for (final id in leftover) {
        _insertOrdered(next, id, _groups[id]!.sortKey);
      }
    }
    _groupOrderedIds
      ..clear()
      ..addAll(next);
  }

  void _patchFriendOrder(RelationshipDelta delta) {
    switch (delta.kind) {
      case RelationshipDeltaKind.remove:
        _friendOrderedIds.remove(delta.id);
        break;
      case RelationshipDeltaKind.add:
      case RelationshipDeltaKind.change:
        final entry = _friends[delta.id];
        if (entry == null) {
          _friendOrderedIds.remove(delta.id);
          break;
        }
        _friendOrderedIds.remove(delta.id);
        _insertOrdered(_friendOrderedIds, delta.id, entry.sortKey);
        break;
    }
  }

  void _patchGroupOrder(RelationshipDelta delta) {
    switch (delta.kind) {
      case RelationshipDeltaKind.remove:
        _groupOrderedIds.remove(delta.id);
        break;
      case RelationshipDeltaKind.add:
      case RelationshipDeltaKind.change:
        final entry = _groups[delta.id];
        if (entry == null) {
          _groupOrderedIds.remove(delta.id);
          break;
        }
        _groupOrderedIds.remove(delta.id);
        _insertOrdered(_groupOrderedIds, delta.id, entry.sortKey);
        break;
    }
  }

  void _insertOrdered(List<String> ids, String id, String sortKey) {
    var low = 0;
    var high = ids.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      final other = ids[mid];
      final otherKey = _friends[other]?.sortKey ?? _groups[other]?.sortKey ?? '';
      final cmp = sortKey.compareTo(otherKey);
      if (cmp < 0 || (cmp == 0 && id.compareTo(other) < 0)) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    ids.insert(low, id);
  }

  void _publishFriendDiff(
    Set<String> oldIds,
    Map<String, RelationshipFriendEntry> oldFriends, {
    required bool snapshotCompleted,
  }) {
    final added = <String>[];
    final removed = <String>[];
    final metadata = <String>[];
    final sortKey = <String>[];
    for (final id in _friends.keys) {
      if (!oldIds.contains(id)) {
        added.add(id);
        continue;
      }
      final prev = oldFriends[id];
      final next = _friends[id]!;
      if (prev == null) {
        added.add(id);
        continue;
      }
      if (prev.sortKey != next.sortKey) {
        sortKey.add(id);
      } else if (prev.fingerprint != next.fingerprint) {
        metadata.add(id);
      }
    }
    for (final id in oldIds) {
      if (!_friends.containsKey(id)) {
        removed.add(id);
      }
    }
    if (added.isEmpty &&
        removed.isEmpty &&
        metadata.isEmpty &&
        sortKey.isEmpty &&
        !snapshotCompleted) {
      return;
    }
    _friendRevision++;
    _emit(
      RelationshipDirectoryChange(
        kind: RelationshipListKind.friends,
        revision: _friendRevision,
        snapshotCompleted: snapshotCompleted,
        addedIds: added,
        removedIds: removed,
        metadataChangedIds: metadata,
        sortKeyChangedIds: sortKey,
      ),
    );
  }

  void _publishGroupDiff(
    Set<String> oldIds,
    Map<String, RelationshipGroupEntry> oldGroups, {
    required bool snapshotCompleted,
  }) {
    final added = <String>[];
    final removed = <String>[];
    final metadata = <String>[];
    final sortKey = <String>[];
    for (final id in _groups.keys) {
      if (!oldIds.contains(id)) {
        added.add(id);
        continue;
      }
      final prev = oldGroups[id];
      final next = _groups[id]!;
      if (prev == null) {
        added.add(id);
        continue;
      }
      if (prev.sortKey != next.sortKey) {
        sortKey.add(id);
      } else if (prev.fingerprint != next.fingerprint) {
        metadata.add(id);
      }
    }
    for (final id in oldIds) {
      if (!_groups.containsKey(id)) {
        removed.add(id);
      }
    }
    if (added.isEmpty &&
        removed.isEmpty &&
        metadata.isEmpty &&
        sortKey.isEmpty &&
        !snapshotCompleted) {
      return;
    }
    _groupRevision++;
    _emit(
      RelationshipDirectoryChange(
        kind: RelationshipListKind.groups,
        revision: _groupRevision,
        snapshotCompleted: snapshotCompleted,
        addedIds: added,
        removedIds: removed,
        metadataChangedIds: metadata,
        sortKeyChangedIds: sortKey,
      ),
    );
  }

  void _emit(RelationshipDirectoryChange change) {
    final listeners = List<RelationshipDirectoryListener>.from(_listeners);
    for (final listener in listeners) {
      listener(change);
    }
  }
}
