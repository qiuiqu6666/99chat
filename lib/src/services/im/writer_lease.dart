import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

/// Parses `flutter-message-core-v2:$pid:$uuid`. No IO; lock probing stays
/// in [MessageCoreOwner.isAbandoned].
class MessageCoreOwnerId {
  static final RegExp _v2Pattern = RegExp(
    r'^flutter-message-core-v2:(\d+):([a-f0-9-]{36})$',
  );

  static const int sameProcessStaleThresholdMs = 15000;

  static int? pid(String ownerId) {
    final match = _v2Pattern.firstMatch(ownerId.trim());
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  static String? token(String ownerId) {
    final match = _v2Pattern.firstMatch(ownerId.trim());
    return match?.group(2);
  }

  static bool sameProcess(String left, String right) {
    final leftPid = pid(left);
    final rightPid = pid(right);
    return leftPid != null && rightPid != null && leftPid == rightPid;
  }

  static bool isHeartbeatStale({
    required int heartbeatAtMs,
    required int nowMs,
  }) {
    if (heartbeatAtMs <= 0) return true;
    return nowMs - heartbeatAtMs > sameProcessStaleThresholdMs;
  }
}

class ImWriterLease {
  const ImWriterLease({
    required this.ownerUserId,
    required this.leaseOwnerId,
    required this.fencingToken,
    required this.acquiredAtMs,
    required this.expiresAtMs,
    required this.heartbeatAtMs,
  });

  final String ownerUserId;
  final String leaseOwnerId;
  final int fencingToken;
  final int acquiredAtMs;
  final int expiresAtMs;
  final int heartbeatAtMs;

  bool isExpiredAt(int nowMs) => expiresAtMs <= nowMs;

  ImWriterLeaseRecord toRecord() => ImWriterLeaseRecord(
        ownerUserId: ownerUserId,
        leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken,
        acquiredAtMs: acquiredAtMs,
        expiresAtMs: expiresAtMs,
        heartbeatAtMs: heartbeatAtMs,
      );

  static ImWriterLease fromRecord(ImWriterLeaseRecord record) => ImWriterLease(
        ownerUserId: record.ownerUserId,
        leaseOwnerId: record.leaseOwnerId,
        fencingToken: record.fencingToken,
        acquiredAtMs: record.acquiredAtMs,
        expiresAtMs: record.expiresAtMs,
        heartbeatAtMs: record.heartbeatAtMs,
      );
}

class ImMessageCoreLeaseContext {
  const ImMessageCoreLeaseContext({
    required this.store,
    required this.lease,
    required this.ownerUserId,
    required this.accountGeneration,
    required this.domainGeneration,
  });

  final ImIngressStore store;
  final ImWriterLease lease;
  final String ownerUserId;
  final int accountGeneration;
  final int domainGeneration;
}

/// Transactional owner election and fencing-token validation for MessageCore.
class ImWriterLeaseService {
  ImWriterLeaseService({
    required ImIngressStore store,
    this.isOwnerAbandoned,
    this.prepareOwner,
  }) : _store = store;

  final ImIngressStore _store;
  final Future<bool> Function(String leaseOwnerId)? isOwnerAbandoned;
  final Future<String> Function()? prepareOwner;

