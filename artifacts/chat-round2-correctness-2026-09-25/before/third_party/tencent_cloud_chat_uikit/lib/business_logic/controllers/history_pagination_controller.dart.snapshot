import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'history_window_replay_controller.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

enum LoadDirection { previous, latest }

enum HistoryAvailability { unknown, available, exhausted }

/// K.10：归档拉取状态枚举
enum ArchiveLoadingState { idle, fetching, completed, exhausted, error }

/// Per-conversation history pagination + archive fallback flags.
///
/// Owned by [TUIChatSeparateViewModel]. Load loops live in
/// `HistoryPaginationLoadRunner` (same library as the view model); the runner is
/// bound here so the public API is `controller.loadChatRecord(...)`.
class HistoryPaginationController {
  HistoryAvailability olderAvailability = HistoryAvailability.unknown;
  bool haveMoreLatestData = false;
  bool previousPaginationInFlight = false;

  /// 自建后端归档「更早冷历史」是否已拉到底（避免拉空后反复请求同一段）。
  bool archiveOlderExhausted = false;

  /// 是否已进入归档兜底分页（此后列表最老一条来自归档，不能再作为 SDK 锚点）。
  bool archiveOlderActive = false;

  /// Next inclusive upper Seq bound for Community archive pagination.
  /// Kept per chat page so account switches, route recreation and clear do
  /// not reuse another request's cursor.
  int? archiveNextToSeq;

  /// Community 后端签发的不透明游标及固定快照。仅在页面完成校验并合并后推进。
  String? archiveOlderCursor;
  int? archiveSnapshotMaxSeq;
  int? archiveLastAcceptedOldestSeq;
  HistoryWindowPage? archiveLastAcceptedPage;
  final HistoryWindowReplayController windowReplay =
      HistoryWindowReplayController();
  final Map<LoadDirection,
          ({String sessionID, String anchorID, HistoryWindowBoundary boundary})>
      cacheReadContinuations = {};
  final Map<String, String> archiveChecksumByRequest = <String, String>{};

  /// 历史缺口、保留期或权限错误的用户可见提示。
  String? archiveHistoryNotice;
  int archiveHistoryNoticeRevision = 0;

  /// K.10：归档拉取状态（用于聊天页顶部状态条）
  ArchiveLoadingState archiveLoadingState = ArchiveLoadingState.idle;

  void setArchiveHistoryNotice(String? value) {
    if (archiveHistoryNotice == value) return;
    archiveHistoryNotice = value;
    archiveHistoryNoticeRevision++;
  }

  /// Retryable history failures stay in diagnostics, without a sticky grey
  /// error bar (including automatic fills when history is shorter than a page).
  /// The load runner still retains its cursor and allows a later scroll retry.
  static bool shouldShowHistoryFailureNotice(String? errorType) => false;

  void resetCommunityCursor() {
    archiveOlderCursor = null;
    archiveSnapshotMaxSeq = null;
    archiveLastAcceptedOldestSeq = null;
    archiveLastAcceptedPage = null;
    windowReplay.reset();
    cacheReadContinuations.clear();
    archiveChecksumByRequest.clear();
  }

  /// 首屏 SDK 为空且未接受归档为「当前尾巴」时：禁止上拉再用归档挖旧消息。
  bool suppressArchiveUntilSdkHistory = false;

  /// Timestamp of the last empty older batch (transient SDK/network issue).
  /// After [emptyBatchRetryWindow] the haveMoreData flag can be re-armed
  /// so the user can retry scrolling up without re-entering the chat.
  DateTime? lastEmptyBatchAt;
  static const Duration emptyBatchRetryWindow = Duration(seconds: 30);

  final Set<String> historyLoadingKeys = <String>{};

  bool get isLoadingChatHistory => historyLoadingKeys.isNotEmpty;

  bool get haveMoreData => olderAvailability == HistoryAvailability.available;

  set haveMoreData(bool value) {
    olderAvailability =
        value ? HistoryAvailability.available : HistoryAvailability.exhausted;
  }

  void markHistoryUnknown() {
    olderAvailability = HistoryAvailability.unknown;
  }

  /// Returns true if the empty-batch latch should be retried (enough time
  /// has passed since the last empty batch to warrant another attempt).
  bool get emptyBatchLatchExpired =>
      lastEmptyBatchAt != null &&
      DateTime.now().difference(lastEmptyBatchAt!) >= emptyBatchRetryWindow;

  void resetForConversationInit() {
    archiveOlderExhausted = false;
    archiveOlderActive = false;
    archiveNextToSeq = null;
    resetCommunityCursor();
    setArchiveHistoryNotice(null);
    suppressArchiveUntilSdkHistory = false;
    lastEmptyBatchAt = null;
    olderAvailability = HistoryAvailability.unknown;
  }

  Future<bool> Function({
    HistoryMsgGetTypeEnum? getType,
    int lastMsgSeq,
    required int count,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    LoadDirection direction,
    bool forceReloadNewest,
  })? _loadChatRecordBound;

  void bindLoadChatRecord(
    Future<bool> Function({
      HistoryMsgGetTypeEnum? getType,
      int lastMsgSeq,
      required int count,
      String? lastMsgID,
      V2TimMessage? lastMsg,
      LoadDirection direction,
      bool forceReloadNewest,
    }) runner,
  ) {
    _loadChatRecordBound = runner;
  }

  Future<bool> loadChatRecord({
    HistoryMsgGetTypeEnum? getType,
    int lastMsgSeq = -1,
    required int count,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    LoadDirection direction = LoadDirection.previous,
    bool forceReloadNewest = false,
  }) {
    final bound = _loadChatRecordBound;
    if (bound == null) {
      throw StateError('HistoryPaginationController.loadChatRecord not bound');
    }
    return bound(
      getType: getType,
      lastMsgSeq: lastMsgSeq,
      count: count,
      lastMsgID: lastMsgID,
      lastMsg: lastMsg,
      direction: direction,
      forceReloadNewest: forceReloadNewest,
    );
  }
}
