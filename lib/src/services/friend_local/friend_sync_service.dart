import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/c2c_friend_message_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_warmup_remark_gate.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_reconcile_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime/friend_realtime_event.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/utils/friend_display_fields_merge.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_display_name.dart';
import 'package:tencent_cloud_chat_demo/utils/user_avatar.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_conversation_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_search_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

typedef FriendBecameFriendsCompletedHook = void Function(String reason);

enum ContactSyncPhase {
  idle,
  localLoading,
  localReady,
  snapshotLoading,
  incrementalLoading,
  ready,
  degradedRetrying,
}

class ContactSyncState {
  const ContactSyncState({
    this.phase = ContactSyncPhase.idle,
    this.ownerUserId = '',
    this.authoritativeSnapshotCommitted = false,
    this.contactCount = 0,
  });

  final ContactSyncPhase phase;
  final String ownerUserId;
  final bool authoritativeSnapshotCommitted;
  final int contactCount;

  bool get isLoading =>
      phase == ContactSyncPhase.idle ||
      phase == ContactSyncPhase.localLoading ||
      phase == ContactSyncPhase.localReady ||
      phase == ContactSyncPhase.snapshotLoading ||
      phase == ContactSyncPhase.incrementalLoading;

  bool get hasRetryableFailure => phase == ContactSyncPhase.degradedRetrying;
}

/// Display-only first page. It never establishes friendship authority and is
/// replaced by the complete, validated local snapshot.
class ContactSnapshotPreview {
  const ContactSnapshotPreview({this.owner = '', this.friends = const []});
  final String owner;
  final List<V2TimFriendInfo> friends;
}

/// TCP friend_list_changed / 成友事件写入 [FriendLocalStore]。好友本以 IM SDK 为准。
class FriendSyncService {
  FriendSyncService._();

  static final FriendSyncService instance = FriendSyncService._();

  static const String _snapshotCommittedPrefix =
      'friend_snapshot_committed_v1_';

  final ValueNotifier<ContactSyncState> syncState =
      ValueNotifier<ContactSyncState>(const ContactSyncState());
  final ValueNotifier<ContactSnapshotPreview> snapshotPreview =
      ValueNotifier<ContactSnapshotPreview>(const ContactSnapshotPreview());

  /// 本机成友收口后回调。
  FriendBecameFriendsCompletedHook? onBecameFriendsCompleted;

  int _syncGeneration = 0;

  @visibleForTesting
  String? debugOwnerUserId;

  /// 单测用：跳过 UIKit 刷新，只验证乐观入库。
  @visibleForTesting
  bool debugSkipBecameFriendsSideEffects = false;

  @visibleForTesting
  int debugRemarkDisplayPublishCount = 0;

  static const bool _logEnabled = kDebugMode;

  static void _log(String message) {
    if (!_logEnabled) return;
    debugPrint('FriendSync: $message');
  }

  String _ownerUserId() {
    final override = debugOwnerUserId?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return ChatIdFormat.rawUserUid(ContactSocialCacheStore.safeLoginUserId());
  }

  String _snapshotCommittedKey(String owner) =>
      '$_snapshotCommittedPrefix$owner';

  Future<bool> hasAuthoritativeSnapshot({String? ownerUserId}) async {
    final owner = (ownerUserId ?? _ownerUserId()).trim();
    if (owner.isEmpty) {
      return false;
    }
    final current = syncState.value;
    if (current.ownerUserId == owner &&
        current.authoritativeSnapshotCommitted) {
      return true;
    }
    final prefs = await SharedPreferences.getInstance();
    final committed = prefs.getBool(_snapshotCommittedKey(owner)) == true;
    if (committed && _ownerUserId() == owner) {
      final latest = syncState.value;
      if (latest.ownerUserId == owner &&
          !latest.authoritativeSnapshotCommitted) {
        _setSyncState(
          latest.phase,
          owner: owner,
          authoritativeSnapshotCommitted: true,
          contactCount: latest.contactCount,
        );
      }
    }
    return committed;
  }

