import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';

void main() {
  final bus = PeerProfileRefreshBus.instance;
  setUp(bus.clear);

  test(
      'async batch deduplicates nested saves and leaves independent changes immediate',
      () async {
    final release = Completer<void>();
    final entered = Completer<void>();
    final before = bus.revision.value;
    final batch = bus.batch(() async {
      bus.notify('a');
      entered.complete();
      await release.future;
      bus.notifyMany(['a', 'b']);
      await bus.batch(() async {
        bus.notify('c');
      }, isCurrent: () => true);
    }, isCurrent: () => true);
    await entered.future;
    expect(bus.revision.value, before);
    bus.notify('independent');
    expect(bus.revision.value, before + 1);
    expect(bus.latestChangedUserIds, {'independent'});
    release.complete();
    await batch;
    expect(bus.revision.value, before + 2);
    expect(bus.latestChangedUserIds, {'a', 'b', 'c'});
  });

  test('partial failure publishes applied changes and releases the batch',
      () async {
    final before = bus.revision.value;
    await expectLater(
        bus.batch<void>(() async {
          bus.notify('applied');
          throw StateError('later event failed');
        }, isCurrent: () => true),
        throwsStateError);
    expect(bus.revision.value, before + 1);
    expect(bus.latestChangedUserIds, {'applied'});
    bus.notify('next');
    expect(bus.revision.value, before + 2);
    expect(bus.latestChangedUserIds, {'next'});
  });

  test('account switch discards old batch and its late async notification',
      () async {
    var current = true;
    final before = bus.revision.value;
    final release = Completer<void>();
    late Future<void> lateNotification;
    await bus.batch(() async {
      bus.notify('old');
      lateNotification = release.future.then((_) => bus.notify('late-old'));
      current = false;
    }, isCurrent: () => current);
    expect(bus.revision.value, before);
    release.complete();
    await lateNotification;
    expect(bus.revision.value, before);
    await bus.batch(() async {
      bus.notify('new');
    }, isCurrent: () => true);
    expect(bus.latestChangedUserIds, {'new'});
    expect(bus.revision.value, before + 1);
  });
}
