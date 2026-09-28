import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_recovery_trace.dart';

import 'recovery_log_buffer.dart';
import 'api_failure_diagnostics.dart';
import 'im/message_persist_coordinator.dart';
import 'recovery_log_file_stub.dart'
    if (dart.library.io) 'recovery_log_file.dart';

class ChatRecoveryDiagnostics {
  ChatRecoveryDiagnostics._();
  static final _file = RecoveryLogFile();
  static final _buffer = RecoveryLogBuffer(write: _file.append);
  static bool _installed = false;

  static void install() {
    if (_installed) return;
    _installed = true;
    for (final event in ChatRecoveryTrace.recentEvents) {
      _buffer.add(event);
    }
    ChatRecoveryTrace.sink = _buffer.add;
    ChatRecoveryTrace.log('diagnostics_started', conversationID: '', fields: {
      'platform': defaultTargetPlatform.name,
      'release': kReleaseMode
    });
  }

  /// An unavailable disk/plugin must still allow a bounded in-memory export.
  static Future<String> export() async {
    install();
    final details = await Future.wait<String>([
      () async {
        try {
          final info = await PackageInfo.fromPlatform()
              .timeout(const Duration(seconds: 2));
          return '${info.version}+${info.buildNumber}';
        } catch (_) {
          return 'unavailable';
        }
      }(),
      () async {
        try {
          await _buffer.flush().timeout(const Duration(seconds: 2));
          return await _file.read().timeout(const Duration(seconds: 2));
        } catch (_) {
          return '[Local file unavailable; current session follows]';
        }
      }(),
    ]);
    return 'Chat recovery report v1\n'
        'exported=${DateTime.now().toUtc().toIso8601String()}\n'
        'app=${details[0]} platform=${defaultTargetPlatform.name} web=$kIsWeb release=$kReleaseMode\n'
        'pending=${_buffer.pendingCount} writing=${_buffer.writing} '
        'dropped=${_buffer.droppedCount} storageFailures=${_buffer.failureCount}\n\n'
        '--- Message persistence (live snapshot) ---\n'
        '${jsonEncode(MessagePersistCoordinator.instance.diagnosticSnapshot)}\n\n'
        '--- Saved events ---\n${details[1]}\n'
        '--- Current session (may overlap saved events) ---\n'
        '${ChatRecoveryTrace.recentEvents.join('\n')}\n'
        '${await ApiFailureDiagnostics.export()}';
  }
}
