import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Two private, size-limited files survive process restarts. Only the buffer
/// calls append; exports can read concurrently and fall back to memory.
class RecoveryLogFile {
  RecoveryLogFile(
      {Future<Directory> Function()? directory,
      this.maxBytes = 256 * 1024,
      this.folderName = 'chat_recovery'})
      : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;
  final int maxBytes;
  final String folderName;

  Future<File> _file(String name) async {
    final root = await _directory();
    final folder = Directory('${root.path}/$folderName');
    await folder.create(recursive: true);
    return File('${folder.path}/$name');
  }

  Future<void> append(List<String> events) async {
    final lines = <List<int>>[];
    var size = 0;
    for (final event in events.reversed) {
      final bytes = utf8.encode('$event\n');
      if (size + bytes.length > maxBytes) break;
      lines.insert(0, bytes);
      size += bytes.length;
    }
    if (lines.isEmpty) return;
    final file = await _file('recent.log');
    if (await file.exists() && await file.length() + size > maxBytes) {
      final previous = await _file('previous.log');
      if (await previous.exists()) await previous.delete();
      await file.rename(previous.path);
    }
    await file.writeAsBytes(lines.expand((line) => line).toList(),
        mode: FileMode.append, flush: true);
  }

  Future<String> read() async {
    final output = StringBuffer();
    for (final name in ['previous.log', 'recent.log']) {
      final file = await _file(name);
      if (await file.exists()) {
        // Defend against an unexpectedly large/externally modified file.
        final bytes = await file
            .openRead(0, maxBytes)
            .fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk));
        output.writeln(utf8.decode(bytes, allowMalformed: true));
      }
    }
    return output.toString();
  }
}
