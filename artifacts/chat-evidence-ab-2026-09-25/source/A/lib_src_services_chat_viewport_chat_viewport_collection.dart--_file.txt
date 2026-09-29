import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_readiness.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_coverage.dart';

/// 当前聊天视口协调层：只持有投影与 merge 状态，不存第四份消息实体。
///
/// 消息体仍来自 [TUIChatGlobalModel.messageListMap] / HistoryWindowStore。
class ChatViewportCollection {
  ChatViewportCollection._();

  static final ChatViewportCollection instance = ChatViewportCollection._();

  String? _conversationKey;
  int _openGeneration = 0;
  SessionIdentity? _identity;
  ChatOpenViewportResult? _state;
  ChatOpenViewportResult? _initialState;
  ChatViewportRepairKind _repair = ChatViewportRepairKind.none;
  bool _uiAttached = false;
  final Set<String> _abandonedOpenGenerations = <String>{};

  String? get conversationKey => _conversationKey;
  int get openGeneration => _openGeneration;
  ChatOpenViewportResult? get state => _state;
  ChatOpenViewportResult? get initialState => _initialState;
  ChatViewportRepairKind get repair => _repair;
  bool get uiAttached => _uiAttached;

  int openGenerationFor(String conversationKey) {
    final key = conversationKey.trim();
    if (key.isEmpty || key != (_conversationKey ?? '')) {
      return 0;
    }
    return _openGeneration;
  }

  static String _abandonedKey(String conversationKey, int openGeneration) {
    return '$conversationKey#$openGeneration';
  }

  /// 该次 open generation 是否已因 detach 作废。未 attach / 未 detach 的 generation 不是 abandoned。
  bool isOpenGenerationAbandoned(
    String conversationKey,
    int openGeneration,
  ) {
    final key = conversationKey.trim();
    if (key.isEmpty) {
      return false;
    }
    return _abandonedOpenGenerations.contains(
      _abandonedKey(key, openGeneration),
    );
  }

  void attach({
    required String conversationKey,
    required SessionIdentity identity,
    String attachSource = '',
  }) {
    final key = conversationKey.trim();
    if (key.isEmpty) {
      return;
    }
    if (key == _conversationKey &&
        _identity == identity &&
        _uiAttached) {
      ChatOpenPerfLog.mark(
        'viewport_attach_skip',
        conversationID: key,
        extras: <String, Object?>{
          'openGeneration': _openGeneration,
          'attachSource': attachSource,
        },
      );
      return;
    }
    final previousGeneration = _openGeneration;
    _conversationKey = key;
    _identity = identity;
    _openGeneration += 1;
    _uiAttached = true;
    _repair = ChatViewportRepairKind.none;
    _initialState = null;
    ChatOpenPerfLog.mark(
      'viewport_attach_bump',
      conversationID: key,
      extras: <String, Object?>{
        'previousGeneration': previousGeneration,
        'openGeneration': _openGeneration,
        'attachSource': attachSource,
      },
    );
  }

  /// 取消页面等待，并作废该 openGeneration 的后续写窗。
  /// 已发出的 SDK 请求无法取消，但回调不得再提交到该 generation。
  void detachUi({required String conversationKey, required int openGeneration}) {
    final key = conversationKey.trim();
    if (key.isEmpty ||
        key != (_conversationKey ?? '') ||
        openGeneration != _openGeneration) {
      return;
    }
    _abandonedOpenGenerations.add(_abandonedKey(key, openGeneration));
    _uiAttached = false;
    _repair = ChatViewportRepairKind.none;
  }

  void resetForTest() {
    _conversationKey = null;
    _openGeneration = 0;
    _identity = null;
    _state = null;
    _initialState = null;
    _repair = ChatViewportRepairKind.none;
    _uiAttached = false;
    _abandonedOpenGenerations.clear();
  }