  Future<void> restoreSyncStateForCurrentOwner() async {
    final owner = _ownerUserId();
    if (owner.isEmpty) {
      return;
    }
    final before = syncState.value;
    if (before.ownerUserId == owner && before.phase != ContactSyncPhase.idle) {
      return;
    }
    _setSyncState(
      ContactSyncPhase.localLoading,
      owner: owner,
      authoritativeSnapshotCommitted: false,
    );
    final local = await FriendLocalStore.instance.readAll(ownerUserId: owner);
    final authoritative = await hasAuthoritativeSnapshot(ownerUserId: owner);
    if (_ownerUserId() != owner) {
      return;
    }
    final current = syncState.value;
    if (current.ownerUserId == owner &&
        current.phase != ContactSyncPhase.localLoading) {
      return;
    }
    _setSyncState(
      authoritative ? ContactSyncPhase.ready : ContactSyncPhase.localReady,
      owner: owner,
      authoritativeSnapshotCommitted: authoritative,
      contactCount: local.length,
    );
  }

  void _setSyncState(
    ContactSyncPhase phase, {
    required String owner,
    required bool authoritativeSnapshotCommitted,
    int contactCount = 0,
  }) {
    final next = ContactSyncState(
      phase: phase,
      ownerUserId: owner,
      authoritativeSnapshotCommitted: authoritativeSnapshotCommitted,
      contactCount: contactCount,
    );
    final current = syncState.value;
    if (current.phase == next.phase &&
        current.ownerUserId == next.ownerUserId &&
        current.authoritativeSnapshotCommitted ==
            next.authoritativeSnapshotCommitted &&
        current.contactCount == next.contactCount) {
      return;
    }
    syncState.value = next;
  }

  /// 名单仍以 IM SNS 为准；本地库只补备注/昵称/头像，不灌 ViewModel。
  Future<bool> hydrateContactListFromLocal() async {
    await ImSdkRelationshipReconcileService.instance
        .overlayLocalFriendDisplay(reason: 'enter_contacts');
    return true;
  }

  Future<List<V2TimFriendInfo>> loadFriendsForUIKit() async {
    final owner = _ownerUserId();
    return FriendLocalStore.instance.loadAsV2TimFriends(
      ownerUserId: owner,
    );
  }

  /// 好友头像变更：补 C2C 会话列表 + 已缓存群成员 faceUrl（灌源后再由 bus 通知 UI）。
  void _publishPeerAvatarLocally(String userId, String faceUrl) {
    final id = ChatIdFormat.rawUserUid(userId);
    final nextAvatar = UserAvatarHelper.usableAvatarOrEmpty(faceUrl);
    if (id.isEmpty || nextAvatar.isEmpty) {
      return;
    }
    unawaited(
      ConversationSyncService.instance.applyConversationMetadataPatch(
        conversationID: 'c2c_$id',
        faceUrl: nextAvatar,
        remoteAuthority: true,
      ),
    );
    GroupMemberStore.instance.putFaceUrlForUser(id, nextAvatar, notify: true);
  }

