import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/recovery_log_buffer.dart';
import 'package:tencent_cloud_chat_demo/src/services/recovery_log_file.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_recovery_trace.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_history_recovery_notice.dart';

void main() {
  tearDown(() => ChatRecoveryTrace.sink = null);

  test(
      'logging survives disabled console and failing sink, bounded and redacted',
      () {
    ChatRecoveryTrace.sink = (_) => throw StateError('full disk');
    expect(
        () => ChatRecoveryTrace.log('sdk_failed',
                conversationID: 'c2c_peer',
                fields: {
                  'message': 'token=SECRET https://private/file',
                  'body': 'private text',
                  'code': 6005,
                  'payload': 'private payload'
                }),
        returnsNormally);
    final event = ChatRecoveryTrace.recentEvents.last;
    expect(event, contains('code=6005'));
    expect(event, isNot(contains('SECRET')));
    expect(event, isNot(contains('https://private')));
    expect(event, isNot(contains('private text')));
    for (var n = 0; n < 300; n++) {
      ChatRecoveryTrace.log('test',
          conversationID: 'peer', fields: {'index': n});
    }
    expect(ChatRecoveryTrace.recentEvents.length, ChatRecoveryTrace.capacity);
    expect(ChatRecoveryTrace.recentEvents.last, contains('index=299'));
  });

  test('recovery events carry a monotonic process timestamp', () {
    ChatRecoveryTrace.log('clock_first', conversationID: 'c');
    final first = ChatRecoveryTrace.recentEvents.last;
    ChatRecoveryTrace.log('clock_second', conversationID: 'c');
    final second = ChatRecoveryTrace.recentEvents.last;
    int clock(String line) =>
        int.parse(RegExp(r'\bmonoUs=(\d+)').firstMatch(line)!.group(1)!);
    expect(clock(second), greaterThanOrEqualTo(clock(first)));
    expect(RegExp(r'\brun=\S+').firstMatch(first)!.group(0),
        RegExp(r'\brun=\S+').firstMatch(second)!.group(0));
  });

  test('failed file write retries in order and does not poison later events',
      () async {
    var calls = 0;
    final saved = <String>[];
    final buffer = RecoveryLogBuffer(write: (batch) async {
      if (++calls == 1) throw FileSystemException('temporarily unavailable');
      saved.addAll(batch);
    });
    addTearDown(buffer.dispose);
    buffer.add('first');
    await buffer.flush();
    expect(buffer.failureCount, 1);
    buffer.add('second');
    await buffer.flush();
    expect(saved, ['first', 'second']);
    expect(buffer.pendingCount, 0);
  });

  test('hung file writer stays single with a bounded queue and resumes later',
      () async {
    final gate = Completer<void>();
    var calls = 0;
    final saved = <String>[];
    final buffer = RecoveryLogBuffer(
        capacity: 3,
        write: (batch) async {
          calls++;
          if (calls == 1) await gate.future;
          saved.addAll(batch);
        });
    addTearDown(buffer.dispose);
    buffer.add('first');
    final write = buffer.flush();
    for (var n = 0; n < 10; n++) {
      buffer.add('event$n');
    }
    expect(buffer.flush(), same(write));
    expect(calls, 1);
    expect(buffer.pendingCount, 3);
    expect(buffer.droppedCount, 7);
    gate.complete();
    await write;
    await buffer.flush();
    expect(saved, ['first', 'event7', 'event8', 'event9']);
  });

  test('rotated files are bounded, survive restart and preserve UTF-8',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('chat-recovery-log-');
    addTearDown(() => directory.delete(recursive: true));
    final store =
        RecoveryLogFile(directory: () async => directory, maxBytes: 120);
    for (var n = 0; n < 30; n++) {
      await store.append(['event=$n 消息重试记录']);
    }
    final restarted =
        RecoveryLogFile(directory: () async => directory, maxBytes: 120);
    final text = await restarted.read();
    expect(text, contains('event=29 消息重试记录'));
    expect(text, isNot(contains('event=0 ')));
    final files =
        await Directory('${directory.path}/chat_recovery').list().toList();
    expect(files, hasLength(2));
    for (final file in files.cast<File>()) {
      expect(await file.length(), lessThanOrEqualTo(120));
    }
  });

  testWidgets('slow initial history reports progress before offering retry',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChatHistoryRecoveryNotice(
                conversationID: 'peer', onRetry: () async {}))));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('正在加载消息…'), findsOneWidget);
    expect(find.text('重新加载'), findsNothing);
    await tester.pump(const Duration(seconds: 9));
    expect(find.text('重新加载'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
