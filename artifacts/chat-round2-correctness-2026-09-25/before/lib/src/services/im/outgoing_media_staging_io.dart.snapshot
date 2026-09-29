import 'dart:convert';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_send_perf.dart';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';

typedef OutgoingMediaSupportDirectoryProvider = Future<Directory> Function();

class OutgoingMediaStageResult {
  const OutgoingMediaStageResult({
    required this.hadLocalMedia,
    required this.rootPath,
    required this.succeeded,
  });

  final bool hadLocalMedia;
  final String? rootPath;
  final bool succeeded;

  bool get shouldBlock => hadLocalMedia && !succeeded;
}

class OutgoingMediaStager {
  OutgoingMediaStager({this.supportDirectoryProvider});

  static final OutgoingMediaStager instance = OutgoingMediaStager();

  final OutgoingMediaSupportDirectoryProvider? supportDirectoryProvider;

  static const int _imageAndSoundMaxBytes = 28 * 1024 * 1024;
  static const int _videoAndFileMaxBytes = 100 * 1024 * 1024;

  static bool hasLocalMedia(V2TimMessage? message) {
    if (message == null) return false;
    return _path(message.imageElem?.path).isNotEmpty ||
        _path(message.videoElem?.videoPath).isNotEmpty ||
        _path(message.videoElem?.snapshotPath).isNotEmpty ||
        _path(message.soundElem?.path).isNotEmpty ||
        _path(message.fileElem?.path).isNotEmpty;
  }

  Future<OutgoingMediaStageResult> stageMessage({
    required V2TimMessage? message,
    required String operationId,
  }) async {
    if (!hasLocalMedia(message)) {
      return const OutgoingMediaStageResult(
        hadLocalMedia: false,
        rootPath: null,
        succeeded: true,
      );
    }
    Directory? root;
    try {
      final support = await (supportDirectoryProvider?.call() ??
          getApplicationSupportDirectory());
      root = Directory(
        p.join(support.path, 'im_outbox_media', _safeOperationId(operationId)),
      );
      await root.create(recursive: true);
      final copies = <({
        String source,
        String name,
        int maxBytes,
        bool requireJpeg,
        void Function(String) set,
      })>[];
      final imagePath = _path(message?.imageElem?.path);
      if (imagePath.isNotEmpty) {
        copies.add((
          source: imagePath,
          name: 'image${p.extension(imagePath)}',
          maxBytes: _imageAndSoundMaxBytes,
          requireJpeg: false,
          set: (value) => message!.imageElem!.path = value,
        ));
      }
      final videoPath = _path(message?.videoElem?.videoPath);
      if (videoPath.isNotEmpty) {
        copies.add((
          source: videoPath,
          name: 'video${p.extension(videoPath)}',
          maxBytes: _videoAndFileMaxBytes,
          requireJpeg: false,
          set: (value) => message!.videoElem!.videoPath = value,
        ));
      }
      final snapshotPath = _path(message?.videoElem?.snapshotPath);
      if (snapshotPath.isNotEmpty) {
        copies.add((
          source: snapshotPath,
          name: 'snapshot${p.extension(snapshotPath)}',
          maxBytes: _imageAndSoundMaxBytes,
          requireJpeg: true,
          set: (value) => message!.videoElem!.snapshotPath = value,
        ));
      }
      final soundPath = _path(message?.soundElem?.path);
      if (soundPath.isNotEmpty) {
        copies.add((
          source: soundPath,
          name: 'sound${p.extension(soundPath)}',
          maxBytes: _imageAndSoundMaxBytes,
          requireJpeg: false,
          set: (value) => message!.soundElem!.path = value,
        ));
      }
      final filePath = _path(message?.fileElem?.path);
      if (filePath.isNotEmpty) {
        copies.add((
          source: filePath,
          name: 'file${p.extension(filePath)}',
          maxBytes: _videoAndFileMaxBytes,
          requireJpeg: false,
          set: (value) => message!.fileElem!.path = value,
        ));
      }
      final staged = <({String path, void Function(String) set})>[];
      final borrowed = <String>{};
      final perf = MediaSendPerf.lookup(message?.id);
      final copyWatch = Stopwatch()..start();
      var copiedBytes = 0;
      final managed = Directory(p.join(support.path, 'im_media_staging'));
      final managedRoot =
          await managed.exists() ? await managed.resolveSymbolicLinks() : null;
      for (final copy in copies) {
        final source = File(copy.source);
        if (!_isUsableSource(
          source,
          maxBytes: copy.maxBytes,
          requireJpeg: copy.requireJpeg,
        )) {
          throw FileSystemException('media is missing or invalid');
        }
        final canonical = await source.resolveSymbolicLinks();
        // Only borrow files inside our real durable root, never picker paths or
        // symlinks that escape the root. Keep a small reference manifest so
        // recovery cleanup protects files for every account, including retries.
        if (managedRoot != null && p.isWithin(managedRoot, canonical)) {
          borrowed.add(canonical);
          staged.add((path: copy.source, set: copy.set));
          continue;
        }
        final target = await source.copy(p.join(root.path, copy.name));
        copiedBytes += await target.length();
        if (!_isUsableSource(
          target,
          maxBytes: copy.maxBytes,
          requireJpeg: copy.requireJpeg,
        )) {
          throw FileSystemException('staged media verification failed');
        }
        staged.add((path: target.path, set: copy.set));
      }
      if (borrowed.isNotEmpty) {
        await File(p.join(root.path, 'media_refs.json'))
            .writeAsString(jsonEncode(borrowed.toList()), flush: true);
      }
      perf?.record('recoveryStagingMs', copyWatch.elapsedMilliseconds);
      perf?.record('copyBytes', copiedBytes);
      for (final item in staged) {
        item.set(item.path);
      }
      return OutgoingMediaStageResult(
        hadLocalMedia: true,
        rootPath: root.path,
        succeeded: true,
      );
    } catch (_) {
      await cleanup(root?.path);
      return OutgoingMediaStageResult(
        hadLocalMedia: true,
        rootPath: null,
        succeeded: false,
      );
    }
  }

