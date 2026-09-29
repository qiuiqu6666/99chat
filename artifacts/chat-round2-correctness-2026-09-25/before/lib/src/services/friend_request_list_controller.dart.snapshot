import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/api/friend_request_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/friend_request_record.dart';

typedef RequestWindowLoader = Future<FriendRequestPage> Function(int limit);
typedef RequestHistoryLoader = Future<FriendRequestPage> Function(
    String? cursor);

/// Cursor history and latest-N request endpoints have different paging contracts.
/// Keep their positions separate so a failure never advances another source.
class FriendRequestListController extends ChangeNotifier {
  FriendRequestListController(
      {required this.loadIncoming,
      required this.loadSent,
      required this.loadHistory,
      required this.captureCurrentGuard});

  final RequestWindowLoader loadIncoming;
  final RequestWindowLoader loadSent;
  final RequestHistoryLoader loadHistory;
  final bool Function() Function() captureCurrentGuard;
  static const int pageSize = 20;
  final List<List<FriendRequestRecord>> _rows = [[], [], []];
  final List<bool> _more = [true, true, true];
  final List<Object?> _errors = [null, null, null];
  final List<int> _limits = [0, 0];
  final List<bool> _needsFirst = [true, true, true];
  String? _cursor;
  int _generation = 0;
  bool _loading = false;
  bool _refreshing = false;
  int visibleCount = pageSize;

  List<FriendRequestRecord> get incoming => List.unmodifiable(_rows[0]);
  List<FriendRequestRecord> get sent => List.unmodifiable(_rows[1]);
  List<FriendRequestRecord> get history => List.unmodifiable(_rows[2]);
  bool get loading => _loading;
  bool get failed => _errors.any((error) => error != null);
  bool get hasMore =>
      _more.any((more) => more) ||
      _rows
              .expand((rows) => rows)
              .map((row) => row.identityKey)
              .toSet()
              .length >
          visibleCount;

  Set<String> get visibleKeys {
    final byId = <String, FriendRequestRecord>{
      for (final rows in _rows.reversed)
        for (final row in rows) row.identityKey: row,
    };
    final sorted = byId.values.toList()
      ..sort((a, b) => b.displayTimestamp.compareTo(a.displayTimestamp));
    return sorted.take(visibleCount).map((row) => row.identityKey).toSet();
  }

  Future<void> refresh() async {
    if (_refreshing) return;
    await _load(reset: true);
  }

  Future<void> loadMore() async {
    if (_loading || (!hasMore && !failed)) return;
    await _load(reset: false);
  }

  Future<void> _load({required bool reset}) async {
    final generation = ++_generation;
    final isCurrent = captureCurrentGuard();
    if (reset) {
      for (var source = 0; source < 3; source++) {
        _needsFirst[source] = true;
      }
    }
    _loading = true;
    _refreshing = reset;
    notifyListeners();
    final retryOnly = !reset && failed;
    await Future.wait(List.generate(3, (source) async {
      if (!reset && (retryOnly ? _errors[source] == null : !_more[source])) {
        return;
      }
      final first = _needsFirst[source];
      final limit = source < 2
          ? (first
              ? pageSize
              : (_limits[source] + pageSize).clamp(pageSize, 200))
          : pageSize;
      try {
        final page = source == 0
            ? await loadIncoming(limit)
            : source == 1
                ? await loadSent(limit)
                : await loadHistory(first ? null : _cursor);
        if (generation != _generation || !isCurrent()) return;
        _rows[source] = source == 2 && !first
            ? {
                for (final row in [..._rows[source], ...page.items])
                  row.identityKey: row
              }.values.toList()
            : page.items;
        _more[source] = page.hasMore;
        _errors[source] = null;
        _needsFirst[source] = false;
        if (source < 2) _limits[source] = limit;
        if (source == 2) _cursor = page.nextCursor;
      } catch (error) {
        if (generation == _generation && isCurrent()) _errors[source] = error;
      }
    }));
    if (generation != _generation) return;
    _loading = false;
    _refreshing = false;
    if (isCurrent()) {
      if (reset) {
        visibleCount = pageSize;
      } else if (!failed) {
        visibleCount += pageSize;
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}
