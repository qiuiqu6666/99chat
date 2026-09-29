import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/message_history_coverage_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/message_media_metadata_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_host.dart';
import 'support/controlled_database.dart' as f;

class _Database extends f.StalledAuditDatabase {
  bool fail = false;
  @override
  Future<void> close() async {
    if (!closeStarted.isCompleted) closeStarted.complete();
    await releaseClose.future;
    if (fail) throw StateError('native close not acknowledged');
    await super.close();
  }
}

class _Factory extends f.AuditDatabaseFactory {
  _Factory(super.db);
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
  for (final kind in ['media', 'history_coverage']) {
    for (final fails in [false, true]) {
      test('$kind late open retains close fence; native failure=$fails',
          () async {
        DatabaseFactory? previous;
        try {
          previous = databaseFactory;
        } catch (_) {}
        final db = _Database()..fail = fails;
        final factory = _Factory(db);
        databaseFactory = factory;
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        SqfliteLifecycleHost.debugReset();
        SqfliteLifecycleGuard.instance.debugReset();
        final warmup = kind == 'media'
            ? MessageMediaMetadataStore.warmUp()
            : MessageHistoryCoverageStore.instance
                .loadForOwner('close-$fails', 'c2c_peer');
        try {
          await factory.started.future;
          await SqfliteLifecycleHost.handle(AppLifecycleState.paused,
              waitBudget: const Duration(milliseconds: 10));
          await SqfliteLifecycleHost.handle(AppLifecycleState.resumed,
              waitBudget: const Duration(milliseconds: 10));
          await Future<void>.delayed(const Duration(milliseconds: 450));
          expect(SqfliteLifecycleGuard.instance.canOpenDatabase, isFalse);
          expect(SqfliteLifecycleHost.pendingStores, contains(kind));
          factory.release.complete();
          await db.closeStarted.future;
          expect(SqfliteLifecycleGuard.instance.canOpenDatabase, isFalse);
          db.releaseClose.complete();
          await warmup;
          expect(
              await SqfliteLifecycleHost.waitForWrites(
                  timeout: const Duration(milliseconds: 100)),
              fails
                  ? SqfliteWriteGateResult.deferred
                  : SqfliteWriteGateResult.ready);
          expect(SqfliteLifecycleGuard.instance.canOpenDatabase, !fails);
        } finally {
          if (!factory.release.isCompleted) factory.release.complete();
          if (!db.releaseClose.isCompleted) db.releaseClose.complete();
          await warmup;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          SqfliteLifecycleHost.debugReset();
          SqfliteLifecycleGuard.instance.debugReset();
          databaseFactory = previous ?? databaseFactoryFfi;
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
