import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// The OS releases this lock on process exit, even when Dart teardown never ran.
/// SQLite fencing still decides who can write; the lock only proves abandonment.
class MessageCoreOwner {
  MessageCoreOwner({this.directory});

  static final MessageCoreOwner instance = MessageCoreOwner();
  final String? directory;
  final String _token = const Uuid().v4();
  String get _guardedId => 'flutter-message-core-v2:$pid:$_token';
  String get id => _lock == null ? 'flutter-message-core:$_token' : _guardedId;
  static final _ownerPattern = RegExp(
    r'^flutter-message-core-v2:(\d+):([a-f0-9-]{36})$',
  );
  RandomAccessFile? _lock;
  Future<void>? _opening;
  String? _directory;

  Future<void> ensureReady() => _opening ??= _open();

  Future<String> prepareLeaseOwner() async {
    await ensureReady();
    return id;
  }

  Future<void> _open() async {
    try {
      _directory = directory ?? await getDatabasesPath();
      await Directory(_directory!).create(recursive: true);
      final file = await File(_path(_guardedId)).open(mode: FileMode.append);
      try {
        await file.lock(FileLock.exclusive, 0, 1);
        _lock = file;
      } catch (_) {
        await file.close();
      }
    } catch (_) {
      // Unsupported filesystems keep the original TTL-based election behavior.
    }
  }

  String _path(String owner) => p.join(
        _directory!,
        'message_core_owner_${owner.split(':').skip(1).join('_')}.lock',
      );

  Future<bool> isAbandoned(String ownerId) async {
    await ensureReady();
    final match = _ownerPattern.firstMatch(ownerId);
    if (_lock == null || match == null) return false;
    // POSIX locks belong to a process, not a Dart isolate. Never probe another
    // engine in this process, or infer death from an older, unguarded owner ID.
    if (int.tryParse(match.group(1)!) == pid) return false;
    final source = File(_path(ownerId));
    if (!await source.exists()) return false;
    RandomAccessFile? probe;
    try {
      probe = await source.open(mode: FileMode.append);
      await probe.lock(FileLock.exclusive, 0, 1);
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        await probe?.close();
      } catch (_) {}
    }
  }
}
