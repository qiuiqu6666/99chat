import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef FriendRealtimeLineHandler = void Function(String line);
typedef FriendRealtimeVoidHandler = void Function();

class FriendRealtimeConnection {
  FriendRealtimeConnection({
    required this.onLine,
    required this.onDisconnected,
    this.onProtocolError,
  });

  final FriendRealtimeLineHandler onLine;
  final FriendRealtimeVoidHandler onDisconnected;
  final void Function(Object error)? onProtocolError;

  Socket? _socket;
  StreamSubscription<dynamic>? _subscription;
  final StringBuffer _buffer = StringBuffer();
  Future<void> _sendTail = Future<void>.value();
  int _bufferBytes = 0;
  static const int maxFrameBytes = 256 * 1024;

  Future<void> connect({
    required String host,
    required int port,
    bool useTls = false,
    Duration? connectTimeout,
  }) async {
    await close();
    // 默认 10s：冷启动阶段调用方可传入更短的超时（如 3s），避免阻塞
    // post_home bootstrap 链（连接失败时仍要走 10s 才退出）。
    final timeout = connectTimeout ?? const Duration(seconds: 10);
    final socket = useTls
        ? await SecureSocket.connect(
            host,
            port,
            timeout: timeout,
          )
        : await Socket.connect(
            host,
            port,
            timeout: timeout,
          );
    _socket = socket;
    // One decoder per connection retains incomplete UTF-8 code points across
    // socket reads. Malformed bytes are stream errors, not uncaught callbacks.
    _subscription = socket.cast<List<int>>().transform(utf8.decoder).listen(
      _onChunk,
      onError: (Object error) {
        onProtocolError?.call(error);
        _handleDisconnect();
      },
      onDone: () {
        if (_buffer.isNotEmpty) {
          onProtocolError
              ?.call(const FormatException('Incomplete realtime frame'));
        }
        _handleDisconnect();
      },
      cancelOnError: true,
    );
  }

  void _onChunk(String chunk) {
    final pieces = chunk.split('\n');
    for (var i = 0; i < pieces.length; i++) {
      _bufferBytes += utf8.encode(pieces[i]).length;
      if (_bufferBytes > maxFrameBytes) {
        _handleDisconnect();
        return;
      }
      _buffer.write(pieces[i]);
      if (i == pieces.length - 1) break;
      final line = _buffer.toString().trim();
      _buffer.clear();
      _bufferBytes = 0;
      if (line.isEmpty) continue;
      try {
        onLine(line);
      } catch (_) {
        _handleDisconnect();
        return;
      }
      if (_socket == null) return;
    }
  }

  Future<void> send(Map<String, dynamic> message) {
    final socket = _socket;
    if (socket == null) {
      return Future.error(StateError('Realtime connection is closed'));
    }
    final bytes = utf8.encode('${jsonEncode(message)}\n');
    final operation = _sendTail.then((_) async {
      if (!identical(_socket, socket)) {
        throw StateError('Realtime connection was replaced');
      }
      socket.add(bytes);
      await socket.flush();
    });
    // Ping, auth and presence queries share the same sink. A failed write must
    // not poison the next send, nor may an old queued send use a new socket.
    _sendTail =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  Future<void> close() async {
    final subscription = _subscription;
    final socket = _socket;
    _subscription = null;
    _socket = null;
    _buffer.clear();
    _bufferBytes = 0;
    _sendTail = Future<void>.value();
    // Detach ownership before awaiting; another connect must not be cleared
    // by the continuation of this close. Destroy also settles pending flushes.
    socket?.destroy();
    await subscription?.cancel();
  }

  void _handleDisconnect() {
    if (_socket == null && _subscription == null) {
      return;
    }
    unawaited(close());
    onDisconnected();
  }
}
