import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'account_scoped_conversation_key.dart';

const String kOutgoingIdentitySchema = '99chat.outgoing.v1';

/// Creates an Outbox key that is independent of Tencent's process-local
/// `created_temp_id-*` message IDs. The value is persisted with both Outbox
/// copies and reused for recovery, so a restart cannot collide with a prior
/// send in the same conversation.
String newOutgoingOperationId() => 'send_${const Uuid().v4()}';

/// Correlation IDs are also per-send identities; the SDK local ID is only a
/// provider handle and is not stable across process restarts.
String newOutgoingClientCorrelationId() => 'client_${const Uuid().v4()}';

enum OutgoingMessageKind { text, image, video, audio, custom }

/// Cross-process and cross-platform identity for one outbound operation.
///
/// Only [toCloudCustomData] belongs in Tencent's cloudCustomData. Local file
/// paths, credentials, message bodies and page objects are deliberately absent.
class OutgoingIdentityContract {
  factory OutgoingIdentityContract({
    required AccountScopedConversationKey scope,
    required String operationId,
    required String clientCorrelationId,
    required OutgoingMessageKind messageKind,
    required String payloadFingerprint,
    required int createdAtMs,
    String? sdkLocalId,
    String? serverMsgId,
  }) {
    final operation = _requiredId(operationId, 'operationId');
    final correlation = _requiredId(
      clientCorrelationId,
      'clientCorrelationId',
    );
    final fingerprint = _requiredId(payloadFingerprint, 'payloadFingerprint');
    if (createdAtMs < 0) {
      throw ArgumentError.value(
          createdAtMs, 'createdAtMs', 'must be non-negative');
    }
    return OutgoingIdentityContract._(
      scope: scope,
      operationId: operation,
      clientCorrelationId: correlation,
      messageKind: messageKind,
      payloadFingerprint: fingerprint,
      createdAtMs: createdAtMs,
      sdkLocalId: _optionalId(sdkLocalId),
      serverMsgId: _optionalId(serverMsgId),
    );
  }

  const OutgoingIdentityContract._({
    required this.scope,
    required this.operationId,
    required this.clientCorrelationId,
    required this.messageKind,
    required this.payloadFingerprint,
    required this.createdAtMs,
    required this.sdkLocalId,
    required this.serverMsgId,
  });

  final AccountScopedConversationKey scope;
  final String operationId;
  final String clientCorrelationId;
  final OutgoingMessageKind messageKind;
  final String payloadFingerprint;
  final int createdAtMs;
  final String? sdkLocalId;
  final String? serverMsgId;

  Map<String, Object?> toCloudCustomData({String? businessCloudCustomData}) {
    final data = <String, Object?>{};
    final business = businessCloudCustomData?.trim() ?? '';
    if (business.isNotEmpty) {
      try {
        final decoded = jsonDecode(business);
        if (decoded is Map) {
          // UIKit consumes messageReply/messageFeature at the JSON root. Do
          // not hide application metadata inside a string-valued `business`
          // field or every quoted/replied message loses its protocol shape.
          for (final entry in decoded.entries) {
            final key = entry.key?.toString() ?? '';
            if (key.isNotEmpty) data[key] = entry.value;
          }
        } else {
          data['business'] = business;
        }
      } catch (_) {
        // Preserve non-JSON legacy metadata without making a normal send fail.
        data['business'] = business;
      }
    }

    // Correlation fields are reserved and authoritative even if a business
    // payload accidentally contains fields with the same names.
    data.addAll(<String, Object?>{
      'schema': kOutgoingIdentitySchema,
      'operationId': operationId,
      'clientCorrelationId': clientCorrelationId,
      'messageKind': messageKind.name,
      'payloadFingerprint': payloadFingerprint,
      'createdAtMs': createdAtMs,
    });
    return data;
  }

  String encodeCloudCustomData({String? businessCloudCustomData}) => jsonEncode(
        toCloudCustomData(businessCloudCustomData: businessCloudCustomData),
      );

  static OutgoingIdentityContract? fromCloudCustomData(
    String? raw, {
    required AccountScopedConversationKey scope,
  }) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['schema'] != kOutgoingIdentitySchema) return null;
      final kindName = map['messageKind'] ?? map['messageType'];
      final kind = OutgoingMessageKind.values.firstWhere(
        (value) => value.name == kindName?.toString(),
        orElse: () => throw const FormatException('unknown message kind'),
      );
      final createdAtMs = _asInt(map['createdAtMs']);
      if (createdAtMs == null) return null;
      return OutgoingIdentityContract(
        scope: scope,
        operationId: map['operationId']?.toString() ?? '',
        clientCorrelationId: map['clientCorrelationId']?.toString() ?? '',
        messageKind: kind,
        payloadFingerprint: map['payloadFingerprint']?.toString() ?? '',
        createdAtMs: createdAtMs,
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  OutgoingIdentityContract withFormalIdentity({
    String? sdkLocalId,
    String? serverMsgId,
  }) {
    return OutgoingIdentityContract(
      scope: scope,
      operationId: operationId,
      clientCorrelationId: clientCorrelationId,
      messageKind: messageKind,
      payloadFingerprint: payloadFingerprint,
      createdAtMs: createdAtMs,
      sdkLocalId: sdkLocalId ?? this.sdkLocalId,
      serverMsgId: serverMsgId ?? this.serverMsgId,
    );
  }

  bool matchesCandidate({
    required AccountScopedConversationKey candidateScope,
    required OutgoingMessageKind candidateKind,
    required String candidatePayloadFingerprint,
    String? candidateCorrelationId,
  }) {
    return scope == candidateScope &&
        messageKind == candidateKind &&
        payloadFingerprint == candidatePayloadFingerprint &&
        (candidateCorrelationId == null ||
            candidateCorrelationId == clientCorrelationId);
  }

  Map<String, Object?> toMetadataJson() => <String, Object?>{
        ...toCloudCustomData(),
        'ownerUserId': scope.ownerUserId,
        'conversationKey': scope.canonicalConversationId,
        'sdkLocalId': sdkLocalId,
        'serverMsgId': serverMsgId,
      };
}

String _requiredId(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return normalized;
}

String? _optionalId(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

/// Legacy deterministic key retained only for rows written before UUID send
/// identities were introduced. New sends use [newOutgoingOperationId].
String hashOutgoingOperationId({
  required AccountScopedConversationKey scope,
  required String sdkLocalId,
}) {
  final localId = sdkLocalId.trim();
  if (localId.isEmpty) {
    throw ArgumentError.value(sdkLocalId, 'sdkLocalId', 'must not be empty');
  }
  final digest = sha256
      .convert(utf8.encode('send|${scope.storageKey}|$localId'))
      .toString()
      .substring(0, 32);
  return 'send_$digest';
}

String hashOutgoingClientCorrelationId(String sdkLocalId) {
  final localId = sdkLocalId.trim();
  if (localId.isEmpty) {
    throw ArgumentError.value(sdkLocalId, 'sdkLocalId', 'must not be empty');
  }
  final digest = sha256.convert(utf8.encode('client|$localId')).toString();
  return 'client_${digest.substring(0, 24)}';
}
