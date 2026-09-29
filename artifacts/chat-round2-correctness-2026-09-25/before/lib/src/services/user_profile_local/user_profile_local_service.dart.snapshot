import 'package:tencent_cloud_chat_demo/src/api/auth_api.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/bounded_lru_map.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/user_profile_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_warmup_remark_gate.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_store.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_user_full_info.dart';

class UserProfileLocalService {
  UserProfileLocalService._();

  static final UserProfileLocalService instance = UserProfileLocalService._();

  final UserProfileLocalStore _store = UserProfileLocalStore.instance;

  static const int memoryCapacity = 4096;
  final BoundedLruMap<String, UserProfileRecord> _memory =
      BoundedLruMap(memoryCapacity);
  int get cachedProfileCount => _memory.length;
  int get profileCacheEvictions => _memory.evictions;
  final Map<String, Future<V2TimFriendInfo?>> _friendInfoInFlight =
      <String, Future<V2TimFriendInfo?>>{};

  /// 页面同步渲染时的单聊资料真源。首次 [read] 后由所有写入统一维护。
  UserProfileRecord? readCached(String userId) => _memory[userId.trim()];

  /// Share real SDK remarks with profile pages when their UIKit list is empty.
  /// This is only a fallback: a confirmed local remark (including a clear) wins.
  /// No refresh notification here, since contacts are already publishing a list.
  void hydrateImFriendRemarkFallbacks(List<V2TimFriendInfo> friends) {
    for (final friend in friends) {
      final id = ChatIdFormat.rawUserUid(friend.userID);
      final remark = friend.friendRemark?.trim() ?? '';
      if (id.isEmpty || remark.isEmpty) continue;
      final current = _memory[id];
      if (current?.friendRemarkConfirmed == true ||
          (current?.friendRemark.trim().isNotEmpty ?? false)) {
        continue;
      }
      _memory[id] = (current ?? UserProfileRecord(userId: id))
          .copyWith(friendRemark: remark);
    }
  }

  /// 仅 [saveFriendRemark] / 好友快照预热会确认备注；公开资料的空备注不是清空。
  bool isFriendRemarkConfirmed(String userId) {
    final record = _memory[userId.trim()];
    if (record == null) {
      return false;
    }
    return record.friendRemarkConfirmed;
  }

  Future<UserProfileRecord?> read(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return null;
    final cached = _memory[id];
    if (cached != null) return cached;
    final record = await _store.read(userId: id);
    // Visible-row warmup or a remark edit may have completed during disk I/O.
    final current = _memory[id];
    if (current != null) return current;
    if (record == null) return null;
    final overlaid = await _overlayUnconfirmedFriendRemark(record);
    // A remark edit/warmup may also finish during the friend-store lookup.
    final latest = _memory[id];
    if (latest != null) return latest;
    _memory[id] = overlaid;
    return overlaid;
  }

  Future<UserProfileRecord> _overlayUnconfirmedFriendRemark(
    UserProfileRecord record,
  ) async {
    if (record.friendRemark.trim().isNotEmpty) {
      return record;
    }
    if (record.friendRemarkConfirmed) {
      return record;
    }
    final lookupId = ChatIdFormat.rawUserUid(record.userId);
    if (lookupId.isEmpty) {
      return record;
    }
    final friendRecord = await MeFriendApi.instance.cachedByUserId(lookupId);
    if (friendRecord == null || !friendRecord.remarkKnown) {
      return record;
    }
    return record.copyWith(
      friendRemark: friendRecord.remark.trim(),
      friendRemarkConfirmed: true,
    );
  }

