import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/chat_page/chat_open_lifecycle.dart';
import 'package:tencent_cloud_chat_demo/src/chat_page/chat_mute_refresh_queue.dart';

void main() {
  test('mute and unmute can refresh repeatedly without leaving the page',
      () async {
    final queue = ChatMuteRefreshQueue();
    final applied = <int>[];
    for (final value in [0, 300, 0, 600, 0]) {
      await queue.refresh((isCurrent) async {
        if (isCurrent()) applied.add(value);
      });
    }
    expect(applied, [0, 300, 0, 600, 0]);
  });

  test('events during a fetch coalesce and invalidate its stale response',
      () async {
    final queue = ChatMuteRefreshQueue();
    final response = Completer<void>();
    final applied = <int>[];
    var requests = 0;
    final first = queue.refresh((isCurrent) async {
      requests++;
      await response.future;
      if (isCurrent()) applied.add(300);
    });
    for (final value in [0, 600, 0]) {
      final pending = queue.refresh((isCurrent) async {
        requests++;
        if (isCurrent()) applied.add(value);
      });
      expect(identical(first, pending), isTrue);
    }
    expect(requests, 1);
    response.complete();
    await first;
    expect(requests, 2);
    expect(applied, [0]);
  });

  test('new event during publication prevents a delayed model update',
      () async {
    final queue = ChatMuteRefreshQueue();
    final localWrite = Completer<void>();
    final applied = <String>[];
    final first = queue.refresh((isCurrent) async {
      expect(isCurrent(), isTrue);
      await localWrite.future;
      if (isCurrent()) applied.add('old');
    });
    queue.refresh((isCurrent) async {
      if (isCurrent()) applied.add('new');
    });
    localWrite.complete();
    await first;
    expect(applied, ['new']);
  });

  test('leaving and reopening invalidates the old request and its cleanup',
      () async {
    final life = ChatOpenLifecycle();
    final oldResponse = Completer<void>();
    final newResponse = Completer<void>();
    final applied = <String>[];
    final oldTask = life.muteRefreshQueue.refresh((isCurrent) async {
      await oldResponse.future;
      if (isCurrent()) applied.add('old');
    });
    life.beginConversation();
    final newTask = life.muteRefreshQueue.refresh((isCurrent) async {
      await newResponse.future;
      if (isCurrent()) applied.add('new');
    });
    oldResponse.complete();
    await oldTask;
    final latestTask = life.muteRefreshQueue.refresh((isCurrent) async {
      if (isCurrent()) applied.add('latest');
    });
    expect(identical(newTask, latestTask), isTrue);
    newResponse.complete();
    await latestTask;
    expect(applied, ['latest']);
  });

  test('null result and failure do not latch subsequent refreshes', () async {
    final queue = ChatMuteRefreshQueue();
    await queue.refresh((_) async {});
    await expectLater(queue.refresh((_) async => throw StateError('offline')),
        throwsStateError);
    var applied = false;
    await queue.refresh((isCurrent) async => applied = isCurrent());
    expect(applied, isTrue);
  });

  test('disposal discards both running and queued work', () async {
    final life = ChatOpenLifecycle();
    final response = Completer<void>();
    var publications = 0;
    final first = life.muteRefreshQueue.refresh((isCurrent) async {
      await response.future;
      if (isCurrent()) publications++;
    });
    life.muteRefreshQueue.refresh((_) async => publications++);
    life.resetForDispose();
    response.complete();
    await first;
    expect(publications, 0);
  });
}
