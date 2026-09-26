import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/conversation_projection_reason.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_id_canonical.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_flicker_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/utils/archived_conversation_ref.dart';
import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

class ConversationPinApplyResult {
  const ConversationPinApplyResult({
    required this.applied,
    required this.isPinned,
    this.sdkOk = false,
  });

  final bool applied;
  final bool isPinned;

  /// 腾讯 `pinConversation` 是否成功。
  final bool sdkOk;
}

/// 会话置顶同步。腾讯 IM `pinConversation` / SDK `isPinned` 为唯一真相。
class ConversationPinSyncService {
  ConversationPinSyncService._();

  static final ConversationPinSyncService instance =
      ConversationPinSyncService._();

  static const String _guestScope = '_guest';
  static const Duration _loginSyncCooldown = Duration(minutes: 2);
  static const int _tencentPinListPageSize = 100;
  static const int _tencentPinListMaxPages = 20;

  final Set<String> _pinnedConversationIds = <String>{};
  int _setUpdatedAtMs = 0;
  bool _isHydrated = false;
  final Map<String, ({bool value, Object token})> _pendingSdkPins = {};
  final Map<String, ({bool value, Future<ConversationPinApplyResult> task})>
      _pinCommands = {};

  bool pinValueFor(V2TimConversation conversation) =>
      _pendingSdkPins[
              ConversationIdCanonical.forStorage(conversation.conversationID)]
          ?.value ??
      // A profile/settings route retains its opening snapshot. Prefer the
      // current SDK projection before deciding that an explicit tap is a noop.
      ChatSessionController.instance
          .currentConversationById(conversation.conversationID)
          ?.isPinned ??
      conversation.isPinned ??
      isPinnedConversationId(conversation.conversationID);

  /// SDK fields win after an operation completes. Cached pin sets must never
  /// overwrite a newer cross-device SDK update.
  void applySdkPinProjection(V2TimConversation conversation) {
    final id = conversation.conversationID.trim();
    if (id.isEmpty) return;
    final key = ConversationIdCanonical.forStorage(id);
    final pending = _pendingSdkPins[key];
    if (pending != null) {
      conversation.isPinned = pending.value;
      return;
    }
    if (conversation.isPinned == null) return;
    _pinnedConversationIds.removeWhere(
      (other) => MessageConversationId.sameConversation(other, id),
    );
    if (conversation.isPinned == true) _pinnedConversationIds.add(id);
    _isHydrated = true;
  }

  DateTime? _lastLoginSyncAt;
  SessionIdentity? _lastLoginSyncIdentity;
  SessionIdentity? _loginSyncIdentity;
  Future<void>? _loginSyncInFlight;
  SessionIdentity? _tencentReconcileIdentity;
  Future<void>? _tencentReconcileInFlight;

  /// 单测注入：返回 `true` 表示腾讯置顶成功。
  @visibleForTesting
  static Future<bool> Function(String conversationID, bool isPinned)?
      debugPinConversationOverride;

  /// 单测注入：返回腾讯当前置顶 conversationID 集合。
  @visibleForTesting
  static Future<Set<String>> Function()? debugCollectTencentPinnedIdsOverride;

  /// 单测注入账号 scope（非空时跳过 `_guest` 门闩）。
  @visibleForTesting
  static String? debugAccountScopeOverride;

  /// 单测：跳过 prefs / SQLite / UI 刷新，只改内存集合。
  @visibleForTesting
  static bool debugSkipPersistAndUiForTest = false;

  Set<String> get pinnedConversationIds =>
      Set<String>.unmodifiable(_pinnedConversationIds);

  /// Whether the account has received a pin projection. SDK rows always keep
  /// their own absolute value, except for an in-flight local pin command.
  bool get isHydrated => _isHydrated;

  /// Removes a conversation that no longer exists (for example after leaving
  /// or dissolving a group) from every local pin projection.
  Future<void> removeDeletedConversation(String conversationID) async {
    final identity = _captureIdentity();
    if (!_hasAccountScopedIdentity(identity)) return;
    final id = conversationID.trim();
    if (id.isEmpty) return;
    final hadMatch = _pinnedConversationIds.any(
      (pinned) => MessageConversationId.sameConversation(pinned, id),
    );
    if (!hadMatch) return;
    final previous = Set<String>.from(_pinnedConversationIds);
    _pinnedConversationIds.removeWhere(
      (pinned) => MessageConversationId.sameConversation(pinned, id),
    );
    await ConversationSyncService.instance.reconcileConversationPinSetLocally(
      previousPinnedConversationIds: previous,
      pinnedConversationIds: _pinnedConversationIds,
    );
  }

