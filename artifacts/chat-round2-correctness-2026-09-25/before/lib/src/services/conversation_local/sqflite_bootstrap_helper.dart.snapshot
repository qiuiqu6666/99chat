import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';

/// FFB-2 扩散（v17）：多 store 共用的 sqflite openDatabase bootstrap 辅助。
///
/// 解决：iOS sqflite_darwin 在冷启动早期 `openDatabase` 的 `onOpen` 回调里执行
/// `PRAGMA busy_timeout = 5000` 偶发把 NSError 包成 "not an error" / SqliteException(0)
/// 抛出。原本 11 个 store 各写各的；现在统一走本 helper：
///
///   - `runOnOpenPragmas(db)`：执行 `PRAGMA busy_timeout = 5000`，失败时打
///     `conv_db_open_pragma_busy_timeout_failed{store:<tag>}` 细分埋点，
///     但不 rethrow（sqflite 内部已经把 PRAGMA 失败后的 db 标记可用）。
///   - `runOnOpenPragmasRawQuery(db)`：给使用 rawQuery 的 store（如 message_core_store）。
///
/// 不做单飞 / 节流：留给各 store 复用现有 `SqfliteLifecycleGuard`；ConvStore
/// 原有的 FFB-1.2 give-up 行为**不通过本 helper 走**（这是 ConvStore 独有优势）。
class SqfliteBootstrapHelper {
  /// 共享单例（默认 store tag = 'shared'，不推荐用作埋点维度）。
  static final SqfliteBootstrapHelper instance = SqfliteBootstrapHelper.withTag(
    'shared',
  );

  /// store 短名（埋点 details['store'] 用）。
  /// 例如 'conv' / 'conv_legacy' / 'friend' / 'group' / 'moments' 等。
  final String _storeTag;

  SqfliteBootstrapHelper.withTag(String storeTag) : _storeTag = storeTag;

  String get storeTag => _storeTag;

  /// 在 store 的 `onOpen` 回调里调用：执行 `PRAGMA busy_timeout = 5000`。
  /// 失败时打细分埋点但不 rethrow。
  Future<void> runOnOpenPragmas(Database db) {
    // iOS sqflite_darwin can block the onOpen callback while another store is
    // opening. The setting is connection-local and best effort; never make
    // the database-open critical path wait for it on iOS.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      // sqflite_darwin returns a misleading "not an error" for this pragma
      // during concurrent cold-start opens. It has no value for our iOS
      // stores, so skip it instead of enqueueing a doomed database operation.
      return Future<void>.value();
    }
    return _runOnOpenPragmas(db);
  }

  Future<void> _runOnOpenPragmas(Database db) async {
    try {
      // busy_timeout returns a result row, including on Android.
      await db.rawQuery('PRAGMA busy_timeout=5000');
    } catch (e) {
      // F-fix：只打短消息，避免同步完整 stack trace 阻塞 paint。
      // stack 暂不记录；如需事后回查可接 StartupPerfLog.asyncStack()。
      debugPrint(
        '[SqfliteBootstrap] $_storeTag PRAGMA busy_timeout failed (ignored): $e',
      );
      StartupPerfLog.markTagged(
        'conv_db_open_pragma_busy_timeout_failed',
        category: 'cold_start',
        details: <String, Object>{
          'store': _storeTag,
          'errorType': e.runtimeType.toString(),
          'errorMessage': e.toString(),
          'sql': 'PRAGMA busy_timeout = 5000',
        },
      );
    }
  }

  /// 给使用 `db.rawQuery('PRAGMA busy_timeout=5000')` 的 store 提供等价入口。
  /// 失败时同样打细分埋点但不 rethrow。
  Future<void> runOnOpenPragmasRawQuery(Database db) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      // Same as runOnOpenPragmas: do not enqueue an iOS no-op/failing query.
      return Future<void>.value();
    }
    return _runOnOpenPragmasRawQuery(db);
  }

  Future<void> _runOnOpenPragmasRawQuery(Database db) async {
    try {
      await db.rawQuery('PRAGMA busy_timeout=5000');
    } catch (e, st) {
      debugPrint(
        '[SqfliteBootstrap] $_storeTag PRAGMA busy_timeout (rawQuery) failed (ignored): $e\n$st',
      );
      StartupPerfLog.markTagged(
        'conv_db_open_pragma_busy_timeout_failed',
        category: 'cold_start',
        details: <String, Object>{
          'store': _storeTag,
          'errorType': e.runtimeType.toString(),
          'errorMessage': e.toString(),
          'sql': 'PRAGMA busy_timeout=5000 (rawQuery)',
        },
      );
    }
  }
}

/// 顶层句柄：每个 store 在自己的 `_openDb` 内 `onOpen` 入口调用：
///   `await SqfliteBootstrapHelper.withTag('friend').runOnOpenPragmas(db);`
/// 失败时不阻断 DB open；DB 仍可继续被业务层使用。
