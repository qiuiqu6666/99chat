import 'dart:async';

import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/message_media_metadata_store.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/group_tips_message_helper.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_coverage.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_batch.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_history_peek_loader.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/constants/history_message_constant.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_history_trace.dart';

class ConversationPeekLoadResult {
  const ConversationPeekLoadResult({
    required this.messages,
    required this.hasMoreOlder,
    required this.isFinished,
    this.receivedCloudResponse = false,
    this.requestedCursor,
    this.returnedBounds = const MessageHistoryBounds.empty(),
    this.batchKind = MessageHistoryBatchKind.olderPage,
  });

  final List<V2TimMessage> messages;
  final bool hasMoreOlder;
  final bool isFinished;

  /// Distinguishes a successful empty SDK page from a missing/error response.
  /// This is transport metadata, not proof that history is complete.
  final bool receivedCloudResponse;
  final MessageHistoryCursor? requestedCursor;
  final MessageHistoryBounds returnedBounds;
  final MessageHistoryBatchKind batchKind;

  /// Converts the legacy peek result into the typed history envelope used by
  /// reconciliation. Generation and clear epoch belong to the caller because
  /// they are allocated around the actual async request.
  MessageHistoryBatch<V2TimMessage> toBatch({
    required String conversationKey,
    required MessageReconciliationSource requestedSource,
    required MessageReconciliationSource actualSource,
    required int requestGeneration,
    required int clearEpoch,
    required bool cloudResponseProven,
    MessageHistoryBatchKind? batchKind,
    Iterable<V2TimMessage>? messages,
  }) {
    final effectiveMessages =
        messages?.toList(growable: false) ?? this.messages;
    return MessageHistoryBatch<V2TimMessage>(
      conversationKey: conversationKey,
      requestedSource: requestedSource,
      actualSource: actualSource,
      batchKind: batchKind ?? this.batchKind,
      requestGeneration: requestGeneration,
      clearEpoch: clearEpoch,
      requestedCursor: requestedCursor,
      returnedBounds: messages == null && !returnedBounds.isEmpty
          ? returnedBounds
          : _boundsForMessages(effectiveMessages),
      isFinished: isFinished,
      hasMoreOlder: hasMoreOlder,
      cloudHasMoreNewer: false,
      cloudResponseProven: cloudResponseProven,
      messages: effectiveMessages,
    );
  }

  static MessageHistoryBounds _boundsForMessages(
    Iterable<V2TimMessage> messages,
  ) {
    V2TimMessage? oldest;
    V2TimMessage? newest;
    for (final message in messages) {
      if ((message.msgID?.trim() ?? '').isEmpty) continue;
      if (oldest == null ||
          TUIChatGlobalModel.compareMessagesChronological(message, oldest) <
              0) {
        oldest = message;
      }
      if (newest == null ||
          TUIChatGlobalModel.compareMessagesChronological(message, newest) >
              0) {
        newest = message;
      }
    }
    return MessageHistoryBounds(
      oldestMsgID: oldest?.msgID,
      newestMsgID: newest?.msgID,
      oldestSeq: int.tryParse(oldest?.seq?.trim() ?? ''),
      newestSeq: int.tryParse(newest?.seq?.trim() ?? ''),
    );
  }
}

class ConversationPeekService {
  ConversationPeekService._();

  static const int peekMessageCount = 15;

  static final MessageService _messageService =
      serviceLocator<MessageService>();

  static bool canPeek(V2TimConversation conversation) {
    if ((conversation.userID ?? '').trim() == '10000') {
      return false;
    }
    return _isGroup(conversation)
        ? (conversation.groupID?.trim().isNotEmpty ?? false)
        : (conversation.userID?.trim().isNotEmpty ?? false);
  }

  static Future<ConversationPeekLoadResult> loadInitial(
    V2TimConversation conversation,
  ) {
    return _loadOlder(
      conversation: conversation,
      anchor: null,
      count: peekMessageCount,
    );
  }

  /// 进入聊天页首屏：C2C / 群聊只打 IM 云端最新一页。
  static Future<ConversationPeekLoadResult> loadForChatEntry(
    V2TimConversation conversation,
  ) {
    return _loadCloudOnlyForChatEntry(conversation);
  }

