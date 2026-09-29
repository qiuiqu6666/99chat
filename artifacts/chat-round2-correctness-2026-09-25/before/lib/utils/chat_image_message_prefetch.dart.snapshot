import 'package:tencent_cloud_chat_uikit/ui/utils/background_media_gate.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/speculative_media_queue.dart';
import 'dart:async';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_cover_diag.dart';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_demo/src/chat_page/chat_page_scope.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_peek_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_thermal_perf.dart';
import 'package:tencent_cloud_chat_demo/src/services/message_media_metadata_store.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_history_sync.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/constants/history_message_constant.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_gallery_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_resolution_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_pagination_anchor.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_video_cover_provider.dart';

/// 聊天气泡缩略图 disk/memory cache key（与预览原图区分）。
String chatBubbleImageCacheKey(String? msgID, {String? url}) {
  return chatMediaBubbleImageCacheKey(msgID, urlFallback: url);
}

/// 进入聊天页前的首屏预取结果。
class ChatOpenPrefetchResult {
  const ChatOpenPrefetchResult({
    required this.messages,
    required this.hasMoreOlder,
  });

  final List<V2TimMessage> messages;
  final bool hasMoreOlder;
}

class _ThumbnailDownloadJob {
  _ThumbnailDownloadJob(this.key, V2TimMessage message)
      : messages = <V2TimMessage>[message];

  final String key;
  final List<V2TimMessage> messages;

  void attach(V2TimMessage message) {
    if (!messages.any((candidate) => identical(candidate, message))) {
      messages.add(message);
    }
  }
}

/// 历史消息加载后，预热首屏图片缩略图缓存。
class ChatImageMessagePrefetch {
  ChatImageMessagePrefetch._();

  static const _maxPrefetch = 10;
  static const _maxHistoricalPrefetch = 6;
  static const _maxInitialMediaMessages = 6;
  static const _maxUrlResolve = 16;
  static const _maxConcurrent = 3;
  static const _maxUrlResolveConcurrent = 8;
  static const _leaveEvictBatchSize = 8;
  static const _maxThumbnailDownloadConcurrent = 2;
  static const _maxThumbnailDownloadQueue = 24;
  static const _maxThumbnailDownloadsPerMinute = 12;

  /// Media is allowed to use a small, bounded part of the chat-open budget.
  /// URL lookup is intentionally shorter than image warming so a slow IM
  /// endpoint can never hold the history gate for the whole route transition.
  static const Duration initialMediaBudget = Duration(milliseconds: 220);
  static const Duration initialLocalMediaBudget = Duration(milliseconds: 24);
  static const Duration initialMediaUrlBudget = Duration(milliseconds: 140);

  /// 气泡预热位图软顶：超出则 evict 最旧 thumb（保留列表可见命中空间）。
  static const int maxWarmedBubbleProviders = 40;

  static final MessageService _messageService =
      serviceLocator<MessageService>();

  static final _warmQueue = SpeculativeMediaQueue(
    canStart: () => BackgroundMediaGate.instance.canStart,
    maxConcurrent: _maxConcurrent,
  );
  static Timer? _thumbnailResumeTimer;
  static ChatPageScopeToken? _pageScope;
  static bool _prefetchPaused = false;
  static int _prefetchInflight = 0;
  static final List<({String url, String cacheKey})> _warmedBubbleProviders =
      <({String url, String cacheKey})>[];

  static final Map<String, Future<ConversationPeekLoadResult>> _peekInFlight =
      <String, Future<ConversationPeekLoadResult>>{};
  static final Map<String, Future<V2TimMessage?>> _urlResolveInFlight =
      <String, Future<V2TimMessage?>>{};
  static final List<_ThumbnailDownloadJob> _thumbnailDownloadPending =
      <_ThumbnailDownloadJob>[];
  static final Map<String, _ThumbnailDownloadJob> _thumbnailDownloadJobs =
      <String, _ThumbnailDownloadJob>{};
  static int _thumbnailDownloadInFlight = 0;
  static final List<int> _thumbnailDownloadStartsMs = <int>[];

  static int get prefetchInflight =>
      _prefetchInflight + _thumbnailDownloadInFlight;

  static void bindPageScope(ChatPageScopeToken? token) {
    _pageScope = token;
    _prefetchPaused = false;
  }

  static bool get _pageAllowsDecode {
    if (_pageScope == null) return true;
    return ChatPageScope.instance.isCurrent(_pageScope);
  }

  static void setPrefetchPaused(bool paused) {
    _prefetchPaused = paused;
    _warmQueue.setPaused(paused);
    if (!paused) {
      _pumpThumbnailDownloads();
    }
  }

  /// 退出聊天页：取消尚未开始的预取，并作废本页 decode 任务。
  static void cancelForPageDispose() {
    cancelPending();
    for (final job in _thumbnailDownloadPending) {
      _thumbnailDownloadJobs.remove(job.key);
    }
    _thumbnailDownloadPending.clear();
    _pageScope = null;
    _prefetchPaused = false;
    ChatPageScope.instance.notePrefetchCancel();
  }

