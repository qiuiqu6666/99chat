import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_latest_window_reset_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_collection.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_readiness.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_peek_service.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_history_sync.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

/// 消息 Tab 可见会话的轻量首屏缓存。只读 Memory / 本地库，不碰云、不修洞。
class OpenViewportCache {
  OpenViewportCache._();

  static final OpenViewportCache instance = OpenViewportCache._();

  static const int maxVisible = 8;
  static const int minVisible = 5;
  static const int maxMessagesPerConversation = 30;

  final LinkedHashMap<String, ChatOpenViewportResult> _entries =
      LinkedHashMap<String, ChatOpenViewportResult>();

  /// Recovery epoch each entry was prepared under. An entry from an earlier
  /// epoch predates a real reconnect and can no longer skip a latest-window
  /// repair.
  final Map<String, int> _epochByKey = <String, int>{};
  bool _paused = false;
  int _generation = 0;

  /// Tests inject the recovery epoch; production reads the connect service.
  @visibleForTesting
  static int Function()? debugRecoveryEpochProvider;

  static int get _currentEpoch =>
      (debugRecoveryEpochProvider ?? (() => ImConnectStatusService.recoveryEpoch))();

  ChatOpenViewportResult? peek(String conversationKey) {
    final key = conversationKey.trim();
    if (key.isEmpty) {
      return null;
    }
    final hit = _entries.remove(key);
    if (hit == null) {
      _epochByKey.remove(key);
      return null;
    }
    final epoch = _epochByKey[key];
    final currentEpoch = _currentEpoch;
    if (epoch != null && epoch != currentEpoch) {
      _epochByKey.remove(key);
      ChatOpenPerfLog.mark(
        'open_viewport_cache_stale_epoch',
        conversationID: key,
        extras: <String, Object?>{
          'entryEpoch': epoch,
          'currentEpoch': currentEpoch,
        },
      );
      return null;
    }
    _entries[key] = hit;
    return hit;
  }

  void put(String conversationKey, ChatOpenViewportResult result) {
    final key = conversationKey.trim();
    if (key.isEmpty) {
      return;
    }
    _entries.remove(key);
    _entries[key] = result;
    _epochByKey[key] = _currentEpoch;
    while (_entries.length > maxVisible) {
      final evicted = _entries.keys.first;
      _entries.remove(evicted);
      _epochByKey.remove(evicted);
    }
  }

  void invalidate(String conversationKey) {
    final key = conversationKey.trim();
    _entries.remove(key);
    _epochByKey.remove(key);
  }

  void pause({String reason = 'feed_scroll'}) {
    _paused = true;
    _generation++;
  }

  void resume() {
    _paused = false;
    _generation++;
  }

  void resetForTest() {
    _entries.clear();
    _epochByKey.clear();
    _paused = false;
    _generation = 0;
  }

  bool get isPaused => _paused;

  /// 停稳后准备当前可见 5～8 个会话。禁止拉云、改 coverage、下载媒体。
  Future<void> prepareVisible({
    required List<V2TimConversation> visible,
    double viewportHeight = 560,
    String reason = 'home_idle',
  }) async {
    if (_paused || visible.isEmpty) {
      return;
    }
    final generation = ++_generation;
    final candidates = visible.take(maxVisible).toList(growable: false);
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    for (final conversation in candidates) {
      if (_paused || generation != _generation) {
        return;
      }
      final key =
          ConversationPreviewHistorySync.conversationMessageCacheKey(
                conversation,
              ) ??
              conversation.conversationID.trim();
      if (key.isEmpty) {
        continue;
      }
      // A conversation awaiting a latest-window reset must not receive a
      // pre-reconnect local page into memory; that page is the stale window
      // the reset exists to replace.
      if (ChatLatestWindowResetService.instance.needsLatestWindowReset(key)) {
        invalidate(key);
        continue;
      }
      final cached = peek(key);
      if (cached != null && cached.isViewportReady) {
        continue;
      }
      final memory = List<V2TimMessage>.from(
        globalModel.rawMessageList(key) ?? const <V2TimMessage>[],
      );
      var source = ChatViewportSource.memory;
      var messages = memory;
      if (messages.isEmpty && ConversationPeekService.canPeek(conversation)) {
        final local = await ConversationPeekService.loadLocalForChatEntry(
          conversation,
        );
        if (_paused || generation != _generation) {
          return;
        }
        final isGroupPeek = conversation.type == 2 ||
            (conversation.groupID?.trim().isNotEmpty ?? false);
        messages = ChatViewportReadiness.takeNewestContiguous(
          newestFirst: local.messages
              .take(maxMessagesPerConversation)
              .toList(growable: false),
          useSeqContiguity: isGroupPeek,
        );
        source = ChatViewportSource.local;
        if (messages.isNotEmpty &&
            (globalModel.rawMessageList(key)?.isEmpty ?? true)) {
          globalModel.setMessageList(
            key,
            ChatViewportCollection.instance.mergeIncoming(
              current: globalModel.rawMessageList(key) ?? const <V2TimMessage>[],
              incoming: messages,
              useSeqContiguity: isGroupPeek,
            ),
            historyCommitSource: 'open_viewport_cache_local',
          );
        }
      }
      final isGroup = conversation.type == 2 ||
          (conversation.groupID?.trim().isNotEmpty ?? false);
      final result = ChatViewportCollection.instance.project(
        conversationKey: key,
        newestFirst: messages,
        useSeqContiguity: isGroup,
        viewportHeight: viewportHeight,
        source: source,
      );
      put(key, result);
      ChatOpenPerfLog.mark(
        'open_viewport_cache_prepared',
        conversationID: key,
        extras: <String, Object?>{
          'reason': reason,
          'source': source.name,
          'count': result.continuousCount,
          'ready': result.isViewportReady,
        },
      );
    }
  }
}
