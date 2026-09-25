import 'package:tencent_cloud_chat_uikit/ui/utils/media_send_perf.dart';
import 'package:tencent_cloud_chat_demo/src/services/device_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_service.dart';
import 'dart:io' show File;
import 'package:flutter_plugin_record_plus/const/response.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_history_around_loader.dart';
import 'dart:async';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_host.dart';
import 'dart:convert';
import 'dart:math';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';

import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/outgoing_media_work_queue.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_demo/src/utils/revoked_message_preview.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_history_sync.dart';
import 'package:tencent_cloud_chat_demo/src/utils/web_chat_open_policy.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_history_sync_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/mobile_async_commit_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_send_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_draft_submission.dart';
import 'package:tencent_cloud_chat_demo/src/services/c2c_friend_message_guard.dart';
import 'package:tencent_cloud_chat_demo/src/utils/c2c_blocked_outgoing_message_sync.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_message_recreator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/read_receipt_outbox_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/tencent_conversation_read_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/c2c_peer_rejected_tip_message.dart';
import 'package:tencent_cloud_chat_demo/utils/group_mention_resolver.dart';
import 'package:tencent_cloud_chat_sdk/enum/get_group_message_read_member_list_filter.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_filter_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_role.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_priority_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/enum/offlinePushInfo.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_message_read_member_list.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_message_read_member_list.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_sound_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_sound_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_change_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_change_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_receipt.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_receipt.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_online_url.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_online_url.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_msg_create_info_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_msg_create_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_callback.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_class.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/life_cycle/chat_life_cycle.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_model_tools.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_uikit/data_services/profile/user_profile_local_bridge.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/controllers/history_pagination_controller.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_ui_state_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_coverage.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_batch.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_delta.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_identity.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/chat_composer_ui_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_conversation_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_self_info_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/friendShip/friendship_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/archive_history_provider.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_history_peek_loader.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/ui/constants/history_message_constant.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/chat_list_pagination_ui_gate.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_history_trace.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_main_thread_perf.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/outgoing_visible_probe.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_jitter_diag.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_history_open_layout_ready.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/sound_record.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/voice_auto_play_order.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/voice_auto_play_session.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/voice_message_path_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_pagination_anchor.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_pagination_continuity.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/roaming_contiguous_window.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/search_jump_latest_gate.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/logger.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/outgoing_send_status.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_anchor.dart';
import 'package:tencent_cloud_chat_demo/src/services/voice_to_text_service.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/voice_to_text_bridge.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_message_height_cache.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_gallery_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_gallery_expand.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_preview_builder.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';

export 'package:tencent_cloud_chat_uikit/business_logic/controllers/history_pagination_controller.dart'
    show LoadDirection;

part 'tui_chat_history_pagination_load.dart';
part 'tui_chat_history_live_window.dart';

class _ResolvedSendTarget {
  final String receiver;
  final String groupID;
  final String normalizedConvID;

  const _ResolvedSendTarget({
    required this.receiver,
    required this.groupID,
    required this.normalizedConvID,
  });
}

class OptimisticImagePlaceholderInput {
  const OptimisticImagePlaceholderInput({
    this.imagePath = '',
    this.imageWidth,
    this.imageHeight,
    this.sourcePending = false,
    this.batchId,
    this.batchIndex,
  });

  final String imagePath;
  final int? imageWidth;
  final int? imageHeight;
  final bool sourcePending;
  final String? batchId;
  final int? batchIndex;
}

class TUIChatSeparateViewModel extends ChangeNotifier {
  Object? _latestReturnOwner;
  String? _latestReturnConversation;
  Future<void> Function()? _latestReturnHandler;
  int? _latestViewportReturnWatermark;
  int? _latestViewportReturnGeneration;

  void bindLatestViewportReturn(Object owner, Future<void> Function() handler) {
    _latestReturnOwner = owner;
    _latestReturnConversation = conversationID;
    _latestReturnHandler = handler;
  }

  void unbindLatestViewportReturn(Object owner) {
    if (!identical(_latestReturnOwner, owner)) return;
    _latestReturnOwner = null;
    _latestReturnConversation = null;
    _latestReturnHandler = null;
  }

  /// All user return intents use the mounted viewport's transaction and proof.
  Future<bool> requestLatestViewportReturn() async {
    final handler = _latestReturnHandler;
    if (_disposed || handler == null ||
        _latestReturnConversation != conversationID) {
      return false;
    }
    await handler();
    return true;
  }

  /// 禁言诊断。完成后关闭。
  static const bool _muteDebugEnabled = false;

  /// Permanent mute sentinel. Must stay within JS safe-integer range for web.
  static const int _kPermanentMuteUntil = 0x1FFFFFFFFFFFFF;

  void _muteDebugLog(String message) {
    if (!_muteDebugEnabled) {
      return;
    }
    debugPrint(message);
  }

  final FriendshipServices _friendshipServices =
      serviceLocator<FriendshipServices>();
  final MessageService _messageService = serviceLocator<MessageService>();
  final GroupServices _groupServices = serviceLocator<GroupServices>();
  final TUIChatGlobalModel globalModel = serviceLocator<TUIChatGlobalModel>();
  final ChatUiStateStore chatUiStateStore = serviceLocator<ChatUiStateStore>();
  final TUIChatModelTools tools = serviceLocator<TUIChatModelTools>();
  final TUISelfInfoViewModel selfModel = serviceLocator<TUISelfInfoViewModel>();
  final TUIConversationViewModel conversationViewModel =
      serviceLocator<TUIConversationViewModel>();
  bool _notifyScheduled = false;
  bool _disposed = false;
  final HistoryPaginationController _pagination = HistoryPaginationController();

  /// Plain initial open policy owned by the host app. This only gates the
  /// first route load; explicit pagination, search jumps, unread recovery and
  /// reconnect reconciliation remain cloud-capable.
  bool localOnlyInitialOpen = false;

  /// 由宿主 app 注入的 entry 未读数；用于首屏动态 count（K.1）。
  /// null 表示宿主未提供，按 initialOpenFetchCount 拉取。
  int? initialUnreadCount;
  V2TimMessage? entryUnreadLastMessage;

  /// Releases the pre-first-frame remote gate.  The initial route must only
  /// read the SDK local cache; after the first frame, roaming completion and
  /// targeted gap repair are allowed to run through the shared coordinator.
  void allowRemoteHistoryAfterFirstFrame() {
    if (!localOnlyInitialOpen) {
      return;
    }
    localOnlyInitialOpen = false;
    ChatHistoryTrace.log(
      'remote_history_enabled_after_first_frame',
      conversationID: conversationID,
    );
  }

  Set<String> get _historyLoadingKeys => _pagination.historyLoadingKeys;
  bool get isLoadingChatHistory => _pagination.isLoadingChatHistory;

  ChatLifeCycle? lifeCycle;
  int _totalUnreadCount = 0;
  bool _isInit = false;
  String conversationID = "";
  ConvType? conversationType;
  final MobileAsyncCommitGuard _mediaCommitGuard = MobileAsyncCommitGuard();

  bool _isDetachedMediaSender = false;
  SessionIdentity? _outgoingMediaIdentity;

  /// Captures only send configuration, never the route's controllers, callbacks
  /// or history lifecycle. Global Writer/Outbox still own all message commits.
  TUIChatSeparateViewModel captureMediaSender({
    required String convID,
    required ConvType convType,
  }) {
    if (_isDetachedMediaSender) return this;
    final sender = TUIChatSeparateViewModel();
    sender._isDetachedMediaSender = true;
    sender._outgoingMediaIdentity = SessionIdentityService.instance.capture();
    sender.conversationID = _storageConversationId(convID);
    sender.conversationType = convType;
    sender.chatConfig = chatConfig;
    sender.showC2cMessageEditStatus = showC2cMessageEditStatus;
    if (sender.conversationID == conversationID) {
      sender._groupType = _groupType;
    }
    // This send-only model has no UI listeners and must never notify a route.
    sender._disposed = true;
    sender.suppressReadReporting = true;
    return sender;
  }

  bool get canSendCapturedMedia =>
      !_isDetachedMediaSender ||
      SessionIdentityService.instance.isCurrent(_outgoingMediaIdentity!);

  /// 所有标准 IM 会话（包括 Community）都以腾讯 SDK 历史为准。
  /// 业务会话归档/文件夹仍由宿主应用维护，但不参与消息正文读取。
  bool get usesOfficialSdkHistory {
    return conversationType == ConvType.c2c ||
        conversationType == ConvType.group;
  }

  bool get haveMoreData =>
      _pagination.haveMoreData ||
      globalModel.memoryWindowMissingOlder(conversationID);
  set haveMoreData(bool value) {
    _pagination.haveMoreData = value;
    if (!value) {
      globalModel.clearMemoryWindowMissingOlder(conversationID);
    }
  }

  HistoryAvailability get historyAvailability => _pagination.olderAvailability;

  String? get historyLoadNotice => _pagination.archiveHistoryNotice;
  int get historyLoadNoticeRevision => _pagination.archiveHistoryNoticeRevision;

  void markHistoryAvailabilityUnknown() {
    _pagination.markHistoryUnknown();
  }

  bool get haveMoreLatestData =>
      _pagination.haveMoreLatestData ||
      globalModel.memoryWindowMissingNewer(conversationID);
  set haveMoreLatestData(bool value) {
    _pagination.haveMoreLatestData = value;
    if (value) {
      globalModel.markMemoryWindowMissingNewer(conversationID);
    } else {
      globalModel.clearMemoryWindowMissingNewer(conversationID);
    }
  }

  /// 首屏 SDK 为空且未接受归档为「当前尾巴」时：禁止上拉再用归档挖旧消息
  ///（否则 tip 空会话会把已清掉的归档当成更早历史灌回来）。
  bool get _suppressArchiveUntilSdkHistory =>
      _pagination.suppressArchiveUntilSdkHistory;
  set _suppressArchiveUntilSdkHistory(bool value) =>
      _pagination.suppressArchiveUntilSdkHistory = value;

  /// 会话预加载或首屏已写入缓存时，恢复上拉分页开关。
  void syncHaveMoreDataFromCachedHistory({bool? mayHaveOlder}) {
    final cachedCount = globalModel.rawMessageCount(conversationID);
    final before = haveMoreData;
    final bool next;
    if (mayHaveOlder == true) {
      next = true;
    } else if (mayHaveOlder == false) {
      final coverage = globalModel.messageHistoryCoverageFor(conversationID);
      if (globalModel.memoryWindowMissingOlder(conversationID)) {
        haveMoreData = true;
        return;
      }
      // Persisted group exhaustion is not proof for this page's oldest
      // cursor. Keep the session state: unknown/available permits a probe,
      // while a live request's exhausted state still prevents empty loops.
      if (conversationType == ConvType.group) {
        return;
      }
      // An absent optimistic flag is not an SDK exhaustion proof. Preserve
      // one explicit user-triggered probe instead of permanently closing history.
      if (coverage?.olderExhausted != true || coverage!.hasOpenHoles) {
        _pagination.markHistoryUnknown();
        return;
      }
      next = false;
    } else {
      if (cachedCount < HistoryMessageDartConstant.initialOpenFetchCount) {
        _pagination.markHistoryUnknown();
        return;
      }
      next = true;
    }
    if (before == next) {
      return;
    }
    haveMoreData = next;
    ChatHistoryTrace.log(
      'sync_have_more_from_cache',
      conversationID: conversationID,
      extras: <String, Object?>{
        'mayHaveOlder': mayHaveOlder,
        'cachedCount': cachedCount,
        'before': before,
        'after': haveMoreData,
      },
    );
  }

  String _currentPlayedMsgId = "";
  static TUIChatSeparateViewModel? _voiceAutoPlayOwner;
  VoiceAutoPlaySession? _voiceAutoPlaySession;
  GroupReceiptAllowType? _groupType;
  // List<V2TimMessage> _multiSelectedMessageList = [];
  final ChatComposerUiState _composerUi = ChatComposerUiState();
  String _jumpMsgID = "";
  bool _isGroupExist = true;
  bool _isNotAMember = false;
  bool showC2cMessageEditStatus = true;
  TIMUIKitChatConfig chatConfig = const TIMUIKitChatConfig();

  /// 会话长按预览等只读场景：不向 SDK 上报已读，避免关闭预览时清空列表未读气泡。
  bool suppressReadReporting = false;
  ValueChanged<String>? setInputField;
  String? Function(V2TimMessage message)? abstractMessageBuilder;
  Function(String userID, TapDownDetails tapDetails)? onTapAvatar;
  V2TimGroupMemberFullInfo? _currentChatUserInfo;
  V2TimGroupInfo? _groupInfo;
  String groupMemberListSeq = "0";
  List<V2TimGroupMemberFullInfo?>? groupMemberList = [];
  V2TimGroupMemberFullInfo? selfMemberInfo;
  int _groupMemberVersion = 0;
  Map<String, String> _groupUserShowName = {};
  String? _groupID;
  final GroupSenderDisplayNameCache _groupSenderDisplayNameCache =
      GroupSenderDisplayNameCache();

  /// 进页只拉自己+首屏 sender；成员列表靠分页窗口，不再 idle 全量补齐。
  /// true 仅表示「当前分页窗口已拉完且无下一页」（小群首屏即齐），不等于万人全表在内存。
  bool groupMemberListComplete = false;
  int _idleFullMemberLoadGeneration = 0;
  Future<void>? _fullMemberLoadInFlight;
  int _openShellGeneration = 0;

  /// 搜索 / 未读 / @me 等「整窗替换」世代：在途 loadChatRecord 提交前若世代已变则丢弃，
  /// 避免把旧最新页 baseline 再 merge 回 around 窗口。
  int _historyWindowGeneration = 0;

  /// 每次进会话只调度一次满窗校对 / 洞补。

  /// 暖开历史补齐（cloud merge + 归档校对）每开一次只调度一轮。
  bool _warmOpenHistoryReconcileScheduled = false;
  bool _warmOpenTowardLocalScheduled = false;
  Timer? _fillTowardOlderHistoryResumeTimer;
  bool _lastPeekIsFinished = false;

  /// 官方续拉：上一页 SDK 返回列表的最后一条（不是整窗时间最老一条）。
  V2TimMessage? _sdkOlderPageTail;
  final _historyLiveWindow = _HistoryLiveWindow();
  Future<void>? _openShellInFlight;
  String? _openShellCompletedGid;
  static const int _openShellSenderLimit = 40;

  Map<String, String> get groupUserShowName => _groupUserShowName;

  int get groupMemberVersion => _groupMemberVersion;
  // value 的 bool 值表示是否已经延迟显示过发送进度
  final Map<String, bool> _sendingMessageIDMap = {};
  bool _reloadNewestAfterOutgoingInFlight = false;
  final Set<String> _cancelledOutgoingMediaIds = <String>{};
  Map<String, V2TimMessage> _readReceiptMap = {};
  Timer? _readReceiptFlushTimer;
  int _readReceiptRetryCount = 0;
  static const int _readReceiptRetryLimit = 6;
  Timer? _groupMarkReadDebounce;
  int _chatOpenGeneration = 0;
  Future<void>? _openProfileEnrichmentInFlight;
  List<V2TimGroupMemberFullInfo?>? _preGroupMemberListForOpen;
  int _groupMarkReadNotLoggedInRetries = 0;
  int _lastGroupMarkReadAtMs = 0;
  static const _groupMarkReadMinIntervalMs = 5000;
  static const _groupMarkReadFrequencyBlockBackoffMs = 12000;
  static const _groupMarkReadNotLoggedInRetryLimit = 5;

  bool _isChatGenerationCurrent(int generation, String convID) {
    return !_disposed &&
        generation == _chatOpenGeneration &&
        conversationID == _storageConversationId(convID);
  }

  set groupUserShowName(Map<String, String> value) {
    _groupUserShowName = value;
    _notify();
  }

  double get atPositionX => _composerUi.atPositionX;
  set atPositionX(double value) => _composerUi.atPositionX = value;

  double get atPositionY => _composerUi.atPositionY;
  set atPositionY(double value) => _composerUi.atPositionY = value;

  int get activeAtIndex => _composerUi.activeAtIndex;

  set activeAtIndex(int value) {
    if (_composerUi.activeAtIndex == value) {
      return;
    }
    _composerUi.activeAtIndex = value;
    _notify();
  }

  List<V2TimGroupMemberFullInfo?> get showAtMemberList =>
      _composerUi.showAtMemberList;

  set showAtMemberList(List<V2TimGroupMemberFullInfo?> value) {
    if (ChatComposerUiState.sameAtMemberList(
      _composerUi.showAtMemberList,
      value,
    )) {
      return;
    }
    _composerUi.showAtMemberList = value;
    _notify();
  }

  void clearAtPanelState({bool notify = true}) {
    final changed = _composerUi.clearAtPanel();
    if (changed && notify) {
      _notify();
    }
  }

  V2TimGroupInfo? get groupInfo => _groupInfo;

  set groupInfo(V2TimGroupInfo? value) {
    if (identical(_groupInfo, value)) {
      return;
    }
    // 同 groupID + 关键字段不变时不 notify，避免进场 loadGroupInfo 整表抖一下。
    final prev = _groupInfo;
    if (prev != null &&
        value != null &&
        prev.groupID == value.groupID &&
        prev.groupName == value.groupName &&
        prev.faceUrl == value.faceUrl &&
        prev.memberCount == value.memberCount &&
        prev.notification == value.notification &&
        prev.introduction == value.introduction &&
        prev.owner == value.owner &&
        prev.groupType == value.groupType) {
      _groupInfo = value;
      return;
    }
    _groupInfo = value;
    _notify();
  }

  int get totalUnreadCount => _totalUnreadCount;

  set totalUnreadCount(int value) {
    _totalUnreadCount = value;
    _notify();
  }

  bool get isMultiSelect => chatUiStateStore.isMultiSelect(conversationID);

  set isMultiSelect(bool value) {
    updateMultiSelectStatus(value);
  }

  String get currentPlayedMsgId => _currentPlayedMsgId;

  set currentPlayedMsgId(String value) {
    if (_currentPlayedMsgId == value) {
      return;
    }
    final previous = _currentPlayedMsgId;
    _currentPlayedMsgId = value;
    if (conversationID.isNotEmpty) {
      chatUiStateStore.markMessagesChanged(conversationID, <String>{
        previous,
        value,
      });
    }
    _notify();
  }

  bool get voiceAutoPlayChainEnabled => _voiceAutoPlaySession?.enabled ?? false;

  void enableVoiceAutoPlayChain({required V2TimMessage message}) {
    if (_disposed) return;
    if (_voiceAutoPlayOwner != this) {
      _voiceAutoPlayOwner?.stopVoiceAutoPlay();
    }
    disableVoiceAutoPlayChain();
    _voiceAutoPlayOwner = this;
    final conversation = conversationID;
    _voiceAutoPlaySession = VoiceAutoPlaySession(
      messagesNewestFirst: getOriginMessageList,
      loadNewer: (anchor) async {
        if (_disposed ||
            conversationID != conversation ||
            !voiceAutoPlayChainEnabled ||
            TencentUtils.checkString(anchor.msgID) == null) {
          return const <V2TimMessage>[];
        }
        // Use the existing IM history gateway; keep pagination private to voice
        // playback so an offscreen continuation does not move the chat window.
        final result = await globalModel.getHistoryMessageListThroughIm06(
          count: 40,
          getType: HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG,
          userID: conversationType == ConvType.c2c ? conversation : null,
          groupID: conversationType == ConvType.group ? conversation : null,
          lastMsgID: anchor.msgID,
          lastMsg: anchor,
        );
        if (result == null) {
          throw StateError('Voice history could not be loaded');
        }
        return result.messageList;
      },
      play: (next, isCurrent) async {
        bool valid() =>
            isCurrent() &&
            !_disposed &&
            conversationID == conversation &&
            _voiceAutoPlayOwner == this;
        if (!valid()) return true;
        final msgId = soundPlaybackId(next)!;
        final clientId = TencentUtils.checkString(next.id);
        // The same playback entry as a manual tap binds the loading message
        // immediately and invalidates async/queued work when stopped.
        await SoundPlayer.handleBubbleTap(
          messageId: msgId,
          altMessageId: clientId,
          resolveUrl: () async {
            var url =
                await VoiceMessagePathUtils.resolveLocalSoundPathWithDownload(
                  message: next,
                  globalModel: globalModel,
                  messageService: _messageService,
                );
            if (!valid()) return null;
            url ??= TencentUtils.checkString(next.soundElem?.url);
            if (url == null || url.isEmpty) return null;
            if (next.isSelf != true &&
                next.localCustomInt != HistoryMessageDartConstant.read) {
              unawaited(
                globalModel.setLocalCustomInt(
                  msgId,
                  HistoryMessageDartConstant.read,
                  conversation,
                ),
              );
              next.localCustomInt = HistoryMessageDartConstant.read;
            }
            return url;
          },
        );
        return SoundPlayer.currentPhase != VoicePlaybackPhase.idle;
      },
      onSelected: (next) => currentPlayedMsgId = soundPlaybackId(next)!,
      onWaiting: () => currentPlayedMsgId = '',
      onError: (error, stack) {
        debugPrint('Voice auto-play: $error');
      },
    )..start(message);
    SoundPlayer.addPlayerStateCallback(_onVoiceAutoPlayStateChanged);
    globalModel.addListener(_onVoiceAutoPlayMessagesChanged);
  }

  void disableVoiceAutoPlayChain() {
    _voiceAutoPlaySession?.cancel();
    SoundPlayer.removePlayerStateCallback(_onVoiceAutoPlayStateChanged);
    globalModel.removeListener(_onVoiceAutoPlayMessagesChanged);
    if (_voiceAutoPlayOwner == this) _voiceAutoPlayOwner = null;
  }

  /// Route exit/cover and conversation switches stop sound and pending work.
  void stopVoiceAutoPlay() {
    final ownsPlayback =
        _voiceAutoPlayOwner == this ||
        (currentPlayedMsgId.isNotEmpty &&
            SoundPlayer.matchesMessage(currentPlayedMsgId));
    disableVoiceAutoPlayChain();
    if (ownsPlayback) unawaited(SoundPlayer.stop());
    currentPlayedMsgId = '';
  }

  void _onVoiceAutoPlayStateChanged() {
    if (_disposed ||
        _voiceAutoPlayOwner != this ||
        SoundPlayer.currentPhase != VoicePlaybackPhase.completed) {
      return;
    }
    final id = _voiceAutoPlaySession?.currentMessageId;
    if (id != null && SoundPlayer.didJustComplete(
      id, altMessageId: _voiceAutoPlaySession?.currentClientMessageId,
    )) {
      unawaited(tryAutoPlayNextVoice(id));
    }
  }

  void _onVoiceAutoPlayMessagesChanged() {
    if (!_disposed && _voiceAutoPlayOwner == this) {
      _voiceAutoPlaySession?.messagesChanged();
    }
  }

  Future<void> tryAutoPlayNextVoice(String completedMessageId) async {
    await _voiceAutoPlaySession?.completed(completedMessageId);
  }

  GroupReceiptAllowType? get groupType => _groupType;

  set groupType(GroupReceiptAllowType? value) {
    _groupType = value;
    _notify();
  }

  bool get _isReadReceiptAllowedGroup {
    // 社群 ID 形态硬关（不依赖 _groupType 是否已加载/是否被误标为 Public）。
    final gid = (_groupID ?? conversationID).trim();
    if (_looksLikeCommunityGroupId(gid)) {
      return false;
    }
    return _groupType == GroupReceiptAllowType.work ||
        _groupType == GroupReceiptAllowType.public ||
        _groupType == GroupReceiptAllowType.meeting;
  }

  static bool _looksLikeCommunityGroupId(String? input) {
    return ChatIdFormat.looksLikeCommunityGroupId(input);
  }

  bool get _canUseReadReceipt {
    if (!chatConfig.isShowReadingStatus) {
      return false;
    }
    if (conversationType != ConvType.group) {
      return true;
    }
    return _isReadReceiptAllowedGroup;
  }

  bool get canUseReadReceipt => _canUseReadReceipt;

  Future<void> _ensureGroupInfoLoaded() async {
    if (conversationType != ConvType.group || _groupInfo != null) {
      return;
    }
    await loadGroupInfo(_groupID ?? conversationID);
  }

  List<V2TimMessage> getSelectedMessageList() {
    List<V2TimMessage> selectList = [];
    if (chatUiStateStore.selectedCount(conversationID) == 0) {
      return selectList;
    }

    List<V2TimMessage> currentHistoryMsgList = getOriginMessageList();
    for (var v2TimMessage in currentHistoryMsgList) {
      final messageKey = ChatUiStateStore.messageKeyOf(v2TimMessage);
      if (chatUiStateStore.isMessageSelected(conversationID, messageKey)) {
        selectList.add(v2TimMessage);
      }
    }

    return selectList.reversed.toList();
  }

  List<String> getSelectedMessageIDList() {
    return getSelectedMessageList()
        .map((message) => message.msgID ?? '')
        .where((msgID) => msgID.isNotEmpty)
        .toList();
  }

  V2TimMessage? get repliedMessage => _composerUi.repliedMessage;

  set repliedMessage(V2TimMessage? value) {
    _composerUi.repliedMessage = value;
    _notify();
  }

  String get jumpMsgID => _jumpMsgID;

  set jumpMsgID(String value) {
    _jumpMsgID = value;
    _notify();
  }

  bool get isGroupExist => _isGroupExist;

  set isGroupExist(bool value) {
    setGroupExist(value);
  }

  void setGroupExist(bool value, {bool notify = true}) {
    if (_isGroupExist == value) {
      return;
    }
    _isGroupExist = value;
    if (notify) {
      _notify();
    }
  }

  bool get isNotAMember => _isNotAMember;

  set isNotAMember(bool value) {
    _isNotAMember = value;
    _notify();
  }

  V2TimGroupMemberFullInfo? get currentChatUserInfo => _currentChatUserInfo;

  set currentChatUserInfo(V2TimGroupMemberFullInfo? value) {
    _currentChatUserInfo = value;
    _notify();
  }

  setLoadingMessageMap(String conversationID, V2TimMessage messageInfo) {
    if (PlatformUtils().isWeb) {
      if (globalModel.loadingMessage[conversationID] != null &&
          globalModel.loadingMessage[conversationID]!.isNotEmpty) {
        globalModel.loadingMessage[conversationID]!.add(messageInfo);
      } else {
        globalModel.loadingMessage[conversationID] = <V2TimMessage>[
          messageInfo,
        ];
      }
    }
  }

  void getUserShowName(List<String> userIDs) async {
    final generation = _chatOpenGeneration;
    final scheduledConversationID = conversationID;
    final List<String> filteredList = userIDs
        .where((element) => !_groupUserShowName.containsKey(element))
        .toList();
    for (final element in filteredList) {
      _groupUserShowName[element] = element;
    }

    final String groupID = TencentUtils.checkString(_groupID) ?? conversationID;

    if (filteredList.isNotEmpty) {
      final res = await TencentImSDKPlugin.manager
          ?.getGroupManager()
          .getGroupMembersInfo(groupID: groupID, memberList: filteredList);
      if (!_isChatGenerationCurrent(generation, scheduledConversationID)) {
        return;
      }
      if (res?.code == 0 && res?.data != null) {
        final data = res!.data!;
        GroupMemberStore.instance.putMembers(groupID, data);
        for (final userInfo in data) {
          final showName = resolveGroupSenderShowName(
            friendRemark: userInfo.friendRemark,
            nameCard: userInfo.nameCard,
            nickName: userInfo.nickName,
            storeName: DisplayNameStore.instance.c2c(userInfo.userID),
            userID: userInfo.userID,
          );
          if (TencentUtils.checkString(showName) != null) {
            _groupUserShowName[userInfo.userID] = showName;
          }
        }
        if (data.isNotEmpty) {
          _groupMemberVersion++;
          _notify();
        }
      }
    }
  }

