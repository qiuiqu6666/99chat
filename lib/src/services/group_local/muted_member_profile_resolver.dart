import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

enum MutedProfileStatus {
  resolved,
  resolvedEmpty,
  partial,
  forbidden,
  notFound,
  failed,
  stale,
}

class MutedProfileResult {
  const MutedProfileResult(this.status, {this.nickname, this.avatarUrl});
  final MutedProfileStatus status;
  final String? nickname;
  final String? avatarUrl;
  bool get canRetry =>
      status == MutedProfileStatus.failed ||
      status == MutedProfileStatus.partial ||
      status == MutedProfileStatus.notFound;
}

typedef MutedProfileLoader
    = Future<V2TimValueCallback<List<V2TimGroupMemberFullInfo>>> Function(
        String groupId, List<String> ids);

/// Display-only, route-owned cache. Never writes group membership or mute state.
/// A caller must invalidate this resolver when its route/permission changes.
class MutedMemberProfileResolver {
  MutedMemberProfileResolver({
    MutedProfileLoader? loader,
    this.timeout = const Duration(seconds: 8),
    this.ttl = const Duration(seconds: 60),
    this.retryDelay = const Duration(seconds: 1),
    DateTime Function()? now,
  })  : _loader = loader ?? _loadSdk,
        _now = now ?? DateTime.now;

  final MutedProfileLoader _loader;
  final DateTime Function() _now;
  final Duration timeout;
  final Duration ttl;
  final Duration retryDelay;
  final _cache =
      LinkedHashMap<String, ({DateTime at, MutedProfileResult value})>();
  final _inFlight = <String, Future<Map<String, MutedProfileResult>>>{};
  int _epoch = 0;

  static Future<V2TimValueCallback<List<V2TimGroupMemberFullInfo>>> _loadSdk(
          String groupId, List<String> ids) =>
      TencentImSDKPlugin.v2TIMManager
          .getGroupManager()
          .getGroupMembersInfo(groupID: groupId, memberList: ids);

  void invalidate() {
    _epoch++;
    _cache.clear();
    _inFlight.clear();
  }

  Future<Map<String, MutedProfileResult>> resolve({
    required String groupId,
    required List<String> userIds,
    required SessionIdentity identity,
    required bool Function() isCurrent,
    bool force = false,
  }) {
    final ids = userIds
        .map(ChatIdFormat.rawUserUid)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final gid = ChatIdFormat.normalizeGroupId(groupId);
    if (ids.isEmpty ||
        gid.isEmpty ||
        identity.ownerUserId.isEmpty ||
        !isCurrent()) {
      return Future.value({});
    }
    final scope = jsonEncode([identity.ownerUserId, identity.generation, gid]);
    final key = jsonEncode([scope, ids, force]);
    final active = _inFlight[key];
    if (active != null) return active;
    // Route callers normally have one request. Bound pathological concurrent
    // requests as well, without launching more SDK work.
    if (_inFlight.length >= 16) {
      return Future.value({
        for (final id in ids)
          id: const MutedProfileResult(MutedProfileStatus.failed)
      });
    }
    final epoch = _epoch;
    bool valid() => epoch == _epoch && isCurrent();
    late final Future<Map<String, MutedProfileResult>> task;
    task = _resolve(gid, ids, scope, valid, force).whenComplete(() {
      if (identical(_inFlight[key], task)) _inFlight.remove(key);
    });
    _inFlight[key] = task;
    return task;
  }

  Future<Map<String, MutedProfileResult>> _resolve(String groupId,
      List<String> ids, String scope, bool Function() valid, bool force) async {
    final out = <String, MutedProfileResult>{};
    final missing = <String>[];
    for (final id in ids) {
      final key = jsonEncode([scope, id]);
      final cached = _cache.remove(key);
      if (!force && cached != null && _now().difference(cached.at) < ttl) {
        _cache[key] = cached;
        out[id] = cached.value;
      } else {
        missing.add(id);
      }
    }
    for (var offset = 0; offset < missing.length; offset += 50) {
      if (!valid()) return {};
      final batch = missing.skip(offset).take(50).toList();
      V2TimValueCallback<List<V2TimGroupMemberFullInfo>>? response;
      // Retry only an actual timeout; unknown SDK errors may be permission
      // failures. Never switch endpoints or group aliases to evade a denial.
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          response = await _loader(groupId, batch).timeout(timeout);
          break;
        } on TimeoutException {
          if (attempt == 0 && valid()) await Future<void>.delayed(retryDelay);
        } catch (_) {
          break;
        }
        if (!valid()) return {};
      }
      if (!valid()) return {};
      final code = response?.code;
      if (kDebugMode)
        debugPrint('[MutedProfiles] batch=${batch.length} code=$code');
      // Codes are defined by the bundled SDK TIMErrCode enum.
      if (code == 10007 || code == 10010) {
        _cache.clear();
        return {
          for (final id in ids)
            id: MutedProfileResult(code == 10007
                ? MutedProfileStatus.forbidden
                : MutedProfileStatus.notFound)
        };
      }
      final found = {
        for (final m in response?.data ?? <V2TimGroupMemberFullInfo>[])
          ChatIdFormat.rawUserUid(m.userID): m
      };
      for (final id in batch) {
        final member = code == 0 ? found[id] : null;
        final name = member?.nickName?.trim();
        final avatar = member?.faceUrl?.trim();
        final status = code != 0
            ? MutedProfileStatus.failed
            : member == null
                ? MutedProfileStatus.notFound
                : name == null || avatar == null
                    ? MutedProfileStatus.partial
                    : name.isEmpty && avatar.isEmpty
                        ? MutedProfileStatus.resolvedEmpty
                        : MutedProfileStatus.resolved;
        final result =
            MutedProfileResult(status, nickname: name, avatarUrl: avatar);
        out[id] = result;
        if (member != null) {
          _cache[jsonEncode([scope, id])] = (at: _now(), value: result);
          while (_cache.length > 500) {
            _cache.remove(_cache.keys.first);
          }
        }
      }
    }
    return valid() ? out : {};
  }
}
