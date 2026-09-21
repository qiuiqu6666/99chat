import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/controllers/history_window_replay_controller.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/archive_history_provider.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';

const scope = HistoryWindowScope(
    ownerUserID: 'u',
    accountGeneration: 1,
    domainGeneration: 1,
    conversationID: 'g',
    clearEpoch: 0,
    sessionID: 's');
V2TimMessage message(int seq) => V2TimMessage.fromJson({
      'message_msg_id': 'm$seq',
      'message_seq': '$seq',
      'message_server_time': seq,
      'message_risk_type_identified': 0
    });
List<V2TimMessage> rows(int from, int to) =>
    [for (var seq = from; seq <= to; seq++) message(seq)];
HistoryWindowBoundary boundary(int seq) =>
    HistoryWindowBoundary(msgID: 'm$seq', seq: '$seq');
HistoryWindowPage root() => HistoryWindowPage(
    scope: scope,
    pageKey: communityHistoryPageKey(1000, ''),
    messages: rows(951, 1000).reversed.toList(),
    snapshotMaxSeq: 1000,
    pageChecksum: 'root',
    isReplayRoot: true,
    nextOlderCursor: 'opaque-950');
ArchiveHistoryResult transport(int end,
        {int snapshot = 1000, List<ArchiveUnavailableRange> gaps = const []}) =>
    ArchiveHistoryResult(
        messages: rows(end - 49, end),
        hasMore: end > 50,
        olderCursor: end > 50 ? 'opaque-${end - 50}' : null,
        oldestSeq: end - 49,
        newestSeq: end,
        snapshotMaxSeq: snapshot,
        pageChecksum: 'hash-$end',
        unavailableRanges: gaps);