  int get setUpdatedAtMs => _setUpdatedAtMs;

  bool isPinnedConversationId(String? conversationID) {
    final id = conversationID?.trim() ?? '';
    if (id.isEmpty || _pinnedConversationIds.isEmpty) {
      return false;
    }
    if (_pinnedConversationIds.contains(id)) {
      return true;
    }
    for (final pinned in _pinnedConversationIds) {
      if (MessageConversationId.sameConversation(pinned, id)) {
        return true;
      }
    }
    return false;
  }

  Future<void> syncOnLogin({bool force = false}) {
    final identity = _captureIdentity();
    if (!_hasAccountScopedIdentity(identity)) return Future<void>.value();
    if (!force &&
        _lastLoginSyncIdentity == identity &&
        _lastLoginSyncAt != null &&
        DateTime.now().difference(_lastLoginSyncAt!) < _loginSyncCooldown) {
      return Future<void>.value();
    }
    final running = _loginSyncInFlight;
    if (running != null && _loginSyncIdentity == identity) return running;
    late final Future<void> task;
    task = _syncOnLogin(force: force, identity: identity).whenComplete(() {
      if (identical(_loginSyncInFlight, task)) {
        _loginSyncInFlight = null;
        _loginSyncIdentity = null;
      }
    });
    _loginSyncIdentity = identity;
    _loginSyncInFlight = task;
    return task;
  }

  Future<void> _syncOnLogin({
    required bool force,
    required SessionIdentity identity,
  }) async {
    try {
      await reconcileFromTencent(reason: 'login');
      if (!_isCurrent(identity)) return;
      _lastLoginSyncAt = DateTime.now();
      _lastLoginSyncIdentity = identity;
    } catch (e, st) {
      debugPrint('ConversationPinSync: login sync failed: $e\n$st');
      if (force) {
        rethrow;
      }
    }
  }

  /// 拉取腾讯当前置顶会话 ID（置顶在列表头部，遇首条非置顶可提前结束）。
  ///
  /// 例外：此处仍可用混流 `getConversationList` 扫 `isPinned`（日志可见
  /// `conversation_type:unknown`）。**禁止**在本路径写入
  /// ConversationLocalStore sync meta / `setHasSyncedOnce`——会话灌库游标
  /// 只允许 ByFilter typed 路径推进。
  Future<Set<String>> collectTencentPinnedConversationIds({
    SessionIdentity? expectedIdentity,
  }) async {
    final identity = expectedIdentity ?? _captureIdentity();
    if (!_hasAccountScopedIdentity(identity)) return <String>{};
    final override = debugCollectTencentPinnedIdsOverride;
    if (override != null) {
      return override();
    }
    final pinned = <String>{};
    var nextSeq = '0';
    for (var page = 0; page < _tencentPinListMaxPages; page++) {
      final res = await TencentImSDKPlugin.v2TIMManager
          .getConversationManager()
          .getConversationList(
            nextSeq: nextSeq,
            count: _tencentPinListPageSize,
          );
      if (!_isCurrent(identity)) return <String>{};
      if (res.code != 0) {
        ConversationPinFlickerLog.log(
          'pin_tencent_list_fail',
          extras: <String, Object?>{
            'code': res.code,
            'desc': res.desc,
            'page': page,
          },
        );
        break;
      }
      final data = res.data;
      final list = data?.conversationList ?? const <V2TimConversation>[];
      var hitUnpinned = false;
      for (final conversation in list) {
        final id = conversation.conversationID.trim();
        if (id.isEmpty) {
          continue;
        }
        if (conversation.isPinned == true) {
          pinned.add(id);
        } else {
          hitUnpinned = true;
          break;
        }
      }
      final finished = data?.isFinished == true;
      final seq = data?.nextSeq?.toString() ?? '';
      if (hitUnpinned ||
          finished ||
          seq.isEmpty ||
          seq == '0' ||
          seq == nextSeq) {
        break;
      }
      nextSeq = seq;
    }
    return pinned;
  }