  /// 用自建好友记录灌 [DisplayNameStore] + 会话列表展示名（备注优先）。
  ///
  /// 批量 `setC2C(notify:false)` + 一次列表刷新，避免 N 次 refresh 风暴。
  Future<void> seedC2cDisplayNamesFromFriendRecords(
    List<MeFriendRecord> records,
  ) async {
    if (records.isEmpty) {
      return;
    }
    final store = DisplayNameStore.instance;
    // Hydration also writes names, so capture their values before it runs.
    final previousNames = <String, String?>{
      for (final record in records)
        ChatIdFormat.rawUserUid(record.friendUserId):
            store.c2c(ChatIdFormat.rawUserUid(record.friendUserId)),
    };
    final conversationShowNames = <String, String>{};
    for (final record in records) {
      final id = ChatIdFormat.rawUserUid(record.friendUserId);
      if (id.isEmpty) {
        continue;
      }
      final fromConversation = _warmupConversationShowName(id);
      if (fromConversation != null && fromConversation.isNotEmpty) {
        conversationShowNames[id] = fromConversation;
      }
    }
    UserProfileLocalService.instance.hydrateFromFriendRecords(
      records,
      conversationShowNames: conversationShowNames,
    );
    final batch = <String, String>{};
    for (final record in records) {
      final id = ChatIdFormat.rawUserUid(record.friendUserId);
      if (id.isEmpty) {
        continue;
      }
      // Store.c2c is cache only; skip uses IM / authoritative conversation.
      if (!FriendWarmupRemarkGate.shouldApplyLocalRemark(
        record,
        conversationShowName: conversationShowNames[id],
      )) {
        continue;
      }
      final cached = UserProfileLocalService.instance.readCached(id);
      final remark = cached?.friendRemark.trim() ?? record.remark.trim();
      final nickname = cached?.nickname.trim() ?? record.friendNickname.trim();
      final showName = remark.isNotEmpty ? remark : nickname;
      if (showName.isEmpty ||
          DisplayNameStore.isRawUserIdDisplayName(id, showName)) {
        continue;
      }
      if (store.c2c(id) != showName) {
        store.setC2C(id, showName, notify: false);
      }
      batch['c2c_$id'] = showName;
      try {
        serviceLocator<TUIConversationViewModel>().updateC2CShowName(
          id,
          showName,
        );
      } catch (_) {}
    }
    if (batch.isNotEmpty) {
      ChatSessionController.instance.applyC2cShowNamesBatch(batch);
    }
    // An unchanged notification advances the UIKit friendship revision and
    // re-enters contact loading, which itself performs this warmup.
    if (previousNames.entries.any((entry) => store.c2c(entry.key) != entry.value)) {
      store.notifyBatch();
    }
  }

  String? _warmupConversationShowName(String userId) {
    try {
      final conversationId = 'c2c_$userId';
      for (final row in ChatSessionController.instance.conversations) {
        if (row.conversationID == conversationId) {
          final name = row.showName?.trim() ?? '';
          return name.isEmpty ? null : name;
        }
      }
    } catch (_) {}
    return null;
  }

  /// 从本地好友库重灌展示名（纠正 IM `loadContactListData` 空备注写成的昵称）。
  Future<void> reseedC2cDisplayNamesFromLocalFriends() async {
    final owner = _ownerUserId();
    if (owner.isEmpty) {
      return;
    }
    try {
      final records = await FriendLocalStore.instance.readAll(
        ownerUserId: owner,
      );
      await seedC2cDisplayNamesFromFriendRecords(records);
    } catch (e) {
      _log('reseedC2cDisplayNamesFromLocalFriends failed: $e');
    }
  }

  /// 温启动展示名预热：内存镜像 + DisplayNameStore + 会话行一次批量修正。
  ///
  /// seed 在首次异步让出前完成内存镜像与展示名更新，使 `resolveC2C`
  /// 与会话行使用同一份已确认资料。
  void applyC2cDisplayNameWarmup(List<MeFriendRecord> records) {
    if (records.isEmpty) {
      return;
    }
    unawaited(seedC2cDisplayNamesFromFriendRecords(records));
  }

  /// 从本地好友库预热 C2C 展示名（纯本地读，无网络）。
  ///
  /// 温启动场景：增量同步零事件、全量快照已提交时，备注批量灌名两个
  /// 既有入口都不会执行，会话列表在备注真源就绪前兜底成昵称。此方法
  /// 在首屏投影建立后调用，补上那次缺失的预热。失败仅记日志。
  Future<void> warmupC2cDisplayNamesFromLocalStore({
    List<String>? friendUserIds,
  }) async {
    final owner = _ownerUserId();
    final generation = _syncGeneration;
    final accountGeneration = SessionIdentityService.instance.generation;
    if (owner.isEmpty) {
      return;
    }
    try {
      final records = friendUserIds == null
          ? await FriendLocalStore.instance.readAll(ownerUserId: owner)
          : await FriendLocalStore.instance.readByIds(
              ownerUserId: owner,
              friendUserIds: friendUserIds,
            );
      if (!_isCurrentSync(owner, generation) ||
          !SessionIdentityService.instance
              .isGenerationCurrent(accountGeneration)) {
        return;
      }
      applyC2cDisplayNameWarmup(records);
    } catch (e) {
      _log('warmupC2cDisplayNamesFromLocalStore failed: $e');
    }
  }

