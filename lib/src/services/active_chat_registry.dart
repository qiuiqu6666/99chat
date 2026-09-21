import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';

/// 当前前台聊天会话的单一真相源，供通知抑制、未读 bump、ExternalChatEntry 共用。
class ActiveChatRegistry {
  ActiveChatRegistry._();

  static final ActiveChatRegistry instance = ActiveChatRegistry._();

  String? _conversationId;
  ConvType? _conversationType;
  bool _routeVisible = false;
  bool _hasVisibleMessages = false;
  bool _lifecycleForeground = true;
  bool _listVisibleAlongsideChat = false;

  void enter(
    String conversationId, {
    bool routeVisible = true,
    ConvType? conversationType,
  }) {
    final id = conversationId.trim();
    if (id.isEmpty) {
      return;
    }
    _conversationId = id;
    _conversationType = conversationType;
    _routeVisible = routeVisible;
    _hasVisibleMessages = false;
    MessagePersistCoordinator.instance.setActiveChatConversationId(id);
  }

  void updateRouteVisible(bool visible) {
    _routeVisible = visible;
  }

  void updateHasVisibleMessages(bool hasMessages) {
    _hasVisibleMessages = hasMessages;
  }

  void setLifecycleForeground(bool foreground) {
    _lifecycleForeground = foreground;
  }

  void setListVisibleAlongsideChat(bool visible) {
    _listVisibleAlongsideChat = visible;
  }

  void leave(String? conversationId) {
    final id = conversationId?.trim() ?? '';
    if (id.isNotEmpty &&
        _conversationId != null &&
        _conversationId!.trim() != id &&
        !MessageConversationId.sameConversation(id, _conversationId!)) {
      return;
    }
    _conversationId = null;
    _conversationType = null;
    _routeVisible = false;
    _hasVisibleMessages = false;
    MessagePersistCoordinator.instance.setActiveChatConversationId(null);
  }

  void reset() {
    _conversationId = null;
    _conversationType = null;
    _routeVisible = false;
    _hasVisibleMessages = false;
    _lifecycleForeground = true;
    MessagePersistCoordinator.instance.setActiveChatConversationId(null);
  }

  bool isActiveChat(String? conversationId) {
    final id = conversationId?.trim() ?? '';
    final current = _conversationId?.trim() ?? '';
    if (id.isEmpty || current.isEmpty) {
      return false;
    }
    if (!MessageConversationId.sameConversation(id, current)) {
      return false;
    }
    return _routeVisible;
  }

  /// 聊天会话是否仍打开（仅比对 conversationId，不受 RouteVisibility 转场影响）。
  /// 用于未读合并：pop 动画期间 routeVisible 可能短暂为 false，但仍应抑制未读 bump。
  bool matchesOpenConversation(String? conversationId) {
    final id = conversationId?.trim() ?? '';
    final current = _conversationId?.trim() ?? '';
    if (id.isEmpty || current.isEmpty) {
      return false;
    }
    return MessageConversationId.sameConversation(id, current);
  }

  String? get activeConversationId {
    final id = _conversationId?.trim() ?? '';
    return id.isEmpty ? null : id;
  }

  /// 是否有打开中的聊天（含进资料页时 routeVisible=false）。
  /// 供列表 UI defer / upsert busy 判断；比 [isActiveChat] 更稳。
  bool get hasOpenChat {
    final id = _conversationId?.trim() ?? '';
    return id.isNotEmpty;
  }

  /// 会话列表是否与聊天同屏常驻（桌面分栏为 `true`；手机恒 `false`）。
  bool get listVisibleAlongsideChat => _listVisibleAlongsideChat;

  /// 列表更新是否可以延后：有聊天打开 **且** 列表不同屏。
  /// 桌面分栏下恒为 `false`——列表就在旁边，延后等于卡住不刷。
  bool get canDeferListUpdatesForOpenChat =>
      hasOpenChat && !_listVisibleAlongsideChat;

  ConvType? get activeConversationType => _conversationType;

  bool isActiveChatInForeground(String? conversationId) {
    return _lifecycleForeground && isActiveChat(conversationId);
  }

  bool get hasVisibleMessages => _hasVisibleMessages;
}
