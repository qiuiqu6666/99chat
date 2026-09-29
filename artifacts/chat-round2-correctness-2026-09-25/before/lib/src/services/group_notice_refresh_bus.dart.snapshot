import 'package:flutter/foundation.dart';

class GroupNoticeRefreshEvent {
  const GroupNoticeRefreshEvent({
    required this.groupId,
    this.notification,
    this.pushTs,
  });

  final String groupId;
  final String? notification;
  final int? pushTs;
}

/// 群公告更新后通知当前聊天页重新弹出公告。
class GroupNoticeRefreshBus {
  GroupNoticeRefreshBus._();

  static final GroupNoticeRefreshBus instance = GroupNoticeRefreshBus._();

  final ValueNotifier<GroupNoticeRefreshEvent?> lastRefresh =
      ValueNotifier<GroupNoticeRefreshEvent?>(null);

  /// 宽屏侧栏群资料页是否打开；打开时不应在资料页弹出群公告。
  bool _sideProfilePanelOpen = false;

  /// 本机正在保存群公告时按 groupId 抑制聊天 overlay，不替代侧栏开关。
  final Set<String> _popupSuppressedGroupIds = <String>{};

  bool get isSideProfilePanelOpen => _sideProfilePanelOpen;

  void setSideProfilePanelOpen(bool open) {
    _sideProfilePanelOpen = open;
  }

  void suppressPopupFor(String groupId) {
    final id = groupId.trim();
    if (id.isEmpty) {
      return;
    }
    _popupSuppressedGroupIds.add(id);
  }

  bool shouldSuppressPopup(String groupId) {
    final id = groupId.trim();
    if (id.isEmpty) {
      return false;
    }
    return _popupSuppressedGroupIds.contains(id);
  }

  void clearPopupSuppress(String groupId) {
    final id = groupId.trim();
    if (id.isEmpty) {
      return;
    }
    _popupSuppressedGroupIds.remove(id);
  }

  void notifyRefresh(
    String groupId, {
    String? notification,
    int? pushTs,
  }) {
    final id = groupId.trim();
    if (id.isEmpty) {
      return;
    }
    lastRefresh.value = GroupNoticeRefreshEvent(
      groupId: id,
      notification:
          notification?.trim().isNotEmpty == true ? notification!.trim() : null,
      pushTs: pushTs ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
