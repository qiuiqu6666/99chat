import 'dart:async';
import 'dart:typed_data';

/// Shared across a page's visible rows. Running work retains its slot until
/// actually finished; clearing a queue never pretends to cancel a download.
class BoundedFileLoader {
  BoundedFileLoader(this.download,
      {this.maxConcurrent = 2,
      this.maxBytes = 24 * 1024 * 1024,
      this.maxPending = 32});
  final Future<Uint8List> Function(String) download;
  final int maxConcurrent, maxBytes, maxPending;
  final cache = <String, Uint8List>{};
  final _pending = <String, Completer<Uint8List?>>{};
  final _inFlight = <String, Future<Uint8List?>>{};
  int _running = 0, _bytes = 0, _generation = 0;
  bool _disposed = false;
  int get cachedBytes => _bytes;

  Future<Uint8List?> load(String id, {bool priority = false}) {
    if (_disposed) return Future.value(null);
    final bytes = cache.remove(id);
    if (bytes != null) {
      cache[id] = bytes;
      return Future.value(bytes);
    }
    final running = _inFlight[id];
    if (running != null) return running;
    final queued = _pending[id];
    if (queued != null) return queued.future;
    if (_pending.length >= maxPending) {
      if (!priority) return Future.value(null);
      _pending.remove(_pending.keys.last)?.complete(null);
    }
    final result = Completer<Uint8List?>();
    if (priority) {
      final rest = Map<String, Completer<Uint8List?>>.from(_pending);
      _pending
        ..clear()
        ..[id] = result
        ..addAll(rest);
    } else {
      _pending[id] = result;
    }
    _drain();
    return result.future;
  }

  void _drain() {
    while (!_disposed && _running < maxConcurrent && _pending.isNotEmpty) {
      final id = _pending.keys.first;
      final result = _pending.remove(id)!;
      final generation = _generation;
      _inFlight[id] = result.future;
      _running++;
      Future<Uint8List>.sync(() => download(id)).then((bytes) {
        if (_disposed || generation != _generation) {
          result.complete(null);
          return;
        }
        if (bytes.lengthInBytes <= maxBytes) {
          while (cache.isNotEmpty && _bytes + bytes.lengthInBytes > maxBytes) {
            _bytes -= cache.remove(cache.keys.first)!.lengthInBytes;
          }
          cache[id] = bytes;
          _bytes += bytes.lengthInBytes;
        }
        result.complete(bytes);
      }, onError: (Object error, StackTrace stack) {
        result.completeError(error, stack);
      }).whenComplete(() {
        _inFlight.remove(id);
        _running--;
        _drain();
      });
    }
  }

  void clear() {
    _generation++;
    cache.clear();
    _bytes = 0;
    for (final task in _pending.values) {
      task.complete(null);
    }
    _pending.clear();
  }

  void dispose() {
    _disposed = true;
    clear();
  }
}
