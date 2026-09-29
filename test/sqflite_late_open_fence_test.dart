import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_host.dart';
import 'support/controlled_database.dart' as f;

class _OpeningFactory extends f.AuditDatabaseFactory {
  _OpeningFactory(super.db);
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<Database> openDatabase(String path,
      {OpenDatabaseOptions? options}) async {
    started.complete();
    await release.future;
    return db;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a late conversation open retains the actual fence through its close',
      () async {
    DatabaseFactory? previous;
    try {
      previous = databaseFactory;
    } catch (_) {}
    final db = f.StalledAuditDatabase();
    final factory = _OpeningFactory(db);
    databaseFactory = factory;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SqfliteLifecycleHost.debugReset();
    SqfliteLifecycleGuard.instance.debugReset();
    final store = ConversationLocalStore.instance;
    final warmup = store.warmFirstScreenIndex();
    try {
      await factory.started.future;
      await SqfliteLifecycleHost.handle(AppLifecycleState.paused,
          waitBudget: const Duration(milliseconds: 10));
      await SqfliteLifecycleHost.handle(AppLifecycleState.resumed,
          waitBudget: const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(SqfliteLifecycleGuard.instance.canOpenDatabase, isFalse);
      expect(SqfliteLifecycleHost.pendingStores, contains('conversation'));
      factory.release.complete();
      await db.closeStarted.future.timeout(const Duration(seconds: 2));
      expect(SqfliteLifecycleGuard.instance.canOpenDatabase, isFalse);
      db.releaseClose.complete();
      await warmup;
      expect(await SqfliteLifecycleHost.waitForWrites(),
          SqfliteWriteGateResult.ready);
      expect(db.isOpen, isFalse);
    } finally {
      if (!factory.release.isCompleted) factory.release.complete();
      if (!db.releaseClose.isCompleted) db.releaseClose.complete();
      await warmup;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      SqfliteLifecycleHost.debugReset();
      SqfliteLifecycleGuard.instance.debugReset();
      await store.closeIfOpen();
      databaseFactory = previous ?? databaseFactoryFfi;
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
