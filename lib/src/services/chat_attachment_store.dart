import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';

/// Account-scoped files. Task metadata and cache indexes are atomically replaced;
/// the immutable source is also the sender's local copy after sending.
class ChatAttachmentStore {
  ChatAttachmentStore({Future<Directory> Function()? rootProvider})
      : _rootProvider = rootProvider ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _rootProvider;
  final Map<String, Future<void>> _writes = {};

  String _key(String value) => sha256.convert(utf8.encode(value)).toString();
  Future<Directory> accountDirectory(String owner) async {
    if (owner.isEmpty) {
      throw const ChatAttachmentException('SESSION_CHANGED', '未登录');
    }
    final support = await _rootProvider();
    final directory =
        Directory(p.join(support.path, 'chat_attachments_v1', _key(owner)));
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> taskDirectory(String owner, String taskId) async {
    final root = await accountDirectory(owner);
    final directory = Directory(p.join(root.path, 'tasks', _key(taskId)));
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> stageSource(String owner, String taskId, String path) async {
    final source = File(path);
    if (!await source.exists() || await source.length() <= 0) {
      throw const ChatAttachmentException('LOCAL_FILE_MISSING', '附件不可用');
    }
    final dir = await taskDirectory(owner, taskId);
    final extension = p.extension(path).toLowerCase();
    final safeExtension =
        RegExp(r'^\.[a-z0-9]{1,12}$').hasMatch(extension) ? extension : '.bin';
    final dest = File(p.join(dir.path, 'original$safeExtension'));
    if (p.equals(source.absolute.path, dest.absolute.path)) return source;
    final temp = File('${dest.path}.part');
    await source.copy(temp.path);
    if (await temp.length() != await source.length()) {
      throw const ChatAttachmentException('LOCAL_FILE_MISSING', '文件在复制时发生变化');
    }
    return temp.rename(dest.path);
  }

  Future<void> saveTask(
      String owner, String id, Map<String, dynamic> task) async {
    final root = await taskDirectory(owner, id);
    await _writeJson(File(p.join(root.path, 'task.json')), task);
  }

  Future<List<Map<String, dynamic>>> tasks(String owner) async {
    final root = await accountDirectory(owner);
    final dir = Directory(p.join(root.path, 'tasks'));
    if (!await dir.exists()) return [];
    final rows = <Map<String, dynamic>>[];
    await for (final item in dir.list(followLinks: false)) {
      if (item is! Directory) continue;
      final data = await _readJson(File(p.join(item.path, 'task.json')));
      if (data['ownerUserId'] == owner &&
          attachmentString(data['taskId']).isNotEmpty) {
        rows.add(data);
      }
    }
    rows.sort((a, b) =>
        attachmentInt(a['createdAt']).compareTo(attachmentInt(b['createdAt'])));
    return rows;
  }

  Future<File> downloadFile(String owner, String attachmentId, String name,
      {String variant = 'original'}) async {
    final root = await accountDirectory(owner);
    final directory = Directory(
        p.join(root.path, 'downloads', _key('$attachmentId:$variant')));
    await directory.create(recursive: true);
    final safeName = p
        .basename(name.replaceAll('\\', '/'))
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    final limited = safeName.length > 140
        ? safeName.substring(safeName.length - 140)
        : safeName;
    return File(p.join(
        directory.path,
        limited.isEmpty || limited == '.' || limited == '..'
            ? 'attachment.bin'
            : limited));
  }

  Future<File> _cacheIndex(String owner, String id, String variant) async {
    final root = await accountDirectory(owner);
    final directory = Directory(p.join(root.path, 'cache'));
    await directory.create(recursive: true);
    return File(p.join(directory.path, '${_key('$id:$variant')}.json'));
  }

  Future<void> registerLocal(
    String owner,
    String id,
    File file, {
    required int expectedSize,
    String variant = 'original',
  }) async {
    final root = await accountDirectory(owner);
    if (!p.isWithin(root.path, file.absolute.path) ||
        file.path.endsWith('.part') ||
        !await file.exists() ||
        expectedSize <= 0 ||
        await file.length() != expectedSize) {
      throw const ChatAttachmentException('LOCAL_FILE_MISSING', '本地附件不完整');
    }
    final index = await _cacheIndex(owner, id, variant);
    await _writeJson(index, {
      'path': file.absolute.path,
      'sizeBytes': expectedSize,
      'complete': true
    });
  }

  /// Local availability never depends on cloud expiry, policy, or network.
  Future<File?> localFile(String owner, String id,
      {String variant = 'original', int? expectedSize}) async {
    final root = await accountDirectory(owner);
    final index = await _cacheIndex(owner, id, variant);
    final data = await _readJson(index);
    final path = attachmentString(data['path']);
    final size = attachmentInt(data['sizeBytes']);
    if (path.isEmpty ||
        data['complete'] != true ||
        size <= 0 ||
        (expectedSize != null && size != expectedSize) ||
        path.endsWith('.part') ||
        !p.isWithin(root.path, p.absolute(path))) {
      return null;
    }
    final file = File(path);
    try {
      if (await FileSystemEntity.type(path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() != size) {
        return null;
      }
      final handle = await file.open();
      await handle.close();
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _readJson(File file) async {
    try {
      if (await file.exists()) {
        return attachmentMap(jsonDecode(await file.readAsString()));
      }
      // Windows cannot overwrite an existing file with rename. The .previous
      // generation makes the short replacement window recoverable after a crash.
      final previous = File('${file.path}.previous');
      if (await previous.exists()) {
        return attachmentMap(jsonDecode(await previous.readAsString()));
      }
    } catch (_) {}
    return {};
  }

  Future<void> _writeJson(File file, Map<String, dynamic> value) {
    final bytes = jsonEncode(value);
    final previousWrite = _writes[file.path] ?? Future<void>.value();
    final write = previousWrite.catchError((_) {}).then((_) async {
      final temp = File('${file.path}.tmp');
      final previous = File('${file.path}.previous');
      await temp.writeAsString(bytes, flush: true);
      if (await file.exists()) {
        if (await previous.exists()) await previous.delete();
        await file.rename(previous.path);
      }
      await temp.rename(file.path);
      if (await previous.exists()) await previous.delete();
    });
    late Future<void> tracked;
    tracked = write.whenComplete(() {
      if (identical(_writes[file.path], tracked)) _writes.remove(file.path);
    });
    _writes[file.path] = tracked;
    return tracked;
  }
}
