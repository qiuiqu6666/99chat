import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

/// Opt-in only: BEGIN/END IDs locate native CursorWindow warnings between
/// queries. Never logs bind arguments, SQL literals, or returned user data.
extension SqliteQueryDiagnostics on DatabaseExecutor {
  Future<List<Map<String, Object?>>> diagnosedQuery(
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
  }) => _QueryTrace.run(
    'table=$table columns=${columns?.join(",") ?? "*"} limit=$limit',
    () => query(table, distinct: distinct, columns: columns, where: where,
      whereArgs: whereArgs, groupBy: groupBy, having: having,
      orderBy: orderBy, limit: limit, offset: offset),
  );

  Future<List<Map<String, Object?>>> diagnosedRawQuery(
    String sql, [List<Object?>? arguments,
  ]) => _QueryTrace.run('rawQuery=true', () => rawQuery(sql, arguments));
}

class _QueryTrace {
  static const enabled = bool.fromEnvironment('SQLITE_QUERY_DIAGNOSTICS');
  static int _nextId = 0;

  static Future<List<Map<String, Object?>>> run(
    String description,
    Future<List<Map<String, Object?>>> Function() action,
  ) async {
    if (!enabled) return action();
    final id = ++_nextId;
    final source = StackTrace.current.toString().split('\n')
        .where((line) => !line.contains('sqlite_query_diagnostics.dart'))
        .take(2).join(' ');
    final watch = Stopwatch()..start();
    debugPrintSynchronously('[SqlQuery] begin id=$id $description source=$source');
    try {
      final rows = await action();
      debugPrintSynchronously('[SqlQuery] end id=$id rows=${rows.length} '
          'columns=${rows.isEmpty ? "" : rows.first.keys.join(",")} '
          'elapsedMs=${watch.elapsedMilliseconds}');
      return rows;
    } catch (error) {
      debugPrintSynchronously('[SqlQuery] error id=$id type=${error.runtimeType} '
          'elapsedMs=${watch.elapsedMilliseconds}');
      rethrow;
    }
  }
}
