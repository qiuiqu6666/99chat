import 'package:flutter/foundation.dart';

/// 当前可展示视口的覆盖状态。只描述**最新锚点附近**，不是整段会话历史。
enum ChatViewportCoverageState {
  /// 最新连续窗口足够铺满首屏。
  readyLocal,

  /// 有连续消息，但估算高度不足一屏。
  partialLocal,

  /// 最新窗口附近存在 gap。更老位置的洞不算。
  gapLocal,

  /// 本地当前没有可展示消息。不等于确定无历史。
  emptyLocal,

  /// 云端已证明该会话没有历史。
  emptyVerified,

  /// 最新窗口已和云校正（H2 之后）。
  verified,
}

enum ChatViewportSource {
  cache,
  memory,
  local,
  cloudMerged,
}

enum ChatViewportRepairKind {
  none,
  openViewport,
  freshnessVerify,
}

@immutable
class ChatViewportAnchor {
  const ChatViewportAnchor({
    this.msgID,
    this.seq,
    this.timestamp,
  });

  final String? msgID;
  final int? seq;
  final int? timestamp;

  bool get isResolved =>
      (msgID != null && msgID!.isNotEmpty) || (seq != null && seq! > 0);
}

/// 开页准备结果：投影描述，不是第二份消息实体仓库。
@immutable
class ChatOpenViewportResult {
  const ChatOpenViewportResult({
    required this.conversationKey,
    required this.mountedMessageIds,
    required this.anchor,
    required this.estimatedContentExtent,
    required this.viewportTargetExtent,
    required this.coverageState,
    required this.isContiguous,
    required this.needsLatestRepair,
    required this.reachedKnownLocalBoundary,
    required this.source,
    required this.continuousCount,
    this.gapBeforeSeq,
    this.isHugeGap = false,
    this.emptyVerified = false,
    this.openGeneration = 0,
  });

  final String conversationKey;
  final List<String> mountedMessageIds;
  final ChatViewportAnchor? anchor;
  final double estimatedContentExtent;
  final double viewportTargetExtent;
  final ChatViewportCoverageState coverageState;
  final bool isContiguous;
  final bool needsLatestRepair;
  final bool reachedKnownLocalBoundary;
  final ChatViewportSource source;
  final int continuousCount;
  final int? gapBeforeSeq;
  final bool isHugeGap;
  final bool emptyVerified;
  final int openGeneration;

  /// 首屏可转场：连续，且高度够一屏，或已到达已知边界（含 EMPTY_VERIFIED）。
  bool get isViewportReady {
    if (!isContiguous) {
      return false;
    }
    if (coverageState == ChatViewportCoverageState.emptyLocal) {
      return false;
    }
    if (coverageState == ChatViewportCoverageState.emptyVerified) {
      return true;
    }
    return estimatedContentExtent >= viewportTargetExtent ||
        reachedKnownLocalBoundary;
  }

  bool get isEmptyLocal =>
      coverageState == ChatViewportCoverageState.emptyLocal;
}

/// H0 请求票：返回时校验账号 / 会话 / 开页代 / 请求锚点。
@immutable
class ChatViewportRepairTicket {
  const ChatViewportRepairTicket({
    required this.ownerUserId,
    required this.accountGeneration,
    required this.conversationKey,
    required this.openGeneration,
    this.requestAnchorMsgId,
    this.requestAnchorSeq,
  });

  final String ownerUserId;
  final int accountGeneration;
  final String conversationKey;
  final int openGeneration;
  final String? requestAnchorMsgId;
  final int? requestAnchorSeq;

  String get flightKey =>
      '$ownerUserId@$accountGeneration|$conversationKey|latest';
}
