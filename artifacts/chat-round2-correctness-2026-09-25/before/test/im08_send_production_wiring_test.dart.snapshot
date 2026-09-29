import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every UIKit send invocation supplies a durable message envelope', () {
    for (final path in <String>[
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
          'separate_models/tui_chat_separate_view_model.dart',
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
          'view_models/tui_chat_global_model.dart',
    ]) {
      final source = File(path).readAsStringSync();
      final starts = RegExp(r'(?:return|await)\s+_sendMessage\(')
          .allMatches(source)
          .map((match) => source.indexOf('_sendMessage(', match.start));
      for (final start in starts) {
        final invocation = _balancedInvocation(source, start);
        expect(invocation, contains('messageInfo:'), reason: path);
      }
    }
  });

  test('raw SDK send and resend stay inside the Tencent adapter boundary', () {
    const allowed = <String>{
      'lib/src/services/im/tencent_message_adapter.dart',
      'third_party/tencent_cloud_chat_uikit/lib/data_services/message/'
          'message_service_implement.dart',
    };
    final actual = <String>{};
    final rawSend = RegExp(r'\.(?:sendMessage|reSendMessage)\(');
    for (final root in <String>[
      'lib',
      'third_party/tencent_cloud_chat_uikit/lib'
    ]) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (rawSend.hasMatch(entity.readAsStringSync())) {
          actual.add(entity.path.replaceAll('\\', '/'));
        }
      }
    }
    expect(actual, allowed);
  });

  test('failed-message retry recreates and re-enters the Outbox', () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
      'separate_models/tui_chat_separate_view_model.dart',
    ).readAsStringSync();
    final start = source.indexOf('reSendFailMessage({');
    final end = source.indexOf(
        'Future<V2TimValueCallback<V2TimMessage>?> '
        'sendTextMessage',
        start);
    final retry = source.substring(start, end);
    expect(retry, contains('recreateOutgoingMessage('));
    expect(retry, contains('return _sendMessage('));
    expect(retry, isNot(contains('.reSendMessage(')));
    expect(retry, isNot(contains('.setMessageList(')));
  });
}

String _balancedInvocation(String source, int start) {
  final open = source.indexOf('(', start);
  var depth = 0;
  for (var index = open; index < source.length; index++) {
    switch (source.codeUnitAt(index)) {
      case 40:
        depth++;
        break;
      case 41:
        depth--;
        if (depth == 0) return source.substring(start, index + 1);
        break;
    }
  }
  throw StateError('unterminated _sendMessage invocation');
}
