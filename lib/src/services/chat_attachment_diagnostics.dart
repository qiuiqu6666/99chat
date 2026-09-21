import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Only allowlisted capability/policy values are logged. Never log payloads,
/// file names, user IDs, JWTs, device IDs or signed object-storage URLs.
class ChatAttachmentDiagnostics {
  static void policyResponse(
      {required int? status,
      required Map<String, dynamic> headers,
      required dynamic payload}) {
    final data = payload is Map ? payload : const {};
    final normalized =
        headers.map((key, value) => MapEntry(key.toLowerCase(), value));
    final native = data['nativeMaxBytes'];
    event('policy_response', {
      'httpStatus': status,
      'platform': _token(normalized['x-client-platform']),
      'appVersion': _token(normalized['x-app-version']),
      'buildNumber': _token(normalized['x-app-version-code']),
      'protocolVersion':
          _token(normalized['x-chat-attachment-protocol-version']),
      'deviceIdPresent':
          normalized['x-device-id']?.toString().isNotEmpty == true,
      for (final key in ['uploadEnabled', 'sendEnabled', 'readEnabled'])
        key: data[key] is bool ? data[key] : 'missing_or_invalid',
      'sizeComparison': data['sizeComparison'] == 'strictGreaterThan'
          ? 'strictGreaterThan'
          : 'missing_or_unsupported',
      'routingThresholdBytes': _number(data['routingThresholdBytes']),
      'nativeMaxBytes': {
        for (final kind in ['image', 'sound', 'video', 'file'])
          kind: _number(native is Map ? native[kind] : null),
      },
    });
  }

  static void event(String event, Map<String, Object?> fields) {
    debugPrint('[ChatAttachment] ${jsonEncode({'event': event, ...fields})}');
  }

  static Object _number(dynamic value) =>
      value is int ? value : 'missing_or_invalid';
  static String _token(dynamic value) {
    final text = value?.toString() ?? '';
    return RegExp(r'^[a-zA-Z0-9.+_-]{1,40}$').hasMatch(text)
        ? text
        : 'missing_or_invalid';
  }
}
