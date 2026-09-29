import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_notice_api.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_change_event.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_feed_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/core_services_implements.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

/// 群系统通知（设/撤管理员、转让群主），REST + TCP 驱动。
class GroupSystemNoticeService extends ChangeNotifier {
  GroupSystemNoticeService._();

  static final GroupSystemNoticeService instance = GroupSystemNoticeService._();

  static const int _maxDismissedKeys = 500;
  static const int _maxProjectedNotices = 200;
  static const String _projectedPrefix = 'groupChangeEventNotices_v1_';

  List<GroupSystemNoticeItem> _notices = const [];
  bool _loading = false;
  static const int pageSize = 20;
  int _nextOffset = 0;
  int _pageGeneration = 0;
  bool _hasMore = true;
  bool _loadingMore = false;
  Object? _pageError;
  bool _needsFirstPage = true;

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _loadingMore;
  Object? get pageError => _pageError;

  Future<void> loadMore() async {
    if (_loading || _loadingMore) return;
    if (_needsFirstPage) return refresh();
    if (!_hasMore) return;
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) return;
    final clearGeneration = _sessionClearGeneration;
    final generation = _pageGeneration;
    _loadingMore = true;
    _pageError = null;
    notifyListeners();
    try {
      final page = await GroupNoticeApi.instance.fetchMyGroupNotices(
        limit: pageSize,
        offset: _nextOffset,
      );
      if (!_isCurrentRefresh(identity, clearGeneration) ||
          generation != _pageGeneration) {
        return;
      }
      _nextOffset += page.items.length;
      _hasMore = page.items.isNotEmpty && (page.total != null
          ? _nextOffset < page.total!
          : page.items.length == pageSize);
      final byId = <String, GroupSystemNoticeItem>{
        for (final item in _notices) item.id: item,
        for (final item in page.items.map((item) => item.toUIKitNotice()))
          item.id: item,
      };
      _notices = _filterDismissed(byId.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp)));
      _syncUnreadCount();
    } catch (error) {
      if (generation == _pageGeneration &&
          _isCurrentRefresh(identity, clearGeneration)) {
        _pageError = error;
      }
    } finally {
      if (generation == _pageGeneration &&
          _isCurrentRefresh(identity, clearGeneration)) {
        _loadingMore = false;
        notifyListeners();
      }
    }
  }
  int? _lastReadAtMs;
  int _unreadCount = 0;
  Set<String> _dismissedNoticeIds = <String>{};
  bool _dismissedNoticeIdsLoaded = false;
  String _dismissedNoticeOwner = '';
  List<GroupSystemNoticeItem> _projectedNotices = const [];
  String _projectedNoticeOwner = '';
  int _sessionClearGeneration = 0;

  List<GroupSystemNoticeItem> get notices =>
      List<GroupSystemNoticeItem>.unmodifiable(_notices);

  bool get isLoading => _loading;

  int? get lastReadAtMs => _lastReadAtMs;

  int get unreadCount => _unreadCount;

  Future<Set<String>> _loadDismissedNoticeIds({
    bool force = false,
    String? ownerUserId,
    SessionIdentity? identity,
    int? clearGeneration,
  }) async {
    final owner = ChatIdFormat.rawUserUid(
      ownerUserId ??
          serviceLocator<CoreServicesImpl>().loginUserInfo?.userID ??
          '',
    );
    if (_dismissedNoticeIdsLoaded && !force && _dismissedNoticeOwner == owner) {
      return _dismissedNoticeIds;
    }
    final prefs = await SharedPreferences.getInstance();
    if (identity != null &&
        !_isCurrentRefresh(
            identity, clearGeneration ?? _sessionClearGeneration)) {
      return _dismissedNoticeIds;
    }
    final stored =
        prefs.getStringList(_dismissedStorageKeyForOwner(owner)) ?? const [];
    _dismissedNoticeIds = stored
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    _dismissedNoticeIdsLoaded = true;
    _dismissedNoticeOwner = owner;
    return _dismissedNoticeIds;
  }

  String _dismissedStorageKeyForOwner(String owner) {
    if (owner.isEmpty) {
      return 'groupSystemNoticeDismissedIds';
    }
    return 'groupSystemNoticeDismissedIds_$owner';
  }

  Future<void> _saveDismissedNoticeIds(
    Set<String> ids, {
    required String ownerUserId,
    SessionIdentity? identity,
    int? clearGeneration,
  }) async {
    final owner = ChatIdFormat.rawUserUid(ownerUserId);
    if (owner.isEmpty ||
        (identity != null &&
            !_isCurrentRefresh(
              identity,
              clearGeneration ?? _sessionClearGeneration,
            ))) {
      return;
    }
    final normalized = ids
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(_maxDismissedKeys)
        .toList(growable: false);
    _dismissedNoticeIds = normalized.toSet();
    _dismissedNoticeIdsLoaded = true;
    _dismissedNoticeOwner = owner;
    final prefs = await SharedPreferences.getInstance();
    if (identity != null &&
        !_isCurrentRefresh(
            identity, clearGeneration ?? _sessionClearGeneration)) {
      return;
    }
    await prefs.setStringList(_dismissedStorageKeyForOwner(owner), normalized);
  }

  bool _isDismissed(String noticeId) {
    final id = noticeId.trim();
    return id.isNotEmpty && _dismissedNoticeIds.contains(id);
  }

  List<GroupSystemNoticeItem> _filterDismissed(
    List<GroupSystemNoticeItem> notices,
  ) {
    if (_dismissedNoticeIds.isEmpty) {
      return notices;
    }
    return notices
        .where((item) => !_isDismissed(item.id))
        .toList(growable: false);
  }

  void _syncUnreadCount() {
    final watermark = _lastReadAtMs ?? 0;
    _unreadCount = _notices.where((item) => item.timestamp > watermark).length;
  }

  Future<void> refresh({bool force = false}) async {
    if (_loading) {
      GroupNoticeFeedLog.log('service_refresh_skip', extras: {
        'force': force,
        'loading': _loading,
      });
      return;
    }
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) {
      return;
    }
    final clearGeneration = _sessionClearGeneration;
    _pageGeneration++;
    _needsFirstPage = true;
    _loadingMore = false;
    _pageError = null;
    GroupNoticeFeedLog.log('service_refresh_begin', extras: {
      'force': force,
      'beforeCount': _notices.length,
    });
    _loading = true;
    notifyListeners();
    try {
      await _loadDismissedNoticeIds(ownerUserId: identity.ownerUserId);
      if (!_isCurrentRefresh(identity, clearGeneration)) {
        return;
      }
      final projected = await _loadProjectedNotices(identity.ownerUserId);
      if (!_isCurrentRefresh(identity, clearGeneration)) {
        return;
      }
      final localById = <String, GroupSystemNoticeItem>{
        for (final item in _notices) item.id: item,
        for (final item in projected) item.id: item,
      };
      final localNext = _filterDismissed(localById.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp)));
      if (!_sameNotices(_notices, localNext)) {
        _notices = localNext;
        _syncUnreadCount();
        notifyListeners();
      }
      final page = await GroupNoticeApi.instance.fetchMyGroupNotices(
        limit: pageSize,
      );
      if (!_isCurrentRefresh(identity, clearGeneration)) {
        return;
      }
      final byId = <String, GroupSystemNoticeItem>{
        for (final item in projected) item.id: item,
        for (final item in page.items.map((item) => item.toUIKitNotice()))
          item.id: item,
      };
      final next = _filterDismissed(byId.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp)));
      final changed = !_sameNotices(_notices, next) ||
          _lastReadAtMs != page.lastReadAtMs ||
          _unreadCount != (page.unreadCount ?? _unreadCount);
      _notices = next;
      _nextOffset = page.items.length;
      _needsFirstPage = false;
      _hasMore = page.items.isNotEmpty && (page.total != null
          ? _nextOffset < page.total!
          : page.items.length == pageSize);
      _lastReadAtMs = page.lastReadAtMs;
      _syncUnreadCount();
      GroupNoticeFeedLog.log('service_refresh_done', extras: {
        'changed': changed,
        'count': _notices.length,
        'unread': _unreadCount,
        'lastReadAtMs': _lastReadAtMs,
      });
      if (changed) {
        notifyListeners();
      }
    } catch (error, stack) {
      if (_isCurrentRefresh(identity, clearGeneration)) _pageError = error;
      if (kDebugMode) {
        debugPrint('GroupSystemNoticeService.refresh failed: $error\n$stack');
      }
      GroupNoticeFeedLog.log('service_refresh_failed', extras: {
        'error': '$error',
      });
    } finally {
      if (_isCurrentRefresh(identity, clearGeneration)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrentRefresh(SessionIdentity identity, int clearGeneration) {
    return clearGeneration == _sessionClearGeneration &&
        SessionIdentityService.instance.isCurrent(identity);
  }

  void upsertFromDetail(Map<String, dynamic>? detail) {
    final record = GroupNoticeRecord.fromDetail(detail);
    if (record == null) {
      GroupNoticeFeedLog.log('service_upsert_detail_null', extras: {
        'detailKeys': detail?.keys.join(','),
      });
      return;
    }
    upsertNotice(record.toUIKitNotice());
  }

  Future<void> upsertChangeEvent(GroupChangeEvent event) async {
    final id = event.changeEventId.trim();
    final groupId = ChatIdFormat.canonicalGroupStorageId(event.groupId);
    final type = _noticeTypeForAction(event.action);
    final identity = SessionIdentityService.instance.capture();
    if (id.isEmpty ||
        groupId.isEmpty ||
        type == null ||
        identity.ownerUserId.isEmpty) {
      return;
    }

    final userIds = <String>{
      event.operatorUserId,
      ...event.memberUserIds,
    }.where((item) => item.trim().isNotEmpty).toList(growable: false);
    final members = await GroupMemberLocalStore.instance.readByUserIds(
      groupId: groupId,
      userIds: userIds,
    );
    if (!SessionIdentityService.instance.isCurrent(identity)) {
      return;
    }
    final names = <String, String>{
      for (final member in members)
        ChatIdFormat.rawUserUid(member.userID): _memberDisplayName(member),
    };
    final group = GroupLocalStore.instance.readCached(groupId: groupId);
    final targetIds = event.memberUserIds
        .map(ChatIdFormat.rawUserUid)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final targetNames = targetIds
        .map((userId) => names[userId]?.trim().isNotEmpty == true
            ? names[userId]!.trim()
            : userId)
        .toList(growable: false);
    final operatorId = ChatIdFormat.rawUserUid(event.operatorUserId);
    final timestamp = event.occurredAt > 0 && event.occurredAt < 1000000000000
        ? event.occurredAt * 1000
        : event.occurredAt;
    final notice = GroupSystemNoticeItem(
      id: id,
      groupID: groupId,
      groupName: group?.groupName.trim().isNotEmpty == true
          ? group!.groupName.trim()
          : groupId,
      groupFaceUrl: group?.avatarUrl.trim() ?? '',
      type: type,
      operatorUserID: operatorId,
      operatorName: names[operatorId]?.trim().isNotEmpty == true
          ? names[operatorId]!.trim()
          : operatorId,
      targetUserID: targetIds.join(','),
      targetName: targetNames.join('、'),
      timestamp: timestamp,
    );

    final projected = await _loadProjectedNotices(identity.ownerUserId);
    if (!SessionIdentityService.instance.isCurrent(identity)) {
      return;
    }
    _projectedNotices = <GroupSystemNoticeItem>[
      notice,
      ...projected.where((item) => item.id != id),
    ].take(_maxProjectedNotices).toList(growable: false);
    await _saveProjectedNotices(identity.ownerUserId, _projectedNotices);
    if (!SessionIdentityService.instance.isCurrent(identity)) {
      return;
    }
    upsertNotice(notice);
  }

  GroupSystemNoticeType? _noticeTypeForAction(String action) {
    switch (action.trim().toLowerCase()) {
      case 'member_added':
        return GroupSystemNoticeType.memberAdded;
      case 'member_removed':
        return GroupSystemNoticeType.memberRemoved;
      case 'member_left':
        return GroupSystemNoticeType.memberLeft;
      default:
        return null;
    }
  }

  String _memberDisplayName(dynamic member) {
    final nameCard = member.nameCard?.toString().trim() ?? '';
    if (nameCard.isNotEmpty) return nameCard;
    final friendRemark = member.friendRemark?.toString().trim() ?? '';
    if (friendRemark.isNotEmpty) return friendRemark;
    final nickname = member.nickName?.toString().trim() ?? '';
    if (nickname.isNotEmpty) return nickname;
    return ChatIdFormat.rawUserUid(member.userID?.toString() ?? '');
  }

  String _projectedStorageKey(String ownerUserId) =>
      '$_projectedPrefix${ChatIdFormat.rawUserUid(ownerUserId)}';

  Future<List<GroupSystemNoticeItem>> _loadProjectedNotices(
    String ownerUserId,
  ) async {
    final owner = ChatIdFormat.rawUserUid(ownerUserId);
    if (_projectedNoticeOwner == owner) {
      return _projectedNotices;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_projectedStorageKey(owner));
    final loaded = <GroupSystemNoticeItem>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded.whereType<Map>()) {
            final json = Map<String, dynamic>.from(item);
            final typeName = json['type']?.toString() ?? '';
            GroupSystemNoticeType? type;
            for (final value in GroupSystemNoticeType.values) {
              if (value.name == typeName) {
                type = value;
                break;
              }
            }
            if (type == null) {
              continue;
            }
            loaded.add(GroupSystemNoticeItem(
              id: json['id']?.toString() ?? '',
              groupID: json['groupID']?.toString() ?? '',
              groupName: json['groupName']?.toString() ?? '',
              groupFaceUrl: json['groupFaceUrl']?.toString() ?? '',
              type: type,
              operatorUserID: json['operatorUserID']?.toString() ?? '',
              operatorName: json['operatorName']?.toString() ?? '',
              targetUserID: json['targetUserID']?.toString() ?? '',
              targetName: json['targetName']?.toString() ?? '',
              timestamp: int.tryParse(json['timestamp']?.toString() ?? '') ?? 0,
            ));
          }
        }
      } catch (_) {}
    }
    _projectedNoticeOwner = owner;
    _projectedNotices = loaded
        .where((item) => item.id.isNotEmpty && item.groupID.isNotEmpty)
        .take(_maxProjectedNotices)
        .toList(growable: false);
    return _projectedNotices;
  }

  Future<void> _saveProjectedNotices(
    String ownerUserId,
    List<GroupSystemNoticeItem> notices,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _projectedStorageKey(ownerUserId),
      jsonEncode(notices
          .map((notice) => <String, dynamic>{
                'id': notice.id,
                'groupID': notice.groupID,
                'groupName': notice.groupName,
                'groupFaceUrl': notice.groupFaceUrl,
                'type': notice.type.name,
                'operatorUserID': notice.operatorUserID,
                'operatorName': notice.operatorName,
                'targetUserID': notice.targetUserID,
                'targetName': notice.targetName,
                'timestamp': notice.timestamp,
              })
          .toList(growable: false)),
    );
  }

  void upsertNotice(GroupSystemNoticeItem notice) {
    if (notice.id.isEmpty || notice.groupID.isEmpty) {
      GroupNoticeFeedLog.log('service_upsert_skip_empty', extras: {
        'id': notice.id,
        'groupID': notice.groupID,
      });
      return;
    }
    if (_isDismissed(notice.id)) {
      GroupNoticeFeedLog.log('service_upsert_skip_dismissed', extras: {
        'id': notice.id,
        'groupID': notice.groupID,
      });
      return;
    }
    final before = _notices.length;
    final next = List<GroupSystemNoticeItem>.from(_notices)
      ..removeWhere((item) => item.id == notice.id)
      ..insert(0, notice)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _notices = next;
    _syncUnreadCount();
    GroupNoticeFeedLog.log('service_upsert', extras: {
      'id': notice.id,
      'groupID': notice.groupID,
      'type': notice.type.index,
      'ts': notice.timestamp,
      'before': before,
      'after': _notices.length,
      'unread': _unreadCount,
    });
    notifyListeners();
  }

  /// 增量/TCP 软删：本地移除并记入 dismissed，不打 DELETE API。
  Future<void> removeNoticeById(
    String noticeId, {
    bool markDismissed = true,
  }) async {
    final id = noticeId.trim();
    if (id.isEmpty) {
      return;
    }
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) return;
    final clearGeneration = _sessionClearGeneration;
    if (markDismissed) {
      final dismissed = await _loadDismissedNoticeIds(
        ownerUserId: identity.ownerUserId,
        identity: identity,
        clearGeneration: clearGeneration,
      );
      if (!_isCurrentRefresh(identity, clearGeneration)) return;
      final nextDismissed = Set<String>.from(dismissed)..add(id);
      await _saveDismissedNoticeIds(
        nextDismissed,
        ownerUserId: identity.ownerUserId,
        identity: identity,
        clearGeneration: clearGeneration,
      );
    }
    if (!_isCurrentRefresh(identity, clearGeneration)) return;
    final before = _notices.length;
    _notices =
        _notices.where((item) => item.id.trim() != id).toList(growable: false);
    if (_notices.length != before || markDismissed) {
      _syncUnreadCount();
      notifyListeners();
    }
  }

  /// 远端已读水位（增量 `READ_WATERMARK`），不请求 PUT。
  void applyRemoteReadWatermark(int readAtMs) {
    if (readAtMs <= 0) {
      return;
    }
    final current = _lastReadAtMs ?? 0;
    if (readAtMs <= current) {
      return;
    }
    _lastReadAtMs = readAtMs;
    _syncUnreadCount();
    notifyListeners();
  }

  Future<void> markRead(int readAtMs) async {
    if (readAtMs <= 0) {
      return;
    }
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) return;
    final clearGeneration = _sessionClearGeneration;
    try {
      await GroupNoticeApi.instance.markGroupNoticesRead(readAt: readAtMs);
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('GroupSystemNoticeService.markRead failed: $error\n$stack');
      }
    }
    if (!_isCurrentRefresh(identity, clearGeneration)) return;
    _lastReadAtMs = readAtMs;
    _syncUnreadCount();
    notifyListeners();
  }

  Future<bool> clearAllNotices() async {
    if (_notices.isEmpty) {
      return true;
    }
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) return false;
    final clearGeneration = _sessionClearGeneration;
    final snapshot = List<GroupSystemNoticeItem>.from(_notices);
    try {
      try {
        await GroupNoticeApi.instance.deleteMyGroupNotices();
      } catch (error, stack) {
        if (kDebugMode) {
          debugPrint(
            'GroupSystemNoticeService.clearAllNotices api failed: $error\n$stack',
          );
        }
      }
      if (!_isCurrentRefresh(identity, clearGeneration)) return false;
      final dismissed = await _loadDismissedNoticeIds(
        ownerUserId: identity.ownerUserId,
        identity: identity,
        clearGeneration: clearGeneration,
      );
      if (!_isCurrentRefresh(identity, clearGeneration)) return false;
      final nextDismissed = Set<String>.from(dismissed)
        ..addAll(
          snapshot.map((item) => item.id.trim()).where((id) => id.isNotEmpty),
        );
      await _saveDismissedNoticeIds(
        nextDismissed,
        ownerUserId: identity.ownerUserId,
        identity: identity,
        clearGeneration: clearGeneration,
      );
      if (!_isCurrentRefresh(identity, clearGeneration)) return false;
      _notices = const [];
      _pageGeneration++;
      _loadingMore = false;
      _nextOffset = 0;
      _hasMore = false;
      _pageError = null;
      _syncUnreadCount();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteNotice(GroupSystemNoticeItem notice) async {
    final id = notice.id.trim();
    if (id.isEmpty) {
      _toastDeleteFailed();
      return false;
    }
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) return false;
    final clearGeneration = _sessionClearGeneration;
    try {
      try {
        await GroupNoticeApi.instance.deleteMyGroupNotice(id);
      } catch (error, stack) {
        if (kDebugMode) {
          debugPrint(
            'GroupSystemNoticeService.deleteNotice api failed: $error\n$stack',
          );
        }
      }
      if (!_isCurrentRefresh(identity, clearGeneration)) return false;
      final dismissed = await _loadDismissedNoticeIds(
        ownerUserId: identity.ownerUserId,
        identity: identity,
        clearGeneration: clearGeneration,
      );
      if (!_isCurrentRefresh(identity, clearGeneration)) return false;
      final nextDismissed = Set<String>.from(dismissed)..add(id);
      await _saveDismissedNoticeIds(
        nextDismissed,
        ownerUserId: identity.ownerUserId,
        identity: identity,
        clearGeneration: clearGeneration,
      );
      if (!_isCurrentRefresh(identity, clearGeneration)) return false;
      _notices = _notices
          .where((item) => item.id.trim() != id)
          .toList(growable: false);
      _syncUnreadCount();
      notifyListeners();
      _toastDeleteSuccess();
      unawaited(refresh());
      return true;
    } catch (_) {
      _toastDeleteFailed();
      return false;
    }
  }

  void _toastDeleteSuccess() {
    ToastUtils.toast(AppI18n.current.t(
      zhHans: '已删除',
      zhHant: '已刪除',
      en: 'Deleted',
      ja: '削除しました',
      ko: '삭제됨',
    ));
  }

  void _toastDeleteFailed() {
    ToastUtils.toast(AppI18n.current.t(
      zhHans: '删除失败，请稍后重试',
      zhHant: '刪除失敗，請稍後重試',
      en: 'Delete failed. Please try again.',
      ja: '削除に失敗しました。しばらくして再試行してください。',
      ko: '삭제에 실패했습니다. 잠시 후 다시 시도해 주세요.',
    ));
  }

  void clearSession() {
    _sessionClearGeneration++;
    _pageGeneration++;
    _nextOffset = 0;
    _needsFirstPage = true;
    _hasMore = true;
    _loadingMore = false;
    _pageError = null;
    _notices = const [];
    _loading = false;
    _lastReadAtMs = null;
    _unreadCount = 0;
    _dismissedNoticeIds = <String>{};
    _dismissedNoticeIdsLoaded = false;
    _dismissedNoticeOwner = '';
    _projectedNotices = const [];
    _projectedNoticeOwner = '';
    notifyListeners();
  }

  Future<void> clearForOwner(String? ownerUserId) async {
    final owner = ChatIdFormat.rawUserUid(ownerUserId);
    if (owner.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dismissedStorageKeyForOwner(owner));
    await prefs.remove(_projectedStorageKey(owner));
    final currentOwner = ChatIdFormat.rawUserUid(
      SessionIdentityService.instance.capture().ownerUserId,
    );
    if (currentOwner == owner) {
      clearSession();
    }
  }

  bool _sameNotices(
    List<GroupSystemNoticeItem> oldList,
    List<GroupSystemNoticeItem> nextList,
  ) {
    if (oldList.length != nextList.length) {
      return false;
    }
    for (var i = 0; i < oldList.length; i++) {
      final oldItem = oldList[i];
      final nextItem = nextList[i];
      if (oldItem.id != nextItem.id ||
          oldItem.groupID != nextItem.groupID ||
          oldItem.type != nextItem.type ||
          oldItem.timestamp != nextItem.timestamp ||
          oldItem.operatorName != nextItem.operatorName ||
          oldItem.targetName != nextItem.targetName) {
        return false;
      }
    }
    return true;
  }
}
