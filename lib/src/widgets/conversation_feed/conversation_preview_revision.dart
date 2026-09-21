import 'package:flutter/foundation.dart';

/// A row only needs eager preview work while its builder is listening.
/// Cached widgets without a mounted element do not keep this active.
class ConversationPreviewRevision extends ValueNotifier<int> {
  ConversationPreviewRevision() : super(0);

  bool get isObserved => hasListeners;
}