  /// 先 IM，成功后再改本地。
  Future<ConversationPinApplyResult> setPinned({
    required V2TimConversation conversation,
    required bool pinned,
    String source = 'unknown',
    double? listScrollOffset,
  }) async {
    final identity = _captureIdentity();
    if (!_hasAccountScopedIdentity(identity)) {
      return ConversationPinApplyResult(
        applied: false,
        isPinned: conversation.isPinned ?? false,
        sdkOk: false,
      );
    }
    final commandKey =
        ConversationIdCanonical.forStorage(conversation.conversationID);
    final pendingCommand = _pinCommands[commandKey];
    if (pendingCommand != null) {
      if (pendingCommand.value == pinned) return pendingCommand.task;
      await pendingCommand.task;
      if (!_isCurrent(identity)) {
        return ConversationPinApplyResult(
            applied: false,
            sdkOk: false,
            isPinned: conversation.isPinned ?? false);
      }
      // Opposite taps wait for the first result. A failed optimistic pin is
      // never used as the rollback baseline for a second command.
      conversation.isPinned =
          isPinnedConversationId(conversation.conversationID);
      return setPinned(
          conversation: conversation,
          pinned: pinned,
          source: source,
          listScrollOffset: listScrollOffset);
    }
    final ref = ArchivedConversationRef.fromConversation(conversation);
    if (ref == null) {
      return ConversationPinApplyResult(
        applied: false,
        isPinned: conversation.isPinned ?? false,
        sdkOk: false,
      );
    }
    final prevPinned = pinValueFor(conversation);
    if (prevPinned == pinned) {
      return ConversationPinApplyResult(
        applied: true,
        isPinned: pinned,
        sdkOk: true,
      );
    }

    _pinnedConversationIds.removeWhere((id) =>
        MessageConversationId.sameConversation(
            id, conversation.conversationID));
    if (prevPinned) _pinnedConversationIds.add(conversation.conversationID);
    final task = _setPinnedTencentPrimary(
      conversation: conversation,
      ref: ref,
      pinned: pinned,
      prevPinned: prevPinned,
      source: source,
      listScrollOffset: listScrollOffset,
      identity: identity,
    );
    _pinCommands[commandKey] = (value: pinned, task: task);
    try {
      return await task;
    } finally {
      if (identical(_pinCommands[commandKey]?.task, task))
        _pinCommands.remove(commandKey);
    }
  }

  Future<ConversationPinApplyResult> _setPinnedTencentPrimary({
    required V2TimConversation conversation,
    required ArchivedConversationRef ref,
    required bool pinned,
    required bool prevPinned,
    required String source,
    required SessionIdentity identity,
    double? listScrollOffset,
  }) async {
    if (!_isCurrent(identity)) {
      return ConversationPinApplyResult(
        applied: false,
        isPinned: prevPinned,
        sdkOk: false,
      );
    }
    final conversationID = conversation.conversationID.trim();
    ConversationPinFlickerLog.log(
      'pin_tencent_start',
      conversationID: conversationID,
      extras: <String, Object?>{
        'source': source,
        'nextPinned': pinned,
        'prevPinned': prevPinned,
      },
    );

    void publish(bool value) {
      _pinnedConversationIds.removeWhere(
          (id) => MessageConversationId.sameConversation(id, conversationID));
      if (value) _pinnedConversationIds.add(conversationID);
      _isHydrated = true;
      _setUpdatedAtMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      conversation.isPinned = value;
      if (!debugSkipPersistAndUiForTest) {
        ChatSessionController.instance.applyPinnedWithDeferredReorder(
            conversationID: conversationID,
            isPinned: value,
            snapshot: conversation,
            listScrollOffset: listScrollOffset);
      }
    }

    final optimistic = ConversationPerfFlags.pinOptimisticUiEnabled &&
        !debugSkipPersistAndUiForTest;
    if (optimistic) {
      publish(pinned);
      ConversationPinFlickerLog.log(
        'pin_phase_optimistic',
        conversationID: conversationID,
        extras: <String, Object?>{
          'source': source,
          'nextPinned': pinned,
        },
      );
    }

    final pendingKey = ConversationIdCanonical.forStorage(conversationID);
    final token = Object();
    _pendingSdkPins[pendingKey] = (value: pinned, token: token);
    final bool sdkOk;
    var ownsResult = false;
    try {
      sdkOk = await _pinConversationOnTencent(conversationID, pinned);
    } finally {
      ownsResult = identical(_pendingSdkPins[pendingKey]?.token, token);
      if (ownsResult) {
        _pendingSdkPins.remove(pendingKey);
      }
    }
    if (!_isCurrent(identity) || !ownsResult) {
      return ConversationPinApplyResult(
        applied: false,
        isPinned: prevPinned,
        sdkOk: false,
      );
    }
    if (!sdkOk) {
      if (optimistic) {
        publish(prevPinned);
        ConversationPinFlickerLog.log(
          'pin_phase_rollback',
          conversationID: conversationID,
          extras: <String, Object?>{'source': source},
        );
      }
      ConversationPinFlickerLog.log(
        'pin_tencent_fail',
        conversationID: conversationID,
        extras: <String, Object?>{'source': source},
      );
      return ConversationPinApplyResult(
        applied: false,
        isPinned: prevPinned,
        sdkOk: false,
      );
    }

    // Publish synchronously at SDK completion. No prefs/SQLite round trip can
    // later overwrite a newer cross-device callback; SDK owns persistence.
    publish(pinned);

    ConversationPinFlickerLog.log(
      'pin_tencent_ok',
      conversationID: conversationID,
      extras: <String, Object?>{
        'source': source,
        'pinned': pinned,
        'count': _pinnedConversationIds.length,
      },
    );
    return ConversationPinApplyResult(
      applied: true,
      isPinned: pinned,
      sdkOk: true,
    );
  }