  /// C2C inbound thumbnails are persisted while the app is foregrounded.
  /// This queue downloads compressed THUMB files only; it never decodes them.
  static void prefetchThumbnailForMessage(V2TimMessage message) {
    if (kIsWeb || !_isForeground || _prefetchPaused) {
      return;
    }
    if (message.elemType != MessageElemType.V2TIM_ELEM_TYPE_IMAGE &&
        message.imageElem == null) {
      return;
    }
    if (HistoryPaginationAnchor.isArchiveHistoryMessage(message)) {
      return;
    }
    final msgID = message.msgID?.trim() ?? '';
    if (msgID.isEmpty) {
      return;
    }
    if (_resolveLocalBubblePath(message) != null) {
      ChatThermalPerf.increment('thumb_download_skipped_local');
      return;
    }
    final existing = _thumbnailDownloadJobs[msgID];
    if (existing != null) {
      existing.attach(message);
      return;
    }
    if (_thumbnailDownloadPending.length >= _maxThumbnailDownloadQueue) {
      ChatThermalPerf.increment('thumb_download_skipped_queue_full');
      return;
    }
    final job = _ThumbnailDownloadJob(msgID, message);
    _thumbnailDownloadJobs[msgID] = job;
    _thumbnailDownloadPending.add(job);
    _pumpThumbnailDownloads();
  }

  static void handleAppLifecycleState(AppLifecycleState state) {
    _warmQueue.setPaused(state != AppLifecycleState.resumed);
    _thumbnailResumeTimer?.cancel();
    _thumbnailResumeTimer = null;
    if (state == AppLifecycleState.resumed) {
      _pumpThumbnailDownloads();
      return;
    }
    for (final job in _thumbnailDownloadPending) {
      _thumbnailDownloadJobs.remove(job.key);
    }
    _thumbnailDownloadPending.clear();
  }