  /// 锁定本轮开页第一帧 snapshot。后续 H0/H2 只升级 [_state]，不改第一帧。
  void lockInitial(ChatOpenViewportResult result) {
    if (result.conversationKey != (_conversationKey ?? '')) {
      return;
    }
    _state = result;
    _initialState ??= result;
  }

  /// 当前消息窗是否已经包含第一帧 snapshot，而不是 lastMessage 半成品。
  bool matchesInitialWindow(List<V2TimMessage> newestFirst) {
    final initial = _initialState;
    if (initial == null || initial.conversationKey != (_conversationKey ?? '')) {
      return false;
    }
    if (initial.mountedMessageIds.isEmpty) {
      return true;
    }
    if (newestFirst.length < initial.continuousCount) {
      return false;
    }
    final ids = <String>{
      for (final message in newestFirst)
        ChatViewportReadiness.messageId(message),
    }..removeWhere((id) => id.isEmpty);
    for (final id in initial.mountedMessageIds) {
      if (id.isEmpty || !ids.contains(id)) {
        return false;
      }
    }
    return true;
  }

  bool acceptsTicket(ChatViewportRepairTicket ticket) {
    if (_identity == null) {
      return false;
    }
    return ticket.ownerUserId == _identity!.ownerUserId &&
        ticket.accountGeneration == _identity!.generation &&
        ticket.conversationKey == (_conversationKey ?? '') &&
        ticket.openGeneration == _openGeneration &&
        _uiAttached;
  }

  String ticketRejectedReason(ChatViewportRepairTicket ticket) {
    if (_identity == null) {
      return 'identityNull';
    }
    if (ticket.ownerUserId != _identity!.ownerUserId ||
        ticket.accountGeneration != _identity!.generation) {
      return 'accountMismatch';
    }
    if (ticket.conversationKey != (_conversationKey ?? '')) {
      return 'conversationMismatch';
    }
    if (ticket.openGeneration != _openGeneration) {
      return 'generationMismatch';
    }
    if (!_uiAttached) {
      return 'uiDetached';
    }
    return 'generationMismatch';
  }

  bool sameConversationCache(ChatViewportRepairTicket ticket) {
    return ticket.conversationKey == (_conversationKey ?? '') &&
        ticket.ownerUserId == (_identity?.ownerUserId ?? '') &&
        ticket.accountGeneration == (_identity?.generation ?? -1);
  }

  void markRepair(ChatViewportRepairKind kind) {
    _repair = kind;
  }

  ChatOpenViewportResult project({
    required String conversationKey,
    required List<V2TimMessage> newestFirst,
    required bool useSeqContiguity,
    required double viewportHeight,
    required ChatViewportSource source,
    MessageHistoryCoverage? coverage,
    bool reachedKnownLocalBoundary = false,
  }) {
    final result = ChatViewportReadiness.classify(
      conversationKey: conversationKey,
      newestFirst: newestFirst,
      useSeqContiguity: useSeqContiguity,
      viewportHeight: viewportHeight,
      source: source,
      coverage: coverage,
      reachedKnownLocalBoundary: reachedKnownLocalBoundary,
      openGeneration: conversationKey == _conversationKey ? _openGeneration : 0,
    );
    if (conversationKey == _conversationKey) {
      _state = result;
    }
    return result;
  }

  /// 所有输入都 merge。当前视口已比 incoming 新时只合并、不替换。
  List<V2TimMessage> mergeIncoming({
    required List<V2TimMessage> current,
    required List<V2TimMessage> incoming,
    required bool useSeqContiguity,
  }) {
    if (ChatViewportReadiness.incomingIsStaleAgainstCurrent(
      current: current,
      incoming: incoming,
      useSeqContiguity: useSeqContiguity,
    )) {
      return ChatViewportReadiness.mergePreserveRealtime(
        current: current,
        incoming: incoming,
      );
    }
    return ChatViewportReadiness.mergePreserveRealtime(
      current: current,
      incoming: incoming,
    );
  }
}
