import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

/// iOS 进后台时 SQLite 仍持锁会被 RunningBoard 以 `0xdead10cc` 杀掉。
/// `inactive` 只停写；`paused` 再禁止新 open 并关连接。
class SqfliteLifecycleGuard {
  SqfliteLifecycleGuard._();

  static final SqfliteLifecycleGuard instance = SqfliteLifecycleGuard._();

  bool _writesAllowed = true;
  bool _canOpenDatabase = true;

  bool get writesAllowed => _writesAllowed;
  bool get canOpenDatabase => _canOpenDatabase;

  void pauseWrites() {
    _writesAllowed = false;
  }

  void forbidOpen() {
    _writesAllowed = false;
    _canOpenDatabase = false;
  }

  void resume() {
    _writesAllowed = true;
    _canOpenDatabase = true;
  }

  /// 已打开则返回现有连接；后台已关且未打开则抛 [SqfliteClosedForBackground]。
  static Database? beforeOpen(Database? existing) {
    if (!instance.canOpenDatabase) {
      throw const SqfliteClosedForBackground();
    }
    return existing;
  }

  static Future<void> closeDatabase(Database? db) async {
    if (db == null) {
      return;
    }
    // sqflite marks the Dart handle closed before the native acknowledgment.
    // isOpen=false cannot prove a failed native close is safe to reopen.
    await db.close();
  }

  @visibleForTesting
  void debugReset() {
    _writesAllowed = true;
    _canOpenDatabase = true;
  }
}

class SqfliteClosedForBackground implements Exception {
  const SqfliteClosedForBackground();

  @override
  String toString() => 'SqfliteClosedForBackground';
}
