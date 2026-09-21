import 'dart:async';

/// Best-effort typing notifications, independent of durable message ordering.
///
/// Keep at most one native operation and one latest pending update per peer.
/// A stuck native Future keeps its slot: a Dart timeout cannot cancel it, and
/// releasing the slot would accumulate native calls or reorder start/stop.
/// Nothing outside this lane awaits its completion.
class TypingStatusSendQueue {
  TypingStatusSendQueue({
    DateTime Function()? now,
    this.maxAge = const Duration(seconds: 5),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Duration maxAge;
  final Map<String, _TypingSlot> _slots = {};
  String? _sessionKey;

  void runLatest({
    required String sessionKey,
    required String receiver,
    required Future<void> Function(bool Function() isFresh) action,
  }) {
    if (_sessionKey != sessionKey) {
      _slots.clear();
      _sessionKey = sessionKey;
    }
    final slot = _slots.putIfAbsent(receiver, _TypingSlot.new);
    slot.pending = _TypingUpdate(_now(), action);
    if (!slot.running) {
      slot.running = true;
      unawaited(_drain(receiver, slot));
    }
  }

  Future<void> _drain(String receiver, _TypingSlot slot) async {
    while (identical(_slots[receiver], slot) && slot.pending != null) {
      final update = slot.pending!;
      slot.pending = null;
      bool isFresh() =>
          identical(_slots[receiver], slot) &&
          slot.pending == null &&
          _now().difference(update.createdAt) < maxAge;
      try {
        if (isFresh()) await update.action(isFresh);
      } catch (_) {
        // Transient notifications have no retry, Outbox or message error UI.
      }
    }
    if (identical(_slots[receiver], slot)) _slots.remove(receiver);
  }
}

class _TypingSlot {
  bool running = false;
  _TypingUpdate? pending;
}

class _TypingUpdate {
  _TypingUpdate(this.createdAt, this.action);

  final DateTime createdAt;
  final Future<void> Function(bool Function() isFresh) action;
}
