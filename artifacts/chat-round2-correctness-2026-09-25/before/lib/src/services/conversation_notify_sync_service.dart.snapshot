import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/conversation_notify_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation_result.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

class _NotifyState {
  final Map<String, ConversationNotifyItem> pending = {};
  final Map<String, int> versions = {};
  int revision = 0, failures = 0;
  Future<void>? load, drain, sync;
  DateTime? lastSync;
  Timer? retry;
}

/// Account-scoped last-value outbox for SDK mute preferences and offline push.
class ConversationNotifySyncService {
  ConversationNotifySyncService._();
  static final instance = ConversationNotifySyncService._();
  ConversationNotifySyncService.forTesting(
      {required this.ownerForTest,
      required this.sendForTest,
      required this.pageForTest});
  String Function()? ownerForTest;
  Future<void> Function(List<ConversationNotifyItem>)? sendForTest;
  Future<V2TimConversationResult> Function(String)? pageForTest;
  final Map<SessionIdentity, _NotifyState> _states = {};
  Future<void> _persistence = Future.value();
  static bool recvOptToMuted(int? value) => value != null && value != 0;
  static bool receiveMessageOptToMuted(int? value) => recvOptToMuted(value);
  String get _owner =>
      ownerForTest?.call() ?? ApiClient.instance.authenticatedUserId;
  SessionIdentity _identity() =>
      SessionIdentityService.instance.capture(ownerUserId: _owner);
  bool _current(SessionIdentity id) =>
      SessionIdentityService.instance.isCurrent(id, currentOwnerUserId: _owner);
  String _key(ConversationNotifyItem item) => '${item.chatType}:${item.peerId}';
  String _storage(SessionIdentity id) =>
      'conversation_notify_pending_v2_${id.ownerUserId}';
  Future<void> _load(SessionIdentity id, _NotifyState state) =>
      state.load ??= () async {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_storage(id));
        if (raw == null || !_current(id)) return;
        try {
          for (final value in jsonDecode(raw) as List) {
            final item = ConversationNotifyItem.fromJson(
                Map<String, dynamic>.from(value as Map));
            if (item.peerId.isNotEmpty &&
                (item.chatType == 'c2c' || item.chatType == 'group')) {
              state.pending.putIfAbsent(_key(item), () => item);
            }
          }
        } catch (error) {
          if (kDebugMode) {
            debugPrint('ConversationNotifySync: invalid pending cache: $error');
          }
        }
      }();
  Future<void> _persist(SessionIdentity id, _NotifyState state) {
    final task = _persistence.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storage(id),
          jsonEncode(state.pending.values.map((e) => e.toJson()).toList()));
    });
    _persistence =
        task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }

  Future<void> reportAfterImSuccess(
      {required String chatType,
      required String peerId,
      required bool muted}) async {
    final type = chatType.trim().toLowerCase();
    final peer = type == 'group'
        ? ChatIdFormat.apiGroupId(peerId)
        : ChatIdFormat.rawUserUid(peerId);
    final id = _identity();
    if (!_current(id) || peer.isEmpty || (type != 'group' && type != 'c2c')) {
      return;
    }
    final state = _states.putIfAbsent(id, _NotifyState.new);
    final item =
        ConversationNotifyItem(chatType: type, peerId: peer, muted: muted);
    state.pending[_key(item)] = item;
    state.versions[_key(item)] = ++state.revision;
    await _load(id, state);
    if (!_current(id)) return;
    await _persist(id, state);
    if (_current(id)) await _drain(id, state);
  }

  void _retry(SessionIdentity id, _NotifyState state) {
    if (!_current(id) || state.retry != null) return;
    final seconds = 1 << (state.failures++).clamp(0, 6);
    state.retry = Timer(Duration(seconds: seconds), () {
      state.retry = null;
      if (_current(id)) unawaited(_drain(id, state));
    });
  }

  Future<void> _drain(SessionIdentity id, _NotifyState state) {
    if (state.drain != null) return state.drain!;
    late Future<void> task;
    task = () async {
      while (_current(id) && state.pending.isNotEmpty) {
        final sent = state.pending.values.take(100).toList();
        try {
          if (sendForTest != null) {
            await sendForTest!(sent);
          } else if (sent.length == 1) {
            final item = sent.single;
            await ConversationNotifyApi.instance.updateMute(
                chatType: item.chatType,
                peerId: item.peerId,
                muted: item.muted);
          } else {
            await ConversationNotifyApi.instance.batchUpdate(sent);
          }
        } catch (error) {
          if (kDebugMode) {
            debugPrint('ConversationNotifySync: queued retry: $error');
          }
          _retry(id, state);
          return;
        }
        if (!_current(id)) return;
        for (final item in sent) {
          if (identical(state.pending[_key(item)], item)) {
            state.pending.remove(_key(item));
          }
        }
        state.failures = 0;
        state.retry?.cancel();
        state.retry = null;
        await _persist(id, state);
      }
    }()
        .whenComplete(() {
      if (identical(state.drain, task)) state.drain = null;
    });
    state.drain = task;
    return task;
  }

  Future<void> syncAllOnLogin({bool force = false}) {
    final id = _identity();
    if (!_current(id)) return Future.value();
    final state = _states.putIfAbsent(id, _NotifyState.new);
    if (state.sync != null) return state.sync!;
    late Future<void> task;
    task = () async {
      await _load(id, state);
      if (!_current(id)) return;
      await _drain(id, state);
      if (!_current(id)) return;
      if (!force &&
          state.lastSync != null &&
          DateTime.now().difference(state.lastSync!) <
              const Duration(minutes: 5)) {
        return;
      }
      final revision = state.revision;
      final collected = <String, ConversationNotifyItem>{};
      var cursor = '0';
      final seen = <String>{};
      do {
        if (!seen.add(cursor)) throw StateError('SDK cursor repeated');
        final V2TimConversationResult page;
        if (pageForTest != null) {
          page = await pageForTest!(cursor);
        } else {
          final result = await TencentImSDKPlugin.v2TIMManager
              .getConversationManager()
              .getConversationList(nextSeq: cursor, count: 100);
          if (result.code != 0 || result.data == null) {
            throw StateError('SDK mute snapshot failed: ${result.code}');
          }
          page = result.data!;
        }
        if (!_current(id)) return;
        for (final row in page.conversationList ?? []) {
          final isGroup = !row.conversationID.startsWith('c2c_') &&
              (row.type == 2 || (row.groupID?.isNotEmpty ?? false));
          final peer = isGroup
              ? ChatIdFormat.apiGroupId(
                  row.groupID ?? row.conversationID.replaceFirst('group_', ''))
              : ChatIdFormat.rawUserUid(
                  row.userID ?? row.conversationID.replaceFirst('c2c_', ''));
          if (peer.isEmpty || peer == '10000' || row.recvOpt == null) continue;
          final item = ConversationNotifyItem(
              chatType: isGroup ? 'group' : 'c2c',
              peerId: peer,
              muted: recvOptToMuted(row.recvOpt));
          collected[_key(item)] = item;
        }
        if (page.isFinished == true) break;
        cursor = page.nextSeq?.trim() ?? '';
        if (cursor.isEmpty) throw StateError('SDK cursor missing');
      } while (true);
      for (final entry in collected.entries) {
        if ((state.versions[entry.key] ?? 0) > revision) continue;
        state.pending.putIfAbsent(entry.key, () => entry.value);
      }
      await _persist(id, state);
      if (!_current(id)) return;
      await _drain(id, state);
      if (_current(id) && state.pending.isEmpty) {
        state.lastSync = DateTime.now();
      }
    }()
        .catchError((Object error, StackTrace stack) {
      if (kDebugMode) {
        debugPrint('ConversationNotifySync: login sync failed: $error');
      }
      if (force) Error.throwWithStackTrace(error, stack);
    }).whenComplete(() {
      if (identical(state.sync, task)) state.sync = null;
    });
    state.sync = task;
    return task;
  }

  void clearSession() {
    for (final state in _states.values) {
      state.retry?.cancel();
    }
    _states.clear();
  }
}