  bool _isCurrentSync(String owner, int generation) {
    return generation == _syncGeneration && _ownerUserId() == owner;
  }

  String _resolvePeerUserId(FriendRealtimeEvent event) {
    final peer = ChatIdFormat.rawUserUid(event.peerUserId);
    if (peer.isNotEmpty) {
      return peer;
    }
    final self = _ownerUserId();
    final from = ChatIdFormat.rawUserUid(event.fromUserId);
    final to = ChatIdFormat.rawUserUid(event.toUserId);
    if (self.isNotEmpty) {
      if (from.isNotEmpty && from != self) {
        return from;
      }
      if (to.isNotEmpty && to != self) {
        return to;
      }
    }
    return from.isNotEmpty ? from : to;
  }

  Future<void> applyOptimisticAdd({
    required String friendUserId,
    String? friendNickname,
    String? friendAvatarUrl,
    String remark = '',
  }) async {
    final owner = _ownerUserId();
    final id = ChatIdFormat.rawUserUid(friendUserId);
    if (owner.isEmpty || id.isEmpty) {
      return;
    }
    final existingList = await FriendLocalStore.instance.readAll(
      ownerUserId: owner,
    );
    MeFriendRecord? existing;
    for (final item in existingList) {
      if (ChatIdFormat.rawUserUid(item.friendUserId) == id) {
        existing = item;
        break;
      }
    }
    final profile = await UserProfileLocalService.instance.read(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final shell = existing ??
        MeFriendRecord(
          friendUserId: id,
          remark: '',
          friendNickname: '',
          friendAvatarUrl: '',
          addedAt: now,
          peerDeletedMe: false,
          canMessage: true,
        );
    final incoming = shell.copyWith(
      friendNickname: friendNickname?.trim() ?? '',
      friendAvatarUrl: friendAvatarUrl?.trim() ?? '',
      remark: remark.trim(),
      canMessage: true,
      inMyFriendList: true,
      isFriend: true,
      addedAt: (existing?.addedAt ?? 0) == 0 ? now : existing?.addedAt,
    );
    final record = FriendDisplayFieldsMerge.merge(
      incoming: incoming,
      previous: existing,
      profile: profile,
    );
    await FriendLocalStore.instance.upsert(ownerUserId: owner, record: record);
    await UserProfileLocalService.instance.saveFriendRecord(record);
    await publishFriendRemarkDisplayName(
      friendUserId: id,
      remark: record.remark,
    );
    // 先 trust 再 notify：打开中的 Chat invalidate 后仍能靠 trust 解锁输入栏。
    C2cFriendMessageGuard.trustCanSendHint(
      id,
      source: C2cFriendMessageGuard.becameFriendsTrustSource,
    );
    PeerProfileRefreshBus.instance.notify(id);
    _syncGeneration++;
    _log('applyOptimisticAdd peer=$id');
  }

  /// 已成为好友统一收口：乐观入库 → 刷通讯录 → 通知。
  Future<void> onBecameFriends({
    required String peerUserId,
    String? nickname,
    String? avatarUrl,
    String remark = '',
    String reason = 'became_friends',
  }) async {
    final id = ChatIdFormat.rawUserUid(peerUserId);
    if (id.isEmpty) {
      return;
    }
    await applyOptimisticAdd(
      friendUserId: id,
      friendNickname: nickname,
      friendAvatarUrl: avatarUrl,
      remark: remark,
    );
    if (debugSkipBecameFriendsSideEffects) {
      return;
    }
    try {
      await upsertFriendLocallyFromStore(id);
    } catch (e) {
      _log('upsertFriendLocally failed: $e');
    }
    try {
      await ConversationSyncService.instance.ensureC2cConversationVisible(
        userId: id,
        nickname: nickname,
        avatarUrl: avatarUrl,
      );
    } catch (e) {
      _log('ensureC2cConversationVisible failed: $e');
    }
    await refreshUIKitLists(force: true);
    onBecameFriendsCompleted?.call(reason);
    PeerProfileRefreshBus.instance.notify(id);
    ConversationRefreshBus.instance.requestRefresh(
      reason: 'friend_list_changed',
      conversationId: 'c2c_$id',
      debounce: Duration.zero,
    );
  }

  Future<bool> applyListChanged(FriendRealtimeEvent event) async {
    final owner = _ownerUserId();
    if (owner.isEmpty) {
      return false;
    }
    final action = event.action?.trim().toLowerCase() ?? '';
    final peerUserId = _resolvePeerUserId(event);
    if (action.isEmpty || peerUserId.isEmpty) {
      return false;
    }

    final seq = event.seq;
    _log('applyListChanged action=$action peer=$peerUserId seq=$seq');

    var changed = false;
    switch (action) {
      case 'added':
        var addedRecord = MeFriendRecord.fromListChangedEvent(event);
        if (addedRecord.friendUserId.trim().isEmpty) {
          addedRecord = addedRecord.copyWith(friendUserId: peerUserId);
        }
        final existingAdded = await MeFriendApi.instance.cachedByUserId(
          peerUserId,
        );
        final profileAdded = await UserProfileLocalService.instance.read(
          peerUserId,
        );
        addedRecord = FriendDisplayFieldsMerge.merge(
          incoming: addedRecord,
          previous: existingAdded,
          profile: profileAdded,
        );
        await FriendLocalStore.instance.upsert(
          ownerUserId: owner,
          record: addedRecord,
        );
        await UserProfileLocalService.instance.saveFriendRecord(addedRecord);
        _seedPresenceFromFriendRecords([addedRecord]);
        if (addedRecord.remarkKnown) {
          await publishFriendRemarkDisplayName(
            friendUserId: peerUserId,
            remark: addedRecord.remark,
          );
        }
        _publishPeerAvatarLocally(peerUserId, addedRecord.friendAvatarUrl);
        PeerProfileRefreshBus.instance.notify(peerUserId);
        await upsertFriendLocallyFromStore(peerUserId);
        changed = true;
        break;
      case 'removed':
        await FriendLocalStore.instance.delete(
          ownerUserId: owner,
          friendUserId: peerUserId,
        );
        changed = true;
        break;
      case 'updated':
        await FriendLocalStore.instance.patch(
          ownerUserId: owner,
          friendUserId: peerUserId,
          transform: (current) => current.copyWith(
            peerDeletedMe: event.peerDeletedMe ?? current.peerDeletedMe,
            canMessage: event.canMessage ?? current.canMessage,
            isFriend: event.isFriend ?? current.isFriend,
            inMyFriendList: event.inMyFriendList ?? current.inMyFriendList,
            lastActiveAt: event.lastActiveAt ?? current.lastActiveAt,
            lastActiveVisibility:
                event.lastActiveVisibility ?? current.lastActiveVisibility,
          ),
        );
        final cached = await FriendLocalStore.instance.readByIds(
          ownerUserId: owner,
          friendUserIds: [peerUserId],
        );
        for (final item in cached) {
          if (item.friendUserId == peerUserId) {
            await UserProfileLocalService.instance.saveFriendRecord(item);
            _seedPresenceFromFriendRecords([item]);
            break;
          }
        }
        PeerProfileRefreshBus.instance.notify(peerUserId);
        ConversationRefreshBus.instance.requestRefresh(
          reason: 'friend_list_changed',
          conversationId: 'c2c_$peerUserId',
        );
        changed = true;
        break;
      case 'profile_updated':
        await FriendLocalStore.instance.patch(
          ownerUserId: owner,
          friendUserId: peerUserId,
          transform: (current) => current.copyWith(
            friendNickname: _firstNonEmpty(
              event.peerNickname,
              current.friendNickname,
            ),
            friendAvatarUrl: _firstNonEmpty(
              event.peerAvatarUrl,
              current.friendAvatarUrl,
            ),
            remark: event.remark,
          ),
        );
        final cached = await FriendLocalStore.instance.readByIds(
          ownerUserId: owner,
          friendUserIds: [peerUserId],
        );
        MeFriendRecord? updatedProfile;
        for (final item in cached) {
          if (item.friendUserId == peerUserId) {
            updatedProfile = item;
            await UserProfileLocalService.instance.saveFriendRecord(item);
            break;
          }
        }
        if (updatedProfile != null) {
          if (updatedProfile.remarkKnown) {
            await publishFriendRemarkDisplayName(
              friendUserId: peerUserId,
              remark: updatedProfile.remark,
            );
          }
          // 先灌会话/群成员活头像，再 bus，避免聊天页监听时仍读到旧快照。
          _publishPeerAvatarLocally(peerUserId, updatedProfile.friendAvatarUrl);
        }
        PeerProfileRefreshBus.instance.notify(peerUserId);
        changed = true;
        break;
      case 'remark_updated':
        final nextRemark = event.remark?.trim() ?? '';
        final beforeRows = await FriendLocalStore.instance.readByIds(
          friendUserIds: <String>[peerUserId],
          ownerUserId: owner,
        );
        final hadRow = beforeRows.isNotEmpty;
        final beforeRemark = hadRow ? beforeRows.first.remark : null;
        await FriendLocalStore.instance.patch(
          ownerUserId: owner,
          friendUserId: peerUserId,
          transform: (current) => current.copyWith(remark: nextRemark),
        );
        var remarkCached = await FriendLocalStore.instance.readByIds(
          friendUserIds: <String>[peerUserId],
          ownerUserId: owner,
        );
        if (remarkCached.isEmpty) {
          // 记录缺失时 patch 静默 return：用事件本身构造记录兜底落库，
          // 避免增量备注事件被静默丢弃（重启也不变）。
          var fallback = MeFriendRecord.fromListChangedEvent(event);
          if (fallback.friendUserId.trim().isEmpty) {
            fallback = fallback.copyWith(friendUserId: peerUserId);
          }
          final profile = await UserProfileLocalService.instance.read(
            peerUserId,
          );
          fallback = FriendDisplayFieldsMerge.merge(
            incoming: fallback.copyWith(remark: nextRemark),
            profile: profile,
          );
          await FriendLocalStore.instance.upsert(
            ownerUserId: owner,
            record: fallback,
          );
          remarkCached = await FriendLocalStore.instance.readByIds(
            friendUserIds: <String>[peerUserId],
            ownerUserId: owner,
          );
        }
        for (final item in remarkCached) {
          if (item.friendUserId == peerUserId) {
            await UserProfileLocalService.instance.saveFriendRecord(item);
            break;
          }
        }
        if (!hadRow || beforeRemark != nextRemark) {
          await publishFriendRemarkDisplayName(
            friendUserId: peerUserId,
            remark: nextRemark,
          );
        }
        changed = true;
        break;
      default:
        return false;
    }

    return changed;
  }

  /// 备注写入缺失兜底：本地库查不到该好友记录时，构造最小记录落库。
  ///
  /// 返回 `true` 表示新建了 shell 记录；`false` 表示记录已存在（调用方应走
  /// patch 路径，不得覆盖 patch 职责）。版本闸门保持不变：若该 id 有删除
  /// 墓碑（tombstone），upsert 的既有版本检查会拒绝写入，不复活已删好友。
  Future<bool> _upsertRemarkShellRecord({
    required String owner,
    required String friendUserId,
    required String remark,
  }) async {
    final id = ChatIdFormat.rawUserUid(friendUserId);
    if (owner.isEmpty || id.isEmpty) {
      return false;
    }
    // 探测与写入必须用同一显式 owner：cachedByUserId 走默认登录态 owner，
    // 与 _ownerUserId() 存在解析时机差，会造成误判缺失/误判存在。
    final existing = await FriendLocalStore.instance.readByIds(
      friendUserIds: <String>[id],
      ownerUserId: owner,
    );
    if (existing.isNotEmpty) {
      return false;
    }
    final profile = await UserProfileLocalService.instance.read(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final record = MeFriendRecord(
      friendUserId: id,
      remark: remark,
      friendNickname: profile?.nickname.trim() ?? '',
      friendAvatarUrl: profile?.avatarUrl.trim() ?? '',
      addedAt: now,
      peerDeletedMe: false,
      canMessage: true,
    );
    await FriendLocalStore.instance.upsert(ownerUserId: owner, record: record);
    _log('upsertRemarkShell peer=$id remark non-empty=${remark.isNotEmpty}');
    return true;
  }

  Future<void> applyOptimisticRemark({
    required String friendUserId,
    required String remark,
  }) async {
    final owner = _ownerUserId();
    final id = friendUserId.trim();
    if (owner.isEmpty || id.isEmpty) {
      return;
    }
    final nextRemark = remark.trim();
    final existing = await FriendLocalStore.instance.readByIds(
      friendUserIds: <String>[id],
      ownerUserId: owner,
    );
    if (existing.isEmpty) {
      // 记录缺失时 patch 会静默 return，remark 永不落库（重启也不变）。
      await _upsertRemarkShellRecord(
        owner: owner,
        friendUserId: id,
        remark: nextRemark,
      );
    } else {
      final updated = await FriendLocalStore.instance.updateRemark(
        ownerUserId: owner,
        friendUserId: id,
        remark: nextRemark,
      );
      if (!updated) {
        await FriendLocalStore.instance.patch(
          ownerUserId: owner,
          friendUserId: id,
          transform: (current) => current.copyWith(remark: nextRemark),
        );
      }
    }
    final cached = await FriendLocalStore.instance.readByIds(
      friendUserIds: <String>[id],
      ownerUserId: owner,
    );
    if (cached.isNotEmpty) {
      await UserProfileLocalService.instance.saveFriendRecord(cached.first);
    }
    // The remote update and local friend record are the save boundary. The
    // conversation database patch can wait; holding the editor open for it
    // makes the save control spin when a conversation coordinator is busy.
    unawaited(
      publishFriendRemarkDisplayName(friendUserId: id, remark: nextRemark),
    );
  }

  Future<void> publishProtocolFriendProjection({
    required MeFriendRecord after,
    required bool remarkChanged,
    required bool nicknameChanged,
    required bool avatarChanged,
  }) async {
    if (!remarkChanged && !nicknameChanged && !avatarChanged) {
      return;
    }
    await UserProfileLocalService.instance.saveFriendRecord(after);
    if (remarkChanged) {
      await publishFriendRemarkDisplayName(
        friendUserId: after.friendUserId,
        remark: after.remark,
      );
    }
    if (avatarChanged) {
      _publishPeerAvatarLocally(after.friendUserId, after.friendAvatarUrl);
    }
  }

  /// 备注/展示名变更后同步会话列表（含 hydrate 行指纹依赖的 showName）。
  Future<void> publishFriendRemarkDisplayName({
    required String friendUserId,
    required String remark,
  }) async {
    debugRemarkDisplayPublishCount++;
    final id = ChatIdFormat.rawUserUid(friendUserId);
    if (id.isEmpty) {
      return;
    }
    final text = remark.trim();
    TUIFriendShipViewModel? friendship;
    try {
      friendship = serviceLocator<TUIFriendShipViewModel>();
      friendship.updateFriendRemarkLocal(id, text);
    } catch (_) {
      friendship = null;
    }

    var showName = text;
    if (showName.isEmpty) {
      final friend = FriendDisplayName.findFriend(friendship?.friendList, id);
      final nickFromFriend = friend?.userProfile?.nickName?.trim() ?? '';
      if (nickFromFriend.isNotEmpty) {
        showName = nickFromFriend;
      } else {
        // 好友列表未加载时，从本地资料/好友缓存取昵称，避免短暂回退成 userID。
        final local = await UserProfileLocalService.instance.read(id);
        final localNick = local?.nickname.trim() ?? '';
        if (localNick.isNotEmpty) {
          showName = localNick;
        } else {
          final cachedFriend = await MeFriendApi.instance.cachedByUserId(id);
          final cachedNick = cachedFriend?.friendNickname.trim() ?? '';
          showName = cachedNick.isNotEmpty ? cachedNick : id;
        }
      }
    }

    DisplayNameStore.instance.setC2C(id, showName);
    try {
      serviceLocator<TUIConversationViewModel>().updateC2CShowName(
        id,
        showName,
      );
    } catch (_) {}

    final conversationId = 'c2c_$id';
    await _persistC2cShowName(
      conversationId: conversationId,
      userId: id,
      showName: showName,
    );
    PeerProfileRefreshBus.instance.notify(id);
  }

  Future<void> _persistC2cShowName({
    required String conversationId,
    required String userId,
    required String showName,
  }) async {
    final name = showName.trim();
    if (conversationId.isEmpty || name.isEmpty) {
      return;
    }
    V2TimConversation? match;
    for (final item in ChatSessionController.instance.conversations) {
      final cid = item.conversationID.trim();
      if (cid == conversationId ||
          ChatIdFormat.rawUserUid(item.userID) == userId) {
        match = item;
        break;
      }
    }
    if (match == null) {
      return;
    }
    try {
      await ConversationSyncService.instance.applyConversationMetadataPatch(
        conversationID: match.conversationID,
        showName: name,
        snapshot: match,
        explicitAuthority: true,
      );
    } catch (_) {}
  }

  Future<void> applyOptimisticDelete(String friendUserId) async {
    final owner = _ownerUserId();
    final id = ChatIdFormat.rawUserUid(friendUserId);
    if (owner.isEmpty || id.isEmpty) {
      return;
    }
    // 删好友行前把备注/昵称保留进资料库，供再加时自动恢复。
    final existing = await MeFriendApi.instance.cachedByUserId(id);
    if (existing != null) {
      await UserProfileLocalService.instance.saveFriendRecord(existing);
    }
    await FriendLocalStore.instance.delete(
      ownerUserId: owner,
      friendUserId: id,
      force: true,
    );
    C2cFriendMessageGuard.invalidate(id, clearTrusted: true);
    await refreshUIKitLists(force: true);
    try {
      serviceLocator<TUISearchViewModel>().invalidateGlobalSearchContext();
    } catch (_) {}
  }

  /// 名单以 IM SNS 为准，不再把自建库单条乐观写入 ViewModel。
  Future<void> upsertFriendLocallyFromStore(String peerUserId) async {}

  Future<void> refreshUIKitLists({bool force = false}) async {
    try {
      final friendship = serviceLocator<TUIFriendShipViewModel>();
      if (force) {
        await friendship.reloadContactListData();
      } else {
        await friendship.loadContactListData();
      }
      if ((friendship.friendList?.isNotEmpty ?? false)) {
        await friendship.loadUserStatus();
      }
      // IM 空备注会写成昵称；用自建库备注盖回 Store/列表。
      await reseedC2cDisplayNamesFromLocalFriends();
    } catch (e) {
      _log('refreshUIKitLists failed: $e');
    }
  }

  Future<void> handlePushFriendList(Map<String, dynamic> data) async {
    final event = FriendRealtimeEvent.fromJson(<String, dynamic>{
      ...data,
      'event': data['event'] ?? 'friend_list_changed',
      'type': 'event',
    });
    if (event.event != 'friend_list_changed') {
      return;
    }
    await applyListChanged(event);
    await refreshUIKitLists(force: true);
  }

  Future<void> clearSession({String? ownerUserId}) async {
    final owner = ChatIdFormat.rawUserUid(ownerUserId ?? _ownerUserId());
    _syncGeneration++;
    snapshotPreview.value = const ContactSnapshotPreview();
    if (owner.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_snapshotCommittedKey(owner));
    }
    syncState.value = const ContactSyncState();
    await FriendLocalStore.instance.clearSession();
    await UserProfileLocalService.instance.clearSession();
  }

  String _firstNonEmpty(String? primary, String fallback) {
    final value = primary?.trim() ?? '';
    if (value.isNotEmpty) {
      return value;
    }
    return fallback;
  }

  void _seedPresenceFromFriendRecords(List<MeFriendRecord> records) {
    final lastSeen = <String, int>{};
    final visibility = <String, String>{};
    for (final record in records) {
      final id = ChatIdFormat.rawUserUid(record.friendUserId);
      if (id.isEmpty) {
        continue;
      }
      final ts = record.lastActiveAt;
      if (ts != null) {
        lastSeen[id] = ts;
      }
      final vis = record.lastActiveVisibility?.trim() ?? '';
      if (vis.isNotEmpty) {
        visibility[id] = vis;
      }
    }
    PresenceProvider.activeInstance?.applyPresenceBatch(
      lastSeen: lastSeen.isEmpty ? null : lastSeen,
      lastActiveVisibility: visibility.isEmpty ? null : visibility,
    );
  }
}
