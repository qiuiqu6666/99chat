/// Result of moving the conversation window in one direction.
class ConversationWindowSlideResult {
  const ConversationWindowSlideResult({
    this.added = 0,
    this.trimmedFromStart = 0,
    this.trimmedFromEnd = 0,
  });

  final int added;
  final int trimmedFromStart;
  final int trimmedFromEnd;

  bool get changed => added > 0 || trimmedFromStart > 0 || trimmedFromEnd > 0;

  static const empty = ConversationWindowSlideResult();
}
