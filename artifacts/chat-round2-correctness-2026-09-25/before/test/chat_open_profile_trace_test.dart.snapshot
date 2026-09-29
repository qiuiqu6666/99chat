import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_history_peek_loader.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final lines = <String>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ChatOpenPerfLog.resetForTest();
    lines.clear();
    ChatOpenPerfLog.debugSink = lines.add;
  });
  tearDown(() {
    ChatOpenPerfLog.resetForTest();
    ChatOpenPerfLog.debugSink = null;
  });

  ChatOpenTraceContext begin(String id) {
    ChatOpenPerfLog.beginOpen(conversationID: id, phase: 'test');
    return ChatOpenPerfLog.captureCurrent(conversationKey: id);
  }

  test('each open owns a unique trace even for the same conversation', () {
    final first = begin('c2c_alice');
    final second = begin('c2c_alice');
    expect(first.chatOpenTraceId, isNot(second.chatOpenTraceId));
    expect(
        ChatOpenPerfLog.captureCurrent(conversationKey: 'alice')
            .chatOpenTraceId,
        second.chatOpenTraceId);
    expect(
        ChatOpenPerfLog.captureCurrent(conversationKey: 'c2c_other')
            .chatOpenTraceId,
        '-');
  });

  test(
      'async work and nested spans keep their creating trace after another open',
      () async {
    final first = begin('c2c_alice');
    final gate = Completer<void>();
    final task = ChatOpenPerfLog.withTrace(
        first,
        () => ChatOpenPerfLog.measure('producer', () async {
              await gate.future;
              expect(
                  ChatOpenPerfLog.captureCurrent(conversationKey: 'alice')
                      .chatOpenTraceId,
                  first.chatOpenTraceId);
              await ChatOpenPerfLog.measure('sdk_local_read', () async => 7);
            }));
    final second = begin('c2c_bob');
    gate.complete();
    await task;
    final producer = lines.firstWhere(
        (l) => l.contains('event=span_start') && l.contains('stage=producer'));
    final producerId = RegExp(r'\bspanId=(\S+)').firstMatch(producer)!.group(1);
    final child = lines.firstWhere((l) =>
        l.contains('event=span_start') && l.contains('stage=sdk_local_read'));
    expect(child, contains('parentSpanId=$producerId'));
    expect(child, contains('chatOpenTraceId=${first.chatOpenTraceId}'));
    expect(child, isNot(contains(second.chatOpenTraceId)));
  });

  test('queue wait and execution are disjoint; finish is idempotent', () async {
    final trace = begin('c2c_alice');
    final span = ChatOpenPerfLog.queueSpan('producer', trace: trace)!;
    await Future<void>.value();
    span.start();
    await Future<void>.value();
    span.finish(extras: {'rawCount': 4});
    span.finish(outcome: 'error');
    final ends = lines.where((l) => l.contains('event=span_end')).toList();
    expect(ends, hasLength(1));
    int field(String name) =>
        int.parse(RegExp('$name=(\\d+)').firstMatch(ends.single)!.group(1)!);
    expect(field('totalUs'), field('queueWaitUs') + field('executionUs'));
    expect(ends.single, contains('outcome=completed'));
    expect(ends.single, contains('rawCount=4'));
  });

  test('measurement preserves the exception and records an error outcome',
      () async {
    begin('c2c_alice');
    final error = StateError('private payload');
    await expectLater(
        ChatOpenPerfLog.measure<void>('read', () async => throw error),
        throwsA(same(error)));
    expect(lines.last, contains('outcome=error'));
    expect(lines.join('\n'), isNot(contains('private payload')));
  });

  test('a caller timeout does not end or cancel the shared producer span',
      () async {
    begin('c2c_alice');
    final gate = Completer<int>();
    final task = ChatOpenPerfLog.measure('producer', () => gate.future);
    await expectLater(
        task.timeout(Duration.zero), throwsA(isA<TimeoutException>()));
    expect(lines.where((l) => l.contains('event=span_end')), isEmpty);
    gate.complete(3);
    expect(await task, 3);
    expect(lines.where((l) => l.contains('event=span_end')), hasLength(1));
  });

  test('profile diagnostics redact content and authentication fields', () {
    begin('c2c_private_owner');
    ChatOpenPerfLog.mark('diagnostic', extras: {
      'owner': 'private_owner',
      'serverMsgID': 'private_message',
      'text': 'private_text',
      'payload': 'private_payload',
      'accessToken': 'private_token',
      'userSig': 'private_signature',
      'url': 'https://private.invalid',
      'error': 'private_exception',
      'stage': 'sdk_local_read',
      'spanId': 'span_123',
      'queueWaitUs': 3,
    });
    expect(lines.join('\n'), isNot(contains('private_')));
    expect(lines.last, contains('payload=<redacted>'));
    expect(lines.last, contains('spanId=span_123'));
    expect(lines.last, contains('queueWaitUs=3'));
  });

  test('two joined requests log only one actual SDK call', () async {
    begin('c2c_profile_peer');
    final service = _ControlledHistoryService()..gate = Completer<void>();
    Future<V2TimMessageListResult> request() =>
        MessageHistoryPeekLoader.loadOlderLocalOnlyResult(
            messageService: service, count: 3, userID: 'profile_peer');
    final first = request();
    final second = request();
    expect(service.calls, 1);
    service.gate!.complete();
    await Future.wait([first, second]);
    expect(service.calls, 1);
    expect(lines.where((l) => l.contains('event=history_loader_reused')),
        hasLength(1));
    expect(
        lines.where((l) =>
            l.contains('event=span_start') &&
            l.contains('stage=sdk_local_call')),
        hasLength(1));
  });

  test('one paginated request logs each actual SDK call', () async {
    begin('group_profile_room');
    final service = _ControlledHistoryService()..paged = true;
    final result = await MessageHistoryPeekLoader.loadOlderLocalOnlyResult(
        messageService: service, count: 3, groupID: 'profile_room');
    expect(result.messageList, hasLength(3));
    expect(service.calls, 3);
    expect(
        lines.where((l) =>
            l.contains('event=span_start') &&
            l.contains('stage=sdk_local_call')),
        hasLength(3));
  });
}

class _ControlledHistoryService extends Fake implements MessageService {
  int calls = 0;
  bool paged = false;
  Completer<void>? gate;
  @override
  Future<V2TimMessageListResult?> getHistoryMessageListWithComplete({
    HistoryMsgGetTypeEnum getType =
        HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
    String? userID,
    String? groupID,
    int lastMsgSeq = 0,
    required int count,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    List<int>? messageTypeList,
    List<int>? messageSeqList,
    int? timeBegin,
    int? timePeriod,
  }) async {
    calls++;
    if (gate != null) await gate!.future;
    final seq = 4 - calls;
    final message = V2TimMessage.fromJson({'message_risk_type_identified': 0})
      ..msgID = 'message_$seq'
      ..seq = '$seq'
      ..timestamp = 100000 + seq
      ..elemType = 1;
    return V2TimMessageListResult(
        isFinished: !paged || calls >= 3, messageList: paged ? [message] : []);
  }
}