  Future<ImWriterLease?> acquire({
    required String ownerUserId,
    required String leaseOwnerId,
    required int nowMs,
    int ttlMs = 15000,
    void Function(ImWriterLease? current, String reason)? onBlocked,
  }) async {
    final owner = _required(ownerUserId, 'ownerUserId');
    _requiredOpaque(leaseOwnerId, 'leaseOwnerId');
    _validateTimes(nowMs: nowMs, ttlMs: ttlMs);
    return _store.transaction<ImWriterLease?>((transaction) async {
      final leaseOwner = _requiredOpaque(
          await prepareOwner?.call() ?? leaseOwnerId, 'leaseOwnerId');
      final current = await transaction.findWriterLease(owner);
      if (current != null &&
          current.leaseOwnerId != leaseOwner &&
          !current.isExpiredAt(nowMs)) {
        final holder = ImWriterLease.fromRecord(current);
        if (MessageCoreOwnerId.sameProcess(current.leaseOwnerId, leaseOwner)) {
          if (!MessageCoreOwnerId.isHeartbeatStale(
            heartbeatAtMs: current.heartbeatAtMs,
            nowMs: nowMs,
          )) {
            onBlocked?.call(holder, 'other_owner_active');
            return null;
          }
          onBlocked?.call(holder, 'abandoned_same_process_isolate');
        } else if (!(await isOwnerAbandoned?.call(current.leaseOwnerId) ??
            false)) {
          onBlocked?.call(holder, 'other_owner_active');
          return null;
        }
      }

      final isSameActiveOwner = current != null &&
          current.leaseOwnerId == leaseOwner &&
          !current.isExpiredAt(nowMs);
      final nextToken = isSameActiveOwner
          ? current.fencingToken
          : (current?.fencingToken ?? 0) + 1;
      final replacement = ImWriterLeaseRecord(
        ownerUserId: owner,
        leaseOwnerId: leaseOwner,
        fencingToken: nextToken,
        acquiredAtMs: isSameActiveOwner ? current.acquiredAtMs : nowMs,
        expiresAtMs: nowMs + ttlMs,
        heartbeatAtMs: nowMs,
      );
      final replaced = current == null
          ? await transaction.insertWriterLeaseIfAbsent(replacement)
          : await transaction.replaceWriterLeaseIfCurrent(
              ownerUserId: owner,
              expectedLeaseOwnerId: current.leaseOwnerId,
              expectedFencingToken: current.fencingToken,
              replacement: replacement,
            );
      if (!replaced) {
        onBlocked?.call(
            current == null ? null : ImWriterLease.fromRecord(current),
            'compare_and_swap_failed');
      }
      return replaced ? ImWriterLease.fromRecord(replacement) : null;
    });
  }

  Future<ImWriterLease?> renew({
    required ImWriterLease lease,
    required int nowMs,
    int ttlMs = 15000,
  }) async {
    _validateTimes(nowMs: nowMs, ttlMs: ttlMs);
    if (lease.isExpiredAt(nowMs)) return null;
    return _store.transaction<ImWriterLease?>((transaction) async {
      final current = await transaction.findWriterLease(lease.ownerUserId);
      if (current == null ||
          current.leaseOwnerId != lease.leaseOwnerId ||
          current.fencingToken != lease.fencingToken ||
          current.isExpiredAt(nowMs)) {
        return null;
      }
      final replacement = ImWriterLeaseRecord(
        ownerUserId: current.ownerUserId,
        leaseOwnerId: current.leaseOwnerId,
        fencingToken: current.fencingToken,
        acquiredAtMs: current.acquiredAtMs,
        expiresAtMs: nowMs + ttlMs,
        heartbeatAtMs: nowMs,
      );
      final replaced = await transaction.replaceWriterLeaseIfCurrent(
        ownerUserId: current.ownerUserId,
        expectedLeaseOwnerId: current.leaseOwnerId,
        expectedFencingToken: current.fencingToken,
        replacement: replacement,
      );
      return replaced ? ImWriterLease.fromRecord(replacement) : null;
    });
  }

  Future<bool> isCurrent({
    required ImWriterLease lease,
    required int nowMs,
  }) async {
    final owner = _required(lease.ownerUserId, 'ownerUserId');
    return _store.transaction<bool>((transaction) async {
      final current = await transaction.findWriterLease(owner);
      return current != null &&
          current.leaseOwnerId == lease.leaseOwnerId &&
          current.fencingToken == lease.fencingToken &&
          !current.isExpiredAt(nowMs);
    });
  }

  Future<bool> release(ImWriterLease lease) {
    return _store.transaction<bool>((transaction) {
      return transaction.deleteWriterLeaseIfCurrent(
        ownerUserId: lease.ownerUserId,
        leaseOwnerId: lease.leaseOwnerId,
        fencingToken: lease.fencingToken,
      );
    });
  }
}

String _required(String value, String name) {
  final normalized = ChatIdFormat.rawUserUid(value);
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return normalized;
}

String _requiredOpaque(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return normalized;
}

void _validateTimes({required int nowMs, required int ttlMs}) {
  if (nowMs < 0) throw ArgumentError.value(nowMs, 'nowMs');
  if (ttlMs <= 0) throw ArgumentError.value(ttlMs, 'ttlMs');
}
