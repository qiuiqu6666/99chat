import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_inline_watch_banner.dart';

void main() {
  test('poll joins active load and explicit reload keeps only latest request',
      () async {
    final gate = GroupLiveLoadGate();
    final releaseFirst = Completer<void>();
    final calls = <String>[];

    final first = gate.run(() async {
      calls.add('first');
      await releaseFirst.future;
    });
    final poll = gate.run(() async {
      calls.add('poll');
    });
    final supersededReload = gate.run(
      () async => calls.add('superseded'),
      queueLatestIfBusy: true,
    );
    final latestReload = gate.run(
      () async => calls.add('latest'),
      queueLatestIfBusy: true,
    );

    expect(gate.isBusy, isTrue);
    expect(calls, <String>['first']);

    releaseFirst.complete();
    await Future.wait<void>(
      <Future<void>>[first, poll, supersededReload, latestReload],
    );

    expect(calls, <String>['first', 'latest']);
    expect(gate.isBusy, isFalse);
  });
}