void main() {
  test('four-page slices resume from fixed root and retain at most two pages',
      () async {
    final replay = HistoryWindowReplayController();
    final requests = <String>[];
    final saved = <List<HistoryWindowPage>>[];
    var yields = 0;
    Future<ArchiveHistoryResult> fetch(String cursor) async {
      requests.add(cursor);
      Timer.run(() => yields++);
      return transport(int.parse(cursor.split('-').last));
    }

    Future<HistoryWindowReplayResult> load() => replay.loadNewer(
        root: root(),
        boundary: boundary(650),
        fetchPage: fetch,
        isCurrent: () => true,
        savePages: (pages) async => saved.add(pages),
        maxPages: 999);
    expect((await load()).status, HistoryWindowReplayStatus.pending);
    expect(requests, ['opaque-950', 'opaque-900', 'opaque-850', 'opaque-800']);
    expect(replay.rootResumeCursor, 'opaque-950');
    expect(replay.retainedMessageCount, lessThanOrEqualTo(100));
    expect(yields, 4);
    final completed = await load();
    expect(completed.status, HistoryWindowReplayStatus.ready);
    expect(completed.messages.first.seq, '700');
    expect(completed.messages.last.seq, '651');
    expect(requests.last, 'opaque-650');
    expect(replay.rootResumeCursor, 'opaque-950');
    expect(replay.retainedMessageCount, lessThanOrEqualTo(100));
    for (final pair in saved) {
      expect(pair, hasLength(2));
      expect(pair.first.olderPageKey, pair.last.pageKey);
      expect(pair.last.newerPageKey, pair.first.pageKey);
      expect(pair.last.snapshotMaxSeq, 1000);
    }
    final calls = requests.length;
    expect((await load()).messages, same(completed.messages));
    expect(requests.length, calls,
        reason: 'a rejected UI commit retries the identical accepted page');
  });

  test(
      'missing older edge replays nearest older page without using deep cursor',
      () async {
    final replay = HistoryWindowReplayController();
    final requests = <String>[];
    final result = await replay.loadNewer(
        root: root(),
        boundary: boundary(901),
        direction: HistoryWindowDirection.older,
        isCurrent: () => true,
        savePages: (_) async {},
        fetchPage: (cursor) async {
          requests.add(cursor);
          return transport(int.parse(cursor.split('-').last));
        });
    expect(requests, ['opaque-950', 'opaque-900']);
    expect(result.messages.first.seq, '900');
    expect(result.messages.last.seq, '851');
  });

  test(
      'failed atomic save retries the same cursor and never publishes the page',
      () async {
    final replay = HistoryWindowReplayController();
    final requests = <String>[];
    var fail = true;
    Future<HistoryWindowReplayResult> load() => replay.loadNewer(
        root: root(),
        boundary: boundary(950),
        isCurrent: () => true,
        fetchPage: (cursor) async {
          requests.add(cursor);
          return transport(950);
        },
        savePages: (_) async {
          if (fail) throw StateError('disk full');
        });
    await expectLater(load(), throwsStateError);
    fail = false;
    expect((await load()).status, HistoryWindowReplayStatus.ready);
    expect(requests, ['opaque-950', 'opaque-950']);
  });

  test('scope cancellation after transport prevents any durable write',
      () async {
    final replay = HistoryWindowReplayController();
    var current = true;
    var saves = 0;
    final result = await replay.loadNewer(
        root: root(),
        boundary: boundary(500),
        isCurrent: () => current,
        fetchPage: (_) async {
          current = false;
          return transport(950);
        },
        savePages: (_) async {
          saves++;
        });
    expect(result.status, HistoryWindowReplayStatus.stale);
    expect(saves, 0);
    expect(replay.retainedMessageCount, 0);
  });

  for (final mode in ['410', 'snapshot']) {
    test('$mode never combines different snapshot pages', () async {
      var saves = 0;
      final result = await HistoryWindowReplayController().loadNewer(
          root: root(),
          boundary: boundary(500),
          isCurrent: () => true,
          fetchPage: (_) async {
            if (mode == '410')
              throw const ArchiveHistoryException(
                  statusCode: 410, code: 'INVALID_CURSOR');
            return transport(950, snapshot: 1001);
          },
          savePages: (_) async {
            saves++;
          });
      expect(result.status, HistoryWindowReplayStatus.stale);
      expect(saves, 0);
    });
  }

  test(
      'unproven cross-page gaps are rejected and explicit unavailable ranges are accepted',
      () async {
    Future<HistoryWindowReplayResult> load(
            List<ArchiveUnavailableRange> ranges) =>
        HistoryWindowReplayController().loadNewer(
            root: root(),
            boundary: boundary(940),
            isCurrent: () => true,
            fetchPage: (_) async => transport(940, gaps: ranges),
            savePages: (_) async {});
    await expectLater(load([]), throwsFormatException);
    expect(
        (await load([const ArchiveUnavailableRange(fromSeq: 941, toSeq: 950)]))
            .status,
        HistoryWindowReplayStatus.ready);
  });

  test(
      'replayed stored page preserves its proven older link and checks checksum',
      () async {
    final old = HistoryWindowPage(
        scope: scope,
        pageKey: communityHistoryPageKey(1000, 'opaque-950'),
        messages: rows(901, 950).reversed.toList(),
        snapshotMaxSeq: 1000,
        pageChecksum: 'hash-950',
        olderPageKey: 'already-proven-older');
    final saved = <HistoryWindowPage>[];
    final result = await HistoryWindowReplayController().loadNewer(
        root: root(),
        boundary: boundary(950),
        isCurrent: () => true,
        fetchPage: (_) async => transport(950),
        readPage: (_) async => HistoryWindowReadResult(
            status: HistoryWindowReadStatus.hit, pages: [old]),
        savePages: (pages) async => saved.addAll(pages));
    expect(result.status, HistoryWindowReplayStatus.ready);
    expect(saved.last.olderPageKey, 'already-proven-older');
    final stale = await HistoryWindowReplayController().loadNewer(
        root: root(),
        boundary: boundary(950),
        isCurrent: () => true,
        fetchPage: (_) async => transport(950),
        readPage: (_) async => HistoryWindowReadResult(
                status: HistoryWindowReadStatus.hit,
                pages: [
                  HistoryWindowPage(
                      scope: scope,
                      pageKey: old.pageKey,
                      messages: old.messages,
                      snapshotMaxSeq: 1000,
                      pageChecksum: 'changed')
                ]),
        savePages: (_) async => fail('changed checksum must not be persisted'));
    expect(stale.status, HistoryWindowReplayStatus.stale);
  });
}
