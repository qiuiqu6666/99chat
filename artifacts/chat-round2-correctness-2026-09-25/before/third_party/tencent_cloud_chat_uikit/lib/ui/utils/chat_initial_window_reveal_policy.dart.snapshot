/// Reveal can use an already available local message. History completion is a
/// background concern; the caller still owns geometry and loading guards.
class ChatInitialWindowRevealPolicy {
  static bool canReveal({
    required bool alreadyPainted,
    required bool explicitPosition,
    required bool completeWindow,
    required bool hasMessages,
  }) =>
      alreadyPainted ||
      explicitPosition ||
      completeWindow ||
      hasMessages;
}
