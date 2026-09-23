import 'dart:async';

import 'package:tencent_cloud_chat_uikit/data_services/message/outgoing_message_send_queue.dart';
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

  test('compression keeps progressing while all three upload slots are busy',
      () async {
    final prep = OutgoingMediaWorkQueue.imagePreparation;
    expect(prep.maxConcurrent, 2);
    final uploads = OutgoingMessageSendQueue.instance;
    final gates = List.generate(6, (_) => Completer<void>());
    final preparation = List.generate(6, (_) => Completer<void>());
    final prepared = <int>[];
    final uploading = <int>[];
    var activePrep = 0;
    var peakPrep = 0;
    final jobs = List.generate(6, (i) async {
      await prep.run(() async {
        activePrep++;
        if (activePrep > peakPrep) peakPrep = activePrep;
        await preparation[i].future;
        prepared.add(i);
        activePrep--;
      });
      await uploads.runMedia('image', () async {
        uploading.add(i);
        await gates[i].future;
      });
    });
    expect(activePrep, 2);
    preparation[0].complete();
    await Future<void>.delayed(Duration.zero);
    expect(uploading, [0]); // first image uploads before the batch is ready
    expect(prepared, [0]);
    for (final gate in preparation.skip(1)) {
      gate.complete();
    }
    await Future<void>.delayed(Duration.zero);
    expect(prepared.length, 6);
    expect(uploading.length, 3);
    expect(peakPrep, 2);
    for (final gate in gates) {
      gate.complete();
    }
    await Future.wait(jobs);
  });

  test('slow video does not block image or file lanes', () async {
    final queue = OutgoingMessageSendQueue.instance;
    final gate = Completer<void>();
    final video = queue.runMedia('video', () => gate.future);
    var secondVideoStarted = false;
    final second = queue.runMedia('video', () async {
      secondVideoStarted = true;
    });
    expect(await queue.runMedia('image', () async => 'image'), 'image');
    expect(await queue.runMedia('file', () async => 'file'), 'file');
    expect(secondVideoStarted, isFalse);
    gate.complete();
    await Future.wait([video, second]);
    expect(secondVideoStarted, isTrue);
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