  /// 以腾讯当前 pin 集合覆盖本地。
  Future<void> reconcileFromTencent({String reason = 'manual'}) {
    final identity = _captureIdentity();
    if (!_hasAccountScopedIdentity(identity)) return Future<void>.value();
    final running = _tencentReconcileInFlight;
    if (running != null && _tencentReconcileIdentity == identity) {
      return running;
    }
    late final Future<void> task;
    task = _reconcileFromTencentCore(
      reason: reason,
      identity: identity,
    ).whenComplete(() {
      if (identical(_tencentReconcileInFlight, task)) {
        _tencentReconcileInFlight = null;
        _tencentReconcileIdentity = null;
      }
    });
    _tencentReconcileIdentity = identity;
    _tencentReconcileInFlight = task;
    return task;
  }

  Future<void> _reconcileFromTencentCore({
    required String reason,
    required SessionIdentity identity,
  }) async {
    if (!_hasAccountScopedIdentity(identity)) {
      return;
    }
    try {
      final ids = await collectTencentPinnedConversationIds(
        expectedIdentity: identity,
      );
      if (!_isCurrent(identity)) return;
      await _applyPinnedIds(
        ids,
        updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
        identity: identity,
      );
      ConversationRefreshBus.instance.requestRefresh(reason: reason);
      ConversationPinFlickerLog.log(
        'pin_tencent_reconcile_ok',
        extras: <String, Object?>{
          'reason': reason,
          'count': ids.length,
        },
      );
    } catch (e, st) {
      debugPrint('ConversationPinSync: tencent reconcile failed: $e\n$st');
      ConversationPinFlickerLog.log(
        'pin_tencent_reconcile_fail',
        extras: <String, Object?>{'reason': reason, 'error': '$e'},
      );
    }
  }

  Future<void> _applyPinnedIds(
    Set<String> next, {
    required int updatedAtMs,
    double? listScrollOffset,
    String? changedConversationId,
    bool? changedPinned,
    V2TimConversation? snapshot,
    SessionIdentity? identity,
  }) async {
    final capturedIdentity = identity ?? _captureIdentity();
    if (!_hasAccountScopedIdentity(capturedIdentity)) {
      return;
    }

    final previous = Set<String>.from(_pinnedConversationIds);
    _pinnedConversationIds
      ..clear()
      ..addAll(next);
    _setUpdatedAtMs = updatedAtMs;
    if (debugSkipPersistAndUiForTest) {
      return;
    }
    if (!_isCurrent(capturedIdentity)) return;

    if (changedConversationId != null &&
        changedConversationId.isNotEmpty &&
        changedPinned != null) {
      if (_pinSetChangedOutsideTarget(
        previous: previous,
        next: next,
        targetConversationId: changedConversationId,
      )) {
        await ConversationSyncService.instance
            .reconcileConversationPinSetLocally(
          previousPinnedConversationIds: previous,
          pinnedConversationIds: next,
        );
      }
      await ConversationSyncService.instance.applyConversationPinLocally(
        conversationID: changedConversationId,
        isPinned: changedPinned,
        snapshot: snapshot,
        listScrollOffset: listScrollOffset,
      );
    } else {
      await ConversationSyncService.instance.reconcileConversationPinSetLocally(
        previousPinnedConversationIds: previous,
        pinnedConversationIds: next,
      );
      await ChatSessionController.instance.restoreProjection(
        reason: ConversationStoreProjectionReason.pinHydration,
      );
    }
  }

