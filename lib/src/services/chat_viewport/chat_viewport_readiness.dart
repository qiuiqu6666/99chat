import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_models.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_coverage.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_message_height_cache.dart';

/// 纯函数：从最新锚点裁连续段、按高度判断 Ready、只认最新窗附近的洞。
class ChatViewportReadiness {
  ChatViewportReadiness._();

  static const double defaultViewportHeight = 560;
  static const double readyExtentFactor = 1.2;
  static const int hugeGapSeqDelta = 300;
  static const int openFetchBatch = 20;

  static double targetExtentFor(double viewportHeight) {
    final height = viewportHeight.isFinite && viewportHeight > 0
        ? viewportHeight
        : defaultViewportHeight;
    return height * readyExtentFactor;
  }

  static int messageSeq(V2TimMessage message) {
    return int.tryParse(message.seq?.trim() ?? '') ?? 0;
  }

  static String messageId(V2TimMessage message) {
    final msgID = message.msgID?.trim() ?? '';
    if (msgID.isNotEmpty) {
      return msgID;
    }
    return message.id?.trim() ?? '';
  }

  /// [newestFirst]：与 GlobalModel 一致，下标 0 为最新。
  /// 群聊用 seq 裁到洞即停；C2C seq 按发送方编号，不把 seq 跳号当洞。
  static List<V2TimMessage> takeNewestContiguous({
    required List<V2TimMessage> newestFirst,
    required bool useSeqContiguity,
  }) {
    if (newestFirst.isEmpty) {
      return const <V2TimMessage>[];
    }
    if (!useSeqContiguity) {
      return List<V2TimMessage>.from(newestFirst);
    }
    final spine = <V2TimMessage>[newestFirst.first];
    for (var i = 1; i < newestFirst.length; i++) {
      final newer = newestFirst[i - 1];
      final older = newestFirst[i];
      final newerSeq = messageSeq(newer);
      final olderSeq = messageSeq(older);
      if (newerSeq > 0 && olderSeq > 0 && newerSeq - olderSeq > 1) {
        break;
      }
      spine.add(older);
    }
    return spine;
  }

  static int? gapBeforeSeq({
    required List<V2TimMessage> newestFirst,
    required List<V2TimMessage> spine,
    required bool useSeqContiguity,
  }) {
    if (!useSeqContiguity || spine.isEmpty || spine.length >= newestFirst.length) {
      return null;
    }
    final oldestSpineSeq = messageSeq(spine.last);
    if (oldestSpineSeq <= 1) {
      return null;
    }
    return oldestSpineSeq - 1;
  }

  static bool isHugeGap({
    required List<V2TimMessage> newestFirst,
    required List<V2TimMessage> spine,
    required bool useSeqContiguity,
  }) {
    if (!useSeqContiguity || spine.isEmpty || spine.length >= newestFirst.length) {
      return false;
    }
    final older = newestFirst[spine.length];
    final newer = spine.last;
    final newerSeq = messageSeq(newer);
    final olderSeq = messageSeq(older);
    if (newerSeq <= 0 || olderSeq <= 0) {
      return false;
    }
    return newerSeq - olderSeq >= hugeGapSeqDelta;
  }

  /// 只认与当前最新连续段相交或紧贴其更早一侧的洞。
  static bool hasGapNearLatest({
    required MessageHistoryCoverage? coverage,
    required int? oldestContiguousSeq,
    required int? latestSeq,
  }) {
    if (coverage == null ||
        oldestContiguousSeq == null ||
        latestSeq == null ||
        oldestContiguousSeq <= 0 ||
        latestSeq <= 0) {
      return false;
    }
    for (final hole in coverage.holes) {
      if (hole.status == MessageHistoryHoleStatus.resolved) {
        continue;
      }
      final start = hole.startSeq;
      final end = hole.endSeq;
      if (start == null || end == null) {
        continue;
      }
      if (end < oldestContiguousSeq - 1) {
        continue;
      }
      if (start > latestSeq) {
        continue;
      }
      return true;
    }
    return false;
  }

  static double estimateContentExtent(
    Iterable<V2TimMessage> messages, {
    double screenWidth = ChatMessageHeightCache.defaultScreenWidth,
  }) {
    var sum = 0.0;
    final cache = ChatMessageHeightCache.instance;
    for (final message in messages) {
      final height = cache.heightFor(message) ??
          cache.estimateRowHeight(message, screenWidth: screenWidth) ??
          ChatMessageHeightCache.defaultRowHeight;
      if (height.isFinite && height > 0) {
        sum += height;
      }
    }
    return sum;
  }

  static ChatViewportAnchor? anchorOf(List<V2TimMessage> newestFirst) {
    if (newestFirst.isEmpty) {
      return null;
    }
    final newest = newestFirst.first;
    final id = messageId(newest);
    return ChatViewportAnchor(
      msgID: id.isEmpty ? null : id,
      seq: messageSeq(newest),
      timestamp: newest.timestamp,
    );
  }

  /// 本地 loaded 且 0 条不能当成 EMPTY_VERIFIED。
  static bool isEmptyVerified({
    required MessageHistoryCoverage? coverage,
    required int rawCount,
  }) {
    if (rawCount > 0) {
      return false;
    }
    if (coverage == null) {
      return false;
    }
    return coverage.status == MessageHistoryCoverageStatus.verified &&
        coverage.olderExhausted &&
        coverage.cloudVerifiedAtMs > 0 &&
        !coverage.hasOpenHoles;
  }

