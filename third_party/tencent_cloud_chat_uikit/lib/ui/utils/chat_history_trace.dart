import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

/// Chat history pagination / 首屏源追溯。过滤关键字：`[ChatHistory]`。
class ChatHistoryTrace {
  ChatHistoryTrace._();

  /// 历史分页 / 首屏源追溯。debug 包默认打开，便于对照 `[ChatHistory]`。
  /// profile / release 关闭；`CHAT_HISTORY_TRACE` / `CHAT_HISTORY_TRACE_FORCE` 不再开日志。
  /// Only structured `[ChatHistory]` event lines are emitted; no message body,
  /// user nickname, or real user ID is ever printed (msgID / seq / ts only).
  static const bool enabled = kDebugMode;

  /// SDK uikitTrace 仅 debug，避免 release 滚动开销。
  static const bool sdkTraceEnabled = false;

  static void log(
    String event, {
    String? conversationID,
    Map<String, Object?> extras = const <String, Object?>{},
  }) {
    if (!enabled) {
      return;
    }
    final buffer = StringBuffer('[ChatHistory] event=$event');
    final conv = conversationID?.trim() ?? '';
    if (conv.isNotEmpty) {
      buffer.write(' conv=$conv');
    }
    extras.forEach((key, value) {
      if (value == null) {
        return;
      }
      final safeValue = value.toString().replaceAll(RegExp(r'[\r\n]+'), ' ');
      buffer.write(' $key=$safeValue');
    });
    debugPrint(buffer.toString());
  }

  /// 进会话时单次 dump：消费 4 个翻页开关，避免日志里来回溯源。
  /// [olderAvailabilityIndex] 取 [HistoryAvailability].index（unknown / available / exhausted）。
  static Map<String, Object?> initDiagSummary({
    required String? conversationID,
    required bool usesOfficialSdkHistory,
    required bool isCommunity,
    required bool haveMoreData,
    required bool haveMoreLatestData,
    required int olderAvailabilityIndex,
    required bool archiveOlderExhausted,
    required bool archiveOlderActive,
    required bool suppressArchiveUntilSdkHistory,
    required int historyLoadingKeysSize,
    required bool previousPaginationInFlight,
    required DateTime? lastEmptyBatchAt,
  }) {
    return <String, Object?>{
      'usesOfficialSdk': usesOfficialSdkHistory,
      'isCommunity': isCommunity,
      'haveMoreData': haveMoreData,
      'haveMoreLatestData': haveMoreLatestData,
      'olderAvailability': olderAvailabilityIndex,
      'archiveExhausted': archiveOlderExhausted,
      'archiveActive': archiveOlderActive,
      'suppressArchiveUntilSdk': suppressArchiveUntilSdkHistory,
      'loadingKeys': historyLoadingKeysSize,
      'previousInFlight': previousPaginationInFlight,
      'emptyBatchAtMs': lastEmptyBatchAt?.millisecondsSinceEpoch,
    };
  }

  /// SDK 调用结果单行汇总：方便 grep `load_chat_record_sdk_response` 判断
  /// 到底是被 `isFinished=true` 提前关闭，还是被 dedupe / direction mismatch 误关。
  static Map<String, Object?> sdkResponseSummary({
    required int returnedCount,
    required bool isFinished,
    required String actualSource,
    String? newestMsgId,
    int? newestSeq,
    int? newestTs,
    String? oldestMsgId,
    int? oldestSeq,
    int? oldestTs,
  }) {
    return <String, Object?>{
      'count': returnedCount,
      'isFinished': isFinished,
      'actualSource': actualSource,
      'newestId': _shortMsgId(newestMsgId),
      'newestSeq': newestSeq ?? '',
      'newestTs': newestTs ?? 0,
      'oldestId': _shortMsgId(oldestMsgId),
      'oldestSeq': oldestSeq ?? '',
      'oldestTs': oldestTs ?? 0,
    };
  }

  /// 合并决策 verdict：
  ///   `decision in {grew, direction_mismatch, no_growth, shrink_rejected}`。
  static Map<String, Object?> mergeDecision({
    required String decision,
    required int commitBaseCount,
    required int dedupedCount,
    required int rawBatchCount,
    required bool isFinished,
    required bool haveMoreDataAfter,
    int? currentOldestSeq,
    int? responseNewestSeq,
  }) {
    return <String, Object?>{
      'decision': decision,
      'baseCount': commitBaseCount,
      'dedupedCount': dedupedCount,
      'rawBatchCount': rawBatchCount,
      'isFinished': isFinished,
      'haveMoreDataAfter': haveMoreDataAfter,
      'currentOldestSeq': currentOldestSeq ?? '',
      'responseNewestSeq': responseNewestSeq ?? '',
    };
  }