  void initForEachConversation(
    ConvType convType,
    String convID,
    ValueChanged<String>? onChangeInputField, {
    String? groupID,
    String? groupType,
    List<V2TimGroupMemberFullInfo?>? preGroupMemberList,
  }) async {
    if (_isInit) {
      syncHaveMoreDataFromCachedHistory(
        mayHaveOlder: globalModel.mayHaveOlderHistory(conversationID),
      );
      return;
    }
    setInputField = onChangeInputField;
    conversationType = convType;
    _groupType = null;
    if (convType == ConvType.group) {
      final normalizedGroupType = groupType?.trim().toLowerCase();
      _groupType = switch (normalizedGroupType) {
        'meeting' => GroupReceiptAllowType.meeting,
        'public' => GroupReceiptAllowType.public,
        'work' => GroupReceiptAllowType.work,
        'community' => GroupReceiptAllowType.community,
        _ => null,
      };
    }
    // 消息列表 / hydrate / 归档一律用裸会话 ID（@TGS#…），勿带 group_。
    final previousConversationID = conversationID;
    conversationID = _storageConversationId(convID);
    if (previousConversationID != conversationID) {
      _mediaCommitGuard.advanceConversation();
    }
    _disposed = false;
    final initGeneration = ++_chatOpenGeneration;
    final initConversationID = conversationID;
    // Establish the visit boundary before the first await or incoming callback.
    // Failure keeps the baseline pending; admission/return retries it in order.
    unawaited(globalModel.beginHistoryUnreadVisit(conversationID).catchError(
      (Object error, StackTrace stack) {
        ChatHistoryTrace.log('unread_visit_baseline_retry_required',
            conversationID: initConversationID);
      },
    ));
    _preGroupMemberListForOpen = preGroupMemberList;
    _openProfileEnrichmentInFlight = null;
    _pagination.resetForConversationInit();

    var warmOnStorage = globalModel.rawMessageCount(conversationID);
    final warmOnRaw = globalModel.rawMessageCount(convID);
    final idMismatchRisk = warmOnStorage == 0 && warmOnRaw > 0;
    ChatHistoryTrace.log(
      'init_conv',
      conversationID: conversationID,
      extras: <String, Object?>{
        'rawConvID': convID,
        'warmOnStorage': warmOnStorage,
        'warmOnRaw': warmOnRaw,
        'loadedStorage': globalModel.hasInitialHistoryLoaded(conversationID),
        'loadedRaw': globalModel.hasInitialHistoryLoaded(convID),
        'idMismatchRisk': idMismatchRisk,
      },
    );

    // 暖窗写在 raw/group_ 桶、页面已收成裸 storageId：迁到 storage，避免假空。
    if (idMismatchRisk) {
      final aliasWindow = globalModel.rawMessageList(convID);
      if (aliasWindow != null && aliasWindow.isNotEmpty) {
        final historyIsCurrent = _historyPublicationFence();
        final authoritative = await globalModel.applyHistoryWindowMutations(
            conversationID, List<V2TimMessage>.from(aliasWindow));
        if (!historyIsCurrent()) return;
        final commit = globalModel.setMessageList(
          conversationID,
          authoritative,
          needResetNewMessageCount: false,
          replace: true,
        );
        globalModel.markInitialHistoryLoaded(conversationID);
        final mayOlder = globalModel.mayHaveOlderHistory(convID) ||
            aliasWindow.length >=
                HistoryMessageDartConstant.initialOpenFetchCount;
        globalModel.markInitialHistoryMayHaveOlder(
          conversationID,
          mayHaveOlder: mayOlder,
        );
        warmOnStorage = commit.rawCount;
        ChatHistoryTrace.log(
          'init_conv_migrate_alias_window',
          conversationID: conversationID,
          extras: <String, Object?>{
            'fromKey': convID,
            'toKey': conversationID,
            'count': aliasWindow.length,
            'mayHaveOlder': mayOlder,
            'warmOnStorageAfter': warmOnStorage,
          },
        );
      }
    }

    if (globalModel.hasInitialHistoryLoaded(conversationID) &&
        globalModel.rawMessageCount(conversationID) > 0) {
      final mayOlder = globalModel.mayHaveOlderHistory(conversationID);
      haveMoreData = mayOlder ||
          globalModel.rawMessageCount(conversationID) >=
              HistoryMessageDartConstant.initialOpenFetchCount;
    } else if (globalModel.hasInitialHistoryLoaded(convID) &&
        globalModel.rawMessageCount(convID) > 0) {
      // 兼容进页瞬间仍用旧 key（group_）写暖窗的情况。
      final mayOlder = globalModel.mayHaveOlderHistory(convID);
      haveMoreData = mayOlder ||
          globalModel.rawMessageCount(convID) >=
              HistoryMessageDartConstant.initialOpenFetchCount;
    } else {
      _pagination.markHistoryUnknown();
    }
    haveMoreLatestData = false;

    isGroupExist = true;
    _groupInfo = null;
    groupMemberList = null;
    selfMemberInfo = null;
    groupMemberListComplete = false;
    _idleFullMemberLoadGeneration++;
    _fullMemberLoadInFlight = null;
    _openShellGeneration++;
    _openShellInFlight = null;
    _openShellCompletedGid = null;
    _warmOpenHistoryReconcileScheduled = false;
    _warmOpenTowardLocalScheduled = false;
    _fillTowardOlderHistoryResumeTimer?.cancel();
    _fillTowardOlderHistoryResumeTimer = null;
    _lastPeekIsFinished = false;
    _sdkOlderPageTail = null;

    globalModel.setCurrentConversation(
      CurrentConversation(conversationID, conversationType ?? ConvType.c2c),
      notify: false,
    );
    globalModel.lifeCycle = lifeCycle;
    if (globalModel.hasPendingScrollRestore(conversationID)) {
      globalModel.setMessageListPosition(
        conversationID,
        HistoryMessagePosition.notShowLatest,
        notify: false,
      );
    } else {
      globalModel.setMessageListPosition(
        conversationID,
        HistoryMessagePosition.bottom,
        notify: false,
      );
    }
    globalModel.setChatConfig(chatConfig);

    if (globalModel.hasInitialHistoryLoaded(convID) &&
        globalModel.rawMessageCount(convID) > 0) {
      syncHaveMoreDataFromCachedHistory(
        mayHaveOlder: globalModel.mayHaveOlderHistory(convID),
      );
    }

    if (conversationType == ConvType.group) {
      _groupID = groupID;
      final resolvedGroupId = groupID ?? convID;
      final selfId = selfModel.loginInfo?.userID?.trim() ?? '';
      if (selfId.isNotEmpty) {
        final cachedSelf = GroupMemberStore.instance.memberOf(
          resolvedGroupId,
          selfId,
        );
        if (cachedSelf != null) {
          selfMemberInfo = cachedSelf;
        }
      }
      final skipOpenNotify = globalModel.hasInitialHistoryLoaded(convID) &&
          globalModel.rawMessageCount(convID) > 0;
      if (!skipOpenNotify) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_isChatGenerationCurrent(initGeneration, initConversationID)) {
            _notify();
          }
        });
      }
    }

    globalModel.removeRoamingSyncListener(_onRoamingSyncFinished);
    globalModel.addRoamingSyncListener(_onRoamingSyncFinished);
    _isInit = true;
  }

  /// Runs profile/member work only after the host chat reaches Interactive.
  /// It is single-flight for the current conversation generation.
  Future<void> runPostOpenProfileEnrichment() {
    final inFlight = _openProfileEnrichmentInFlight;
    if (inFlight != null) return inFlight;
    final generation = _chatOpenGeneration;
    final scheduledConversationID = conversationID;
    final task = _runPostOpenProfileEnrichmentImpl(
      generation: generation,
      scheduledConversationID: scheduledConversationID,
    );
    _openProfileEnrichmentInFlight = task;
    return task.whenComplete(() {
      if (identical(_openProfileEnrichmentInFlight, task)) {
        _openProfileEnrichmentInFlight = null;
      }
    });
  }

  Future<void> _runPostOpenProfileEnrichmentImpl({
    required int generation,
    required String scheduledConversationID,
  }) async {
    bool current() =>
        _isChatGenerationCurrent(generation, scheduledConversationID);
    if (!current()) return;
    if (conversationType == ConvType.group) {
      globalModel.refreshGroupApplicationList();
      final resolvedGid = _groupID ?? scheduledConversationID;
      await loadGroupInfo(resolvedGid);
      if (!current()) return;
      final preloaded = _preGroupMemberListForOpen;
      if (preloaded != null) {
        groupMemberList = List<V2TimGroupMemberFullInfo?>.from(preloaded);
        GroupMemberStore.instance.putMembers(resolvedGid, preloaded);
        final fromList = preloaded.firstWhereOrNull(
          (member) => member?.userID == selfModel.loginInfo?.userID,
        );
        if (fromList != null) {
          selfMemberInfo = _mergeSelfMemberPreservingActiveMute(
            existing: selfMemberInfo,
            incoming: fromList,
          );
        }
        groupMemberListComplete = true;
      } else {
        if (selfMemberInfo == null) {
          await loadSelfMemberInfo(groupID: resolvedGid);
          if (!current()) return;
        }
      }
      if (current() && selfMemberInfo == null) {
        await loadSelfMemberInfo(groupID: resolvedGid);
      }
      return;
    }
    final friendRes = await _friendshipServices.getFriendsInfo(
      userIDList: <String>[scheduledConversationID],
    );
    if (!current()) return;
    if (friendRes != null && friendRes.isNotEmpty) {
      final friend = friendRes.first.friendInfo;
      currentChatUserInfo = V2TimGroupMemberFullInfo(
        userID: scheduledConversationID,
        faceUrl: friend?.userProfile?.faceUrl,
        nickName: friend?.userProfile?.nickName,
        friendRemark: friend?.friendRemark,
      );
    } else {
      final users = await _friendshipServices.getUsersInfo(
        userIDList: <String>[scheduledConversationID],
      );
      if (!current()) return;
      if (users != null && users.isNotEmpty) {
        currentChatUserInfo = V2TimGroupMemberFullInfo(
          userID: scheduledConversationID,
          faceUrl: users.first.faceUrl,
          nickName: users.first.nickName,
        );
      }
    }
    if (current()) _notify();
  }

  void _onRoamingSyncFinished() {
    unawaited(reconcileAfterRoamingSync());
  }

  /// 90 天漫游入库后：重拉最新连续窗，并用云端把中间洞补上再与旧本地合并。
  Future<void> reconcileAfterRoamingSync() async {
    if (_disposed || !_isInit) {
      return;
    }
    allowRemoteHistoryAfterFirstFrame();
    await ConversationHistorySyncCoordinator.instance.reconcileConversation(
      conversationID: conversationID,
      reason: 'roaming_sync',
    );
  }

  /// 作废在途分页，准备用 around 窗口整表替换当前列表。
  void _beginHistoryWindowReplace({String reason = 'around_seq'}) {
    _historyWindowGeneration++;
    ChatHistoryTrace.log(
      'history_window_replace_begin',
      conversationID: conversationID,
      extras: <String, Object?>{
        'generation': _historyWindowGeneration,
        'reason': reason,
      },
    );
  }

  Future<bool> loadListForSpecificMessage({
    MessageAnchor? anchor,
    int? seq,
    V2TimMessage? targetMessage,
    int? searchJumpRequest,
  }) async {
    bool isCurrentSearch() =>
        searchJumpRequest == null ||
        (globalModel.isCurrentSearchJumpRequest(
                conversationID, searchJumpRequest) &&
            globalModel.getSearchJumpStatus(conversationID) !=
                SearchJumpStatus.failed);
    if (!isCurrentSearch()) return false;
    bool tempHaveMoreData = false;
    bool tempHaveMoreLatestData = true;

    // 直接定位目标页：作废在途翻页，禁止「从最新一路查」与旧窗口 merge。
    final expectedLatest = _newestHistoryRow([
      ...?globalModel.rawMessageList(conversationID),
      if (entryUnreadLastMessage != null) entryUnreadLastMessage!,
    ]);
    _beginHistoryWindowReplace(reason: 'load_list_for_specific_message');
    final windowGen = _historyWindowGeneration;
    final historyIsCurrent = _historyPublicationFence();

    final resolvedAnchor = anchor ??
        MessageAnchor(
          conversationID: conversationID,
          convType: conversationType?.index ?? 0,
          seq: seq == null || seq <= 0 ? null : seq.toString(),
          msgID: TencentUtils.checkString(targetMessage?.msgID),
          localID: TencentUtils.checkString(targetMessage?.id),
          timestamp: targetMessage?.timestamp,
          sender: targetMessage?.sender ?? targetMessage?.userID,
          elemType: targetMessage?.elemType,
        );
    var resolvedTarget = targetMessage;
    final targetMsgID = TencentUtils.checkString(resolvedAnchor.msgID) ??
        TencentUtils.checkString(targetMessage?.msgID);
    final targetSeq =
        resolvedAnchor.seqInt ?? seq ?? int.tryParse(targetMessage?.seq ?? '');

    if (resolvedTarget == null && targetMsgID != null) {
      final found = await _messageService.findMessages(
        messageIDList: <String>[targetMsgID],
      );
      if (found != null && found.isNotEmpty) {
        resolvedTarget = found.first;
      }
    }

    // 腾讯云官方「跳转到群 @」：OLDER/NEWER 都用 lastMsgSeq=target（含自身）。
    // 远跳只拉目标前后一页，不边翻边找。
    // 文档：https://cloud.tencent.com/document/product/269/75323
    Future<V2TimMessageListResult?> fetch(
      HistoryMsgGetTypeEnum getType, {
      int? count,
      required int lastMsgSeqValue,
      List<int>? messageSeqList,
      V2TimMessage? lastMsgValue,
      String? lastMsgIDValue,
    }) {
      if (!historyIsCurrent()) return Future.value(null);
      final resolvedCount = count ?? HistoryMessageDartConstant.getCount;
      final useSeqList = messageSeqList != null && messageSeqList.isNotEmpty;
      return globalModel.getHistoryMessageListThroughIm06(
        count: resolvedCount,
        getType: getType,
        userID: conversationType == ConvType.c2c ? conversationID : null,
        groupID: conversationType == ConvType.group ? conversationID : null,
        lastMsgID: useSeqList ? null : lastMsgIDValue,
        lastMsgSeq: useSeqList ? -1 : lastMsgSeqValue,
        lastMsg: useSeqList ? null : lastMsgValue,
        messageSeqList: messageSeqList,
      );
    }

    // 群聊：先 messageSeqList 钉住目标，再按 lastMsgSeq 拉前后页（官方示例）。
    if (targetSeq != null &&
        targetSeq > 0 &&
        conversationType == ConvType.group &&
        resolvedTarget == null) {
      final pinned = await fetch(
        HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
        count: 1,
        lastMsgSeqValue: -1,
        messageSeqList: <int>[targetSeq],
      );
      final pinnedList = pinned?.messageList ?? const <V2TimMessage>[];
      if (pinnedList.isNotEmpty) {
        resolvedTarget = pinnedList.firstWhere(
          (m) => (int.tryParse(m.seq?.trim() ?? '') ?? 0) == targetSeq,
          orElse: () => pinnedList.first,
        );
      }
    }

    if (!historyIsCurrent() ||
        !isCurrentSearch() ||
        windowGen != _historyWindowGeneration) {
      return false;
    }

    // 官方：两侧都用 lastMsgSeq=target（含自身）。有 msgID 时仍优先 seq，
    // 避免 lastMsg 语义（不含自身）与续拉污染。
    final aroundSeq = max(
      targetSeq ?? int.tryParse(resolvedTarget?.seq ?? '') ?? 0,
      0,
    );
    if (aroundSeq <= 0 && targetMsgID == null) {
      return false;
    }

    Future<V2TimMessageListResult?> readSide(bool newer) =>
        MessageHistoryAroundLoader.loadSide(
          read: (getType, {required lastMsgSeq, lastMsgID, lastMsg}) => fetch(
            getType,
            lastMsgSeqValue: lastMsgSeq,
            lastMsgIDValue: lastMsgID,
            lastMsgValue: lastMsg,
          ),
          isGroup: conversationType == ConvType.group,
          newer: newer,
          targetSeq: aroundSeq,
          targetMsgID: targetMsgID,
          targetMessage: resolvedTarget,
        );
    // Both sides use the same immutable cursor and are independent. A slow
    // cloud side must not delay starting the other side or its local fallback.
    final sides = await Future.wait([readSide(false), readSide(true)]);
    final previousResponse = sides[0];
    final nextResponse = sides[1];
    if (!historyIsCurrent() ||
        !isCurrentSearch() ||
        windowGen != _historyWindowGeneration) return false;
    final olderList = previousResponse?.messageList ?? <V2TimMessage>[];
    final newerList = nextResponse?.messageList ?? <V2TimMessage>[];
    tempHaveMoreData = olderList.isNotEmpty ||
        !(previousResponse?.isFinished ?? false);
    tempHaveMoreLatestData = !(nextResponse?.isFinished ?? false);

    // lastMsgSeq 两侧通常已含 target；lastMsg/msgID 路径不含，需补锚点。
    final anchorMsg = resolvedTarget ?? targetMessage;
    bool sideHasAnchor(List<V2TimMessage> side) {
      if (anchorMsg == null) {
        return false;
      }
      final aId = TencentUtils.checkString(anchorMsg.msgID);
      final aSeq = int.tryParse(anchorMsg.seq?.trim() ?? '') ?? 0;
      for (final m in side) {
        final id = TencentUtils.checkString(m.msgID);
        if (aId != null && id != null && id == aId) {
          return true;
        }
        final s = int.tryParse(m.seq?.trim() ?? '') ?? 0;
        if (aSeq > 0 && s == aSeq) {
          return true;
        }
      }
      return false;
    }

    final merged = <V2TimMessage>[
      ...newerList.reversed,
      if (anchorMsg != null &&
          !sideHasAnchor(olderList) &&
          !sideHasAnchor(newerList))
        anchorMsg,
      ...olderList,
    ];

    var msgList = await globalModel.applyHistoryWindowMutations(
        conversationID, _dedupeMessages(merged));
    if (!historyIsCurrent()) return false;
    // Seq-only jump: keep the around-window even if exact string match misses
    // (e.g. formatting). Prefer numeric seq equality; otherwise keep closest.
    if (msgList.isNotEmpty &&
        !msgList.any(resolvedAnchor.matches) &&
        anchorMsg == null) {
      final want = resolvedAnchor.seqInt;
      if (want != null && want > 0) {
        V2TimMessage? closest;
        var bestDelta = 1 << 30;
        for (final m in msgList) {
          final s = int.tryParse(m.seq?.trim() ?? '') ?? 0;
          if (s <= 0) {
            continue;
          }
          final d = (s - want).abs();
          if (d < bestDelta) {
            bestDelta = d;
            closest = m;
          }
        }
        if (closest == null) {
          msgList = <V2TimMessage>[];
        }
      } else {
        msgList = <V2TimMessage>[];
      }
    }
    if (msgList.isEmpty) {
      haveMoreData = tempHaveMoreData;
      haveMoreLatestData = tempHaveMoreLatestData;
      ChatHistoryTrace.log(
        'around_seq_load_empty',
        conversationID: conversationID,
        extras: <String, Object?>{
          'targetSeq': targetSeq,
          'older': olderList.length,
          'newer': newerList.length,
        },
      );
      return false;
    }

    // 搜索/未读跳转进入历史定位态；远跳后一定还有更新消息可下翻。
    haveMoreLatestData = true;
    globalModel.setMessageListPosition(
      conversationID,
      HistoryMessagePosition.notShowLatest,
    );

    msgList = await lifeCycle?.didGetHistoricalMessageList(msgList) ?? msgList;
    if (!historyIsCurrent() ||
        !isCurrentSearch() ||
        windowGen != _historyWindowGeneration) return false;
    msgList = await globalModel.applyHistoryWindowMutations(
        conversationID, _dedupeMessages(msgList));
    if (!historyIsCurrent()) return false;
    final matched = msgList.any(resolvedAnchor.matches) ||
        (resolvedAnchor.seqInt != null &&
            msgList.any((m) {
              final s = int.tryParse(m.seq?.trim() ?? '') ?? 0;
              return s > 0 && s == resolvedAnchor.seqInt;
            }));
    if (!matched && targetMessage != null) {
      haveMoreData = tempHaveMoreData;
      haveMoreLatestData = tempHaveMoreLatestData;
      return false;
    }
    if (!matched && msgList.isEmpty) {
      haveMoreData = tempHaveMoreData;
      haveMoreLatestData = tempHaveMoreLatestData;
      return false;
    }
    // 远跳：窗口须覆盖目标 seq；若该 seq 已删/无效，允许 ±20 近邻（仍远好于最新页误命中）。
    if (targetSeq != null && targetSeq > 0 && targetMessage == null) {
      var bestDelta = 1 << 30;
      var hasExact = false;
      for (final m in msgList) {
        final s = int.tryParse(m.seq?.trim() ?? '') ?? 0;
        if (s <= 0) {
          continue;
        }
        if (s == targetSeq) {
          hasExact = true;
          break;
        }
        final d = (s - targetSeq).abs();
        if (d < bestDelta) {
          bestDelta = d;
        }
      }
      if (!hasExact && bestDelta > 20) {
        ChatHistoryTrace.log(
          'around_seq_load_missing_target',
          conversationID: conversationID,
          extras: <String, Object?>{
            'targetSeq': targetSeq,
            'bestDelta': bestDelta == (1 << 30) ? null : bestDelta,
            'winCount': msgList.length,
            'winOldest': msgList.isEmpty ? null : msgList.last.seq,
            'winNewest': msgList.isEmpty ? null : msgList.first.seq,
          },
        );
        haveMoreData = tempHaveMoreData;
        haveMoreLatestData = tempHaveMoreLatestData;
        return false;
      }
    }
    if (!historyIsCurrent() ||
        !isCurrentSearch() ||
        windowGen != _historyWindowGeneration) {
      return false;
    }

    _installHistoryReadingWindow(msgList, expectedLatest);
    // 整表替换为目标页；禁止与最新页 merge。上下滑再按需 loadPrevious/loadLatest。
    globalModel.setMessageList(
      conversationID,
      msgList,
      needResetNewMessageCount: false,
      replace: true,
      applyMemoryWindow: false,
      memoryWindowAnchorSeq:
          targetSeq != null && targetSeq > 0 ? targetSeq.toString() : null,
      memoryWindowAnchorMsgID: TencentUtils.checkString(
        (resolvedTarget ?? targetMessage)?.msgID,
      ),
    );

    await _ensureGroupInfoLoaded();
    if (!historyIsCurrent() ||
        !isCurrentSearch() ||
        windowGen != _historyWindowGeneration) return false;

    if (_canUseReadReceipt) {
      _getMsgReadReceipt(msgList);
    }

    // 目标页两侧都还可续拉：上滑更早、下滑更新。
    // A short older side still needs a continuation probe from its accepted tail.
    haveMoreData = tempHaveMoreData;
    // Native adapters may synthesize isFinished from a short local page.
    // It cannot close a gap to an already-known newer conversation message.
    haveMoreLatestData = tempHaveMoreLatestData || _historyKnownTipMissing;
    // Every subsequent page must continue from the newly installed window.
    _pagination.resetCommunityCursor();
    _pagination.archiveNextToSeq = null;
    _pagination.lastEmptyBatchAt = null;
    _sdkOlderPageTail = null;
    _rememberSdkOlderPage(olderList);
    _notify();
    ChatHistoryTrace.log(
      'around_seq_load_ok',
      conversationID: conversationID,
      extras: <String, Object?>{
        'targetSeq': targetSeq,
        'winCount': msgList.length,
        'winOldest': msgList.isEmpty ? null : msgList.last.seq,
        'winNewest': msgList.isEmpty ? null : msgList.first.seq,
        'haveMoreLatest': haveMoreLatestData,
        'haveMoreOlder': haveMoreData,
        'windowGen': windowGen,
        'replaced': true,
      },
    );
    return true;
  }

  /// 去掉 `group_` / `c2c_` 前缀，供 SDK / 归档 API / messageListMap 共用。
  static String _storageConversationId(String? raw) {
    var id = raw?.trim() ?? '';
    if (id.isEmpty) {
      return '';
    }
    final lower = id.toLowerCase();
    if (lower.startsWith('group_')) {
      return id.substring(6);
    }
    if (lower.startsWith('c2c_')) {
      return id.substring(4);
    }
    if (id.startsWith('GROUP')) {
      return id.substring(5);
    }
    if (id.startsWith('C2C')) {
      return id.substring(3);
    }
    return id;
  }

  /// 在「候选 keep-empty」前提下，返回应拒绝的原因；`null` 表示允许确认空。
  ///
  /// 调用方须已确认：`warmLoaded && warmCount==0 && !mayHaveOlder && !inFlight`。
  @visibleForTesting
  static String? hydrateKeepEmptyRejectReason({
    required int warmCountBare,
    required int warmCountGroup,
    required bool hasNonTipPreviewEvidence,
    required bool inClearGrace,
  }) {
    if (warmCountBare > 0 || warmCountGroup > 0) {
      return 'alias_nonzero';
    }
    if (hasNonTipPreviewEvidence) {
      return 'preview_evidence';
    }
    if (inClearGrace) {
      return 'clear_grace';
    }
    return null;
  }

  /// 聊天页空拉兜底：选中会话是否与当前 chat conversationID 同一会话。
  static bool selectedConversationMatchesChatId({
    required String conversationID,
    String? selectedUserID,
    String? selectedGroupID,
    String? selectedConversationID,
  }) {
    final chatId = conversationID.trim();
    if (chatId.isEmpty) {
      return false;
    }
    return TUIChatGlobalModel.isSameConversationIdForHistory(
          selectedUserID,
          chatId,
        ) ||
        TUIChatGlobalModel.isSameConversationIdForHistory(
          selectedGroupID,
          chatId,
        ) ||
        TUIChatGlobalModel.isSameConversationIdForHistory(
          selectedConversationID,
          chatId,
        );
  }

  String _historyRequestKey({
    required HistoryMsgGetTypeEnum? getType,
    required int lastMsgSeq,
    required int count,
    required String? lastMsgID,
    required LoadDirection direction,
  }) {
    final canonical = TUIChatGlobalModel.canonicalHistoryStorageKey(
      conversationID,
    );
    return '${canonical.isEmpty ? conversationID : canonical}|${conversationType?.index}|${getType ?? ''}|$lastMsgSeq|$count|${lastMsgID ?? ''}|${direction.index}|$_historyWindowGeneration';
  }

  List<V2TimMessage> _dedupeMessages(List<V2TimMessage> messages) {
    return TUIChatGlobalModel.dedupeMessages(messages);
  }

  V2TimMessage? _resolvePaginationAnchorInMemory({
    String? lastMsgID,
    int lastMsgSeq = -1,
  }) {
    final list = globalModel.mergedAliasMessageList(conversationID);
    if (list == null || list.isEmpty) {
      return null;
    }
    final normalizedMsgID = lastMsgID?.trim() ?? '';
    if (normalizedMsgID.isNotEmpty) {
      for (final message in list) {
        if (message.msgID?.trim() == normalizedMsgID) {
          return message;
        }
      }
    }
    if (lastMsgSeq > 0) {
      for (final message in list) {
        final seq = int.tryParse(message.seq?.toString() ?? '') ?? -1;
        if (seq == lastMsgSeq) {
          return message;
        }
      }
    }
    return null;
  }

  /// K.5：按 msgID 精确查找消息（本地命中优先）。
  /// 用于 @me / 未读第一条 / 搜索结果定位等跳转场景。
  Future<V2TimMessage?> findMessageByID(String msgID) async {
    if (msgID.isEmpty) return null;
    try {
      final local =
          await _messageService.findMessages(messageIDList: <String>[msgID]);
      if (local != null && local.isNotEmpty) {
        return local.first;
      }
    } catch (_) {
      // 本地查询失败不阻断云端
    }
    return null;
  }

  List<V2TimMessage> _mergeWithInMemoryHistory(List<V2TimMessage> fetched) {
    final existing = globalModel.mergedAliasMessageList(conversationID);
    if (conversationType == ConvType.group && existing.isNotEmpty) {
      final continuity = HistoryPaginationContinuity.canAppendOlderBatch(
        existingNewestFirst: [
          for (final message in existing)
            (
              seq: int.tryParse(message.seq?.trim() ?? ''),
              msgID: message.msgID?.trim(),
            ),
        ],
        incomingOlderNewestFirst: [
          for (final message in fetched)
            (
              seq: int.tryParse(message.seq?.trim() ?? ''),
              msgID: message.msgID?.trim(),
            ),
        ],
        isGroup: true,
        olderCloudBacked: usesOfficialSdkHistory,
      );
      if (!continuity.canMerge) {
        ChatHistoryTrace.log(
          'merge_in_memory_rejected_seq_gap',
          conversationID: conversationID,
          extras: continuity.toTraceExtras(),
        );
        if (continuity.hasClosedGap) {
          globalModel.noteRejectedOlderPageGap(
            conversationID: conversationID,
            missingLowerSeq: continuity.missingLowerSeq,
            missingUpperSeq: continuity.missingUpperSeq,
          );
        }
        return List<V2TimMessage>.of(existing);
      }
    }
    if (usesOfficialSdkHistory) {
      return TUIChatGlobalModel.mergeC2cOfficialOlderPage(
        existing: existing,
        fetched: fetched,
      );
    }
    return TUIChatGlobalModel.mergeHistoricalWithInMemory(
      existing: existing,
      fetched: fetched,
    );
  }

  /// 首屏 refetch 批次的稳定签名：同一窗口重复拉取时跳过重复 commit。
  /// 只取跨轮稳定的可比字段，不含本地自增 id（每次实例化会变）。
  String _peekWindowBatchSignature(List<V2TimMessage> messages) {
    final buffer = StringBuffer()
      ..write(messages.length)
      ..write(';');
    for (final message in messages) {
      buffer
        ..write(message.msgID ?? '')
        ..write(':')
        ..write(message.seq ?? '')
        ..write(':')
        ..write(message.timestamp ?? '')
        ..write(':')
        ..write(message.status ?? '')
        ..write(';');
    }
    return buffer.toString();
  }

  /// Lets the list reject cleanup belonging to a replaced history window.
  bool Function() captureHistoryWindowPublicationFence() =>
      _historyPublicationFence();

  /// Captured before transport/lifecycle awaits, including clear and account scope.
  bool Function() _historyPublicationFence() {
    final conv = conversationID;
    final window = _historyWindowGeneration;
    final chat = _chatOpenGeneration;
    final clear = globalModel.messageDeltaClearEpochFor(conv);
    final scope = globalModel.historyWindowScopeFor(conv);
    final owner = globalModel.im06WriterOwnerUserID;
    final account = globalModel.im06WriterAccountGeneration;
    final domain = globalModel.im06WriterDomainGeneration;
    return () =>
        !_disposed &&
        conversationID == conv &&
        _historyWindowGeneration == window &&
        _chatOpenGeneration == chat &&
        globalModel.messageDeltaClearEpochFor(conv) == clear &&
        globalModel.im06WriterOwnerUserID == owner &&
        globalModel.im06WriterAccountGeneration == account &&
        globalModel.im06WriterDomainGeneration == domain &&
        (scope == null || globalModel.isHistoryWindowScopeCurrent(scope));
  }

  Future<bool> _commitHistoricalMessages(
    List<V2TimMessage> fetched, {
    bool markInitialLoaded = false,
    bool? mayHaveOlder,
    bool replaceWithPeekWindow = false,
    bool Function()? requestIsCurrent,
  }) async {
    final isCurrent = requestIsCurrent ?? _historyPublicationFence();
    if (!isCurrent()) return false;
    final conv = conversationID;
    final transportCount = fetched.length;
    final filtered = await globalModel.applyHistoryWindowMutations(
      conv,
      fetched,
    );
    if (!isCurrent()) return false;
    // Retry one merge if realtime rows arrived during the facts read. Never
    // replace a newer live revision with the snapshot preceding an async read.
    for (var attempt = 0; attempt < 2; attempt++) {
      final revision = globalModel.messageListRevisionFor(conv);
      final existing = globalModel.mergedAliasMessageList(conv);
      final preserveFilled = replaceWithPeekWindow &&
          (usesOfficialSdkHistory
              ? HistoryPaginationAnchor.shouldRejectC2cPeekRestamp(
                  existingCount: existing.length,
                  incomingCount: transportCount,
                )
              : HistoryPaginationAnchor.shouldPreserveFilledHistoryOverPeek(
                  existingCount: existing.length,
                  fetchedCount: transportCount,
                ));
      final merged = replaceWithPeekWindow && !preserveFilled
          ? TUIChatGlobalModel.mergePeekWindowWithLiveMemory(
              existing: existing,
              fetched: filtered,
            )
          : _mergeWithInMemoryHistory(filtered);
      final authoritative = await globalModel.applyHistoryWindowMutations(
        conv,
        merged,
      );
      if (!isCurrent()) return false;
      if (revision != globalModel.messageListRevisionFor(conv)) continue;
      globalModel.setMessageList(
        conv,
        authoritative,
        needResetNewMessageCount: false,
        replace: true,
      );
      if (markInitialLoaded) globalModel.markInitialHistoryLoaded(conv);
      if (mayHaveOlder != null)
        globalModel.markInitialHistoryMayHaveOlder(
          conv,
          mayHaveOlder: mayHaveOlder,
        );
      return true;
    }
    return false;
  }

  Future<bool> _refreshCurrentHistoryFacts(bool Function() isCurrent) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!isCurrent()) return false;
      final revision = globalModel.messageListRevisionFor(conversationID);
      final current = globalModel.canonicalMessageWindow(conversationID);
      final corrected = await globalModel.applyHistoryWindowMutations(
        conversationID,
        current,
      );
      if (!isCurrent()) return false;
      if (revision != globalModel.messageListRevisionFor(conversationID))
        continue;
      var changed = corrected.length != current.length;
      for (var i = 0; !changed && i < current.length; i++) {
        changed = !identical(current[i], corrected[i]);
      }
      if (changed)
        globalModel.setMessageList(
          conversationID,
          corrected,
          replace: true,
          needResetNewMessageCount: false,
        );
      return true;
    }
    return false;
  }

  // 加载聊天记录（逻辑在 HistoryPaginationLoadRunner，经 _pagination 委托）
  late final HistoryPaginationLoadRunner _historyLoadRunner = () {
    final runner = HistoryPaginationLoadRunner(this, _pagination);
    _pagination.bindLoadChatRecord(runner.loadChatRecord);
    return runner;
  }();

  Future<bool> loadChatRecord({
    HistoryMsgGetTypeEnum? getType,
    int lastMsgSeq = -1,
    required int count,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    LoadDirection direction = LoadDirection.previous,

    /// true：忽略「内存已有足够条数」短路，强制重拉最新一页（回底用）。
    bool forceReloadNewest = false,
  }) {
    // A retained outgoing/live row is not the edge of this history segment.
    if (direction == LoadDirection.latest &&
        !forceReloadNewest &&
        historyNewerPageCursor != null) {
      lastMsg = historyNewerPageCursor;
      lastMsgID = TencentUtils.checkString(lastMsg?.msgID);
      lastMsgSeq = int.tryParse(lastMsg?.seq ?? '') ?? -1;
    }
    // Ensure runner is initialized (binds into _pagination) before delegating.
    final runner = _historyLoadRunner;
    return runner.pagination.loadChatRecord(
      getType: getType,
      lastMsgSeq: lastMsgSeq,
      count: count,
      lastMsgID: lastMsgID,
      direction: direction,
      lastMsg: lastMsg,
      forceReloadNewest: forceReloadNewest,
    );
  }

  /// 内存窗口裁掉较新端后，回到真正的全局最新底部。
  Future<bool> reloadNewestMessageWindow({
    int? count,
    bool allowWhileReadingHistory = false,
    Future<void>? cancelWhen,
  }) async {
    final currentPosition = globalModel.getMessageListPosition(conversationID);
    if (!allowWhileReadingHistory &&
        (globalModel.isMemoryWindowSuppressed(conversationID) ||
            globalModel.isReadingHistory(conversationID) ||
            currentPosition == HistoryMessagePosition.awayTwoScreen ||
            currentPosition == HistoryMessagePosition.notShowLatest)) {
      ChatHistoryTrace.log(
        'reload_newest_message_window_deferred_reading_history',
        conversationID: conversationID,
        extras: <String, Object?>{
          'position': currentPosition.name,
          'memorySuppressed': globalModel.isMemoryWindowSuppressed(
            conversationID,
          ),
          'missingNewer': globalModel.memoryWindowMissingNewer(conversationID),
        },
      );
      return false;
    }
    final previousMissingNewer =
        globalModel.memoryWindowMissingNewer(conversationID);
    final previousHaveMoreLatest = haveMoreLatestData;
    final previousReadingWindow = hasHistoryReadingWindow;
    final previousExpectedLatest = _historyLiveWindow.expectedLatest;
    void restoreLatestAvailability() {
      // The force-load runner may have installed a page before the durable
      // boundary check rejects it. Keep the loaded page navigable and retryable.
      if (previousMissingNewer ||
          globalModel.hasDurableHistoryDeferred(conversationID)) {
        globalModel.markMemoryWindowMissingNewer(conversationID);
      }
      haveMoreLatestData = previousHaveMoreLatest ||
          globalModel.hasDurableHistoryDeferred(conversationID);
      if (previousReadingWindow) {
        _installHistoryReadingWindow(
          globalModel.rawMessageList(conversationID) ?? <V2TimMessage>[],
          previousExpectedLatest,
        );
      }
    }
    _beginHistoryWindowReplace(reason: 'user_reload_newest');
    final returnConversation = conversationID;
    final returnGeneration = _historyWindowGeneration;
    final returnScope = globalModel.historyWindowScopeFor(conversationID);
    final returnOwnerIsCurrent =
        globalModel.captureMessageOwnerFence(conversationID);
    var finished = false;
    bool returnIsCurrent() =>
        !finished && !_disposed && returnOwnerIsCurrent() &&
        conversationID == returnConversation &&
        _historyWindowGeneration == returnGeneration &&
        (returnScope == null ||
            globalModel.isHistoryWindowScopeCurrent(returnScope));
    Future<bool> reload() async {
      final deferredWatermark =
          await globalModel.beginHistoryWindowReturnToLatest(conversationID);
      if (!returnIsCurrent()) return false;
      final fetchCount = count ?? HistoryMessageDartConstant.getCount;
      ChatHistoryTrace.log(
        'reload_newest_message_window_start',
        conversationID: conversationID,
        extras: <String, Object?>{
          'fetchCount': fetchCount,
          'listLenBefore': globalModel.rawMessageCount(conversationID),
          'missingNewer': globalModel.memoryWindowMissingNewer(conversationID),
        },
      );
      globalModel.setMessageListPosition(
        conversationID,
        HistoryMessagePosition.bottom,
        notify: false,
      );
      bool ok;
      try {
        ok = await loadChatRecord(
          count: fetchCount,
          forceReloadNewest: true,
          direction: LoadDirection.previous,
        );
        if (!returnIsCurrent()) return false;
      } catch (_) {
        // The temporary bottom state is an implementation detail of this
        // reload. Do not leave the message model at bottom when the fetch did
        // not complete, otherwise unread/bottom decisions race with a false
        // position on the next inbound message.
        if (!returnIsCurrent()) return false;
        restoreLatestAvailability();
        globalModel.setMessageListPosition(
          conversationID,
          currentPosition,
          notify: true,
        );
        rethrow;
      }
      if (ok &&
          !await globalModel.confirmHistoryWindowReturnCoversDeferred(
              conversationID, deferredWatermark)) {
        // The SDK returned successfully but has not caught up with the received
        // boundary yet. Keep the counter/gap so the reader can retry.
        ok = false;
      }
      if (!returnIsCurrent()) return false;
      if (ok) {
        if (!returnIsCurrent()) return false;
        try {
          // Loading the latest page proves availability, not that its newest
          // row has reached the viewport. The visible confirmation owns ACK.
          // Authoritative deletions need no viewport and must not be replayed.
          await globalModel.acknowledgeHistoryWindowReturnToLatest(
              conversationID, deferredWatermark,
              onlyIfAuthoritativelyDeleted: true);
          if (!returnIsCurrent()) return false;
          await globalModel.resetHistoryWindowAfterLatest(conversationID);
          if (!returnOwnerIsCurrent() ||
              conversationID != returnConversation ||
              _historyWindowGeneration != returnGeneration) return false;
          _pagination.resetCommunityCursor();
        } catch (_) {
          if (!returnIsCurrent()) return false;
          restoreLatestAvailability();
          globalModel.setMessageListPosition(conversationID, currentPosition,
              notify: true);
          rethrow;
        }
        // A direct return starts a different SDK window. Reusing the search
        // window's older cursor would skip everything between the two windows.
        _sdkOlderPageTail = null;
        _rememberSdkOlderPage(globalModel.getMessageList(conversationID) ?? []);
  
        globalModel.clearMemoryWindowMissingNewer(conversationID);
        haveMoreLatestData = false;
        _latestViewportReturnWatermark = deferredWatermark;
        _latestViewportReturnGeneration = returnGeneration;
        globalModel.setMessageListPosition(
          conversationID,
          globalModel.hasDurableHistoryDeferred(conversationID)
              ? HistoryMessagePosition.notShowLatest
              : HistoryMessagePosition.bottom,
          notify: true,
        );
      } else {
        restoreLatestAvailability();
        globalModel.setMessageListPosition(
          conversationID,
          currentPosition,
          notify: true,
        );
      }
      ChatHistoryTrace.log(
        'reload_newest_message_window_done',
        conversationID: conversationID,
        extras: <String, Object?>{
          'ok': ok,
          'listLenAfter': globalModel.rawMessageCount(conversationID),
          'missingNewer': globalModel.memoryWindowMissingNewer(conversationID),
        },
      );
      return ok;
    }

    Future<bool> cancel() async {
      await cancelWhen;
      // Invalidate the publication fence before releasing the caller. Native
      // IO may finish later; it must not install an obsolete window or ACK it.
      if (!finished && !_disposed && returnOwnerIsCurrent() &&
          conversationID == returnConversation &&
          _historyWindowGeneration == returnGeneration) {
        _historyWindowGeneration++;
        restoreLatestAvailability();
        globalModel.setMessageListPosition(returnConversation, currentPosition,
            notify: true);
      }
      return false;
    }

    try {
      return await Future.any<bool>([
        reload(),
        if (cancelWhen != null) cancel(),
      ]);
    } finally {
      finished = true;
    }
  }

  Future<bool> loadDataFromController({int? count}) {
    return loadChatRecord(
      count: count ?? HistoryMessageDartConstant.getCount, //20
    );
  }

  /// Standard C2C/group history comes from the SDK cloud cursor.  Archive
  /// state is applied as a post-processing/mutation layer and never supplies
  /// message正文 for this window.
  Future<List<V2TimMessage>> loadHistoryPeekStyle({
    int? count,
    String? lastMsgID,
    int lastMsgSeq = -1,
    bool scheduleWindowReconcile = true,
  }) async {
    final historyIsCurrent = _historyPublicationFence();
    // K.1：首屏动态 count
    // 当宿主注入了 entryUnreadCount 时，按 unreadHint + 缓冲扩拉，避免首屏只见 20 条最新。
    final baseCount = count ?? HistoryMessageDartConstant.initialOpenFetchCount;
    final dynamicFetchCount = (initialUnreadCount != null &&
            initialUnreadCount! > baseCount)
        ? (initialUnreadCount! + 10)
            .clamp(baseCount, HistoryMessageDartConstant.maxInitialFetchCount)
        : baseCount;
    final fetchCount = dynamicFetchCount;
    final storageId = _storageConversationId(conversationID);
    final userID = conversationType == ConvType.c2c ? storageId : null;
    final groupID = conversationType == ConvType.group ? storageId : null;
    final isWeb = PlatformUtils().isWeb;
    final isInitialWindow = lastMsgID == null && lastMsgSeq <= 0;
    // DIAG: peek 入口摘要
    ChatHistoryTrace.log(
      'diag_peek_enter',
      conversationID: conversationID,
      extras: <String, Object?>{
        'fetchCount': fetchCount,
        'usesOfficial': usesOfficialSdkHistory,
        'initialUnreadCount': initialUnreadCount ?? -1,
        'storageId': storageId,
        'listLenBefore': globalModel.rawMessageCount(conversationID),
        'isWeb': isWeb,
        'isInitialWindow': isInitialWindow,
        'localOnlyInitialOpen': localOnlyInitialOpen,
        'hasJumpMsgID': jumpMsgID?.isNotEmpty ?? false,
      },
    );
    ChatHistoryTrace.log(
      'load_history_peek_start',
      conversationID: conversationID,
      extras: <String, Object?>{
        'storageId': storageId,
        'fetchCount': fetchCount,
        'lastMsgID': lastMsgID ?? '',
        'lastMsgSeq': lastMsgSeq,
        'isWeb': isWeb,
      },
    );
    final peekResult = usesOfficialSdkHistory
        ? await MessageHistoryPeekLoader.loadOlderCloudOnlyResult(
            messageService: _messageService,
            count: fetchCount,
            userID: userID,
            groupID: groupID,
            lastMsgID: lastMsgID,
            lastMsgSeq: lastMsgSeq,
          )
        : await MessageHistoryPeekLoader.loadOlderLocalThenCloudResult(
            messageService: _messageService,
            count: fetchCount,
            userID: userID,
            groupID: groupID,
            lastMsgID: lastMsgID,
            lastMsgSeq: lastMsgSeq,
          );
    if (!historyIsCurrent()) return [];
    _lastPeekIsFinished =
        peekResult.isFinished && peekResult.messageList.isEmpty;
    var messages = peekResult.messageList;
    messages = await ArchiveHistoryProvider.filterMessagesAfterHistoryClear(
      conversationID: conversationID,
      messages: messages,
    );
    if (!historyIsCurrent()) return [];
    messages =
        await globalModel.applyHistoryWindowMutations(conversationID, messages);
    if (!historyIsCurrent()) return [];
    if (messages.isNotEmpty) {
      final processed =
          await lifeCycle?.didGetHistoricalMessageList(messages) ?? messages;
      if (!historyIsCurrent()) return [];
      messages = await globalModel.applyHistoryWindowMutations(
          conversationID, _dedupeMessages(processed));
      if (!historyIsCurrent()) return [];
    }
    final sdkCount = peekResult.messageList.length;
    // Web 进页且 SDK 仍空：清 skip 以便必要时打归档；SDK 有首屏则保留 defer。
    if (isWeb &&
        isInitialWindow &&
        sdkCount == 0 &&
        !ArchiveHistoryProvider.isInHistoryClearGrace(conversationID)) {
      ArchiveHistoryProvider.clearArchiveFallbackSkipped(conversationID);
      _suppressArchiveUntilSdkHistory = false;
    }
    if (sdkCount > 0) {
      _suppressArchiveUntilSdkHistory = false;
    }
    // 与会话预览一致：首屏只保留最新窗口，避免补档后条数膨胀。
    if (isInitialWindow && messages.length > fetchCount) {
      messages = messages.sublist(messages.length - fetchCount);
      // 截断说明窗口外还有更早消息，必须打开上拉分页。
      haveMoreData = true;
    } else if (isInitialWindow && messages.length >= fetchCount) {
      // 满窗口：默认可继续上拉（与会话预览 hasMoreOlder 一致）。
      haveMoreData = true;
    }
    // Native short pages synthesize isFinished. Only an empty finished page
    // closes initial older history; a nonempty page keeps pagination open.
    if (isInitialWindow && sdkCount > 0) haveMoreData = true;
    if (isInitialWindow && _lastPeekIsFinished) {
      haveMoreData = false;
      ChatHistoryTrace.log(
        'load_history_peek_finished_sync_exhausted',
        conversationID: conversationID,
        extras: <String, Object?>{
          'sdkCount': sdkCount,
          'fetchCount': fetchCount,
          'finalLen': messages.length,
        },
      );
    }
    ChatHistoryTrace.log(
      'load_history_peek_done',
      conversationID: conversationID,
      extras: <String, Object?>{
        'haveMoreData': haveMoreData,
        'suppressArchive': _suppressArchiveUntilSdkHistory,
        ...ChatHistoryTrace.windowSummary(messages, prefix: 'final'),
      },
    );
    // DIAG: peek 退出摘要
    ChatHistoryTrace.log(
      'diag_peek_exit',
      conversationID: conversationID,
      extras: <String, Object?>{
        'sdkCount': sdkCount,
        'finalCount': messages.length,
        'peekIsFinished': _lastPeekIsFinished,
        'listLenAfter': globalModel.rawMessageCount(conversationID),
      },
    );
    if (!historyIsCurrent()) return [];
    final authoritative =
        await globalModel.applyHistoryWindowMutations(conversationID, messages);
    return historyIsCurrent() ? authoritative : [];
  }

  /// K.6：按时间窗口拉取首屏（默认最近 7 天）。
  /// 进页首帧不阻塞；渲染后异步触发，命中数据通过现有 commit 链路写入。
  /// 注：使用 SDK getHistoryMessageList 的命名参数 getTimeBegin/getTimePeriod。
  Future<V2TimValueCallback<List<V2TimMessage>>?> loadInitialByTimeWindow({
    required int secondsWindow,
  }) async {
    final historyIsCurrent = _historyPublicationFence();
    if (_disposed) return null;
    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final begin = now - secondsWindow;
      final storageId = _storageConversationId(conversationID);
      final userID = conversationType == ConvType.c2c ? storageId : null;
      final groupID = conversationType == ConvType.group ? storageId : null;
      final result = await TencentImSDKPlugin.v2TIMManager
          .getMessageManager()
          .getHistoryMessageList(
            getType: HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
            userID: userID,
            groupID: groupID,
            count: HistoryMessageDartConstant.initialOpenFetchCount,
            timeBegin: begin,
            timePeriod: secondsWindow,
          );
      ChatHistoryTrace.log(
        'load_initial_by_time_window',
        conversationID: conversationID,
        extras: <String, Object?>{
          'secondsWindow': secondsWindow,
          'begin': begin,
          'returned': result?.data?.length ?? 0,
          'code': result?.code ?? -1,
        },
      );
      // DIAG: 时间窗口补拉退出 - 记录 SDK 原始返回的最早/最晚一条 + seq/ts 范围，
      // 用以判断 SDK 是否真的有时间窗口数据但被业务层丢弃。
      final data = result?.data;
      ChatHistoryTrace.log(
        'diag_time_window_exit',
        conversationID: conversationID,
        extras: <String, Object?>{
          'code': result?.code ?? -1,
          'returned': data?.length ?? 0,
          if (data != null && data.isNotEmpty)
            ...ChatHistoryTrace.windowSummary(data, prefix: 'tw'),
          'secondsWindow': secondsWindow,
          'begin': begin,
          'userID': userID ?? '',
          'groupID': groupID ?? '',
          'desc': result?.desc ?? '',
        },
      );
      if (!historyIsCurrent()) return null;
      final corrected = await globalModel.applyHistoryWindowMutations(
          conversationID, result.data ?? <V2TimMessage>[]);
      if (!historyIsCurrent()) return null;
      return V2TimValueCallback<List<V2TimMessage>>(
          code: result.code, desc: result.desc, data: corrected);
    } catch (e) {
      ChatHistoryTrace.log(
        'load_initial_by_time_window_error',
        conversationID: conversationID,
        extras: <String, Object?>{'error': e.toString()},
      );
      return null;
    }
  }

  /// 取会话列表 / 选中会话的 lastMessage，供首屏归档过期判定（对齐 Peek）。
  V2TimMessage? _conversationLastMessageHint() {
    final storageId = _storageConversationId(conversationID);
    if (storageId.isEmpty) {
      return null;
    }
    final keys = <String>{
      storageId,
      conversationID,
      if (conversationType == ConvType.group) 'group_$storageId',
      if (conversationType == ConvType.c2c) 'c2c_$storageId',
    };
    final selected = conversationViewModel.selectedConversation;
    if (selected != null) {
      final selectedBare = _storageConversationId(selected.conversationID);
      if (selectedBare == storageId || keys.contains(selected.conversationID)) {
        final last = selected.lastMessage;
        if (last != null) {
          return last;
        }
      }
    }
    for (final key in keys) {
      final last = conversationViewModel.getConversation(key)?.lastMessage;
      if (last != null) {
        return last;
      }
    }
    final warm = globalModel.messageListMap[conversationID] ??
        globalModel.messageListMap[storageId];
    if (warm != null && warm.isNotEmpty) {
      return warm.first;
    }
    return null;
  }

  Future<bool> _waitForWarmOpenBackgroundWindow({
    required int generation,
    required String convId,
  }) async {
    await ChatHistoryOpenLayoutReady.wait(
      convId,
      timeout: const Duration(milliseconds: 1000),
    );
    if (_disposed ||
        generation != _openShellGeneration ||
        convId != conversationID) {
      return false;
    }
    // Keep SDK/cloud reconciliation out of the route transition and the
    // message list's short post-reveal geometry stabilization window.
    await Future<void>.delayed(const Duration(milliseconds: 550));
    return !_disposed &&
        generation == _openShellGeneration &&
        convId == conversationID;
  }

  /// 暖开首屏：异步委托给应用层历史同步协调器。
  ///
  /// 这个方法保留兼容入口，但不再直接调用 IM 云端分页、归档校对或
  /// 本地窗口 merge。历史云端请求只能由
  /// [ConversationHistorySyncCoordinator] 统一发起，避免 UIKit 内部旧
  /// 暖开链路和 ChatHistoryPeekBootstrap 重复拉取。
  void scheduleWarmOpenHistoryReconcile({int? fetchCount}) {
    if (localOnlyInitialOpen || _warmOpenHistoryReconcileScheduled) {
      if (localOnlyInitialOpen) {
        ChatHistoryTrace.log(
          'warm_open_reconcile_deferred_local_only_open',
          conversationID: conversationID,
        );
      }
      return;
    }
    final convId = conversationID;
    final existing = globalModel.messageListMap[convId] ??
        globalModel.rawMessageList(convId);
    if (existing == null || existing.isEmpty) {
      return;
    }
    _warmOpenHistoryReconcileScheduled = true;
    ChatHistoryTrace.log(
      'warm_open_reconcile_delegated',
      conversationID: convId,
      extras: <String, Object?>{
        'rawCount': existing.length,
        'fetchCount':
            fetchCount ?? HistoryMessageDartConstant.initialOpenFetchCount,
        'owner': 'ConversationHistorySyncCoordinator',
      },
    );
    final generation = _openShellGeneration;
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 550), () async {
        if (_disposed ||
            generation != _openShellGeneration ||
            convId != conversationID) {
          return;
        }
        await ConversationHistorySyncCoordinator.instance.reconcileConversation(
          conversationID: convId,
          reason: 'warm_open_delegated',
        );
      }),
    );
  }

  void _scheduleFillTowardOlderHistory({
    required int fetchCount,
    required int generation,
    required String convId,
  }) {
    if (_warmOpenTowardLocalScheduled) {
      return;
    }
    _warmOpenTowardLocalScheduled = true;
    unawaited(
      _fillTowardOlderHistory(
        generation: generation,
        convId: convId,
        fetchCount: fetchCount,
      ),
    );
  }

  /// 用户上滑读历史或列表仍在滚动时，暂停暖开后台补旧，避免与视口/窗口裁剪对打。
  bool _shouldDeferBackgroundHistoryFill(String convId) {
    // Context-menu dismissal owns the list geometry until its restore gate
    // settles. Background warm-fill must not commit another page in that
    // window, otherwise it changes the sliver extent underneath the anchor.
    if (globalModel.isMessageContextMenuOverlayOpen ||
        globalModel.isContextMenuViewportRestoreActive(convId)) {
      return true;
    }
    if (globalModel.isChatListUserScrolling) {
      return true;
    }
    final position = globalModel.getMessageListPosition(convId);
    return position == HistoryMessagePosition.awayTwoScreen ||
        position == HistoryMessagePosition.notShowLatest;
  }

  void _deferFillTowardOlderHistoryResume({
    required int generation,
    required String convId,
    required int fetchCount,
  }) {
    _warmOpenTowardLocalScheduled = false;
    _fillTowardOlderHistoryResumeTimer?.cancel();
    ChatHistoryTrace.log(
      'toward_local_fill_deferred',
      conversationID: convId,
      extras: <String, Object?>{
        'userScrolling': globalModel.isChatListUserScrolling,
        'position': globalModel.getMessageListPosition(convId).name,
      },
    );
    ChatJitterDiag.log(
      'toward_local_fill',
      conv: convId,
      extras: <String, Object?>{
        'action': 'deferred',
        'userScrolling': globalModel.isChatListUserScrolling,
        'position': globalModel.getMessageListPosition(convId).name,
      },
    );
    _fillTowardOlderHistoryResumeTimer = Timer(
      const Duration(milliseconds: 500),
      () {
        _fillTowardOlderHistoryResumeTimer = null;
        if (_disposed ||
            generation != _openShellGeneration ||
            convId != conversationID) {
          return;
        }
        if (_shouldDeferBackgroundHistoryFill(convId)) {
          _deferFillTowardOlderHistoryResume(
            generation: generation,
            convId: convId,
            fetchCount: fetchCount,
          );
          return;
        }
        _scheduleFillTowardOlderHistory(
          fetchCount: fetchCount,
          generation: generation,
          convId: convId,
        );
      },
    );
  }

  /// C2C / 群：按官方 lastMsg 链续拉（上一页 SDK 尾巴），不在整窗里重算最老一条。
  /// 其它未配置的会话类型保留 SDK 本地/云兼容路径。
  Future<void> _fillTowardOlderHistory({
    required int generation,
    required String convId,
    required int fetchCount,
  }) async {
    final historyIsCurrent = _historyPublicationFence();
    if (!historyIsCurrent() ||
        generation != _openShellGeneration ||
        convId != conversationID) {
      return;
    }
    if (!await _waitForWarmOpenBackgroundWindow(
      generation: generation,
      convId: convId,
    )) {
      return;
    }
    if (PlatformUtils().isWeb) {
      ChatHistoryTrace.log(
        'toward_local_fill_skip',
        conversationID: convId,
        extras: <String, Object?>{'reason': 'web'},
      );
      return;
    }

    final storageId = _storageConversationId(conversationID);
    final userID = conversationType == ConvType.c2c ? storageId : null;
    final groupID = conversationType == ConvType.group ? storageId : null;

    ChatHistoryTrace.log(
      'toward_local_fill_start',
      conversationID: convId,
      extras: <String, Object?>{'fetchCount': fetchCount},
    );

    for (var round = 0; round < 6; round++) {
      if (!historyIsCurrent() ||
          generation != _openShellGeneration ||
          convId != conversationID) {
        return;
      }
      if (_shouldDeferBackgroundHistoryFill(convId)) {
        ChatJitterDiag.log(
          'toward_local_fill',
          conv: convId,
          extras: <String, Object?>{
            'action': 'defer_before_round',
            'round': round,
            'userScrolling': globalModel.isChatListUserScrolling,
            'position': globalModel.getMessageListPosition(convId).name,
          },
        );
        _deferFillTowardOlderHistoryResume(
          generation: generation,
          convId: convId,
          fetchCount: fetchCount,
        );
        return;
      }
      final menuGeneration =
          globalModel.messageContextMenuTransactionGeneration;
      final existing = List<V2TimMessage>.from(
        globalModel.mergedAliasMessageList(convId),
      );
      if (existing.isEmpty) {
        return;
      }
      final isOfficialFill = usesOfficialSdkHistory;
      final oldest = isOfficialFill
          ? HistoryPaginationAnchor.officialOlderCursor(
              newestFirstWindow: existing,
              lastSdkPageTail: _sdkOlderPageTail,
              firstScreenCount: fetchCount,
            )
          : HistoryPaginationAnchor.oldestSdkPaginationAnchor(existing);
      if (oldest == null) {
        return;
      }
      final officialSeq = conversationType == ConvType.group
          ? int.tryParse(oldest.seq?.toString() ?? '') ?? -1
          : -1;
      final V2TimMessageListResult? peek = isOfficialFill
          ? await globalModel.getHistoryMessageListThroughIm06(
              count: fetchCount,
              getType: HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
              userID: userID,
              groupID: groupID,
              lastMsgID: oldest.msgID,
              lastMsgSeq: officialSeq,
              lastMsg: oldest,
            )
          : await MessageHistoryPeekLoader.loadOlderLocalThenCloudResult(
              messageService: _messageService,
              count: fetchCount,
              userID: userID,
              groupID: groupID,
              lastMsgID: oldest.msgID,
              lastMsgSeq: int.tryParse(oldest.seq?.toString() ?? '') ?? -1,
              lastMsg: oldest,
            );
      if (!historyIsCurrent()) return;
      if (peek == null) {
        haveMoreData = true;
        break;
      }
      if (peek.messageList.isEmpty) {
        haveMoreData = !peek.isFinished;
        globalModel.markInitialHistoryMayHaveOlder(
          convId,
          mayHaveOlder: !peek.isFinished,
        );
        break;
      }
      final continuity = HistoryPaginationContinuity.canAppendOlderBatch(
        existingNewestFirst: [
          for (final message in existing)
            (
              seq: int.tryParse(message.seq?.trim() ?? ''),
              msgID: message.msgID?.trim(),
            ),
        ],
        incomingOlderNewestFirst: [
          for (final message in peek.messageList)
            (
              seq: int.tryParse(message.seq?.trim() ?? ''),
              msgID: message.msgID?.trim(),
            ),
        ],
        isGroup: conversationType == ConvType.group,
        olderCloudBacked: isOfficialFill,
      );
      final canMerge = continuity.canMerge;
      if (!canMerge) {
        ChatHistoryTrace.log(
          'toward_local_skip_disconnected',
          conversationID: convId,
          extras: <String, Object?>{
            'olderCount': peek.messageList.length,
            'windowCount': existing.length,
            ...continuity.toTraceExtras(),
          },
        );
        if (continuity.hasClosedGap) {
          globalModel.noteRejectedOlderPageGap(
            conversationID: convId,
            missingLowerSeq: continuity.missingLowerSeq,
            missingUpperSeq: continuity.missingUpperSeq,
          );
        }
        globalModel.markInitialHistoryMayHaveOlder(convId, mayHaveOlder: true);
        haveMoreData = true;
        break;
      }
      if (_shouldDeferBackgroundHistoryFill(convId)) {
        _deferFillTowardOlderHistoryResume(
          generation: generation,
          convId: convId,
          fetchCount: fetchCount,
        );
        return;
      }
      // The request may have started before a context menu opened. Re-check
      // the transaction generation immediately before mutating the visible
      // projection so an in-flight page cannot cross the menu boundary.
      if (menuGeneration !=
              globalModel.messageContextMenuTransactionGeneration ||
          globalModel.isMessageContextMenuOverlayOpen ||
          globalModel.isContextMenuViewportRestoreActive(convId)) {
        _deferFillTowardOlderHistoryResume(
          generation: generation,
          convId: convId,
          fetchCount: fetchCount,
        );
        return;
      }
      if (!await _commitHistoricalMessages(
        peek.messageList,
        markInitialLoaded: true,
        // Empty pages were handled above; a short accepted page is not EOF.
        mayHaveOlder: true,
        replaceWithPeekWindow: false,
        requestIsCurrent: historyIsCurrent,
      )) return;
      // SDK 游标必须与已提交窗口保持一致。请求完成后若因用户滚动而延期，
      // 不能提前推进游标，否则手动上拉会从未写入页的尾部继续，整页历史被跳过。
      if (isOfficialFill || conversationType == ConvType.group) {
        _rememberSdkOlderPage(peek.messageList);
      }
      _notify();
      final afterLen = globalModel.mergedAliasMessageList(convId).length;
      ChatHistoryTrace.log(
        'toward_local_fill_commit',
        conversationID: convId,
        extras: <String, Object?>{
          'round': round,
          'beforeLen': existing.length,
          'afterLen': afterLen,
          'added': peek.messageList.length,
          'isFinished': peek.isFinished,
          'cursorMsgID': oldest.msgID ?? '',
        },
      );
      ChatJitterDiag.log(
        'toward_local_fill',
        conv: convId,
        extras: <String, Object?>{
          'action': 'commit',
          'round': round,
          'beforeLen': existing.length,
          'afterLen': afterLen,
          'peekCount': peek.messageList.length,
        },
      );
      if (afterLen <= existing.length) {
        break;
      }
    }
  }

  void _rememberSdkOlderPage(List<V2TimMessage> rawSdkPage) {
    // All standard group pages, including Community, continue from the SDK
    // page tail so an upward request cannot repeat or skip a page.
    if (!usesOfficialSdkHistory && conversationType != ConvType.group) {
      return;
    }
    final tail = HistoryPaginationAnchor.tailOfCloudOlderPage(rawSdkPage);
    if (tail == null) {
      ChatHistoryTrace.log(
        'remember_sdk_older_page_no_tail',
        conversationID: conversationID,
        extras: <String, Object?>{
          'rawCount': rawSdkPage.length,
        },
      );
      return;
    }
    _sdkOlderPageTail = tail;
  }

  static String _historyMessageId(V2TimMessage message) {
    final msgID = message.msgID?.trim() ?? '';
    if (msgID.isNotEmpty) {
      return msgID;
    }
    return message.id?.trim() ?? '';
  }

  static int _historyTimestampSec(V2TimMessage message) {
    final ts = message.timestamp ?? 0;
    if (ts <= 0) {
      return 0;
    }
    return ts < 1000000000000 ? ts : ts ~/ 1000;
  }

  /// 暖开/进页异步校对写回门禁：等 layout reveal，或 ≤2s 超时兜底。
  /// 返回 false 表示会话已失效，调用方不得 `_commitHistoricalMessages`。
  Future<bool> _awaitWarmOpenCommitGate({
    required int generation,
    required String convId,
  }) async {
    if (_disposed ||
        generation != _openShellGeneration ||
        convId != conversationID) {
      return false;
    }
    final gateTrace = ChatOpenPerfLog.captureCurrent(conversationKey: convId);
    if (ChatHistoryOpenLayoutReady.isReady(convId)) {
      ChatHistoryTrace.log(
        'warm_open_reconcile_commit_after_reveal',
        conversationID: convId,
        extras: <String, Object?>{
          'generation': generation,
          'alreadyReady': true,
        },
      );
      ChatOpenPerfLog.mark(
        'warm_open_reconcile_commit_after_reveal',
        conversationID: convId,
        extras: <String, Object?>{
          'generation': generation,
          'alreadyReady': true,
        },
        trace: gateTrace,
      );
      return true;
    }
    ChatHistoryTrace.log(
      'warm_open_reconcile_deferred',
      conversationID: convId,
      extras: <String, Object?>{'generation': generation},
    );
    ChatOpenPerfLog.mark(
      'warm_open_reconcile_deferred',
      conversationID: convId,
      extras: <String, Object?>{'generation': generation},
      trace: gateTrace,
    );
    final ready = await ChatHistoryOpenLayoutReady.wait(
      convId,
      timeout: const Duration(seconds: 2),
    );
    if (_disposed ||
        generation != _openShellGeneration ||
        convId != conversationID) {
      return false;
    }
    final event = ready
        ? 'warm_open_reconcile_commit_after_reveal'
        : 'warm_open_reconcile_commit_after_timeout';
    ChatHistoryTrace.log(
      event,
      conversationID: convId,
      extras: <String, Object?>{'generation': generation},
    );
    ChatOpenPerfLog.mark(
      event,
      conversationID: convId,
      extras: <String, Object?>{'generation': generation},
      trace: gateTrace,
    );
    return true;
  }

  /// 首屏 SDK 窗上屏后异步校对自建归档（满窗也会打一次；不挡进页）。
  Future<bool> hydrateInitialHistoryPeekStyle({
    int? count,
    List<Duration>? retryDelays,
    bool plainOpen = false,
  }) async {
    final historyIsCurrent = _historyPublicationFence();
    final fetchCount =
        count ?? HistoryMessageDartConstant.initialOpenFetchCount;
    final storageId = _storageConversationId(conversationID);
    final groupPrefixed = storageId.isEmpty ? '' : 'group_$storageId';

    if (plainOpen) {
      await globalModel.awaitOpenHydrateInFlight(
        conversationID,
        timeout: const Duration(milliseconds: 900),
      );
      if (globalModel.hasOpenHydrateInFlight(conversationID)) {
        // The app-owned open bootstrap remains the sole first-window owner.
        // Waiting timed out only for this caller; it did not cancel the
        // native SDK request, so starting LOCAL/CLOUD here would create a
        // second logical owner and can poison the C2C history lane.
        ChatHistoryTrace.log(
          'hydrate_defer_open_hydrate_inflight',
          conversationID: conversationID,
        );
        return false;
      }
    }

    if (!await _refreshCurrentHistoryFacts(historyIsCurrent)) return false;
    final warmCount = globalModel.rawMessageCount(conversationID);
    final warmLoaded = globalModel.hasInitialHistoryLoaded(conversationID);
    if (usesOfficialSdkHistory) {
      final aliasCount =
          globalModel.mergedAliasMessageList(conversationID).length;
      if (aliasCount > fetchCount) {
        globalModel.markInitialHistoryLoaded(conversationID);
        syncHaveMoreDataFromCachedHistory(
          mayHaveOlder: globalModel.mayHaveOlderHistory(conversationID) ||
              aliasCount > fetchCount,
        );
        haveMoreData = true;
        ChatHistoryTrace.log(
          'hydrate_keep_c2c_sdk_window',
          conversationID: conversationID,
          extras: <String, Object?>{
            'aliasCount': aliasCount,
            'fetchCount': fetchCount,
          },
        );
        return true;
      }
    }

    if (plainOpen &&
        WebChatOpenPolicy.canSkipHydrateRefetch(
          globalModel: globalModel,
          conversationKey: conversationID,
          preview: _conversationLastMessageHint(),
        )) {
      syncHaveMoreDataFromCachedHistory(
        mayHaveOlder: globalModel.mayHaveOlderHistory(conversationID) ||
            warmCount >= fetchCount,
      );
      ChatHistoryTrace.log(
        'hydrate_web_skip_refetch',
        conversationID: conversationID,
        extras: <String, Object?>{
          'warmCount': warmCount,
          'warmLoaded': warmLoaded,
        },
      );
      return true;
    }

    final warmCountBare = storageId == conversationID
        ? warmCount
        : globalModel.rawMessageCount(storageId);
    final warmCountGroup =
        groupPrefixed.isEmpty ? 0 : globalModel.rawMessageCount(groupPrefixed);
    final warmLoadedBare = storageId == conversationID
        ? warmLoaded
        : globalModel.hasInitialHistoryLoaded(storageId);
    final warmLoadedGroup = groupPrefixed.isEmpty
        ? false
        : globalModel.hasInitialHistoryLoaded(groupPrefixed);

    ChatHistoryTrace.log(
      'hydrate_enter',
      conversationID: conversationID,
      extras: <String, Object?>{
        'plainOpen': plainOpen,
        'storageId': storageId,
        'fetchCount': fetchCount,
        'warmCount': warmCount,
        'warmLoaded': warmLoaded,
        'warmCountBare': warmCountBare,
        'warmLoadedBare': warmLoadedBare,
        'warmCountGroup': warmCountGroup,
        'warmLoadedGroup': warmLoadedGroup,
        'mayHaveOlder': globalModel.mayHaveOlderHistory(conversationID),
        ...ChatHistoryTrace.windowSummary(
          globalModel.messageListMap[conversationID] ??
              globalModel.messageListMap[storageId],
          prefix: 'warm',
        ),
      },
    );

    // 仅跳过「已确认空会话」，避免空列表转圈。
    // 冷开并行 peek 仍在飞时绝不能 keep-empty，否则会把稍后注入的暖窗挡掉。
    // 别名桶仍有消息 / 列表预览有非 tip 证据 / 清空宽限期 → 禁止假确认空。
    if (plainOpen &&
        warmLoaded &&
        warmCount == 0 &&
        !globalModel.mayHaveOlderHistory(conversationID) &&
        !globalModel.hasOpenHydrateInFlight(conversationID)) {
      final previewHint = _conversationLastMessageHint();
      final hasNonTipPreview = previewHint != null &&
          !HistoryPaginationAnchor.isLocalInjectedMessage(previewHint) &&
          !ConversationPreviewHistorySync.isSyntheticLocalMessage(previewHint);
      final inClearGrace =
          ArchiveHistoryProvider.isInHistoryClearGrace(conversationID) ||
              ArchiveHistoryProvider.isInHistoryClearGrace(storageId) ||
              (groupPrefixed.isNotEmpty &&
                  ArchiveHistoryProvider.isInHistoryClearGrace(groupPrefixed));
      final rejectReason = hydrateKeepEmptyRejectReason(
        warmCountBare: warmCountBare,
        warmCountGroup: warmCountGroup,
        hasNonTipPreviewEvidence: hasNonTipPreview,
        inClearGrace: inClearGrace,
      );
      if (rejectReason != null) {
        ChatHistoryTrace.log(
          'hydrate_reject_keep_empty',
          conversationID: conversationID,
          extras: <String, Object?>{
            'reason': rejectReason,
            'warmCountBare': warmCountBare,
            'warmCountGroup': warmCountGroup,
            'hasNonTipPreview': hasNonTipPreview,
            'inClearGrace': inClearGrace,
          },
        );
      } else {
        syncHaveMoreDataFromCachedHistory(mayHaveOlder: false);
        ChatHistoryTrace.log(
          'hydrate_keep_empty_confirmed',
          conversationID: conversationID,
        );
        return true;
      }
    }

    // 进页 bootstrap 已灌入 peek 暖窗：禁止再被「空 SDK + 旧归档」整窗替换。
    // 例外：暖窗几乎全是过期归档（SDK 空时被错灌）——必须剥掉并继续 refetch。
    // 必须用 alias-aware rawMessageList：messageListMap[字面 key] 为空时
    // 会把「别名上的真实暖窗」误判成 tip-only 并写成空 list → 灰屏。
    final warmList = globalModel.rawMessageList(conversationID);
    final staleArchiveWarm = plainOpen &&
        warmCount > 0 &&
        HistoryPaginationAnchor.isStaleArchiveDominatedWindow(warmList);
    final alignedWarmWindow = plainOpen &&
        ConversationPreviewHistorySync.canSkipOpenRebootstrap(
          globalModel: globalModel,
          conversationKey: conversationID,
          preview: _conversationLastMessageHint(),
        );
    // 进页已有完整暖窗：keep 即返回，禁止二次 peek replace 扩 len。
    // 未灌满的短窗（列表预热几条）必须继续 refetch，避免先贴底再补页。
    if (plainOpen && alignedWarmWindow && warmCount > 0 && !staleArchiveWarm) {
      final warmHasSdk =
          HistoryPaginationAnchor.oldestSdkPaginationAnchor(warmList) != null;
      final warmOnlyTipsOrEmpty = !warmHasSdk &&
          !(warmList?.any(HistoryPaginationAnchor.isArchiveHistoryMessage) ??
              false);
      final keptShortWindow = warmCount < fetchCount;
      if (warmOnlyTipsOrEmpty) {
        // tip 空会话：清掉历史 tip 铺满，禁止上拉归档。
        if (warmCount > 0) {
          globalModel.clearLocalHistoryAsEmptyLoaded(conversationID);
          ChatHistoryTrace.log(
            'hydrate_strip_tip_only_empty',
            conversationID: conversationID,
            extras: <String, Object?>{
              'beforeCount': warmCount,
              ...ChatHistoryTrace.windowSummary(warmList, prefix: 'stripped'),
            },
          );
        }
        _suppressArchiveUntilSdkHistory = true;
        haveMoreData = false;
        globalModel.markInitialHistoryMayHaveOlder(
          conversationID,
          mayHaveOlder: false,
        );
      } else {
        globalModel.markInitialHistoryLoaded(conversationID);
        final mayHaveOlder = globalModel.mayHaveOlderHistory(conversationID) ||
            keptShortWindow ||
            warmCount >= fetchCount;
        syncHaveMoreDataFromCachedHistory(mayHaveOlder: mayHaveOlder);
        haveMoreData = haveMoreData || mayHaveOlder;
      }
      ChatHistoryTrace.log(
        'hydrate_keep_warm_peek',
        conversationID: conversationID,
        extras: <String, Object?>{
          'warmCount': warmCount,
          'fetchCount': fetchCount,
          'keptShortWindow': keptShortWindow,
          'haveMoreData': haveMoreData,
          'warmHasSdk': warmHasSdk,
          'suppressArchive': _suppressArchiveUntilSdkHistory,
          ...ChatHistoryTrace.windowSummary(warmList, prefix: 'kept'),
        },
      );
      return true;
    }
    if (staleArchiveWarm) {
      // 不在此处立即剥离：列表已在屏上时先塌成几条再被 refetch 弹回
      //（如 60→3→62），就是进页肉眼可见的抖动。改为延迟处理：
      // refetch 拉到新窗后用 peek-window replace 一次性换掉过期归档；
      // 全部拉空才在收尾兜底剥离。
      ChatHistoryTrace.log(
        'hydrate_defer_stale_archive_strip',
        conversationID: conversationID,
        extras: <String, Object?>{
          'warmCount': warmCount,
          ...ChatHistoryTrace.windowSummary(warmList, prefix: 'warm'),
        },
      );
    }

    ChatHistoryTrace.log(
      'hydrate_will_refetch',
      conversationID: conversationID,
      extras: <String, Object?>{
        'reason': !plainOpen
            ? 'not_plain_open'
            : staleArchiveWarm
                ? 'stale_archive_warm'
                : !warmLoaded
                    ? 'warm_not_loaded'
                    : warmCount <= 0
                        ? 'warm_empty'
                        : 'unknown',
        'hintAliasMismatch':
            warmCount <= 0 && (warmCountBare > 0 || warmCountGroup > 0),
      },
    );

    // 刚清空宽限期内：避免多轮空拉转圈；若内存已有清空后新消息则直接用，
    // 内存仍为空则继续走下面单次 peek，避免漏掉宽限期内到达的新消息。
    if (plainOpen &&
        ArchiveHistoryProvider.isInHistoryClearGrace(conversationID) &&
        globalModel.hasInitialHistoryLoaded(conversationID) &&
        globalModel.rawMessageCount(conversationID) > 0) {
      final existing =
          globalModel.messageListMap[conversationID] ?? const <V2TimMessage>[];
      final kept = await ArchiveHistoryProvider.filterMessagesAfterHistoryClear(
        conversationID: conversationID,
        messages: existing,
      );
      final authoritative =
          await globalModel.applyHistoryWindowMutations(conversationID, kept);
      if (!historyIsCurrent()) return false;
      globalModel.setMessageList(
        conversationID,
        authoritative,
        needResetNewMessageCount: false,
        replace: true,
      );
      syncHaveMoreDataFromCachedHistory(
        mayHaveOlder: globalModel.mayHaveOlderHistory(conversationID),
      );
      return true;
    }

    final clearedAt = await ArchiveHistoryProvider.historyClearedAtMs(
      conversationID,
    );
    final delays = retryDelays ??
        (clearedAt > 0
            ? const <Duration>[Duration.zero]
            : (plainOpen
                ? const <Duration>[
                    Duration.zero,
                    Duration(milliseconds: 150),
                    Duration(milliseconds: 400),
                  ]
                : const <Duration>[
                    Duration.zero,
                    Duration(milliseconds: 350),
                    Duration(milliseconds: 900),
                    Duration(milliseconds: 1800),
                  ]));
    final requestKey = 'peek_hydrate_$conversationID';
    _historyLoadingKeys.add(requestKey);
    if (_historyLoadingKeys.length == 1) {
      _notify();
    }
    var committedDuringRefetch = false;
    String? committedBatchSignature;
    try {
      for (final delay in delays) {
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
        // 页面已关闭：停止向全局模型写整表。否则关页后剩余重试轮仍会
        // setMessageList → bump revision（日志里 dispose 后 400ms 还在写）。
        if (_disposed) {
          ChatHistoryTrace.log(
            'hydrate_abort_disposed',
            conversationID: conversationID,
          );
          return committedDuringRefetch;
        }
        if (plainOpen &&
            globalModel.getMessageListPosition(conversationID) ==
                HistoryMessagePosition.notShowLatest) {
          ChatHistoryTrace.log(
            'hydrate_abort_history_position',
            conversationID: conversationID,
          );
          return committedDuringRefetch;
        }
        final messages = await loadHistoryPeekStyle(count: fetchCount);
        if (!historyIsCurrent()) return false;
        if (_disposed) {
          ChatHistoryTrace.log(
            'hydrate_abort_disposed',
            conversationID: conversationID,
          );
          return committedDuringRefetch;
        }
        if (plainOpen &&
            globalModel.getMessageListPosition(conversationID) ==
                HistoryMessagePosition.notShowLatest) {
          ChatHistoryTrace.log(
            'hydrate_abort_history_position',
            conversationID: conversationID,
          );
          return committedDuringRefetch;
        }
        if (messages.isEmpty) {
          continue;
        }
        final existingWarm = globalModel.messageListMap[conversationID];
        final existingNewest = existingWarm == null || existingWarm.isEmpty
            ? 0
            : (existingWarm.first.timestamp ?? 0);
        final lastHintTs = _conversationLastMessageHint()?.timestamp ?? 0;
        final staleRefTs = existingNewest > 0 ? existingNewest : lastHintTs;
        if (HistoryPaginationAnchor.isStaleArchiveDominatedWindow(
          messages,
          referenceTimestampSec: staleRefTs > 0 ? staleRefTs : null,
        )) {
          ChatHistoryTrace.log(
            'hydrate_skip_stale_archive_batch',
            conversationID: conversationID,
            extras: <String, Object?>{
              'existingNewestTs': existingNewest,
              'lastHintTs': lastHintTs,
              ...ChatHistoryTrace.windowSummary(messages, prefix: 'fetched'),
            },
          );
          _suppressArchiveUntilSdkHistory = true;
          haveMoreData = false;
          continue;
        }
        final completeWindow = messages.length >= fetchCount;
        // 不足目标窗口可能只是 SDK 漫游尚未同步；但 peek 已标记 finished
        // 时就是短会话，不能据此连打多轮 LOCAL+CLOUD。
        final mayOlder =
            haveMoreData || (!completeWindow && !_lastPeekIsFinished);
        haveMoreData = mayOlder;
        // 重试轮拉到与已 commit 轮完全相同的窗口：跳过整表重写。
        // 短会话（< fetchCount）不满窗、循环每轮都会 commit，一次进页
        // 固定 3 次 setMessageList → 3 次 revision bump → 3 次全列表重建。
        final batchSignature = _peekWindowBatchSignature(messages);
        if (committedDuringRefetch &&
            batchSignature == committedBatchSignature) {
          ChatHistoryTrace.log(
            'hydrate_skip_unchanged_batch',
            conversationID: conversationID,
            extras: <String, Object?>{'messageCount': messages.length},
          );
          if (completeWindow) {
            return true;
          }
          continue;
        }
        // 过期归档暖窗：用新窗一次性整体替换（含剥离旧归档），
        // 避免「先剥离塌缩、再补回弹开」的两段式可见抖动。
        // 首屏已确认（哪怕总量不足一窗，如只有 6 条的短会话）就标记 loaded：
        // 只标 completeWindow 会让短会话每次进页都被当成冷启动、盖空壳闪一下。
        if (!await _commitHistoricalMessages(
          messages,
          markInitialLoaded: true,
          mayHaveOlder: mayOlder,
          replaceWithPeekWindow: true,
          requestIsCurrent: historyIsCurrent,
        )) return false;
        if (usesOfficialSdkHistory || conversationType == ConvType.group) {
          _rememberSdkOlderPage(messages);
        }
        committedDuringRefetch = true;
        committedBatchSignature = batchSignature;
        ChatHistoryTrace.log(
          'hydrate_initial_done',
          conversationID: conversationID,
          extras: <String, Object?>{
            'fetchCount': fetchCount,
            'messageCount': messages.length,
            'haveMoreData': haveMoreData,
            'plainOpen': plainOpen,
          },
        );
        _notify();
        if (completeWindow || (plainOpen && _lastPeekIsFinished)) {
          return true;
        }
        if (plainOpen && committedDuringRefetch && messages.isNotEmpty) {
          // 短会话已有首屏：不要按「未满 40」再打 350/900/1800ms 重试。
          return true;
        }
      }
      // 页面已关闭：收尾的剥离/归档兜底同样不再写全局状态。
      if (_disposed) {
        ChatHistoryTrace.log(
          'hydrate_abort_disposed',
          conversationID: conversationID,
        );
        return committedDuringRefetch;
      }
      if (plainOpen &&
          globalModel.getMessageListPosition(conversationID) ==
              HistoryMessagePosition.notShowLatest) {
        return committedDuringRefetch;
      }
      // 延迟剥离兜底：refetch 全轮拉空且暖窗仍是过期归档，才剥离一次。
      if (staleArchiveWarm && !committedDuringRefetch) {
        final remainingWarm = globalModel.messageListMap[conversationID];
        final stripped = HistoryPaginationAnchor.withoutArchiveHistory(
          remainingWarm,
        );
        final authoritative = await globalModel.applyHistoryWindowMutations(
            conversationID, stripped);
        if (!historyIsCurrent()) return false;
        globalModel.setMessageList(
          conversationID,
          authoritative,
          needResetNewMessageCount: false,
          replace: true,
        );
        ChatHistoryTrace.log(
          'hydrate_strip_stale_archive_warm',
          conversationID: conversationID,
          extras: <String, Object?>{
            'beforeCount': remainingWarm?.length ?? 0,
            'afterCount': stripped.length,
            'deferred': true,
          },
        );
      }

      // SDK 全空才允许归档兜底。若内存已有 peek 暖窗，绝不用旧归档整窗覆盖。
      final existingWarm = globalModel.rawMessageCount(conversationID);
      if (existingWarm > 0) {
        // 以暖窗收尾同样算首屏已确认，否则下次进页仍走冷 gate 闪空壳。
        globalModel.markInitialHistoryLoaded(conversationID);
        syncHaveMoreDataFromCachedHistory(
          mayHaveOlder: globalModel.mayHaveOlderHistory(conversationID) ||
              existingWarm >= fetchCount,
        );
        haveMoreData = haveMoreData ||
            globalModel.mayHaveOlderHistory(conversationID) ||
            existingWarm >= fetchCount;
        _notify();
        return true;
      }
      // 空会话也标记已加载，避免下次进页继续转圈 bootstrapping。
      globalModel.markInitialHistoryLoaded(conversationID);
      // tip/空首屏且未接受归档：与移动端一致，不再开上拉挖冷历史。
      _suppressArchiveUntilSdkHistory = true;
      globalModel.markInitialHistoryMayHaveOlder(
        conversationID,
        mayHaveOlder: false,
      );
      haveMoreData = false;
      if (clearedAt > 0) {
        // clearedAt 标记已由上方 suppress 处理。
      }
      return false;
    } finally {
      _historyLoadingKeys.remove(requestKey);
      if (_historyLoadingKeys.isEmpty) {
        _notify();
      }
    }
  }

  /// Peek 风格补全首屏窗口，与内存中实时消息 merge 后写入。
  Future<void> fillHistoryWindowPeekStyle({int? targetCount}) async {
    final historyIsCurrent = _historyPublicationFence();
    final fetchCount = targetCount ?? HistoryMessageDartConstant.getCount;
    final messages = await loadHistoryPeekStyle(count: fetchCount);
    if (messages.isEmpty) {
      return;
    }
    if (!await _commitHistoricalMessages(
      messages,
      markInitialLoaded: true,
      mayHaveOlder: messages.length >= fetchCount,
      replaceWithPeekWindow: true,
      requestIsCurrent: historyIsCurrent,
    )) return;
    if (usesOfficialSdkHistory || conversationType == ConvType.group) {
      _rememberSdkOlderPage(messages);
    }
    haveMoreData = messages.length >= fetchCount;
    _notify();
  }

  Future<V2TimValueCallback<List<V2TimMessageReceipt>>> getMessageReadReceipts(
    List<String> messageIDList,
  ) {
    return _messageService.getMessageReadReceipts(messageIDList: messageIDList);
  }

  _getMsgReadReceipt(List<V2TimMessage> message) async {
    if (!_canUseReadReceipt) {
      return;
    }
    final msgID = message
        .where(
          (e) =>
              (e.isSelf ?? true) &&
              (e.needReadReceipt ?? false) &&
              (e.status == MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC),
        )
        .map((e) => e.msgID ?? '')
        .toList();
    if (msgID.isNotEmpty) {
      final res = await getMessageReadReceipts(msgID);
      if (res.code == 0) {
        final receiptList = res.data;
        if (receiptList != null) {
          final changedMsgIDs = <String>[];
          for (var item in receiptList) {
            final msgID = item.msgID;
            if (msgID == null || msgID.isEmpty) {
              continue;
            }
            globalModel.messageReadReceiptMap[msgID] = item;
            changedMsgIDs.add(msgID);
          }
          globalModel.markMessageRowsChangedByMsgIDs(changedMsgIDs);
        }
      }
      _notify();
    }
  }

  translateText(V2TimMessage message) async {
    final String originText = message.textElem?.text ?? "";
    final String deviceLocale = TIM_getCurrentDeviceLocale();
    final String targetMessage = deviceLocale.split("-")[0];
    final translatedText = await _messageService.translateText(
      originText,
      targetMessage,
    );

    final LocalCustomDataModel localCustomData = LocalCustomDataModel.fromMap(
      json.decode(TencentUtils.checkString(message.localCustomData) ?? "{}"),
    );
    localCustomData.translatedText = translatedText;
    await _persistLocalCustomData(message, localCustomData);
  }

  Future<void> convertVoiceMessageToText(V2TimMessage message) async {
    final msgID = TencentUtils.checkString(message.msgID);
    if (msgID == null) {
      final localCustomData = LocalCustomDataModel.fromMap(
        json.decode(TencentUtils.checkString(message.localCustomData) ?? '{}'),
      );
      localCustomData.voiceToTextStatus = 'error';
      message.localCustomData = json.encode(localCustomData.toMap());
      globalModel.markMessageChangedByMessage(conversationID, message);
      _notify();
      serviceLocator<CoreServicesImpl>().callOnCallback(
        TIMCallback(
          type: TIMCallbackType.INFO,
          infoRecommendText: '语音消息缺少消息标识，无法转文字',
          infoCode: 6660424,
        ),
      );
      return;
    }

    final localCustomData = LocalCustomDataModel.fromMap(
      json.decode(TencentUtils.checkString(message.localCustomData) ?? "{}"),
    );
    if (TencentUtils.checkString(localCustomData.voiceToText) != null) {
      return;
    }
    // `loading` is persisted locally. After a route/process restart there is
    // no in-flight request to finish, so treat the stale marker as retryable
    // instead of hiding the action forever.
    if (localCustomData.voiceToTextStatus == 'loading') {
      localCustomData.voiceToTextStatus = 'error';
    }

    localCustomData.voiceToTextStatus = 'loading';
    // 先出 loading，SDK 落盘与转写并行，避免菜单点下去先卡在 persist。
    final loadingPersist = _persistLocalCustomData(message, localCustomData);
    String? text;
    try {
      text = await _transcribeVoiceMessage(message, msgID);
    } catch (_) {
      VoiceToTextBridge.lastErrorMessage = '转写失败，请重试';
    }
    void publishVoiceToTextState() {
      message.localCustomData = json.encode(localCustomData.toMap());
      globalModel.markMessageChangedByMessage(conversationID, message);
      _notify();
    }

    if (text == null || text.isEmpty) {
      localCustomData.voiceToTextStatus = 'error';
      publishVoiceToTextState();
      await loadingPersist;
      await _persistLocalCustomData(message, localCustomData);
      serviceLocator<CoreServicesImpl>().callOnCallback(
        TIMCallback(
          type: TIMCallbackType.INFO,
          infoRecommendText: _voiceToTextFailureMessage(),
          infoCode: 6660424,
        ),
      );
      return;
    }

    localCustomData.voiceToText = text;
    localCustomData.voiceToTextStatus = 'done';
    publishVoiceToTextState();
    await loadingPersist;
    await _persistLocalCustomData(message, localCustomData);
  }

  /// Persists only the local presentation preference for a voice transcript.
  /// This intentionally uses message localCustomData, so the original message
  /// and its cross-device payload remain unchanged.
  Future<void> setVoiceToTextExpanded(
    V2TimMessage message, {
    required bool expanded,
  }) async {
    final transcript = TencentUtils.checkString(message.localCustomData);
    final localCustomData = LocalCustomDataModel.fromMap(
      json.decode(transcript ?? '{}'),
    );
    if (TencentUtils.checkString(localCustomData.voiceToText) == null ||
        localCustomData.isVoiceToTextExpanded == expanded) {
      return;
    }

    localCustomData.setVoiceToTextExpanded(expanded);
    await _persistLocalCustomData(message, localCustomData);
  }

  Future<V2TimValueCallback<V2TimMessage>?> sendRecordingAsTextMessage({
    required String soundPath,
    required int duration,
    required String convID,
    required ConvType convType,
  }) async {
    final coreServices = serviceLocator<CoreServicesImpl>();
    coreServices.callOnCallback(
      TIMCallback(
        type: TIMCallbackType.INFO,
        infoRecommendText: TIM_t('转文字中…'),
        infoCode: 6660422,
      ),
    );

    if (duration <= 0) {
      coreServices.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.INFO,
          infoRecommendText: TIM_t('说话时间太短'),
          infoCode: 6660404,
        ),
      );
      return null;
    }

    final text = await _transcribeLocalVoiceFile(
      soundPath,
      duration: duration,
      convID: convID,
      convType: convType,
    );
    if (text == null || text.isEmpty) {
      coreServices.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.INFO,
          infoRecommendText: _voiceToTextFailureMessage(),
          infoCode: 6660424,
        ),
      );
      return null;
    }

    await discardVoiceToTextPendingUpload();
    return sendTextMessage(text: text, convID: convID, convType: convType);
  }

  String _voiceToTextFailureMessage() {
    final detail = VoiceToTextService.lastErrorMessage?.trim() ??
        VoiceToTextBridge.lastErrorMessage?.trim();
    if (detail != null && detail.isNotEmpty) {
      return detail;
    }
    return TIM_t('转文字失败，请重试');
  }

  Future<String?> transcribeLocalVoiceFile(
    String soundPath, {
    int? duration,
    String? convID,
    ConvType? convType,
    VoiceToTextCancellationToken? cancellationToken,
  }) =>
      _transcribeLocalVoiceFile(
        soundPath,
        duration: duration,
        convID: convID,
        convType: convType,
        cancellationToken: cancellationToken,
      );

  String voiceToTextFailureMessage() => _voiceToTextFailureMessage();

  Future<void> discardVoiceToTextPendingUpload() async {}

  Future<void> revokeVoiceToTextPendingUpload() =>
      discardVoiceToTextPendingUpload();

  Future<String?> _transcribeLocalVoiceFile(
    String soundPath, {
    int? duration,
    String? convID,
    ConvType? convType,
    VoiceToTextCancellationToken? cancellationToken,
  }) async {
    VoiceToTextBridge.lastErrorMessage = null;
    if (convID == null || convType == null) {
      VoiceToTextService.lastErrorMessage = '当前会话已失效，请返回后重试';
      return null;
    }
    final result = await VoiceToTextService.convertLocalFile(
      soundPath: soundPath,
      duration: duration ?? 0,
      convID: convID,
      convType: convType,
      cancellationToken: cancellationToken,
    );
    if (result.isCancelled) {
      return null;
    }
    if (result.isSuccess) {
      return result.text;
    }
    VoiceToTextBridge.lastErrorMessage = result.errorMessage;
    return null;
  }

  int captureVoiceRecordAccountGeneration() =>
      SessionIdentityService.instance.generation;

  bool isVoiceRecordAccountGenerationCurrent(int generation) =>
      SessionIdentityService.instance.isGenerationCurrent(generation);

  Future<String?> _transcribeVoiceMessage(
    V2TimMessage message,
    String msgID,
  ) async {
    VoiceToTextBridge.lastErrorMessage = null;
    final result = await VoiceToTextService.convertMessage(
      message: message,
      msgID: msgID,
      resolveUrl: _resolveSoundMessageUrl,
    );
    if (result.isSuccess) {
      return result.text;
    }
    VoiceToTextBridge.lastErrorMessage = result.errorMessage;
    return null;
  }

  Future<void> _persistLocalCustomData(
    V2TimMessage message,
    LocalCustomDataModel localCustomData,
  ) async {
    message.localCustomData = json.encode(localCustomData.toMap());
    globalModel.markMessageChangedByMessage(conversationID, message);
    await globalModel.onMessageModified(message, conversationID);
    final msgID = TencentUtils.checkString(message.msgID);
    if (msgID != null) {
      await TencentImSDKPlugin.v2TIMManager.v2TIMMessageManager
          .setLocalCustomData(
        msgID: msgID,
        localCustomData: message.localCustomData ?? '',
      );
    }
    _notify();
  }

  Future<String?> _resolveSoundMessageUrl(
    V2TimMessage message,
    String msgID,
  ) async {
    final directUrl = TencentUtils.checkString(message.soundElem?.url);
    if (directUrl != null) {
      return directUrl;
    }

    const maxAttempts = 10;
    const perAttemptTimeout = Duration(seconds: 2);
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (_disposed) {
        return null;
      }
      V2TimValueCallback<V2TimMessageOnlineUrl>? onlineUrlResult;
      try {
        onlineUrlResult = await _messageService
            .getMessageOnlineUrl(msgID: msgID, reportError: false)
            .timeout(perAttemptTimeout);
      } catch (_) {
        onlineUrlResult = null;
      }
      if (onlineUrlResult?.code == 0) {
        final onlineUrl = TencentUtils.checkString(
          onlineUrlResult?.data?.soundElem?.url,
        );
        if (onlineUrl != null) {
          message.soundElem?.url = onlineUrl;
          return onlineUrl;
        }
      }
      if (attempt + 1 < maxAttempts) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    return null;
  }

  addToMessageReadReceiptList(V2TimMessage message) {
    if (!_canUseReadReceipt || message.msgID == null) {
      return;
    }
    if (_readReceiptMap.containsKey(message.msgID!)) {
      return;
    }
    _readReceiptMap[message.msgID!] = message;
    _scheduleReadReceiptFlush(const Duration(milliseconds: 300));
  }

  void _scheduleReadReceiptFlush(Duration delay) {
    final generation = _chatOpenGeneration;
    final scheduledConversationID = conversationID;
    _readReceiptFlushTimer?.cancel();
    _readReceiptFlushTimer = Timer(delay, () {
      if (!_isChatGenerationCurrent(generation, scheduledConversationID)) {
        return;
      }
      // Detach the bounded batch before the async SDK call. Keeping every
      // previously seen message in the map caused long-lived chat pages to
      // retain an ever-growing receipt set and rescan it on every flush.
      final batch = _readReceiptMap.values.toList(growable: false);
      _readReceiptMap.clear();
      unawaited(
        _setMsgReadReceipt(
          batch,
          generation: generation,
          scheduledConversationID: scheduledConversationID,
        ),
      );
    });
  }

  Future<void> _setMsgReadReceipt(
    List<V2TimMessage> messageList, {
    required int generation,
    required String scheduledConversationID,
  }) async {
    if (!_canUseReadReceipt) {
      _readReceiptMap.clear();
      return;
    }
    final msgIDList = List<String>.empty(growable: true);
    final pending = <String, V2TimMessage>{};
    for (var item in messageList) {
      final isSelf = item.isSelf ?? true;
      final needReadReceipt = item.needReadReceipt ?? false;
      final isRead = item.isRead ?? false;
      if (!isRead && !isSelf && needReadReceipt && item.msgID != null) {
        final msgID = item.msgID!;
        msgIDList.add(msgID);
        pending[msgID] = item;
      }
    }
    if (msgIDList.isEmpty) return;

    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) {
      for (final entry in pending.entries) {
        _readReceiptMap.putIfAbsent(entry.key, () => entry.value);
      }
      return;
    }
    try {
      await ReadReceiptOutboxStore.instance.enqueue(
        ownerUserId: identity.ownerUserId,
        messageIds: msgIDList,
      );
    } catch (_) {
      // Do not make an untracked SDK call. Restore the batch and retry after
      // the durable store becomes available.
      for (final entry in pending.entries) {
        _readReceiptMap.putIfAbsent(entry.key, () => entry.value);
      }
      _scheduleReadReceiptFlush(const Duration(seconds: 2));
      return;
    }

    dynamic result;
    try {
      result = await sendMessageReadReceipts(msgIDList);
    } catch (_) {
      result = null;
    }
    if (!_isChatGenerationCurrent(generation, scheduledConversationID)) {
      return;
    }
    if (!SessionIdentityService.instance.isCurrent(identity)) {
      return;
    }
    if (result?.code == 0) {
      await ReadReceiptOutboxStore.instance.acknowledge(
        ownerUserId: identity.ownerUserId,
        messageIds: msgIDList,
      );
      for (final item in pending.values) {
        item.needReadReceipt = false;
      }
      _readReceiptRetryCount = 0;
      return;
    }

    // The SDK did not acknowledge the batch. Restore it instead of clearing
    // needReadReceipt before the call and permanently losing the receipt.
    for (final entry in pending.entries) {
      _readReceiptMap.putIfAbsent(entry.key, () => entry.value);
    }
    if (_readReceiptRetryCount < _readReceiptRetryLimit) {
      _readReceiptRetryCount++;
      final exponent =
          _readReceiptRetryCount > 5 ? 4 : _readReceiptRetryCount - 1;
      final seconds = 1 << exponent;
      _scheduleReadReceiptFlush(Duration(seconds: seconds));
    }
  }

  sendMessageReadReceipts(List<String> messageIDList) async {
    if (!_canUseReadReceipt) {
      return null;
    }
    final res = await _messageService.sendMessageReadReceipts(
      messageIDList: messageIDList,
    );
    return res;
  }

  void _scheduleDeferredGroupMarkRead({
    Duration delay = const Duration(milliseconds: 1500),
  }) {
    final generation = _chatOpenGeneration;
    final scheduledConversationID = conversationID;
    _groupMarkReadDebounce?.cancel();
    _groupMarkReadDebounce = Timer(delay, () {
      if (!_isChatGenerationCurrent(generation, scheduledConversationID) ||
          globalModel.isChatListUserScrolling) {
        return;
      }
      unawaited(markMessageAsRead(force: true));
    });
  }

  markMessageAsRead({bool notify = true, bool force = false}) async {
    if (suppressReadReporting) {
      return null;
    }
    final currentConversationID = conversationID;
    final currentConversationType = conversationType;
    if (currentConversationID.isEmpty || currentConversationType == null) {
      return null;
    }
    final identity = SessionIdentityService.instance.capture();
    if (currentConversationType == ConvType.c2c) {
      return TencentConversationReadService.markRead(
        messageService: _messageService,
        conversationID: currentConversationID,
        isGroup: false,
        capturedIdentity: identity,
      );
    }
    if (!force && globalModel.isChatListUserScrolling) {
      _scheduleDeferredGroupMarkRead();
      return null;
    }
    if (!force) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastGroupMarkReadAtMs < _groupMarkReadMinIntervalMs) {
        return null;
      }
    }

    final res = await TencentConversationReadService.markRead(
      messageService: _messageService,
      conversationID: currentConversationID,
      isGroup: true,
      capturedIdentity: identity,
    );
    if (res.code == 0) {
      _lastGroupMarkReadAtMs = DateTime.now().millisecondsSinceEpoch;
      _groupMarkReadNotLoggedInRetries = 0;
    } else {
      debugPrint(
        'markGroupMessageAsRead failed: code=${res.code}, desc=${res.desc}',
      );
      if (res.code == -10113) {
        _lastGroupMarkReadAtMs = DateTime.now().millisecondsSinceEpoch +
            _groupMarkReadFrequencyBlockBackoffMs;
        _scheduleDeferredGroupMarkRead(
          delay: const Duration(
            milliseconds: _groupMarkReadFrequencyBlockBackoffMs,
          ),
        );
      }
      // 页面可能先于 IM 登录完成。6014 只表示 SDK 当前未登录，不是业务
      // 会话失效；延迟有限次数重试，待登录成功后补发已读标记。
      if (res.code == 6014 &&
          !_disposed &&
          _groupMarkReadNotLoggedInRetries <
              _groupMarkReadNotLoggedInRetryLimit) {
        _groupMarkReadNotLoggedInRetries++;
        _scheduleDeferredGroupMarkRead(
          delay: const Duration(milliseconds: 1000),
        );
      }
    }
    if (res.code == 10015 &&
        !_disposed &&
        conversationID == currentConversationID) {
      setGroupExist(false, notify: notify);
    }
    return res;
  }

  Future<void> loadSelfMemberInfo({required String groupID}) async {
    _muteDebugLog('[MUTE_DEBUG] loadSelfMemberInfo: START, groupID=$groupID');

    V2TimValueCallback<List<V2TimGroupMemberFullInfo>> getGroupMembersInfoRes =
        await TencentImSDKPlugin.v2TIMManager
            .getGroupManager()
            .getGroupMembersInfo(
      groupID: groupID,
      memberList: [selfModel.loginInfo?.userID ?? ""],
    );
    _muteDebugLog(
      '[MUTE_DEBUG] loadSelfMemberInfo: got response, code=${getGroupMembersInfoRes.code}',
    );
    if (getGroupMembersInfoRes.code == 0) {
      final userList = getGroupMembersInfoRes.data;
      final newSelfMemberInfo = userList?.firstWhereOrNull(
        (e) => e.userID == selfModel.loginInfo?.userID,
      );
      _muteDebugLog(
        '[MUTE_DEBUG] loadSelfMemberInfo: newSelfMemberInfo=${newSelfMemberInfo?.userID}, muteUntil=${newSelfMemberInfo?.muteUntil}',
      );
      if (newSelfMemberInfo != null) {
        final prev = selfMemberInfo;
        final merged = _mergeSelfMemberPreservingActiveMute(
          existing: prev,
          incoming: newSelfMemberInfo,
        );
        final muteChanged = (prev?.muteUntil ?? 0) != (merged.muteUntil ?? 0);
        final roleChanged = prev?.role != merged.role;
        final firstAssign = prev == null;
        selfMemberInfo = merged;
        _muteDebugLog(
          '[MUTE_DEBUG] loadSelfMemberInfo: selfMemberInfo updated, muteUntil=${selfMemberInfo?.muteUntil}',
        );
        GroupMemberStore.instance.putMember(
          groupID,
          selfMemberInfo,
          notify: false,
        );
        final selfId = selfMemberInfo!.userID?.trim() ?? '';
        if (selfId.isNotEmpty) {
          final targetIndex =
              groupMemberList?.indexWhere((e) => e?.userID == selfId) ?? -1;
          if (targetIndex >= 0) {
            groupMemberList![targetIndex] = selfMemberInfo;
          } else {
            groupMemberList = [...?groupMemberList, selfMemberInfo];
          }
        }
        if (firstAssign || muteChanged || roleChanged) {
          _muteDebugLog(
            '[MUTE_DEBUG] loadSelfMemberInfo: Bumping _groupMemberVersion from $_groupMemberVersion',
          );
          _groupMemberVersion++;
          _muteDebugLog(
            '[MUTE_DEBUG] loadSelfMemberInfo: Bumped _groupMemberVersion to $_groupMemberVersion',
          );
          _notify();
        }
      }
    }
    return;
  }

  /// Updates self member info directly without fetching from server.
  /// Used to preserve local mute state when server data might be stale.
  void updateSelfMemberInfo(
    V2TimGroupMemberFullInfo member, {
    required String groupID,
  }) {
    selfMemberInfo = member;

    // Also update in groupMemberList
    final selfId = member.userID?.trim() ?? '';
    if (selfId.isNotEmpty) {
      final targetIndex =
          groupMemberList?.indexWhere((e) => e?.userID == selfId) ?? -1;
      if (targetIndex >= 0) {
        groupMemberList![targetIndex] = member;
      }
    }

    // Update in GroupMemberStore
    GroupMemberStore.instance.putMember(groupID, member, notify: true);

    // Bump version to notify listeners about selfMemberInfo changes
    _groupMemberVersion++;

    // Notify listeners that self member info has changed
    _notify();
  }

  /// Updates self member's mute status from backend API response.
  /// Priority: isAllMuted > SDK data > Backend API
  /// Applies the authoritative snapshot, including explicit unmute (zero).
  Future<void> updateSelfMuteStatus({
    required String groupID,
    required int muteUntil,
    bool isAllMuted = false,
  }) async {
    _muteDebugLog(
      '[MUTE_DEBUG] updateSelfMuteStatus: groupID=$groupID, muteUntil=$muteUntil, isAllMuted=$isAllMuted',
    );
    final groupMuteChanged =
        _groupInfo != null && (_groupInfo?.isAllMuted ?? false) != isAllMuted;
    final versionBefore = _groupMemberVersion;
    void notifyGroupMuteChangeIfNeeded() {
      if (groupMuteChanged && _groupMemberVersion == versionBefore) {
        _groupMemberVersion++;
        _notify();
      }
    }
    if (_groupInfo != null) {
      _groupInfo!.isAllMuted = isAllMuted;
    }

    // 全员禁言优先级最高
    if (isAllMuted) {
      _muteDebugLog(
        '[MUTE_DEBUG] updateSelfMuteStatus: isAllMuted=true, setting muteUntil to max',
      );
      _setSelfMuteUntil(groupID, _kPermanentMuteUntil);
      notifyGroupMuteChangeIfNeeded();
      return;
    }

    // 该接口返回的是后端权威状态；0 表示已解除禁言，需要清掉本地旧状态。
    if (muteUntil <= 0) {
      final existingMute = selfMemberInfo?.muteUntil ?? 0;
      // 本地已是未禁言时无需清除；避免进群后 0→0 的无效通知重建消息列表。
      if (selfMemberInfo != null && existingMute > 0) {
        _muteDebugLog(
          '[MUTE_DEBUG] updateSelfMuteStatus: Backend returned unmuted state, '
          'clearing existing muteUntil=$existingMute',
        );
        _setSelfMuteUntil(groupID, 0);
        return;
      }
      if (groupMuteChanged) {
        _groupMemberVersion++;
        _notify();
      }
      return;
    }

    // 后端返回有效的禁言时间，使用后端数据
    _muteDebugLog(
      '[MUTE_DEBUG] updateSelfMuteStatus: Using backend muteUntil=$muteUntil',
    );
    _setSelfMuteUntil(groupID, muteUntil);
    notifyGroupMuteChangeIfNeeded();
  }

  /// Internal helper to update selfMemberInfo muteUntil
  void _setSelfMuteUntil(String groupID, int muteUntil) {
    final selfId =
        (selfMemberInfo?.userID ?? selfModel.loginInfo?.userID ?? '').trim();
    if (selfMemberInfo == null) {
      if (selfId.isEmpty) {
        _muteDebugLog(
          '[MUTE_DEBUG] _setSelfMuteUntil: selfMemberInfo is null and no selfId, cannot update',
        );
        return;
      }
      _muteDebugLog(
        '[MUTE_DEBUG] _setSelfMuteUntil: selfMemberInfo is null, creating stub for $selfId',
      );
      selfMemberInfo = V2TimGroupMemberFullInfo(
        userID: selfId,
        role: _groupInfo?.role ??
            GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER,
        muteUntil: muteUntil,
      );
      GroupMemberStore.instance.putMember(
        groupID,
        selfMemberInfo,
        notify: true,
      );
      _groupMemberVersion++;
      _notify();
      return;
    }
    // 值未变化时直接跳过，避免进群后 0→0 的无效写入 bump groupMemberVersion，
    // 触发整个消息列表（含头像）全量重建造成抖动。
    if ((selfMemberInfo!.muteUntil ?? 0) == muteUntil) {
      _muteDebugLog(
        '[MUTE_DEBUG] _setSelfMuteUntil: muteUntil unchanged ($muteUntil), skip notify',
      );
      return;
    }

    final updatedMember = V2TimGroupMemberFullInfo(
      userID: selfMemberInfo!.userID,
      role: selfMemberInfo!.role,
      nickName: selfMemberInfo!.nickName,
      nameCard: selfMemberInfo!.nameCard,
      friendRemark: selfMemberInfo!.friendRemark,
      faceUrl: selfMemberInfo!.faceUrl,
      joinTime: selfMemberInfo!.joinTime,
      muteUntil: muteUntil,
      customInfo: selfMemberInfo!.customInfo,
    );

    selfMemberInfo = updatedMember;

    if (selfId.isNotEmpty) {
      final targetIndex =
          groupMemberList?.indexWhere((e) => e?.userID == selfId) ?? -1;
      if (targetIndex >= 0) {
        groupMemberList![targetIndex] = updatedMember;
      }
    }

    GroupMemberStore.instance.putMember(groupID, updatedMember, notify: true);

    _groupMemberVersion++;
    _notify();

    _muteDebugLog(
      '[MUTE_DEBUG] _setSelfMuteUntil: Updated selfMemberInfo muteUntil=$muteUntil',
    );
  }

  /// SDK/成员列表可能带回过期的 muteUntil=0；保留本地仍有效的禁言截止时间。
  V2TimGroupMemberFullInfo _mergeSelfMemberPreservingActiveMute({
    required V2TimGroupMemberFullInfo? existing,
    required V2TimGroupMemberFullInfo incoming,
  }) {
    if (existing == null) {
      if (_groupInfo?.isAllMuted == true && !_isMuteExemptRole(incoming.role)) {
        return _copyMemberWithMuteUntil(incoming, _kPermanentMuteUntil);
      }
      return incoming;
    }
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final existingMute = existing.muteUntil ?? 0;
    final incomingMute = incoming.muteUntil ?? 0;
    final preferExisting = existingMute > nowSec && existingMute > incomingMute;
    final forceAllMute =
        _groupInfo?.isAllMuted == true && !_isMuteExemptRole(incoming.role);
    if (!preferExisting && !forceAllMute) {
      return incoming;
    }
    final muteUntil = forceAllMute
        ? _kPermanentMuteUntil
        : (preferExisting ? existingMute : incomingMute);
    return _copyMemberWithMuteUntil(incoming, muteUntil);
  }

  bool _isMuteExemptRole(int? role) {
    return GroupRolePolicy.isMuteExemptRole(role);
  }

  V2TimGroupMemberFullInfo _copyMemberWithMuteUntil(
    V2TimGroupMemberFullInfo source,
    int muteUntil,
  ) {
    return V2TimGroupMemberFullInfo(
      userID: source.userID,
      role: source.role,
      nickName: source.nickName,
      nameCard: source.nameCard,
      friendRemark: source.friendRemark,
      faceUrl: source.faceUrl,
      joinTime: source.joinTime,
      muteUntil: muteUntil,
      customInfo: source.customInfo,
    );
  }

  /// 只拉一页；禁止递归翻到 nextSeq 空。触底请用 [loadMoreGroupMembers]。
  Future<void> loadGroupMemberList({
    required String groupID,
    int count = 100,
    String? seq,
  }) async {
    final String? nextSeq = await _loadGroupMemberListFunction(
      groupID: groupID,
      seq: seq,
      count: count,
    );
    final fromList = groupMemberList?.firstWhereOrNull(
      (e) => e?.userID == selfModel.loginInfo?.userID,
    );
    if (fromList != null) {
      selfMemberInfo = _mergeSelfMemberPreservingActiveMute(
        existing: selfMemberInfo,
        incoming: fromList,
      );
      final selfId = selfMemberInfo?.userID?.trim() ?? '';
      if (selfId.isNotEmpty) {
        final targetIndex =
            groupMemberList?.indexWhere((e) => e?.userID == selfId) ?? -1;
        if (targetIndex >= 0) {
          groupMemberList![targetIndex] = selfMemberInfo;
        }
      }
    }
    GroupMemberStore.instance.putMembers(
      groupID,
      groupMemberList ?? const <V2TimGroupMemberFullInfo?>[],
    );
    // 仅当本窗口无下一页时标记「窗口齐」；有下一页则保持 false，禁止再触发全表。
    final done = nextSeq == null || nextSeq == "0" || nextSeq == "";
    groupMemberListComplete = done;
    _groupMemberVersion++;
    _notify();
  }

  Future<bool> loadMoreGroupMembers({int count = 100}) async {
    final gid = (_groupID ?? conversationID).trim();
    final seq = groupMemberListSeq.trim();
    if (gid.isEmpty || seq.isEmpty || seq == '0' || _disposed) {
      return false;
    }
    await loadGroupMemberList(groupID: gid, count: count, seq: seq);
    final next = groupMemberListSeq.trim();
    return next.isNotEmpty && next != '0';
  }

  /// 按 userId 定点刷新成员（踢人/禁言后），禁止整表。
  Future<void> refreshGroupMembersByUserIds({
    required String groupID,
    required List<String> userIds,
  }) async {
    final gid = groupID.trim();
    final ids = userIds
        .map(ChatIdFormat.rawUserUid)
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (gid.isEmpty || ids.isEmpty || _disposed) {
      return;
    }
    try {
      final res = await TencentImSDKPlugin.v2TIMManager
          .getGroupManager()
          .getGroupMembersInfo(groupID: gid, memberList: ids);
      if (res.code != 0) {
        return;
      }
      final byId = <String, V2TimGroupMemberFullInfo>{
        for (final m in res.data ?? const <V2TimGroupMemberFullInfo>[])
          if (ChatIdFormat.rawUserUid(m.userID).isNotEmpty)
            ChatIdFormat.rawUserUid(m.userID): m,
      };
      final missing = ids.where((id) => !byId.containsKey(id)).toList();
      if (missing.isNotEmpty) {
        GroupMemberStore.instance.removeMembers(gid, missing);
        groupMemberList = groupMemberList
                ?.where((member) => !missing
                    .contains(ChatIdFormat.rawUserUid(member?.userID)))
                .toList() ??
            groupMemberList;
      }
      _ensureGrowableGroupMemberList();
      for (final entry in byId.entries) {
        if (GroupMemberStore.instance.isRemovalTombstoned(gid, entry.key)) {
          continue;
        }
        final idx = groupMemberList?.indexWhere(
                (e) => ChatIdFormat.rawUserUid(e?.userID) == entry.key) ??
            -1;
        if (idx >= 0) {
          groupMemberList![idx] = entry.value;
        } else {
          groupMemberList = [...?groupMemberList, entry.value];
        }
        GroupMemberStore.instance.putMember(gid, entry.value, notify: false);
      }
      _groupMemberVersion++;
      _notify();
    } catch (_) {}
  }

  /// 等进页 hydrate 后再跑一次 open-shell，避免「仅 self」与「含 sender」各跑一轮。
  Future<void> _loadGroupMembersOpenShellOnce({required String groupID}) async {
    final gid = groupID.trim();
    if (gid.isEmpty || _disposed) {
      return;
    }
    final generation = _openShellGeneration;
    await globalModel.awaitOpenHydrateInFlight(
      conversationID,
      timeout: const Duration(milliseconds: 700),
    );
    if (_disposed || generation != _openShellGeneration) {
      return;
    }
    await loadGroupMembersForOpenShell(groupID: gid);
    unawaited(
      _supplementOpenShellSendersAfterHydrate(
        groupID: gid,
        generation: generation,
      ),
    );
  }

  /// hydrate 超时后仍会完成：再扫一轮 sender，只补 GroupMemberStore 没有的 id。
  /// 不得被 [_openShellCompletedGid] 短路。
  Future<void> _supplementOpenShellSendersAfterHydrate({
    required String groupID,
    required int generation,
  }) async {
    await globalModel.awaitOpenHydrateInFlight(
      conversationID,
      timeout: const Duration(seconds: 8),
    );
    if (_disposed || generation != _openShellGeneration) {
      return;
    }
    await _supplementOpenShellSenders(groupID: groupID, generation: generation);
  }

  Future<void> _supplementOpenShellSenders({
    required String groupID,
    required int generation,
  }) async {
    final gid = groupID.trim();
    if (gid.isEmpty || _disposed || generation != _openShellGeneration) {
      return;
    }
    final selfId = selfModel.loginInfo?.userID?.trim() ?? '';
    final userIds = <String>{};
    if (selfId.isNotEmpty) {
      userIds.add(selfId);
    }
    final warm = globalModel.rawMessageList(conversationID) ??
        globalModel.rawMessageList(gid);
    if (warm != null && warm.isNotEmpty) {
      final limit = warm.length < _openShellSenderLimit
          ? warm.length
          : _openShellSenderLimit;
      for (var i = 0; i < limit; i++) {
        final message = warm[i];
        final sender = (message.sender ?? message.userID ?? '').trim();
        if (sender.isNotEmpty) {
          userIds.add(sender);
        }
      }
    }

    final missing = <String>[];
    for (final userId in userIds) {
      if (GroupMemberStore.instance.memberOf(gid, userId) == null) {
        missing.add(userId);
      }
    }
    if (missing.isEmpty) {
      ChatHistoryTrace.log(
        'group_member_open_shell',
        conversationID: gid,
        extras: <String, Object?>{
          'supplement': true,
          'requested': userIds.length,
          'resolved': 0,
          'missingAfterStore': 0,
        },
      );
      return;
    }

    final fetched = <V2TimGroupMemberFullInfo>[];
    const chunkSize = 50;
    for (var offset = 0; offset < missing.length; offset += chunkSize) {
      if (_disposed || generation != _openShellGeneration) {
        return;
      }
      final end = offset + chunkSize > missing.length
          ? missing.length
          : offset + chunkSize;
      final chunk = missing.sublist(offset, end);
      try {
        final res = await _groupServices.getGroupMembersInfo(
            groupID: gid, memberList: chunk);
        if (res.code == 0 && res.data != null) {
          for (final member in res.data!) {
            final id = member.userID?.trim() ?? '';
            if (id.isEmpty) {
              continue;
            }
            fetched.add(member);
          }
        }
      } catch (_) {
        // 补齐失败不挡进页。
      }
    }

    if (_disposed || generation != _openShellGeneration) {
      return;
    }
    if (fetched.isEmpty) {
      ChatHistoryTrace.log(
        'group_member_open_shell',
        conversationID: gid,
        extras: <String, Object?>{
          'supplement': true,
          'requested': userIds.length,
          'resolved': 0,
          'missingAfterStore': missing.length,
        },
      );
      return;
    }

    GroupMemberStore.instance.putMembers(gid, fetched, notify: false);
    final existingIds = <String>{};
    for (final member
        in groupMemberList ?? const <V2TimGroupMemberFullInfo?>[]) {
      final id = member?.userID?.trim() ?? '';
      if (id.isNotEmpty) {
        existingIds.add(id);
      }
    }
    final additions = <V2TimGroupMemberFullInfo>[];
    for (final member in fetched) {
      final id = member.userID?.trim() ?? '';
      if (id.isEmpty || existingIds.contains(id)) {
        continue;
      }
      additions.add(member);
      existingIds.add(id);
    }
    if (additions.isNotEmpty) {
      groupMemberList = [...?groupMemberList, ...additions];
      _groupMemberVersion++;
      _notify();
    }
    ChatHistoryTrace.log(
      'group_member_open_shell',
      conversationID: gid,
      extras: <String, Object?>{
        'supplement': true,
        'requested': userIds.length,
        'resolved': fetched.length,
        'added': additions.length,
        'missingAfterStore': missing.length,
      },
    );
    ChatOpenPerfLog.mark(
      'group_member_open_shell',
      conversationID: gid,
      extras: <String, Object?>{
        'supplement': true,
        'requested': userIds.length,
        'resolved': fetched.length,
        'added': additions.length,
        'missingAfterStore': missing.length,
      },
    );
  }

  /// 进页最小成员集：自己 + 当前暖窗/首屏消息 sender（上限 [_openShellSenderLimit]）。
  /// 同一会话打开周期内只成功提交一次（in-flight 去重）。
  Future<void> loadGroupMembersForOpenShell({required String groupID}) async {
    final gid = groupID.trim();
    if (gid.isEmpty || _disposed) {
      return;
    }
    if (_openShellCompletedGid == gid) {
      return;
    }
    final existing = _openShellInFlight;
    if (existing != null) {
      await existing;
      return;
    }
    final generation = _openShellGeneration;
    final task = _loadGroupMembersForOpenShellImpl(
      groupID: gid,
      generation: generation,
    );
    _openShellInFlight = task;
    try {
      await task;
    } finally {
      if (identical(_openShellInFlight, task)) {
        _openShellInFlight = null;
      }
    }
  }

  Future<void> _loadGroupMembersForOpenShellImpl({
    required String groupID,
    required int generation,
  }) async {
    final gid = groupID.trim();
    if (gid.isEmpty ||
        _disposed ||
        generation != _openShellGeneration ||
        _openShellCompletedGid == gid) {
      return;
    }
    // The group cache may hold thousands of members from other screens.
    // Build only the current sender/self window, even when that cache is full.
    groupMemberListComplete = false;
    final selfId = selfModel.loginInfo?.userID?.trim() ?? '';
    final userIds = <String>{};
    if (selfId.isNotEmpty) {
      userIds.add(selfId);
    }
    final warm = globalModel.rawMessageList(conversationID) ??
        globalModel.rawMessageList(gid);
    if (warm != null && warm.isNotEmpty) {
      final limit = warm.length < _openShellSenderLimit
          ? warm.length
          : _openShellSenderLimit;
      for (var i = 0; i < limit; i++) {
        final message = warm[i];
        final sender = (message.sender ?? message.userID ?? '').trim();
        if (sender.isNotEmpty) {
          userIds.add(sender);
        }
      }
    }

    final merged = <String, V2TimGroupMemberFullInfo>{};
    final missing = <String>[];
    for (final userId in userIds) {
      final cached = GroupMemberStore.instance.memberOf(gid, userId);
      if (cached != null) {
        merged[userId] = cached;
      } else {
        missing.add(userId);
      }
    }

    const chunkSize = 50;
    for (var offset = 0; offset < missing.length; offset += chunkSize) {
      if (_disposed || generation != _openShellGeneration) {
        return;
      }
      final end = offset + chunkSize > missing.length
          ? missing.length
          : offset + chunkSize;
      final chunk = missing.sublist(offset, end);
      try {
        final res = await _groupServices.getGroupMembersInfo(
            groupID: gid, memberList: chunk);
        if (res.code == 0 && res.data != null) {
          for (final member in res.data!) {
            final id = member.userID?.trim() ?? '';
            if (id.isEmpty) {
              continue;
            }
            merged[id] = member;
          }
        }
      } catch (_) {
        // 最小集失败不挡进页。
      }
    }

    if (_disposed || generation != _openShellGeneration) {
      return;
    }

    if (selfMemberInfo != null) {
      final id = selfMemberInfo!.userID?.trim() ?? '';
      if (id.isNotEmpty) {
        merged[id] = _mergeSelfMemberPreservingActiveMute(
          existing: merged[id],
          incoming: selfMemberInfo!,
        );
      }
    } else if (selfId.isNotEmpty && !merged.containsKey(selfId)) {
      await loadSelfMemberInfo(groupID: gid);
      if (_disposed || generation != _openShellGeneration) {
        return;
      }
      if (selfMemberInfo != null) {
        final id = selfMemberInfo!.userID?.trim() ?? selfId;
        merged[id] = selfMemberInfo!;
      }
    }

    // 须可 grow：后续分页 loadMore 会 append；固定长度列表会抛 set length。
    final list =
        merged.values.map((e) => e as V2TimGroupMemberFullInfo?).toList();
    groupMemberList = list;
    _openShellCompletedGid = gid;
    if (list.isNotEmpty) {
      GroupMemberStore.instance.putMembers(gid, list, notify: false);
      _groupMemberVersion++;
      _notify();
    }
    ChatHistoryTrace.log(
      'group_member_open_shell',
      conversationID: gid,
      extras: <String, Object?>{
        'requested': userIds.length,
        'resolved': list.length,
        'missingAfterStore': missing.length,
        'hasSelf': selfId.isNotEmpty && merged.containsKey(selfId),
      },
    );
    ChatOpenPerfLog.mark(
      'group_member_open_shell',
      conversationID: gid,
      extras: <String, Object?>{
        'requested': userIds.length,
        'resolved': list.length,
        'missingAfterStore': missing.length,
        'hasSelf': selfId.isNotEmpty && merged.containsKey(selfId),
      },
    );
  }

  /// 退页：取消 open-shell 成员加载（禁言由 Chat 页 lifecycle 取消）。
  void cancelOpenSideMemberLoads() {
    _openShellGeneration++;
    _openShellInFlight = null;
    _openShellCompletedGid = null;
    _idleFullMemberLoadGeneration++;
    _fullMemberLoadInFlight = null;
  }

  /// 已废止整表拉取：保留入口兼容调用方，不再网络拉全量。
  @Deprecated(
    'Do not full-load group members; use open-shell / page / by-userIds',
  )
  Future<void> ensureGroupMemberListComplete({required String groupID}) async {
    return;
  }

  void processGroupMemberListEnter({
    required String groupID,
    required List<V2TimGroupMemberInfo> memberList,
  }) async {
    final List<V2TimGroupMemberFullInfo> fullInfoList =
        memberList.where((member) => member.userID != null).map((member) {
      return V2TimGroupMemberFullInfo(
        userID: member.userID!,
        nickName: member.nickName,
        nameCard: member.nameCard,
        friendRemark: member.friendRemark,
        faceUrl: member.faceUrl,
        onlineDevices: member.onlineDevices,
      );
    }).toList();

    for (final fullInfo in fullInfoList) {
      final exists =
          groupMemberList?.any((e) => e?.userID == fullInfo.userID) ?? false;
      if (!exists) {
        groupMemberList = [...?groupMemberList, fullInfo];
      }
    }
    GroupMemberStore.instance.clearRemovalTombstones(
      groupID,
      fullInfoList.map((member) => member.userID),
    );
    GroupMemberStore.instance.putMembers(groupID, fullInfoList);
    _groupMemberVersion++;
    _notify();
  }

  void processGroupMemberListLeave({
    required String groupID,
    required List<V2TimGroupMemberInfo> memberList,
  }) async {
    final userIDsToRemove = memberList
        .map((member) => ChatIdFormat.rawUserUid(member.userID))
        .where((id) => id.isNotEmpty)
        .toSet();

    groupMemberList = groupMemberList
            ?.where((member) => !userIDsToRemove
                .contains(ChatIdFormat.rawUserUid(member?.userID)))
            .toList() ??
        groupMemberList;
    GroupMemberStore.instance.removeMembers(
      groupID,
      userIDsToRemove,
      notify: false,
    );
    _groupMemberVersion++;
    _notify();
  }

  V2TimGroupMemberFullInfo? getGroupMember(String userID) {
    final uid = userID.trim();
    if (uid.isEmpty) {
      return null;
    }
    final gid = TencentUtils.checkString(_groupID) ?? conversationID;
    final live = GroupMemberStore.instance.memberOf(gid, uid);
    if (live != null) {
      return live;
    }
    final fromList = groupMemberList?.firstWhereOrNull((e) => e?.userID == uid);
    if (fromList != null) {
      return fromList;
    }
    return null;
  }

  String _normalizeC2CPeerID(String? value) {
    final text = value?.trim() ?? '';
    if (text.startsWith('c2c_')) {
      return text.substring(4);
    }
    return text;
  }

  String _normalizeGroupID(String? value) {
    final text = value?.trim() ?? '';
    if (text.startsWith('group_')) {
      return text.substring(6);
    }
    return text;
  }

  String _currentC2CPeerID() => _normalizeC2CPeerID(conversationID);

  String? _latestC2CName(String? userID) {
    final peerID = _normalizeC2CPeerID(userID);
    if (peerID.isEmpty) {
      return null;
    }
    final cached = TencentUtils.checkString(
      DisplayNameStore.instance.c2c(peerID),
    );
    if (cached != null) {
      return cached;
    }
    final conversationKey = 'c2c_$peerID';
    final selected = conversationViewModel.selectedConversation;
    if (selected?.conversationID == conversationKey) {
      final showName = TencentUtils.checkString(selected?.showName);
      if (showName != null) {
        return showName;
      }
    }
    final conversation = conversationViewModel.getConversation(conversationKey);
    return TencentUtils.checkString(conversation?.showName);
  }

  String getMessageDisplayName(V2TimMessage message) {
    if (conversationType == ConvType.group) {
      final userID = TencentUtils.checkString(message.sender) ??
          TencentUtils.checkString(message.userID);
      if (userID != null) {
        final member = getGroupMember(userID);
        final friendRemark = TencentUtils.checkString(member?.friendRemark) ??
            message.friendRemark;
        final nameCard =
            TencentUtils.checkString(member?.nameCard) ?? message.nameCard;
        final nickName =
            TencentUtils.checkString(member?.nickName) ?? message.nickName;
        final storeName = DisplayNameStore.instance.c2c(userID);
        final local = UserProfileLocalBridge.readCached(userID);
        final fingerprint = GroupSenderDisplayNameCache.fingerprint(
          friendRemark: friendRemark,
          nameCard: nameCard,
          nickName: nickName,
          storeName: storeName,
          localRemark: local?.remark,
          localNickname: local?.nickname,
        );
        final cached = _groupSenderDisplayNameCache.lookup(userID, fingerprint);
        if (cached != null) {
          return cached;
        }
        final name = resolveGroupSenderShowName(
          friendRemark: friendRemark,
          nameCard: nameCard,
          nickName: nickName,
          storeName: storeName,
          userID: userID,
        );
        if (name.isNotEmpty) {
          _groupSenderDisplayNameCache.put(userID, fingerprint, name);
          return name;
        }
      }
    } else if (conversationType == ConvType.c2c) {
      final loginID = TencentUtils.checkString(selfModel.loginInfo?.userID);
      final sender = TencentUtils.checkString(message.sender);
      final isSelfMessage = (message.isSelf == true) ||
          (loginID != null && sender != null && sender == loginID);
      if (!isSelfMessage) {
        for (final peerID in <String?>[
          _currentC2CPeerID(),
          message.userID,
          message.sender,
        ]) {
          final name = _latestC2CName(peerID);
          if (name != null) {
            return name;
          }
        }
      }
    }
    return resolveGroupSenderShowName(
      friendRemark: message.friendRemark,
      nameCard: message.nameCard,
      nickName: message.nickName,
      storeName: DisplayNameStore.instance.c2c(
        TencentUtils.checkString(message.sender) ??
            TencentUtils.checkString(message.userID) ??
            '',
      ),
      userID: TencentUtils.checkString(message.sender) ??
          TencentUtils.checkString(message.userID),
    );
  }

  String getMessageFaceUrl(V2TimMessage message) {
    return _resolveMessageFaceUrl(message) ?? '';
  }

  String? _resolveMessageFaceUrl(V2TimMessage message) {
    final loginID = TencentUtils.checkString(selfModel.loginInfo?.userID);
    final sender = TencentUtils.checkString(message.sender) ??
        TencentUtils.checkString(message.userID);
    final isSelfMessage = (message.isSelf == true) ||
        (loginID != null && sender != null && sender == loginID);

    if (isSelfMessage) {
      final selfFace = TencentUtils.checkString(selfModel.loginInfo?.faceUrl) ??
          TencentUtils.checkString(message.faceUrl);
      final localSelf = UserProfileLocalBridge.cachedAvatarUrl(
        loginID ?? sender,
        fallback: selfFace,
      );
      return TencentUtils.checkString(localSelf) ?? selfFace;
    }

    final localFace = TencentUtils.checkString(
      UserProfileLocalBridge.readCached(sender)?.avatarUrl,
    );
    if (localFace != null) {
      return localFace;
    }

    if (conversationType == ConvType.group) {
      if (sender != null) {
        final memberFace = TencentUtils.checkString(
          getGroupMember(sender)?.faceUrl,
        );
        if (memberFace != null) {
          return memberFace;
        }
      }
      return TencentUtils.checkString(message.faceUrl);
    }

    if (conversationType == ConvType.c2c) {
      final currentFace = TencentUtils.checkString(
        _currentChatUserInfo?.faceUrl,
      );
      if (currentFace != null) {
        return currentFace;
      }
      for (final peerID in <String?>[
        _currentC2CPeerID(),
        message.userID,
        message.sender,
      ]) {
        final normalized = _normalizeC2CPeerID(peerID);
        if (normalized.isEmpty) {
          continue;
        }
        final conv = conversationViewModel.getConversation('c2c_$normalized');
        final convFace = TencentUtils.checkString(conv?.faceUrl);
        if (convFace != null) {
          return convFace;
        }
      }
      return TencentUtils.checkString(message.faceUrl);
    }

    return TencentUtils.checkString(message.faceUrl);
  }

  Future<void> syncMessagesFaceUrlFromSdk(List<V2TimMessage> messages) async {
    if (messages.isEmpty) {
      return;
    }

    final loginID = TencentUtils.checkString(selfModel.loginInfo?.userID);

    if (conversationType == ConvType.group) {
      final groupID = TencentUtils.checkString(_groupID) ?? conversationID;
      final pendingUserIDs = <String>{};

      for (final message in messages) {
        final cached = _resolveMessageFaceUrl(message);
        if (cached != null) {
          _applySyncedFaceUrl(message, cached);
          continue;
        }
        final userID = TencentUtils.checkString(message.sender) ??
            TencentUtils.checkString(message.userID);
        if (userID == null || userID.isEmpty) {
          continue;
        }
        if (loginID != null && userID == loginID) {
          final selfFace = TencentUtils.checkString(
            selfModel.loginInfo?.faceUrl,
          );
          if (selfFace != null) {
            _applySyncedFaceUrl(message, selfFace);
          }
          continue;
        }
        pendingUserIDs.add(userID);
      }

      if (pendingUserIDs.isEmpty) {
        return;
      }

      final res = await TencentImSDKPlugin.manager
          ?.getGroupManager()
          .getGroupMembersInfo(
            groupID: groupID,
            memberList: pendingUserIDs.toList(),
          );
      if (res?.code != 0 || res?.data == null) {
        return;
      }

      GroupMemberStore.instance.putMembers(groupID, res!.data!);
      _groupMemberVersion++;

      for (final message in messages) {
        final faceUrl = _resolveMessageFaceUrl(message);
        if (faceUrl != null) {
          _applySyncedFaceUrl(message, faceUrl);
        }
      }
      _notify();
      return;
    }

    var peerNeedsFetch = false;
    for (final message in messages) {
      final sender = TencentUtils.checkString(message.sender) ??
          TencentUtils.checkString(message.userID);
      final isSelfMessage = (message.isSelf == true) ||
          (loginID != null && sender != null && sender == loginID);
      if (isSelfMessage) {
        final selfFace = TencentUtils.checkString(selfModel.loginInfo?.faceUrl);
        if (selfFace != null) {
          _applySyncedFaceUrl(message, selfFace);
        }
        continue;
      }
      final cached = _resolveMessageFaceUrl(message);
      if (cached != null) {
        _applySyncedFaceUrl(message, cached);
      } else {
        peerNeedsFetch = true;
      }
    }

    if (!peerNeedsFetch) {
      return;
    }

    final peerID = _currentC2CPeerID();
    if (peerID.isEmpty) {
      return;
    }

    String? peerFaceUrl;
    final friendRes = await _friendshipServices.getFriendsInfo(
      userIDList: [peerID],
    );
    if (friendRes != null && friendRes.isNotEmpty) {
      peerFaceUrl = TencentUtils.checkString(
        friendRes[0].friendInfo?.userProfile?.faceUrl,
      );
      _currentChatUserInfo = V2TimGroupMemberFullInfo(
        userID: peerID,
        faceUrl: friendRes[0].friendInfo?.userProfile?.faceUrl,
        nickName: friendRes[0].friendInfo?.userProfile?.nickName,
        friendRemark: friendRes[0].friendInfo?.friendRemark,
      );
    } else {
      final userRes = await _friendshipServices.getUsersInfo(
        userIDList: [peerID],
      );
      if (userRes != null && userRes.isNotEmpty) {
        peerFaceUrl = TencentUtils.checkString(userRes[0].faceUrl);
        _currentChatUserInfo = V2TimGroupMemberFullInfo(
          userID: peerID,
          faceUrl: userRes[0].faceUrl,
          nickName: userRes[0].nickName,
        );
      }
    }

    if (peerFaceUrl != null) {
      for (final message in messages) {
        final sender = TencentUtils.checkString(message.sender) ??
            TencentUtils.checkString(message.userID);
        final isSelfMessage = (message.isSelf == true) ||
            (loginID != null && sender != null && sender == loginID);
        if (!isSelfMessage) {
          _applySyncedFaceUrl(message, peerFaceUrl);
        }
      }
    }
    _notify();
  }

  void _applySyncedFaceUrl(V2TimMessage message, String faceUrl) {
    if (TencentUtils.checkString(message.faceUrl) == faceUrl) {
      return;
    }
    message.faceUrl = faceUrl;
  }

  String getGroupMessageDisplayName(V2TimMessage message) {
    return getMessageDisplayName(message);
  }

  String getMergerForwardSourceName() {
    if (conversationType == ConvType.group) {
      return TencentUtils.checkString(groupInfo?.groupName) ??
          TencentUtils.checkString(_conversationShowName()) ??
          TIM_t("群聊");
    }

    final peerInfo = _currentChatUserInfo;
    return TencentUtils.checkString(peerInfo?.friendRemark) ??
        TencentUtils.checkString(peerInfo?.nickName) ??
        TencentUtils.checkString(_latestC2CName(_currentC2CPeerID())) ??
        TencentUtils.checkString(_conversationShowName()) ??
        TencentUtils.checkString(_currentC2CPeerID()) ??
        TIM_t("聊天");
  }

  String getMergerForwardTitle() {
    final sourceName = getMergerForwardSourceName();
    return TIM_t_para("{{option1}}的聊天记录", "$sourceName的聊天记录")(
      option1: sourceName,
    );
  }

  String? _conversationShowName() {
    final convID = conversationID.trim();
    if (convID.isEmpty) {
      return null;
    }
    final candidates = <String>{
      convID,
      if (conversationType == ConvType.group)
        convID.startsWith('group_') ? convID : 'group_$convID'
      else
        convID.startsWith('c2c_') ? convID : 'c2c_$convID',
    };
    final selected = conversationViewModel.selectedConversation;
    if (selected != null && candidates.contains(selected.conversationID)) {
      final showName = TencentUtils.checkString(selected.showName);
      if (showName != null) {
        return showName;
      }
    }
    for (final id in candidates) {
      final showName = TencentUtils.checkString(
        conversationViewModel.getConversation(id)?.showName,
      );
      if (showName != null) {
        return showName;
      }
    }
    return null;
  }

  void applyDisplayNameChange(DisplayNameChange change) {
    if (change.type == 'c2c') {
      final peerID = _normalizeC2CPeerID(change.id);
      if (conversationType == ConvType.c2c) {
        if (_currentC2CPeerID() != peerID) {
          return;
        }
        _groupMemberVersion++;
        _notify();
        return;
      }
      if (conversationType == ConvType.group && peerID.isNotEmpty) {
        // 群气泡可能用 Store 备注兜底：该 uid 在成员表或当前消息里出现时刷新。
        final inMembers = getGroupMember(peerID) != null;
        final inMessages = !inMembers &&
            getOriginMessageList().any((m) {
              final sender = (m.sender ?? m.userID ?? '').trim();
              return sender == peerID;
            });
        if (inMembers || inMessages) {
          final member = getGroupMember(peerID);
          _groupUserShowName[peerID] = resolveGroupSenderShowName(
            friendRemark: member?.friendRemark,
            nameCard: member?.nameCard,
            nickName: member?.nickName,
            storeName: change.name,
            userID: peerID,
          );
          _groupMemberVersion++;
          _notify();
        }
      }
      return;
    }
    if (change.type == 'group') {
      final gid = _normalizeGroupID(
        TencentUtils.checkString(_groupID) ?? conversationID,
      );
      if (conversationType == ConvType.group &&
          gid == _normalizeGroupID(change.id)) {
        _groupMemberVersion++;
        _notify();
      }
    }
  }

  void applyGroupMemberChange(GroupMemberChange change) {
    final gid = TencentUtils.checkString(_groupID) ?? conversationID;
    if (conversationType != ConvType.group) {
      return;
    }
    if (change.groupID.isNotEmpty && change.groupID != gid) {
      return;
    }
    final member =
        change.member ?? GroupMemberStore.instance.memberOf(gid, change.userID);
    if (member == null) {
      return;
    }
    final targetIndex =
        groupMemberList?.indexWhere((e) => e?.userID == change.userID) ?? -1;
    if (targetIndex >= 0) {
      groupMemberList![targetIndex] = member;
    } else {
      groupMemberList = [...?groupMemberList, member];
    }
    if (change.userID == selfModel.loginInfo?.userID) {
      selfMemberInfo = member;
    }
    _groupUserShowName[change.userID] = resolveGroupSenderShowName(
      friendRemark: member.friendRemark,
      nameCard: member.nameCard,
      nickName: member.nickName,
      storeName: DisplayNameStore.instance.c2c(change.userID),
      userID: change.userID,
    );
    _groupSenderDisplayNameCache.invalidate(change.userID);
    _groupMemberVersion++;
    _notify();
  }

  void _notify() {
    if (_disposed) {
      return;
    }
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      _notifyNow();
      return;
    }
    if (_notifyScheduled) {
      return;
    }
    _notifyScheduled = true;
    final generation = _chatOpenGeneration;
    final scheduledConversationID = conversationID;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (_isChatGenerationCurrent(generation, scheduledConversationID)) {
        _notifyNow();
      }
    });
  }

  void _notifyNow() {
    try {
      notifyListeners();
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _ensureGrowableGroupMemberList() {
    final current = groupMemberList;
    if (current != null) {
      groupMemberList = List<V2TimGroupMemberFullInfo?>.from(current);
    }
  }

  Future<String?> _loadGroupMemberListFunction({
    required String groupID,
    int count = 100,
    String? seq,
  }) async {
    final generation = _chatOpenGeneration;
    final scheduledConversationID = conversationID;
    if (seq == null || seq == "" || seq == "0") {
      groupMemberList = <V2TimGroupMemberFullInfo?>[];
    } else {
      _ensureGrowableGroupMemberList();
    }
    try {
      final res = await _groupServices.getGroupMemberList(
        groupID: groupID,
        filter: GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ALL,
        count: count,
        nextSeq: seq ?? groupMemberListSeq,
      );
      if (!_isChatGenerationCurrent(generation, scheduledConversationID)) {
        return null;
      }
      final groupMemberListRes = res.data;
      if (res.code == 0 && groupMemberListRes != null) {
        final groupMemberListTemp = groupMemberListRes.memberInfoList ?? [];
        groupMemberList = [...?groupMemberList, ...groupMemberListTemp];
        groupMemberListSeq = groupMemberListRes.nextSeq ?? "0";
        GroupMemberStore.instance.putMembers(groupID, groupMemberListTemp);
      } else if (res.code == 10010) {
        isGroupExist = false;
      } else if (res.code == 10007) {
        isNotAMember = true;
      }
      return groupMemberListRes?.nextSeq;
    } catch (e) {
      return "";
    }
  }

  Future<(V2TimGroupInfo?, GroupReceiptAllowType?)> loadGroupInfo(
    String groupID,
  ) async {
    final generation = _chatOpenGeneration;
    final scheduledConversationID = conversationID;
    final groupInfoList = await _groupServices.getGroupsInfo(
      groupIDList: [groupID],
    );
    if (!_isChatGenerationCurrent(generation, scheduledConversationID)) {
      return (null, null);
    }
    if (groupInfoList != null && groupInfoList.isNotEmpty) {
      final groupRes = groupInfoList.first;
      ChatHistoryTrace.log(
        'group_info_loaded',
        conversationID: groupID,
        extras: <String, Object?>{
          'resultCode': groupRes.resultCode,
          'sdkGroupType': groupRes.groupInfo?.groupType,
          'isSupportTopic': groupRes.groupInfo?.isSupportTopic,
          'memberCount': groupRes.groupInfo?.memberCount,
          'lastMessageTime': groupRes.groupInfo?.lastMessageTime,
        },
      );
      if (groupRes.resultCode == 0) {
        final previousAllMuted = _groupInfo?.isAllMuted == true;
        _groupInfo = groupRes.groupInfo;
        final resolvedGroupId = groupRes.groupInfo?.groupID?.trim() ?? '';
        if (resolvedGroupId.isNotEmpty &&
            resolvedGroupId != groupID &&
            _looksLikeCommunityGroupId(resolvedGroupId)) {
          // 用 REST/本地真源覆盖会话里错误加成的 @TGS#_@TGS#m2…
          _groupID = resolvedGroupId;
        }

        const groupTypeMap = {
          "Meeting": GroupReceiptAllowType.meeting,
          "Public": GroupReceiptAllowType.public,
          "Work": GroupReceiptAllowType.work,
          "Community": GroupReceiptAllowType.community,
        };
        _groupType = groupTypeMap[groupRes.groupInfo?.groupType];

        final nowAllMuted = _groupInfo?.isAllMuted == true;
        var muteApplied = false;
        if (nowAllMuted &&
            !_isMuteExemptRole(selfMemberInfo?.role ?? _groupInfo?.role)) {
          final beforeMute = selfMemberInfo?.muteUntil ?? 0;
          _setSelfMuteUntil(groupID, _kPermanentMuteUntil);
          muteApplied = beforeMute != (selfMemberInfo?.muteUntil ?? 0);
        }
        if (!muteApplied) {
          if (previousAllMuted != nowAllMuted) {
            _groupMemberVersion++;
          }
          _notify();
        }
        return (_groupInfo, _groupType);
      }
    }
    return (null, null);
  }

  Future<void> updateMessageFromController({
    required String msgID,
    V2TimMessage? message,
  }) async {
    V2TimMessage? newMessage = message ??
        await tools.getExistingMessageByID(
          msgID: msgID,
          conversationType: conversationType ?? ConvType.c2c,
          conversationID: conversationID,
        );
    if (newMessage != null) {
      globalModel.onMessageModified(newMessage, conversationID);
    } else {
      loadChatRecord(count: HistoryMessageDartConstant.getCount);
    }
  }

  Future<V2TimValueCallback<V2TimMessageChangeInfo>?> modifyMessage({
    required V2TimMessage message,
  }) async {
    return _messageService.modifyMessage(message: message);
  }

  String _stripConversationPrefix(String value, String prefix) {
    final target = value.trim();
    if (target.toLowerCase().startsWith(prefix)) {
      return target.substring(prefix.length);
    }
    return target;
  }

  ConvType _forwardConversationType(V2TimConversation conversation) {
    if (conversation.type == 1) {
      return ConvType.c2c;
    }
    if (conversation.type == 2) {
      return ConvType.group;
    }
    final id = conversation.conversationID.trim().toLowerCase();
    if (id.startsWith('group_') ||
        conversation.groupID?.trim().isNotEmpty == true) {
      return ConvType.group;
    }
    if (id.startsWith('c2c_') ||
        conversation.userID?.trim().isNotEmpty == true) {
      return ConvType.c2c;
    }
    return ConvType.none;
  }

  String _forwardConversationId(V2TimConversation conversation) {
    final targetType = _forwardConversationType(conversation);
    if (targetType == ConvType.group) {
      final groupID = conversation.groupID?.trim();
      if (groupID != null && groupID.isNotEmpty) {
        return groupID;
      }
      return _stripConversationPrefix(conversation.conversationID, 'group_');
    }
    if (targetType == ConvType.c2c) {
      final userID = conversation.userID?.trim();
      if (userID != null && userID.isNotEmpty) {
        return userID;
      }
      return _stripConversationPrefix(conversation.conversationID, 'c2c_');
    }
    return conversation.conversationID.trim();
  }

  _ResolvedSendTarget? _resolveSendTarget({
    required String convID,
    required ConvType convType,
    required String messageID,
  }) {
    final rawConvID = convID.trim();
    if (rawConvID.isEmpty || convType == ConvType.none) {
      outputLogger.i(
        'send target invalid: empty target, convType=$convType, messageID=$messageID',
      );
      return null;
    }

    if (convType == ConvType.c2c) {
      if (rawConvID.toLowerCase().startsWith('group_')) {
        outputLogger.i(
          'send target invalid: C2C target has group prefix, convID=$rawConvID, messageID=$messageID',
        );
        return null;
      }
      final receiver = _stripConversationPrefix(rawConvID, 'c2c_');
      if (receiver.isEmpty) {
        outputLogger.i(
          'send target invalid: C2C receiver empty, convID=$rawConvID, messageID=$messageID',
        );
        return null;
      }
      return _ResolvedSendTarget(
        receiver: receiver,
        groupID: '',
        normalizedConvID: receiver,
      );
    }

    if (rawConvID.toLowerCase().startsWith('c2c_')) {
      outputLogger.i(
        'send target invalid: group target has C2C prefix, convID=$rawConvID, messageID=$messageID',
      );
      return null;
    }
    final groupID = _stripConversationPrefix(rawConvID, 'group_');
    if (groupID.isEmpty) {
      outputLogger.i(
        'send target invalid: groupID empty, convID=$rawConvID, messageID=$messageID',
      );
      return null;
    }
    return _ResolvedSendTarget(
      receiver: '',
      groupID: groupID,
      normalizedConvID: groupID,
    );
  }

  V2TimValueCallback<V2TimMessage> _buildInvalidTargetResult({
    required String id,
    required String convID,
    required ConvType convType,
    V2TimMessage? messageInfo,
  }) {
    final failedMessage = messageInfo ??
        V2TimMessage(
          id: id,
          msgID: id,
          elemType: MessageElemType.V2TIM_ELEM_TYPE_NONE,
        );
    failedMessage.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
    final coreServices = serviceLocator<CoreServicesImpl>();
    coreServices.callOnCallback(
      TIMCallback(
        type: TIMCallbackType.INFO,
        infoRecommendText: TIM_t('当前会话已失效，请返回后重试'),
        infoCode: 6660420,
      ),
    );
    outputLogger.i(
      'send target invalid: convID=$convID, convType=$convType, messageID=$id',
    );
    return V2TimValueCallback<V2TimMessage>(
      code: 6660420,
      desc: 'invalid conversation target',
      data: failedMessage,
    );
  }

  Future<V2TimValueCallback<V2TimMessage>> _sendMessage({
    required String id,
    required String convID,
    required ConvType convType,
    V2TimMessage? messageInfo,
    OfflinePushInfo? offlinePushInfo,
    bool? onlineUserOnly = false,
    MessagePriorityEnum priority = MessagePriorityEnum.V2TIM_PRIORITY_NORMAL,
    bool? isExcludedFromUnreadCount,
    bool? needReadReceipt,
    String? cloudCustomData,
    String? localCustomData,
    bool? isEditStatusMessage = false,
    bool? isExcludedFromContentModeration,
    bool preserveTargetGroupID = false,
    String? retryOfSdkLocalId,
    VoidCallback? onDispatchGranted,
  }) async {
    debugPrint(
      '[IM_SEND_INTENT] conv=$convID type=${convType.name} clientId=$id',
    );
    if (!canSendCapturedMedia) {
      return V2TimValueCallback<V2TimMessage>(
        code: -1,
        desc: 'media session changed',
        data: messageInfo,
      );
    }
    final target = _resolveSendTarget(
      convID: convID,
      convType: convType,
      messageID: id,
    );
    if (target == null) {
      debugPrint(
        '[IM_SEND_BLOCKED] conv=$convID clientId=$id reason=invalid_target',
      );
      removeSendingMessageID(id);
      final invalidResult = _buildInvalidTargetResult(
        id: id,
        convID: convID,
        convType: convType,
        messageInfo: messageInfo,
      );
      if (messageInfo != null) {
        messageInfo.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
        globalModel.updateMessage(
          invalidResult,
          convID,
          id,
          convType,
          groupType,
          setInputField,
        );
      }
      return invalidResult;
    }
    String receiver = target.receiver;
    String groupID = target.groupID;
    // IM peer-blacklist is sendMessage code (20007 if console fails closed).
    // App POST /me/blocks does not produce 20007. This gate only reads
    // confirmed relation canMessage=false.
    if (convType == ConvType.c2c) {
      final snapshot = C2cFriendMessageGuard.cachedUiSnapshot(receiver);
      if (snapshot != null &&
          snapshot.decision == C2cSendPermissionDecision.blocked &&
          snapshot.relationConfirmed) {
        debugPrint(
          '[IM_SEND_BLOCKED] conv=$convID clientId=$id reason=relation_blocked',
        );
        removeSendingMessageID(id);
        final failedMessage = messageInfo ??
            V2TimMessage(
              id: id,
              msgID: id,
              elemType: MessageElemType.V2TIM_ELEM_TYPE_NONE,
            );
        failedMessage.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
        final blockedResult = V2TimValueCallback<V2TimMessage>(
          code: C2cBlockedOutgoingMessageSync.blockedCode,
          desc: 'friend relation blocked',
          data: failedMessage,
        );
        globalModel.applyOutgoingSendResult(
          blockedResult,
          convID,
          id,
          convType,
          groupType,
          setInputField,
        );
        return blockedResult;
      }
    }
    // Dispatch C2C messages without a blocking friend-relation HTTP lookup.
    // Provider send results own rejection; UI relation refresh runs separately.
    if (convType == ConvType.group &&
        _groupType == null &&
        !preserveTargetGroupID) {
      await loadGroupInfo(groupID);
    }
    // SelfHosted 拉到的真源 groupID（如 @TGS#_mc…）优先于会话里错误加成的 ID。
    final infoGroupId = _groupInfo?.groupID?.trim() ?? '';
    if (convType == ConvType.group &&
        !preserveTargetGroupID &&
        infoGroupId.isNotEmpty &&
        infoGroupId != groupID &&
        (_looksLikeCommunityGroupId(infoGroupId) ||
            !_looksLikeCommunityGroupId(groupID))) {
      groupID = infoGroupId;
      if (_groupID != infoGroupId) {
        _groupID = infoGroupId;
      }
    }
    final useReadReceipt =
        (needReadReceipt ?? chatConfig.isShowReadingStatus) &&
            (convType != ConvType.group || _isReadReceiptAllowedGroup) &&
            !_looksLikeCommunityGroupId(groupID);
    if (!canSendCapturedMedia) {
      return V2TimValueCallback<V2TimMessage>(
        code: -1,
        desc: 'media session changed',
        data: messageInfo,
      );
    }
    if (messageInfo != null) {
      setLoadingMessageMap(convID, messageInfo);
    }
    final mediaKind = switch (messageInfo?.elemType) {
      MessageElemType.V2TIM_ELEM_TYPE_IMAGE => 'image',
      MessageElemType.V2TIM_ELEM_TYPE_VIDEO => 'video',
      MessageElemType.V2TIM_ELEM_TYPE_FILE => 'file',
      _ => null,
    };
    if (mediaKind != null) {
      final raw = localCustomData ?? messageInfo?.localCustomData;
      try {
        final decoded = raw == null || raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw);
        if (decoded is Map) {
          localCustomData = jsonEncode({...decoded, 'mediaSendKind': mediaKind});
          messageInfo?.localCustomData = localCustomData;
        }
      } catch (_) {
        // Preserve opaque metadata; it keeps the legacy serial admission.
      }
    }
    var retryDispatched = false;
    final coordinatedSend = await ImOutgoingSendCoordinator.instance.send(
      messageService: _messageService,
      retryOfSdkLocalId: retryOfSdkLocalId,
      onDispatchGranted: () { retryDispatched = true; onDispatchGranted?.call(); },
      sdkLocalId: id,
      conversationId: convType == ConvType.group ? groupID : receiver,
      conversationType: convType == ConvType.group
          ? ImConversationType.group
          : ImConversationType.c2c,
      receiver: receiver,
      groupID: groupID,
      fallbackMessage: messageInfo,
      needReadReceipt: useReadReceipt,
      priority: priority,
      localCustomData: localCustomData ?? messageInfo?.localCustomData,
      isExcludedFromUnreadCount: isExcludedFromUnreadCount ?? false,
      offlinePushInfo: offlinePushInfo,
      onlineUserOnly: onlineUserOnly ?? false,
      isExcludedFromContentModeration: isExcludedFromContentModeration ?? false,
      businessCloudCustomData: cloudCustomData ??
          (showC2cMessageEditStatus == true
              ? json.encode({
                  "messageFeature": {"needTyping": 1, "version": 1},
                })
              : ""),
      persistOutbox: isEditStatusMessage != true,
      expectedSessionIdentity: _outgoingMediaIdentity,
      onSyncMsgID: (syncMsgID) {
        globalModel.bindOutgoingSyncMsgId(convID, id, syncMsgID);
      },
    );
    var sendMsgRes = coordinatedSend.sdkResult;
    if (retryOfSdkLocalId != null && !retryDispatched) return sendMsgRes;
    if (!canSendCapturedMedia) return sendMsgRes;
    debugPrint(
      '[IM_SEND_COORDINATOR_RESULT] conv=$convID clientId=$id '
      'code=${sendMsgRes.code} desc=${sendMsgRes.desc} '
      'outcomeUnknown=${coordinatedSend.outcomeUnknown}',
    );
    if (_isOutgoingMediaCancelled(id) ||
        _isOutgoingMediaCancelled(messageInfo?.msgID) ||
        _isOutgoingMediaCancelled(sendMsgRes.data?.msgID)) {
      removeSendingMessageID(id);
      final sdkMsgID = TencentUtils.checkString(sendMsgRes.data?.msgID);
      if (sendMsgRes.code == 0 && sdkMsgID != null) {
        try {
          await _messageService.revokeMessage(
            msgID: sdkMsgID,
            webMessageInstance: sendMsgRes.data?.messageFromWeb,
          );
        } catch (_) {}
        await _messageService.deleteMessageFromLocalStorage(
          msgID: sdkMsgID,
          webMessageInstance: sendMsgRes.data?.messageFromWeb,
        );
      }
      globalModel.markOutgoingSendFailedByIdentity(
        conversationID: convID,
        clientId: id,
        msgID: sdkMsgID ?? messageInfo?.msgID,
        reason: 'cancelled',
      );
      globalModel.clearMessageProgress(id);
      globalModel.clearMessageProgress(messageInfo?.msgID);
      globalModel.clearMessageProgress(sendMsgRes.data?.msgID);
      _clearOutgoingMediaCancelled(id);
      _clearOutgoingMediaCancelled(messageInfo?.msgID);
      _clearOutgoingMediaCancelled(sendMsgRes.data?.msgID);
      return V2TimValueCallback<V2TimMessage>(
        code: -1,
        desc: 'cancelled',
        data: messageInfo,
      );
    }
    removeSendingMessageID(id);
    OutgoingVisibleProbe.log(
      'send_sdk_result',
      conversationID: convID,
      message: sendMsgRes.data ?? messageInfo,
      extras: <String, Object?>{
        'code': sendMsgRes.code,
        'desc': sendMsgRes.desc,
        'clientId': id,
        'hasData': sendMsgRes.data != null,
        'dataMsgID': sendMsgRes.data?.msgID ?? '',
        ...OutgoingVisibleProbe.trackedInList(
          globalModel.rawMessageList(convID),
        ),
      },
    );
    if (sendMsgRes.data != null) {
      OutgoingVisibleProbe.rememberSent(
        conversationID: convID,
        message: sendMsgRes.data!,
      );
    }
    // IM-08: when the SDK Future resolves OutcomeUnknown, the dispatch path
    // cannot prove the provider accepted or rejected the operation. The
    // Outbox main + recovery copy already record OutcomeUnknown; the
    // single Writer must keep the optimistic bubble in SENDING and wait
    // for history/realtime to claim it. Auto-committing a success/failed
    // projection here would resurrect an in-flight message or flash a
    // red retry icon on a still-pending send.
    var projectionCommitted = true;
    if (isEditStatusMessage == false) {
      projectionCommitted = globalModel.applyOutgoingSendResult(
        sendMsgRes,
        convID,
        id,
        convType,
        groupType,
        setInputField,
        coordinatedResult: coordinatedSend,
      );
    } else if (coordinatedSend.outcomeUnknown) {
      projectionCommitted = false;
    }
    if (globalModel.mayPublishOutgoingSendCompletion(convID, id, coordinatedSend)) {
      globalModel.insertPeerRejectedLocalTip(
        convID,
        sendMsgRes.code,
        clientId: id,
      );
    }
    if (projectionCommitted && coordinatedSend.canCompleteProjection) {
      await ImOutgoingSendCoordinator.instance.completeSuccessfulProjection(
        coordinatedSend,
      );
    }
    sendMsgRes = coordinatedSend.sdkResult;
    if (lifeCycle?.messageDidSend != null &&
        globalModel.mayPublishOutgoingSendCompletion(convID, id, coordinatedSend)) {
      lifeCycle!.messageDidSend(sendMsgRes);
    }

    return sendMsgRes;
  }

  List<V2TimMessage> getOriginMessageList() {
    return globalModel.rawMessageList(conversationID) ?? const <V2TimMessage>[];
  }

  /// 图集收集与 [TIMUIKitHistoryMessageList] 同源：走 display 投影并去掉时间分割线。
  List<V2TimMessage> getGalleryOriginMessageList() {
    final display =
        globalModel.getMessageList(conversationID) ?? const <V2TimMessage>[];
    return filterChatGalleryOriginRows(display);
  }

  Future<ChatMediaGalleryExpandPage> _loadGalleryHistoryPage({
    required HistoryMsgGetTypeEnum getType,
    required int count,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    required List<int> messageTypeList,
  }) async {
    final userID = conversationType == ConvType.c2c ? conversationID : null;
    final groupID = conversationType == ConvType.group ? conversationID : null;
    Future<V2TimMessageListResult?> fetch(HistoryMsgGetTypeEnum type) {
      return globalModel.getHistoryMessageListThroughIm06(
        count: count,
        getType: type,
        userID: userID,
        groupID: groupID,
        lastMsgID: lastMsgID,
        lastMsg: lastMsg,
        messageTypeList: messageTypeList,
      );
    }

    final result = await fetch(getType);
    final messages = result?.messageList ?? const <V2TimMessage>[];
    return ChatMediaGalleryExpandPage(
      messages: messages,
      isFinished: result?.isFinished ?? messages.isEmpty,
    );
  }

  /// 以当前聊天列表为种子，向本地库两侧分页扩窗。结果不写进聊天内存窗、不打云端。
  Future<List<V2TimMessage>> expandGalleryOriginMessageList({
    required V2TimMessage tappedMessage,
    required Set<ChatMediaPreviewType> types,
    void Function(List<V2TimMessage> oldestFirst)? onProgress,
    bool Function()? shouldContinue,
  }) async {
    final galleryConversation = conversationID;
    final galleryType = conversationType;
    final galleryGeneration = _chatOpenGeneration;
    final ownerIsCurrent =
        globalModel.captureMessageOwnerFence(galleryConversation);
    bool canContinue() =>
        !_disposed &&
        galleryGeneration == _chatOpenGeneration &&
        conversationID == galleryConversation &&
        conversationType == galleryType &&
        ownerIsCurrent() &&
        shouldContinue?.call() != false;
    if (!canContinue()) return const <V2TimMessage>[];
    // Keep revoked rows as identity tombstones while reconciling local history
    // and the short gallery cache. Their payload is excluded below, while the
    // msgID suppresses a stale unrevoked copy of the same media.
    final display =
        globalModel.getMessageList(conversationID) ?? const <V2TimMessage>[];
    final seed = display
        .where((message) => !isChatListNonMessageRow(message))
        .toList(growable: false);
    bool isPreviewable(V2TimMessage message) =>
        isChatMediaPreviewable(message, types);
    final cacheKey = ChatMediaGalleryExpandCache.keyFor(
      conversationID: conversationID,
      types: types,
    );
    final cached = resolveCachedChatMediaGallery(
      cachedOldestFirst: ChatMediaGalleryExpandCache.get(cacheKey),
      seedNewestFirst: seed,
      tappedMessage: tappedMessage,
      isPreviewable: isPreviewable,
    );
    if (cached != null) {
      ChatMediaGalleryExpandCache.put(cacheKey, cached);
      onProgress?.call(cached);
      return cached;
    }
    final expanded = await expandChatMediaGalleryMessages(
      seedNewestFirst: seed,
      tappedMessage: tappedMessage,
      types: types,
      isPreviewable: isPreviewable,
      loader: _loadGalleryHistoryPage,
      onProgress: onProgress,
      shouldContinue: canContinue,
    );
    // A canceled partial expansion must not become a full short-cache hit on
    // the next open, or suppress that preview's remaining local pages.
    if (!canContinue()) return const <V2TimMessage>[];
    ChatMediaGalleryExpandCache.put(cacheKey, expanded.messagesOldestFirst);
    return expanded.messagesOldestFirst;
  }

  void _prependOutgoingMessage(V2TimMessage messageInfoWithSender) {
    globalModel.markMessageEnterAnimation(messageInfoWithSender);
    globalModel.prepareForOutgoingMessage(conversationID);
    globalModel.assignOutgoingLocalSeq(conversationID, messageInfoWithSender);
    globalModel.commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: conversationID,
        eventID: 'optimistic:${messageInfoWithSender.id ?? ''}:'
            '${messageInfoWithSender.msgID ?? ''}',
        kind: MessageDeltaKind.optimisticInsert,
        source: MessageDeltaSource.sendPipeline,
        generation: globalModel.messageDeltaGenerationFor(conversationID),
        clearEpoch: globalModel.messageDeltaClearEpochFor(conversationID),
        upserts: [globalModel.messageDeltaRecord(messageInfoWithSender)],
      ),
    );
    globalModel.requestPinToBottom(conversationID, force: true);
    _scheduleReloadNewestAfterOutgoingSend(conversationID);
  }

  void _prependOutgoingMessageWithoutNotify(
    V2TimMessage messageInfoWithSender,
  ) {
    _prependOutgoingMessageForConversation(
      conversationID,
      messageInfoWithSender,
    );
  }

  void _prependOutgoingMessageForConversation(
    String convID,
    V2TimMessage messageInfoWithSender, {
    bool skipEnterAnimation = false,
  }) {
    final targetConvID = convID.trim();
    if (targetConvID.isEmpty) {
      return;
    }
    if (!skipEnterAnimation) {
      globalModel.markMessageEnterAnimation(messageInfoWithSender);
    }
    globalModel.prepareForOutgoingMessage(targetConvID);
    globalModel.assignOutgoingLocalSeq(targetConvID, messageInfoWithSender);
    globalModel.commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: targetConvID,
        eventID: 'optimistic:${messageInfoWithSender.id ?? ''}:'
            '${messageInfoWithSender.msgID ?? ''}',
        kind: MessageDeltaKind.optimisticInsert,
        source: MessageDeltaSource.sendPipeline,
        generation: globalModel.messageDeltaGenerationFor(targetConvID),
        clearEpoch: globalModel.messageDeltaClearEpochFor(targetConvID),
        upserts: [globalModel.messageDeltaRecord(messageInfoWithSender)],
      ),
    );
    OutgoingVisibleProbe.rememberSent(
      conversationID: targetConvID,
      message: messageInfoWithSender,
    );
    OutgoingVisibleProbe.log(
      'send_prepend',
      conversationID: targetConvID,
      message: messageInfoWithSender,
      extras: OutgoingVisibleProbe.trackedInList(
        globalModel.rawMessageList(targetConvID),
      ),
    );
    _seedOutgoingMediaRowHeight(messageInfoWithSender);
    globalModel.requestPinToBottom(targetConvID, force: true);
    _scheduleReloadNewestAfterOutgoingSend(targetConvID);
  }

  void _scheduleReloadNewestAfterOutgoingSend(String convID) {
    if (!haveMoreLatestData || _reloadNewestAfterOutgoingInFlight) {
      OutgoingVisibleProbe.log(
        'reload_newest_skip',
        conversationID: convID,
        extras: <String, Object?>{
          'haveMoreLatestData': haveMoreLatestData,
          'inFlight': _reloadNewestAfterOutgoingInFlight,
        },
      );
      return;
    }
    _reloadNewestAfterOutgoingInFlight = true;
    OutgoingVisibleProbe.log(
      'reload_newest_start',
      conversationID: convID,
      extras: OutgoingVisibleProbe.trackedInList(
        globalModel.rawMessageList(convID),
      ),
    );
    unawaited(() async {
      var reloadedNewest = false;
      try {
        // reloadNewestMessageWindow deliberately returns false while the user
        // is reading history.  Do not turn that deferred operation into a
        // bottom-pin in finally: that would race the pagination anchor and
        // pull ScrollPosition away from the row being read.
        reloadedNewest = await reloadNewestMessageWindow();
        OutgoingVisibleProbe.log(
          'reload_newest_done',
          conversationID: convID,
          extras: OutgoingVisibleProbe.trackedInList(
            globalModel.rawMessageList(convID),
          ),
        );
      } finally {
        _reloadNewestAfterOutgoingInFlight = false;
        final position = globalModel.getMessageListPosition(convID);
        final readingHistory = globalModel.isReadingHistory(convID) ||
            globalModel.isMemoryWindowSuppressed(convID) ||
            position == HistoryMessagePosition.awayTwoScreen ||
            position == HistoryMessagePosition.notShowLatest;
        if (reloadedNewest && !readingHistory) {
          globalModel.requestPinToBottom(convID, force: true);
        } else {
          OutgoingVisibleProbe.log(
            'reload_newest_pin_skipped',
            conversationID: convID,
            extras: <String, Object?>{
              'reloadedNewest': reloadedNewest,
              'readingHistory': readingHistory,
              'position': position.name,
              'memorySuppressed': globalModel.isMemoryWindowSuppressed(convID),
            },
          );
        }
      }
    }());
  }

  void _seedOutgoingMediaRowHeight(V2TimMessage message) {
    switch (message.elemType) {
      case MessageElemType.V2TIM_ELEM_TYPE_IMAGE:
      case MessageElemType.V2TIM_ELEM_TYPE_VIDEO:
        break;
      default:
        return;
    }
    final estimated = ChatMessageHeightCache.instance.estimateRowHeight(
      message,
    );
    if (estimated != null && estimated > 0) {
      ChatMessageHeightCache.instance.remember(message, estimated);
    }
  }

  int getConversationUnreadCount() {
    return globalModel.unreadCountForTongue;
  }

  Future<V2TimValueCallback<V2TimMessage>?> sendTextAtMessage({
    required String text,
    required String convID,
    required ConvType convType,
    required List<String> atUserList,
    List<GroupMentionOccurrence> mentionOccurrences = const [],
  }) async {
    if (text.isEmpty) {
      return null;
    }
    final typingBase = showC2cMessageEditStatus == true
        ? json.encode({
            "messageFeature": {"needTyping": 1, "version": 1},
          })
        : null;
    final cloudCustomData = mentionOccurrences.isEmpty
        ? null
        : GroupMentionOccurrenceCodec.mergeIntoCloudCustomData(
            typingBase,
            mentionOccurrences,
          );
    final optimisticId = _prependOptimisticTextPlaceholder(
      text: text,
      cloudCustomData: cloudCustomData,
      groupAtUserList: atUserList,
    );
    final textATMessageInfo = await _messageService.createTextAtMessage(
      text: text,
      atUserList: atUserList,
    );
    final messageInfo = textATMessageInfo?.messageInfo;
    if (textATMessageInfo == null || messageInfo == null) {
      _markOutgoingMediaSendFailed(
        convID: conversationID,
        clientId: optimisticId,
      );
      _notifyCreateMessageFailed(TIM_t('消息创建失败，请重试'));
      return null;
    }
    final messageInfoWithSender = tools.setUserInfoForMessage(
      messageInfo,
      textATMessageInfo.id!,
    );
    messageInfoWithSender.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
    if (cloudCustomData != null) {
      messageInfoWithSender.cloudCustomData = cloudCustomData;
    }
    _adoptOptimisticOutgoingTextMessage(
      optimisticId: optimisticId,
      newMessage: messageInfoWithSender,
    );
    return _sendMessage(
      convID: convID,
      id: textATMessageInfo.id as String,
      convType: ConvType.group,
      messageInfo: messageInfoWithSender,
      cloudCustomData: cloudCustomData,
      offlinePushInfo: tools.buildMessagePushInfo(
        textATMessageInfo.messageInfo!,
        convID,
        convType,
      ),
    );
  }

  Future<V2TimValueCallback<V2TimMessage>?> sendCustomMessage({
    required String data,
    required String convID,
    required ConvType convType,
  }) async {
    final customMessageInfo = await _messageService.createCustomMessage(
      data: data,
    );
    List<V2TimMessage> currentHistoryMsgList = getOriginMessageList();
    final messageInfo = customMessageInfo!.messageInfo;
    if (messageInfo != null) {
      final messageInfoWithSender = tools.setUserInfoForMessage(
        messageInfo,
        customMessageInfo.id!,
      );
      messageInfoWithSender.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
      addSendingMessageID(messageInfo.id);
      _prependOutgoingMessage(messageInfoWithSender);

      return _sendMessage(
        convID: convID,
        id: customMessageInfo.id as String,
        convType: convType,
        messageInfo: messageInfoWithSender,
        offlinePushInfo: tools.buildMessagePushInfo(
          customMessageInfo.messageInfo!,
          convID,
          convType,
        ),
      );
    }
    return null;
  }

  Future<V2TimValueCallback<V2TimMessage>?> sendFaceMessage({
    required int index,
    required String data,
    required String convID,
    required ConvType convType,
  }) async {
    final faceMessageInfo = await _messageService.createFaceMessage(
      index: index,
      data: data,
    );
    List<V2TimMessage> currentHistoryMsgList = getOriginMessageList();
    final messageInfo = faceMessageInfo!.messageInfo;
    if (messageInfo != null) {
      final messageInfoWithSender = tools.setUserInfoForMessage(
        messageInfo,
        faceMessageInfo.id!,
      );
      messageInfoWithSender.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
      addSendingMessageID(messageInfo.id);
      _prependOutgoingMessage(messageInfoWithSender);

      return _sendMessage(
        convID: convID,
        id: faceMessageInfo.id as String,
        convType: convType,
        messageInfo: messageInfoWithSender,
        offlinePushInfo: tools.buildMessagePushInfo(
          faceMessageInfo.messageInfo!,
          convID,
          convType,
        ),
      );
    }
    return null;
  }

  /// Accepted on release; neither file finalization nor upload belongs to a route.
  Future<void> sendFinalizingRecording({
    required Future<RecordResponse> completion,
    required String convID,
    required ConvType convType,
    required int estimatedDuration,
  }) async {
    final sender = captureMediaSender(convID: convID, convType: convType);
    if (!sender.canSendCapturedMedia) {
      // Consume the completion even when an account boundary rejects the task.
      try {
        await completion;
      } catch (_) {}
      return;
    }
    final id = sender._prependOptimisticSoundMessage(
      convID: sender.conversationID,
      soundPath: '',
      duration: estimatedDuration,
    );
    try {
      final result = await completion;
      if (!sender.canSendCapturedMedia || sender._isOutgoingMediaCancelled(id))
        return;
      final duration = result.audioTimeLength?.ceil() ?? 0;
      final path = result.path;
      if (result.msg != 'onStop' ||
          path == null ||
          path.isEmpty ||
          duration <= 0) {
        throw StateError('invalid recording');
      }
      final uniquePath = await SoundPlayer.copyRecordingToUniquePath(path);
      if (!sender.canSendCapturedMedia || sender._isOutgoingMediaCancelled(id))
        return;
      if (uniquePath == null) throw StateError('missing recording');
      final size = await File(uniquePath).length();
      if (size <= 44 || size > 28 * 1024 * 1024)
        throw StateError('invalid recording size');
      await sender.sendSoundMessage(
          soundPath: uniquePath,
          duration: duration,
          convID: convID,
          convType: convType,
          existingOptimisticId: id);
    } catch (_) {
      if (sender.canSendCapturedMedia &&
          !sender._isOutgoingMediaCancelled(id)) {
        sender._markOutgoingMediaSendFailed(
            convID: sender.conversationID, clientId: id);
      }
    }
  }

  Future<V2TimValueCallback<V2TimMessage>?> sendSoundMessage({
    required String soundPath,
    required int duration,
    required String convID,
    required ConvType convType,
    String? existingOptimisticId,
  }) async {
    if (!_isDetachedMediaSender) {
      return captureMediaSender(convID: convID, convType: convType)
          .sendSoundMessage(
              soundPath: soundPath,
              duration: duration,
              convID: convID,
              convType: convType,
              existingOptimisticId: existingOptimisticId);
    }
    DeviceSyncService.instance
        .beginForegroundMediaWork(reason: 'sendSoundMessage');
    try {
      if (await _trySendBackendAttachment(path: soundPath, nativeKind: 'sound',
          convID: convID, convType: convType, durationMs: duration * 1000,
          existingOptimisticId: existingOptimisticId)) {
        return null;
      }
      if (!canSendCapturedMedia ||
          _isOutgoingMediaCancelled(existingOptimisticId)) return null;
      final effectiveConvID =
          conversationID.isNotEmpty ? conversationID : convID.trim();
      final optimisticId = existingOptimisticId ??
          _prependOptimisticSoundMessage(
            convID: effectiveConvID,
            soundPath: soundPath,
            duration: duration,
          );
      final soundMessageInfo = await _messageService.createSoundMessage(
        soundPath: soundPath,
        duration: duration,
      );
      if (!canSendCapturedMedia || _isOutgoingMediaCancelled(optimisticId))
        return null;
      final messageInfo = soundMessageInfo?.messageInfo;
      if (soundMessageInfo == null || messageInfo == null) {
        _markOutgoingMediaSendFailed(
          convID: effectiveConvID,
          clientId: optimisticId,
        );
        _notifyCreateMessageFailed(TIM_t('语音消息创建失败，请重试'));
        return null;
      }

      final clientId = soundMessageInfo.id!;
      final messageInfoWithSender = tools.setUserInfoForMessage(
        messageInfo,
        clientId,
      );
      final soundElem = messageInfoWithSender.soundElem;
      if (soundElem != null && soundPath.isNotEmpty) {
        soundElem.path = soundPath;
        soundElem.localUrl ??= soundPath;
      }
      messageInfoWithSender.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
      applyOutgoingStableIdToMessage(messageInfoWithSender, clientId);
      _swapOutgoingMessage(
        convID: effectiveConvID,
        oldClientId: optimisticId,
        newMessage: messageInfoWithSender,
      );
      chatUiStateStore.bindMessageAlias(
        effectiveConvID,
        optimisticId,
        ChatUiStateStore.messageKeyOf(messageInfoWithSender),
      );
      addSendingMessageID(clientId);
      globalModel.setUploadProgressRowLocal(clientId, 0);
      globalModel.setFileMessageLocationRowLocal(clientId, soundPath);
      globalModel.markMessageRowsChangedByMsgIDs([
        optimisticId,
        clientId,
        messageInfoWithSender.msgID,
      ]);

      return await _sendMessage(
        convID: effectiveConvID,
        id: clientId,
        preserveTargetGroupID: true,
        convType: conversationType ?? convType,
        messageInfo: messageInfoWithSender,
        offlinePushInfo: tools.buildMessagePushInfo(
          soundMessageInfo.messageInfo!,
          effectiveConvID,
          conversationType ?? convType,
        ),
      );
    } finally {
      DeviceSyncService.instance
          .endForegroundMediaWork(reason: 'sendSoundMessage');
    }
  }

  Future<V2TimValueCallback<V2TimMessage>?> sendReplyMessage({
    required String text,
    required String convID,
    required ConvType convType,
    List<String>? atUserIDList,
    List<GroupMentionOccurrence> mentionOccurrences = const [],
  }) async {
    if (text.isEmpty) {
      return null;
    }
    final replyTarget = _composerUi.repliedMessage;
    if (replyTarget == null) {
      return null;
    }
    final hasNickName =
        replyTarget.nickName != null && replyTarget.nickName != "";
    var cloudCustomData = json.encode({
      "messageReply": {
        "messageID": replyTarget.msgID,
        "messageAbstract": tools.getMessageAbstract(
          replyTarget,
          abstractMessageBuilder,
        ),
        "messageSender":
            hasNickName ? replyTarget.nickName : replyTarget.sender,
        "messageType": replyTarget.elemType,
        "version": 1,
      },
    });
    cloudCustomData = GroupMentionOccurrenceCodec.mergeIntoCloudCustomData(
      cloudCustomData,
      mentionOccurrences,
    );
    final normalizedAtUserIDs = (atUserIDList ?? const <String>[])
        .map((userID) => userID.trim())
        .where((userID) => userID.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final optimisticId = _prependOptimisticTextPlaceholder(
      text: text,
      cloudCustomData: cloudCustomData,
      groupAtUserList:
          normalizedAtUserIDs.isEmpty ? null : normalizedAtUserIDs,
    );
    // The reply metadata is already captured by the optimistic bubble. Clear
    // the composer immediately instead of waiting for the network result. It
    // also prevents an older send completion from clearing a newly selected
    // reply target.
    final submissionBoundary = ImDraftSubmissionContext.current;
    if (submissionBoundary == null) {
      repliedMessage = null;
    } else {
      submissionBoundary.onAccepted(() {
        if (identical(_composerUi.repliedMessage, replyTarget)) repliedMessage = null;
      });
    }
    final V2TimMsgCreateInfoResult? textMessageInfo =
        normalizedAtUserIDs.isEmpty
            ? await _messageService.createTextMessage(text: text)
            : await _messageService.createTextAtMessage(
                text: text,
                atUserList: normalizedAtUserIDs,
              );
    final messageInfo = textMessageInfo?.messageInfo;
    if (textMessageInfo == null || messageInfo == null) {
      _markOutgoingMediaSendFailed(
        convID: conversationID,
        clientId: optimisticId,
      );
      if (_composerUi.repliedMessage == null) {
        repliedMessage = replyTarget;
      }
      _notifyCreateMessageFailed(TIM_t('消息创建失败，请重试'));
      return null;
    }
    final messageInfoWithSender = tools.setUserInfoForMessage(
      messageInfo,
      textMessageInfo.id!,
    );
    messageInfoWithSender.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
    messageInfoWithSender.cloudCustomData = cloudCustomData;
    _adoptOptimisticOutgoingTextMessage(
      optimisticId: optimisticId,
      newMessage: messageInfoWithSender,
    );
    return _sendMessage(
      convID: convID,
      id: textMessageInfo.id as String,
      convType: convType,
      messageInfo: messageInfoWithSender,
      offlinePushInfo: tools.buildMessagePushInfo(
        messageInfoWithSender,
        convID,
        convType,
      ),
      cloudCustomData: messageInfoWithSender.cloudCustomData,
      needReadReceipt: _canUseReadReceipt,
    );
  }

  void _notifyCreateMessageFailed(String text) {
    final coreServices = serviceLocator<CoreServicesImpl>();
    coreServices.callOnCallback(
      TIMCallback(
        type: TIMCallbackType.INFO,
        infoRecommendText: text,
        infoCode: 6660421,
      ),
    );
  }

  String _safeVideoType(String? videoPath) {
    final raw = videoPath == null || !videoPath.contains('.')
        ? ''
        : videoPath.split('.').last.toLowerCase();
    const supported = {'mp4', 'mov', 'm4v', '3gp'};
    if (supported.contains(raw)) {
      return raw;
    }
    return 'mp4';
  }

  /// 立即插入图片发送中占位气泡，返回 optimistic clientId。
  /// 不做压缩 / createImageMessage / _sendMessage。
  String beginOptimisticImagePlaceholder({
    required String convID,
    required String imagePath,
    int? imageWidth,
    int? imageHeight,
    bool probeSizeSynchronously = true,
  }) {
    final optimisticIds = beginOptimisticImagePlaceholders(
      convID: convID,
      inputs: [
        OptimisticImagePlaceholderInput(
          imagePath: imagePath,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
        ),
      ],
      probeSizeSynchronously: probeSizeSynchronously,
    );
    return optimisticIds.isEmpty ? '' : optimisticIds.first;
  }

  /// 多图发送一次性写入消息列表，避免逐张复制整个列表、逐张贴底和连续重建。
  List<String> beginOptimisticImagePlaceholders({
    required String convID,
    required List<OptimisticImagePlaceholderInput> inputs,
    bool probeSizeSynchronously = false,
    bool requestInitialPin = true,
  }) {
    if (!canSendCapturedMedia || inputs.isEmpty) {
      return const <String>[];
    }
    final effectiveConvID =
        conversationID.isNotEmpty ? conversationID : convID.trim();
    if (effectiveConvID.isEmpty) {
      return const <String>[];
    }

    final optimisticMessages = <V2TimMessage>[];
    final optimisticIds = <String>[];
    final animateRows = inputs.length == 1;
    globalModel.prepareForOutgoingMessage(effectiveConvID);

    for (final input in inputs) {
      Size? imageSize;
      if (input.imageWidth != null &&
          input.imageHeight != null &&
          input.imageWidth! > 0 &&
          input.imageHeight! > 0) {
        imageSize = Size(
          input.imageWidth!.toDouble(),
          input.imageHeight!.toDouble(),
        );
      }
      if (probeSizeSynchronously &&
          imageSize == null &&
          input.imagePath.trim().isNotEmpty) {
        imageSize = readLocalImageSizeSync(input.imagePath);
      }

      final optimisticId = _nextOptimisticClientId();
      final optimistic = tools.setUserInfoForMessage(
        V2TimMessage(
          elemType: MessageElemType.V2TIM_ELEM_TYPE_IMAGE,
          imageElem: V2TimImageElem(path: input.imagePath),
          // The SDK assigns msgID only after createMessage.  Keep a distinct
          // random identity during the pre-SDK window; otherwise dedupe sees
          // multiple pending images with null sender/time/seq/random as one.
          random: optimisticId.hashCode,
        ),
        optimisticId,
      );
      optimistic.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
      applyOutgoingStableIdToMessage(optimistic, optimisticId);
      if (input.batchId != null && input.batchIndex != null) {
        applyChatMediaBatchToMessage(
          optimistic,
          batchId: input.batchId!,
          batchIndex: input.batchIndex!,
        );
      }
      setImageSourcePending(optimistic, input.sourcePending);
      // Admit visible batch previews over successive frames instead of
      // starting six large decodes on the picker-return frame.
      setImageDecodeStagger(optimistic, inputs.length > 1);
      addSendingMessageID(optimisticId);
      globalModel.setMessageProgress(optimisticId, 0);
      if (imageSize != null && imageSize.width > 0 && imageSize.height > 0) {
        applyImageLayoutToMessage(optimistic, imageSize);
      }
      globalModel.setFileMessageLocation(
        optimisticId,
        input.imagePath,
        imageSize: imageSize,
      );
      if (animateRows) {
        globalModel.markMessageEnterAnimation(optimistic);
      }
      globalModel.assignOutgoingLocalSeq(effectiveConvID, optimistic);
      _seedOutgoingMediaRowHeight(optimistic);
      optimisticIds.add(optimisticId);
      optimisticMessages.add(optimistic);
    }

    final commit = globalModel.commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: effectiveConvID,
        eventID: 'optimistic_batch:${optimisticIds.join(',')}',
        kind: MessageDeltaKind.optimisticInsert,
        source: MessageDeltaSource.sendPipeline,
        generation: globalModel.messageDeltaGenerationFor(effectiveConvID),
        clearEpoch: globalModel.messageDeltaClearEpochFor(effectiveConvID),
        upserts: <V2TimMessage>[
          ...optimisticMessages.reversed,
        ].reversed.map(globalModel.messageDeltaRecord).toList(growable: false),
      ),
    );
    outputLogger.i(
      'gallery_placeholder_batch count=${optimisticMessages.length} '
      'ids=${optimisticMessages.map((m) => '${m.id}/${readOutgoingStableId(m)}/${m.random}').join(',')} '
      'rawAfter=${commit?.rawCount ?? -1}',
    );
    if (requestInitialPin) {
      globalModel.requestPinToBottom(effectiveConvID, force: true);
    }
    return optimisticIds;
  }

  /// Resolves a pre-export gallery row without replacing its stable identity.
  bool hydrateOptimisticImagePlaceholder({
    required String convID,
    required String clientId,
    required String imagePath,
    int? imageWidth,
    int? imageHeight,
  }) {
    if (!canSendCapturedMedia || _isOutgoingMediaCancelled(clientId))
      return false;
    final targetConvID = convID.trim();
    final targetClientId = clientId.trim();
    final targetPath = imagePath.trim();
    if (targetConvID.isEmpty || targetClientId.isEmpty || targetPath.isEmpty) {
      return false;
    }
    final messages = globalModel.rawMessageList(targetConvID);
    if (messages == null) {
      outputLogger.i(
        'gallery_hydrate_result client=$targetClientId found=false list=null',
      );
      return false;
    }
    outputLogger.i(
      'gallery_hydrate_begin client=$targetClientId pathReady=${targetPath.isNotEmpty} list=${messages.length}',
    );
    V2TimMessage? target;
    for (final message in messages) {
      if (message.id == targetClientId ||
          readOutgoingStableId(message) == targetClientId) {
        target = message;
        break;
      }
    }
    if (target == null || !isImageSourcePending(target)) {
      outputLogger.i(
        'gallery_hydrate_result client=$targetClientId found=${target != null} '
        'pending=${target != null && isImageSourcePending(target)}',
      );
      return false;
    }
    target.imageElem ??= V2TimImageElem();
    target.imageElem!.path = targetPath;
    setImageSourcePending(target, false);
    setImageDecodeStagger(target, true);
    Size? imageSize;
    if (imageWidth != null &&
        imageHeight != null &&
        imageWidth > 0 &&
        imageHeight > 0) {
      imageSize = Size(imageWidth.toDouble(), imageHeight.toDouble());
      applyImageLayoutToMessage(target, imageSize);
    }
    globalModel.setFileMessageLocation(
      targetClientId,
      targetPath,
      imageSize: imageSize,
    );
    globalModel.markMessageRowsChangedByMsgIDs([targetClientId, target.msgID]);
    return true;
  }

  /// 立即插入视频发送中气泡。时长、封面、转码等准备工作在气泡出现后执行。
  String beginOptimisticVideoPlaceholder({
    required String convID,
    required String videoPath,
    int? duration,
    String? snapshotPath,
    bool requestInitialPin = true,
  }) {
    if (!canSendCapturedMedia) return '';
    final effectiveConvID =
        conversationID.isNotEmpty ? conversationID : convID.trim();
    return _prependOptimisticVideoMessage(
      convID: effectiveConvID,
      videoPath: videoPath,
      duration: duration,
      snapshotPath: snapshotPath,
      requestInitialPin: requestInitialPin,
    );
  }

  /// Fills a video placeholder once the picker has produced a stable local
  /// path. This is deliberately separate from SDK message creation so the
  /// bubble can appear while file staging and thumbnail work are still running.
  bool hydrateOptimisticVideoPlaceholder({
    required String convID,
    required String clientId,
    required String videoPath,
    int? duration,
    String? snapshotPath,
  }) {
    if (!canSendCapturedMedia || _isOutgoingMediaCancelled(clientId))
      return false;
    final targetConvID = convID.trim();
    final targetClientId = clientId.trim();
    final targetPath = videoPath.trim();
    if (targetConvID.isEmpty || targetClientId.isEmpty || targetPath.isEmpty) {
      return false;
    }
    final messages = globalModel.rawMessageList(targetConvID);
    if (messages == null) return false;
    V2TimMessage? target;
    for (final message in messages) {
      if (message.id == targetClientId ||
          readOutgoingStableId(message) == targetClientId) {
        target = message;
        break;
      }
    }
    if (target == null ||
        target.elemType != MessageElemType.V2TIM_ELEM_TYPE_VIDEO) {
      return false;
    }
    target.videoElem ??= V2TimVideoElem();
    target.videoElem!.videoPath = targetPath;
    if (duration != null && duration > 0) {
      target.videoElem!.duration = duration;
    }
    final snapshot = TencentUtils.checkString(snapshotPath);
    if (snapshot != null) {
      target.videoElem!.snapshotPath = snapshot;
    }
    globalModel.setFileMessageLocation(targetClientId, targetPath);
    globalModel.markMessageRowsChangedByMsgIDs([targetClientId, target.msgID]);
    return true;
  }

  /// Removes a local media placeholder when the user leaves the captured chat
  /// before the file is ready to be handed to the SDK.
  void markOptimisticMediaPlaceholderFailed({
    required String convID,
    required String clientId,
  }) {
    if (!canSendCapturedMedia) return;
    final targetConvID = convID.trim();
    final targetClientId = clientId.trim();
    if (targetConvID.isEmpty || targetClientId.isEmpty) return;
    _markOutgoingMediaSendFailed(
      convID: targetConvID,
      clientId: targetClientId,
    );
  }

  void cancelOptimisticMediaPlaceholder({
    required String convID,
    required String clientId,
  }) {
    if (!canSendCapturedMedia) return;
    final targetConvID = convID.trim();
    final targetClientId = clientId.trim();
    if (targetConvID.isEmpty || targetClientId.isEmpty) {
      return;
    }
    _removeOutgoingMessage(convID: targetConvID, clientId: targetClientId);
  }

  /// The oversized-video task replaces an unsent native placeholder. A plain
  /// list replacement would retain it as an in-flight send (or revive it after
  /// history completes). Retire its local identity through the Writer instead.
  void retireBackendVideoPlaceholder({
    required String convID,
    required String clientId,
  }) {
    if (!canSendCapturedMedia ||
        convID.trim().isEmpty ||
        clientId.trim().isEmpty) {
      return;
    }
    globalModel.commitMessageDelta(MessageDelta<V2TimMessage>(
      conversationKey: convID,
      eventID: 'backend_video_handoff:$clientId',
      kind: MessageDeltaKind.delete,
      source: MessageDeltaSource.sendPipeline,
      generation: globalModel.messageDeltaGenerationFor(convID),
      clearEpoch: globalModel.messageDeltaClearEpochFor(convID),
      localDeletes: {clientId},
    ));
    globalModel.clearMessageProgress(clientId);
    removeSendingMessageID(clientId);
  }

  Future<bool> _trySendBackendAttachment({
    required String? path,
    required String nativeKind,
    required String convID,
    required ConvType convType,
    String? batchId,
    int? batchIndex,
    dynamic inputElement,
    String? name,
    String? snapshotPath,
    String? existingOptimisticId,
    int? durationMs,
    int? width,
    int? height,
  }) async {
    if (inputElement != null || path == null || path.isEmpty) return false;
    final attachments = ChatAttachmentService.instance;
    if (!await attachments.handles(path, nativeKind)) return false;
    if (!canSendCapturedMedia || _isOutgoingMediaCancelled(existingOptimisticId)) {
      return true;
    }
    final effectiveID = conversationID.isNotEmpty ? conversationID : convID.trim();
    final group = (conversationType ?? convType) == ConvType.group;
    final prefix = group ? 'group_' : 'c2c_';
    final targetID = effectiveID.startsWith(prefix)
        ? effectiveID.substring(prefix.length) : effectiveID;
    var handedOff = false;
    void onQueued() {
      handedOff = true;
      if (!canSendCapturedMedia) return;
      if (existingOptimisticId != null) {
        if (nativeKind == 'video') {
          retireBackendVideoPlaceholder(convID: effectiveID, clientId: existingOptimisticId);
        } else {
          _removeOutgoingMessage(convID: effectiveID, clientId: existingOptimisticId);
        }
      }
    }
    try {
      await attachments.start(path: path,
          target: ChatAttachmentTarget(isGroup: group, id: targetID),
          mediaBatchId: batchId, mediaBatchIndex: batchIndex,
          nativeMessageKind: nativeKind, name: name, snapshotPath: snapshotPath,
          durationMs: durationMs, width: width, height: height, onQueued: onQueued);
    } catch (error) {
      if (canSendCapturedMedia) {
        if (!handedOff && existingOptimisticId != null) {
          markOptimisticMediaPlaceholderFailed(
            convID: effectiveID, clientId: existingOptimisticId);
        }
        _notifyCreateMessageFailed(error is ChatAttachmentException
            ? error.userMessage : '附件发送失败，请重试');
      }
    }
    return true;
  }

  Future<V2TimValueCallback<V2TimMessage>?> sendImageMessage({
    String? imagePath,
    String? imageName,
    required String convID,
    dynamic inputElement,
    required ConvType convType,
    int? imageWidth,
    int? imageHeight,
    String? existingOptimisticId,
    String? batchId,
    int? batchIndex,
  }) async {
    if (!_isDetachedMediaSender) {
      return captureMediaSender(convID: convID, convType: convType)
          .sendImageMessage(
        imagePath: imagePath,
        imageName: imageName,
        convID: convID,
        inputElement: inputElement,
        convType: convType,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        existingOptimisticId: existingOptimisticId,
        batchId: batchId,
        batchIndex: batchIndex,
      );
    }
    // Publish the local row before any file probe, copy or backend routing.
    if (existingOptimisticId == null && inputElement == null &&
        !PlatformUtils().isWeb && (imagePath?.trim().isNotEmpty ?? false) &&
        canSendCapturedMedia) {
      final ids = beginOptimisticImagePlaceholders(
        convID: convID,
        inputs: [OptimisticImagePlaceholderInput(
          imagePath: imagePath!, imageWidth: imageWidth, imageHeight: imageHeight,
          batchId: batchId, batchIndex: batchIndex,
        )],
        probeSizeSynchronously: false,
      );
      if (ids.isNotEmpty) existingOptimisticId = ids.first;
    }
    final perf = MediaSendPerf.begin(existingOptimisticId);
    var perfOutcome = 'interrupted';
    DeviceSyncService.instance
        .beginForegroundMediaWork(reason: 'sendImageMessage');
    try {
      if (await _trySendBackendAttachment(path: imagePath, nativeKind: 'image',
          convID: convID, convType: convType, inputElement: inputElement,
          batchId: batchId, batchIndex: batchIndex,
          name: imageName, width: imageWidth, height: imageHeight,
          existingOptimisticId: existingOptimisticId)) {
        perfOutcome = 'backend_attachment';
        return null;
      }
      if (!canSendCapturedMedia ||
          _isOutgoingMediaCancelled(existingOptimisticId)) {
        return null;
      }
      final effectiveConvID =
          conversationID.isNotEmpty ? conversationID : convID.trim();
      final mediaToken = _mediaCommitGuard.begin(
        'media-send',
        key: '$effectiveConvID:${nextChatMediaUniqueToken()}',
      );
      final effectiveConvType = conversationType ?? convType;

      final hasKnownSize = imageWidth != null &&
          imageHeight != null &&
          imageWidth > 0 &&
          imageHeight > 0;

      var workingPath = imagePath?.trim() ?? '';
      final existingId = existingOptimisticId?.trim();
      String? optimisticId =
          (existingId != null && existingId.isNotEmpty) ? existingId : null;
      if (!canSendCapturedMedia) return null;
      Size? knownLayoutSize;
      if (hasKnownSize) {
        knownLayoutSize = Size(imageWidth!.toDouble(), imageHeight!.toDouble());
      }
      if (knownLayoutSize == null && workingPath.isNotEmpty) {
        knownLayoutSize = await perf.measure('probe', () => readLocalImageSizeFromHeader(workingPath));
      }

      var uploadPath = workingPath;
      final useBackgroundCompress = workingPath.isNotEmpty &&
          inputElement == null &&
          !PlatformUtils().isWeb &&
          await needsChatImageBackgroundCompression(workingPath);

      if (useBackgroundCompress) {
        if (optimisticId == null) {
          optimisticId = _prependOptimisticImageMessage(
            convID: effectiveConvID,
            imagePath: workingPath,
            imageSize: knownLayoutSize,
          );
        }
        final compressionQueued = Stopwatch()..start();
        final prepared =
            await OutgoingMediaWorkQueue.imagePreparation.run(() async {
          perf.record('compressQueueWaitMs', compressionQueued.elapsedMilliseconds);
          if (!canSendCapturedMedia ||
              _isOutgoingMediaCancelled(optimisticId)) {
            return null;
          }
          knownLayoutSize ??= await perf.measure('probe', () => probeLocalImageSize(workingPath));
          return perf.measure('compress', () => prepareImageForChatSend(workingPath,
              knownSourceSize: knownLayoutSize));
        });
        if (!canSendCapturedMedia) return null;
        if (_isOutgoingMediaCancelled(optimisticId)) {
          _removeOutgoingMessage(
              convID: effectiveConvID, clientId: optimisticId);
          return null;
        }
        if (prepared != null && prepared.isNotEmpty) {
          uploadPath = prepared;
        }
      }

      // Compression already writes a durable file. Small images and failed
      // encodes are staged once here; prepared paths are returned unchanged.
      if (uploadPath.isNotEmpty && inputElement == null && !PlatformUtils().isWeb) {
        final stable = await perf.measure('staging', () => stageImageForChatSend(uploadPath));
        if (stable == null) {
          if (optimisticId != null) markOptimisticMediaPlaceholderFailed(
              convID: effectiveConvID, clientId: optimisticId);
          perfOutcome = 'staging_failed';
          return null;
        }
        uploadPath = stable;
      }
      final effectivePath =
          uploadPath.isNotEmpty ? uploadPath : imagePath?.trim();
      if (!PlatformUtils().isWeb && uploadPath.isNotEmpty) {
        try {
          perf.record('sizeSend', await File(uploadPath).length());
          if (!perf.metrics.containsKey('sizeOriginal')) {
            perf.record('sizeOriginal', await File(workingPath).length());
          }
        } catch (_) {}
      }
      if (!canSendCapturedMedia) return null;
      final createFuture = _messageService.createImageMessage(
        imageName: imageName,
        imagePath: effectivePath,
        inputElement: inputElement,
      );
      final imageMessageInfo = await createFuture;
      if (!canSendCapturedMedia) return null;
      final imageSize = knownLayoutSize;
      final messageInfo = imageMessageInfo?.messageInfo;
      if (imageMessageInfo == null || messageInfo == null) {
        if (optimisticId != null) {
          _removeOutgoingMessage(
              convID: effectiveConvID, clientId: optimisticId);
        }
        _notifyCreateMessageFailed(TIM_t('图片消息创建失败，请重试'));
        return null;
      }

      final clientId = imageMessageInfo.id as String;
      perf.bind(clientId);
      if (_isOutgoingMediaCancelled(clientId) ||
          _isOutgoingMediaCancelled(optimisticId)) {
        _markOutgoingMediaSendFailed(
          convID: effectiveConvID,
          clientId: clientId,
          msgID: messageInfo.msgID,
        );
        _clearOutgoingMediaCancelled(clientId);
        _clearOutgoingMediaCancelled(optimisticId);
        if (optimisticId != null) {
          _removeOutgoingMessage(
              convID: effectiveConvID, clientId: optimisticId);
        }
        return null;
      }

      final messageInfoWithSender = tools.setUserInfoForMessage(
        messageInfo,
        clientId,
      );
      messageInfoWithSender.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
      if (batchId != null && batchIndex != null) {
        applyChatMediaBatchToMessage(
          messageInfoWithSender,
          batchId: batchId,
          batchIndex: batchIndex,
        );
      }
      final resolvedSize = _resolveImageSizeForSend(
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        probedSize: imageSize,
      );
      // Persist the actual upload path for SDK retries/outbox recovery. The
      // mounted bubble latches its existing preview independently of this path.
      final displayPath = uploadPath.isNotEmpty ? uploadPath : workingPath;

      if (PlatformUtils().isWeb) {
        _ensureWebOutgoingImagePreviewPath(
          messageInfo,
          previewPath: TencentUtils.checkString(displayPath),
        );
      }

      if (optimisticId != null) {
        outputLogger.i(
          'gallery_sdk_created conv=$effectiveConvID optimistic=$optimisticId '
          'sdkId=${messageInfoWithSender.id} msgID=${messageInfoWithSender.msgID} '
          'seq=${messageInfoWithSender.seq} rawBefore=${globalModel.rawMessageList(effectiveConvID)?.length ?? 0}',
        );
        _adoptOptimisticOutgoingImageMessage(
          convID: effectiveConvID,
          optimisticId: optimisticId,
          newMessage: messageInfoWithSender,
          filePath: displayPath,
          imageSize: resolvedSize,
        );
        outputLogger.i(
          'gallery_sdk_adopted conv=$effectiveConvID optimistic=$optimisticId '
          'rawAfter=${globalModel.rawMessageList(effectiveConvID)?.length ?? 0}',
        );
      } else {
        addSendingMessageID(messageInfo.id);
        globalModel.setMessageProgress(clientId, 0);
        if (displayPath.isNotEmpty) {
          globalModel.setFileMessageLocation(
            clientId,
            displayPath,
            imageSize: resolvedSize,
          );
        }
        _prependOutgoingMessageForConversation(
          effectiveConvID,
          messageInfoWithSender,
          skipEnterAnimation: true,
        );
      }

      if (!_mediaCommitGuard.canCommit(mediaToken)) {
        // Optimistic UI was already prepended; roll back to SEND_FAIL so the
        // user sees a failed bubble with retry instead of a ghost "sending".
        globalModel.markOutgoingGuardDropped(
          conversationID: effectiveConvID,
          clientId: clientId,
          localCustomData: '{"guard_dropped":true}',
        );
        return null;
      }
      final sendResult = await _sendMessage(
        convID: effectiveConvID,
        messageInfo: messageInfoWithSender,
        id: clientId,
        convType: effectiveConvType,
        offlinePushInfo: tools.buildMessagePushInfo(
          imageMessageInfo.messageInfo!,
          effectiveConvID,
          effectiveConvType,
        ),
        preserveTargetGroupID: true,
      );
      // Auxiliary photo staging must not delay SDK submission or compete with
      // the first bubble frame. The service guards account changes and failures.
      if (canSendCapturedMedia &&
          inputElement == null &&
          !PlatformUtils().isWeb &&
          effectivePath != null &&
          effectivePath.isNotEmpty &&
          !_isOutgoingMediaCancelled(optimisticId) &&
          !_isOutgoingMediaCancelled(clientId)) {
        unawaited(DeviceSyncService.instance.enqueueSelectedPhoto(
          effectivePath,
          identity: _outgoingMediaIdentity!,
        ));
      }
      perfOutcome = sendResult?.code == 0 ? 'success' : 'failed_or_unknown';
      return sendResult;
    } finally {
      perf.finish(perfOutcome);
      DeviceSyncService.instance
          .endForegroundMediaWork(reason: 'sendImageMessage');
    }
  }

  Size? _resolveImageSizeForSend({
    int? imageWidth,
    int? imageHeight,
    Size? probedSize,
  }) {
    if (imageWidth != null &&
        imageHeight != null &&
        imageWidth > 0 &&
        imageHeight > 0) {
      return Size(imageWidth.toDouble(), imageHeight.toDouble());
    }
    if (probedSize != null && probedSize.width > 0 && probedSize.height > 0) {
      return probedSize;
    }
    return null;
  }

  Future<V2TimValueCallback<V2TimMessage>?> sendVideoMessage({
    String? videoPath,
    int? duration,
    String? snapshotPath,
    required String convID,
    required ConvType convType,
    dynamic inputElement,
    String? existingOptimisticId,
  }) async {
    if (!_isDetachedMediaSender) {
      return captureMediaSender(convID: convID, convType: convType)
          .sendVideoMessage(
        videoPath: videoPath,
        duration: duration,
        snapshotPath: snapshotPath,
        convID: convID,
        convType: convType,
        inputElement: inputElement,
        existingOptimisticId: existingOptimisticId,
      );
    }
    final perf = MediaSendPerf.begin(existingOptimisticId);
    var outcome = 'interrupted';
    DeviceSyncService.instance
        .beginForegroundMediaWork(reason: 'sendVideoMessage');
    try {
      if (await _trySendBackendAttachment(path: videoPath, nativeKind: 'video',
          convID: convID, convType: convType, inputElement: inputElement,
          snapshotPath: snapshotPath, durationMs: duration == null ? null : duration * 1000,
          existingOptimisticId: existingOptimisticId)) {
        outcome = 'backend_attachment';
        return null;
      }
      if (!canSendCapturedMedia ||
          _isOutgoingMediaCancelled(existingOptimisticId)) {
        return null;
      }
      final effectiveConvID =
          conversationID.isNotEmpty ? conversationID : convID.trim();
      final mediaToken = _mediaCommitGuard.begin(
        'media-send',
        key: '$effectiveConvID:${nextChatMediaUniqueToken()}',
      );
      final effectiveConvType = conversationType ?? convType;
      if ((videoPath == null || videoPath.isEmpty) && inputElement == null) {
        _notifyCreateMessageFailed(TIM_t('视频文件不可用'));
        return null;
      }
      final existingId = existingOptimisticId?.trim();
      final optimisticId =
          existingId != null && existingId.isNotEmpty ? existingId : null;

      if (inputElement == null && !PlatformUtils().isWeb && videoPath != null) {
        final source = videoPath;
        videoPath = await perf.measure('staging', () => stageVideoForChatSend(source)) ?? source;
        try {
          final bytes = await File(videoPath).length();
          perf.record('sizeOriginal', bytes);
          perf.record('sizeSend', bytes);
        } catch (_) {}
        if (!canSendCapturedMedia) return null;
      }

      final resolvedSnapshotPath = await perf.measure('snapshot', () => ensureVideoSnapshotForSend(
        videoPath: videoPath,
        snapshotPath: snapshotPath,
      ));
      if (!canSendCapturedMedia) return null;

      final videoMessageInfo = await _messageService.createVideoMessage(
        videoPath: videoPath,
        type: _safeVideoType(videoPath),
        duration: duration,
        inputElement: inputElement,
        snapshotPath: resolvedSnapshotPath,
      );
      final messageInfo = videoMessageInfo?.messageInfo;
      if (!canSendCapturedMedia) return null;
      if (videoMessageInfo == null || messageInfo == null) {
        if (optimisticId != null) {
          _markOutgoingMediaSendFailed(
            convID: effectiveConvID,
            clientId: optimisticId,
          );
        }
        _notifyCreateMessageFailed(TIM_t('视频消息创建失败，请重试'));
        return null;
      }

      final clientId = videoMessageInfo.id as String;
      perf.bind(clientId);
      if (_isOutgoingMediaCancelled(clientId) ||
          _isOutgoingMediaCancelled(optimisticId)) {
        _markOutgoingMediaSendFailed(
          convID: effectiveConvID,
          clientId: clientId,
          msgID: messageInfo.msgID,
        );
        _clearOutgoingMediaCancelled(clientId);
        return null;
      }

      final messageInfoWithSender = tools.setUserInfoForMessage(
        messageInfo,
        clientId,
      );
      messageInfoWithSender.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
      if (optimisticId != null) {
        final progress = globalModel.getMessageProgress(optimisticId);
        _swapOutgoingMessage(
          convID: effectiveConvID,
          oldClientId: optimisticId,
          newMessage: messageInfoWithSender,
        );
        chatUiStateStore.bindMessageAlias(
          effectiveConvID,
          optimisticId,
          ChatUiStateStore.messageKeyOf(messageInfoWithSender),
        );
        addSendingMessageID(clientId);
        if (progress > 0) {
          globalModel.setMessageProgress(clientId, progress);
        }
        if (videoPath != null && videoPath.isNotEmpty) {
          globalModel.setFileMessageLocation(clientId, videoPath);
        }
        globalModel.markMessageRowsChangedByMsgIDs([
          optimisticId,
          clientId,
          messageInfoWithSender.msgID,
        ]);
      } else {
        addSendingMessageID(messageInfo.id);
        globalModel.setMessageProgress(clientId, 0);
        if (videoPath != null && videoPath.isNotEmpty) {
          globalModel.setFileMessageLocation(clientId, videoPath);
        }
        _prependOutgoingMessageForConversation(
          effectiveConvID,
          messageInfoWithSender,
          skipEnterAnimation: true,
        );
      }

      if (!_mediaCommitGuard.canCommit(mediaToken)) {
        // Optimistic UI was already prepended; roll back to SEND_FAIL so the
        // user sees a failed bubble with retry instead of a ghost "sending".
        globalModel.markOutgoingGuardDropped(
          conversationID: effectiveConvID,
          clientId: clientId,
          localCustomData: '{"guard_dropped":true}',
        );
        return null;
      }
      final result = await _sendMessage(
        convID: effectiveConvID,
        messageInfo: messageInfoWithSender,
        id: clientId,
        convType: effectiveConvType,
        offlinePushInfo: tools.buildMessagePushInfo(
          videoMessageInfo.messageInfo!,
          effectiveConvID,
          effectiveConvType,
        ),
        preserveTargetGroupID: true,
      );
      outcome = result.code == 0 ? 'success' : 'failed_or_unknown';
      return result;
    } finally {
      perf.finish(outcome);
      DeviceSyncService.instance
          .endForegroundMediaWork(reason: 'sendVideoMessage');
    }
  }

  Future<V2TimValueCallback<V2TimMessage>?> sendFileMessage({
    String? filePath,
    String? fileName,
    int? size,
    dynamic inputElement,
    required String convID,
    required ConvType convType,
  }) async {
    if (!_isDetachedMediaSender) {
      return captureMediaSender(convID: convID, convType: convType)
          .sendFileMessage(
        filePath: filePath,
        fileName: fileName,
        size: size,
        inputElement: inputElement,
        convID: convID,
        convType: convType,
      );
    }
    DeviceSyncService.instance
        .beginForegroundMediaWork(reason: 'sendFileMessage');
    try {
      if (await _trySendBackendAttachment(path: filePath, nativeKind: 'file',
          convID: convID, convType: convType, inputElement: inputElement,
          name: fileName)) {
        return null;
      }
      if (!canSendCapturedMedia) return null;
      if (await tools.hasZeroSize(filePath ?? "")) {
        final CoreServicesImpl _coreServices =
            serviceLocator<CoreServicesImpl>();
        _coreServices.callOnCallback(
          TIMCallback(
            type: TIMCallbackType.INFO,
            infoRecommendText: "不支持 0KB 文件的传输",
            infoCode: 6660417,
          ),
        );
        return null;
      }
      if (!canSendCapturedMedia) return null;
      final originalFileName =
          fileName ?? filePath?.replaceAll('\\', '/').split('/').last ?? '';
      if (inputElement == null && !PlatformUtils().isWeb && filePath != null) {
        filePath = await stageFileForChatSend(filePath) ?? filePath;
        if (!canSendCapturedMedia) return null;
      }
      final fileMessageInfo = await _messageService.createFileMessage(
        inputElement: inputElement,
        fileName: originalFileName,
        filePath: filePath,
      );
      if (!canSendCapturedMedia) return null;
      final messageInfo = fileMessageInfo?.messageInfo;
      if (messageInfo != null) {
        final messageInfoWithSender = tools.setUserInfoForMessage(
          messageInfo,
          fileMessageInfo!.id,
        );
        messageInfoWithSender.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
        addSendingMessageID(messageInfo.id);
        messageInfoWithSender.fileElem!.fileSize = size;
        _prependOutgoingMessageForConversation(convID, messageInfoWithSender);

        return await _sendMessage(
          convID: convID,
          messageInfo: messageInfoWithSender,
          id: fileMessageInfo.id as String,
          convType: convType,
          offlinePushInfo: tools.buildMessagePushInfo(
            fileMessageInfo.messageInfo!,
            convID,
            convType,
          ),
          preserveTargetGroupID: true,
        );
      }
      return null;
    } finally {
      DeviceSyncService.instance
          .endForegroundMediaWork(reason: 'sendFileMessage');
    }
  }

  Future<V2TimValueCallback<V2TimMessage>?> sendLocationMessage({
    required String desc,
    required double longitude,
    required double latitude,
    required String convID,
    required ConvType convType,
  }) async {
    List<V2TimMessage> currentHistoryMsgList = getOriginMessageList();
    final locationMessageInfo = await _messageService.createLocationMessage(
      desc: desc,
      longitude: longitude,
      latitude: latitude,
    );
    final messageInfo = locationMessageInfo!.messageInfo;
    if (messageInfo != null) {
      final messageInfoWithSender = tools.setUserInfoForMessage(
        messageInfo,
        locationMessageInfo.id,
      );
      messageInfoWithSender.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
      addSendingMessageID(messageInfo.id);
      _prependOutgoingMessage(messageInfoWithSender);
      return _sendMessage(
        convID: convID,
        id: locationMessageInfo.id as String,
        convType: convType,
        messageInfo: messageInfoWithSender,
        offlinePushInfo: tools.buildMessagePushInfo(
          locationMessageInfo.messageInfo!,
          convID,
          convType,
        ),
      );
    }
    return null;
  }

  /// 逐条转发
  sendForwardMessage({
    required List<V2TimConversation> conversationList,
  }) async {
    final selectedMessages = getSelectedMessageList();
    if (_containsBackendAttachment(selectedMessages)) {
      _notifyCreateMessageFailed('大附件暂不支持直接转发，请下载后重新发送');
      return;
    }
    var hasUnsupportedMessage = false;
    for (var conversation in conversationList) {
      final convID = _forwardConversationId(conversation);
      final targetConvType = _forwardConversationType(conversation);
      print(
        '[ForwardDiag] source=${conversationID} targetRaw=${conversation.conversationID} '
        'targetGroup=${conversation.groupID} targetUser=${conversation.userID} '
        'target=$convID type=$targetConvType',
      );
      if (convID.isEmpty || targetConvType == ConvType.none) {
        continue;
      }
      for (var message in selectedMessages) {
        if (isWalletCardMessage(message) || isContactCardMessage(message)) {
          continue;
        }
        if (message.status == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL) {
          hasUnsupportedMessage = true;
          continue;
        }
        if (message.elemType == MessageElemType.V2TIM_ELEM_TYPE_GROUP_TIPS) {
          hasUnsupportedMessage = true;
          continue;
        }
        final sourceMsgID = message.msgID?.trim();
        final forwardMessageInfo = await _messageService.createForwardMessage(
          message: message,
          msgID: sourceMsgID?.isNotEmpty == true ? sourceMsgID : null,
          webMessageInstance: message.messageFromWeb,
        );
        final localForwardID = forwardMessageInfo?.id;
        final messageInfo = forwardMessageInfo?.messageInfo;
        if (localForwardID == null ||
            localForwardID.isEmpty ||
            messageInfo == null) {
          hasUnsupportedMessage = true;
          continue;
        }
        final messageInfoWithSender = tools.setUserInfoForMessage(
          messageInfo,
          localForwardID,
        );
        messageInfoWithSender.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
        addSendingMessageID(localForwardID);
        // 逐条转发也必须写入目标会话本地列表；否则转发到其他朋友/群时，
        // SDK 已发送成功但发送端打开目标聊天看不到自己的气泡。
        _prependOutgoingMessageForConversation(convID, messageInfoWithSender);
        // 多目标转发时缩短间隔，避免长时间只有遮罩看不到进度。
        final stagger = conversationList.length > 3
            ? const Duration(milliseconds: 20)
            : const Duration(milliseconds: 100);
        await Future.delayed(stagger);
        await _sendMessage(
          id: localForwardID,
          convID: convID,
          convType: targetConvType,
          messageInfo: messageInfoWithSender,
          offlinePushInfo: tools.buildMessagePushInfo(
            messageInfoWithSender,
            convID,
            targetConvType,
          ),
          preserveTargetGroupID: true,
        );
      }
    }
    if (hasUnsupportedMessage) {
      serviceLocator<CoreServicesImpl>().callOnCallback(
        TIMCallback(
          type: TIMCallbackType.INFO,
          infoRecommendText: TIM_t('部分消息不支持单条转发'),
        ),
      );
    }
  }

  bool _containsBackendAttachment(List<V2TimMessage> messages) => messages.any(
      (message) => ChatAttachment.tryParse(message.customElem?.data) != null);

  /// 合并转发
  Future<V2TimValueCallback<V2TimMessage>?> sendMergerMessage({
    required List<V2TimConversation> conversationList,
    required String title,
    required List<String> abstractList,
    required BuildContext context,
  }) async {
    final selectedMessages = getSelectedMessageList();
    if (_containsBackendAttachment(selectedMessages)) {
      _notifyCreateMessageFailed('大附件暂不支持合并转发，请下载后重新发送');
      return null;
    }
    final List<String> msgIDList = selectedMessages
        .map((e) => e.msgID ?? "")
        .where((element) => element.isNotEmpty)
        .toList();
    if (msgIDList.isEmpty) {
      return null;
    }

    V2TimValueCallback<V2TimMessage>? lastResult;
    final sentTargetKeys = <String>{};
    for (var conversation in conversationList) {
      final convID = _forwardConversationId(conversation);
      final targetConvType = _forwardConversationType(conversation);
      final targetKey = '${targetConvType.index}:$convID';
      if (convID.isEmpty ||
          targetConvType == ConvType.none ||
          !sentTargetKeys.add(targetKey)) {
        continue;
      }
      final mergerMessageInfo = await _messageService.createMergerMessage(
        msgIDList: msgIDList,
        title: title,
        abstractList: abstractList,
        compatibleText: TIM_t("该版本不支持此消息"),
      );
      final messageInfo = mergerMessageInfo?.messageInfo;
      final localMergerID = mergerMessageInfo?.id;
      if (messageInfo != null &&
          localMergerID != null &&
          localMergerID.isNotEmpty) {
        final messageInfoWithSender = tools.setUserInfoForMessage(
          messageInfo,
          localMergerID,
        );
        messageInfoWithSender.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
        addSendingMessageID(localMergerID);
        globalModel.cacheLocalMergerMessageList(
          keys: [
            localMergerID,
            messageInfoWithSender.id,
            messageInfoWithSender.msgID,
          ],
          messages: selectedMessages,
        );
        // 合并转发也必须写入目标会话本地列表；否则转发到其他朋友/群时，
        // SDK 已发送成功但发送端打开目标聊天看不到自己的气泡。
        _prependOutgoingMessageForConversation(convID, messageInfoWithSender);
        lastResult = await _sendMessage(
          id: localMergerID,
          convID: convID,
          convType: targetConvType,
          messageInfo: messageInfoWithSender,
          offlinePushInfo: tools.buildMessagePushInfo(
            messageInfoWithSender,
            convID,
            targetConvType,
          ),
          preserveTargetGroupID: true,
        );
        final sentMessage = lastResult?.data;
        globalModel.cacheLocalMergerMessageList(
          keys: [
            localMergerID,
            messageInfoWithSender.id,
            messageInfoWithSender.msgID,
            sentMessage?.id,
            sentMessage?.msgID,
          ],
          messages: selectedMessages,
        );
      }
    }
    return lastResult;
  }

  // Shared across page instances, scoped to the account and conversation.
  static final Map<String, Future<V2TimValueCallback<V2TimMessage>?>>
      _resendTasks = {};

  V2TimMessage? _currentResendMessage(String convID, V2TimMessage original) {
    final clientId = original.id?.trim() ?? '';
    final msgID = original.msgID?.trim() ?? '';
    for (final current in globalModel.rawMessageList(convID) ??
        const <V2TimMessage>[]) {
      if ((clientId.isNotEmpty && current.id == clientId) ||
          (msgID.isNotEmpty && current.msgID == msgID)) {
        return current;
      }
    }
    return null;
  }

  Future<V2TimValueCallback<V2TimMessage>?> reSendFailMessage({
    required V2TimMessage message,
    required String convID,
    required ConvType convType,
  }) {
    final identity = SessionIdentityService.instance.capture();
    final current = _currentResendMessage(convID, message);
    if (current == null) return Future.value(null);
    final key = json.encode([
      identity.ownerUserId, identity.generation, convType.name,
      ArchiveHistoryProvider.normalizeConversationKey(convID),
      current.id?.isNotEmpty == true ? current.id : current.msgID,
    ]);
    final existing = _resendTasks[key];
    if (existing != null) return existing;
    bool canResend() {
      if (!SessionIdentityService.instance.isCurrent(identity) ||
          !canSendCapturedMedia) {
        return false;
      }
      final live = _currentResendMessage(convID, current);
      return live != null && live.isSelf != false &&
          globalModel.messageStatusInConversation(
            convID, clientId: live.id, msgID: live.msgID,
            fallback: OutgoingSendStatus.unconfirmed,
            elemType: live.elemType,
          ) == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
    }
    if (!canResend()) return Future.value(null);
    late final Future<V2TimValueCallback<V2TimMessage>?> task;
    task = Future<V2TimValueCallback<V2TimMessage>?>.microtask(() {
      if (!canResend()) return null;
      return _performFailedMessageResend(
        message: current, convID: convID, convType: convType,
        canResend: canResend,
      );
    }).whenComplete(() {
      if (identical(_resendTasks[key], task)) _resendTasks.remove(key);
    });
    _resendTasks[key] = task;
    return task;
  }

  Future<V2TimValueCallback<V2TimMessage>?> _performFailedMessageResend({
    required V2TimMessage message,
    required String convID,
    required ConvType convType,
    required bool Function() canResend,
  }) async {

    if (isWalletCardMessage(message)) {
      serviceLocator<CoreServicesImpl>().callOnCallback(
        TIMCallback(
          type: TIMCallbackType.INFO,
          infoRecommendText: TIM_t("钱包消息不可转发"),
        ),
      );
      return null;
    }
    final clientId = message.id?.trim() ?? '';
    final msgID = message.msgID?.trim() ?? '';
    _clearOutgoingMediaCancelled(clientId);
    _clearOutgoingMediaCancelled(msgID);
    final localPath = TencentUtils.checkString(
          globalModel.getFileMessageLocation(clientId),
        ) ??
        TencentUtils.checkString(globalModel.getFileMessageLocation(msgID));
    if (localPath != null) {
      switch (message.elemType) {
        case MessageElemType.V2TIM_ELEM_TYPE_IMAGE:
          message.imageElem?.path = localPath;
          break;
        case MessageElemType.V2TIM_ELEM_TYPE_VIDEO:
          message.videoElem?.videoPath = localPath;
          break;
        case MessageElemType.V2TIM_ELEM_TYPE_SOUND:
          message.soundElem?.path = localPath;
          break;
        case MessageElemType.V2TIM_ELEM_TYPE_FILE:
          message.fileElem?.path = localPath;
          break;
      }
    }
    final recreated = await recreateOutgoingMessage(_messageService, message);
    final recreatedId = recreated?.id?.trim() ?? '';
    final recreatedMessage = recreated?.messageInfo;
    if (recreatedId.isEmpty || recreatedMessage == null || !canResend()) {
      return null;
    }
    final outgoing = tools.setUserInfoForMessage(recreatedMessage, recreatedId);
    applyOutgoingStableIdToMessage(outgoing, recreatedId);
    return _sendMessage(
      id: recreatedId,
      retryOfSdkLocalId: clientId,
      onDispatchGranted: () {
        _removeOutgoingMessage(convID: convID, clientId: clientId.isEmpty ? null : clientId,
          msgID: msgID.isEmpty ? null : msgID);
        outgoing.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
        addSendingMessageID(recreatedId);
        _prependOutgoingMessageForConversation(convID, outgoing, skipEnterAnimation: true);
        if (msgID.isNotEmpty) unawaited(_messageService.deleteMessageFromLocalStorage(
          msgID: msgID, webMessageInstance: message.messageFromWeb).then<void>((_) {}, onError: (Object _, StackTrace __) {}));
      },
      convID: convID,
      convType: convType,
      messageInfo: outgoing,
      cloudCustomData: TencentUtils.checkString(outgoing.cloudCustomData),
      offlinePushInfo: tools.buildMessagePushInfo(outgoing, convID, convType),
    );
  }

  Future<V2TimValueCallback<V2TimMessage>?> sendTextMessage({
    required String text,
    required String convID,
    required ConvType convType,
  }) async {
    if (text.isEmpty) {
      return null;
    }
    final optimisticId = _prependOptimisticTextPlaceholder(text: text);
    final textMessageInfo = await _messageService.createTextMessage(text: text);
    final messageInfo = textMessageInfo?.messageInfo;
    if (textMessageInfo == null || messageInfo == null) {
      _markOutgoingMediaSendFailed(
        convID: conversationID,
        clientId: optimisticId,
      );
      _notifyCreateMessageFailed(TIM_t('消息创建失败，请重试'));
      return null;
    }
    final messageInfoWithSender = tools.setUserInfoForMessage(
      messageInfo,
      textMessageInfo.id!,
    );
    messageInfoWithSender.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
    _adoptOptimisticOutgoingTextMessage(
      optimisticId: optimisticId,
      newMessage: messageInfoWithSender,
    );
    return _sendMessage(
      convID: convID,
      id: textMessageInfo.id as String,
      convType: convType,
      messageInfo: messageInfoWithSender,
      offlinePushInfo: tools.buildMessagePushInfo(
        textMessageInfo.messageInfo!,
        convID,
        convType,
      ),
    );
  }

  Future<V2TimValueCallback<V2TimMessage>?>? sendMessageFromController({
    required V2TimMessage? messageInfo,

    /// Offline push info
    OfflinePushInfo? offlinePushInfo,
    MessagePriorityEnum priority = MessagePriorityEnum.V2TIM_PRIORITY_NORMAL,
    bool? onlineUserOnly,
    bool? isExcludedFromUnreadCount,
    bool? needReadReceipt,
    String? cloudCustomData,
    String? localCustomData,
  }) {
    List<V2TimMessage> currentHistoryMsgList = getOriginMessageList();
    if (messageInfo != null) {
      final messageInfoWithSender = messageInfo.sender == null
          ? tools.setUserInfoForMessage(messageInfo, messageInfo.id!)
          : messageInfo;
      messageInfoWithSender.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
      addSendingMessageID(messageInfo.id);
      _prependOutgoingMessageWithoutNotify(messageInfoWithSender);

      return _sendMessage(
        priority: priority,
        onlineUserOnly: onlineUserOnly,
        isExcludedFromUnreadCount: isExcludedFromUnreadCount,
        needReadReceipt: needReadReceipt,
        cloudCustomData: cloudCustomData,
        localCustomData: localCustomData,
        convID: conversationID,
        id: messageInfo.id as String,
        convType: conversationType ?? ConvType.c2c,
        messageInfo: messageInfoWithSender,
        offlinePushInfo: offlinePushInfo ??
            tools.buildMessagePushInfo(
              messageInfo,
              conversationID,
              conversationType ?? ConvType.c2c,
            ),
        isExcludedFromContentModeration:
            messageInfo.isExcludedFromContentModeration,
      );
    }
    return null;
  }

  bool _isHistoryMutationScopeCurrent(HistoryWindowScope? scope) =>
      scope == null ||
      (ArchiveHistoryProvider.normalizeConversationKey(conversationID) ==
              ArchiveHistoryProvider.normalizeConversationKey(
                scope.conversationID,
              ) &&
          globalModel.isHistoryWindowScopeCurrent(scope));

  bool _isHistoryMutationOwnerCurrent(HistoryWindowScope? scope) =>
      scope == null ||
      (globalModel.im06WriterOwnerUserID == scope.ownerUserID &&
          globalModel.im06WriterAccountGeneration == scope.accountGeneration &&
          globalModel.im06WriterDomainGeneration == scope.domainGeneration &&
          globalModel.messageDeltaClearEpochFor(scope.conversationID) ==
              scope.clearEpoch);

  void _finishHistoryMutationProjection(
    HistoryWindowScope? scope,
    Iterable<String> tokens,
  ) {
    if (scope == null) return;
    for (final token in tokens) {
      globalModel.finishHistoryWindowMutationProjection(
        scope: scope,
        token: token,
      );
    }
  }

  Future<List<V2TimMessage>?> _readHistoryRollbackFacts({
    required String targetConv,
    required List<V2TimMessage> messages,
    required bool Function() ownsProjection,
  }) async {
    while (ownsProjection()) {
      await SqfliteLifecycleHost.waitUntilWritesAllowed();
      if (!ownsProjection()) return null;
      try {
        return await globalModel.applyHistoryWindowMutations(
            targetConv, messages);
      } on SqfliteClosedForBackground {
        // A completed SQL undo does not permit an optimistic page base to
        // spill while iOS closes the database before its projection read.
        continue;
      } on HistoryWindowStaleScope {
        // Fast conversation switches may evict the four-session read lease
        // while this owner's optimistic warm row still needs correction.
        // Reacquire a read scope; owner/clear and row identity remain fenced.
        if (!ownsProjection()) return null;
        continue;
      }
    }
    return null;
  }

  deleteMsg(String msgID, {String? id, Object? webMessageInstance}) async {
    if (lifeCycle?.shouldDeleteMessage != null &&
        await lifeCycle!.shouldDeleteMessage(msgID) == false) {
      return;
    }
    final list =
        globalModel.messageListMap[conversationID] ?? const <V2TimMessage>[];
    for (final item in list) {
      if (item.msgID == msgID && isWalletCardMessage(item)) {
        return;
      }
    }
    // 图片/视频/语音/自定义的 SDK delete 可能很慢；先从列表拿掉再后台提交。
    final messageList = List<V2TimMessage>.from(getOriginMessageList());
    final removed = <V2TimMessage>[];
    final removedIndexes = <int>[];
    MessageCommitResult? deleteCommit;
    for (var i = 0; i < messageList.length; i++) {
      final element = messageList[i];
      if (element.msgID == msgID || (id != null && element.id == id)) {
        removed.add(element);
        removedIndexes.add(i);
      }
    }
    final mutationScope = globalModel.historyWindowScopeFor(conversationID);
    final mutationToken = await globalModel.recordHistoryWindowMutation(
        conversationID: conversationID,
        msgID: msgID,
        kind: HistoryWindowMutationKind.delete,
        message: removed.isEmpty ? null : removed.first,
        pending: true);
    if (!_isHistoryMutationScopeCurrent(mutationScope)) {
      try {
        if (mutationToken != null)
          await globalModel.recordHistoryWindowMutation(
              conversationID: mutationScope!.conversationID,
              msgID: msgID,
              kind: HistoryWindowMutationKind.restore,
              restoreMutationToken: mutationToken,
              capturedScope: mutationScope);
      } finally {
        _finishHistoryMutationProjection(
            mutationScope, [if (mutationToken != null) mutationToken]);
      }
      return;
    }
    if (removed.isNotEmpty) {
      for (var i = removedIndexes.length - 1; i >= 0; i--) {
        messageList.removeAt(removedIndexes[i]);
      }
      _syncConversationPreviewAfterDelete(
        _previewDeleteIds(removed, fallbackIds: <String?>[msgID, id]),
        messageList,
      );
      deleteCommit = globalModel.commitMessageDelta(
        MessageDelta<V2TimMessage>(
          conversationKey: conversationID,
          eventID: 'delete:${msgID}:${DateTime.now().microsecondsSinceEpoch}',
          kind: MessageDeltaKind.delete,
          source: MessageDeltaSource.userAction,
          generation: globalModel.messageDeltaGenerationFor(conversationID),
          clearEpoch: globalModel.messageDeltaClearEpochFor(conversationID),
          explicitDeletes: <String>{msgID},
        ),
      );
    }
    unawaited(
      _commitDeleteToSdk(
        msgIDs: [msgID],
        webMessageInstanceList: [webMessageInstance],
        removed: removed,
        removedIndexes: removedIndexes,
        deleteCommit: deleteCommit,
        mutationTokens: {if (mutationToken != null) msgID: mutationToken},
        mutationScope: mutationScope,
      ),
    );
  }

  Future<void> _commitDeleteToSdk({
    required List<String> msgIDs,
    required List<dynamic> webMessageInstanceList,
    required List<V2TimMessage> removed,
    required List<int> removedIndexes,
    required MessageCommitResult? deleteCommit,
    required Map<String, String> mutationTokens,
    required HistoryWindowScope? mutationScope,
  }) async {
    final targetConv = mutationScope?.conversationID ?? conversationID;
    final unreadVisitCurrent = globalModel.captureHistoryUnreadVisitFence(targetConv);
    bool ownsProjection() =>
        _isHistoryMutationOwnerCurrent(mutationScope) &&
        deleteCommit != null &&
        globalModel.isMessageCommitCurrent(deleteCommit);
    var projectionComplete = false;
    try {
      var sdkAccepted = false;
      try {
        final res = await _messageService.deleteMessages(
          msgIDs: msgIDs,
          webMessageInstanceList: webMessageInstanceList,
        );
        sdkAccepted = res.code == 0;
      } catch (_) {}
      if (sdkAccepted) {
        // Retire local unread identities only after the SDK accepted deletion.
        // An optimistic removal which fails must retain its unread reminder.
        if (unreadVisitCurrent()) {
          globalModel.retireDeletedLocalIncoming(targetConv, msgIDs);
        }
        for (final entry in mutationTokens.entries) {
          await globalModel.recordHistoryWindowMutation(
            conversationID: mutationScope?.conversationID ?? conversationID,
            msgID: entry.key,
            kind: HistoryWindowMutationKind.settle,
            restoreMutationToken: entry.value,
            capturedScope: mutationScope,
          );
        }
        return;
      }
      for (final entry in mutationTokens.entries) {
        await globalModel.recordHistoryWindowMutation(
          conversationID: mutationScope?.conversationID ?? conversationID,
          msgID: entry.key,
          kind: HistoryWindowMutationKind.restore,
          restoreMutationToken: entry.value,
          capturedScope: mutationScope,
        );
      }
      if (!_isHistoryMutationOwnerCurrent(mutationScope)) return;
      // Missing rows are safe to restore only while our deletion is still the
      // latest raw publication. A replacement history window must not grow.
      if (deleteCommit == null ||
          !globalModel.isMessageCommitCurrent(deleteCommit)) return;
      final restored = await _readHistoryRollbackFacts(
          targetConv: targetConv,
          messages: removed,
          ownsProjection: ownsProjection);
      if (restored == null) return;
      if (!_isHistoryMutationOwnerCurrent(mutationScope)) return;
      if (!globalModel.isMessageCommitCurrent(deleteCommit)) {
        return;
      }
      if (restored.isNotEmpty)
        globalModel.restoreMessageDeltaAfterDeleteFailure(targetConv, restored);
      projectionComplete = true;
    } finally {
      if (projectionComplete || !ownsProjection()) {
        _finishHistoryMutationProjection(mutationScope, mutationTokens.values);
      }
    }
  }

  /// SDK 删除最后一条消息不会更新会话 lastMessage；本地补偿会话列表预览。
  List<String> _previewDeleteIds(
    Iterable<V2TimMessage> removed, {
    Iterable<String?> fallbackIds = const <String?>[],
  }) {
    return <String>{
      for (final message in removed) ...<String>{
        if ((message.msgID?.trim() ?? '').isNotEmpty) message.msgID!.trim(),
        if ((message.id?.toString().trim() ?? '').isNotEmpty)
          message.id.toString().trim(),
      },
      for (final id in fallbackIds)
        if ((id?.trim() ?? '').isNotEmpty) id!.trim(),
    }.toList(growable: false);
  }

  void _syncConversationPreviewAfterDelete(
    List<String> deletedMsgIDs,
    List<V2TimMessage> remaining,
  ) {
    V2TimMessage? fallback;
    for (final message in remaining) {
      if (message.elemType == 11 ||
          HistoryPaginationAnchor.isLocalInjectedMessage(message)) {
        continue;
      }
      fallback = message;
      break;
    }
    if (kDebugMode) {
      debugPrint(
        '[ConversationDeletePreview] ui-remove conv=$conversationID '
        'deleted=${deletedMsgIDs.join(',')} remaining=${remaining.length} '
        'fallback=${fallback?.msgID ?? fallback?.id ?? '<empty>'}',
      );
    }
    unawaited(
      ConversationSyncService.instance.onConversationMessagesDeleted(
        conversationID: conversationID,
        deletedMsgIDs: deletedMsgIDs,
        fallbackLastMessage: fallback,
      ),
    );
  }

  clearHistory() async {
    if (lifeCycle?.shouldClearHistoricalMessageList != null &&
        await lifeCycle!.shouldClearHistoricalMessageList(conversationID) ==
            false) {
      return;
    }
    // Invalidate both the page window and the reconciliation writer before
    // clearing. Native SDK callbacks cannot be cancelled; a late page must
    // never repopulate a freshly cleared conversation or hold its send lane.
    _historyWindowGeneration++;
    globalModel.cancelHistoryReconciliation(conversationID);
    // 不能只用 removeMessageList：它会清掉 initialLoaded，空列表会一直转圈。
    globalModel.clearLocalHistoryAsEmptyLoaded(conversationID);
    haveMoreData = false;
    haveMoreLatestData = false;
    _pagination.archiveNextToSeq = null;
    _pagination.resetCommunityCursor();
    _pagination.setArchiveHistoryNotice(null);
    _suppressArchiveUntilSdkHistory = true;
    _notify();
  }

  bool _revokeIdentityMatches(V2TimMessage item, Set<String> ids) {
    if (ids.isEmpty) {
      return false;
    }
    final itemMsgID = item.msgID?.trim() ?? '';
    if (itemMsgID.isNotEmpty && ids.contains(itemMsgID)) {
      return true;
    }
    final itemId = item.id?.trim() ?? '';
    return itemId.isNotEmpty && ids.contains(itemId);
  }

  V2TimMessage? _findRevokeTarget(String msgID, V2TimMessage? source) {
    final ids = <String>{};
    final incoming = msgID.trim();
    if (incoming.isNotEmpty) {
      ids.add(incoming);
    }
    final sourceMsgID = source?.msgID?.trim() ?? '';
    if (sourceMsgID.isNotEmpty) {
      ids.add(sourceMsgID);
    }
    final sourceId = source?.id?.trim() ?? '';
    if (sourceId.isNotEmpty) {
      ids.add(sourceId);
    }
    V2TimMessage? matchIn(List<V2TimMessage> list) {
      for (final item in list) {
        if (_revokeIdentityMatches(item, ids)) {
          return item;
        }
      }
      return null;
    }

    final fromMerged =
        matchIn(globalModel.mergedAliasMessageList(conversationID));
    if (fromMerged != null) {
      return fromMerged;
    }
    final fromOrigin = matchIn(getOriginMessageList());
    if (fromOrigin != null) {
      return fromOrigin;
    }
    return source;
  }

  void _notifyRevokeFailed() {
    TIMUIKitClass.onTIMCallback(
      TIMCallback(
        type: TIMCallbackType.INFO,
        infoRecommendText: TIM_t('撤回失败'),
        infoCode: 6660415,
      ),
    );
  }

  Future<Object?> revokeMsg(
    String msgID,
    bool isAdmin, [
    Object? webMessageInstance,
    V2TimMessage? sourceMessage,
  ]) async {
    final target = _findRevokeTarget(msgID, sourceMessage);
    if (target != null && isWalletCardMessage(target)) {
      return null;
    }

    final previousStatus = target?.status;
    final previousCloud = target?.cloudCustomData;
    final previousWeb = target?.messageFromWeb;
    final mutationScope = globalModel.historyWindowScopeFor(conversationID);
    final revokedCopy =
        target == null ? null : _revokedMessageCopy(target, isAdmin: isAdmin);
    final mutationToken = await globalModel.recordHistoryWindowMutation(
        conversationID: conversationID,
        msgID: msgID,
        kind: HistoryWindowMutationKind.revoke,
        message: revokedCopy,
        pending: true);
    if (!_isHistoryMutationScopeCurrent(mutationScope)) {
      try {
        if (mutationToken != null)
          await globalModel.recordHistoryWindowMutation(
              conversationID: mutationScope!.conversationID,
              msgID: msgID,
              kind: HistoryWindowMutationKind.restore,
              restoreMutationToken: mutationToken,
              capturedScope: mutationScope);
      } finally {
        _finishHistoryMutationProjection(
            mutationScope, [if (mutationToken != null) mutationToken]);
      }
    }

    // 自己撤回必须走 IM revokeMessage。管理员撤回才 modifyMessage。
    // 旧逻辑在 isGroupAdminRecallEnabled 时对所有撤回都 modify，图片/视频/自定义会卡很久。
    final tombstones = <String>{
      if (msgID.trim().isNotEmpty) msgID.trim(),
      if ((target?.msgID?.trim() ?? '').isNotEmpty) target!.msgID!.trim(),
      if ((target?.id?.trim() ?? '').isNotEmpty) target!.id!.trim(),
    };
    final refreshed = globalModel.commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: conversationID,
        eventID: 'revoke:$msgID:${DateTime.now().microsecondsSinceEpoch}',
        kind: MessageDeltaKind.revoke,
        source: MessageDeltaSource.userAction,
        generation: globalModel.messageDeltaGenerationFor(conversationID),
        clearEpoch: globalModel.messageDeltaClearEpochFor(conversationID),
        tombstones: tombstones,
        upserts: target == null
            ? const <MessageReconciliationRecord<V2TimMessage>>[]
            : [
                globalModel.messageDeltaRecord(
                  revokedCopy!,
                ),
              ],
      ),
      forcePublishForRevoke: true,
    );
    if (revokedCopy != null) {
      globalModel.markMessageChangedByMessage(conversationID, revokedCopy);
    }
    if (refreshed == null &&
        !globalModel.hasActiveHistoryReconciliation(conversationID)) {
      globalModel.onMessageRevoked(msgID, conversationID);
    }
    // 先驱逐图集扩窗缓存。撤回图片仍保留 imageElem 供聊天气泡显示
    // “已撤回”，但绝不能继续作为全屏图集的可滑动项。
    ChatMediaGalleryExpandCache.removeMessage(
      msgID,
      conversationID: conversationID,
    );
    _notify();

    // 先同步会话预览，再提交网络撤回。否则会话列表要等 SDK 撤回回调
    // 才能看到状态，而该回调可能晚于当前页面的刷新或根本不触发。
    unawaited(
      ConversationSyncService.instance.markConversationLastMessageRevoked(
        msgID: msgID,
        conversationID: conversationID,
        isAdmin: isAdmin,
      ),
    );

    unawaited(
      _commitRevokeToSdk(
        msgID: msgID,
        isAdmin: isAdmin,
        webMessageInstance: webMessageInstance,
        target: target,
        optimisticMessage: revokedCopy,
        previousStatus: previousStatus,
        previousCloud: previousCloud,
        previousWeb: previousWeb,
        mutationToken: mutationToken,
        mutationScope: mutationScope,
      ),
    );
    return null;
  }

  V2TimMessage _revokedMessageCopy(
    V2TimMessage target, {
    required bool isAdmin,
  }) {
    final copy = V2TimMessage.fromJson(
      Map<String, dynamic>.from(target.toJson()),
    );
    copy.status = MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED;
    final data = <String, dynamic>{};
    final raw = copy.cloudCustomData?.trim() ?? '';
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) data.addAll(Map<String, dynamic>.from(decoded));
      } catch (_) {}
    }
    data['isRevoke'] = true;
    data['revokeByAdmin'] = isAdmin;
    copy.cloudCustomData = jsonEncode(data);
    copy.id ??= copy.msgID;
    return copy;
  }

  Future<void> _rollbackRevoke(
    V2TimMessage target, {
    required String msgID,
    required int? previousStatus,
    required String? previousCloud,
    required String? previousWeb,
    required String? mutationToken,
    required V2TimMessage? optimisticMessage,
    required HistoryWindowScope? mutationScope,
  }) async {
    final targetConv = mutationScope?.conversationID ?? conversationID;
    bool ownsOptimisticRow() =>
        _isHistoryMutationOwnerCurrent(mutationScope) &&
        globalModel.canonicalMessageWindow(targetConv).any(
              (message) =>
                  message.msgID == msgID &&
                  identical(message, optimisticMessage),
            );
    var projectionComplete = false;
    try {
      if (mutationToken != null) {
        await globalModel.recordHistoryWindowMutation(
          conversationID: mutationScope?.conversationID ?? conversationID,
          msgID: msgID,
          kind: HistoryWindowMutationKind.restore,
          restoreMutationToken: mutationToken,
          capturedScope: mutationScope,
        );
      }
      if (!ownsOptimisticRow()) return;
      final original = V2TimMessage.fromJson(
        Map<String, dynamic>.from(target.toJson()),
      );
      if (previousStatus != null) {
        original.status = previousStatus;
      }
      original.cloudCustomData = previousCloud;
      original.messageFromWeb = previousWeb;
      final restored = await _readHistoryRollbackFacts(
          targetConv: targetConv,
          messages: [original],
          ownsProjection: ownsOptimisticRow);
      if (restored == null) return;
      if (!ownsOptimisticRow()) return;
      // A later delete/revoke remains authoritative after undoing only our token.
      if (restored.isEmpty || isRevokedMessage(restored.first)) {
        projectionComplete = true;
        return;
      }
      // Revoke is optimistic. Release its tombstone and re-adopt the original
      // row through the same writer so an in-flight history request cannot
      // replay the failed revoke after the rollback.
      globalModel.releaseMessageDeltaTombstones(targetConv, <String>[msgID]);
      globalModel.restoreMessageDeltaAfterDeleteFailure(targetConv, restored);
      projectionComplete = true;
      if (!_disposed && conversationID == targetConv) _notify();
    } finally {
      if (projectionComplete || !ownsOptimisticRow()) {
        _finishHistoryMutationProjection(
            mutationScope, [if (mutationToken != null) mutationToken]);
      }
    }
  }

  Future<void> _commitRevokeToSdk({
    required String msgID,
    required bool isAdmin,
    required Object? webMessageInstance,
    required V2TimMessage? target,
    required int? previousStatus,
    required String? previousCloud,
    required String? previousWeb,
    required String? mutationToken,
    required V2TimMessage? optimisticMessage,
    required HistoryWindowScope? mutationScope,
  }) async {
    var sdkAccepted = false;
    try {
      if (isAdmin && chatConfig.isGroupAdminRecallEnabled && target != null) {
        // The optimistic Writer publishes a revoked copy, leaving target
        // unchanged for rollback. Send the cloud marker on a separate SDK
        // payload too; modifying target here would otherwise be a server no-op.
        final sdkMessage = _revokedMessageCopy(target, isAdmin: true)
          ..status = previousStatus;
        final rawWebMessage = previousWeb?.trim() ?? '';
        if (PlatformUtils().isWeb || rawWebMessage.isNotEmpty) {
          final decodedMessage = <String, dynamic>{};
          if (rawWebMessage.isNotEmpty) {
            try {
              final decoded = jsonDecode(rawWebMessage);
              if (decoded is Map) {
                decodedMessage.addAll(Map<String, dynamic>.from(decoded));
              }
            } catch (_) {}
          }
          decodedMessage['cloudCustomData'] = sdkMessage.cloudCustomData;
          sdkMessage.messageFromWeb = jsonEncode(decodedMessage);
        }
        final result = await modifyMessage(message: sdkMessage);
        if (result?.code != 0) {
          _notifyRevokeFailed();
          await _rollbackRevoke(
            target,
            msgID: msgID,
            previousStatus: previousStatus,
            previousCloud: previousCloud,
            previousWeb: previousWeb,
            mutationToken: mutationToken,
            optimisticMessage: optimisticMessage,
            mutationScope: mutationScope,
          );
          return;
        }
      } else {
        final res = await _messageService.revokeMessage(
          msgID: msgID,
          webMessageInstance: webMessageInstance,
          message: target,
        );
        if (res.code != 0) {
          _notifyRevokeFailed();
          if (target != null) {
            await _rollbackRevoke(
              target,
              msgID: msgID,
              previousStatus: previousStatus,
              previousCloud: previousCloud,
              previousWeb: previousWeb,
              mutationToken: mutationToken,
              optimisticMessage: optimisticMessage,
              mutationScope: mutationScope,
            );
          } else {
            if (mutationToken != null)
              await globalModel.recordHistoryWindowMutation(
                conversationID: mutationScope?.conversationID ?? conversationID,
                msgID: msgID,
                kind: HistoryWindowMutationKind.restore,
                restoreMutationToken: mutationToken,
                capturedScope: mutationScope,
              );
            if (!_isHistoryMutationScopeCurrent(mutationScope)) return;
            globalModel.releaseMessageDeltaTombstones(conversationID, <String>[
              msgID,
            ]);
          }
          return;
        }
      }
      sdkAccepted = true;
      if (mutationToken != null)
        await globalModel.recordHistoryWindowMutation(
          conversationID: mutationScope?.conversationID ?? conversationID,
          msgID: msgID,
          kind: HistoryWindowMutationKind.settle,
          restoreMutationToken: mutationToken,
          capturedScope: mutationScope,
        );
      // 首次撤回成功时，SDK 不一定马上回调消息变更事件。主动补一次
      // 当前消息窗口更新，避免第一次点击网络成功但气泡仍保持原内容，
      // 第二次点击才看起来生效。
      if (!_isHistoryMutationScopeCurrent(mutationScope)) return;
      globalModel.onMessageRevoked(msgID, conversationID);
      await ConversationSyncService.instance.markConversationLastMessageRevoked(
        msgID: msgID,
        conversationID: conversationID,
        isAdmin: isAdmin,
      );
    } catch (_) {
      // A durable settle failure must not undo a revoke accepted by the SDK.
      if (sdkAccepted) return;
      _notifyRevokeFailed();
      if (target != null) {
        await _rollbackRevoke(
          target,
          msgID: msgID,
          previousStatus: previousStatus,
          previousCloud: previousCloud,
          previousWeb: previousWeb,
          mutationToken: mutationToken,
          optimisticMessage: optimisticMessage,
          mutationScope: mutationScope,
        );
      } else {
        if (mutationToken != null)
          await globalModel.recordHistoryWindowMutation(
            conversationID: mutationScope?.conversationID ?? conversationID,
            msgID: msgID,
            kind: HistoryWindowMutationKind.restore,
            restoreMutationToken: mutationToken,
            capturedScope: mutationScope,
          );
        if (!_isHistoryMutationScopeCurrent(mutationScope)) return;
        globalModel.releaseMessageDeltaTombstones(conversationID, <String>[
          msgID,
        ]);
      }
    } finally {
      // A target rollback retains its guard until the raw correction succeeds.
      // Success is released by durable settle; absent targets never published
      // an optimistic message into the page base.
      if (target == null || sdkAccepted) {
        _finishHistoryMutationProjection(
            mutationScope, [if (mutationToken != null) mutationToken]);
      }
    }
  }

  setMessageItemChecked(V2TimMessage message, bool isChecked) {
    final messageKey = ChatUiStateStore.messageKeyOf(message);
    if (messageKey.isNotEmpty) {
      chatUiStateStore.setMessageSelected(
        conversationID,
        messageKey,
        isChecked,
      );
    }
    final msgID = message.msgID;
    if (msgID != null && msgID.isNotEmpty && msgID != messageKey) {
      chatUiStateStore.bindMessageAlias(conversationID, messageKey, msgID);
    }

    _notify();
  }

  deleteSelectedMsg() async {
    final messageList = List<V2TimMessage>.from(getOriginMessageList());
    final selectedMessages = getSelectedMessageList()
        .where((message) => !isWalletCardMessage(message))
        .toList();
    if (selectedMessages.isEmpty) {
      return;
    }
    final msgIDs = selectedMessages
        .map((message) => message.msgID ?? '')
        .where((msgID) => msgID.isNotEmpty)
        .toList();
    final webMessageInstanceList =
        selectedMessages.map((message) => message.messageFromWeb).toList();

    final mutationScope = globalModel.historyWindowScopeFor(conversationID);
    final mutationTokens = <String, String>{};
    try {
      for (final message in selectedMessages) {
        final msgID = message.msgID?.trim() ?? '';
        if (msgID.isEmpty) continue;
        final token = await globalModel.recordHistoryWindowMutation(
            conversationID: conversationID,
            msgID: msgID,
            kind: HistoryWindowMutationKind.delete,
            message: message,
            pending: true);
        if (token != null) mutationTokens[msgID] = token;
        if (!_isHistoryMutationScopeCurrent(mutationScope))
          throw const HistoryWindowStaleScope();
      }
    } catch (_) {
      // A partially persisted selection must not become an invisible deletion.
      try {
        for (final entry in mutationTokens.entries) {
          await globalModel.recordHistoryWindowMutation(
              conversationID: mutationScope?.conversationID ?? conversationID,
              msgID: entry.key,
              kind: HistoryWindowMutationKind.restore,
              restoreMutationToken: entry.value,
              capturedScope: mutationScope);
        }
      } finally {
        _finishHistoryMutationProjection(mutationScope, mutationTokens.values);
      }
      rethrow;
    }

    final removed = <V2TimMessage>[];
    final removedIndexes = <int>[];
    MessageCommitResult? deleteCommit;
    for (var i = 0; i < messageList.length; i++) {
      final element = messageList[i];
      if (msgIDs.contains(element.msgID)) {
        removed.add(element);
        removedIndexes.add(i);
      }
    }
    if (removed.isNotEmpty) {
      for (var i = removedIndexes.length - 1; i >= 0; i--) {
        messageList.removeAt(removedIndexes[i]);
      }
      deleteCommit = globalModel.commitMessageDelta(
        MessageDelta<V2TimMessage>(
          conversationKey: conversationID,
          eventID: 'delete:selected:${DateTime.now().microsecondsSinceEpoch}',
          kind: MessageDeltaKind.delete,
          source: MessageDeltaSource.userAction,
          generation: globalModel.messageDeltaGenerationFor(conversationID),
          clearEpoch: globalModel.messageDeltaClearEpochFor(conversationID),
          explicitDeletes: msgIDs.toSet(),
        ),
      );
      _syncConversationPreviewAfterDelete(
        _previewDeleteIds(removed, fallbackIds: msgIDs),
        messageList,
      );
    }
    unawaited(
      _commitDeleteToSdk(
        msgIDs: msgIDs,
        webMessageInstanceList: webMessageInstanceList,
        removed: removed,
        removedIndexes: removedIndexes,
        deleteCommit: deleteCommit,
        mutationTokens: mutationTokens,
        mutationScope: mutationScope,
      ),
    );
  }

  updateMultiSelectStatus(bool isSelect) {
    chatUiStateStore.setMultiSelect(conversationID, isSelect);
    // setMultiSelect(false) already clears store selection.
    _notify();
  }

  Future<V2TimValueCallback<V2TimGroupMessageReadMemberList>>
      getGroupMessageReadMemberList(
    String messageID,
    GetGroupMessageReadMemberListFilter fileter,
    int nextSeq,
  ) async {
    if (!_canUseReadReceipt) {
      return V2TimValueCallback<V2TimGroupMessageReadMemberList>(
        code: 6017,
        desc: "The community group does not support message read receipt",
      );
    }
    final res = await _messageService.getGroupMessageReadMemberList(
      nextSeq: nextSeq,
      messageID: messageID,
      filter: fileter,
    );
    return res;
  }

  Future<List<V2TimMessage>?> downloadMergerMessage(String msgID) async {
    final cached = globalModel.getLocalMergerMessageList(msgID);
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final result = await _messageService.downloadMergerMessage(msgID: msgID);
    if (result != null && result.isNotEmpty) {
      globalModel.cacheLocalMergerMessageList(keys: [msgID], messages: result);
    }
    return result;
  }

  Future<V2TimMessage?> findMessage(String msgID) async {
    List<V2TimMessage> messageList = getOriginMessageList();
    final repliedMessage =
        messageList.where((element) => element.msgID == msgID).toList();
    if (repliedMessage.isNotEmpty) {
      return repliedMessage.first;
    }
    final message = await _messageService.findMessages(messageIDList: [msgID]);
    if (message != null && message.isNotEmpty) {
      return message.first;
    }
    return null;
  }

  showLatestUnread() {
    globalModel.flushDeferredIncomingMessages(
      conversationID,
      notify: false,
      userInitiated: true,
    );
    globalModel.unlockEntryUnreadForTongue(
      conversationID: conversationID,
      notify: false,
    );
    globalModel.clearReceivedUnreadState(conversationID: conversationID);
    markMessageAsRead(force: true);
    globalModel.setMessageListPosition(
      conversationID,
      HistoryMessagePosition.bottom,
    );
  }

  // 添加发送中的消息的 id 或者 msgID(id 不存在时使用 msgID)
  void addSendingMessageID(String? id) {
    if (id?.isNotEmpty == true) {
      _sendingMessageIDMap[id!] = false;
    }
  }

  bool _isOutgoingMediaCancelled(String? id) {
    return id != null &&
        id.isNotEmpty &&
        (_cancelledOutgoingMediaIds.contains(id) ||
            globalModel.isOutgoingMediaCancelled(id));
  }

  void _markOutgoingMediaCancelled(String? id) {
    if (id != null && id.isNotEmpty) {
      _cancelledOutgoingMediaIds.add(id);
      globalModel.markOutgoingMediaCancelled(id);
    }
  }

  void _clearOutgoingMediaCancelled(String? id) {
    if (id != null && id.isNotEmpty) {
      _cancelledOutgoingMediaIds.remove(id);
      globalModel.clearOutgoingMediaCancelled(id);
    }
  }

  void _markOutgoingMediaSendFailed({
    required String convID,
    String? clientId,
    String? msgID,
  }) {
    globalModel.markOutgoingSendFailedByIdentity(
      conversationID: convID,
      clientId: clientId,
      msgID: msgID,
      reason: 'media_failed',
    );
  }

  String _nextOptimisticClientId() {
    return '${V2TimMessage.createIDPrefix}${nextChatMediaUniqueToken()}';
  }

  /// 点发送立刻上屏，不必等原生 createTextMessage。
  String _prependOptimisticTextPlaceholder({
    required String text,
    String? cloudCustomData,
    List<String>? groupAtUserList,
  }) {
    final optimisticId = _nextOptimisticClientId();
    final optimistic = tools.setUserInfoForMessage(
      V2TimMessage(
        elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
        textElem: V2TimTextElem(text: text),
        cloudCustomData: cloudCustomData,
        groupAtUserList: groupAtUserList,
      ),
      optimisticId,
    );
    optimistic.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
    applyOutgoingStableIdToMessage(optimistic, optimisticId);
    addSendingMessageID(optimisticId);
    _prependOutgoingMessage(optimistic);
    return optimisticId;
  }

  void _adoptOptimisticOutgoingTextMessage({
    required String optimisticId,
    required V2TimMessage newMessage,
  }) {
    final convID = conversationID;
    _swapOutgoingMessage(
      convID: convID,
      oldClientId: optimisticId,
      newMessage: newMessage,
    );
    final clientId = newMessage.id;
    if (clientId != null && clientId.isNotEmpty) {
      chatUiStateStore.bindMessageAlias(
        convID,
        optimisticId,
        ChatUiStateStore.messageKeyOf(newMessage),
      );
      addSendingMessageID(clientId);
    }
  }

  void _ensureWebOutgoingImagePreviewPath(
    V2TimMessage message, {
    String? previewPath,
  }) {
    if (previewPath == null || previewPath.isEmpty) {
      return;
    }
    message.imageElem ??= V2TimImageElem(path: previewPath);
    if (TencentUtils.checkString(message.imageElem!.path) == null) {
      message.imageElem!.path = previewPath;
    }
  }

  String _prependOptimisticImageMessage({
    required String convID,
    required String imagePath,
    Size? imageSize,
  }) {
    final optimisticId = _nextOptimisticClientId();
    final optimistic = tools.setUserInfoForMessage(
      V2TimMessage(
        elemType: MessageElemType.V2TIM_ELEM_TYPE_IMAGE,
        imageElem: V2TimImageElem(path: imagePath),
      ),
      optimisticId,
    );
    optimistic.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
    applyOutgoingStableIdToMessage(optimistic, optimisticId);
    addSendingMessageID(optimisticId);
    globalModel.setMessageProgress(optimisticId, 0);
    if (imageSize != null && imageSize.width > 0 && imageSize.height > 0) {
      applyImageLayoutToMessage(optimistic, imageSize);
    }
    globalModel.setFileMessageLocation(
      optimisticId,
      imagePath,
      imageSize: imageSize,
    );
    _prependOutgoingMessageForConversation(convID, optimistic);
    return optimisticId;
  }

  void _adoptOptimisticOutgoingImageMessage({
    required String convID,
    required String optimisticId,
    required V2TimMessage newMessage,
    required String filePath,
    Size? imageSize,
  }) {
    final progress = globalModel.getMessageProgress(optimisticId);
    if (imageSize != null && imageSize.width > 0 && imageSize.height > 0) {
      applyImageLayoutToMessage(newMessage, imageSize);
    }
    final imageElem = newMessage.imageElem;
    if (imageElem != null) {
      imageElem.path = filePath;
    }
    _swapOutgoingMessage(
      convID: convID,
      oldClientId: optimisticId,
      newMessage: newMessage,
    );
    final clientId = newMessage.id;
    if (clientId != null && clientId.isNotEmpty) {
      chatUiStateStore.bindMessageAlias(
        convID,
        optimisticId,
        ChatUiStateStore.messageKeyOf(newMessage),
      );
      addSendingMessageID(clientId);
      if (progress > 0) {
        globalModel.setUploadProgressRowLocal(clientId, progress);
      }
      globalModel.setFileMessageLocationRowLocal(
        clientId,
        filePath,
        imageSize: imageSize,
      );
      globalModel.markMessageRowsChangedByMsgIDs([
        optimisticId,
        clientId,
        newMessage.msgID,
      ]);
    }
  }

  String _prependOptimisticVideoMessage({
    required String convID,
    required String videoPath,
    int? duration,
    String? snapshotPath,
    bool requestInitialPin = true,
  }) {
    final optimisticId = _nextOptimisticClientId();
    final snapshot = TencentUtils.checkString(snapshotPath);
    final optimistic = tools.setUserInfoForMessage(
      V2TimMessage(
        elemType: MessageElemType.V2TIM_ELEM_TYPE_VIDEO,
        videoElem: V2TimVideoElem(
          videoPath: videoPath,
          snapshotPath: snapshot,
          duration: duration,
        ),
      ),
      optimisticId,
    );
    optimistic.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
    applyOutgoingStableIdToMessage(optimistic, optimisticId);
    addSendingMessageID(optimisticId);
    globalModel.setMessageProgress(optimisticId, 0);
    globalModel.setFileMessageLocation(optimisticId, videoPath);
    _prependOutgoingMessageForConversation(convID, optimistic);
    if (requestInitialPin) {
      globalModel.requestPinToBottom(convID, force: true);
    }
    return optimisticId;
  }

  String _prependOptimisticSoundMessage({
    required String convID,
    required String soundPath,
    required int duration,
  }) {
    final optimisticId = _nextOptimisticClientId();
    final optimistic = tools.setUserInfoForMessage(
      V2TimMessage(
        elemType: MessageElemType.V2TIM_ELEM_TYPE_SOUND,
        soundElem: V2TimSoundElem(
          path: soundPath,
          localUrl: soundPath,
          duration: duration,
        ),
        random: optimisticId.hashCode,
      ),
      optimisticId,
    );
    optimistic.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
    applyOutgoingStableIdToMessage(optimistic, optimisticId);
    addSendingMessageID(optimisticId);
    globalModel.setUploadProgressRowLocal(optimisticId, 0);
    globalModel.setFileMessageLocationRowLocal(optimisticId, soundPath);
    _prependOutgoingMessageForConversation(convID, optimistic);
    return optimisticId;
  }

  void _swapOutgoingMessage({
    required String convID,
    required String oldClientId,
    required V2TimMessage newMessage,
  }) {
    final list = List<V2TimMessage>.from(
      globalModel.rawMessageList(convID) ?? const <V2TimMessage>[],
    );
    final oldId = oldClientId.trim();
    // Collapse optimistic + any orphan SDK echo of the same send into one row.
    // A plain "insert when missing" left the old placeholder in place and caused
    // 一图两气泡 until a later dedupe pass (if any) cleaned up.
    V2TimMessage? previous;
    for (final item in list) {
      if (oldId.isNotEmpty && item.id == oldId) {
        previous = item;
        break;
      }
      final itemStable = readOutgoingStableId(item);
      if (itemStable != null && itemStable.isNotEmpty && itemStable == oldId) {
        previous = item;
        break;
      }
    }
    final stableId = readOutgoingStableId(previous) ??
        readOutgoingStableId(newMessage) ??
        oldId;
    if (stableId.isNotEmpty) {
      applyOutgoingStableIdToMessage(newMessage, stableId);
    }
    if (newMessage.status == MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC) {
      admitOwnConfirmedOutgoingToHistoryWindow(newMessage);
    }
    if (previous != null) {
      TUIChatGlobalModel.preserveOutgoingLocalOrderDataForTesting(
        previous,
        newMessage,
      );
      ChatMessageHeightCache.instance.rememberAliasesBetween(
        previous,
        newMessage,
      );
    }

    final newId = newMessage.id?.trim() ?? '';
    final newMsgID = newMessage.msgID?.trim() ?? '';
    var matchedCount = 0;
    for (final item in list) {
      final itemStable = readOutgoingStableId(item);
      final isSameSend = (oldId.isNotEmpty && item.id == oldId) ||
          (stableId.isNotEmpty && itemStable == stableId) ||
          (newId.isNotEmpty && item.id == newId) ||
          (newMsgID.isNotEmpty && item.msgID?.trim() == newMsgID);
      if (isSameSend) {
        matchedCount++;
      }
    }

    _seedOutgoingMediaRowHeight(newMessage);
    globalModel.clearUploadProgressRowLocal(oldId);
    removeSendingMessageID(oldId);
    final localPath = newMessage.imageElem?.path?.trim() ?? '';
    if (previous != null &&
        matchedCount == 1 &&
        stableId.isNotEmpty &&
        globalModel.replaceMessageRowByStableIdentity(
              conversationID: convID,
              stableIdentity: stableId,
              replacement: newMessage,
              aliases: <String?>[oldId, stableId, newId, newMsgID, localPath],
            ) ==
            RowLocalMessageReplacementResult.replaced) {
      outputLogger.i(
        'gallery_swap_row_local conv=$convID optimistic=$oldId sdkId=$newId msgID=$newMsgID '
        'matched=$matchedCount raw=${globalModel.rawMessageList(convID)?.length ?? 0}',
      );
      // Stable identity, membership, order and row height are unchanged. The
      // row-local revision makes the bubble resolve the authoritative SDK
      // message; a list revision or completion-time pin would only rebuild and
      // move the whole viewport.
      return;
    }
    final next = <V2TimMessage>[];
    var inserted = false;
    for (final item in list) {
      final itemStable = readOutgoingStableId(item);
      final isSameSend = (oldId.isNotEmpty && item.id == oldId) ||
          (stableId.isNotEmpty && itemStable == stableId) ||
          (newId.isNotEmpty && item.id == newId) ||
          (newMsgID.isNotEmpty && item.msgID?.trim() == newMsgID);
      if (isSameSend) {
        if (!inserted) {
          next.add(newMessage);
          inserted = true;
        }
        continue;
      }
      next.add(item);
    }
    if (!inserted) {
      next.insert(0, newMessage);
    }
    // 已是完整替换后的列表。若走默认 merge，会把旧 optimistic 再拼回来，
    // 而 dedupe 认不出 optimisticId ≠ SDK clientId → 一图两气泡（一条发送中一条已送达）。
    final commit = globalModel.setMessageList(convID, next, replace: true);
    outputLogger.i(
      'gallery_swap_set_list conv=$convID optimistic=$oldId sdkId=$newId msgID=$newMsgID '
      'matched=$matchedCount before=${list.length} after=${commit.rawCount}',
    );
    globalModel.prepareForOutgoingMessage(convID);
    globalModel.requestPinToBottom(convID, force: false);
  }

  void _removeOutgoingMessage({
    required String convID,
    String? clientId,
    String? msgID,
  }) {
    final storageConvID = convID.trim();
    if (storageConvID.isEmpty) {
      return;
    }
    final cid = clientId?.trim() ?? '';
    final mid = msgID?.trim() ?? '';
    final list =
        globalModel.rawMessageList(storageConvID) ?? const <V2TimMessage>[];
    V2TimMessage? live;
    for (final item in list) {
      if (cid.isNotEmpty && item.id == cid) {
        live = item;
        break;
      }
      if (mid.isNotEmpty && item.msgID == mid) {
        live = item;
        break;
      }
      final stable = readOutgoingStableId(item)?.trim() ?? '';
      if (cid.isNotEmpty && stable == cid) {
        live = item;
        break;
      }
    }
    final localDeletes = <String>{};
    if (cid.isNotEmpty) {
      localDeletes.add(cid);
    }
    final liveId = live?.id?.trim() ?? '';
    if (liveId.isNotEmpty) {
      localDeletes.add(liveId);
    }
    final liveStable =
        live == null ? '' : (readOutgoingStableId(live)?.trim() ?? '');
    if (liveStable.isNotEmpty) {
      localDeletes.add(liveStable);
    }
    final tipLocalIds = <String>{};
    if (cid.isNotEmpty) {
      tipLocalIds.add(c2cPeerRejectedTipLocalId(cid));
    }
    if (liveId.isNotEmpty) {
      tipLocalIds.add(c2cPeerRejectedTipLocalId(liveId));
    }
    localDeletes.addAll(tipLocalIds);
    for (final item in list) {
      final itemId = item.id?.trim() ?? '';
      if (itemId.isEmpty || !tipLocalIds.contains(itemId)) {
        continue;
      }
      if (isC2cPeerRejectedTipMessage(item)) {
        localDeletes.add(itemId);
      }
    }
    final explicitDeletes = <String>{};
    if (mid.isNotEmpty) {
      explicitDeletes.add(mid);
    }
    final liveMsgID = live?.msgID?.trim() ?? '';
    if (liveMsgID.isNotEmpty) {
      explicitDeletes.add(liveMsgID);
    }
    if (localDeletes.isEmpty && explicitDeletes.isEmpty) {
      return;
    }
    globalModel.commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: storageConvID,
        eventID:
            'send_remove:$storageConvID:$cid:$mid:${DateTime.now().microsecondsSinceEpoch}',
        kind: MessageDeltaKind.delete,
        source: MessageDeltaSource.sendPipeline,
        generation: globalModel.messageDeltaGenerationFor(storageConvID),
        clearEpoch: globalModel.messageDeltaClearEpochFor(storageConvID),
        localDeletes: localDeletes,
        explicitDeletes: explicitDeletes,
      ),
    );
    globalModel.clearMessageProgress(clientId);
    globalModel.clearMessageProgress(msgID);
    if (clientId != null) {
      removeSendingMessageID(clientId);
    }
    if (msgID != null) {
      removeSendingMessageID(msgID);
    }
  }

  Future<void> cancelOutgoingMediaMessage(V2TimMessage message) async {
    final clientId = message.id;
    final msgID = message.msgID;
    final convID = conversationID;
    if (convID.isEmpty) {
      return;
    }
    _markOutgoingMediaCancelled(clientId);
    _markOutgoingMediaCancelled(msgID);
    _markOutgoingMediaSendFailed(
      convID: convID,
      clientId: clientId,
      msgID: msgID,
    );
    globalModel.clearMessageProgress(clientId);
    globalModel.clearMessageProgress(msgID);
    if (clientId != null) {
      removeSendingMessageID(clientId);
    }
    if (msgID != null) {
      removeSendingMessageID(msgID);
    }
    final sdkMsgID = TencentUtils.checkString(msgID);
    if (sdkMsgID != null) {
      try {
        await _messageService.revokeMessage(
          msgID: sdkMsgID,
          webMessageInstance: message.messageFromWeb,
          message: message,
        );
      } catch (_) {}
      await _messageService.deleteMessageFromLocalStorage(
        msgID: sdkMsgID,
        webMessageInstance: message.messageFromWeb,
      );
    }
    _notify();
  }

  // 移除发送中的消息的 id 或者 msgID(id 不存在时使用 msgID)
  void removeSendingMessageID(String id) {
    _sendingMessageIDMap.remove(id);
  }

  // 是否已经延迟渲染
  bool? hasDelayedRenderSendingStatus(String id) {
    if (_sendingMessageIDMap.containsKey(id)) {
      return _sendingMessageIDMap[id];
    }

    return true;
  }

  // 设置已经延迟渲染过的消息
  void setDelayedRenderSendingStatus(String id) {
    if (_sendingMessageIDMap.containsKey(id)) {
      _sendingMessageIDMap[id] = true;
    }
  }

  bool isVoteMessage(V2TimMessage message) {
    bool isVote = false;
    V2TimCustomElem? custom = message.customElem;

    if (custom != null) {
      String? data = custom.data;
      if (data != null && data.isNotEmpty) {
        try {
          Map<String, dynamic> mapData = json.decode(data);
          if (mapData["businessID"] == "group_poll") {
            isVote = true;
          }
        } catch (err) {
          // err
        }
      }
    }
    return isVote;
  }

  bool isContactCardMessage(V2TimMessage message) {
    final custom = message.customElem;
    final data = custom?.data;
    if (data == null || data.isEmpty) {
      return false;
    }
    try {
      final mapData = json.decode(data);
      if (mapData is! Map) {
        return false;
      }
      return mapData['businessID']?.toString() == 'contact_card';
    } catch (_) {
      return false;
    }
  }

  bool isWalletCardMessage(V2TimMessage message) {
    final custom = message.customElem;
    final data = custom?.data;
    if (data == null || data.isEmpty) {
      return false;
    }
    try {
      final mapData = json.decode(data);
      if (mapData is! Map) {
        return false;
      }
      final customType = mapData['customType']?.toString() ?? '';
      final legacyType = mapData['type']?.toString() ?? '';
      final businessID = mapData['businessID']?.toString() ?? '';
      if (customType == 'platform_wallet_notice' ||
          businessID == 'platform_wallet_notice' ||
          legacyType == 'platform_wallet_notice') {
        return false;
      }
      return customType == 'wallet_transfer' ||
          legacyType == 'wallet_transfer' ||
          customType == 'wallet_red_packet' ||
          legacyType == 'wallet_red_packet' ||
          customType == 'wallet_group_transfer' ||
          legacyType == 'wallet_group_transfer' ||
          businessID == 'wallet_order';
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _latestReturnOwner = null;
    _latestReturnConversation = null;
    _latestReturnHandler = null;
    stopVoiceAutoPlay();
    _chatOpenGeneration++;
    _historyWindowGeneration++;
    _preGroupMemberListForOpen = null;
    _openProfileEnrichmentInFlight = null;
    globalModel.removeRoamingSyncListener(_onRoamingSyncFinished);
    _readReceiptFlushTimer?.cancel();
    _readReceiptFlushTimer = null;
    _readReceiptRetryCount = 0;
    _fillTowardOlderHistoryResumeTimer?.cancel();
    _fillTowardOlderHistoryResumeTimer = null;
    _groupMarkReadDebounce?.cancel();
    _groupMarkReadDebounce = null;
    cancelOpenSideMemberLoads();
    _groupSenderDisplayNameCache.clear();
    _pagination.setArchiveHistoryNotice(null);
    _disposed = true;
    globalModel.cancelHistoryReconciliation(conversationID);
    globalModel.unlockEntryUnreadForTongue(
      conversationID: conversationID,
      notify: false,
    );
    if (!suppressReadReporting) {
      unawaited(markMessageAsRead(notify: false, force: true));
      globalModel.setUnreadCountForTongue(0, notify: false);
    }
    globalModel.clearCurrentConversation(notify: false);
    _isInit = false;
    super.dispose();
  }
}