  static bool get _isForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  static void _pumpThumbnailDownloads() {
    BackgroundMediaGate.instance.observeMetrics();
    if (!_isForeground || _prefetchPaused) {
      return;
    }
    if (_thumbnailDownloadPending.isNotEmpty &&
        !BackgroundMediaGate.instance.canStart) {
      _thumbnailResumeTimer ??= Timer(const Duration(milliseconds: 100), () {
        _thumbnailResumeTimer = null;
        _pumpThumbnailDownloads();
      });
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _thumbnailDownloadStartsMs.removeWhere(
      (startedMs) => nowMs < startedMs || nowMs - startedMs >= 60000,
    );
    if (_thumbnailDownloadStartsMs.length >= _maxThumbnailDownloadsPerMinute) {
      for (final job in _thumbnailDownloadPending) {
        _thumbnailDownloadJobs.remove(job.key);
      }
      _thumbnailDownloadPending.clear();
      return;
    }
    while (_thumbnailDownloadInFlight < _maxThumbnailDownloadConcurrent &&
        _thumbnailDownloadPending.isNotEmpty &&
        _thumbnailDownloadStartsMs.length < _maxThumbnailDownloadsPerMinute) {
      final job = _thumbnailDownloadPending.removeAt(0);
      _thumbnailDownloadInFlight++;
      _thumbnailDownloadStartsMs.add(nowMs);
      ChatThermalPerf.increment('thumb_download_started');
      ChatThermalPerf.record(
        'thumb_download_inflight',
        _thumbnailDownloadInFlight,
      );
      unawaited(
        _runThumbnailDownload(job).whenComplete(() {
          _thumbnailDownloadInFlight--;
          _thumbnailDownloadJobs.remove(job.key);
          _pumpThumbnailDownloads();
        }),
      );
    }
  }

  static Future<void> _runThumbnailDownload(
    _ThumbnailDownloadJob job,
  ) async {
    final source = job.messages.first;
    try {
      await MessageMediaMetadataStore.instance.hydrateMessages(
        <V2TimMessage>[source],
      );
      if (!_hasLocalThumbFile(source) &&
          resolveBubbleThumbUrl(source) == null) {
        await _resolveOnlineUrlForMessage(source);
      }
      if (!_isForeground) {
        return;
      }
      if (!_hasLocalThumbFile(source) &&
          resolveBubbleThumbUrl(source) != null) {
        final result = await _messageService.downloadMessage(
          msgID: job.key,
          message: source,
          messageType: MessageElemType.V2TIM_ELEM_TYPE_IMAGE,
          imageType: 1,
          isSnapshot: false,
          reportError: false,
        );
        if (result.code != 0) {
          ChatThermalPerf.increment('thumb_download_failed');
          return;
        }
      }
      if (!_hasLocalThumbFile(source)) {
        ChatThermalPerf.increment('thumb_download_failed');
        return;
      }
      for (final target in job.messages) {
        _copyResolvedMedia(source, target);
      }
      await MessageMediaMetadataStore.instance.upsertFromMessage(source);
      if (_isForeground) {
        _notifyMediaMessageResolved(source);
      }
      ChatThermalPerf.increment('thumb_download_completed');
    } catch (_) {
      ChatThermalPerf.increment('thumb_download_failed');
    }
  }

  @visibleForTesting
  static int get debugThumbnailDownloadInFlight => _thumbnailDownloadInFlight;

  @visibleForTesting
  static int get debugThumbnailDownloadPending =>
      _thumbnailDownloadPending.length;

  @visibleForTesting
  static int get debugMaxThumbnailDownloadConcurrent =>
      _maxThumbnailDownloadConcurrent;

  @visibleForTesting
  static int get debugMaxThumbnailDownloadQueue => _maxThumbnailDownloadQueue;

  @visibleForTesting
  static int get debugMaxThumbnailDownloadsPerMinute =>
      _maxThumbnailDownloadsPerMinute;

  /// 点击会话时只预热已有本地首屏媒体缓存，不主动拉取历史。
  static void prefetchForConversation(V2TimConversation conversation) {
    final key = _conversationKey(conversation);
    if (key == null || key.isEmpty) {
      return;
    }
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    if (!globalModel.hasInitialHistoryLoaded(key) ||
        globalModel.rawMessageCount(key) <= 0) {
      return;
    }
    final cached = globalModel.getMessageList(key);
    if (cached == null || cached.isEmpty) {
      return;
    }
    if ((conversation.userID?.trim() ?? '').isNotEmpty) {
      prefetchThumbnailsForFirstWindow(cached);
    }
    unawaited(
      prepareFirstWindowMedia(
        cached,
        budget: initialMediaBudget,
        onMessageResolved: _notifyMediaMessageResolved,
      ),
    );
  }

  /// 进入聊天页前：只读取本地首屏并立即返回可灌入 globalModel 的消息；
  /// 补 URL / 预热缩略图在后台进行，不阻塞导航，也不触发云端历史请求。
  static Future<ChatOpenPrefetchResult> prepareBeforeChatOpen(
    V2TimConversation conversation, {
    Duration warmBudget = const Duration(milliseconds: 450),
    Duration? prepareBudget,
    void Function(ChatOpenPrefetchResult result)? onLatePrepared,
  }) async {
    final result = await _loadPeekForConversation(conversation);
    if (result.messages.isEmpty) {
      return const ChatOpenPrefetchResult(
        messages: <V2TimMessage>[],
        hasMoreOlder: false,
      );
    }
    final messages = List<V2TimMessage>.from(result.messages);
    await MessageMediaMetadataStore.instance.hydrateMessages(messages);
    if ((conversation.userID?.trim() ?? '').isNotEmpty) {
      prefetchThumbnailsForFirstWindow(messages);
    }
    final effectivePrepareBudget = prepareBudget;
    if (effectivePrepareBudget != null &&
        effectivePrepareBudget > Duration.zero) {
      await prepareFirstWindowMedia(
        messages,
        budget: effectivePrepareBudget,
        onMessageResolved: _notifyMediaMessageResolved,
      );
    }
    final openResult = ChatOpenPrefetchResult(
      messages: messages,
      hasMoreOlder: result.hasMoreOlder,
    );
    unawaited(
      _enrichOpenPrefetchInBackground(
        messages: messages,
        warmBudget: warmBudget,
        hasMoreOlder: result.hasMoreOlder,
        onLatePrepared: onLatePrepared,
      ),
    );
    return openResult;
  }

  static Future<void> _enrichOpenPrefetchInBackground({
    required List<V2TimMessage> messages,
    required Duration warmBudget,
    required bool hasMoreOlder,
    void Function(ChatOpenPrefetchResult result)? onLatePrepared,
  }) async {
    await resolveOnlineUrlsForMessages(
      messages,
      includeSelf: true,
      onMessageResolved: _notifyMediaMessageResolved,
    );
    unawaited(MessageMediaMetadataStore.instance.persistFromMessages(messages));
    fromMessages(messages);
    if (warmBudget > Duration.zero) {
      await warmWithBudget(messages, warmBudget);
    }
    onLatePrepared?.call(
      ChatOpenPrefetchResult(
        messages: messages,
        hasMoreOlder: hasMoreOlder,
      ),
    );
  }

  static Future<ConversationPeekLoadResult> _loadPeekForConversation(
    V2TimConversation conversation,
  ) {
    final key = _conversationKey(conversation);
    if (key == null || key.isEmpty) {
      return Future<ConversationPeekLoadResult>.value(
        const ConversationPeekLoadResult(
          messages: <V2TimMessage>[],
          hasMoreOlder: false,
          isFinished: true,
        ),
      );
    }
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    if (ConversationPreviewHistorySync.isWarmWindowReadyForOpen(
      globalModel: globalModel,
      conversationKey: key,
      preview: conversation.lastMessage,
    )) {
      final cached = globalModel.messageListMap[key] ?? const <V2TimMessage>[];
      return Future<ConversationPeekLoadResult>.value(
        ConversationPeekLoadResult(
          messages: List<V2TimMessage>.from(cached),
          hasMoreOlder: globalModel.mayHaveOlderHistory(key),
          isFinished: !globalModel.mayHaveOlderHistory(key),
        ),
      );
    }
    final inFlight = _peekInFlight[key];
    if (inFlight != null) {
      return inFlight;
    }
    // 历史云端校验只能由 ConversationHistorySyncCoordinator 发起。
    // 图片预取只消费 SDK 本地已有窗口，避免在路由转场前再开一个云端历史请求。
    final task = ConversationPeekService.loadLocalForChatEntry(conversation);
    _peekInFlight[key] = task;
    return task.whenComplete(() {
      if (_peekInFlight[key] == task) {
        _peekInFlight.remove(key);
      }
    });
  }

  static String? _conversationKey(V2TimConversation conversation) {
    final userID = conversation.userID?.trim();
    if (userID != null && userID.isNotEmpty) {
      return userID;
    }
    final groupID = conversation.groupID?.trim();
    if (groupID != null && groupID.isNotEmpty) {
      return ChatIdFormat.canonicalGroupStorageId(groupID);
    }
    final conversationID = conversation.conversationID.trim();
    if (conversationID.isEmpty) {
      return null;
    }
    if (conversationID.toLowerCase().startsWith('group_')) {
      return ChatIdFormat.canonicalGroupStorageId(conversationID);
    }
    return conversationID;
  }

  /// 本地历史有图但缺 URL 时，批量向 SDK 补全（首进关键路径）。
  ///
  /// [budget] 超时后后台继续补全，不阻塞导航。
  static Future<void> resolveOnlineUrlsForMessages(
    Iterable<V2TimMessage?> messages, {
    Duration? budget,
    bool includeSelf = false,
    void Function(V2TimMessage message)? onMessageResolved,
  }) async {
    final task = _resolveOnlineUrlsForMessages(
      messages,
      includeSelf: includeSelf,
      onMessageResolved: onMessageResolved,
    );
    if (budget == null) {
      await task;
      return;
    }
    try {
      await task.timeout(budget);
    } on TimeoutException {
      unawaited(task);
    }
  }

  static Future<void> _resolveOnlineUrlsForMessages(
    Iterable<V2TimMessage?> messages, {
    bool includeSelf = false,
    void Function(V2TimMessage message)? onMessageResolved,
  }) async {
    final list = messages.whereType<V2TimMessage>().toList(growable: false);
    await MessageMediaMetadataStore.instance.hydrateMessages(list);
    unawaited(MessageMediaMetadataStore.instance.persistFromMessages(list));
    final pending = <V2TimMessage>[];
    for (var index = list.length - 1; index >= 0; index--) {
      if (pending.length >= _maxUrlResolve) {
        break;
      }
      final message = list[index];
      if (!needsOnlineUrlResolution(message, includeSelf: includeSelf)) {
        continue;
      }
      pending.add(message);
    }
    if (pending.isEmpty) {
      return;
    }

    var cursor = 0;
    Future<void> worker() async {
      while (true) {
        if (cursor >= pending.length) {
          return;
        }
        final index = cursor;
        cursor++;
        final message = pending[index];
        await _resolveOnlineUrlForMessage(message);
        if (onMessageResolved != null &&
            !needsOnlineUrlResolution(message, includeSelf: includeSelf)) {
          onMessageResolved(message);
          // A URL that arrives after the bounded open budget still gets the
          // same bubble cache warm-up before the row rebuilds.
          fromMessages(<V2TimMessage>[message]);
        }
      }
    }

    final workers = <Future<void>>[];
    final workerCount = pending.length < _maxUrlResolveConcurrent
        ? pending.length
        : _maxUrlResolveConcurrent;
    for (var i = 0; i < workerCount; i++) {
      workers.add(worker());
    }
    await Future.wait(workers);
  }

  static bool needsOnlineUrlResolution(
    V2TimMessage message, {
    bool includeSelf = false,
  }) {
    // 会话预览需要给「自己发的图」补 URL：本地缓存可能已被清掉。
    if (message.isSelf == true && !includeSelf) {
      return false;
    }
    final msgID = message.msgID?.trim() ?? '';
    if (msgID.isEmpty) {
      return false;
    }
    if (message.elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE ||
        message.imageElem != null) {
      if (_hasLocalThumbFile(message)) {
        return false;
      }
      return resolveBubbleThumbUrl(message) == null;
    }
    if (message.elemType == MessageElemType.V2TIM_ELEM_TYPE_VIDEO ||
        message.videoElem != null) {
      if (_hasLocalVideoSnapshotFile(message)) {
        return false;
      }
      return resolveVideoSnapshotUrl(message) == null ||
          resolveVideoPlayUrl(message) == null;
    }
    return false;
  }

  static bool _hasLocalThumbFile(V2TimMessage message) {
    final imageList = message.imageElem?.imageList;
    if (imageList == null) {
      return false;
    }
    final banOrigin = imageMessageExceedsListPrefetchBan(message);
    for (final image in imageList) {
      final type = image?.type;
      if (banOrigin) {
        if (type != 1) {
          continue;
        }
      } else if (type != 1 && type != 2) {
        continue;
      }
      final local = image?.localUrl?.trim() ?? '';
      if (local.isNotEmpty && !kIsWeb && File(local).existsSync()) {
        return true;
      }
    }
    return false;
  }

  static String? _resolveLocalBubblePath(V2TimMessage message) {
    if (kIsWeb) {
      return null;
    }
    final banOrigin = imageMessageExceedsListPrefetchBan(message);
    final imageList = message.imageElem?.imageList;
    if (imageList != null) {
      final allowedTypes = banOrigin ? const <int>[1] : const <int>[1, 2];
      for (final type in allowedTypes) {
        for (final image in imageList) {
          if (image?.type != type) {
            continue;
          }
          final local = image?.localUrl?.trim() ?? '';
          if (local.isNotEmpty && File(local).existsSync()) {
            return local;
          }
        }
      }
    }
    if (banOrigin) {
      return null;
    }
    final path = message.imageElem?.path?.trim() ?? '';
    if (path.isNotEmpty && File(path).existsSync()) {
      return path;
    }
    return null;
  }

  @visibleForTesting
  static String? debugResolveLocalBubblePath(V2TimMessage message) =>
      _resolveLocalBubblePath(message);

  static bool _hasLocalVideoSnapshotFile(V2TimMessage message) {
    if (kIsWeb) {
      return false;
    }
    for (final path in <String?>[
      message.videoElem?.localSnapshotUrl,
      message.videoElem?.snapshotPath,
      message.videoElem?.localVideoUrl,
      message.videoElem?.videoPath,
    ]) {
      final value = path?.trim() ?? '';
      if (value.isNotEmpty && File(value).existsSync()) {
        return true;
      }
    }
    return false;
  }

  static String? resolveBubbleThumbUrl(V2TimMessage message) {
    final imageList = message.imageElem?.imageList;
    if (imageList == null || imageList.isEmpty) {
      return null;
    }
    final banOrigin = imageMessageExceedsListPrefetchBan(message);
    // 预热只用缩略图，避免大图进全局 imageCache 挤掉头像。
    final thumb = MessageUtils.getImageFromImgList(
      imageList,
      HistoryMessageDartConstant.smallImgPrior,
    );
    if (!banOrigin || thumb?.type == 1) {
      final url = thumb?.url?.trim() ?? '';
      if (url.startsWith('http')) {
        return url;
      }
    }
    for (final image in imageList) {
      if (image?.type != 1) {
        continue;
      }
      final candidate = image?.url?.trim() ?? '';
      if (candidate.startsWith('http')) {
        return candidate;
      }
    }
    if (imageMessageExceedsListPrefetchBan(message)) {
      return null;
    }
    for (final image in imageList) {
      final candidate = image?.url?.trim() ?? '';
      if (candidate.startsWith('http')) {
        return candidate;
      }
    }
    return null;
  }

  static String? resolveVideoSnapshotUrl(V2TimMessage message) {
    for (final candidate in <String?>[
      message.videoElem?.snapshotUrl,
      message.videoElem?.videoUrl,
    ]) {
      final value = candidate?.trim() ?? '';
      if (value.startsWith('http')) {
        return value;
      }
    }
    return null;
  }

  static String? resolveVideoPlayUrl(V2TimMessage message) {
    final value = message.videoElem?.videoUrl?.trim() ?? '';
    return value.startsWith('http') ? value : null;
  }

  static Future<void> _resolveOnlineUrlForMessage(V2TimMessage message) async {
    final msgID = message.msgID?.trim() ?? '';
    if (msgID.isEmpty) {
      return;
    }
    final existing = _urlResolveInFlight[msgID];
    if (existing != null) {
      final source = await existing;
      _copyResolvedMedia(source, message);
      return;
    }
    final task = _resolveOnlineUrlForMessageImpl(message).then((_) => message);
    _urlResolveInFlight[msgID] = task;
    try {
      await task;
    } finally {
      if (identical(_urlResolveInFlight[msgID], task)) {
        _urlResolveInFlight.remove(msgID);
      }
    }
  }

  static void _copyResolvedMedia(
    V2TimMessage? source,
    V2TimMessage target,
  ) {
    if (source == null || identical(source, target)) {
      return;
    }
    if (source.imageElem != null) {
      target.imageElem = source.imageElem;
    }
    if (source.videoElem != null) {
      target.videoElem = source.videoElem;
    }
  }

  static Future<void> _resolveOnlineUrlForMessageImpl(
    V2TimMessage message,
  ) async {
    final msgID = message.msgID?.trim() ?? '';
    if (msgID.isEmpty) {
      return;
    }
    try {
      final response = await _messageService.getMessageOnlineUrl(
        msgID: msgID,
        reportError: false,
      );
      final imageElem = response.data?.imageElem;
      if (imageElem != null) {
        message.imageElem = imageElem;
      }
      final videoElem = response.data?.videoElem;
      if (videoElem != null) {
        message.videoElem = videoElem;
      }
      if (imageElem != null || videoElem != null) {
        await MessageMediaMetadataStore.instance.upsertFromMessage(message);
      }
    } catch (_) {}
  }

  /// Resolves only the newest image rows that can be visible at the bottom of
  /// the initial window, then warms their bubble thumbnail cache. The caller
  /// returns immediately by default; callers that opt into [awaitNetwork] get a
  /// bounded wait. URL/image work continues in the background and the same
  /// message objects are updated in place.
  static Future<void> prepareFirstWindowMedia(
    Iterable<V2TimMessage?> messages, {
    Duration budget = initialMediaBudget,
    bool awaitNetwork = false,
    void Function(V2TimMessage message)? onMessageResolved,
  }) async {
    if (budget <= Duration.zero) {
      return;
    }
    final selected = _selectInitialMediaMessages(messages);
    if (ChatCoverDiag.enabled && ChatCoverDiag.canLog) {
      ChatCoverDiag.log('prepare', '-', 'selected=${selected.length} budgetMs=${budget.inMilliseconds} awaitNetwork=$awaitNetwork');
      for (final message in selected) {
        ChatCoverDiag.log('selected', message.msgID ?? message.id ?? '-',
            'type=${message.elemType} ts=${message.timestamp} image=${message.imageElem != null} video=${message.videoElem != null}');
      }
    }
    if (selected.isEmpty) {
      return;
    }
    final stopwatch = Stopwatch()..start();
    // Only a very small local-cache warm is allowed to delay the first frame.
    // Remote covers must never hold chat navigation, even when awaitNetwork is
    // false: network warming continues after the route can render.
    final localSelected = selected
        .where((message) => _resolveLocalBubblePath(message) != null)
        .toList(growable: false);
    if (localSelected.isNotEmpty) {
      await warmWithBudget(
        localSelected,
        _shorterDuration(budget, initialLocalMediaBudget),
      );
    }
    if (ChatCoverDiag.enabled && ChatCoverDiag.canLog) {
      ChatCoverDiag.log('prepare_warm_return', '-', 'elapsedMs=${stopwatch.elapsedMilliseconds}');
    }
    final resolveBudget = _shorterDuration(budget, initialMediaUrlBudget);
    final resolveTask = resolveOnlineUrlsForMessages(
      selected,
      budget: resolveBudget,
      includeSelf: true,
      onMessageResolved: onMessageResolved,
    );
    if (!awaitNetwork) {
      // Metadata hydration remains in the task, but URL lookup and image
      // decode must never hold the history commit or route transition.
      unawaited(
        resolveTask.then((_) async {
          final remaining = budget - stopwatch.elapsed;
          if (remaining > Duration.zero) {
            await warmWithBudget(selected, remaining);
          }
        }).catchError((_) {}),
      );
      return;
    }
    await resolveTask;
    final remaining = budget - stopwatch.elapsed;
    if (remaining > Duration.zero) {
      await warmWithBudget(selected, remaining);
    }
  }

  /// Schedules only the newest visible-window thumbnails for disk persistence.
  /// This is safe for direct chat entries because it does not await or decode.
  static void prefetchThumbnailsForFirstWindow(
    Iterable<V2TimMessage?> messages,
  ) {
    for (final message in _selectInitialMediaMessages(messages)) {
      prefetchThumbnailForMessage(message);
    }
  }

  static List<V2TimMessage> _selectInitialMediaMessages(
    Iterable<V2TimMessage?> messages,
  ) {
    final list = messages.whereType<V2TimMessage>().toList(growable: false);
    final selected = <V2TimMessage>[];
    // History windows are chronological here; walk from newest to oldest so
    // the bottom viewport gets first access to both URL and image cache.
    for (var index = list.length - 1;
        index >= 0 && selected.length < _maxInitialMediaMessages;
        index--) {
      final message = list[index];
      if (message.elemType != MessageElemType.V2TIM_ELEM_TYPE_IMAGE &&
          message.imageElem == null && message.videoElem == null) {
        continue;
      }
      selected.add(message);
    }
    // Keep the public list chronological so the existing reverse walkers in
    // URL resolution and image warming still prioritize the newest row.
    return selected.reversed.toList(growable: false);
  }

  static Duration _shorterDuration(Duration left, Duration right) {
    return left <= right ? left : right;
  }

  static void _notifyMediaMessageResolved(V2TimMessage message) {
    try {
      serviceLocator<TUIChatGlobalModel>().mergeMessageMediaMetadata(message);
    } catch (_) {
      // The prefetcher is also used before the global model is registered.
    }
  }

  static void fromMessages(Iterable<V2TimMessage?> messages) {
    _prefetchFromMessages(messages, maxCount: _maxPrefetch);
  }

  /// 上拉加载更早历史时，仅预热少量靠近当前视口的图片。
  static void fromHistoricalBatch(Iterable<V2TimMessage?> messages) {
    _prefetchFromMessages(messages, maxCount: _maxHistoricalPrefetch);
  }

  /// 退出聊天页时取消尚未开始的预取队列。
  static void cancelPending() {
    _warmQueue.cancelPending();
  }

  /// 退出聊天页：释放本会话气泡缩略图内存位图，把头像缓存让出来。
  /// 只驱逐已知气泡 provider，不清空整库。
  static void evictBubbleCacheForMessages(Iterable<V2TimMessage?> messages) {
    if (kIsWeb) {
      return;
    }
    cancelPending();
    _evictBubbleProvidersNow(_collectBubbleProvidersForEviction(messages));
  }

  /// 聊天路由退出后分帧释放图片气泡缓存，避免 pop 动画与 ImageCache 驱逐抢主线程。
  static void evictBubbleCacheForMessagesAfterFrame(
    Iterable<V2TimMessage?> messages,
  ) {
    if (kIsWeb) {
      return;
    }
    cancelPending();
    final snapshot =
        List<V2TimMessage>.from(messages.whereType<V2TimMessage>());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final providers = _collectBubbleProvidersForEviction(snapshot);
      _evictBubbleProvidersInBatches(providers);
    });
  }

  static List<({String url, String cacheKey})>
      _collectBubbleProvidersForEviction(Iterable<V2TimMessage?> messages) {
    final pendingEvict = <({String url, String cacheKey})>[
      ..._warmedBubbleProviders,
    ];
    _warmedBubbleProviders.clear();
    for (final message in messages.whereType<V2TimMessage>()) {
      if (message.elemType != MessageElemType.V2TIM_ELEM_TYPE_IMAGE &&
          message.imageElem == null) {
        continue;
      }
      final localPath = _resolveLocalBubblePath(message);
      if (localPath != null) {
        forgetChatBubbleImageWarmDecodeHint(
          chatBubbleImageCacheKey(message.msgID, url: localPath),
        );
      }
      final url = resolveBubbleThumbUrl(message);
      if (url == null || url.isEmpty) {
        continue;
      }
      pendingEvict.add((
        url: url,
        cacheKey: chatBubbleImageCacheKey(message.msgID, url: url),
      ));
    }
    final seen = <String>{};
    return pendingEvict
        .where((item) => seen.add(item.cacheKey))
        .toList(growable: false);
  }

  static void _evictBubbleProvidersNow(
    Iterable<({String url, String cacheKey})> providers,
  ) {
    for (final item in providers) {
      try {
        _evictBubbleProviders(item.url, item.cacheKey);
      } catch (_) {}
    }
  }

  static void _evictBubbleProvidersInBatches(
    List<({String url, String cacheKey})> providers, [
    int offset = 0,
  ]) {
    if (offset >= providers.length) {
      return;
    }
    final end =
        (offset + _leaveEvictBatchSize).clamp(0, providers.length).toInt();
    _evictBubbleProvidersNow(providers.sublist(offset, end));
    if (end >= providers.length) {
      return;
    }
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _evictBubbleProvidersInBatches(providers, end);
    });
  }

  static void _prefetchFromMessages(
    Iterable<V2TimMessage?> messages, {
    required int maxCount,
  }) {
    if (!_pageAllowsDecode || _prefetchPaused) {
      return;
    }
    final list = messages.whereType<V2TimMessage>().toList(growable: false);
    if (list.isEmpty) {
      return;
    }

    var warmed = 0;
    for (var index = list.length - 1; index >= 0; index--) {
      if (warmed >= maxCount) {
        break;
      }
      final message = list[index];
      if (message.elemType != MessageElemType.V2TIM_ELEM_TYPE_IMAGE &&
          message.imageElem == null) {
        continue;
      }
      if (_hasLocalThumbFile(message)) {
        continue;
      }

      final url = resolveBubbleThumbUrl(message);
      if (url == null) {
        continue;
      }

      warmed++;
      _scheduleWarmNetworkImage(
        url,
        chatBubbleImageCacheKey(message.msgID, url: url),
        decodeByWidth: _decodeBubbleImageByWidth(message),
      );
    }
  }

  static Future<void> warmWithBudget(
    Iterable<V2TimMessage?> messages,
    Duration budget,
  ) async {
    final jobs = <Future<void>>[];
    final list = messages.whereType<V2TimMessage>().toList(growable: false);
    for (var index = list.length - 1; index >= 0; index--) {
      if (jobs.length >= 4) {
        break;
      }
      final message = list[index];
      if (message.videoElem != null) {
        final cover = chatVideoCoverProvider(message.videoElem!);
        if (ChatCoverDiag.enabled && ChatCoverDiag.canLog) {
          ChatCoverDiag.log('warm_video', message.msgID ?? '-', 'provider=${cover?.runtimeType}');
        }
        if (cover != null) jobs.add(_warmProvider(cover));
        continue;
      }
      if (message.elemType != MessageElemType.V2TIM_ELEM_TYPE_IMAGE &&
          message.imageElem == null) {
        continue;
      }
      final url = resolveBubbleThumbUrl(message);
      final localPath = _resolveLocalBubblePath(message);
      if (ChatCoverDiag.enabled && ChatCoverDiag.canLog) {
        ChatCoverDiag.log('warm_image', message.msgID ?? '-', 'local=${localPath != null} url=${url != null}');
      }
      if (url == null && localPath == null) {
        continue;
      }
      jobs.add(
        localPath != null
            ? _warmLocalImage(
                localPath,
                chatBubbleImageCacheKey(message.msgID, url: localPath),
                decodeByWidth: _decodeBubbleImageByWidth(message),
              )
            : _warmNetworkImage(
                url!,
                chatBubbleImageCacheKey(message.msgID, url: url),
                decodeByWidth: _decodeBubbleImageByWidth(message),
              ),
      );
    }
    if (jobs.isEmpty) {
      return;
    }
    try {
      await Future.wait(jobs).timeout(budget);
    } catch (_) {}
  }

  static void _scheduleWarmNetworkImage(
    String url,
    String cacheKey, {
    bool decodeByWidth = true,
  }) {
    BackgroundMediaGate.instance.observeMetrics();
    _warmQueue.add(cacheKey, () => _warmNetworkImage(
      url, cacheKey, decodeByWidth: decodeByWidth,
    ));
  }

  /// Keep the prefetch ResizeImage axis aligned with the chat bubble.
  ///
  /// Normal portrait images are decoded by height, landscape images by width,
  /// and very tall images by width because the bubble uses a top-aligned crop.
  /// When dimensions are unavailable, width is the conservative fallback used
  /// by the legacy prefetch path.
  static bool _decodeBubbleImageByWidth(V2TimMessage message) {
    final meta = preferChatBubbleImageLayoutMeta(
      message.imageElem?.imageList ?? const [],
    );
    final width = meta?.width ?? 0;
    final height = meta?.height ?? 0;
    if (width <= 0 || height <= 0) {
      return true;
    }
    if (isChatBubbleLongImage(
      sourceWidth: width.toDouble(),
      sourceHeight: height.toDouble(),
    )) {
      return true;
    }
    return width >= height;
  }

  static void _trackWarmedBubbleProvider({
    required String url,
    required String cacheKey,
  }) {
    _warmedBubbleProviders.removeWhere((e) => e.cacheKey == cacheKey);
    _warmedBubbleProviders.add((url: url, cacheKey: cacheKey));
    while (_warmedBubbleProviders.length > maxWarmedBubbleProviders) {
      final oldest = _warmedBubbleProviders.removeAt(0);
      _evictBubbleProviders(oldest.url, oldest.cacheKey);
    }
  }

  static Iterable<ImageProvider> _bubbleProviders(
    String url,
    String cacheKey,
  ) sync* {
    final base = CachedNetworkImageProvider(url, cacheKey: cacheKey);
    yield base;
    // 兼容旧预热写入的 720 ResizeImage，离开会话时一并 evict。
    yield ResizeImage(
      base,
      width: kChatBubbleImageDecodeScrollDeferMaxPx,
    );
    yield ResizeImage(
      base,
      height: kChatBubbleImageDecodeScrollDeferMaxPx,
    );
  }

  static void _evictBubbleProviders(String url, String cacheKey) {
    forgetChatBubbleImageWarmDecodeHint(cacheKey);
    final cache = PaintingBinding.instance.imageCache;
    for (final provider in _bubbleProviders(url, cacheKey)) {
      unawaited(_evictResolvedProvider(cache, provider));
    }
  }

  static Future<void> _evictResolvedProvider(
    ImageCache cache,
    ImageProvider provider,
  ) async {
    try {
      // ResizeImage caches under ResizeImageKey, not the provider object.
      final key = await provider.obtainKey(const ImageConfiguration());
      cache.evict(key, includeLive: false);
    } catch (_) {}
  }

  static Future<void> _warmNetworkImage(
    String url,
    String cacheKey, {
    bool decodeByWidth = true,
  }) async {
    if (kIsWeb || !_pageAllowsDecode) {
      return;
    }
    try {
      _trackWarmedBubbleProvider(url: url, cacheKey: cacheKey);
      registerChatBubbleImageWarmDecodeHint(
        cacheKey,
        decodeByWidth: decodeByWidth,
        targetPx: kChatBubbleImageDecodeScrollDeferMaxPx,
      );
      final base = CachedNetworkImageProvider(url, cacheKey: cacheKey);
      // Match the route-transition decode cap used by chat bubbles. The axis
      // follows the same orientation rule as the widget, so portrait rows do
      // not miss the decoded-image cache just because they use height.
      await _warmProvider(
        decodeByWidth
            ? ResizeImage(
                base,
                width: kChatBubbleImageDecodeScrollDeferMaxPx,
              )
            : ResizeImage(
                base,
                height: kChatBubbleImageDecodeScrollDeferMaxPx,
              ),
      );
    } catch (_) {}
  }

  static Future<void> _warmLocalImage(
    String path,
    String cacheKey, {
    bool decodeByWidth = true,
  }) async {
    if (kIsWeb || path.trim().isEmpty || !_pageAllowsDecode) {
      return;
    }
    try {
      registerChatBubbleImageWarmDecodeHint(
        cacheKey,
        decodeByWidth: decodeByWidth,
        targetPx: kChatBubbleImageDecodeScrollDeferMaxPx,
      );
      final base = FileImage(File(path));
      await _warmProvider(
        decodeByWidth
            ? ResizeImage(
                base,
                width: kChatBubbleImageDecodeScrollDeferMaxPx,
              )
            : ResizeImage(
                base,
                height: kChatBubbleImageDecodeScrollDeferMaxPx,
              ),
      );
    } catch (_) {}
  }

  @visibleForTesting
  static Future<void> debugEvictProvider(ImageProvider provider) =>
      _evictResolvedProvider(PaintingBinding.instance.imageCache, provider);

  @visibleForTesting
  static Future<void> debugWarmProvider(ImageProvider provider) =>
      _warmProvider(provider);

  static Future<void> _warmProvider(ImageProvider provider) async {
    final stream = provider.resolve(const ImageConfiguration());
    final completer = Completer<void>();
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, synchronous) {
        try {
          if (ChatCoverDiag.enabled && ChatCoverDiag.canLog) {
            ChatCoverDiag.log('warm_decoded', '-', 'provider=${provider.runtimeType} keyHash=${provider.hashCode} sync=$synchronous size=${info.image.width}x${info.image.height}');
          }
          if (!completer.isCompleted) {
            completer.complete();
          }
        } finally {
          // Each listener owns its ImageInfo clone, including synchronous
          // cache hits and animated frames received before detachment.
          info.dispose();
        }
      },
      onError: (_, __) {
        if (ChatCoverDiag.enabled && ChatCoverDiag.canLog) {
          ChatCoverDiag.log('warm_error', '-', 'provider=${provider.runtimeType} keyHash=${provider.hashCode}');
        }
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );
    stream.addListener(listener);
    try {
      await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {},
      );
    } finally {
      stream.removeListener(listener);
    }
  }
}
