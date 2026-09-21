import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/outgoing_media_work_queue.dart';

void main() {
  test('prepared media starts immediately while later items are still pending',
      () async {
    final queue = OutgoingMediaWorkQueue(maxConcurrent: 1);
    final upload = Completer<void>();
    final starts = <int>[];
    final first = queue.run(() async {
      starts.add(1);
      await upload.future;
    });
    expect(starts, [1]);
    final second = queue.run(() async {
      starts.add(2);
    });
    expect(starts, [1]);
    upload.complete();
    await Future.wait([first, second]);
    expect(starts, [1, 2]);
  });

  test('concurrency remains bounded across independent batches', () async {
    final queue = OutgoingMediaWorkQueue(maxConcurrent: 3);
    final gates = List.generate(8, (_) => Completer<void>());
    var active = 0;
    var peak = 0;
    final jobs = List.generate(
        8,
        (i) => queue.run(() async {
              active++;
              if (active > peak) peak = active;
              await gates[i].future;
              active--;
              return i;
            }));
    expect(active, 3);
    for (final gate in gates) {
      gate.complete();
    }
    expect(await Future.wait(jobs), List.generate(8, (i) => i));
    expect(peak, 3);
    expect(active, 0);
  });

  test('failed preparation releases its slot for later media', () async {
    final queue = OutgoingMediaWorkQueue(maxConcurrent: 1);
    final fail = Completer<void>();
    final first = queue.run(() async {
      await fail.future;
      throw StateError('bad media');
    });
    final assertion = expectLater(first, throwsStateError);
    final next = queue.run(() async => 'sent');
    fail.complete();
    await assertion;
    expect(await next, 'sent');
  });
}
