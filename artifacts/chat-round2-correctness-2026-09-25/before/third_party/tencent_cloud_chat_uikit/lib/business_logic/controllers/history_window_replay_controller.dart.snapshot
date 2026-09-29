import 'dart:convert';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/archive_history_provider.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';

enum HistoryWindowReplayStatus { ready, pending, stale, miss }

class HistoryWindowReplayResult {
  const HistoryWindowReplayResult(this.status, {this.messages = const []});
  final HistoryWindowReplayStatus status;
  final List<V2TimMessage> messages;
}

String communityHistoryPageKey(int snapshot, String cursor) =>
    'community:$snapshot:${cursor.isEmpty ? 'root' : base64Url.encode(utf8.encode(cursor))}';

HistoryWindowPage linkHistoryPage(HistoryWindowPage page,
        {String? olderPageKey}) =>
    HistoryWindowPage(
        scope: page.scope,
        pageKey: page.pageKey,
        messages: page.messages,
        newerPageKey: page.newerPageKey,
        olderPageKey: olderPageKey,
        requestCursor: page.requestCursor,
        nextOlderCursor: page.nextOlderCursor,
        snapshotMaxSeq: page.snapshotMaxSeq,
        pageChecksum: page.pageChecksum,
        isReplayRoot: page.isReplayRoot);

/// Restarts from a fixed snapshot root when a trimmed newer page is missing.
/// Only one predecessor page and one opaque cursor survive a four-page slice;
/// the normal older-pagination cursor is never read or advanced here.
class HistoryWindowReplayController {
  String? _key;
  HistoryWindowPage? _previous;
  String? _cursor;
  String? rootResumeCursor;
  HistoryWindowReplayResult? _ready;
  int get retainedMessageCount =>
      (_previous?.messages.length ?? 0) + (_ready?.messages.length ?? 0);
  void reset() {
    _key = null;
    _previous = null;
    _cursor = null;
    rootResumeCursor = null;
    _ready = null;
  }

