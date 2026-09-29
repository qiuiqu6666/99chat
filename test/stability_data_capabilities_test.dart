import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_sync_collector.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_sync_plan.dart';
import 'package:tencent_cloud_chat_demo/src/services/photo_backup_progress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/contact_projection_merge.dart';

LocalContactRecord contact(String id, String hash) => LocalContactRecord(
    localContactId: id,
    displayName: id,
    phones: const ['123'],
    fingerprint: hash);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  tearDown(() => SqfliteLifecycleGuard.instance.debugReset());

  test(
      'device-scoped delta capability selects only changed rows, including true empty',
      () {
    final current = [
      contact('unchanged', '1'),
      contact('changed', 'new'),
      contact('added', '2')
    ];
    final previous = {'unchanged': '1', 'changed': 'old', 'removed': '3'};
    final delta = ContactSyncPlan.build(
        current: current,
        previous: previous,
        hasServerBaseline: true,
        deviceScopedDelta: true);
    expect(
        delta.uploads.map((row) => row.localContactId), ['changed', 'added']);
    expect(delta.deletedIds, ['removed']);
    final empty = ContactSyncPlan.build(
        current: [],
        previous: previous,
        hasServerBaseline: true,
        deviceScopedDelta: true);
    expect(empty.uploads, isEmpty);
    expect(empty.deletedIds, previous.keys);
    final unchanged = ContactSyncPlan.build(
        current: current,
        previous: delta.snapshot,
        hasServerBaseline: true,
        deviceScopedDelta: true);
    expect(unchanged.uploads, isEmpty);
    expect(unchanged.deletedIds, isEmpty);
    final production = ContactSyncPlan.build(
        current: current, previous: previous, hasServerBaseline: true);
    expect(production.uploads, current,
        reason: 'No server device-domain contract: capability stays OFF');
    expect(ContactSyncPlan.deviceScopedDeltaEnabled, isFalse);
  });

  for (final size in [1000, 5000, 10000]) {
    test(
        'geometric contact publication preserves order with bounded comparisons at $size',
        () {
      var current = <int>[];
      var cursor = 0;
      var copies = 0;
      var comparisons = 0;
      final source = List.generate(size, (i) => size - i);
      while (cursor < source.length) {
        final end = (cursor + contactProjectionPublishSize(current.length))
            .clamp(0, source.length);
        current = mergeContactProjection(current, source.sublist(cursor, end),
            (a, b) {
          comparisons++;
          return a.compareTo(b);
        });
        copies += current.length;
        cursor = end;
      }
      expect(current, List.generate(size, (i) => i + 1));
      expect(copies, lessThan(size * 3));
      expect(comparisons, lessThan(size * 25));
    });
  }

  test(
      'progress migration is idempotent and one-item updates survive reopen per owner',
      () async {
    final directory = await Directory.systemTemp.createTemp('photo_progress_');
    final store =
        PhotoBackupProgressStore(databasePath: '${directory.path}/progress.db');
    addTearDown(() async {
      await store.closeIfOpen();
      await directory.delete(recursive: true);
    });
    final legacy = {for (var i = 0; i < 1000; i++) 'asset-$i': 'v1'};
    await store.migrateLegacy('owner-a', legacy);
    await store.record('owner-a', 'asset-0', 'v2', status: 'uploaded');
    await store
        .migrateLegacy('owner-a', {'asset-0': 'old', 'uncommitted': 'old'});
    await store.record('owner-b', 'asset-0', 'other', status: 'too_large');
    await store.closeIfOpen();
    final a = await store.readOwner('owner-a');
    expect(a.length, 1000);
    expect(a['asset-0'], 'v2');
    expect(a['asset-999'], 'v1');
    expect((await store.readOwner('owner-b'))['asset-0'], 'other');
    await store.clearForOwner('owner-a');
    expect(await store.readOwner('owner-a'), isEmpty);
    expect((await store.readOwner('owner-b')).length, 1);
    expect(PhotoBackupProgressStore.enabled, isFalse,
        reason: 'W8 has not shipped');
  });

  test('progress writes respect pause, stale owner and serialized close',
      () async {
    final store = PhotoBackupProgressStore(databasePath: ':memory:');
    addTearDown(store.closeIfOpen);
    await store.record('owner', 'asset', 'v1', status: 'uploaded');
    SqfliteLifecycleGuard.instance.pauseWrites();
    await expectLater(store.record('owner', 'asset', 'v2', status: 'uploaded'),
        throwsA(isA<SqfliteClosedForBackground>()));
    SqfliteLifecycleGuard.instance.resume();
    await expectLater(
        store.record('owner', 'asset', 'v3',
            status: 'uploaded', isCurrent: () => false),
        throwsA(isA<SqfliteClosedForBackground>()));
    expect((await store.readOwner('owner'))['asset'], 'v1');
    await store.closeIfOpen();
  });
}
