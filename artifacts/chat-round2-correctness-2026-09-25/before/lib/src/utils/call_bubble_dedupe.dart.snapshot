import 'dart:async';
import 'dart:convert';
import 'package:tencent_cloud_chat_demo/src/services/call_result_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_result_repository.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/regexp_probe.dart';
import 'package:tencent_cloud_chat_demo/src/utils/call_bubble_dedupe_key.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/calling_message/calling_message_data_provider.dart';

/// 单条通话消息的轻量解析结果：同一次 normalize / dedupe 内只构建一次，避免反复 jsonDecode。
class _CallMsgMeta {
  const _CallMsgMeta({
    required this.isLocalBubble,
    required this.looksLikeCall,
    required this.isCallingSignal,
    required this.shouldDisplayInHistory,
    required this.stableKey,
    required this.nearKey,
    required this.durationSec,
    required this.lifecycleRank,
    required this.roomId,
    required this.conversationId,
    required this.inviteId,
  });

  final bool isLocalBubble;
  final bool looksLikeCall;
  final bool isCallingSignal;
  final bool shouldDisplayInHistory;
  final String stableKey;
  final String nearKey;
  final int durationSec;
  final int lifecycleRank;
  final String roomId;
  final String conversationId;
  final String inviteId;

  bool get isHistoryCandidate =>
      (isLocalBubble || isCallingSignal) && shouldDisplayInHistory;

  static const empty = _CallMsgMeta(
    isLocalBubble: false,
    looksLikeCall: false,
    isCallingSignal: false,
    shouldDisplayInHistory: false,
    stableKey: '',
    nearKey: '',
    durationSec: 0,
    lifecycleRank: 0,
    roomId: '',
    conversationId: '',
    inviteId: '',
  );
}

/// Pure call-history projection. It never schedules work or writes a message list.
class CallBubbleDedupe {
  CallBubbleDedupe._();

  static const int _maxMetaCache = 500;
  static final Map<String, _CallMsgMeta> _metaCache = <String, _CallMsgMeta>{};

  /// 同列表指纹命中则跳过二次 normalize（开聊常对同一窗跑多次）。
  static final Map<String, _NormalizeCacheEntry> _normalizeCache =
      <String, _NormalizeCacheEntry>{};
  static const int _maxNormalizeCache = 8;

  /// Legacy hold API retained for callers/tests; never gates or writes history.
  static final Set<String> _openHold = <String>{};
  static final Map<String, Timer> _openHoldTimeouts = <String, Timer>{};

  static const Duration openHoldTimeout = Duration(seconds: 2);

  /// Test-only: CallBubbleDedupe-side `jsonDecode` count (via [_tryDecodeMap]).
  @visibleForTesting
  static int debugJsonDecodeCount = 0;

  /// Legacy compatibility only; production rendering is a pure projection.
  static void beginOpenHold(
    String conversationId, {
    Duration timeout = openHoldTimeout,
  }) {
    final convKey = _convKey(conversationId);
    if (convKey.isEmpty) {
      return;
    }
    _openHold.add(convKey);
    _openHoldTimeouts[convKey]?.cancel();
    _openHoldTimeouts[convKey] = Timer(timeout, () {
      endOpenHold(convKey);
    });
  }

  /// Releases a legacy hold without publishing or mutating messages.
  static void endOpenHold(String conversationId) {
    final convKey = _convKey(conversationId);
    _openHoldTimeouts.remove(convKey)?.cancel();
    _openHold.remove(convKey);
  }

  @visibleForTesting
  static bool isOpenHeldForTesting(String conversationId) {
    final convKey = _convKey(conversationId);
    return convKey.isNotEmpty && _openHold.contains(convKey);
  }

  @visibleForTesting
  static void resetOpenHoldForTesting() {
    for (final timer in _openHoldTimeouts.values) {
      timer.cancel();
    }
    _openHoldTimeouts.clear();
    _openHold.clear();
  }

