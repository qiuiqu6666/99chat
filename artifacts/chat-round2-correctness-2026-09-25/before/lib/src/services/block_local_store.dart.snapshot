import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/api/block_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_request_notice_service.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';

/// 本机「我已拉黑」缓存。权威列表来自 `GET /me/blocks`，不含对方是否拉黑我。
class BlockLocalStore extends ChangeNotifier {
  BlockLocalStore._();

  static final BlockLocalStore instance = BlockLocalStore._();

  final Set<String> _ids = <String>{};
  bool _loaded = false;
  String? _scope;
  Future<void>? _inFlight;

  bool get loaded => _loaded;

  Set<String> get blockedIds => Set<String>.unmodifiable(_ids);

  String _norm(String userId) => ChatIdFormat.rawUserUid(userId);

  String _currentScope() {
    try {
      return ChatIdFormat.rawUserUid(
        TIMUIKitCore.getInstance().loginInfo.userID,
      );
    } catch (_) {
      return '';
    }
  }

  bool isBlocked(String userId) {
    final id = _norm(userId);
    return id.isNotEmpty && _ids.contains(id);
  }

  Future<void> ensureLoaded({bool force = false}) async {
    final scope = _currentScope();
    if (!force && _loaded && _scope == scope) {
      return;
    }
    await refresh();
  }

  Future<void> refresh() async {
    final pending = _inFlight;
    if (pending != null) {
      return pending;
    }
    final future = _doRefresh();
    _inFlight = future;
    try {
      await future;
    } finally {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    }
  }

  Future<void> _doRefresh() async {
    final scope = _currentScope();
    final items = await BlockApi.instance.fetchAll();
    _replaceIds(items.map((e) => e.userId), scope: scope);
  }

  void applyPage(
    Iterable<BlockListItem> items, {
    required bool replace,
  }) {
    if (replace) {
      _ids.clear();
    }
    for (final item in items) {
      final id = _norm(item.userId);
      if (id.isNotEmpty) {
        _ids.add(id);
      }
    }
    _loaded = true;
    _scope = _currentScope();
    notifyListeners();
  }

  Future<void> block(String userId) async {
    final id = _norm(userId);
    if (id.isEmpty) {
      return;
    }
    await BlockApi.instance.block(id);
    _ids.add(id);
    _loaded = true;
    _scope = _currentScope();
    notifyListeners();
    unawaited(FriendRequestNoticeService.instance.refreshPendingCount());
  }

  Future<void> unblock(String userId) async {
    final id = _norm(userId);
    if (id.isEmpty) {
      return;
    }
    await BlockApi.instance.unblock(id);
    _ids.remove(id);
    notifyListeners();
  }

  void clearSession() {
    _ids.clear();
    _loaded = false;
    _scope = null;
    notifyListeners();
  }

  void _replaceIds(Iterable<String> userIds, {required String scope}) {
    _ids
      ..clear()
      ..addAll(
        userIds.map(_norm).where((id) => id.isNotEmpty),
      );
    _loaded = true;
    _scope = scope;
    notifyListeners();
  }
}
