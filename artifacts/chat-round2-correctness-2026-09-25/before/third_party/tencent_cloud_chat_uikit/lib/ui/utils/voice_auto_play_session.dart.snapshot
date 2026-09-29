import 'dart:async';

import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'voice_auto_play_order.dart';

/// Conversation-owned continuation. No message widget needs to stay mounted.
/// [play] finishes when playback finishes/pauses, returning false on failure.
class VoiceAutoPlaySession {
  VoiceAutoPlaySession({
    required this.messagesNewestFirst,
    required this.loadNewer,
    required this.play,
    required this.onSelected,
    required this.onWaiting,
    required this.onError,
  });

  final List<V2TimMessage> Function() messagesNewestFirst;
  final Future<List<V2TimMessage>> Function(V2TimMessage anchor) loadNewer;
  final Future<bool> Function(V2TimMessage message, bool Function() isCurrent)
      play;
  final void Function(V2TimMessage message) onSelected;
  final void Function() onWaiting;
  final void Function(Object error, StackTrace stack) onError;

  int _generation = 0;
  int? _runningGeneration;
  bool _enabled = false;
  bool _waiting = false;
  bool _awaitingCompletion = false;
  bool _advanceRequested = false;
  V2TimMessage? _anchor;
  List<V2TimMessage> _history = [];
  final Set<String> _visited = {};

  bool get enabled => _enabled;
  bool get waiting => _waiting;
  String? get currentMessageId =>
      _anchor == null ? null : soundPlaybackId(_anchor!);

  String? get currentClientMessageId => _anchor?.id;

  void start(V2TimMessage message) {
    cancel();
    _anchor = message;
    _enabled = soundPlaybackId(message) != null;
    _awaitingCompletion = _enabled;
    _remember(message);
  }

  void cancel() {
    _generation++;
    _enabled = false;
    _waiting = false;
    _awaitingCompletion = false;
    _advanceRequested = false;
    _anchor = null;
    _history = [];
    _visited.clear();
  }

  Future<void> completed(String id) async {
    if (!_enabled ||
        !_awaitingCompletion ||
        _anchor == null ||
        !messageMatchesPlaybackId(_anchor!, id)) {
      return;
    }
    _awaitingCompletion = false;
    _advanceRequested = true;
    await _advance(_generation);
  }

  /// At the live edge stay armed, without polling the server on every repaint.
  void messagesChanged() {
    if (!_enabled ||
        !_waiting ||
        _anchor == null ||
        _nextIn(messagesNewestFirst(), _anchor!) == null) {
      return;
    }
    _advanceRequested = true;
    unawaited(_advance(_generation));
  }

  bool _current(int generation) => _enabled && generation == _generation;

  void _remember(V2TimMessage message) {
    for (final id in [message.msgID, message.id]) {
      if (id != null && id.isNotEmpty) _visited.add(id);
    }
  }

  bool _wasVisited(V2TimMessage message) =>
      _visited.contains(message.msgID) || _visited.contains(message.id);

  static int _compare(V2TimMessage a, V2TimMessage b) {
    final time = (a.timestamp ?? 0).compareTo(b.timestamp ?? 0);
    if (time != 0) return time;
    return (int.tryParse(a.seq ?? '') ?? 0)
        .compareTo(int.tryParse(b.seq ?? '') ?? 0);
  }

  V2TimMessage? _nextIn(List<V2TimMessage> messages, V2TimMessage anchor) {
    final id = soundPlaybackId(anchor)!;
    final anchorIndex =
        messages.indexWhere((m) => messageMatchesPlaybackId(m, id));
    // Retain the anchor even when the virtualized history window evicts it.
    final newer = anchorIndex >= 0
        ? messages.take(anchorIndex).toList()
        : messages.where((m) => _compare(m, anchor) > 0).toList();
    for (final message in newer.reversed) {
      if (!_wasVisited(message) && isPlayableSoundMessage(message)) {
        return message;
      }
    }
    return null;
  }

  Future<V2TimMessage?> _next(int generation) async {
    var cursor = _anchor!;
    while (_current(generation)) {
      // Drain the fetched page before a possibly distant live memory window.
      final cached = _nextIn(_history, cursor);
      if (cached != null) return cached;
      final memory = messagesNewestFirst();
      final anchorInMemory = memory.any(
        (m) => messageMatchesPlaybackId(m, soundPlaybackId(cursor)!),
      );
      if (anchorInMemory) {
        final next = _nextIn(memory, cursor);
        if (next != null) return next;
        if (memory.isNotEmpty && soundPlaybackId(memory.first) != null) {
          cursor = memory.first;
        }
      }
      if (_history.isNotEmpty && _compare(_history.first, cursor) > 0) {
        cursor = _history.first;
      }
      final page = await loadNewer(cursor);
      if (!_current(generation)) return null;
      final newer = page
          .where((m) =>
              soundPlaybackId(m) != null &&
              !messageMatchesPlaybackId(m, soundPlaybackId(cursor)!) &&
              _compare(m, cursor) >= 0)
          .toList()
        ..sort((a, b) => _compare(b, a));
      if (newer.isEmpty || newer.every(_wasVisited)) {
        // A freshly arrived/local-only voice may not be in SDK history yet.
        return _nextIn(messagesNewestFirst(), _anchor!);
      }
      _history = newer;
      final next = _nextIn([...newer, cursor], cursor);
      if (next != null) return next;
      for (final message in newer) {
        _remember(message);
      }
      cursor = newer.first;
    }
    return null;
  }

  Future<void> _advance(int generation) async {
    if (_runningGeneration == generation || !_current(generation)) return;
    _runningGeneration = generation;
    _waiting = false;
    try {
      while (_current(generation) && _advanceRequested) {
        _advanceRequested = false;
        final next = await _next(generation);
        if (!_current(generation)) return;
        if (next == null) {
          _waiting = true;
          onWaiting();
          return;
        }
        _anchor = next;
        _remember(next);
        _awaitingCompletion = true;
        onSelected(next);
        var accepted = false;
        try {
          accepted = await play(next, () => _current(generation));
        } catch (error, stack) {
          if (_current(generation)) onError(error, stack);
        }
        if (!_current(generation)) return;
        if (!accepted && _awaitingCompletion) {
          // Missing/unplayable media must not terminate the whole sequence.
          _awaitingCompletion = false;
          _advanceRequested = true;
        }
      }
    } catch (error, stack) {
      if (_current(generation)) {
        _waiting = true;
        onWaiting();
        onError(error, stack);
      }
    } finally {
      if (_runningGeneration == generation) _runningGeneration = null;
    }
  }
}
