import 'package:flutter/widgets.dart';

/// Stable across rebuilds of one chat page, never shared by stacked routes.
/// A search result can open the same conversation while its original page
/// remains mounted underneath it.
class ChatListStableKeys {
  final Map<String, GlobalKey> _containers = {};
  final Map<String, GlobalKey> _histories = {};

  GlobalKey containerFor(String conversationID) => _containers.putIfAbsent(
      conversationID.trim(),
      () => GlobalKey(debugLabel: 'chat_container_$conversationID'));

  GlobalKey historyFor(String conversationID) => _histories.putIfAbsent(
      conversationID.trim(),
      () => GlobalKey(debugLabel: 'chat_history_$conversationID'));
}
