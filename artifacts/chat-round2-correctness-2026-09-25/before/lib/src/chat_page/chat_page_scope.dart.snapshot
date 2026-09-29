import 'package:flutter/foundation.dart';

/// 聊天页页面级生命周期。账号级 MessageCore / 持久化 / 会话摘要不在这里停。
class ChatPageScopeToken {
  const ChatPageScopeToken({
    required this.generation,
    required this.conversationId,
    required this.accountGeneration,
  });

  final int generation;
  final String conversationId;
  final int accountGeneration;

  bool matches({
    required String conversationId,
    required int accountGeneration,
  }) {
    return this.conversationId == conversationId.trim() &&
        (this.accountGeneration == 0 ||
            accountGeneration == 0 ||
            this.accountGeneration == accountGeneration);
  }
}

/// 当前前台 ChatPage 的单一页面代。
///
/// 退出聊天后 invalidate，迟到异步不得再 projection / setState / 挂图片任务。
class ChatPageScope {
  ChatPageScope._();

  static final ChatPageScope instance = ChatPageScope._();

  ChatPageScopeToken? _active;
  int _generation = 0;
  int _activeCount = 0;
  int _disposeCount = 0;
  int _prefetchCancelCount = 0;
  int _mountedMessageCount = 0;
  int _mountedMediaCount = 0;

  ChatPageScopeToken? get active => _active;
  int get generation => _generation;
  int get activeCount => _activeCount;
  int get disposeCount => _disposeCount;
  int get prefetchCancelCount => _prefetchCancelCount;
  int get mountedMessageCount => _mountedMessageCount;
  int get mountedMediaCount => _mountedMediaCount;
  bool get hasActivePage => _active != null;

  @visibleForTesting
  void resetForTest() {
    _active = null;
    _generation = 0;
    _activeCount = 0;
    _disposeCount = 0;
    _prefetchCancelCount = 0;
    _mountedMessageCount = 0;
    _mountedMediaCount = 0;
  }

  ChatPageScopeToken attach({
    required String conversationId,
    int accountGeneration = 0,
  }) {
    final id = conversationId.trim();
    final current = _active;
    if (current != null &&
        current.conversationId == id &&
        (accountGeneration == 0 ||
            current.accountGeneration == accountGeneration)) {
      return current;
    }
    _generation++;
    final token = ChatPageScopeToken(
      generation: _generation,
      conversationId: id,
      accountGeneration: accountGeneration,
    );
    _active = token;
    _activeCount = 1;
    return token;
  }

  void invalidate(ChatPageScopeToken? token) {
    if (token == null) return;
    if (_active == null) return;
    if (_active!.generation != token.generation) return;
    _active = null;
    _activeCount = 0;
    _disposeCount++;
    _mountedMessageCount = 0;
    _mountedMediaCount = 0;
  }

  bool isCurrent(ChatPageScopeToken? token) {
    if (token == null || _active == null) return false;
    return identical(_active, token) ||
        (_active!.generation == token.generation &&
            _active!.conversationId == token.conversationId);
  }

  bool allowsProjection({
    ChatPageScopeToken? token,
    String? conversationId,
    int accountGeneration = 0,
  }) {
    final active = _active;
    if (active == null) return false;
    if (token != null && !isCurrent(token)) return false;
    final id = conversationId?.trim() ?? '';
    if (id.isNotEmpty && active.conversationId != id) return false;
    if (accountGeneration != 0 &&
        active.accountGeneration != 0 &&
        active.accountGeneration != accountGeneration) {
      return false;
    }
    return true;
  }

  void notePrefetchCancel() {
    _prefetchCancelCount++;
  }

  void noteMountedWindow({
    required String conversationId,
    required int messageCount,
    int mediaCount = 0,
  }) {
    if (!allowsProjection(conversationId: conversationId)) return;
    _mountedMessageCount = messageCount;
    _mountedMediaCount = mediaCount;
  }
}