  @visibleForTesting
  static void resetMetaCacheForTesting() {
    _metaCache.clear();
    _normalizeCache.clear();
    debugJsonDecodeCount = 0;
  }

  @visibleForTesting
  static int debugNormalizeCacheSize() => _normalizeCache.length;

  /// 暖窗 / peek 写入全局列表前：通话 normalize + 通用 dedupe，首帧 tip 尽量终态。
  static List<V2TimMessage> prepareOpenHistoryMessages(
    List<V2TimMessage> messages,
  ) {
    if (messages.isEmpty) {
      return messages;
    }
    final normalized = normalizeCallHistoryMessages(
      messages,
      preserveTipIdentity: true,
    );
    return TUIChatGlobalModel.dedupeMessages(normalized);
  }

  static List<V2TimMessage> normalizeCallHistoryMessages(
    List<V2TimMessage> messages, {
    bool preserveTipIdentity = false,
  }) {
    final fingerprint = _listFingerprint(
          messages,
          preserveTipIdentity: preserveTipIdentity,
        ) +
        '|result:${CallResultRepository.instance.revision.value}'
            '|owner:${SessionIdentityService.instance.capture().ownerUserId}'
            '|epoch:${SessionIdentityService.instance.generation}';
    final cacheKey = _normalizeCacheKey(
      messages,
      preserveTipIdentity: preserveTipIdentity,
    );
    final hit = _normalizeCache[cacheKey];
    if (hit != null && hit.fingerprint == fingerprint) {
      return hit.output;
    }

    final out = RegExpProbe.measure('call_bubble.normalize', () {
      return _normalizeCallHistoryMessagesImpl(
        messages,
        preserveTipIdentity: preserveTipIdentity,
      );
    });
    if (_normalizeCache.length >= _maxNormalizeCache) {
      _normalizeCache.clear();
    }
    _normalizeCache[cacheKey] = _NormalizeCacheEntry(
      fingerprint: fingerprint,
      output: List<V2TimMessage>.unmodifiable(out),
    );
    return out;
  }

  static String _normalizeCacheKey(
    List<V2TimMessage> messages, {
    required bool preserveTipIdentity,
  }) {
    // 用列表两端 msgID 粗分会话窗；未知会话时退化为全局槽。
    final first = messages.isEmpty ? '' : (messages.first.msgID?.trim() ?? '');
    final last = messages.isEmpty ? '' : (messages.last.msgID?.trim() ?? '');
    return '${preserveTipIdentity ? 1 : 0}|$first|$last';
  }

  static String _listFingerprint(
    List<V2TimMessage> messages, {
    required bool preserveTipIdentity,
  }) {
    if (messages.isEmpty) {
      return '0|${preserveTipIdentity ? 1 : 0}';
    }
    final first = messages.first.msgID?.trim() ?? '';
    final last = messages.last.msgID?.trim() ?? '';
    final mid = messages[messages.length >> 1].msgID?.trim() ?? '';
    var hash = 0;
    for (final message in messages) {
      final id = message.msgID?.trim() ?? '';
      hash = 0x1fffffff & (hash + id.hashCode);
      hash = 0x1fffffff & (hash + (message.customElem?.data ?? '').hashCode);
      hash = 0x1fffffff & (hash + (message.localCustomData ?? '').hashCode);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= (hash >> 6);
    }
    final tipExtra =
        preserveTipIdentity ? '|tip:${tipMsgIdOf(messages) ?? ''}' : '';
    return '${messages.length}|$first|$mid|$last|$hash$tipExtra';
  }

