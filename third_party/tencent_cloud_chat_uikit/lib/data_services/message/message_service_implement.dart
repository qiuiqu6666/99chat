import 'package:tencent_cloud_chat_uikit/ui/utils/media_send_perf.dart';
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimSimpleMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/get_group_message_read_member_list_filter.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_priority_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/offlinePushInfo.dart';
import 'package:tencent_cloud_chat_sdk/enum/receive_message_opt_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_message_read_member_list.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_message_read_member_list.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_change_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_change_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_online_url.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_online_url.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_receipt.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_receipt.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_param.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_search_param.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_search_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_msg_create_info_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_msg_create_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_callback.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_conversation_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/core_services_implements.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/conversation_notify_bridge.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_history_trace.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/error_message_converter.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'message_web_history_loader_stub.dart'
    if (dart.library.html) 'message_web_history_loader_web.dart';
import 'outgoing_message_send_queue.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart'
    show kChatMediaBatchIdKey, kChatMediaBatchIndexKey;
import 'typing_status_send_queue.dart';

class _MessageDownloadFlight {
  _MessageDownloadFlight(this.sourceMessage);

  V2TimMessage? sourceMessage;
  final List<void Function(V2TimMessage)> listeners =
      <void Function(V2TimMessage)>[];
  bool delivered = false;
  late Future<V2TimCallback> future;

  void deliver(V2TimMessage message) {
    if (delivered) {
      return;
    }
    delivered = true;
    sourceMessage = message;
    final snapshot = List<void Function(V2TimMessage)>.from(listeners);
    listeners.clear();
    for (final listener in snapshot) {
      try {
        listener(message);
      } catch (_) {}
    }
  }
}

class _HistoryReadFlight {
  _HistoryReadFlight(this.generation);

  final int generation;
  final Completer<void> completion = Completer<void>();
  bool superseded = false;
}

class _HistoryV2Result {
  const _HistoryV2Result.web(this.web) : sdk = null;
  const _HistoryV2Result.sdk(this.sdk) : web = null;

  final V2TimMessageListResult? web;
  final V2TimValueCallback<List<V2TimMessage>>? sdk;
}

class _HistoryListResult {
  const _HistoryListResult.web(this.web) : sdk = null;
  const _HistoryListResult.sdk(this.sdk) : web = null;

  final List<V2TimMessage>? web;
  final V2TimValueCallback<List<V2TimMessage>>? sdk;
}

class _HistoryCompleteResult {
  const _HistoryCompleteResult.web(this.web) : sdk = null;
  const _HistoryCompleteResult.sdk(this.sdk) : web = null;

  final V2TimMessageListResult? web;
  final V2TimValueCallback<V2TimMessageListResult>? sdk;
}

class MessageServiceImpl extends MessageService {
  final CoreServicesImpl _coreService = serviceLocator<CoreServicesImpl>();
  final TypingStatusSendQueue _typingStatusQueue = TypingStatusSendQueue();
  final Set<V2TimAdvancedMsgListener> _advancedListeners =
      <V2TimAdvancedMsgListener>{};
  V2TimAdvancedMsgListener? _sdkAdvancedListener;
  Future<void>? _advancedListenerAttachInFlight;

  static const Duration _groupReadMinInterval = Duration(seconds: 5);
  static const Duration _groupReadFrequencyBackoff = Duration(seconds: 12);
  // A stuck native history Future must release the reconciliation barrier so
  // later send/adoption and user actions cannot wait indefinitely.
  static const Duration _historyReadTimeout = Duration(seconds: 20);
  static const Set<int> _groupReadFrequencyCodes = <int>{-10113, 6015, 7008};
  static final Map<String, Future<V2TimCallback>> _groupReadInFlight = {};
  static final Map<String, Future<V2TimCallback>> _groupReadDeferred = {};
  static final Map<String, DateTime> _groupReadLastSuccess = {};
  static final Map<String, DateTime> _groupReadBlockedUntil = {};
  static final Set<String> _groupReadNeedsTrailing = <String>{};
  static final Map<String, _MessageDownloadFlight> _downloadInFlight =
      <String, _MessageDownloadFlight>{};
  final Map<String, _HistoryReadFlight> _historyReadInFlight =
      <String, _HistoryReadFlight>{};
  final Map<String, int> _historyGenerationByKey = <String, int>{};
  final Map<String, Future<dynamic>> _historyExactRequestInFlight =
      <String, Future<dynamic>>{};
  @visibleForTesting
  static const int thumbnailDownloadMaxConcurrent = 2;
  @visibleForTesting
  static const int thumbnailDownloadMaxQueue = 24;
  @visibleForTesting
  static const int thumbnailDownloadMaxStartsPerMinute = 12;
  static int _thumbnailDownloadActive = 0;
  static final List<Completer<bool>> _thumbnailDownloadWaiters =
      <Completer<bool>>[];
  static final List<int> _thumbnailDownloadStartsMs = <int>[];

  static void _pruneThumbnailDownloadStarts(int nowMs) {
    _thumbnailDownloadStartsMs.removeWhere(
      (startedMs) => nowMs < startedMs || nowMs - startedMs >= 60000,
    );
  }