  static ChatOpenViewportResult classify({
    required String conversationKey,
    required List<V2TimMessage> newestFirst,
    required bool useSeqContiguity,
    required double viewportHeight,
    required ChatViewportSource source,
    MessageHistoryCoverage? coverage,
    bool reachedKnownLocalBoundary = false,
    int openGeneration = 0,
  }) {
    final target = targetExtentFor(viewportHeight);
    final emptyVerified = isEmptyVerified(
      coverage: coverage,
      rawCount: newestFirst.length,
    );
    if (newestFirst.isEmpty) {
      if (emptyVerified) {
        return ChatOpenViewportResult(
          conversationKey: conversationKey,
          mountedMessageIds: const <String>[],
          anchor: null,
          estimatedContentExtent: 0,
          viewportTargetExtent: target,
          coverageState: ChatViewportCoverageState.emptyVerified,
          isContiguous: true,
          needsLatestRepair: false,
          reachedKnownLocalBoundary: true,
          source: source,
          continuousCount: 0,
          emptyVerified: true,
          openGeneration: openGeneration,
        );
      }
      return ChatOpenViewportResult(
        conversationKey: conversationKey,
        mountedMessageIds: const <String>[],
        anchor: null,
        estimatedContentExtent: 0,
        viewportTargetExtent: target,
        coverageState: ChatViewportCoverageState.emptyLocal,
        isContiguous: true,
        needsLatestRepair: true,
        reachedKnownLocalBoundary: false,
        source: source,
        continuousCount: 0,
        openGeneration: openGeneration,
      );
    }

    final spine = takeNewestContiguous(
      newestFirst: newestFirst,
      useSeqContiguity: useSeqContiguity,
    );
    final gapSeq = gapBeforeSeq(
      newestFirst: newestFirst,
      spine: spine,
      useSeqContiguity: useSeqContiguity,
    );
    final huge = isHugeGap(
      newestFirst: newestFirst,
      spine: spine,
      useSeqContiguity: useSeqContiguity,
    );
    final latestSeq = messageSeq(spine.first);
    final oldestSeq = messageSeq(spine.last);
    final coverageGap = hasGapNearLatest(
      coverage: coverage,
      oldestContiguousSeq: oldestSeq > 0 ? oldestSeq : null,
      latestSeq: latestSeq > 0 ? latestSeq : null,
    );
    final hasViewportGap = gapSeq != null || coverageGap;
    final extent = estimateContentExtent(spine);
    final ids = <String>[
      for (final message in spine)
        if (messageId(message).isNotEmpty) messageId(message),
    ];
    final boundary = reachedKnownLocalBoundary && !hasViewportGap;
    final ChatViewportCoverageState state;
    if (hasViewportGap) {
      state = ChatViewportCoverageState.gapLocal;
    } else if (extent >= target || boundary) {
      state = ChatViewportCoverageState.readyLocal;
    } else {
      state = ChatViewportCoverageState.partialLocal;
    }
    return ChatOpenViewportResult(
      conversationKey: conversationKey,
      mountedMessageIds: List<String>.unmodifiable(ids),
      anchor: anchorOf(spine),
      estimatedContentExtent: extent,
      viewportTargetExtent: target,
      coverageState: state,
      isContiguous: true,
      needsLatestRepair: state == ChatViewportCoverageState.partialLocal ||
          state == ChatViewportCoverageState.gapLocal,
      reachedKnownLocalBoundary: boundary,
      source: source,
      continuousCount: spine.length,
      gapBeforeSeq: gapSeq,
      isHugeGap: huge,
      openGeneration: openGeneration,
    );
  }

  /// 合并时保留已上屏的更新消息。禁止 clear + addAll(incoming)。
  static List<V2TimMessage> mergePreserveRealtime({
    required List<V2TimMessage> current,
    required List<V2TimMessage> incoming,
  }) {
    if (current.isEmpty) {
      return List<V2TimMessage>.from(incoming);
    }
    if (incoming.isEmpty) {
      return List<V2TimMessage>.from(current);
    }
    final byId = <String, V2TimMessage>{};
    final anonymous = <V2TimMessage>[];
    void absorb(V2TimMessage message) {
      final id = messageId(message);
      if (id.isEmpty) {
        anonymous.add(message);
        return;
      }
      byId[id] = message;
    }

    for (final message in incoming) {
      absorb(message);
    }
    for (final message in current) {
      absorb(message);
    }
    final merged = <V2TimMessage>[...byId.values, ...anonymous];
    merged.sort((a, b) {
      final ts = (b.timestamp ?? 0).compareTo(a.timestamp ?? 0);
      if (ts != 0) {
        return ts;
      }
      final seqA = messageSeq(a);
      final seqB = messageSeq(b);
      if (seqA > 0 && seqB > 0 && seqA != seqB) {
        return seqB.compareTo(seqA);
      }
      return messageId(b).compareTo(messageId(a));
    });
    return merged;
  }

  static bool incomingIsStaleAgainstCurrent({
    required List<V2TimMessage> current,
    required List<V2TimMessage> incoming,
    required bool useSeqContiguity,
  }) {
    if (current.isEmpty || incoming.isEmpty || !useSeqContiguity) {
      return false;
    }
    final currentLatest = messageSeq(current.first);
    final incomingLatest = messageSeq(incoming.first);
    return currentLatest > 0 &&
        incomingLatest > 0 &&
        currentLatest > incomingLatest;
  }
}
