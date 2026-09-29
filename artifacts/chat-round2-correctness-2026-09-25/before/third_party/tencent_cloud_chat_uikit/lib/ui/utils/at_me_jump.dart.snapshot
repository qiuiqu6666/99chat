/// Pure helpers for group 「@我」 tongue jump (around-seq window).
class AtMeJump {
  AtMeJump._();

  /// Returns null when [raw] cannot be used as `lastMsgSeq`.
  static int? parseTargetSeq(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    return int.tryParse(text);
  }

  /// Canonical seq string for list lookup (`"1081"` not `" 1081 "`).
  static String? canonicalSeqString(String? raw) {
    final n = parseTargetSeq(raw);
    return n?.toString();
  }

  /// Visible-list index for an @ jump: exact seq, else nearest positive seq.
  /// [seqs] is aligned with the visible list; null / non-positive rows are ignored.
  static int? pickVisibleIndex(List<int?> seqs, int targetSeq) {
    int? exact;
    int? bestIndex;
    var bestDelta = 1 << 30;
    for (var i = 0; i < seqs.length; i++) {
      final seq = seqs[i];
      if (seq == null || seq <= 0) {
        continue;
      }
      if (seq == targetSeq) {
        exact = i;
        break;
      }
      final delta = (seq - targetSeq).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        bestIndex = i;
      }
    }
    return exact ?? bestIndex;
  }
}
