import 'dart:async';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// ignore: implementation_imports
import 'package:sqflite_common/src/factory.dart';

/// Controls the native close acknowledgment without touching user databases.
class StalledAuditDatabase implements Database {
  final closeStarted = Completer<void>();
  final releaseClose = Completer<void>();
  bool _open = true;
  @override
  bool get isOpen => _open;
  @override
  String get path => 'controlled-memory-database';
  @override
  Future<void> close() async {
    if (!closeStarted.isCompleted) closeStarted.complete();
    await releaseClose.future;
    _open = false;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async =>
      [];
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
          [List<Object?>? arguments]) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AuditDatabaseFactory implements SqfliteDatabaseFactory {
  AuditDatabaseFactory(this.db);
  final StalledAuditDatabase db;
  @override
  Future<String> getDatabasesPath() async => 'controlled-no-disk';
  @override
  Future<Database> openDatabase(String path,
          {OpenDatabaseOptions? options}) async =>
      db;
  @override
  Future<bool> databaseExists(String path) async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
