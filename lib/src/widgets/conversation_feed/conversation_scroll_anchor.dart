/// Stable identity plus pixel position in a fixed-extent rendered feed.
/// Null IDs represent archive/notice rows and still occupy layout space.
class ConversationScrollAnchor {
  const ConversationScrollAnchor(
      this.id, this.delta, this.previous, this.next, this.rowExtent);
  final String id;
  final double delta;
  final String? previous;
  final String? next;
  final double rowExtent;

  static ConversationScrollAnchor? capture(List<String?> rows,
      {required double offset,
      required double extent,
      double sampleAhead = 0}) {
    if (rows.isEmpty || extent <= 0) return null;
    var index =
        ((offset + sampleAhead) / extent).floor().clamp(0, rows.length - 1);
    while (index < rows.length && rows[index] == null) index++;
    if (index == rows.length) {
      index--;
      while (index >= 0 && rows[index] == null) index--;
    }
    if (index < 0) return null;
    return ConversationScrollAnchor(
        rows[index]!,
        offset - index * extent,
        index > 0 ? rows[index - 1] : null,
        index + 1 < rows.length ? rows[index + 1] : null,
        extent);
  }

  double? restore(List<String?> rows, {required double extent}) {
    var index = rows.indexOf(id);
    if (index >= 0) return index * extent + delta;
    if (next != null && (index = rows.indexOf(next)) >= 0) {
      return index * extent + delta - rowExtent;
    }
    if (previous != null && (index = rows.indexOf(previous)) >= 0) {
      return index * extent + delta + rowExtent;
    }
    return null;
  }
}
