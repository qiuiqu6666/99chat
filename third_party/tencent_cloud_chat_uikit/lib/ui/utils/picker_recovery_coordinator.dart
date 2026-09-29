import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;

class PickerRecoveryOwner {
  const PickerRecoveryOwner(this.userId, this.epoch);
  final String userId;
  final int epoch;
}

class PickerRecoveredDraft {
  PickerRecoveredDraft(this.intent, this.files,
      {this.error, this.claimed = false});
  final Map<String, dynamic> intent;
  final List<XFile> files;
  final String? error;

  /// A restart interrupted dispatch; consult the existing outbox, never resend
  /// this ambiguous handoff automatically.
  final bool claimed;
  String get id => intent['id'] as String;
  String get owner => intent['owner'] as String? ?? '';
  String get entry => intent['entry'] as String? ?? 'unknown';
  String? get destination => intent['destination'] as String?;
}

/// One process-wide consumer of Android picker recovery. Native results are
/// peeked, copied to application support and journaled before token-matched ack.
/// Recovery creates drafts only; this service never sends messages.
class PickerRecoveryCoordinator {
  PickerRecoveryCoordinator({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('99chat/picker_recovery');
  static final instance = PickerRecoveryCoordinator();
  final MethodChannel _channel;
  Directory? _root;
  Future<PickerRecoveryOwner> Function()? _owner;
  bool _launching = false;
  Future<void>? _recovering;
  int _counter = 0;
  final Set<String> _liveIds = {};

  void configure(
      {required Directory directory,
      required Future<PickerRecoveryOwner> Function() owner}) {
    _root = directory;
    _owner = owner;
  }

  bool get enabled => _root != null && _owner != null;
  String _id() => '${DateTime.now().microsecondsSinceEpoch}_${_counter++}';
  Directory _directory(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Invalid picker operation');
    }
    return Directory(p.join(_root!.path, id));
  }

  Future<void> _write(File file, Map<String, dynamic> value) async {
    if (await file.exists()) return; // immutable journal records
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.pending');
    await pending.writeAsString(jsonEncode(value), flush: true);
    await pending.rename(file.path);
  }

  Future<Map<String, dynamic>?> _read(File file) async {
    if (!await file.exists()) return null;
    try {
      final value = jsonDecode(await file.readAsString());
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } on FormatException {
      return null;
    }
  }

  Future<List<XFile>?> pick(
      {required String entry,
      String? destination,
      required Future<List<XFile>?> Function() launch}) async {
    if (!enabled) return launch();
    if (_launching) throw StateError('A media picker is already active');
    _launching = true;
    String? activeId;
    var handedOff = false;
    try {
      await _recoverJoined();
      await _cleanupCompleted();
      final owner = await _owner!();
      final id = _id();
      activeId = id;
      final dir = _directory(id);
      final intent = <String, dynamic>{
        'id': id,
        'owner': owner.userId,
        'epoch': owner.epoch,
        'entry': entry,
        'destination': destination
      };
      await _write(File(p.join(dir.path, 'intent.json')), intent);
      _liveIds.add(id);
      final began =
          await _channel.invokeMethod<bool>('begin', {'operationId': id});
      if (began != true) throw StateError('Cannot journal native picker');
      List<XFile>? files;
      try {
        files = await launch();
      } catch (_) {
        // A native result may already exist; preserve it if export/dispatch failed.
        _liveIds.remove(id);
        await _recoverJoined();
        await _channel.invokeMethod('end', {'operationId': id});
        rethrow;
      }
      if (files == null || files.isEmpty) {
        await _channel.invokeMethod('end', {'operationId': id});
        _liveIds.remove(id);
        await _write(
            File(p.join(dir.path, 'complete.json')), _completed('cancelled'));
        return files;
      }
      final draft = await _saveDraft(intent, files);
      final native = await _channel.invokeMapMethod<String, dynamic>('peek');
      if (native?['operationId'] == id && native?['token'] != null) {
        final acknowledged = await _channel
            .invokeMethod<bool>('ack', {'token': native!['token']});
        if (acknowledged != true)
          throw StateError('Picker result changed before acknowledgment');
      }
      await _channel.invokeMethod('end', {'operationId': id});
      final current = await _owner!();
      if (current.userId != owner.userId || current.epoch != owner.epoch) {
        _liveIds.remove(id);
        throw StateError('Account changed while choosing media');
      }
      if (draft.error != null) throw StateError('Some selected files are unavailable; saved files remain recoverable');
      handedOff = true;
      return draft.files;
    } finally {
      if (!handedOff && activeId != null) _liveIds.remove(activeId);
      _launching = false;
    }
  }

  Future<PickerRecoveredDraft> _saveDraft(
      Map<String, dynamic> intent, List<XFile> files,
      {String? error}) async {
    final dir = _directory(intent['id'] as String);
    final existing = await _read(File(p.join(dir.path, 'draft.json')));
    if (existing != null) return _draft(intent, existing);
    await dir.create(recursive: true);
    final paths = <String>[];
    var missing = 0;
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      if (!await File(file.path).exists()) {
        missing++;
        continue;
      }
      final extension = p.extension(file.path);
      final safeExtension = RegExp(r'^\.[a-zA-Z0-9]{1,10}$').hasMatch(extension)
          ? extension
          : '.media';
      final output = File(
          p.join(dir.path, '${i.toString().padLeft(3, '0')}$safeExtension'));
      if (!await output.exists()) {
        final pending = File('${output.path}.pending');
        final sink = await pending.open(mode: FileMode.write);
        try {
          await for (final bytes in File(file.path).openRead()) {
            await sink.writeFrom(bytes);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        await pending.rename(output.path);
      }
      paths.add(output.path);
    }
    final data = <String, dynamic>{
      'paths': paths,
      'error': error ?? (missing > 0 ? 'source_files_missing:$missing' : null)
    };
    await _write(File(p.join(dir.path, 'draft.json')), data);
    return _draft(intent, data);
  }

  PickerRecoveredDraft _draft(
          Map<String, dynamic> intent, Map<String, dynamic> data) =>
      PickerRecoveredDraft(intent,
          (data['paths'] as List).cast<String>().map(XFile.new).toList(),
          error: data['error'] as String?);

  Future<void> recover() async {
    if (!enabled || _launching) return;
    await _recoverJoined();
  }

  Future<void> _recoverJoined() async {
    final pending = _recovering;
    if (pending != null) return pending;
    final work = _recover();
    _recovering = work;
    try {
      await work;
    } finally {
      if (identical(_recovering, work)) _recovering = null;
    }
  }

  Future<void> _recover() async {
    final native = await _channel.invokeMapMethod<String, dynamic>('peek');
    if (native == null || native.isEmpty || native['token'] == null) return;
    final nativeId = native['operationId'] as String?;
    Map<String, dynamic>? intent;
    if (nativeId != null)
      intent =
          await _read(File(p.join(_directory(nativeId).path, 'intent.json')));
    // Legacy/unknown entry is quarantined, never assigned to the signed-in chat.
    intent ??= {
      'id': 'unowned_${native['token']}',
      'owner': '',
      'epoch': -1,
      'entry': 'unknown',
      'destination': null
    };
    await _write(
        File(p.join(_directory(intent['id'] as String).path, 'intent.json')),
        intent);
    final paths =
        (native['paths'] as List?)?.cast<String>() ?? const <String>[];
    await _saveDraft(intent, paths.map(XFile.new).toList(),
        error: native['errorCode'] as String?);
    final ack =
        await _channel.invokeMethod<bool>('ack', {'token': native['token']});
    if (ack != true) throw StateError('Picker recovery acknowledgment changed');
  }

  Future<List<PickerRecoveredDraft>> drafts(
      {String? entry, String? destination, bool includeClaimed = false}) async {
    if (!enabled || !await _root!.exists()) return [];
    final owner = await _owner!();
    if (owner.userId.isEmpty) return [];
    final result = <PickerRecoveredDraft>[];
    await for (final entity in _root!.list()) {
      if (entity is! Directory) continue;
      if (_liveIds.contains(p.basename(entity.path))) continue;
      final claimed = await File(p.join(entity.path, 'claimed.json')).exists();
      if (await File(p.join(entity.path, 'complete.json')).exists() ||
          (claimed && !includeClaimed)) continue;
      final intent = await _read(File(p.join(entity.path, 'intent.json')));
      final data = await _read(File(p.join(entity.path, 'draft.json')));
      if (intent == null ||
          data == null ||
          intent['owner'] != owner.userId ||
          (entry != null && intent['entry'] != entry) ||
          (destination != null && intent['destination'] != destination))
        continue;
      final draft = _draft(intent, data);
      result.add(PickerRecoveredDraft(intent, draft.files,
          error: draft.error, claimed: claimed));
    }
    return result;
  }

  final Set<String> _claims = {};

  /// Claim is durable before dispatch. A claimed draft never automatically
  /// dispatches twice after a restart; accepted sends use the existing outbox.
  Future<bool> claim(PickerRecoveredDraft draft) async {
    if (!enabled || !_claims.add(draft.id)) return false;
    try {
      final owner = await _owner!();
      if (owner.userId.isEmpty || owner.userId != draft.owner) return false;
      final dir = _directory(draft.id);
      if (await File(p.join(dir.path, 'claimed.json')).exists() ||
          await File(p.join(dir.path, 'complete.json')).exists()) return false;
      await _write(File(p.join(dir.path, 'claimed.json')), {'claimed': true});
      return true;
    } finally {
      _claims.remove(draft.id);
    }
  }

  Future<void> completePaths(Iterable<XFile> files) async {
    if (!enabled) return;
    for (final file in files) {
      if (!p.isWithin(_root!.path, file.path)) continue;
      final dir = File(file.path).parent;
      final intent = await _read(File(p.join(dir.path, 'intent.json')));
      if (intent != null) {
        _liveIds.remove(intent['id']);
        await _write(
            File(p.join(dir.path, 'complete.json')), _completed('handed_off'));
      }
    }
  }

  Future<void> discard(PickerRecoveredDraft draft) async {
    final owner = await _owner!();
    if (owner.userId != draft.owner || owner.userId.isEmpty) return;
    await _write(File(p.join(_directory(draft.id).path, 'complete.json')),
        _completed('discarded'));
  }

  Map<String, dynamic> _completed(String reason) =>
      {'reason': reason, 'at': DateTime.now().millisecondsSinceEpoch};

  Future<void> _cleanupCompleted() async {
    if (!await _root!.exists()) return;
    final cutoff =
        DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    await for (final entity in _root!.list(followLinks: false)) {
      if (entity is! Directory || !p.isWithin(_root!.path, entity.path))
        continue;
      final completion =
          await _read(File(p.join(entity.path, 'complete.json')));
      if (completion != null && (completion['at'] as int? ?? cutoff) < cutoff) {
        // Only terminal picker copies; pending/claimed drafts and the outbox
        // have independent ownership and are never deleted here.
        await entity.delete(recursive: true);
      }
    }
  }
}
