import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_host.dart';
import 'support/controlled_database.dart' as fixture;

class _Database extends fixture.StalledAuditDatabase {
  int closes = 0;
  bool fail = false;
  @override
  Future<void> close() async {
    closes++;
    if (fail) throw StateError('native close failed');
    await super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Database db;
  DatabaseFactory? previous;
  setUp(() async {
    try {
      previous = databaseFactory;
    } catch (_) {}
    db = _Database();
    databaseFactory = fixture.AuditDatabaseFactory(db);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SqfliteLifecycleGuard.instance.debugReset();
    SqfliteLifecycleHost.debugReset();
    await FriendLocalStore.instance.readAll(ownerUserId: 'lifecycle-test');
  });
  tearDown(() async {
    if (!db.releaseClose.isCompleted) db.releaseClose.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    SqfliteLifecycleGuard.instance.debugReset();
    SqfliteLifecycleHost.debugReset();
    await FriendLocalStore.instance.closeIfOpen();
    databaseFactory = previous ?? databaseFactoryFfi;
    debugDefaultTargetPlatformOverride = null;
  });

  test(
      'pending native close bounds UI waits and 50 lifecycle changes retain one close',
      () async {
    await SqfliteLifecycleHost.handle(AppLifecycleState.paused,
        waitBudget: const Duration(milliseconds: 20));
    expect(SqfliteLifecycleHost.status.value, SqfliteLifecycleStatus.degraded);
    await Future.wait(List.generate(
        50,
        (i) => SqfliteLifecycleHost.handle(
            i.isEven ? AppLifecycleState.paused : AppLifecycleState.resumed,
            waitBudget: const Duration(milliseconds: 10))));
    expect(
        await SqfliteLifecycleHost.waitForWrites(
            timeout: const Duration(milliseconds: 20)),
        SqfliteWriteGateResult.deferred);
    expect(db.closes, 1);
    expect(SqfliteLifecycleGuard.instance.canOpenDatabase, isFalse);
    expect(() => SqfliteLifecycleGuard.beforeOpen(db),
        throwsA(isA<SqfliteClosedForBackground>()));
    var current = true;
    final old = SqfliteLifecycleHost.waitForWrites(
        timeout: const Duration(milliseconds: 20), isCurrent: () => current);
    current = false;
    expect(await old, SqfliteWriteGateResult.cancelled);
    db.releaseClose.complete();
    expect(await SqfliteLifecycleHost.waitForWrites(),
        SqfliteWriteGateResult.ready);
    expect(SqfliteLifecycleHost.status.value, SqfliteLifecycleStatus.ready);
    expect(db.closes, 1);
  });

  test('late native close follows latest background state', () async {
    await SqfliteLifecycleHost.handle(AppLifecycleState.paused,
        waitBudget: const Duration(milliseconds: 10));
    await SqfliteLifecycleHost.handle(AppLifecycleState.resumed,
        waitBudget: const Duration(milliseconds: 10));
    await SqfliteLifecycleHost.handle(AppLifecycleState.paused,
        waitBudget: const Duration(milliseconds: 10));
    db.releaseClose.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(SqfliteLifecycleGuard.instance.writesAllowed, isFalse);
    await SqfliteLifecycleHost.handle(AppLifecycleState.resumed);
    expect(SqfliteLifecycleGuard.instance.writesAllowed, isTrue);
  });

  test('failed close of an open handle never permits reopen', () async {
    db.fail = true;
    await SqfliteLifecycleHost.handle(AppLifecycleState.paused);
    await SqfliteLifecycleHost.handle(AppLifecycleState.resumed);
    expect(SqfliteLifecycleHost.status.value, SqfliteLifecycleStatus.degraded);
    expect(await SqfliteLifecycleHost.waitForWrites(),
        SqfliteWriteGateResult.deferred);
    expect(SqfliteLifecycleGuard.instance.canOpenDatabase, isFalse);
    expect(db.closes, 1);
  });
}