  Future<HistoryWindowReplayResult> loadNewer({
    required HistoryWindowPage root,
    required HistoryWindowBoundary boundary,
    required Future<ArchiveHistoryResult> Function(String cursor) fetchPage,
    required Future<void> Function(List<HistoryWindowPage>) savePages,
    required bool Function() isCurrent,
    Future<HistoryWindowReadResult> Function(String pageKey)? readPage,
    HistoryWindowDirection direction = HistoryWindowDirection.newer,
    int maxPages = 4,
  }) async {
    if (!isCurrent()) {
      reset();
      return const HistoryWindowReplayResult(HistoryWindowReplayStatus.stale);
    }
    final seq = int.tryParse(boundary.seq ?? '');
    final snapshot = root.snapshotMaxSeq;
    if (seq == null || seq <= 0 || snapshot == null || !root.isReplayRoot) {
      return const HistoryWindowReplayResult(HistoryWindowReplayStatus.miss);
    }
    final scope = root.scope;
    final key =
        '${scope.ownerUserID}|${scope.accountGeneration}|${scope.domainGeneration}|'
        '${scope.conversationID}|${scope.clearEpoch}|${scope.sessionID}|${root.pageKey}|${boundary.msgID}|$seq|${direction.name}';
    if (_key != key) {
      reset();
      _key = key;
      _previous = root;
      rootResumeCursor = root.nextOlderCursor;
      _cursor = rootResumeCursor;
      final nearby = root.messages
          .where((message) => direction == HistoryWindowDirection.newer
              ? (int.tryParse(message.seq ?? '') ?? 0) > seq
              : (int.tryParse(message.seq ?? '') ?? 0) < seq)
          .toList();
      final rootOldest = root.messages.isEmpty
          ? null
          : int.tryParse(root.messages.last.seq ?? '');
      if (rootOldest != null &&
          rootOldest <= seq &&
          (direction == HistoryWindowDirection.newer || nearby.isNotEmpty)) {
        return _ready = HistoryWindowReplayResult(
            HistoryWindowReplayStatus.ready,
            messages: nearby);
      }
    }
    if (_ready != null) return _ready!;
    for (var scanned = 0; scanned < maxPages.clamp(1, 4); scanned++) {
      if (!isCurrent()) {
        reset();
        return const HistoryWindowReplayResult(HistoryWindowReplayStatus.stale);
      }
      final requestCursor = _cursor;
      if (requestCursor == null || requestCursor.isEmpty) {
        return const HistoryWindowReplayResult(HistoryWindowReplayStatus.miss);
      }
      ArchiveHistoryResult page;
      try {
        page = await fetchPage(requestCursor);
      } on ArchiveHistoryException catch (error) {
        if (error.statusCode == 410) {
          reset();
          return const HistoryWindowReplayResult(
              HistoryWindowReplayStatus.stale);
        }
        rethrow;
      }
      if (!isCurrent() || page.snapshotMaxSeq != snapshot) {
        reset();
        return const HistoryWindowReplayResult(HistoryWindowReplayStatus.stale);
      }
      final prior = _previous!;
      final priorOldest = prior.messages.isEmpty
          ? null
          : int.tryParse(prior.messages.last.seq ?? '');
      final nextCursor = page.olderCursor?.trim() ?? '';
      var previousSeq = 0;
      final validItems = page.messages.every((message) {
        final itemSeq = int.tryParse(message.seq ?? '') ?? 0;
        if ((message.msgID?.isEmpty ?? true) ||
            itemSeq <= previousSeq ||
            itemSeq > snapshot) return false;
        previousSeq = itemSeq;
        return true;
      });
      if (!validItems ||
          page.messages.length > 50 ||
          (page.pageChecksum?.isEmpty ?? true) ||
          (page.hasMore &&
              (nextCursor.isEmpty || nextCursor == requestCursor)) ||
          (!page.hasMore && nextCursor.isNotEmpty) ||
          (page.messages.isNotEmpty &&
              (page.oldestSeq != int.tryParse(page.messages.first.seq ?? '') ||
                  page.newestSeq !=
                      int.tryParse(page.messages.last.seq ?? '') ||
                  (priorOldest != null && page.newestSeq! >= priorOldest) ||
                  (priorOldest != null &&
                      !_rangesCover(page.unavailableRanges, page.newestSeq! + 1,
                          priorOldest - 1))))) {
        throw const FormatException('Invalid fixed-snapshot replay page');
      }
      final pageKey = communityHistoryPageKey(snapshot, requestCursor);
      final existing = await readPage?.call(pageKey);
      if (!isCurrent() || existing?.status == HistoryWindowReadStatus.stale) {
        reset();
        return const HistoryWindowReplayResult(HistoryWindowReplayStatus.stale);
      }
      final stored =
          existing?.pages.isNotEmpty == true ? existing!.pages.first : null;
      if (stored != null &&
          (stored.snapshotMaxSeq != snapshot ||
              stored.pageChecksum != page.pageChecksum)) {
        reset();
        return const HistoryWindowReplayResult(HistoryWindowReplayStatus.stale);
      }
      final cached = HistoryWindowPage(
          scope: scope,
          pageKey: pageKey,
          messages: page.messages.reversed.toList(growable: false),
          newerPageKey: prior.pageKey,
          olderPageKey: stored?.olderPageKey,
          requestCursor: requestCursor,
          nextOlderCursor: page.hasMore ? nextCursor : null,
          snapshotMaxSeq: snapshot,
          pageChecksum: page.pageChecksum);
      // The link and the page become durable together before advancing.
      await savePages(
          [linkHistoryPage(prior, olderPageKey: cached.pageKey), cached]);
      if (!isCurrent()) {
        reset();
        return const HistoryWindowReplayResult(HistoryWindowReplayStatus.stale);
      }
      _cursor = cached.nextOlderCursor;
      _previous = cached;
      if (page.oldestSeq != null && page.oldestSeq! <= seq) {
        final nearby = cached.messages
            .where((message) => direction == HistoryWindowDirection.newer
                ? (int.tryParse(message.seq ?? '') ?? 0) > seq
                : (int.tryParse(message.seq ?? '') ?? 0) < seq)
            .toList();
        if (direction == HistoryWindowDirection.newer || nearby.isNotEmpty) {
          return _ready = HistoryWindowReplayResult(
              HistoryWindowReplayStatus.ready,
              messages: nearby.isNotEmpty ? nearby : prior.messages);
        }
      }
      await Future<void>.delayed(Duration.zero);
    }
    return const HistoryWindowReplayResult(HistoryWindowReplayStatus.pending);
  }

  static bool _rangesCover(
      List<ArchiveUnavailableRange> ranges, int from, int to) {
    if (to < from) return true;
    var next = from;
    final sorted = List<ArchiveUnavailableRange>.of(ranges)
      ..sort((a, b) => a.fromSeq.compareTo(b.fromSeq));
    for (final range in sorted) {
      if (range.toSeq < next) continue;
      if (range.fromSeq > next) return false;
      next = range.toSeq + 1;
      if (next > to) return true;
    }
    return false;
  }
}
