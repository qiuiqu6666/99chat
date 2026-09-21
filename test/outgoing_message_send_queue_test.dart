import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/outgoing_message_send_queue.dart';

void main() {
  tearDown(OutgoingMessageSendQueue.instance.resetForTesting);

  test('runSerial starts tasks in order for same conversation', () async {
    final starts = <int>[];
    final queue = OutgoingMessageSendQueue.instance;
    const key = 'group:test';

    final first = queue.runSerial(key, () async {
      starts.add(1);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return 1;
    });
    final second = queue.runSerial(key, () async {
      starts.add(2);
      return 2;
    });
    final third = queue.runSerial(key, () async {
      starts.add(3);
      return 3;
    });

    expect(await first, 1);
    expect(await second, 2);
    expect(await third, 3);
    expect(starts, <int>[1, 2, 3]);
  });

  test('runSerial allows parallel sends for different conversations', () async {
    final order = <String>[];
    final queue = OutgoingMessageSendQueue.instance;

    await Future.wait(<Future<void>>[
      queue.runSerial('group:a', () async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        order.add('a');
      }),
      queue.runSerial('group:b', () async {
        order.add('b');
      }),
    ]);

    expect(order.first, 'b');
    expect(order.last, 'a');
  });

  test('runSerial continues chain after failure', () async {
    final order = <int>[];
    final queue = OutgoingMessageSendQueue.instance;
    const key = 'c2c:user';

    final first = queue.runSerial(key, () async {
      order.add(1);
      throw StateError('send failed');
    });
    final second = queue.runSerial(key, () async {
      order.add(2);
      return 2;
    });

    await expectLater(first, throwsStateError);
    expect(await second, 2);
    expect(order, <int>[1, 2]);
  });

  test('stuck upload does not block the next SDK send', () async {
    final queue = OutgoingMessageSendQueue.instance;
    final firstResult = Completer<int>();
    final starts = <String>[];
    const key = 'group:stuck-upload';

    final first = queue.runSerial(
      key,
      () {
        starts.add('media');
        return firstResult.future;
      },
      dispatchTimeout: const Duration(milliseconds: 30),
    );
    final second = queue.runSerial(key, () async {
      starts.add('text');
      return 2;
    });

    final firstFailed = expectLater(first, throwsA(isA<TimeoutException>()));
    expect(await second, 2);
    expect(starts, <String>['media', 'text']);
    await firstFailed;

    // A timeout cannot cancel the native Future; consume its late completion.
    firstResult.complete(1);
    await Future<void>.delayed(Duration.zero);
  });

  test('completed conversation tails are evicted', () async {
    final queue = OutgoingMessageSendQueue.instance;
    const key = 'c2c:evicted';

    await queue.runSerial(key, () async => 1);
    await Future<void>.delayed(Duration.zero);

    expect(queue.hasPending(key), isFalse);
  });

  test('conversationKey prefers group id', () {
    expect(
      OutgoingMessageSendQueue.conversationKey(
        receiver: 'user_a',
        groupID: '@TGS#abc',
      ),
      'group:@TGS#abc',
    );
    expect(
      OutgoingMessageSendQueue.conversationKey(
        receiver: 'user_a',
        groupID: '',
      ),
      'c2c:user_a',
    );
  });
}