  Future<void> _saveAndPublish(
    UserProfileRecord next, {
    bool writesFriendRemark = false,
  }) async {
    final id = next.userId.trim();
    if (id.isEmpty) return;
    final previous = _memory[id];
    // 磁盘/内存均无记录时（如首次 saveUserFullInfo），公开资料不带备注；
    // 先用托管好友库的备注叠加，否则内存镜像只剩昵称，通讯录会显示昵称。
    if (!writesFriendRemark &&
        previous == null &&
        next.friendRemark.trim().isEmpty) {
      next = await _overlayUnconfirmedFriendRemark(next);
    }
    while (true) {
      final current = _memory[id];
      if (!writesFriendRemark && current != null) {
        next = next.copyWith(
          friendRemark: current.friendRemark,
          friendRemarkConfirmed: current.friendRemarkConfirmed,
        );
      }
      if (writesFriendRemark) {
        next = next.copyWith(friendRemarkConfirmed: true);
      }
      await _store.upsert(record: next);
      // A public-profile save must not publish an old remark after warmup or
      // an explicit edit. Rebase the persisted copy too, not only the UI cache.
      if (!writesFriendRemark && !identical(_memory[id], current)) continue;
      break;
    }
    _memory[id] = next;
    if (next.friendRemarkConfirmed) {
      final displayName = next.friendRemark.trim().isNotEmpty
          ? next.friendRemark.trim()
          : (next.nickname.trim().isNotEmpty ? next.nickname.trim() : id);
      // 包括“清空备注”：必须覆盖 Store 的旧备注，不能保留旧值。
      DisplayNameStore.instance.setC2C(id, displayName, notify: false);
    } else {
      DisplayNameStore.instance.applyImFriendShowName(
        userID: id,
        imRemark: next.friendRemark,
        imNickName: next.nickname,
        notify: false,
      );
    }
    GroupMemberStore.instance.putProfileForUser(
      userID: id,
      nickName: next.nickname,
      faceUrl: next.avatarUrl,
    );
    if (next.friendRemarkConfirmed || next.friendRemark.isNotEmpty) {
      GroupMemberStore.instance.putFriendRemarkForUser(id, next.friendRemark);
    }
    if (previous == null ||
        previous.nickname != next.nickname ||
        previous.avatarUrl != next.avatarUrl ||
        previous.avatarVersion != next.avatarVersion ||
        previous.friendRemarkConfirmed != next.friendRemarkConfirmed ||
        previous.friendRemark != next.friendRemark) {
      PeerProfileRefreshBus.instance.notify(id);
    }
  }

  Future<V2TimFriendInfo?> loadFriendInfo(String userId) {
    final id = userId.trim();
    if (id.isEmpty) return Future<V2TimFriendInfo?>.value();
    final active = _friendInfoInFlight[id];
    if (active != null) return active;
    late final Future<V2TimFriendInfo?> task;
    task = _loadFriendInfoImpl(id).whenComplete(() {
      if (identical(_friendInfoInFlight[id], task)) {
        _friendInfoInFlight.remove(id);
      }
    });
    _friendInfoInFlight[id] = task;
    return task;
  }

  Future<V2TimFriendInfo?> _loadFriendInfoImpl(String userId) async {
    final record = await read(userId);
    return mergeHostedFriendRemark(userId, record?.toV2TimFriendInfo());
  }

  /// 当资料缓存里没有备注时，从 [FriendLocalStore]（通讯录同源）补齐；
  /// 已清空的备注也必须覆盖 IM 残留值。
  Future<V2TimFriendInfo?> mergeHostedFriendRemark(
    String userId,
    V2TimFriendInfo? info,
  ) async {
    final id = userId.trim();
    if (id.isEmpty) {
      return info;
    }

    var target = info ?? V2TimFriendInfo(userID: id);
    target.userProfile ??= V2TimUserFullInfo(userID: id);

    final friendRecord = await MeFriendApi.instance.cachedByUserId(id);
    if (friendRecord == null) {
      return info == null ? null : target;
    }

    // 自托管好友库是备注真源：空字符串表示已清空，不能被 IM 旧备注顶回去。
    if (friendRecord.remarkKnown) {
      target.friendRemark = friendRecord.remark.trim();
    }

    final nickname = friendRecord.friendNickname.trim();
    if (nickname.isNotEmpty &&
        (target.userProfile?.nickName?.trim().isEmpty ?? true)) {
      target.userProfile!.nickName = nickname;
    }

    final avatar = friendRecord.friendAvatarUrl.trim();
    if (avatar.isNotEmpty &&
        (target.userProfile?.faceUrl?.trim().isEmpty ?? true)) {
      target.userProfile!.faceUrl = avatar;
    }

    return target;
  }

