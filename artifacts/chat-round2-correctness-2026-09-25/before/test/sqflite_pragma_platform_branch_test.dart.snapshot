import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/sqflite_bootstrap_helper.dart';

class RecordingDatabase implements Database {
  final queries = <String>[];
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments]) async {
    queries.add(sql);
    return [{'timeout': 5000}];
  }
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    fail('Result-bearing PRAGMA must use rawQuery: $sql');
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    test('$platform runs busy_timeout through query API', () async {
      debugDefaultTargetPlatformOverride = platform;
      final db = RecordingDatabase();
      await SqfliteBootstrapHelper.withTag('test').runOnOpenPragmas(db);
      expect(db.queries, ['PRAGMA busy_timeout=5000']);
    });
  }
  test('iOS preserves existing skip policy', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final db = RecordingDatabase();
    await SqfliteBootstrapHelper.withTag('test').runOnOpenPragmas(db);
    expect(db.queries, isEmpty);
  });
}
