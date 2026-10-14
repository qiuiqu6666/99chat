import 'dart:async';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_draft_submission.dart';

/// Captured before the input is cleared. Identity is never reused by another
/// page/conversation, even when its local revision starts from zero.
class ChatDraftSubmission implements ImDurableTextSubmission {
  @override
  ImDraftSubmissionContext? durableContext;
  ChatDraftSubmission._(
      this.editorIdentity, this.revision, this.text, this.persistenceToken);
  final Object editorIdentity;
  final int revision;
  final String text;
  Object? persistenceToken;
}

/// Debounced local draft text for the open chat page.
class ChatDraftController {
  String? text;
  Timer? _debounce;
  int _writeGeneration = 0;
  int _stateRevision = 0;
  bool _sendClearBarrier = false;
  Object _editorIdentity = Object();
  int get writeGeneration => _writeGeneration;
  bool get shouldSuppressLifecyclePersist => _sendClearBarrier;
  int get stateRevision => _stateRevision;

  static const Duration debounceDuration = Duration(milliseconds: 250);

  ChatDraftSubmission captureSubmission(String value,
          {Object? persistenceToken}) =>
      ChatDraftSubmission._(
          _editorIdentity, _stateRevision, value, persistenceToken);

  bool ownsSubmission(ChatDraftSubmission submission) =>
      identical(submission.editorIdentity, _editorIdentity) &&
      submission.revision == _stateRevision;

  /// A send clear belongs to its submission, not to a new user edit.
  bool clearForSubmission(ChatDraftSubmission submission) {
    if (!ownsSubmission(submission)) return false;
    _writeGeneration++;
    cancelDebounce();
    text = null;
    _sendClearBarrier = true;
    return true;
  }

  void setTextImmediate(String? value) {
    final trimmed = value?.trim() ?? '';
    text = trimmed.isEmpty ? null : value;
  }

  void onChanged(
    String value, {
    required void Function(String raw, int generation) persist,
  }) {
    _sendClearBarrier = false;
    _stateRevision++;
    setTextImmediate(value);
    _debounce?.cancel();
    // Programmatic controller.clear() after send does not emit TextField's
    // onChanged by itself. Once the input layer forwards it explicitly, clear
    // the persisted draft immediately so a fast route pop cannot expose stale
    // sent text in the conversation list.
    if (value.trim().isEmpty) {
      _writeGeneration++;
      persist(value, _writeGeneration);
      return;
    }
    final generation = _writeGeneration;
    _debounce = Timer(debounceDuration, () {
      if (generation == _writeGeneration) {
        persist(value, generation);
      }
    });
  }

  void cancelDebounce() {
    _debounce?.cancel();
    _debounce = null;
  }

  void clear() {
    _writeGeneration++;
    _stateRevision++;
    cancelDebounce();
    text = null;
  }

  void dispose() {
    cancelDebounce();
  }

  bool markSendCompleted([ChatDraftSubmission? submission]) {
    if (submission != null) return clearForSubmission(submission);
    // Compatibility for callers that complete synchronously. Asynchronous
    // send results must always pass their captured submission.
    _sendClearBarrier = true;
    clear();
    return true;
  }

  /// Invalidates work owned by the previous conversation while allowing the
  /// new conversation to start persisting immediately.
  void beginConversation() {
    _editorIdentity = Object();
    _sendClearBarrier = false;
    clear();
  }

  bool canApplyLoadedDraft(int capturedRevision) =>
      !_sendClearBarrier && capturedRevision == _stateRevision;
}

/// Serializes draft mutations without allowing one failed write to poison all
/// writes scheduled after it.
class ChatDraftWriteQueue {
  Future<void> _tail = Future<void>.value();

  Future<void> enqueue(
    Future<void> Function() operation, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        try {
          onError?.call(error, stackTrace);
        } catch (_) {
          // Diagnostics must never become the next queue failure.
        }
      },
    );
    return _tail;
  }
}