  bool _pinSetChangedOutsideTarget({
    required Set<String> previous,
    required Set<String> next,
    required String targetConversationId,
  }) {
    for (final id in previous) {
      if (MessageConversationId.sameConversation(id, targetConversationId)) {
        continue;
      }
      if (!_setContainsConversation(next, id)) {
        return true;
      }
    }
    for (final id in next) {
      if (MessageConversationId.sameConversation(id, targetConversationId)) {
        continue;
      }
      if (!_setContainsConversation(previous, id)) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _pinConversationOnTencent(
    String conversationID,
    bool isPinned,
  ) async {
    final id = conversationID.trim();
    if (id.isEmpty) {
      return false;
    }
    final override = debugPinConversationOverride;
    if (override != null) {
      return override(id, isPinned);
    }
    try {
      final V2TimCallback result = await TencentImSDKPlugin.v2TIMManager
          .getConversationManager()
          .pinConversation(conversationID: id, isPinned: isPinned);
      if (result.code != 0) {
        ConversationPinFlickerLog.log(
          'pin_tencent_sdk_error',
          conversationID: id,
          extras: <String, Object?>{
            'code': result.code,
            'desc': result.desc,
            'isPinned': isPinned,
          },
        );
        return false;
      }
      return true;
    } catch (e, st) {
      debugPrint('ConversationPinSync: TIM pinConversation failed: $e\n$st');
      return false;
    }
  }

  Future<void> clearSession() async {
    _lastLoginSyncAt = null;
    _lastLoginSyncIdentity = null;
    _loginSyncIdentity = null;
    _loginSyncInFlight = null;
    _tencentReconcileInFlight = null;
    _tencentReconcileIdentity = null;
    _pinnedConversationIds.clear();
    _isHydrated = false;
    _pendingSdkPins.clear();
    _pinCommands.clear();
    _setUpdatedAtMs = 0;
  }

  /// 注销：删除该账号旧置顶 prefs，并卸内存。
  Future<void> clearForOwner(String? ownerUserId) async {
    final scope = ContactSocialCacheStore.accountScopeForUserId(ownerUserId);
    await clearSession();
    if (scope.isEmpty || scope == _guestScope) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pinned_conversations_v1_$scope');
    await prefs.remove('pinned_source_backend_v1_$scope');
    await prefs.remove('pin_sdk_migrated_v1_$scope');
  }

  /// 单测注入置顶集合（不写 prefs / 不改 SQLite）。
  @visibleForTesting
  void debugReplacePinnedIdsForTest(
    Iterable<String> ids, {
    bool markHydrated = false,
  }) {
    _pinnedConversationIds
      ..clear()
      ..addAll(
        ids.map((e) => e.trim()).where((e) => e.isNotEmpty),
      );
    if (markHydrated) {
      _isHydrated = true;
    }
  }

  /// 单测复位所有 debug 注入。
  @visibleForTesting
  static void debugResetTestHooks() {
    debugPinConversationOverride = null;
    debugCollectTencentPinnedIdsOverride = null;
    debugAccountScopeOverride = null;
    debugSkipPersistAndUiForTest = false;
  }

  /// 正式账号 scope：禁止用 `_guest` 读写正式置顶缓存。
  SessionIdentity _captureIdentity() {
    final override = debugAccountScopeOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return SessionIdentity(
        ownerUserId: override,
        generation: SessionIdentityService.instance.generation,
      );
    }
    return SessionIdentityService.instance.capture();
  }

  bool _isCurrent(SessionIdentity identity) {
    final override = debugAccountScopeOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return identity.ownerUserId == override &&
          SessionIdentityService.instance
              .isGenerationCurrent(identity.generation);
    }
    return SessionIdentityService.instance.isCurrent(identity);
  }

  bool _hasAccountScopedIdentity(SessionIdentity identity) {
    final scope = _prefsScope(identity);
    return scope.isNotEmpty && scope != _guestScope;
  }

  String _prefsScope([SessionIdentity? identity]) {
    final override = debugAccountScopeOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return ContactSocialCacheStore.accountScopeForUserId(
      identity?.ownerUserId ?? ContactSocialCacheStore.safeLoginUserId(),
    );
  }

  static bool _setContainsConversation(Set<String> ids, String conversationId) {
    if (ids.contains(conversationId)) {
      return true;
    }
    for (final id in ids) {
      if (MessageConversationId.sameConversation(id, conversationId)) {
        return true;
      }
    }
    return false;
  }
}
