import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'im05_contracts.dart';

/// A failure attempt, not a storage snapshot version, owns its retry slot.
/// Copy rebuilds and metadata writes may advance stateVersion without creating
/// a new business failure or granting another SDK send.
String? outboxRetryKey(ImOutboxRecord parent) {
  final attempt = parent.dispatchAttemptId?.trim();
  if (attempt == null || attempt.isEmpty) return null;
  return sha256
      .convert(utf8.encode(
          '${parent.ownerUserId}|${parent.operationId}|attempt:$attempt'))
      .toString();
}

String? outboxRetryOperationId(ImOutboxRecord parent) {
  final key = outboxRetryKey(parent);
  return key == null ? null : 'retry_$key';
}

/// Recognizes a prepared child written by the earlier version-based scheme.
/// It is only a compatibility test; new sends use the stable attempt key.
String legacyOutboxRetryOperationId(
    String ownerUserId, String parentOperationId, int stateVersion) {
  final key = sha256
      .convert(utf8.encode('$ownerUserId|$parentOperationId|$stateVersion'))
      .toString();
  return 'retry_$key';
}