  Future<V2TimUserFullInfo?> loadUserFullInfo(String userId) async {
    final record = await read(userId);
    return record?.toV2TimUserFullInfo();
  }

  Future<void> saveFriendInfo(V2TimFriendInfo? info) async {
    if (info == null) {
      return;
    }
    final id = info.userID.trim();
    if (id.isEmpty) {
      return;
    }
    final existing = await read(id);
    final next = (existing ?? UserProfileRecord(userId: id))
        .mergeSdkRemotePreferLocal(info);
    await _saveAndPublish(next);
  }

  Future<void> saveUserFullInfo(V2TimUserFullInfo? info) async {
    if (info == null) {
      return;
    }
    final id = info.userID?.trim() ?? '';
    if (id.isEmpty) {
      return;
    }
    final existing = await read(id);
    final next = (existing ?? UserProfileRecord(userId: id))
        .mergeSdkRemoteUserInfoPreferLocal(info);
    await _saveAndPublish(next);
  }

  Future<void> saveMeResult(MeResult me) async {
    final id = me.userId.trim();
    if (id.isEmpty) {
      return;
    }
    final existing = await read(id);
    final next = (existing ?? UserProfileRecord(userId: id)).copyWith(
      nickname: me.nickname.trim().isNotEmpty
          ? me.nickname.trim()
          : (existing?.nickname ?? ''),
      avatarUrl: me.avatarUrl?.trim().isNotEmpty == true
          ? me.avatarUrl!.trim()
          : (existing?.avatarUrl ?? ''),
      avatarVersion: me.avatarVersion > 0
          ? me.avatarVersion
          : (existing?.avatarVersion ?? 0),
      updatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    await _saveAndPublish(next);
  }

  /// 自建 API 公开资料写入本地（强制覆盖昵称/头像）。
  Future<void> saveBackendProfile({
    required String userId,
    String? nickname,
    String? avatarUrl,
    int? avatarVersion,
  }) async {
    final id = userId.trim();
    if (id.isEmpty) {
      return;
    }
    final existing = await read(id);
    final next = (existing ?? UserProfileRecord(userId: id)).copyWith(
      nickname: nickname?.trim().isNotEmpty == true
          ? nickname!.trim()
          : (existing?.nickname ?? ''),
      avatarUrl: avatarUrl?.trim().isNotEmpty == true
          ? avatarUrl!.trim()
          : (existing?.avatarUrl ?? ''),
      avatarVersion: avatarVersion != null && avatarVersion > 0
          ? avatarVersion
          : (existing?.avatarVersion ?? 0),
      updatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    await _saveAndPublish(next);
  }

  Future<void> saveFriendRecord(MeFriendRecord record) async {
    final id = record.friendUserId.trim();
    if (id.isEmpty) {
      return;
    }
    final existing = await read(id);
    final next = _mergeFriendRecord(
      existing ?? UserProfileRecord(userId: id),
      record,
    );
    await _saveAndPublish(next, writesFriendRemark: record.remarkKnown);
  }

  /// Saves friend-backed profiles in bounded transactions while preserving the
  /// single-record merge rules: non-empty public fields win, but an empty
  /// friend remark is an explicit clear.
  Future<void> saveFriendRecords(
    List<MeFriendRecord> records, {
    String? ownerUserId,
    int? accountGeneration,
    bool Function()? isCurrent,
  }) async {
    if (records.isEmpty) {
      return;
    }
    final owner = ownerUserId?.trim().isNotEmpty == true
        ? ownerUserId!.trim()
        : _store.currentOwnerUserId();
    if (owner.isEmpty) {
      return;
    }
    final generation = accountGeneration;
    bool canCommit() {
      if (isCurrent != null && !isCurrent()) {
        return false;
      }
      return generation == null ||
          SessionIdentityService.instance.isGenerationCurrent(generation);
    }

    const batchSize = 100;
    for (var offset = 0; offset < records.length; offset += batchSize) {
      if (!canCommit()) {
        return;
      }
      final end = offset + batchSize > records.length
          ? records.length
          : offset + batchSize;
      final input = records.sublist(offset, end);
      final ids = input
          .map((record) => record.friendUserId.trim())
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      if (ids.isEmpty) {
        continue;
      }
      final stored = await _store.readByIds(
        userIds: ids,
        ownerUserId: owner,
      );
      final previousById = <String, UserProfileRecord>{};
      for (final id in ids) {
        final cached = _memory[id];
        if (cached != null) {
          previousById[id] = cached;
        }
      }
      for (final record in stored) {
        previousById.putIfAbsent(record.userId, () => record);
      }

      final nextById = <String, UserProfileRecord>{};
      for (final record in input) {
        final id = record.friendUserId.trim();
        if (id.isEmpty) {
          continue;
        }
        final existing =
            nextById[id] ?? previousById[id] ?? UserProfileRecord(userId: id);
        nextById[id] = _mergeFriendRecord(existing, record);
      }
      final nextRecords = nextById.values.toList(growable: false);
      if (nextRecords.isEmpty) {
        continue;
      }
      await _store.upsertBatch(
        records: nextRecords,
        ownerUserId: owner,
      );
      if (!canCommit()) {
        return;
      }

      var groupStoreChanged = false;
      final changedIds = <String>{};
      for (final next in nextRecords) {
        final id = next.userId.trim();
        final previous = previousById[id];
        _memory[id] = next;
        final displayName = next.friendRemark.trim().isNotEmpty
            ? next.friendRemark.trim()
            : (next.nickname.trim().isNotEmpty ? next.nickname.trim() : id);
        if (next.friendRemarkConfirmed || next.friendRemark.isNotEmpty) {
          DisplayNameStore.instance.setC2C(id, displayName, notify: false);
        }
        GroupMemberStore.instance.putProfileForUser(
          userID: id,
          nickName: next.nickname,
          faceUrl: next.avatarUrl,
          notify: false,
        );
        if (next.friendRemarkConfirmed || next.friendRemark.isNotEmpty) {
          GroupMemberStore.instance.putFriendRemarkForUser(
            id,
            next.friendRemark,
            notify: false,
          );
        }
        if (previous == null ||
            previous.nickname != next.nickname ||
            previous.avatarUrl != next.avatarUrl ||
            previous.avatarVersion != next.avatarVersion ||
            previous.friendRemarkConfirmed != next.friendRemarkConfirmed ||
            previous.friendRemark != next.friendRemark) {
          changedIds.add(id);
          groupStoreChanged = true;
        }
      }
      if (groupStoreChanged) {
        GroupMemberStore.instance.notifyChatAvatarRefresh();
      }
      if (changedIds.isNotEmpty) {
        PeerProfileRefreshBus.instance.notifyMany(changedIds);
      }
    }
  }

  /// 显式写入备注，空字符串表示清空（不会回退到旧备注）。
  Future<void> saveFriendRemark({
    required String userId,
    required String remark,
  }) async {
    final id = userId.trim();
    if (id.isEmpty) {
      return;
    }
    final existing = await read(id);
    final next = (existing ?? UserProfileRecord(userId: id)).copyWith(
      friendRemark: remark.trim(),
      updatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    await _saveAndPublish(next, writesFriendRemark: true);
  }

  Future<V2TimFriendInfo?> mergePreferLocal(
    String userId,
    V2TimFriendInfo? remote,
  ) async {
    final localRecord = await read(userId);
    if (localRecord == null) {
      if (remote != null) {
        await saveFriendInfo(remote);
      }
      return remote;
    }
    final local = localRecord.toV2TimFriendInfo();
    if (remote == null) {
      return local;
    }
    final merged = localRecord.mergeSdkRemotePreferLocal(remote);
    await _saveAndPublish(merged);
    return merged.toV2TimFriendInfo();
  }

  Future<void> hydrateFromFriendLocalStore() async {
    final friends = await FriendLocalStore.instance.readAll();
    await saveFriendRecords(friends);
  }

  UserProfileRecord _mergeFriendRecord(
    UserProfileRecord existing,
    MeFriendRecord record,
  ) {
    return existing.copyWith(
      nickname: record.friendNickname.trim().isNotEmpty
          ? record.friendNickname.trim()
          : existing.nickname,
      avatarUrl: record.friendAvatarUrl.trim().isNotEmpty
          ? record.friendAvatarUrl.trim()
          : existing.avatarUrl,
      avatarVersion:
          record.friendAvatarVersion != null && record.friendAvatarVersion! > 0
              ? record.friendAvatarVersion!
              : existing.avatarVersion,
      friendRemark:
          record.remarkKnown ? record.remark.trim() : existing.friendRemark,
      friendRemarkConfirmed:
          record.remarkKnown || existing.friendRemarkConfirmed,
      updatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
  }

  /// 温启动备注预热：从本地好友记录批量灌内存镜像 + DisplayNameStore。
  ///
  /// 只写内存与 Store（setC2C notify:false），不落库、不发逐条
  /// PeerProfileRefreshBus——批量方负责最后一次性 notifyBatch，避免冷启动
  /// 逐条 setState 风暴。已确认的备注（含主动清空）不被旧快照覆盖；
  /// 仅有公开资料的缓存仍需补齐好友备注。与 [FriendWarmupRemarkGate]
  /// 同一可信度：不覆盖首屏 IM/会话 displayedIm；Store 缓存无同等保护。
  void hydrateFromFriendRecords(
    List<MeFriendRecord> records, {
    Map<String, String>? conversationShowNames,
  }) {
    for (final record in records) {
      final id = record.friendUserId.trim();
      if (id.isEmpty) {
        continue;
      }
      final rawId = ChatIdFormat.rawUserUid(id);
      if (!FriendWarmupRemarkGate.shouldApplyLocalRemark(
        record,
        conversationShowName:
            conversationShowNames?[rawId] ?? conversationShowNames?[id],
      )) {
        continue;
      }
      final existing = _memory[id];
      if (existing?.friendRemarkConfirmed == true) {
        continue;
      }
      final remark = record.remark.trim();
      final nickname = record.friendNickname.trim();
      final avatar = record.friendAvatarUrl.trim();
      final next = (existing ?? UserProfileRecord(userId: id)).copyWith(
        nickname: existing?.nickname.trim().isNotEmpty == true
            ? existing!.nickname
            : nickname,
        avatarUrl: existing?.avatarUrl.trim().isNotEmpty == true
            ? existing!.avatarUrl
            : avatar,
        avatarVersion: (existing?.avatarVersion ?? 0) > 0
            ? existing!.avatarVersion
            : (record.friendAvatarVersion ?? 0),
        friendRemark: remark,
        friendRemarkConfirmed: true,
        updatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
      );
      _memory[id] = next;
      final displayName = remark.isNotEmpty
          ? remark
          : (next.nickname.isNotEmpty ? next.nickname : id);
      DisplayNameStore.instance.setC2C(id, displayName, notify: false);
    }
  }

  Future<void> clearSession() {
    _memory.clear();
    _friendInfoInFlight.clear();
    return _store.clearSession();
  }
}