  /// C2C / 群聊进页只打 IM 云端最新一页，不和本地库/归档焊在一起。
  static Future<ConversationPeekLoadResult> _loadCloudOnlyForChatEntry(
    V2TimConversation conversation,
  ) async {
    if (!canPeek(conversation)) {
      return const ConversationPeekLoadResult(
        messages: <V2TimMessage>[],
        hasMoreOlder: false,
        isFinished: true,
      );
    }
    final isGroup = _isGroup(conversation);
    final userID = isGroup ? null : conversation.userID?.trim();
    final rawGroupID = conversation.groupID?.trim();
    final groupID = isGroup && rawGroupID != null && rawGroupID.isNotEmpty
        ? ChatIdFormat.canonicalGroupStorageId(rawGroupID)
        : null;
    // Route the warm cloud read through IM-06 as well. This keeps chat-entry
    // verification in the same per-conversation priority queue as a user's
    // upward pagination request, so a warm read cannot sit ahead of a real
    // user action or hide the native SDK error metadata.
    final result = await serviceLocator<TUIChatGlobalModel>()
        .getHistoryMessageListThroughIm06(
      count: HistoryMessageDartConstant.initialOpenFetchCount,
      getType: HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
      userID: userID,
      groupID: groupID,
    );
    final rawMessages = result?.messageList ?? const <V2TimMessage>[];
    var messages = _dedupeMessages(rawMessages);
    messages = await _dropMessagesAtOrBeforeHistoryClear(
      conversation: conversation,
      messages: messages,
    );
    await MessageMediaMetadataStore.instance.hydrateMessages(messages);
    unawaited(MessageMediaMetadataStore.instance.persistFromMessages(messages));
    return ConversationPeekLoadResult(
      messages: messages,
      hasMoreOlder:
          messages.length >= HistoryMessageDartConstant.initialOpenFetchCount ||
              result == null ||
              !result.isFinished,
      isFinished: result?.isFinished ?? false,
      receivedCloudResponse: result != null,
      batchKind: MessageHistoryBatchKind.latestWindow,
      requestedCursor: const MessageHistoryCursor(
        direction: MessageHistoryCursorDirection.latest,
      ),
      returnedBounds: ConversationPeekLoadResult._boundsForMessages(messages),
    );
  }

  static Future<void> _hydrateLocalMessageMetadata(
    List<V2TimMessage> messages,
  ) async {
    try {
      await MessageMediaMetadataStore.instance.hydrateMessages(messages);
      unawaited(
        MessageMediaMetadataStore.instance.persistFromMessages(messages),
      );
    } catch (_) {
      // A media metadata miss cannot invalidate the local history snapshot.
    }
  }

  /// 冷启动聊天首屏快路径：只读 IM SDK 本地库，不等待云端或归档。
  /// 查到的消息应立即上屏；完整窗口随后由 [loadForChatEntry] 异步校对。
  static Future<ConversationPeekLoadResult> loadLocalForChatEntry(
    V2TimConversation conversation,
  ) async {
    if (!canPeek(conversation)) {
      return const ConversationPeekLoadResult(
        messages: <V2TimMessage>[],
        hasMoreOlder: false,
        isFinished: true,
      );
    }
    final isGroup = _isGroup(conversation);
    final userID = isGroup ? null : conversation.userID?.trim();
    final rawGroupID = conversation.groupID?.trim();
    final groupID = isGroup && rawGroupID != null && rawGroupID.isNotEmpty
        ? ChatIdFormat.canonicalGroupStorageId(rawGroupID)
        : null;
    final result = await MessageHistoryPeekLoader.loadOlderLocalOnlyResult(
      messageService: _messageService,
      count: HistoryMessageDartConstant.initialOpenFetchCount,
      userID: userID,
      groupID: groupID,
    );
    var messages = _dedupeMessages(result.messageList);
    messages = await _dropMessagesAtOrBeforeHistoryClear(
      conversation: conversation,
      messages: messages,
    );
    // Text and message identity are ready after the SDK local query. Media
    // metadata is enrichment and must not delay the local first frame.
    unawaited(_hydrateLocalMessageMetadata(messages));
    return ConversationPeekLoadResult(
      messages: messages,
      hasMoreOlder:
          messages.length >= HistoryMessageDartConstant.initialOpenFetchCount ||
              !result.isFinished,
      isFinished: result.isFinished,
      batchKind: MessageHistoryBatchKind.localSnapshot,
      requestedCursor: const MessageHistoryCursor(
        direction: MessageHistoryCursorDirection.latest,
      ),
      returnedBounds: ConversationPeekLoadResult._boundsForMessages(messages),
    );
  }

  static Future<ConversationPeekLoadResult> loadOlder({
    required V2TimConversation conversation,
    required V2TimMessage anchor,
  }) {
    return _loadOlder(
      conversation: conversation,
      anchor: anchor,
      count: peekMessageCount,
    );
  }

