// Exercises real Host -> Store -> Guard close chain with a controlled database.
// No native database is opened, no user files are touched.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// ignore: implementation_imports
import 'package:sqflite_common/src/factory.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_host.dart';

class StalledAuditDatabase implements Database {
  final closeStarted = Completer<void>();
  final releaseClose = Completer<void>();
  bool _open = true;
  @override
  bool get isOpen => _open;
  @override
  String get path => 'audit-memory-database';
  @override
  Future<void> close() async {
    if (!closeStarted.isCompleted) closeStarted.complete();
    await releaseClose.future;
    _open = false;
  }
  @override
  Future<List<Map<String, Object?>>> query(String table, {
    bool? distinct, List<String>? columns, String? where,
    List<Object?>? whereArgs, String? groupBy, String? having,
    String? orderBy, int? limit, int? offset,
  }) async => [];
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments]) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AuditDatabaseFactory implements SqfliteDatabaseFactory {
  AuditDatabaseFactory(this.db);
  final StalledAuditDatabase db;
  @override
  Future<String> getDatabasesPath() async => 'audit-does-not-touch-disk';
  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) async => db;
  @override
  Future<bool> databaseExists(String path) async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('A09 paused native close stalls resume and write gate until it actually completes', () async {
    DatabaseFactory? oldFactory;
    try { oldFactory = databaseFactory; } catch (_) {}
    final database = StalledAuditDatabase();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    databaseFactory = AuditDatabaseFactory(database);
    SqfliteLifecycleHost.debugReset();
    SqfliteLifecycleGuard.instance.debugReset();
    Future<void>? paused;
    Future<void>? resumed;
    Future<void>? writer;
    try {
      await FriendLocalStore.instance.readAll(ownerUserId: 'audit-owner');
      paused = SqfliteLifecycleHost.handle(AppLifecycleState.paused);
      await database.closeStarted.future.timeout(const Duration(seconds: 2));
      var resumeDone = false;
      var writeDone = false;
      resumed = SqfliteLifecycleHost.handle(AppLifecycleState.resumed)
          .then((_) { resumeDone = true; });
      writer = SqfliteLifecycleHost.waitUntilWritesAllowed()
          .then((_) { writeDone = true; });
      // The open wait has a timeout; the close, lifecycle queue and writer do not.
      expect(await SqfliteLifecycleHost.waitUntilOpenAllowed(
          timeout: const Duration(milliseconds: 40)), isFalse);
      expect(resumeDone, isFalse);
      expect(writeDone, isFalse);
      expect(SqfliteLifecycleGuard.instance.canOpenDatabase, isFalse);
      expect(SqfliteLifecycleGuard.instance.writesAllowed, isFalse);

      database.releaseClose.complete();
      await Future.wait([paused, resumed, writer]).timeout(const Duration(seconds: 2));
      expect(resumeDone, isTrue);
      expect(writeDone, isTrue);
      expect(SqfliteLifecycleGuard.instance.writesAllowed, isTrue);
    } finally {
      if (!database.releaseClose.isCompleted) database.releaseClose.complete();
      if (paused != null) await paused;
      if (resumed != null) await resumed;
      if (writer != null) await writer;
      await FriendLocalStore.instance.closeIfOpen();
      SqfliteLifecycleHost.debugReset();
      SqfliteLifecycleGuard.instance.debugReset();
      databaseFactory = oldFactory ?? databaseFactoryFfi;
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