  static bool _tryStartThumbnailDownload() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _pruneThumbnailDownloadStarts(nowMs);
    if (_thumbnailDownloadActive < thumbnailDownloadMaxConcurrent &&
        _thumbnailDownloadStartsMs.length <
            thumbnailDownloadMaxStartsPerMinute) {
      _thumbnailDownloadActive++;
      _thumbnailDownloadStartsMs.add(nowMs);
      return true;
    }
    return false;
  }

  static Future<bool> _acquireThumbnailDownloadSlot() async {
    if (_tryStartThumbnailDownload()) {
      return true;
    }
    if (_thumbnailDownloadStartsMs.length >=
            thumbnailDownloadMaxStartsPerMinute ||
        _thumbnailDownloadWaiters.length >= thumbnailDownloadMaxQueue) {
      return false;
    }
    final waiter = Completer<bool>();
    _thumbnailDownloadWaiters.add(waiter);
    return waiter.future;
  }

  static void _releaseThumbnailDownloadSlot() {
    if (_thumbnailDownloadActive > 0) {
      _thumbnailDownloadActive--;
    }
    while (_thumbnailDownloadWaiters.isNotEmpty) {
      final waiter = _thumbnailDownloadWaiters.removeAt(0);
      if (_tryStartThumbnailDownload()) {
        waiter.complete(true);
        return;
      }
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      _pruneThumbnailDownloadStarts(nowMs);
      if (_thumbnailDownloadStartsMs.length >=
          thumbnailDownloadMaxStartsPerMinute) {
        waiter.complete(false);
        for (final pending in _thumbnailDownloadWaiters) {
          pending.complete(false);
        }
        _thumbnailDownloadWaiters.clear();
        return;
      }
      waiter.complete(false);
    }
  }

  bool _isSoftWebSdkError(Object error) {
    if (!PlatformUtils().isWeb) {
      return false;
    }
    final text = error.toString();
    return text.contains('Unexpected null value') ||
        text.contains('Future already completed') ||
        text.contains("NoSuchMethodError: 'message'") ||
        text.contains('TypeErrorImpl');
  }

  void _printSoftWebSdkError(String scope, Object error) {
    if (kDebugMode) {
      debugPrint('$scope: $error');
    }
  }

  String _historyLaneKey({String? userID, String? groupID}) {
    final identity = SessionIdentityService.instance.capture();
    final owner =
        identity.ownerUserId.isEmpty ? 'unknown' : identity.ownerUserId;
    final session = '$owner@${identity.generation}';
    final group = ChatIdFormat.canonicalGroupStorageId(groupID);
    if (group.isNotEmpty) return '$session|group:$group';
    final user = ChatIdFormat.rawUserUid(userID);
    return user.isEmpty ? '$session|unknown' : '$session|c2c:$user';
  }

  Future<T> _runHistoryInLane<T>({
    required String key,
    required String requestKey,
    required Future<T> Function() start,
  }) async {
    final exactKey = '$key|$requestKey';
    final existingExact = _historyExactRequestInFlight[exactKey];
    if (existingExact != null) {
      return await existingExact as T;
    }

    late final Future<T> task;
    task = _runHistoryInConversationLane(key: key, start: start);
    _historyExactRequestInFlight[exactKey] = task;
    try {
      return await task;
    } finally {
      if (identical(_historyExactRequestInFlight[exactKey], task)) {
        _historyExactRequestInFlight.remove(exactKey);
      }
    }
  }

  Future<T> _runHistoryInConversationLane<T>({
    required String key,
    required Future<T> Function() start,
  }) async {
    while (true) {
      final existing = _historyReadInFlight[key];
      if (existing == null) break;
      // Waiters use the same bounded window as the original caller. If that
      // window expires, supersede the logical lane immediately; the native
      // Future cannot be cancelled, but its late completion is fenced by the
      // flight identity and cannot clear a newer generation.
      try {
        await existing.completion.future.timeout(_historyReadTimeout);
      } on TimeoutException catch (error) {
        existing.superseded = true;
        if (identical(_historyReadInFlight[key], existing)) {
          _historyReadInFlight.remove(key);
        }
        if (!existing.completion.isCompleted) {
          existing.completion.complete();
        }
        ChatHistoryTrace.log(
          'history_lane_superseded',
          conversationID: key,
          extras: <String, Object?>{
            'requestGeneration': existing.generation,
            'timeoutMs': _historyReadTimeout.inMilliseconds,
            'error': error.toString(),
          },
        );
      }
    }

    final generation = (_historyGenerationByKey[key] ?? 0) + 1;
    _historyGenerationByKey[key] = generation;
    final flight = _HistoryReadFlight(generation);
    _historyReadInFlight[key] = flight;
    late Future<T> nativeFuture;
    try {
      nativeFuture = start();
    } catch (_) {
      _finishHistoryLane(key, flight);
      rethrow;
    }
    nativeFuture.then<void>(
      (_) => _finishHistoryLane(key, flight),
      onError: (Object _, StackTrace __) {
        _finishHistoryLane(key, flight);
      },
    );
    try {
      return await nativeFuture.timeout(_historyReadTimeout);
    } on TimeoutException catch (error) {
      // Release the logical lane immediately. The native Future cannot be
      // cancelled, so its late result is fenced by [flight] identity and is
      // discarded by [_finishHistoryLane] once a newer generation owns the
      // key. This lets the next user request proceed without waiting for a
      // stuck SDK Future.
      flight.superseded = true;
      if (identical(_historyReadInFlight[key], flight)) {
        _historyReadInFlight.remove(key);
      }
      if (!flight.completion.isCompleted) {
        flight.completion.complete();
      }
      ChatHistoryTrace.log(
        'history_lane_timeout',
        conversationID: key,
        extras: <String, Object?>{
          'lane': key,
          'requestGeneration': generation,
          'timeoutMs': _historyReadTimeout.inMilliseconds,
          'error': error.toString(),
        },
      );
      rethrow;
    }
  }

  void _finishHistoryLane(String key, _HistoryReadFlight flight) {
    if (flight.superseded) {
      ChatHistoryTrace.log(
        'history_lane_late_completion',
        conversationID: key,
        extras: <String, Object?>{
          'requestGeneration': flight.generation,
        },
      );
    }
    if (identical(_historyReadInFlight[key], flight)) {
      _historyReadInFlight.remove(key);
    }
    if (!flight.completion.isCompleted) {
      flight.completion.complete();
    }
  }

  @override
  Future<MessageListResponse> getHistoryMessageListV2({
    HistoryMsgGetTypeEnum getType =
        HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
    String? userID,
    String? groupID,
    int lastMsgSeq = -1,
    required int count,
    String? lastMsgID,
    List<int>? messageTypeList,
  }) async {
    bool haveMoreData = true;
    try {
      final res = await _runHistoryInLane(
        key: _historyLaneKey(userID: userID, groupID: groupID),
        requestKey:
            'listV1|${getType.index}|$count|${lastMsgID ?? ''}|$lastMsgSeq|${messageTypeList?.join(',') ?? ''}',
        start: () async {
          if (PlatformUtils().isWeb) {
            final webRes = await WebHistoryLoader.loadWithComplete(
              count: count,
              getType: getType,
              userID: userID,
              groupID: groupID,
              lastMsgID: lastMsgID,
              lastMsgSeq: lastMsgSeq,
              messageTypeList: messageTypeList,
            );
            if (webRes != null) {
              return _HistoryV2Result.web(webRes);
            }
          }
          final sdk = await TencentImSDKPlugin.v2TIMManager
              .getMessageManager()
              .getHistoryMessageList(
                count: count,
                getType: getType,
                userID: userID,
                groupID: groupID,
                lastMsgID: lastMsgID,
                lastMsgSeq: lastMsgSeq,
                messageTypeList: messageTypeList,
              );
          return _HistoryV2Result.sdk(sdk);
        },
      );
      if (res.web != null) {
        final webRes = res.web!;
        return MessageListResponse(
          haveMoreData: !webRes.isFinished,
          data: webRes.messageList,
        );
      }
      final sdkRes = res.sdk!;
      final List<V2TimMessage> responseMessageList = sdkRes.data ?? [];
      if (sdkRes.code != 0) {
        _coreService.callOnCallback(
          TIMCallback(
            type: TIMCallbackType.API_ERROR,
            errorMsg: sdkRes.desc,
            errorCode: sdkRes.code,
          ),
        );
      }
      if (responseMessageList.isEmpty ||
          (!PlatformUtils().isWeb && responseMessageList.length < count) ||
          (PlatformUtils().isWeb &&
              responseMessageList.length < min(count, 20))) {
        haveMoreData = false;
      } else {
        haveMoreData = true;
      }
      return MessageListResponse(
        haveMoreData: haveMoreData,
        data: responseMessageList,
      );
    } catch (e) {
      if (_isSoftWebSdkError(e)) {
        _printSoftWebSdkError('load messages fallback failed on web', e);
        return MessageListResponse(haveMoreData: false, data: const []);
      }
      rethrow;
    }
  }

  @override
  Future<List<V2TimMessage>> getHistoryMessageList({
    HistoryMsgGetTypeEnum getType =
        HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
    String? userID,
    String? groupID,
    int lastMsgSeq = -1,
    required int count,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    List<int>? messageTypeList,
  }) async {
    try {
      final res = await _runHistoryInLane(
        key: _historyLaneKey(userID: userID, groupID: groupID),
        requestKey:
            'list|${getType.index}|$count|${lastMsgID ?? lastMsg?.msgID ?? ''}|$lastMsgSeq|${messageTypeList?.join(',') ?? ''}',
        start: () async {
          if (PlatformUtils().isWeb) {
            final webList = await WebHistoryLoader.loadList(
              count: count,
              getType: getType,
              userID: userID,
              groupID: groupID,
              lastMsgID: lastMsgID,
              lastMsgSeq: lastMsgSeq,
              messageTypeList: messageTypeList,
            );
            if (webList != null) return _HistoryListResult.web(webList);
          }
          final sdk = await TencentImSDKPlugin.v2TIMManager
              .getMessageManager()
              .getHistoryMessageList(
                count: count,
                getType: getType,
                userID: userID,
                groupID: groupID,
                lastMsg: lastMsg,
                lastMsgID: lastMsgID,
                lastMsgSeq: lastMsgSeq,
                messageTypeList: messageTypeList,
              );
          return _HistoryListResult.sdk(sdk);
        },
      );
      if (res.web != null) return res.web!;
      final sdkRes = res.sdk!;
      final reponseMessageList = sdkRes.data ?? [];
      ChatHistoryTrace.log(
        'sdk_get_history',
        conversationID: groupID ?? userID,
        extras: <String, Object?>{
          'api': 'getHistoryMessageList',
          'getType': getType.index,
          'isGroup': groupID != null,
          'reqCount': count,
          'lastMsgID': lastMsgID,
          'lastMsgSeq': lastMsgSeq,
          'code': sdkRes.code,
          'desc': sdkRes.desc,
          'dataLen': reponseMessageList.length,
        },
      );
      if (sdkRes.code != 0) {
        _coreService.callOnCallback(
          TIMCallback(
            type: TIMCallbackType.API_ERROR,
            errorMsg: sdkRes.desc,
            errorCode: sdkRes.code,
          ),
        );
      }
      return reponseMessageList;
    } catch (e) {
      if (_isSoftWebSdkError(e)) {
        _printSoftWebSdkError('load messages fallback failed on web', e);
        return const [];
      }
      rethrow;
    }
  }

  @override
  Future<V2TimMessageListResult?> getHistoryMessageListWithComplete({
    HistoryMsgGetTypeEnum getType =
        HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
    String? userID,
    String? groupID,
    int lastMsgSeq = 0,
    required int count,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    List<int>? messageTypeList,
    List<int>? messageSeqList,
    int? timeBegin,
    int? timePeriod,
  }) async {
    final result = await getHistoryMessageListWithStatus(
      getType: getType,
      userID: userID,
      groupID: groupID,
      lastMsgSeq: lastMsgSeq,
      count: count,
      lastMsgID: lastMsgID,
      lastMsg: lastMsg,
      messageTypeList: messageTypeList,
      messageSeqList: messageSeqList,
      timeBegin: timeBegin,
      timePeriod: timePeriod,
    );
    return result.data;
  }

  @override
  Future<MessageHistorySdkResult> getHistoryMessageListWithStatus({
    HistoryMsgGetTypeEnum getType =
        HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
    String? userID,
    String? groupID,
    int lastMsgSeq = 0,
    required int count,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    List<int>? messageTypeList,
    List<int>? messageSeqList,
    int? timeBegin,
    int? timePeriod,
  }) async {
    try {
      final res = await _runHistoryInLane(
        key: _historyLaneKey(userID: userID, groupID: groupID),
        requestKey:
            'listV2|${getType.index}|$count|${lastMsgID ?? lastMsg?.msgID ?? ''}|$lastMsgSeq|${messageTypeList?.join(',') ?? ''}|${messageSeqList?.join(',') ?? ''}|${timeBegin ?? ''}|${timePeriod ?? ''}',
        start: () async {
          if (PlatformUtils().isWeb) {
            // Web hopping 不支持 timeBegin/timePeriod/messageSeqList；按洞 IM 在上层跳过。
            final webRes = await WebHistoryLoader.loadWithComplete(
              count: count,
              getType: getType,
              userID: userID,
              groupID: groupID,
              lastMsgID: lastMsgID,
              lastMsgSeq: lastMsgSeq,
              messageTypeList: messageTypeList,
            );
            if (webRes != null) return _HistoryCompleteResult.web(webRes);
          }
          final sdk = await TencentImSDKPlugin.v2TIMManager
              .getMessageManager()
              .getHistoryMessageListV2(
                count: count,
                getType: getType,
                userID: userID,
                groupID: groupID,
                lastMsg: lastMsg,
                lastMsgID: lastMsgID,
                lastMsgSeq: lastMsgSeq,
                messageTypeList: messageTypeList,
                messageSeqList: messageSeqList,
                timeBegin: timeBegin,
                timePeriod: timePeriod,
              );
          return _HistoryCompleteResult.sdk(sdk);
        },
      );
      if (res.web != null) {
        return MessageHistorySdkResult(
          code: 0,
          desc: 'OK',
          data: res.web,
        );
      }
      final sdkRes = res.sdk!;
      final responseMessageList = sdkRes.data;
      ChatHistoryTrace.log(
        'sdk_get_history',
        conversationID: groupID ?? userID,
        extras: <String, Object?>{
          'api': 'getHistoryMessageListWithComplete',
          'getType': getType.index,
          'isGroup': groupID != null,
          'reqCount': count,
          'lastMsgID': lastMsgID,
          'lastMsgSeq': lastMsgSeq,
          'code': sdkRes.code,
          'desc': sdkRes.desc,
          'dataLen': responseMessageList?.messageList.length,
          'isFinished': responseMessageList?.isFinished,
        },
      );
      if (sdkRes.code != 0) {
        _coreService.callOnCallback(
          TIMCallback(
            type: TIMCallbackType.API_ERROR,
            errorMsg: sdkRes.desc,
            errorCode: sdkRes.code,
          ),
        );
      }
      return MessageHistorySdkResult(
        code: sdkRes.code,
        desc: sdkRes.desc,
        data: responseMessageList,
      );
    } catch (e) {
      if (_isSoftWebSdkError(e)) {
        _printSoftWebSdkError('load messages fallback failed on web', e);
        return const MessageHistorySdkResult(
          code: -1,
          desc: 'soft web SDK history error',
        );
      }
      rethrow;
    }
  }

  @override
  Future addSimpleMsgListener({
    required V2TimSimpleMsgListener listener,
  }) async {
    return TencentImSDKPlugin.v2TIMManager.addSimpleMsgListener(
      listener: listener,
    );
  }

  @override
  Future<void> removeSimpleMsgListener({V2TimSimpleMsgListener? listener}) {
    return TencentImSDKPlugin.v2TIMManager.removeSimpleMsgListener(
      listener: listener,
    );
  }

  @override
  Future<void> addAdvancedMsgListener({
    required V2TimAdvancedMsgListener listener,
  }) async {
    final added = _advancedListeners.add(listener);
    try {
      await _ensureSdkAdvancedListenerAttached();
    } catch (_) {
      if (added) {
        _advancedListeners.remove(listener);
      }
      rethrow;
    }
  }

  @override
  Future<V2TimValueCallback<V2TimGroupMessageReadMemberList>>
      getGroupMessageReadMemberList({
    required String messageID,
    required GetGroupMessageReadMemberListFilter filter,
    int nextSeq = 0,
    int count = 100,
  }) async {
    if (PlatformUtils().isWeb) {
      return V2TimValueCallback<V2TimGroupMessageReadMemberList>(
        code: 0,
        desc: '',
        data: V2TimGroupMessageReadMemberList(
          nextSeq: 0,
          isFinished: true,
          memberInfoList: const [],
        ),
      );
    }
    final result = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .getGroupMessageReadMemberList(
          messageID: messageID,
          filter: filter,
          nextSeq: nextSeq,
          count: count,
        );
    if (result.code != 0 && !(PlatformUtils().isWeb && result.code == 10007)) {
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: result.desc,
          errorCode: result.code,
        ),
      );
    }
    return result;
  }

  @override
  Future<V2TimValueCallback<List<V2TimMessageReceipt>>> getMessageReadReceipts({
    required List<String> messageIDList,
  }) async {
    final normalizedIDs = messageIDList
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedIDs.isEmpty) {
      return V2TimValueCallback<List<V2TimMessageReceipt>>(
        code: 0,
        desc: '',
        data: const [],
      );
    }
    final result = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .getMessageReadReceipts(messageIDList: normalizedIDs);
    if (result.code != 0) {
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: result.desc,
          errorCode: result.code,
        ),
      );
    }
    return result;
  }

  @override
  Future<V2TimCallback> sendMessageReadReceipts({
    required List<String> messageIDList,
  }) async {
    final normalizedIDs = messageIDList
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedIDs.isEmpty) {
      return V2TimCallback(code: 0, desc: '');
    }
    return _retryMarkMessageAsRead(
      action: () => TencentImSDKPlugin.v2TIMManager
          .getMessageManager()
          .sendMessageReadReceipts(messageIDList: normalizedIDs),
    );
  }

  @override
  Future<V2TimMsgCreateInfoResult?> createTextMessage({
    required String text,
  }) async {
    final res = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .createTextMessage(text: text);
    if (res.code == 0) {
      final messageResult = res.data;
      return messageResult;
    }
    _coreService.callOnCallback(
      TIMCallback(
        type: TIMCallbackType.API_ERROR,
        errorMsg: res.desc,
        errorCode: res.code,
      ),
    );
    return null;
  }

  @override
  Future<V2TimMsgCreateInfoResult?> createCustomMessage({
    required String data,
  }) async {
    final res = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .createCustomMessage(data: data);
    if (res.code == 0) {
      final messageResult = res.data;
      return messageResult;
    }
    _coreService.callOnCallback(
      TIMCallback(
        type: TIMCallbackType.API_ERROR,
        errorMsg: res.desc,
        errorCode: res.code,
      ),
    );
    return null;
  }

  @override
  Future<V2TimMsgCreateInfoResult?> createFaceMessage({
    required int index,
    required String data,
  }) async {
    final res = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .createFaceMessage(index: index, data: data);
    if (res.code == 0) {
      final messageResult = res.data;
      return messageResult;
    }
    _coreService.callOnCallback(
      TIMCallback(
        type: TIMCallbackType.API_ERROR,
        errorMsg: res.desc,
        errorCode: res.code,
      ),
    );
    return null;
  }

  @override
  Future<V2TimValueCallback<V2TimMessage>> reSendMessage({
    required String msgID,
    bool? onlineUserOnly,
  }) async {
    final res = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .reSendMessage(msgID: msgID, onlineUserOnly: onlineUserOnly ?? false);
    if (res.code != 0) {
      String recommendText = ErrorMessageConverter.getErrorMessage(
        res.code,
        res.desc,
      );
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: res.desc,
          errorCode: res.code,
          infoRecommendText: recommendText,
        ),
      );
    }
    return res;
  }

  @override
  Future<V2TimMsgCreateInfoResult?> createTextAtMessage({
    required String text,
    required List<String> atUserList,
  }) async {
    final res = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .createTextAtMessage(text: text, atUserList: atUserList);
    if (res.code == 0) {
      final messageResult = res.data;
      return messageResult;
    }
    _coreService.callOnCallback(
      TIMCallback(
        type: TIMCallbackType.API_ERROR,
        errorMsg: res.desc,
        errorCode: res.code,
      ),
    );
    return null;
  }

  @override
  Future<V2TimMsgCreateInfoResult?> createImageMessage({
    String? imageName,
    String? imagePath,
    dynamic inputElement,
  }) async {
    final res = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .createImageMessage(
          imageName: imageName,
          imagePath: imagePath ?? "",
          inputElement: inputElement,
        );
    if (res.code == 0) {
      return res.data;
    }
    _coreService.callOnCallback(
      TIMCallback(
        type: TIMCallbackType.API_ERROR,
        errorMsg: res.desc,
        errorCode: res.code,
      ),
    );
    return null;
  }

  @override
  Future<V2TimMsgCreateInfoResult?> createSoundMessage({
    required String soundPath,
    required int duration,
  }) async {
    final res = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .createSoundMessage(soundPath: soundPath, duration: duration);
    if (res.code == 0) {
      return res.data;
    }
    _coreService.callOnCallback(
      TIMCallback(
        type: TIMCallbackType.API_ERROR,
        errorMsg: res.desc,
        errorCode: res.code,
      ),
    );
    return null;
  }

  @override
  void sendTypingStatus({required String receiver, required bool isTyping}) {
    final peer = ChatIdFormat.rawUserUid(receiver);
    final identity = SessionIdentityService.instance.capture();
    if (peer.isEmpty || identity.ownerUserId.isEmpty) return;

    _typingStatusQueue.runLatest(
      sessionKey: '${identity.ownerUserId}|${identity.generation}',
      receiver: peer,
      action: (isFresh) async {
        bool canSend() =>
            isFresh() && SessionIdentityService.instance.isCurrent(identity);
        if (!canSend()) return;
        final manager = TencentImSDKPlugin.v2TIMManager.getMessageManager();
        final created = await manager.createCustomMessage(
          data: jsonEncode({
            'businessID': 'user_typing_status',
            'typingStatus': isTyping ? 1 : 0,
            'userAction': 14,
            'version': 0,
            'actionParam': isTyping
                ? 'EIMAMSG_InputStatus_Ing'
                : 'EIMAMSG_InputStatus_End',
          }),
        );
        final id = created.data?.id;
        // Creation may be delayed, superseded or cross an account boundary.
        if (!canSend() || created.code != 0 || id == null || id.isEmpty) return;
        await manager.sendMessage(
          id: id,
          receiver: peer,
          groupID: '',
          onlineUserOnly: true,
          isExcludedFromUnreadCount: true,
          needReadReceipt: false,
        );
      },
    );
  }

  @override
  Future<V2TimValueCallback<V2TimMessage>> sendMessage({
    required String id, // 自己创建的ID
    required String receiver,
    required String groupID,
    MessagePriorityEnum priority = MessagePriorityEnum.V2TIM_PRIORITY_NORMAL,
    bool onlineUserOnly = false,
    bool isExcludedFromUnreadCount = false,
    bool needReadReceipt = false,
    OfflinePushInfo? offlinePushInfo,
    String? cloudCustomData,
    String? localCustomData,
    bool isExcludedFromContentModeration = false,
    void Function(String syncMsgID)? onSyncMsgID,
  }) async {
    final sendIdentity = SessionIdentityService.instance.capture();
    if (sendIdentity.ownerUserId.isEmpty) {
      return V2TimValueCallback<V2TimMessage>(
        code: -1,
        desc: 'send blocked: account identity unavailable',
      );
    }
    final toOfficialAccount =
        groupID.isEmpty && _isOfficialAccountUserId(receiver);
    if (toOfficialAccount) {
      await _ensureOfficialAccountSubscribed(receiver);
      needReadReceipt = false;
    }
    // 社群（@TGS#_… / @TGS#_@TGS#…）不支持已读回执；硬关避免 6017 导致发送失败。
    if (needReadReceipt && _looksLikeCommunityGroupId(groupID)) {
      needReadReceipt = false;
    }
    final rawConvKey = OutgoingMessageSendQueue.conversationKey(
      receiver: receiver,
      groupID: groupID,
    );
    final convKey = '${sendIdentity.ownerUserId}|'
        '${sendIdentity.generation}|$rawConvKey';
    final perf = MediaSendPerf.lookup(id);
    final uploadQueued = Stopwatch()..start();
    Future<V2TimValueCallback<V2TimMessage>> dispatch() {
      perf?.record('uploadQueueWaitMs', uploadQueued.elapsedMilliseconds);
      if (!SessionIdentityService.instance.isCurrent(sendIdentity)) {
        return Future<V2TimValueCallback<V2TimMessage>>.value(
          V2TimValueCallback<V2TimMessage>(
            code: -1,
            desc: 'send blocked: stale account generation',
          ),
        );
      }
      Future<V2TimValueCallback<V2TimMessage>> send() => _sendMessageNow(
        id: id,
        receiver: receiver,
        groupID: groupID,
        priority: priority,
        onlineUserOnly: onlineUserOnly,
        offlinePushInfo: offlinePushInfo,
        needReadReceipt: needReadReceipt,
        localCustomData: localCustomData,
        cloudCustomData: cloudCustomData,
        isExcludedFromContentModeration: isExcludedFromContentModeration,
        isExcludedFromUnreadCount: isExcludedFromUnreadCount,
        toOfficialAccount: toOfficialAccount,
        onSyncMsgID: onSyncMsgID,
      );
      return perf == null ? send() : perf.measure('sdkUploadAndSend', send);
    }

    // Only locally selected media with a valid display order may overlap.
    // Text, single sends and malformed metadata keep the serial path.
    String? batchId;
    String? mediaKind;
    try {
      final data = jsonDecode(localCustomData ?? '');
      if (data is Map && const ['image', 'video', 'file'].contains(data['mediaSendKind'])) {
        mediaKind = data['mediaSendKind'] as String;
      }
      if (data is Map &&
          data[kChatMediaBatchIdKey] is String &&
          data[kChatMediaBatchIndexKey] is int &&
          (data[kChatMediaBatchIndexKey] as int) >= 0) {
        final id = (data[kChatMediaBatchIdKey] as String).trim();
        if (id.isNotEmpty) batchId = id;
      }
    } catch (_) {
      // Non-JSON local metadata is valid for ordinary SDK messages.
    }
    final queue = OutgoingMessageSendQueue.instance;
    if (mediaKind != null) return queue.runMedia(mediaKind, dispatch);
    return batchId == null
        ? queue.runSerial(convKey, dispatch)
        : queue.runMediaBatch(convKey, batchId, dispatch);
  }

  Future<V2TimValueCallback<V2TimMessage>> _sendMessageNow({
    required String id,
    required String receiver,
    required String groupID,
    required MessagePriorityEnum priority,
    required bool onlineUserOnly,
    required bool needReadReceipt,
    required bool isExcludedFromUnreadCount,
    required bool isExcludedFromContentModeration,
    required bool toOfficialAccount,
    OfflinePushInfo? offlinePushInfo,
    String? cloudCustomData,
    String? localCustomData,
    void Function(String syncMsgID)? onSyncMsgID,
  }) async {
    debugPrint(
      '[IM_SEND] target=${groupID.isNotEmpty ? 'group' : 'c2c'} '
      'onlineOnly=$onlineUserOnly',
    );
    final result =
        await TencentImSDKPlugin.v2TIMManager.getMessageManager().sendMessage(
              id: id,
              receiver: receiver,
              groupID: groupID,
              priority: priority,
              onlineUserOnly: onlineUserOnly,
              offlinePushInfo: offlinePushInfo,
              needReadReceipt: needReadReceipt,
              localCustomData: localCustomData,
              cloudCustomData: cloudCustomData,
              isExcludedFromContentModeration: isExcludedFromContentModeration,
              isExcludedFromUnreadCount: isExcludedFromUnreadCount,
              onSyncMsgID: (syncMsgID) {
                if (syncMsgID.trim().isEmpty) {
                  return;
                }
                onSyncMsgID?.call(syncMsgID);
              },
            );
    if (result.code != 0) {
      debugPrint(
        '[IM_SEND_FAIL] target=${groupID.isNotEmpty ? 'group' : 'c2c'} '
        'code=${result.code}',
      );
      String recommendText = ErrorMessageConverter.getErrorMessage(
        result.code,
        result.desc,
      );
      if (toOfficialAccount) {
        final officialText = officialAccountSendErrorText(
          result.code,
          result.desc,
        );
        if (officialText.isNotEmpty) {
          recommendText = officialText;
        }
      }
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: result.desc,
          errorCode: result.code,
          infoRecommendText: recommendText,
        ),
      );
    } else {
      debugPrint(
        '[IM_SEND_DONE] target=${groupID.isNotEmpty ? 'group' : 'c2c'} '
        'status=${result.data?.status} code=${result.code}',
      );
    }
    return result;
  }

  @override
  Future<V2TimCallback> deleteMessageFromLocalStorage({
    required String msgID,
    Object? webMessageInstance,
  }) async {
    V2TimCallback result;
    if (kIsWeb) {
      result = await TencentImSDKPlugin.v2TIMManager
          .getMessageManager()
          .deleteMessages(
        msgIDs: [],
        webMessageInstanceList: [webMessageInstance],
      );
    } else {
      result = await TencentImSDKPlugin.v2TIMManager
          .getMessageManager()
          .deleteMessageFromLocalStorage(msgID: msgID);
    }

    if (result.code != 0) {
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: result.desc,
          errorCode: result.code,
        ),
      );
    }
    return result;
  }

  @override
  Future<V2TimCallback> revokeMessage({
    required String msgID,
    Object? webMessageInstance,
    V2TimMessage? message,
  }) async {
    final result = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .revokeMessage(
          message: message,
          msgID: msgID,
          webMessageInstatnce: webMessageInstance,
        );
    if (result.code != 0) {
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: result.desc,
          errorCode: result.code,
        ),
      );
    }
    return result;
  }

  @override
  Future<V2TimCallback> clearC2CHistoryMessage({required String userID}) async {
    final result = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .clearC2CHistoryMessage(userID: userID);
    if (result.code != 0) {
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: result.desc,
          errorCode: result.code,
        ),
      );
    }
    return result;
  }

  @override
  Future<V2TimCallback> clearGroupHistoryMessage({
    required String groupID,
  }) async {
    final result = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .clearGroupHistoryMessage(groupID: groupID);
    if (result.code != 0) {
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: result.desc,
          errorCode: result.code,
        ),
      );
    }
    return result;
  }

  bool _isOfficialAccountUserId(String? userId) {
    return userId != null && userId.startsWith('@TOA#_');
  }

  /// 社群 ID：`@TGS#_…`（含默认分配 `@TGS#_@TGS#…`）。公开群 `@TGS#{数字}` 不含。
  bool _looksLikeCommunityGroupId(String? input) {
    var id = input?.trim() ?? '';
    if (id.isEmpty) {
      return false;
    }
    if (id.length > 6 && id.toLowerCase().startsWith('group_')) {
      id = id.substring(6);
    }
    final upper = id.toUpperCase();
    return upper.startsWith('@TGS#_') || upper.startsWith('TGS#_');
  }

  bool _isOfficialAccountSubscribeOk(int code, String? desc) {
    if (code == 0) {
      return true;
    }
    final lower = (desc ?? '').toLowerCase();
    if (lower.contains('already') &&
        (lower.contains('subscrib') || lower.contains('follow'))) {
      return true;
    }
    final raw = desc ?? '';
    if (raw.contains('已经') && raw.contains('订阅')) {
      return true;
    }
    if (raw.contains('重复') && raw.contains('订阅')) {
      return true;
    }
    return false;
  }

  Future<void> _ensureOfficialAccountSubscribed(String receiver) async {
    if (!_isOfficialAccountUserId(receiver)) {
      return;
    }
    final friendshipManager =
        TencentImSDKPlugin.v2TIMManager.getFriendshipManager();
    final subscribeRes = await friendshipManager.subscribeOfficialAccount(
      officialAccountID: receiver,
    );
    if (!_isOfficialAccountSubscribeOk(subscribeRes.code, subscribeRes.desc)) {
      debugPrint(
        'subscribeOfficialAccount before send failed: '
        '${subscribeRes.code} ${subscribeRes.desc}',
      );
    }
  }

  static String officialAccountSendErrorText(int code, String? desc) {
    if (code != 131006) {
      return '';
    }
    final lower = (desc ?? '').toLowerCase();
    if (lower.contains('not open') &&
        (lower.contains('official') || lower.contains('account'))) {
      return TIM_t("公众号未开通或未发布，暂无法发送消息，请联系管理员在 IM 控制台启用运营公众号");
    }
    return '';
  }

  bool _isOfficialAccountC2cReadReportError(
    V2TimCallback result,
    String userID,
  ) {
    return _isOfficialAccountUserId(userID) &&
        result.code == 131006 &&
        result.desc.toLowerCase().contains('official account');
  }

  Future<V2TimCallback> _retryMarkMessageAsRead({
    required Future<V2TimCallback> Function() action,
    int retries = 3,
    String? c2cUserID,
    bool Function(V2TimCallback result)? shouldRetry,
  }) async {
    V2TimCallback result;
    int attempts = 0;
    do {
      try {
        result = await action();
      } catch (e) {
        if (PlatformUtils().isWeb) {
          result = V2TimCallback(code: -1, desc: e.toString());
        } else {
          rethrow;
        }
      }
      if (result.code == 0) {
        return result;
      }
      if (c2cUserID != null &&
          _isOfficialAccountC2cReadReportError(result, c2cUserID)) {
        return V2TimCallback(code: 0, desc: '');
      }
      if (shouldRetry != null && !shouldRetry(result)) {
        break;
      }
      attempts++;
      await Future.delayed(const Duration(milliseconds: 500));
    } while (attempts < retries);

    if (c2cUserID != null &&
        _isOfficialAccountC2cReadReportError(result, c2cUserID)) {
      return V2TimCallback(code: 0, desc: '');
    }

    _coreService.callOnCallback(
      TIMCallback(
        type: TIMCallbackType.API_ERROR,
        errorMsg: result.desc,
        errorCode: result.code,
      ),
    );

    return result;
  }

  @override
  Future<V2TimCallback> markC2CMessageAsRead({required String userID}) {
    return _retryMarkMessageAsRead(
      c2cUserID: userID,
      action: () {
        return TencentImSDKPlugin.v2TIMManager
            .getConversationManager()
            .cleanConversationUnreadMessageCount(
              conversationID:
                  "${TUIConversationViewModel.conversationC2CPrefix}$userID",
              cleanTimestamp: 0,
              cleanSequence: 0,
            );
      },
    );
  }

  @override
  Future<V2TimCallback> markGroupMessageAsRead({required String groupID}) {
    final id = groupID.trim().startsWith(
              TUIConversationViewModel.conversationGroupPrefix,
            )
        ? groupID.trim().substring(
              TUIConversationViewModel.conversationGroupPrefix.length,
            )
        : groupID.trim();
    if (id.isEmpty) {
      return Future.value(V2TimCallback(code: -1, desc: 'groupID is required'));
    }
    final active = _groupReadInFlight[id];
    if (active != null) {
      // A message may have arrived after the active SDK call started. Join the
      // call now and retain one trailing clean instead of issuing concurrently.
      _groupReadNeedsTrailing.add(id);
      return active;
    }
    final deferred = _groupReadDeferred[id];
    if (deferred != null) {
      return deferred;
    }
    final now = DateTime.now();
    final blockedUntil = _groupReadBlockedUntil[id];
    if (blockedUntil != null && now.isBefore(blockedUntil)) {
      return _deferGroupRead(id, blockedUntil.difference(now));
    }
    final lastSuccess = _groupReadLastSuccess[id];
    if (lastSuccess != null) {
      final nextAllowed = lastSuccess.add(_groupReadMinInterval);
      if (now.isBefore(nextAllowed)) {
        return _deferGroupRead(id, nextAllowed.difference(now));
      }
    }
    return _startGroupRead(id);
  }

  Future<V2TimCallback> _deferGroupRead(String groupID, Duration delay) {
    final active = _groupReadDeferred[groupID];
    if (active != null) {
      return active;
    }
    late final Future<V2TimCallback> tracked;
    tracked = Future<void>.delayed(delay).then((_) {
      if (identical(_groupReadDeferred[groupID], tracked)) {
        _groupReadDeferred.remove(groupID);
      }
      return _startGroupRead(groupID);
    }).whenComplete(() {
      if (identical(_groupReadDeferred[groupID], tracked)) {
        _groupReadDeferred.remove(groupID);
      }
    });
    _groupReadDeferred[groupID] = tracked;
    return tracked;
  }

  Future<V2TimCallback> _startGroupRead(String groupID) {
    final active = _groupReadInFlight[groupID];
    if (active != null) {
      _groupReadNeedsTrailing.add(groupID);
      return active;
    }
    late final Future<V2TimCallback> tracked;
    tracked = _retryMarkMessageAsRead(
      shouldRetry: (result) => !_groupReadFrequencyCodes.contains(result.code),
      action: () {
        return TencentImSDKPlugin.v2TIMManager
            .getConversationManager()
            .cleanConversationUnreadMessageCount(
              conversationID:
                  "${TUIConversationViewModel.conversationGroupPrefix}$groupID",
              cleanTimestamp: 0,
              cleanSequence: 0,
            );
      },
    ).then((result) {
      final now = DateTime.now();
      if (result.code == 0) {
        _groupReadLastSuccess[groupID] = now;
        _groupReadBlockedUntil.remove(groupID);
      } else if (_groupReadFrequencyCodes.contains(result.code)) {
        _groupReadBlockedUntil[groupID] = now.add(
          _groupReadFrequencyBackoff,
        );
      }
      return result;
    }).whenComplete(() {
      if (identical(_groupReadInFlight[groupID], tracked)) {
        _groupReadInFlight.remove(groupID);
      }
      if (_groupReadNeedsTrailing.remove(groupID)) {
        final now = DateTime.now();
        final blockedUntil = _groupReadBlockedUntil[groupID];
        final lastSuccess = _groupReadLastSuccess[groupID];
        var nextAllowed = now;
        if (blockedUntil != null && blockedUntil.isAfter(nextAllowed)) {
          nextAllowed = blockedUntil;
        }
        if (lastSuccess != null) {
          final afterSuccess = lastSuccess.add(_groupReadMinInterval);
          if (afterSuccess.isAfter(nextAllowed)) {
            nextAllowed = afterSuccess;
          }
        }
        unawaited(
          _deferGroupRead(groupID, nextAllowed.difference(now)),
        );
      }
    });
    _groupReadInFlight[groupID] = tracked;
    return tracked;
  }

  @override
  Future<void> removeAdvancedMsgListener({
    V2TimAdvancedMsgListener? listener,
  }) async {
    if (listener == null) {
      _advancedListeners.clear();
    } else {
      _advancedListeners.remove(listener);
    }
    if (_advancedListeners.isEmpty) {
      await _detachSdkAdvancedListener();
    }
  }

  Future<void> _ensureSdkAdvancedListenerAttached() async {
    final inFlight = _advancedListenerAttachInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    if (_sdkAdvancedListener != null || _advancedListeners.isEmpty) {
      return;
    }
    final listener = _createSdkAdvancedListener();
    final task = () async {
      try {
        await TencentImSDKPlugin.v2TIMManager
            .getMessageManager()
            .addAdvancedMsgListener(listener: listener);
        if (_advancedListeners.isNotEmpty) {
          _sdkAdvancedListener = listener;
        } else {
          await TencentImSDKPlugin.v2TIMManager
              .getMessageManager()
              .removeAdvancedMsgListener(listener: listener);
        }
      } catch (e) {
        if (_isSoftWebSdkError(e)) {
          _printSoftWebSdkError('message listener ignored on web', e);
          return;
        }
        rethrow;
      }
    }();
    _advancedListenerAttachInFlight = task;
    try {
      await task;
    } finally {
      if (identical(_advancedListenerAttachInFlight, task)) {
        _advancedListenerAttachInFlight = null;
      }
    }
  }

  Future<void> _detachSdkAdvancedListener() async {
    final inFlight = _advancedListenerAttachInFlight;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {}
    }
    final listener = _sdkAdvancedListener;
    _sdkAdvancedListener = null;
    if (listener == null) return;
    try {
      await TencentImSDKPlugin.v2TIMManager
          .getMessageManager()
          .removeAdvancedMsgListener(listener: listener);
    } catch (e) {
      if (!_isSoftWebSdkError(e)) rethrow;
    }
  }

  V2TimAdvancedMsgListener _createSdkAdvancedListener() {
    return V2TimAdvancedMsgListener(
      onRecvNewMessage: (message) {
        _forEachAdvanced((listener) => listener.onRecvNewMessage(message));
      },
      onRecvMessageModified: (message) {
        _forEachAdvanced((listener) => listener.onRecvMessageModified(message));
      },
      onSendMessageProgress: (message, progress) {
        _forEachAdvanced(
          (listener) => listener.onSendMessageProgress(message, progress),
        );
      },
      onRecvC2CReadReceipt: (receipts) {
        _forEachAdvanced((listener) => listener.onRecvC2CReadReceipt(receipts));
      },
      onRecvMessageRevoked: (msgID) {
        _forEachAdvanced((listener) => listener.onRecvMessageRevoked(msgID));
      },
      onRecvMessageReadReceipts: (receipts) {
        _forEachAdvanced(
          (listener) => listener.onRecvMessageReadReceipts(receipts),
        );
      },
      onRecvMessageExtensionsChanged: (msgID, extensions) {
        _forEachAdvanced(
          (listener) =>
              listener.onRecvMessageExtensionsChanged(msgID, extensions),
        );
      },
      onRecvMessageExtensionsDeleted: (msgID, extensionKeys) {
        _forEachAdvanced(
          (listener) =>
              listener.onRecvMessageExtensionsDeleted(msgID, extensionKeys),
        );
      },
      onMessageDownloadProgressCallback: (progress) {
        _forEachAdvanced(
          (listener) => listener.onMessageDownloadProgressCallback(progress),
        );
      },
      onRecvMessageReactionsChanged: (changeInfos) {
        _forEachAdvanced(
          (listener) => listener.onRecvMessageReactionsChanged(changeInfos),
        );
      },
      onRecvMessageRevokedWithInfo: (msgID, operateUser, reason) {
        _forEachAdvanced(
          (listener) =>
              listener.onRecvMessageRevokedWithInfo(msgID, operateUser, reason),
        );
      },
      onGroupMessagePinned: (groupID, message, isPinned, operateUser) {
        _forEachAdvanced(
          (listener) => listener.onGroupMessagePinned(
            groupID,
            message,
            isPinned,
            operateUser,
          ),
        );
      },
    );
  }

  void _forEachAdvanced(
    void Function(V2TimAdvancedMsgListener listener) callback,
  ) {
    final listeners = List<V2TimAdvancedMsgListener>.of(_advancedListeners);
    for (final listener in listeners) {
      try {
        callback(listener);
      } catch (_) {
        // One compatibility subscriber must not block the SDK event fanout.
      }
    }
  }

  @override
  Future<List<V2TimMessage>?> downloadMergerMessage({
    required String msgID,
  }) async {
    final res = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .downloadMergerMessage(msgID: msgID);
    if (res.code == 0) {
      return res.data;
    }
    _coreService.callOnCallback(
      TIMCallback(
        type: TIMCallbackType.API_ERROR,
        errorMsg: res.desc,
        errorCode: res.code,
      ),
    );
    return null;
  }

  @override
  Future<V2TimMsgCreateInfoResult?> createForwardMessage({
    String? msgID,
    V2TimMessage? message,
    String? webMessageInstance,
  }) async {
    final res = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .createForwardMessage(
          message: message,
          msgID: msgID,
          webMessageInstance: webMessageInstance,
        );
    if (res.code == 0) {
      return res.data;
    }
    _coreService.callOnCallback(
      TIMCallback(
        type: TIMCallbackType.API_ERROR,
        errorMsg: res.desc,
        errorCode: res.code,
        infoRecommendText: TIM_t('该消息不支持单条转发'),
      ),
    );
    return null;
  }

  @override
  Future<V2TimMsgCreateInfoResult?> createMergerMessage({
    required List<String> msgIDList,
    required String title,
    required List<String> abstractList,
    required String compatibleText,
  }) async {
    final res = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .createMergerMessage(
          msgIDList: msgIDList,
          title: title,
          abstractList: abstractList,
          compatibleText: compatibleText,
        );
    if (res.code == 0) {
      return res.data;
    }
    _coreService.callOnCallback(
      TIMCallback(
        type: TIMCallbackType.API_ERROR,
        errorMsg: res.desc,
        errorCode: res.code,
      ),
    );
    return null;
  }

  @override
  Future<V2TimCallback> deleteMessages({
    required List<String> msgIDs,
    List<dynamic>? webMessageInstanceList,
  }) async {
    final result = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .deleteMessages(
          msgIDs: msgIDs,
          webMessageInstanceList: webMessageInstanceList,
        );
    if (result.code != 0) {
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: result.desc,
          errorCode: result.code,
        ),
      );
    }
    return result;
  }

  @override
  Future<V2TimMsgCreateInfoResult?> createVideoMessage({
    String? videoPath,
    String? type,
    int? duration,
    String? snapshotPath,
    dynamic inputElement,
  }) async {
    final res = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .createVideoMessage(
          videoFilePath: videoPath ?? "",
          type: type ?? "",
          duration: duration ?? 1,
          snapshotPath: snapshotPath ?? "",
          inputElement: inputElement,
        );
    if (res.code == 0) {
      return res.data;
    }
    _coreService.callOnCallback(
      TIMCallback(
        type: TIMCallbackType.API_ERROR,
        errorMsg: res.desc,
        errorCode: res.code,
      ),
    );
    return null;
  }

  @override
  Future<V2TimValueCallback<V2TimMessage>> sendReplyMessage({
    required String id, // 自己创建的ID
    required String receiver,
    required String groupID,
    OfflinePushInfo? offlinePushInfo,
    bool needReadReceipt = false,
    required V2TimMessage replyMessage, // 被回复的消息
  }) async {
    final result = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .sendReplyMessage(
          id: id,
          receiver: receiver,
          offlinePushInfo: offlinePushInfo,
          groupID: groupID,
          needReadReceipt: needReadReceipt,
          replyMessage: replyMessage,
        );
    if (result.code != 0) {
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: result.desc,
          errorCode: result.code,
        ),
      );
    }
    return result;
  }

  @override
  Future<V2TimMsgCreateInfoResult?> createFileMessage({
    String? filePath,
    required String fileName,
    dynamic inputElement,
  }) async {
    final res = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .createFileMessage(
          filePath: filePath ?? "",
          fileName: fileName,
          inputElement: inputElement,
        );
    if (res.code == 0) {
      return res.data;
    }
    _coreService.callOnCallback(
      TIMCallback(
        type: TIMCallbackType.API_ERROR,
        errorMsg: res.desc,
        errorCode: res.code,
      ),
    );
    return null;
  }

  @override
  Future<V2TimMsgCreateInfoResult?> createLocationMessage({
    required String desc,
    required double longitude,
    required double latitude,
  }) async {
    final res = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .createLocationMessage(
          desc: desc,
          longitude: longitude,
          latitude: latitude,
        );
    if (res.code == 0) {
      return res.data;
    }
    _coreService.callOnCallback(
      TIMCallback(
        type: TIMCallbackType.API_ERROR,
        errorMsg: res.desc,
        errorCode: res.code,
      ),
    );
    return null;
  }

  @override
  Future<V2TimValueCallback<V2TimMessageSearchResult>> searchLocalMessages({
    required V2TimMessageSearchParam searchParam,
  }) async {
    final result = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .searchLocalMessages(searchParam: searchParam);
    if (result.code != 0) {
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: result.desc,
          errorCode: result.code,
        ),
      );
    }
    return result;
  }

  @override
  Future<V2TimValueCallback<V2TimMessageSearchResult>> searchCloudMessages({
    required V2TimMessageSearchParam searchParam,
  }) async {
    final result = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .searchCloudMessages(searchParam: searchParam);
    if (result.code != 0) {
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: result.desc,
          errorCode: result.code,
        ),
      );
    }
    return result;
  }

  @override
  Future<List<V2TimMessage>?> findMessages({
    required List<String> messageIDList,
  }) async {
    final res = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .findMessages(messageIDList: messageIDList);
    if (res.code == 0) {
      return res.data;
    }
    _coreService.callOnCallback(
      TIMCallback(
        type: TIMCallbackType.API_ERROR,
        errorMsg: res.desc,
        errorCode: res.code,
      ),
    );
    return null;
  }

  @override
  Future<V2TimCallback> setLocalCustomInt({
    required String msgID,
    required int localCustomInt,
  }) async {
    final result = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .setLocalCustomInt(msgID: msgID, localCustomInt: localCustomInt);
    if (result.code != 0) {
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: result.desc,
          errorCode: result.code,
        ),
      );
    }
    return result;
  }

  @override
  Future<V2TimCallback> setC2CReceiveMessageOpt({
    required List<String> userIDList,
    required ReceiveMsgOptEnum opt,
  }) async {
    final result = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .setC2CReceiveMessageOpt(userIDList: userIDList, opt: opt);
    if (result.code != 0) {
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: result.desc,
          errorCode: result.code,
        ),
      );
    } else {
      _reportConversationMuteSynced(
        chatType: 'c2c',
        peerIds: userIDList,
        opt: opt,
      );
    }
    return result;
  }

  @override
  Future<V2TimCallback> setGroupReceiveMessageOpt({
    required String groupID,
    required ReceiveMsgOptEnum opt,
  }) async {
    final result = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .setGroupReceiveMessageOpt(groupID: groupID, opt: opt);
    if (result.code != 0) {
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: result.desc,
          errorCode: result.code,
        ),
      );
    } else {
      _reportConversationMuteSynced(
        chatType: 'group',
        peerIds: [groupID],
        opt: opt,
      );
    }
    return result;
  }

  void _reportConversationMuteSynced({
    required String chatType,
    required List<String> peerIds,
    required ReceiveMsgOptEnum opt,
  }) {
    final reporter = ConversationNotifyBridge.onMuteSynced;
    if (reporter == null) {
      return;
    }
    final muted = opt != ReceiveMsgOptEnum.V2TIM_RECEIVE_MESSAGE;
    for (final rawPeerId in peerIds) {
      final peerId = rawPeerId.trim();
      if (peerId.isEmpty) {
        continue;
      }
      unawaited(reporter(chatType: chatType, peerId: peerId, muted: muted));
    }
  }

  @override
  Future<V2TimValueCallback<V2TimMessageChangeInfo>> modifyMessage({
    required V2TimMessage message,
  }) async {
    final result = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .modifyMessage(message: message);
    if (result.code != 0) {
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: result.desc,
          errorCode: result.code,
        ),
      );
    }
    return result;
  }

  @override
  Future<V2TimCallback> setLocalCustomData({
    required String msgID,
    required String localCustomData,
  }) async {
    final result = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .setLocalCustomData(msgID: msgID, localCustomData: localCustomData);
    if (result.code != 0) {
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: result.desc,
          errorCode: result.code,
        ),
      );
    }
    return result;
  }

  bool _isBenignMessageResourceError(String? desc) {
    final normalized = (desc ?? '').trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    return normalized.contains('missing necessary download info') ||
        normalized.contains('message not found') ||
        normalized.contains('invalid msgid') ||
        normalized.contains('invalid message id') ||
        normalized.contains('msgid is empty') ||
        normalized.contains('message is sending') ||
        normalized.contains('file not exist') ||
        normalized.contains('file not found');
  }

  @override
  Future<V2TimValueCallback<V2TimMessageOnlineUrl>> getMessageOnlineUrl({
    required String msgID,
    bool reportError = true,
  }) async {
    final result = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .getMessageOnlineUrl(msgID: msgID);

    if (result.code != 0 &&
        reportError &&
        !_isBenignMessageResourceError(result.desc)) {
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: result.desc,
          errorCode: result.code,
        ),
      );
    }
    return result;
  }

  @override
  Future<V2TimCallback> downloadMessage({
    required String msgID,
    required int messageType,
    required int imageType,
    required bool isSnapshot,
    V2TimMessage? message,
    void Function(V2TimMessage message)? onDownloadFinished,
    bool reportError = true,
  }) async {
    final resolvedMsgID =
        msgID.trim().isNotEmpty ? msgID.trim() : (message?.msgID?.trim() ?? '');
    final downloadKey =
        '$resolvedMsgID:$messageType:$imageType:${isSnapshot ? 1 : 0}';
    void Function(V2TimMessage) listenerFor(V2TimMessage? target) {
      return (downloaded) {
        final resolved = target ?? downloaded;
        if (!identical(resolved, downloaded)) {
          resolved.imageElem = downloaded.imageElem;
          resolved.videoElem = downloaded.videoElem;
          resolved.soundElem = downloaded.soundElem;
          resolved.fileElem = downloaded.fileElem;
        }
        onDownloadFinished?.call(resolved);
      };
    }

    final existing = _downloadInFlight[downloadKey];
    if (existing != null) {
      final listener = listenerFor(message);
      if (existing.delivered && existing.sourceMessage != null) {
        listener(existing.sourceMessage!);
      } else {
        existing.listeners.add(listener);
      }
      return existing.future;
    }

    final flight = _MessageDownloadFlight(message);
    flight.listeners.add(listenerFor(message));
    late final Future<V2TimCallback> tracked;
    tracked = (() async {
      final isThumbnail =
          messageType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE &&
              imageType == 1 &&
              !isSnapshot;
      final acquired = !isThumbnail || await _acquireThumbnailDownloadSlot();
      if (!acquired) {
        return V2TimCallback(
          code: -1,
          desc: 'thumbnail download deferred by thermal budget',
        );
      }
      try {
        return await TencentImSDKPlugin.v2TIMManager
            .getMessageManager()
            .downloadMessage(
              message: message,
              msgID: resolvedMsgID,
              messageType: messageType,
              imageType: imageType,
              isSnapshot: isSnapshot,
              onDownloadFinished: flight.deliver,
            );
      } finally {
        if (acquired && isThumbnail) {
          _releaseThumbnailDownloadSlot();
        }
      }
    })()
        .then((result) {
      if (result.code == 0 &&
          !flight.delivered &&
          flight.sourceMessage != null) {
        flight.deliver(flight.sourceMessage!);
      }
      return result;
    }).whenComplete(() {
      if (identical(_downloadInFlight[downloadKey]?.future, tracked)) {
        _downloadInFlight.remove(downloadKey);
      }
    });
    flight.future = tracked;
    _downloadInFlight[downloadKey] = flight;
    final result = await tracked;
    if (result.code != 0 &&
        reportError &&
        !_isBenignMessageResourceError(result.desc)) {
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: result.desc,
          errorCode: result.code,
        ),
      );
    }
    return result;
  }

  @override
  Future<String> translateText(String text, String target) async {
    final result = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .translateText(texts: [text], targetLanguage: target);
    if (result.code != 0) {
      _coreService.callOnCallback(
        TIMCallback(
          type: TIMCallbackType.API_ERROR,
          errorMsg: result.desc,
          errorCode: result.code,
        ),
      );
    }
    return result.data?[text] ?? "";
  }
}