  static Future<ConversationPeekLoadResult> _loadOlder({
    required V2TimConversation conversation,
    required V2TimMessage? anchor,
    required int count,
  }) async {
    if (!canPeek(conversation)) {
      return const ConversationPeekLoadResult(
        messages: [],
        hasMoreOlder: false,
        isFinished: true,
      );
    }

    final isGroup = _isGroup(conversation);
    final userID = isGroup ? null : conversation.userID?.trim();
    // SDK / 归档一律裸群 ID（@TGS#…），禁止 group_ 前缀。
    final rawGroupID = conversation.groupID?.trim();
    final groupID = isGroup && rawGroupID != null && rawGroupID.isNotEmpty
        ? ChatIdFormat.canonicalGroupStorageId(rawGroupID)
        : null;
    final lastMsgID = anchor?.msgID;
    final lastMsgSeq = int.tryParse(anchor?.seq?.toString() ?? '') ?? -1;

    final peekConvKey = isGroup ? (groupID ?? '') : (userID ?? '');
    ChatHistoryTrace.log(
      'peek_load_start',
      conversationID: peekConvKey,
      extras: <String, Object?>{
        'rawGroupID': rawGroupID ?? '',
        'isGroup': isGroup,
        'count': count,
        'hasAnchor': anchor != null,
        'anchorId': anchor?.msgID ?? '',
        'anchorTs': anchor?.timestamp ?? 0,
      },
    );

    final peekResult =
        await MessageHistoryPeekLoader.loadOlderLocalThenCloudResult(
      messageService: _messageService,
      count: count,
      userID: userID,
      groupID: groupID,
      lastMsgID: lastMsgID,
      lastMsgSeq: lastMsgSeq,
    );
    final sdkMessages = peekResult.messageList;

    var merged = _dedupeMessages(sdkMessages);
    merged = await _dropMessagesAtOrBeforeHistoryClear(
      conversation: conversation,
      messages: merged,
    );
    final sdkPageFull = merged.length >= count;
    final hasMoreOlder = sdkPageFull || !peekResult.isFinished;

    merged = await _dropMessagesAtOrBeforeHistoryClear(
      conversation: conversation,
      messages: merged,
    );

    if (anchor == null && merged.length > count) {
      merged = merged.sublist(merged.length - count);
    }

    var sorted = _sortChronologically(merged);
    sorted = GroupTipsMessageHelper.applyPostMergeFilters(sorted);
    await MessageMediaMetadataStore.instance.hydrateMessages(sorted);
    unawaited(MessageMediaMetadataStore.instance.persistFromMessages(sorted));
    return ConversationPeekLoadResult(
      messages: sorted,
      hasMoreOlder: hasMoreOlder,
      isFinished: !hasMoreOlder,
      batchKind: MessageHistoryBatchKind.olderPage,
      requestedCursor: anchor == null
          ? const MessageHistoryCursor(
              direction: MessageHistoryCursorDirection.latest,
            )
          : MessageHistoryCursor(
              direction: MessageHistoryCursorDirection.older,
              lastMsgID: lastMsgID,
              lastMsgSeq: lastMsgSeq > 0 ? lastMsgSeq : null,
            ),
      returnedBounds: ConversationPeekLoadResult._boundsForMessages(sorted),
    );
  }

  static Future<List<V2TimMessage>> _dropMessagesAtOrBeforeHistoryClear({
    required V2TimConversation conversation,
    required List<V2TimMessage> messages,
  }) async {
    if (messages.isEmpty) {
      return messages;
    }
    final conversationID = conversation.conversationID.trim().isNotEmpty
        ? conversation.conversationID.trim()
        : (_isGroup(conversation)
            ? (conversation.groupID?.trim() ?? '')
            : (conversation.userID?.trim() ?? ''));
    if (conversationID.isEmpty) {
      return messages;
    }
    final clearedAt = await ConversationLocalStore.instance.historyClearedAtMs(
      conversationID,
    );
    if (clearedAt <= 0) {
      return messages;
    }
    return messages
        .where(
          (message) =>
              ConversationLocalStore.messageTimestampMs(message) > clearedAt,
        )
        .toList(growable: false);
  }

  static bool _isGroup(V2TimConversation conversation) {
    return conversation.type == 2 ||
        (conversation.groupID?.trim().isNotEmpty ?? false);
  }

  static List<V2TimMessage> _dedupeMessages(List<V2TimMessage> messages) {
    if (messages.isEmpty) {
      return const [];
    }
    return TUIChatGlobalModel.dedupeMessages(messages);
  }

  static List<V2TimMessage> _sortChronologically(List<V2TimMessage> messages) {
    return TUIChatGlobalModel.sortMessagesChronologicallyAsc(messages);
  }
}