  /// 锚点路径：tip_rejected / official_cursor / repair_anchor / recovery_attempt / no_rewrite。
  static Map<String, Object?> anchorDecision({
    required String path,
    String? fromMsgId,
    int? fromSeq,
    String? toMsgId,
    int? toSeq,
  }) {
    return <String, Object?>{
      'path': path,
      'fromId': _shortMsgId(fromMsgId),
      'fromSeq': fromSeq ?? '',
      'toId': _shortMsgId(toMsgId),
      'toSeq': toSeq ?? '',
    };
  }

  /// 单行 dump 翻页 4 开关、闸门倒计时。
  static Map<String, Object?> paginationGate({
    required String event,
    required bool haveMoreData,
    required bool haveMoreLatestData,
    required bool archiveOlderExhausted,
    required bool archiveOlderActive,
    required bool suppressArchiveUntilSdkHistory,
    required int loadingKeysSize,
    required int emptyBatchAgeMs,
  }) {
    return <String, Object?>{
      'event': event,
      'haveMoreData': haveMoreData,
      'haveMoreLatestData': haveMoreLatestData,
      'archiveExhausted': archiveOlderExhausted,
      'archiveActive': archiveOlderActive,
      'suppressArchiveUntilSdk': suppressArchiveUntilSdkHistory,
      'loadingKeys': loadingKeysSize,
      'emptyBatchAgeMs': emptyBatchAgeMs,
    };
  }

  /// 首/尾消息摘要：count / msgId / ts / seq，用于对比 Peek 与聊天页窗口。
  static Map<String, Object?> windowSummary(
    List<V2TimMessage>? messages, {
    String prefix = 'win',
  }) {
    if (messages == null || messages.isEmpty) {
      return <String, Object?>{
        '${prefix}Count': 0,
      };
    }
    // 列表约定：通常 newest-first；取首尾各一条。
    final first = messages.first;
    final last = messages.last;
    final oldest = _olderOf(first, last);
    final newest = identical(oldest, first) ? last : first;
    return <String, Object?>{
      '${prefix}Count': messages.length,
      '${prefix}NewestId': _shortMsgId(newest.msgID),
      '${prefix}NewestTs': newest.timestamp ?? 0,
      '${prefix}NewestSeq': newest.seq ?? '',
      '${prefix}OldestId': _shortMsgId(oldest.msgID),
      '${prefix}OldestTs': oldest.timestamp ?? 0,
      '${prefix}OldestSeq': oldest.seq ?? '',
      '${prefix}ImageHttp': _countImageHttp(messages),
      '${prefix}ArchiveMarked': _countArchiveMarked(messages),
    };
  }

  static V2TimMessage _olderOf(V2TimMessage a, V2TimMessage b) {
    final at = a.timestamp ?? 0;
    final bt = b.timestamp ?? 0;
    if (at != bt) {
      return at <= bt ? a : b;
    }
    final as = int.tryParse(a.seq?.toString() ?? '') ?? 0;
    final bs = int.tryParse(b.seq?.toString() ?? '') ?? 0;
    return as <= bs ? a : b;
  }

  static String _shortMsgId(String? msgID) {
    final id = msgID?.trim() ?? '';
    if (id.length <= 28) {
      return id;
    }
    return '${id.substring(0, 12)}…${id.substring(id.length - 8)}';
  }

  static int _countImageHttp(List<V2TimMessage> messages) {
    var n = 0;
    for (final m in messages) {
      if (m.elemType != 3) {
        continue;
      }
      final list = m.imageElem?.imageList;
      if (list == null) {
        continue;
      }
      for (final img in list) {
        final url = img?.url?.trim() ?? '';
        if (url.startsWith('http://') || url.startsWith('https://')) {
          n++;
          break;
        }
      }
    }
    return n;
  }

  static int _countArchiveMarked(List<V2TimMessage> messages) {
    var n = 0;
    for (final m in messages) {
      final raw = m.localCustomData?.trim() ?? '';
      if (raw.contains('archiveHistory')) {
        n++;
      }
    }
    return n;
  }
}
