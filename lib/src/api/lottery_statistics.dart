class LotteryStatistics {
  LotteryStatistics._(this.snapshotId, this.window, this.sampleCount,
      this.sampleComplete, this.basisIssue, this.items);
  final String snapshotId;
  final int window;
  final int sampleCount;
  final bool sampleComplete;
  final String? basisIssue;
  final List<Map<String, dynamic>> items;
  static const candidateCounts = {
    'special': 49,
    'zodiac': 12,
    'parity': 2,
    'size': 2,
    'head': 5,
    'tail': 10,
    'sumParity': 2,
    'fiveElement': 5,
    'wave': 3,
  };
  factory LotteryStatistics.parse(dynamic raw, String attribute, int window) {
    if (raw is! Map ||
        raw['snapshotId'] is! String ||
        (raw['snapshotId'] as String).isEmpty ||
        raw['window'] != window ||
        raw['sampleCount'] is! int ||
        raw['sampleCount'] < 0 ||
        raw['sampleCount'] > window ||
        raw['sampleComplete'] is! bool ||
        raw['items'] is! List ||
        (raw['items'] as List).length != candidateCounts[attribute]) {
      throw const FormatException('统计数据不完整');
    }
    final seen = <String>{};
    final rows = <Map<String, dynamic>>[];
    for (final item in raw['items'] as List) {
      if (item is! Map ||
          item['value'] is! String ||
          !seen.add(item['value']) ||
          item['order'] is! int ||
          item['count'] is! int ||
          item['count'] < 0 ||
          item['count'] > raw['sampleCount'] ||
          item['ratio'] is! num ||
          !(item['ratio'] as num).isFinite ||
          item['ratio'] < 0 ||
          item['ratio'] > 1 ||
          !['hot', 'cold', 'normal', 'unopened', 'unknown']
              .contains(item['temperature'])) {
        throw const FormatException('统计候选格式错误');
      }
      final omission = item['omission'];
      if (omission != null &&
          (omission is! Map ||
              omission['periods'] is! int ||
              omission['periods'] < 0 ||
              omission['isLowerBound'] is! bool)) {
        throw const FormatException('遗漏数据格式错误');
      }
      rows.add(Map<String, dynamic>.from(item));
    }
    return LotteryStatistics._(raw['snapshotId'], window, raw['sampleCount'],
        raw['sampleComplete'], raw['basisIssue'] as String?, rows);
  }
}
