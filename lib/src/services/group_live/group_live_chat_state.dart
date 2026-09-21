import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_live_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_live/group_live_index_store.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/group_live_message.dart';

/// In-memory snapshot of `/live/current` for one open group chat.
class GroupLiveChatState extends ChangeNotifier {
  GroupLiveCurrentSnapshot? snapshot;
  bool loading = false;
  Future<void>? _refreshInFlight;
  String _groupId = '';
  String _etag = '';
  int _revision = 0;
  bool _disposed = false;

  Object _visibleState() {
    final s = activeSession;
    return (
      s?.liveSessionId,
      s?.groupId,
      s?.roomName,
      s?.description,
      s?.anchorUserId,
      s?.status,
      s?.scheduledStartAt,
      s?.expireAt,
      s?.startedAt,
      s?.endedAt,
      s?.endReason
    );
  }

  void _invalidateRequest() {
    _revision++;
    _refreshInFlight = null;
    loading = false;
  }

  GroupLiveSession? get activeSession =>
      snapshot?.active == true ? snapshot?.session : null;

  bool get hasActiveSlot {
    final session = activeSession;
    return session != null && session.status.isActiveSlot;
  }

  /// 用会话列表已缓存的 live-index 立刻填横幅，避免进群后再闪一下。
  void seedFromIndex(String groupId, {bool notify = false}) {
    _invalidateRequest();
    _groupId = groupId.trim();
    _etag = '';
    final id = groupId.trim();
    if (id.isEmpty) {
      if (snapshot != null) {
        snapshot = null;
        loading = false;
        if (notify) notifyListeners();
      }
      return;
    }
    final item = GroupLiveIndexStore.instance.itemForGroup(id);
    if (item != null && item.status.isActiveSlot) {
      snapshot = GroupLiveCurrentSnapshot.active(item.toSession());
    } else {
      snapshot = null;
    }
    loading = false;
    if (notify) notifyListeners();
  }

  Future<void> refresh(String groupId) {
    final id = groupId.trim();
    if (id.isEmpty || _disposed) return Future.value();
    if (_groupId == id && _refreshInFlight != null) return _refreshInFlight!;
    _groupId = id;
    final revision = ++_revision;
    final future = _refresh(id, revision);
    _refreshInFlight = future;
    return future;
  }

  Future<void> _refresh(String id, int revision) async {
    loading = true;
    try {
      final next = await GroupLiveApi.instance.current(
        groupId: id,
        ifNoneMatch: _etag.isEmpty ? null : _etag,
      );
      if (_disposed || revision != _revision) return;
      if (next.notModified) {
        if (next.etag.isNotEmpty) {
          _etag = next.etag;
        }
        loading = false;
        return;
      }
      if (next.etag.isNotEmpty) {
        _etag = next.etag;
      }
      final before = _visibleState();
      final session = next.session;
      if (next.active && session != null && session.groupId.trim().isEmpty) {
        snapshot = GroupLiveCurrentSnapshot.active(
          GroupLiveSession(
            liveSessionId: session.liveSessionId,
            groupId: id,
            roomName: session.roomName,
            description: session.description,
            anchorUserId: session.anchorUserId,
            status: session.status,
            scheduledStartAt: session.scheduledStartAt,
            expireAt: session.expireAt,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            endReason: session.endReason,
          ),
          etag: next.etag,
        );
      } else {
        snapshot = next;
      }
      loading = false;
      if (_visibleState() != before) notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[GroupLive] current failed groupId=$id error=$e');
      }
    } finally {
      if (revision == _revision) {
        loading = false;
        _refreshInFlight = null;
      }
    }
  }

  void applyImPayload(GroupLiveImPayload payload) {
    _invalidateRequest();
    final session = activeSession;
    if (session == null && !payload.isCard) {
      return;
    }
    if (payload.businessId == GroupLiveMessageIds.ended) {
      snapshot = const GroupLiveCurrentSnapshot.inactive();
      notifyListeners();
      return;
    }
    if (payload.liveSessionId.isEmpty) {
      return;
    }
    final fromIm = payload.raw['description']?.toString().trim() ?? '';
    final merged = GroupLiveSession(
      liveSessionId: payload.liveSessionId,
      groupId: payload.groupId.isNotEmpty
          ? payload.groupId
          : (session?.groupId ?? ''),
      roomName: payload.roomName.isNotEmpty
          ? payload.roomName
          : (session?.roomName ?? ''),
      description: fromIm.isNotEmpty && fromIm != 'null'
          ? fromIm
          : (session?.description ?? ''),
      anchorUserId: payload.anchorUserId.isNotEmpty
          ? payload.anchorUserId
          : (session?.anchorUserId ?? ''),
      status: payload.status != GroupLiveStatus.unknown
          ? payload.status
          : (session?.status ?? GroupLiveStatus.unknown),
      scheduledStartAt: payload.scheduledStartAt ?? session?.scheduledStartAt,
      expireAt: session?.expireAt,
      startedAt: session?.startedAt,
      endReason: payload.endReason,
    );
    if (!merged.status.isActiveSlot &&
        payload.businessId != GroupLiveMessageIds.started) {
      snapshot = const GroupLiveCurrentSnapshot.inactive();
    } else {
      snapshot = GroupLiveCurrentSnapshot.active(merged);
    }
    notifyListeners();
  }

  void applyTcpDetail(
    Map<String, dynamic> detail, {
    required String groupId,
  }) {
    _invalidateRequest();
    final status = GroupLiveStatus.parse(detail['status']?.toString());
    if (!status.isActiveSlot) {
      snapshot = const GroupLiveCurrentSnapshot.inactive();
      notifyListeners();
      return;
    }
    final item = GroupLiveIndexItem.fromTcpDetail(
      detail,
      groupId: groupId,
    );
    if (item.liveSessionId.trim().isEmpty) {
      // 详情缺 id 时仍按 status 展示槽位；由聊天页随后 REST current 补全。
      if (kDebugMode) {
        // ignore: avoid_print
        print(
          '[GroupLive] applyTcpDetail missing liveSessionId '
          'groupId=$groupId status=$status',
        );
      }
    }
    snapshot = GroupLiveCurrentSnapshot.active(item.toSession());
    notifyListeners();
  }

  void clear() {
    _invalidateRequest();
    _groupId = '';
    _etag = '';
    snapshot = null;
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidateRequest();
    super.dispose();
  }
}
