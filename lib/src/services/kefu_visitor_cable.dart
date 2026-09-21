import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/api/kefu_visitor_api.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class KefuVisitorCable {
  KefuVisitorCable({
    required this.onMessage,
    required this.onTyping,
  });

  final void Function(KefuVisitorMessage message) onMessage;
  final void Function(bool typing) onTyping;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnect;
  bool _closed = false;
  int _attempt = 0;
  String? _pubsubToken;

  void connect(String pubsubToken) {
    _pubsubToken = pubsubToken;
    _closed = false;
    _attempt = 0;
    unawaited(_open());
  }

  void dispose() {
    _closed = true;
    _reconnect?.cancel();
    _reconnect = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_channel?.sink.close());
    _channel = null;
  }

  Future<void> _open() async {
    if (_closed) {
      return;
    }
    final token = _pubsubToken?.trim() ?? '';
    if (token.isEmpty) {
      return;
    }
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    try {
      final url = KefuVisitorApi.instance.cableUrl();
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;
      await channel.ready;
      if (_closed) {
        await channel.sink.close();
        return;
      }
      channel.sink.add(
        jsonEncode(<String, dynamic>{
          'command': 'subscribe',
          'identifier': jsonEncode(<String, dynamic>{
            'channel': 'RoomChannel',
            'pubsub_token': token,
          }),
        }),
      );
      _attempt = 0;
      _subscription = channel.stream.listen(
        _onRaw,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CUSTOMER_SERVICE cable open: $e');
      }
      _scheduleReconnect();
    }
  }

  void _onRaw(dynamic raw) {
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! Map) {
        return;
      }
      final map = Map<String, dynamic>.from(decoded);
      final type = map['type']?.toString() ?? '';
      if (type == 'ping' ||
          type == 'welcome' ||
          type == 'confirm_subscription') {
        return;
      }
      final message = map['message'];
      if (message is! Map) {
        return;
      }
      final payload = Map<String, dynamic>.from(message);
      final event = payload['event']?.toString() ?? '';
      if (event == 'conversation_typing_on') {
        onTyping(true);
        return;
      }
      if (event == 'conversation_typing_off') {
        onTyping(false);
        return;
      }
      if (event == 'message.created' || event == 'message.updated') {
        final data = payload['data'];
        if (data is Map) {
          onMessage(
            KefuVisitorMessage.fromJson(Map<String, dynamic>.from(data)),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CUSTOMER_SERVICE cable parse: $e');
      }
    }
  }

  void _scheduleReconnect() {
    if (_closed) {
      return;
    }
    _reconnect?.cancel();
    final shift = _attempt > 4 ? 4 : _attempt;
    var seconds = 2 * (1 << shift);
    if (seconds > 30) {
      seconds = 30;
    }
    _attempt += 1;
    _reconnect = Timer(Duration(seconds: seconds), () {
      unawaited(_open());
    });
  }
}