  static List<V2TimMessage> _normalizeCallHistoryMessagesImpl(
    List<V2TimMessage> messages, {
    required bool preserveTipIdentity,
  }) {
    final tipMsgId = preserveTipIdentity ? tipMsgIdOf(messages) : null;
    final candidates = <V2TimMessage>[];
    for (final message in messages) {
      final meta = _metaFor(message);
      if (!meta.looksLikeCall && !meta.isLocalBubble) {
        candidates.add(message);
        continue;
      }
      final canonical = CallResultRepository.instance.get(meta.inviteId);
      if ((canonical != null && !canonical.effectiveStatus.isTerminal) ||
          ((meta.looksLikeCall || meta.isLocalBubble) &&
              !meta.shouldDisplayInHistory)) {
        if (kDebugMode) {
          debugPrint(
            '[CallBubble] normalize drop non-history msg=${message.msgID}',
          );
        }
        continue;
      }
      candidates.add(message);
    }

    final out = <V2TimMessage>[];
    final indexByCallId = <String, int>{};
    final indexByNearKey = <String, int>{};
    // Invite/callId is the strongest cross-source key (local bubble vs IM hangup
    // often use different stableKey shapes: call:id vs call-hangup:conv:dur).
    final indexByInviteId = <String, int>{};

    for (final message in candidates) {
      final meta = _metaFor(message);
      if (!meta.isHistoryCandidate) {
        out.add(message);
        continue;
      }

      final inviteId = meta.inviteId.trim();
      // An explicit call ID must never collide through a weaker duration key.
      final callKey = inviteId.isNotEmpty
          ? 'call:${meta.conversationId}:$inviteId'
          : meta.stableKey;
      final nearKey = inviteId.isNotEmpty ? '' : meta.nearKey;
      if (callKey.isEmpty && nearKey.isEmpty && inviteId.isEmpty) {
        out.add(message);
        continue;
      }

      final oldIndex = (callKey.isNotEmpty ? indexByCallId[callKey] : null) ??
          (nearKey.isNotEmpty ? indexByNearKey[nearKey] : null) ??
          (inviteId.isNotEmpty ? indexByInviteId[inviteId] : null);
      if (oldIndex == null) {
        final insertIndex = out.length;
        if (callKey.isNotEmpty) {
          indexByCallId[callKey] = insertIndex;
        }
        if (nearKey.isNotEmpty) {
          indexByNearKey[nearKey] = insertIndex;
        }
        if (inviteId.isNotEmpty) {
          indexByInviteId[inviteId] = insertIndex;
        }
        out.add(message);
        continue;
      }

      final old = out[oldIndex];
      if (_preferMessage(message, old, tipMsgId: tipMsgId)) {
        if (kDebugMode) {
          debugPrint(
            '[CallBubble] normalize replace callKey=$callKey nearKey=$nearKey '
            'inviteId=$inviteId oldMsg=${old.msgID} newMsg=${message.msgID}',
          );
        }
        out[oldIndex] = message;
        if (callKey.isNotEmpty) {
          indexByCallId[callKey] = oldIndex;
        }
        if (nearKey.isNotEmpty) {
          indexByNearKey[nearKey] = oldIndex;
        }
        if (inviteId.isNotEmpty) {
          indexByInviteId[inviteId] = oldIndex;
        }
        // Keep alternate keys of the replaced message pointing at the winner.
        final oldMeta = _metaFor(old);
        if (oldMeta.stableKey.isNotEmpty) {
          indexByCallId[oldMeta.stableKey] = oldIndex;
        }
        if (oldMeta.nearKey.isNotEmpty) {
          indexByNearKey[oldMeta.nearKey] = oldIndex;
        }
        if (oldMeta.inviteId.trim().isNotEmpty) {
          indexByInviteId[oldMeta.inviteId.trim()] = oldIndex;
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            '[CallBubble] normalize drop duplicate callKey=$callKey nearKey=$nearKey '
            'inviteId=$inviteId keptMsg=${old.msgID} droppedMsg=${message.msgID}',
          );
        }
        final keptMeta = _metaFor(old);
        if (callKey.isNotEmpty) {
          indexByCallId[callKey] = oldIndex;
        }
        if (nearKey.isNotEmpty) {
          indexByNearKey[nearKey] = oldIndex;
        }
        if (inviteId.isNotEmpty) {
          indexByInviteId[inviteId] = oldIndex;
        }
        if (keptMeta.stableKey.isNotEmpty) {
          indexByCallId[keptMeta.stableKey] = oldIndex;
        }
        if (keptMeta.nearKey.isNotEmpty) {
          indexByNearKey[keptMeta.nearKey] = oldIndex;
        }
      }
    }
    return out;
  }

  /// 列表 tip（newest by timestamp）的 msgID；并列时取先出现者。
  @visibleForTesting
  static String? tipMsgIdOf(List<V2TimMessage> messages) {
    V2TimMessage? newest;
    for (final message in messages) {
      final id = message.msgID?.trim() ?? '';
      if (id.isEmpty) {
        continue;
      }
      if (newest == null) {
        newest = message;
        continue;
      }
      final ts = message.timestamp ?? 0;
      final newestTs = newest.timestamp ?? 0;
      if (ts > newestTs) {
        newest = message;
      }
    }
    return newest?.msgID?.trim();
  }

  static String stableKey(V2TimMessage message) => _metaFor(message).stableKey;

  static String nearDuplicateKey(V2TimMessage message) =>
      _metaFor(message).nearKey;

  static String c2cHangupKeyForMessage(V2TimMessage message) {
    final meta = _metaFor(message);
    if (meta.durationSec <= 0 ||
        !CallBubbleDedupeKey.isC2cConversation(meta.conversationId)) {
      return '';
    }
    if (!_looksLikeConnectedHangupMeta(meta)) {
      return '';
    }
    return CallBubbleDedupeKey.c2cHangup(
      conversationId: meta.conversationId,
      durationSec: meta.durationSec,
      roomId: meta.roomId,
    );
  }

  static String conversationIdForMessage(V2TimMessage message) =>
      _metaFor(message).conversationId;

  static int hangupDurationSec(V2TimMessage message) =>
      _metaFor(message).durationSec;

  static String extractRoomId(V2TimMessage message) => _metaFor(message).roomId;

  static String extractInviteId(V2TimMessage message) =>
      _metaFor(message).inviteId;

  static _CallMsgMeta _metaFor(V2TimMessage message) {
    final key = '${SessionIdentityService.instance.capture().ownerUserId}:'
        '${SessionIdentityService.instance.generation}:'
        '${CallResultRepository.instance.revision.value}:${_cacheKey(message)}';
    final cached = _metaCache[key];
    if (cached != null) {
      return cached;
    }
    final built = _buildMeta(message);
    if (_metaCache.length >= _maxMetaCache) {
      // Drop all when full — avoids allocating a half-key List on hot path.
      _metaCache.clear();
    }
    _metaCache[key] = built;
    return built;
  }

  static String _cacheKey(V2TimMessage message) {
    final id = message.msgID?.trim() ?? '';
    final data = message.customElem?.data ?? '';
    final local = message.localCustomData ?? '';
    if (id.isNotEmpty) {
      // Local lifecycle projections deliberately reuse one msgID per callId.
      // Include mutable payloads so RINGING metadata is not reused for ENDED.
      return '$id:${data.hashCode}:${local.hashCode}';
    }
    return 'noid:${message.timestamp ?? 0}:${data.length}:${local.length}:'
        '${data.hashCode}:${local.hashCode}';
  }

  static _CallMsgMeta _buildMeta(V2TimMessage message) {
    final local = _parseLocalBubble(message);
    if (local != null) {
      return local;
    }

    if (!CallingMessageDataProvider.looksLikeCallMessage(message)) {
      return _CallMsgMeta.empty;
    }

    try {
      final provider = CallingMessageDataProvider(message);
      final isSignal = provider.isCallingSignal;
      final shouldDisplay = provider.shouldDisplayInHistory;
      final duration = provider.hangupDurationSec;
      final roomId = provider.callRoomId;
      final convId = provider.conversationID.trim().isNotEmpty
          ? provider.conversationID.trim()
          : _fallbackConversationId(message);
      final inviteId = provider.inviteID.trim();
      final lifecycleRank = _protocolLifecycleRank(provider.protocolType);

      var stable = '';
      var near = '';
      if (isSignal && shouldDisplay) {
        stable = provider.callStableKey.trim();
        near = provider.callNearDuplicateKey.trim();
      }
      // Every visible C2C lifecycle state uses callId as its stable identity,
      // allowing RINGING -> ANSWERED -> terminal to update one row.
      if (shouldDisplay) {
        if (stable.isEmpty && duration > 0 && roomId.isNotEmpty) {
          stable = 'call-room:$roomId:$duration';
        }
        if (stable.isEmpty && inviteId.isNotEmpty) {
          stable = 'call:$inviteId';
        }
        if (stable.isEmpty &&
            duration > 0 &&
            CallBubbleDedupeKey.isC2cConversation(convId)) {
          stable = CallBubbleDedupeKey.c2cHangup(
            conversationId: convId,
            durationSec: duration,
            roomId: roomId,
          );
          near = stable;
        }
      }
      // Always expose callId near-key so hangup rows collapse with local bubbles.
      if (shouldDisplay && inviteId.isNotEmpty) {
        final inviteKey = 'call:$inviteId';
        if (near.isEmpty || near != inviteKey) {
          near = inviteKey;
        }
      }

      return _CallMsgMeta(
        isLocalBubble: false,
        looksLikeCall: true,
        isCallingSignal: isSignal,
        shouldDisplayInHistory: shouldDisplay,
        stableKey: stable,
        nearKey: near,
        durationSec: duration,
        lifecycleRank: lifecycleRank,
        roomId: roomId,
        conversationId: convId,
        inviteId: inviteId,
      );
    } catch (_) {
      return const _CallMsgMeta(
        isLocalBubble: false,
        looksLikeCall: true,
        isCallingSignal: false,
        shouldDisplayInHistory: false,
        stableKey: '',
        nearKey: '',
        durationSec: 0,
        lifecycleRank: 0,
        roomId: '',
        conversationId: '',
        inviteId: '',
      );
    }
  }

  static _CallMsgMeta? _parseLocalBubble(V2TimMessage message) {
    final raw = message.localCustomData?.trim() ?? '';
    if (raw.isEmpty || !raw.contains('localCallBubble')) {
      return null;
    }
    try {
      final decoded = _tryDecodeMap(raw);
      if (decoded == null || decoded['localCallBubble'] != true) {
        return null;
      }
      final conv = decoded['conversationID']?.toString().trim() ?? '';
      // Duration may live on marker (preferred) or on customElem payload.
      var duration = _readDuration(decoded);
      var roomId = _readRoomId(decoded);
      Map? customMap;
      if (duration <= 0 || roomId.isEmpty) {
        customMap = _tryDecodeMap(message.customElem?.data?.trim() ?? '');
        if (customMap != null) {
          if (duration <= 0) {
            duration = _readDuration(customMap);
          }
          if (roomId.isEmpty) {
            roomId = _readRoomId(customMap);
          }
        }
      }
      if (roomId.isEmpty) {
        final cloudMap = _tryDecodeMap(message.cloudCustomData?.trim() ?? '');
        if (cloudMap != null) {
          roomId = _readRoomId(cloudMap);
        }
      }
      final inviteId = _firstNonEmpty([
        decoded['inviteID'],
        decoded['inviteId'],
        decoded['callId'],
        decoded['callID'],
      ]);
      final conversationId =
          conv.isNotEmpty ? conv : _fallbackConversationId(message);
      customMap ??= _tryDecodeMap(message.customElem?.data?.trim() ?? '');
      final lifecycleRank = _localLifecycleRank(
        marker: decoded,
        payload: customMap,
        durationSec: duration,
      );
      // Always keep callId key so hangup-shaped IM rows can collapse with us.
      final inviteKey = inviteId.isNotEmpty ? 'call:$inviteId' : '';
      var stable = inviteKey;
      if (duration > 0 &&
          CallBubbleDedupeKey.isC2cConversation(conversationId)) {
        stable = CallBubbleDedupeKey.c2cHangup(
          conversationId: conversationId,
          durationSec: duration,
          roomId: roomId,
        );
      } else if (duration > 0 && roomId.isNotEmpty) {
        stable = 'call-room:$roomId:$duration';
      }
      return _CallMsgMeta(
        isLocalBubble: true,
        looksLikeCall: true,
        isCallingSignal: true,
        shouldDisplayInHistory: true,
        stableKey: stable,
        nearKey: inviteKey.isNotEmpty ? inviteKey : stable,
        durationSec: duration,
        lifecycleRank: lifecycleRank,
        roomId: roomId,
        conversationId: conversationId,
        inviteId: inviteId,
      );
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeConnectedHangupMeta(_CallMsgMeta meta) {
    if (meta.durationSec <= 0) {
      return false;
    }
    if (meta.isLocalBubble) {
      return true;
    }
    return meta.isCallingSignal && meta.shouldDisplayInHistory;
  }

  static int _protocolLifecycleRank(CallProtocolType protocol) {
    switch (protocol) {
      case CallProtocolType.send:
        return 10;
      case CallProtocolType.accept:
        return 20;
      case CallProtocolType.reject:
      case CallProtocolType.cancel:
      case CallProtocolType.timeout:
      case CallProtocolType.lineBusy:
        return 30;
      case CallProtocolType.hangup:
        return 40;
      case CallProtocolType.switchToAudio:
      case CallProtocolType.switchToAudioConfirm:
      case CallProtocolType.unknown:
        return 0;
    }
  }

  static int _localLifecycleRank({
    required Map marker,
    required Map? payload,
    required int durationSec,
  }) {
    final action = _firstNonEmpty(<Object?>[
      marker['action'],
      marker['status'],
      marker['phase'],
      payload?['action'],
      payload?['status'],
      payload?['phase'],
    ]).toLowerCase();
    switch (action) {
      case 'invite':
      case 'ringing':
        return 10;
      case 'accept':
      case 'answered':
        return 20;
      case 'reject':
      case 'rejected':
      case 'cancel':
      case 'canceled':
      case 'cancelled':
      case 'timeout':
      case 'missed':
      case 'busy':
      case 'line_busy':
        return 30;
      case 'hangup':
      case 'ended':
      case 'answered_elsewhere':
        return 40;
      default:
        return durationSec > 0 ? 40 : 0;
    }
  }

  /// 轻量从原始 JSON 读 duration，不构造完整 provider 字段树之外的二次 decode 尽量复用。
  @visibleForTesting
  static int hangupDurationSecFromRaw(V2TimMessage message) {
    for (final raw in <String>[
      message.customElem?.data?.trim() ?? '',
      message.localCustomData?.trim() ?? '',
    ]) {
      final decoded = _tryDecodeMap(raw);
      if (decoded == null) {
        continue;
      }
      final value = _readDuration(decoded);
      if (value > 0) {
        return value;
      }
    }
    return 0;
  }

  @visibleForTesting
  static String extractRoomIdFromRaw(V2TimMessage message) {
    for (final raw in <String>[
      message.localCustomData?.trim() ?? '',
      message.customElem?.data?.trim() ?? '',
      message.cloudCustomData?.trim() ?? '',
    ]) {
      final decoded = _tryDecodeMap(raw);
      if (decoded == null) {
        continue;
      }
      final value = _readRoomId(decoded);
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  static Map? _tryDecodeMap(String raw) {
    final text = raw.trim();
    if (text.isEmpty || !text.startsWith('{')) {
      return null;
    }
    try {
      debugJsonDecodeCount += 1;
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  static int _readDuration(Map source) {
    final direct = source['call_end'] ?? source['callEnd'];
    if (direct is num && direct > 0) {
      return direct.round();
    }
    final data = source['data'];
    if (data is String && data.trim().startsWith('{')) {
      final nested = _tryDecodeMap(data);
      if (nested != null) {
        final nestedEnd = nested['call_end'] ?? nested['callEnd'];
        if (nestedEnd is num && nestedEnd > 0) {
          return nestedEnd.round();
        }
      }
    } else if (data is Map) {
      final nestedEnd = data['call_end'] ?? data['callEnd'];
      if (nestedEnd is num && nestedEnd > 0) {
        return nestedEnd.round();
      }
    }
    return 0;
  }

  static String _readRoomId(Map source) {
    for (final key in const ['room_id', 'roomId', 'intRoomId']) {
      final value = source[key];
      if (value is num && value > 0) {
        return value.round().toString();
      }
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text != '0' && text != 'null') {
        return text;
      }
    }
    for (final key in const ['signalingInfo', 'data', 'callInfo']) {
      final nested = source[key];
      if (nested is Map) {
        final value = _readRoomId(nested);
        if (value.isNotEmpty) {
          return value;
        }
      } else if (nested is String && nested.trim().startsWith('{')) {
        final decoded = _tryDecodeMap(nested);
        if (decoded != null) {
          final value = _readRoomId(decoded);
          if (value.isNotEmpty) {
            return value;
          }
        }
      }
    }
    return '';
  }

  static String _fallbackConversationId(V2TimMessage message) {
    final groupId = message.groupID?.trim() ?? '';
    if (groupId.isNotEmpty) {
      return 'group_$groupId';
    }
    final userId = message.userID?.trim() ?? '';
    if (userId.isNotEmpty) {
      return 'c2c_$userId';
    }
    return '';
  }

  static String _firstNonEmpty(List<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text != 'null') {
        return text;
      }
    }
    return '';
  }

  static bool _preferMessage(
    V2TimMessage next,
    V2TimMessage current, {
    String? tipMsgId,
  }) {
    final nextMeta = _metaFor(next);
    final currentMeta = _metaFor(current);
    // Lifecycle is monotonic by callId: a late invite/accept must never replace
    // a terminal projection, even when the older state is the current list tip.
    if (nextMeta.lifecycleRank != currentMeta.lifecycleRank) {
      return nextMeta.lifecycleRank > currentMeta.lifecycleRank;
    }
    final tip = tipMsgId?.trim() ?? '';
    if (tip.isNotEmpty) {
      final nextId = next.msgID?.trim() ?? '';
      final currentId = current.msgID?.trim() ?? '';
      if (nextId == tip && currentId != tip) {
        return true;
      }
      if (currentId == tip && nextId != tip) {
        return false;
      }
    }
    // For equal states prefer IM, richer duration, then newer.
    if (currentMeta.isLocalBubble && !nextMeta.isLocalBubble) {
      return true;
    }
    if (!currentMeta.isLocalBubble && nextMeta.isLocalBubble) {
      return false;
    }
    if (nextMeta.durationSec != currentMeta.durationSec) {
      return nextMeta.durationSec > currentMeta.durationSec;
    }
    final nextTs = next.timestamp ?? 0;
    final currentTs = current.timestamp ?? 0;
    return nextTs >= currentTs;
  }

  static String _convKey(String conversationId) {
    final trimmed = conversationId.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.startsWith('c2c_') || trimmed.startsWith('group_')) {
      return trimmed.substring(4);
    }
    return trimmed;
  }
}

class _NormalizeCacheEntry {
  const _NormalizeCacheEntry({
    required this.fingerprint,
    required this.output,
  });

  final String fingerprint;
  final List<V2TimMessage> output;
}