  Future<void> cleanup(String? rootPath) async {
    final candidate = _path(rootPath);
    if (candidate.isEmpty) return;
    try {
      final support = await (supportDirectoryProvider?.call() ??
          getApplicationSupportDirectory());
      final mediaRoot = p.join(support.path, 'im_outbox_media');
      if (!p.isWithin(mediaRoot, candidate)) return;
      final directory = Directory(candidate);
      if (directory.existsSync()) {
        final refs = File(p.join(directory.path, 'media_refs.json'));
        if (await refs.exists()) {
          final paths = jsonDecode(await refs.readAsString()) as List;
          final liveRoot = Directory(p.join(support.path, 'im_media_staging'));
          final canonicalRoot = await liveRoot.resolveSymbolicLinks();
          for (final path in paths.cast<String>()) {
            final file = File(path);
            if (!await file.exists()) continue;
            final canonical = await file.resolveSymbolicLinks();
            if (!p.isWithin(canonicalRoot, canonical)) continue;
            // Refresh directory mtime without changing the media bytes.
            final marker = File(p.join(p.dirname(canonical), '.retained'));
            if (await marker.exists()) await marker.delete();
            await marker.writeAsString('', flush: true);
          }
        }
        await directory.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> cleanupLiveMessage(V2TimMessage? message) async {
    if (message == null) return;
    final paths = <String?>[
      message.imageElem?.path,
      message.videoElem?.videoPath,
      message.videoElem?.snapshotPath,
      message.soundElem?.path,
      message.fileElem?.path,
    ];
    for (final path in paths) {
      await _cleanupLivePath(path);
    }
  }

  Future<void> _cleanupLivePath(String? value) async {
    final candidate = _path(value).replaceAll('\\', '/');
    if (!candidate.contains('/im_media_staging/')) return;
    try {
      final support = await (supportDirectoryProvider?.call() ??
          getApplicationSupportDirectory());
      final mediaRoot = p.join(support.path, 'im_media_staging');
      final stageDirectory = File(candidate).parent.path;
      if (!p.isWithin(mediaRoot, stageDirectory)) return;
      final directory = Directory(stageDirectory);
      if (directory.existsSync()) await directory.delete(recursive: true);
    } catch (_) {}
  }

  /// Deletes only old, direct children of the managed Outbox directory that
  /// are not referenced by a recoverable Outbox row.  A grace period protects
  /// a file copied immediately before its database transaction commits.
  Future<void> cleanupOrphans({
    required Iterable<String?> activeRootPaths,
    Duration minimumAge = const Duration(hours: 24),
  }) async {
    try {
      final support = await (supportDirectoryProvider?.call() ??
          getApplicationSupportDirectory());
      final mediaRoot = Directory(p.join(support.path, 'im_outbox_media'));
      if (!mediaRoot.existsSync()) return;
      final active = activeRootPaths
          .map(_path)
          .where((value) => value.isNotEmpty)
          .map((value) => p.normalize(p.absolute(value)))
          .toSet();
      final cutoff = DateTime.now().subtract(minimumAge);
      await for (final entity in mediaRoot.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final candidate = p.normalize(p.absolute(entity.path));
        if (!p.isWithin(mediaRoot.path, candidate) ||
            active.contains(candidate)) {
          continue;
        }
        // A manifest can belong to another signed-out account. Only explicit
        // delivery cleanup may release it; an account-local scan is insufficient.
        if (await File(p.join(entity.path, 'media_refs.json')).exists()) {
          continue;
        }
        final stat = await entity.stat();
        if (stat.modified.isAfter(cutoff)) continue;
        await entity.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> cleanupLiveOrphans({
    Duration minimumAge = const Duration(days: 2),
  }) async {
    try {
      final support = await (supportDirectoryProvider?.call() ??
          getApplicationSupportDirectory());
      final root = Directory(p.join(support.path, 'im_media_staging'));
      if (!root.existsSync()) return;
      final protected = <String>{};
      final outbox = Directory(p.join(support.path, 'im_outbox_media'));
      if (await outbox.exists()) {
        await for (final operation in outbox.list(followLinks: false)) {
          if (operation is! Directory) continue;
          final refs = File(p.join(operation.path, 'media_refs.json'));
          if (!await refs.exists()) continue;
          final paths = jsonDecode(await refs.readAsString()) as List;
          for (final path in paths.cast<String>()) {
            protected.add(p.dirname(path));
          }
        }
      }
      final cutoff = DateTime.now().subtract(minimumAge);
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory) continue;
        if (protected.contains(await entity.resolveSymbolicLinks())) continue;
        final stat = await entity.stat();
        if (stat.modified.isAfter(cutoff)) continue;
        await entity.delete(recursive: true);
      }
    } catch (_) {}
  }
}

bool _isUsableSource(
  File file, {
  required int maxBytes,
  required bool requireJpeg,
}) {
  RandomAccessFile? handle;
  try {
    if (!file.existsSync()) return false;
    final length = file.lengthSync();
    if (length <= 0 || length > maxBytes) return false;
    handle = file.openSync(mode: FileMode.read);
    if (!requireJpeg) return true;
    if (length < 256) return false;
    final header = handle.readSync(3);
    if (header.length != 3 ||
        header[0] != 0xff ||
        header[1] != 0xd8 ||
        header[2] != 0xff) {
      return false;
    }
    handle.setPositionSync(length - 2);
    final trailer = handle.readSync(2);
    return trailer.length == 2 && trailer[0] == 0xff && trailer[1] == 0xd9;
  } catch (_) {
    return false;
  } finally {
    try {
      handle?.closeSync();
    } catch (_) {}
  }
}

String _path(String? value) => value?.trim() ?? '';

String _safeOperationId(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  return normalized.isEmpty ? 'unknown' : normalized;
}
