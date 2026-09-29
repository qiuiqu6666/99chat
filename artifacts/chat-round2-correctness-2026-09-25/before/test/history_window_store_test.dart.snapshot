import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';

HistoryWindowScope scope(
        {String owner = 'owner',
        String conv = 'group_g',
        String session = 's1',
        int epoch = 0,
        int account = 1,
        int domain = 1}) =>
    HistoryWindowScope(
        ownerUserID: owner,
        accountGeneration: account,
        domainGeneration: domain,
        conversationID: conv,
        clearEpoch: epoch,
        sessionID: session);
V2TimMessage message(int id, {String? text, bool self = false}) =>
    V2TimMessage.fromJson({
      'message_msg_id': 'm$id',
      'message_seq': id,
      'message_server_time': id,
      'message_risk_type_identified': 0,
    })
      ..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC
      ..isSelf = self
      ..isRead = false
      ..elemType = 1
      ..groupID = 'g'
      ..textElem = V2TimTextElem(text: text ?? 'text$id');
HistoryWindowPage page(String key, List<int> ids,
        {HistoryWindowScope? s,
        String? older,
        String? newer,
        int snapshot = 1000,
        bool root = false}) =>
    HistoryWindowPage(
        scope: s ?? scope(),
        pageKey: key,
        messages: ids.map(message).toList(),
        newerPageKey: newer,
        olderPageKey: older,
        snapshotMaxSeq: snapshot,
        requestCursor: 'opaque-$key',
        nextOlderCursor: 'next-$key',
        isReplayRoot: root);
List<String?> ids(List<V2TimMessage> messages) =>
    messages.map((m) => m.msgID).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late HistoryWindowStore store;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SqfliteLifecycleGuard.instance.debugReset();
    MessagePersistCoordinator.instance.resetForTest();
    directory = await Directory.systemTemp.createTemp('history-window-sqlite-');
    store = HistoryWindowStore(
        debugDatabasePath: p.join(directory.path, 'window.db'));
  });
  tearDown(() async {
    SqfliteLifecycleGuard.instance.debugReset();
    await store.closeIfOpen();
    await directory.delete(recursive: true);
  });

  test(
      'real SQLite walks linked pages in both directions and preserves opaque metadata on reopen',
      () async {
    await store.savePage(page('a', [9, 8, 7], older: 'b', root: true));
    await store.savePage(page('b', [6, 5, 4], newer: 'a', older: 'c'));
    await store.savePage(page('c', [3, 2, 1], newer: 'b'));
    await store.closeIfOpen();
    var result = await store.readAdjacent(
        scope: scope(),
        boundary: const HistoryWindowBoundary(msgID: 'm8'),
        direction: HistoryWindowDirection.older,
        limit: 5);
    expect(result.status, HistoryWindowReadStatus.hit);
    expect(ids(result.messages), ['m7', 'm6', 'm5', 'm4', 'm3']);
    result = await store.readAdjacent(
        scope: scope(),
        boundary: const HistoryWindowBoundary(msgID: 'm2'),
        direction: HistoryWindowDirection.newer,
        limit: 5);
    expect(ids(result.messages), ['m7', 'm6', 'm5', 'm4', 'm3']);
    final root = await store.readReplayRoot(scope());
    expect(root.pages.single.requestCursor, 'opaque-a');
    expect(root.snapshotMaxSeq, 1000);
  });

  test(
      'resaving a trimmed page preserves same-snapshot outer links and replay metadata',
      () async {
    await store.savePages([
      page('a', List.generate(50, (i) => 150 - i), older: 'b', root: true),
      page('b', List.generate(50, (i) => 100 - i), newer: 'a', older: 'c'),
      page('c', List.generate(50, (i) => 50 - i), newer: 'b'),
    ]);
    await store.savePages([
      HistoryWindowPage(
          scope: scope(),
          pageKey: 'a',
          messages: List.generate(50, (i) => message(150 - i)),
          snapshotMaxSeq: 1000),
      page('b', List.generate(50, (i) => 100 - i)),
    ]);
    final saved =
        (await store.readPage(scope: scope(), pageKey: 'b')).pages.single;
    expect(saved.newerPageKey, 'a');
    expect(saved.olderPageKey, 'c');
    final root = await store.readReplayRoot(scope());
    expect(root.pageKeys, ['a']);
    expect(root.pages.single.requestCursor, 'opaque-a');
    expect(root.pages.single.nextOlderCursor, 'next-a');
    final newer = await store.readAdjacent(
        scope: scope(),
        boundary: const HistoryWindowBoundary(msgID: 'm100'),
        direction: HistoryWindowDirection.newer);
    expect(ids(newer.messages), List.generate(50, (i) => 'm${150 - i}'));
    final older = await store.readAdjacent(
        scope: scope(),
        boundary: const HistoryWindowBoundary(msgID: 'm51'),
        direction: HistoryWindowDirection.older);
    expect(ids(older.messages), List.generate(50, (i) => 'm${50 - i}'));
    await store.savePage(page('b', [100, 99], snapshot: 2000));
    final replaced =
        (await store.readPage(scope: scope(), pageKey: 'b')).pages.single;
    expect(replaced.newerPageKey, isNull);
    expect(replaced.olderPageKey, isNull);
  });

  test(
      'same-message overlapping pages continue in both directions without sequence guesses',
      () async {
    await store.savePages([
      page('newer-half', List.generate(50, (i) => 100 - i)),
      page('older-half', List.generate(50, (i) => 75 - i)),
      page('sequence-neighbor-only', List.generate(25, (i) => 25 - i)),
      page('wrong-snapshot', List.generate(50, (i) => 60 - i), snapshot: 999),
    ]);
    // Most recent matching page puts the boundary exactly at its near edge.
    final newer = await store.readAdjacent(
        scope: scope(),
        boundary: const HistoryWindowBoundary(msgID: 'm75'),
        direction: HistoryWindowDirection.newer);
    expect(ids(newer.messages), List.generate(25, (i) => 'm${100 - i}'));
    expect(newer.pageKeys.toSet(), {'newer-half', 'older-half'});
    await store.readPage(scope: scope(), pageKey: 'newer-half');
    final older = await store.readAdjacent(
        scope: scope(),
        boundary: const HistoryWindowBoundary(msgID: 'm51'),
        direction: HistoryWindowDirection.older);
    expect(ids(older.messages), List.generate(25, (i) => 'm${50 - i}'));
    expect(older.pageKeys.toSet(), {'newer-half', 'older-half'});
    expect(older.missingDirection, HistoryWindowDirection.older);
    expect(older.scannedRows, 100);
    expect(older.messages.map((m) => m.msgID).toSet().length,
        older.messages.length);
    await store.recordMutation(const HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 0,
        eventID: 'delete-overlap-frontier',
        msgID: 'm51',
        kind: HistoryWindowMutationKind.delete));
    await store.readPage(scope: scope(), pageKey: 'newer-half');
    final deletedFrontier = await store.readAdjacent(
        scope: scope(),
        boundary: const HistoryWindowBoundary(msgID: 'm60'),
        direction: HistoryWindowDirection.older);
    expect(ids(deletedFrontier.messages), [
      for (var i = 59; i >= 26; i--)
        if (i != 51) 'm$i'
    ]);
  });

  test(
      'overlap traversal retains the four-page budget and resumes without duplicate rows or cycles',
      () async {
    await store.savePages([
      for (var i = 0; i < 10; i++)
        page('overlap$i', List.generate(50, (j) => 300 - i * 25 - j)),
    ]);
    var boundary = const HistoryWindowBoundary(msgID: 'm300');
    final collected = <String?>[];
    for (var attempt = 0; attempt < 5; attempt++) {
      final result = await store.readAdjacent(
          scope: scope(),
          boundary: boundary,
          direction: HistoryWindowDirection.older,
          limit: 200);
      expect(result.pageKeys.length, lessThanOrEqualTo(4));
      expect(result.scannedRows, lessThanOrEqualTo(200));
      collected.addAll(ids(result.messages));
      if (!result.scanLimitReached) break;
      expect(result.continuationBoundary!.msgID, isNot(boundary.msgID));
      boundary = result.continuationBoundary!;
    }
    expect(collected, List.generate(274, (i) => 'm${299 - i}'));
    expect(collected.toSet().length, collected.length);
    // Explicit cyclic links are also bounded and never emit an ID twice.
    await store.savePages([
      page('cycle-a', [10, 9],
          older: 'cycle-b', newer: 'cycle-b', s: scope(session: 'cycle')),
      page('cycle-b', [8, 7],
          older: 'cycle-a', newer: 'cycle-a', s: scope(session: 'cycle')),
    ]);
    final cycle = await store.readAdjacent(
        scope: scope(session: 'cycle'),
        boundary: const HistoryWindowBoundary(msgID: 'm10'),
        direction: HistoryWindowDirection.older,
        limit: 200);
    expect(ids(cycle.messages), ['m9', 'm8', 'm7']);
    expect(cycle.scanLimitReached, isFalse);
    expect(cycle.pageKeys, hasLength(2));
  });

  test(
      'sequence adjacency without reciprocal link or matching snapshot is a miss',
      () async {
    await store.savePage(page('a', [9, 8, 7], older: 'b', root: true));
    await store.savePage(page('b', [6, 5, 4], snapshot: 999));
    final result = await store.readAdjacent(
        scope: scope(),
        boundary: const HistoryWindowBoundary(msgID: 'm7', seq: '7'),
        direction: HistoryWindowDirection.older);
    expect(result.status, HistoryWindowReadStatus.miss);
    expect(result.messages, isEmpty);
    expect(result.missingDirection, HistoryWindowDirection.older);
    expect(result.pages.single.nextOlderCursor, 'next-a');
  });

  test(
      'root pages, identities and session metadata participate in all cache budgets',
      () async {
    await store.closeIfOpen();
    store = HistoryWindowStore(
        debugDatabasePath: p.join(directory.path, 'small.db'),
        maxPages: 3,
        maxRows: 6,
        maxBytes: 16000,
        maxSessions: 2);
    for (var i = 0; i < 30; i++) {
      await store.savePage(page('p$i', [i * 2 + 2, i * 2 + 1],
          s: scope(session: 's${i ~/ 3}'), root: i % 3 == 0));
      final stats = await store.debugStatistics();
      expect(stats['pages'], lessThanOrEqualTo(3));
      expect(stats['rows'], lessThanOrEqualTo(6));
      expect(stats['bytes'], lessThanOrEqualTo(16000));
      expect(stats['sessions'], lessThanOrEqualTo(2));
      expect(stats['page_ids'], stats['rows']);
    }
    expect((await store.readReplayRoot(scope())).status,
        HistoryWindowReadStatus.miss);
    await store.closeIfOpen();
    final stats = await store.debugStatistics();
    expect(stats['rows'], lessThanOrEqualTo(6));
  });

  test(
      'byte budget independently evicts and oversized page fails without destroying old window',
      () async {
    await store.closeIfOpen();
    store = HistoryWindowStore(
        debugDatabasePath: p.join(directory.path, 'bytes.db'), maxBytes: 8000);
    for (var i = 0; i < 20; i++) {
      await store.savePage(HistoryWindowPage(
          scope: scope(),
          pageKey: '$i',
          messages: [message(i, text: 'x' * 1000)],
          isReplayRoot: i == 0));
    }
    final stats = await store.debugStatistics();
    expect(stats['bytes'], lessThanOrEqualTo(8000));
    expect(stats['pages'], lessThan(20));
    await expectLater(
        store.savePage(HistoryWindowPage(
            scope: scope(),
            pageKey: 'huge',
            messages: [message(999, text: 'x' * 9000)])),
        throwsStateError);
    expect((await store.debugStatistics())['pages'], stats['pages']);
  });

  test(
      'cache eviction leaves a genuine hole instead of joining sequence ranges',
      () async {
    await store.closeIfOpen();
    store = HistoryWindowStore(
        debugDatabasePath: p.join(directory.path, 'hole.db'), maxPages: 2);
    await store.savePage(page('b', [6, 5, 4], newer: 'a', older: 'c'));
    await store.savePage(page('a', [9, 8, 7], older: 'b', root: true));
    await store.savePage(page('c', [3, 2, 1], newer: 'b'));
    final result = await store.readAdjacent(
        scope: scope(),
        boundary: const HistoryWindowBoundary(msgID: 'm7'),
        direction: HistoryWindowDirection.older);
    expect(result.status, HistoryWindowReadStatus.miss);
    expect(result.pageKeys, ['a']);
    expect(result.messages, isEmpty);
  });

  test(
      'more than 512 edit/revoke/delete authority facts survive LRU and database reopen',
      () async {
    for (var i = 0; i < 700; i++) {
      await store.recordMutation(HistoryWindowMutation(
          ownerUserID: 'owner',
          conversationID: 'group_g',
          clearEpoch: 0,
          eventID: 'edit-$i',
          msgID: 'm$i',
          kind: HistoryWindowMutationKind.edit,
          message: message(i, text: 'edited-$i'),
          revision: i + 1));
    }
    await store.recordMutation(const HistoryWindowMutation(
        ownerUserID: 'owner',
        clearEpoch: 0,
        eventID: 'revoke-5',
        msgID: 'm5',
        kind: HistoryWindowMutationKind.revoke,
        revision: 701));
    await store.recordMutation(const HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 0,
        eventID: 'delete-6',
        msgID: 'm6',
        kind: HistoryWindowMutationKind.delete,
        revision: 702));
    await store.closeIfOpen();
    final fresh = List.generate(700, message);
    final applied = await store.applyMutations(scope: scope(), messages: fresh);
    expect(applied.length, 699);
    expect(applied.first.textElem!.text, 'edited-0');
    expect(applied.last.textElem!.text, 'edited-699');
    expect(applied.singleWhere((m) => m.msgID == 'm5').status,
        MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED);
    expect(fresh[5].status, MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC);
    expect((await store.debugStatistics())['mutations'], 702);
    final other = await store
        .applyMutations(scope: scope(owner: 'other'), messages: [message(5)]);
    expect(other.single.status, MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC);
    final otherConv = await store.applyMutations(
        scope: scope(conv: 'group_other'), messages: [message(5), message(6)]);
    expect(
        otherConv.first.status, MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED);
    expect(otherConv.last.textElem!.text, 'text6');
  });

  test(
      'restore requires exact token and cannot undo a different/newer deletion',
      () async {
    await store.recordMutation(const HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 0,
        eventID: 'del1',
        msgID: 'm1',
        kind: HistoryWindowMutationKind.delete,
        pending: true,
        revision: 10));
    await store.recordMutation(HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 0,
        eventID: 'wrong',
        msgID: 'm1',
        kind: HistoryWindowMutationKind.restore,
        restoreMutationToken: 'other',
        message: message(1, text: 'bad'),
        revision: 11));
    expect(await store.applyMutations(scope: scope(), messages: [message(1)]),
        isEmpty);
    await store.recordMutation(HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 0,
        eventID: 'restore1',
        msgID: 'm1',
        kind: HistoryWindowMutationKind.restore,
        restoreMutationToken: 'del1',
        message: message(1, text: 'restored'),
        revision: 12));
    expect(
        (await store.applyMutations(scope: scope(), messages: [message(1)]))
            .single
            .textElem!
            .text,
        'text1');
    await store.recordMutation(const HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 0,
        eventID: 'del2',
        msgID: 'm1',
        kind: HistoryWindowMutationKind.delete,
        revision: 13));
    expect(await store.applyMutations(scope: scope(), messages: [message(1)]),
        isEmpty);
  });

  test(
      'deleted cached pages are skipped, limit counts authoritative visible rows',
      () async {
    await store.savePage(page('a', [9, 8, 7], older: 'b'));
    await store.savePage(page('b', [6, 5, 4], newer: 'a', older: 'c'));
    await store.savePage(page('c', [3, 2, 1], newer: 'b'));
    for (final i in [6, 5, 4]) {
      await store.recordMutation(HistoryWindowMutation(
          ownerUserID: 'owner',
          conversationID: 'group_g',
          clearEpoch: 0,
          eventID: 'd$i',
          msgID: 'm$i',
          kind: HistoryWindowMutationKind.delete));
    }
    final result = await store.readAdjacent(
        scope: scope(),
        boundary: const HistoryWindowBoundary(msgID: 'm7'),
        direction: HistoryWindowDirection.older,
        limit: 2);
    expect(ids(result.messages), ['m3', 'm2']);
  });

  test(
      'bulk page writes are atomic and same checksum cannot hide an in-place mutation',
      () async {
    await store.savePage(page('before', [100], root: true));
    final huge = HistoryWindowPage(
        scope: scope(),
        pageKey: 'huge',
        messages: List.generate(12801, message));
    await expectLater(
        store.savePages([
          page('partial', [90]),
          huge
        ]),
        throwsStateError);
    expect((await store.readPage(scope: scope(), pageKey: 'partial')).status,
        HistoryWindowReadStatus.hit);
    expect((await store.readReplayRoot(scope())).pageKeys, ['before']);
    final row = message(80)
      ..timestamp = 9876
      ..groupID = 'community-g';
    final mutable = HistoryWindowPage(
        scope: scope(),
        pageKey: 'mutable',
        messages: [row],
        pageChecksum: 'constant');
    await store.savePages([
      mutable,
      page('next', [79], newer: 'mutable')
    ]);
    await store.savePage(mutable);
    row.textElem!.text = 'changed in place';
    await store.savePage(mutable);
    final restored = (await store.readPage(scope: scope(), pageKey: 'mutable'))
        .messages
        .single;
    expect(restored.textElem!.text, 'changed in place');
    expect(restored.timestamp, 9876);
    expect(restored.groupID, 'community-g');
  });

  test(
      'default production page and row limits hold after 15000 cached messages',
      () async {
    for (var i = 0; i < 300; i++) {
      await store.savePage(page(
          'page-$i', List.generate(50, (j) => 15000 - i * 50 - j),
          older: i < 299 ? 'page-${i + 1}' : null,
          newer: i > 0 ? 'page-${i - 1}' : null,
          root: i == 0));
    }
    final stats = await store.debugStatistics();
    expect(stats['pages'], lessThanOrEqualTo(256));
    expect(stats['rows'], lessThanOrEqualTo(12800));
    expect(stats['bytes'], lessThanOrEqualTo(32 * 1024 * 1024));
    expect(stats['page_ids'], stats['rows']);
    final replay = await store.readReplayRoot(scope());
    expect(replay.status, HistoryWindowReadStatus.hit);
    expect(replay.pageKeys, ['page-0']);
    expect(replay.messages.first.msgID, 'm15000');
    expect((await store.readPage(scope: scope(), pageKey: 'page-1')).status,
        HistoryWindowReadStatus.miss);
    await store.closeIfOpen();
    expect((await store.readReplayRoot(scope())).pageKeys, ['page-0']);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
      'root-only budget overflow evicts whole sessions and never silently drops a live replay root',
      () async {
    await store.closeIfOpen();
    store = HistoryWindowStore(
        debugDatabasePath: p.join(directory.path, 'root-budget.db'),
        maxPages: 2);
    for (var i = 0; i < 3; i++) {
      await store.savePage(page('root-$i', [i],
          s: scope(session: 'root-session-$i'), root: true));
    }
    expect(
        (await store.readReplayRoot(scope(session: 'root-session-0'))).status,
        HistoryWindowReadStatus.miss);
    expect(
        (await store.readReplayRoot(scope(session: 'root-session-1'))).pageKeys,
        ['root-1']);
    expect(
        (await store.readReplayRoot(scope(session: 'root-session-2'))).pageKeys,
        ['root-2']);
    expect((await store.debugStatistics())['sessions'], 2);
    await expectLater(
        store.savePage(
            page('cannot-fit', [4], s: scope(session: 'root-session-2'))),
        throwsStateError);
    expect(
        (await store.readReplayRoot(scope(session: 'root-session-2'))).pageKeys,
        ['root-2']);
    expect((await store.debugStatistics())['pages'], 2);
  });

  test(
      'clear epoch retires only old pending completions and frees all eight slots',
      () async {
    Future<void> pending(String id, String token, int epoch, int revision) =>
        store.recordMutation(HistoryWindowMutation(
            ownerUserID: 'owner',
            conversationID: 'group_g',
            clearEpoch: epoch,
            eventID: token,
            msgID: id,
            kind: HistoryWindowMutationKind.delete,
            pending: true,
            sourceKey: 'command:test',
            revision: revision));
    Future<void> complete(String id, String token, int epoch,
            HistoryWindowMutationKind kind) =>
        store.recordMutation(HistoryWindowMutation(
            ownerUserID: 'owner',
            conversationID: 'group_g',
            clearEpoch: epoch,
            eventID: 'done-$token',
            msgID: id,
            kind: kind,
            restoreMutationToken: token));
    await store.recordMutation(HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 0,
        eventID: 'confirmed',
        msgID: 'm1',
        kind: HistoryWindowMutationKind.edit,
        message: message(1, text: 'confirmed edit'),
        sourceKey: 'sdk',
        revision: 999));
    for (var i = 0; i < 8; i++) {
      await pending('m1', 'old$i', 0, 100 + i);
    }
    await pending('old-terminal', 'old-ended', 0, 200);
    await complete(
        'old-terminal', 'old-ended', 0, HistoryWindowMutationKind.restore);
    await pending('next-pending', 'next', 1, 300);
    await pending('next-terminal', 'next-ended', 1, 301);
    await complete(
        'next-terminal', 'next-ended', 1, HistoryWindowMutationKind.restore);
    await store.clearConversation(
        ownerUserID: 'owner', conversationID: 'group_g', clearEpoch: 1);
    var stats = await store.debugStatistics();
    expect(stats['mutation_pending'], 1);
    expect(stats['mutation_terminal'], 1);
    expect(stats['mutations'], 1);
    for (final kind in [
      HistoryWindowMutationKind.settle,
      HistoryWindowMutationKind.restore
    ]) {
      await expectLater(complete('m1', 'old0', 0, kind),
          throwsA(isA<HistoryWindowStaleScope>()));
    }
    expect(
        (await store
                .applyMutations(scope: scope(epoch: 1), messages: [message(1)]))
            .single
            .textElem!
            .text,
        'confirmed edit');
    await store.recordMutation(HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 1,
        eventID: 'late-sdk',
        msgID: 'm1',
        kind: HistoryWindowMutationKind.edit,
        message: message(1, text: 'old SDK'),
        sourceKey: 'sdk',
        revision: 900));
    expect(
        (await store
                .applyMutations(scope: scope(epoch: 1), messages: [message(1)]))
            .single
            .textElem!
            .text,
        'confirmed edit');
    // Same command source may restart at a lower sequence after the clear;
    // obsolete old-epoch command watermarks cannot consume its new intent.
    for (var i = 0; i < 8; i++) {
      await pending('m1', 'new$i', 1, i + 1);
    }
    expect((await store.debugStatistics())['mutation_pending'], 9);
    for (var i = 0; i < 8; i++) {
      await complete('m1', 'new$i', 1, HistoryWindowMutationKind.restore);
    }
    expect((await store.debugStatistics())['mutation_pending'], 1);
    await store.closeIfOpen();
    expect((await store.debugStatistics())['mutation_pending'], 1);
    expect(
        (await store
                .applyMutations(scope: scope(epoch: 1), messages: [message(1)]))
            .single
            .textElem!
            .text,
        'confirmed edit');
  });

  test(
      'v1 metadata upgrades conservatively and a later clear retires command state',
      () async {
    await store.clearConversation(
        ownerUserID: 'owner', conversationID: 'group_g', clearEpoch: 1);
    await store.recordMutation(const HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 1,
        eventID: 'pending',
        msgID: 'm1',
        kind: HistoryWindowMutationKind.delete,
        pending: true,
        sourceKey: 'command:test',
        revision: 1));
    await store.recordMutation(const HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 1,
        eventID: 'done',
        msgID: 'm1',
        kind: HistoryWindowMutationKind.settle,
        restoreMutationToken: 'pending'));
    await store.closeIfOpen();
    final legacy = await openDatabase(store.debugDatabasePath!);
    await legacy
        .execute('ALTER TABLE hw_mutation_terminal DROP COLUMN clear_epoch');
    await legacy
        .execute('ALTER TABLE hw_mutation_versions DROP COLUMN clear_epoch');
    await legacy
        .execute('ALTER TABLE hw_mutation_versions DROP COLUMN is_command');
    await legacy.execute('DROP INDEX hw_pending_process');
    await legacy
        .execute('ALTER TABLE hw_mutation_pending DROP COLUMN process_id');
    await legacy.execute('PRAGMA user_version=1');
    await legacy.close();
    expect((await store.debugStatistics())['mutation_terminal'], 1);
    await store.clearConversation(
        ownerUserID: 'owner', conversationID: 'group_g', clearEpoch: 2);
    final stats = await store.debugStatistics();
    expect(stats['mutation_pending'], 0);
    expect(stats['mutation_terminal'], 0);
    expect(stats['mutation_versions'], 0);
    expect(stats['mutations'], 1);
    expect(
        await store
            .applyMutations(scope: scope(epoch: 2), messages: [message(1)]),
        isEmpty);
  });

  test(
      'new process expires optimistic commands and pages but preserves confirmed SDK authority',
      () async {
    await store.closeIfOpen();
    final path = p.join(directory.path, 'process.db');
    store = HistoryWindowStore(
        debugDatabasePath: path, debugProcessID: 'process-a');
    for (var i = 0; i < 8; i++) {
      await store.recordMutation(HistoryWindowMutation(
          ownerUserID: 'owner',
          conversationID: 'group_g',
          clearEpoch: 0,
          eventID: 'optimistic-$i',
          msgID: 'm1',
          kind: HistoryWindowMutationKind.revoke,
          pending: true,
          sourceKey: 'command:process-a',
          revision: i + 1));
    }
    await store.recordMutation(const HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 0,
        eventID: 'sdk-confirmed',
        msgID: 'm2',
        kind: HistoryWindowMutationKind.revoke));
    await store.recordMutation(const HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 0,
        eventID: 'confirmed-delete',
        msgID: 'm3',
        kind: HistoryWindowMutationKind.delete));
    final optimisticCopy = message(1)
      ..status = MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED;
    await store.savePage(HistoryWindowPage(
        scope: scope(session: 'old-window'),
        pageKey: 'old-root',
        messages: [optimisticCopy],
        isReplayRoot: true));
    await store.closeIfOpen();
    store = HistoryWindowStore(
        debugDatabasePath: path, debugProcessID: 'process-a');
    expect((await store.debugStatistics())['mutation_pending'], 8);
    expect(
        (await store.applyMutations(scope: scope(), messages: [message(1)]))
            .single
            .status,
        MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED);
    expect((await store.readReplayRoot(scope(session: 'old-window'))).status,
        HistoryWindowReadStatus.hit);
    await store.closeIfOpen();
    store = HistoryWindowStore(
        debugDatabasePath: path, debugProcessID: 'process-b');
    expect((await store.debugStatistics())['mutation_pending'], 0);
    expect((await store.readReplayRoot(scope(session: 'old-window'))).status,
        HistoryWindowReadStatus.miss);
    final fresh = await store.applyMutations(
        scope: scope(session: 'new-window'),
        messages: [message(1), message(2), message(3)]);
    expect(fresh, hasLength(2));
    expect(fresh[0].status, MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC);
    expect(fresh[1].status, MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED);
    await store.savePage(page('new-root', [1, 2, 3],
        s: scope(session: 'new-window'), root: true));
    expect(
        (await store.readReplayRoot(scope(session: 'new-window')))
            .messages
            .first
            .status,
        MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC);
    for (var i = 0; i < 8; i++) {
      await store.recordMutation(HistoryWindowMutation(
          ownerUserID: 'owner',
          conversationID: 'group_g',
          clearEpoch: 0,
          eventID: 'new-command-$i',
          msgID: 'm1',
          kind: HistoryWindowMutationKind.revoke,
          pending: true,
          sourceKey: 'command:process-b',
          revision: i + 1));
    }
    expect((await store.debugStatistics())['mutation_pending'], 8);
  });

  test(
      'v2 unlabelled pending cannot preserve an optimistic cached copy during upgrade',
      () async {
    await store.closeIfOpen();
    final path = p.join(directory.path, 'v2-upgrade.db');
    store = HistoryWindowStore(
        debugDatabasePath: path, debugProcessID: 'same-test-process');
    await store.recordMutation(const HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 0,
        eventID: 'unconfirmed',
        msgID: 'm1',
        kind: HistoryWindowMutationKind.revoke,
        pending: true));
    await store.recordMutation(const HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 0,
        eventID: 'confirmed',
        msgID: 'm2',
        kind: HistoryWindowMutationKind.revoke));
    await store.savePage(HistoryWindowPage(
        scope: scope(),
        pageKey: 'optimistic-copy',
        messages: [
          message(1)..status = MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED
        ],
        isReplayRoot: true));
    await store.closeIfOpen();
    final legacy = await openDatabase(path);
    await legacy.execute('DROP INDEX hw_pending_process');
    await legacy
        .execute('ALTER TABLE hw_mutation_pending DROP COLUMN process_id');
    await legacy.execute('PRAGMA user_version=2');
    await legacy.close();
    expect((await store.debugStatistics())['mutation_pending'], 0);
    expect((await store.readReplayRoot(scope())).status,
        HistoryWindowReadStatus.miss);
    final restored = await store
        .applyMutations(scope: scope(), messages: [message(1), message(2)]);
    expect(restored[0].status, MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC);
    expect(restored[1].status, MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED);
  });

  test(
      'process cleanup SQL failure rolls back and closes the unpublished SQLite handle',
      () async {
    await store.closeIfOpen();
    final path = p.join(directory.path, 'process-cleanup-failure.db');
    store = HistoryWindowStore(
        debugDatabasePath: path, debugProcessID: 'process-a');
    await store.recordMutation(const HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 0,
        eventID: 'unconfirmed',
        msgID: 'm1',
        kind: HistoryWindowMutationKind.revoke,
        pending: true));
    await store.savePage(page('old-root', [1], root: true));
    await store.closeIfOpen();
    // The factory returns this actual shared SQLite handle to the store. An
    // aborting trigger exercises its real cleanup transaction failure path.
    final unpublished = await openDatabase(path);
    await unpublished.execute('''CREATE TRIGGER fail_process_cleanup
      BEFORE DELETE ON hw_mutation_pending
      BEGIN SELECT RAISE(ABORT, 'injected cleanup failure'); END''');
    store = HistoryWindowStore(
        debugDatabasePath: path, debugProcessID: 'process-b');
    await expectLater(
        store.debugStatistics(), throwsA(isA<DatabaseException>()));
    expect(store.isOpenForTesting, isFalse);
    expect(unpublished.isOpen, isFalse);
    final inspect = await openDatabase(path);
    expect((await inspect.query('hw_mutation_pending')).length, 1);
    expect((await inspect.query('hw_pages')).length, 1);
    await inspect.execute('DROP TRIGGER fail_process_cleanup');
    await inspect.close();
    expect((await store.debugStatistics())['mutation_pending'], 0);
    expect((await store.readReplayRoot(scope())).status,
        HistoryWindowReadStatus.miss);
  });

  test(
      '10000 deferred identities stay durable without body copies and exact deduped scalars',
      () async {
    for (var i = 1; i <= 10000; i++) {
      final receipt = await store.appendDeferred(
          scope: scope(),
          eventID: 'e$i',
          ingressSequence: i,
          message: message(i, self: i % 5 == 0));
      expect(receipt.inserted, isTrue);
      if (i % 1000 == 0) {
        expect(receipt.state.receivedCount, i);
        expect((await store.debugStatistics())['deferred_bodies'], 0);
        expect(
            (await store.readDeferredTail(scope: scope(), limit: 10000)).length,
            0);
      }
    }
    final duplicate = await store.appendDeferred(
        scope: scope(),
        eventID: 'e9999',
        ingressSequence: 10001,
        message: message(9999));
    expect(duplicate.inserted, isFalse);
    final duplicateSequence = await store.appendDeferred(
        scope: scope(),
        eventID: 'different-event',
        ingressSequence: 9999,
        message: message(9999));
    expect(duplicateSequence.inserted, isFalse);
    await store.closeIfOpen();
    var state = await store.deferredState(scope());
    expect(state.receivedCount, 10000);
    expect(state.unreadCount, 8000);
    expect(state.firstIngressSequence, 1);
    expect(state.lastIngressSequence, 10000);
    expect(await store.readDeferredTail(scope: scope()), isEmpty);
    expect(state.lastMessageID, 'm10000');
    expect(state.lastGroupMessageSeq, 10000);
    await store.acknowledgeDeferred(
        scope: scope(), throughIngressSequence: 9900);
    state = await store.deferredState(scope());
    expect(state.receivedCount, 100);
    expect(state.unreadCount, 80);
    expect(state.firstIngressSequence, 9901);
    final replay = await store.appendDeferred(
        scope: scope(), eventID: 'e1', ingressSequence: 1, message: message(1));
    expect(replay.inserted, isFalse);
    expect((await store.debugStatistics())['deferred'], 100);
    expect((await store.debugStatistics())['deferred_bodies'], 0);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
      'repeated edits remain a bounded current fact and SQL order does not mix external clocks',
      () async {
    for (var i = 0; i < 1000; i++) {
      await store.recordMutation(HistoryWindowMutation(
          ownerUserID: 'owner',
          conversationID: 'group_g',
          clearEpoch: 0,
          eventID: 'edit-$i',
          msgID: 'm1',
          kind: HistoryWindowMutationKind.edit,
          message: message(1, text: 'edited-$i'),
          sourceKey: 'sdk',
          revision: 1000 + i));
    }
    expect((await store.debugStatistics())['mutations'], 1);
    await store.recordMutation(HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 0,
        eventID: 'local',
        msgID: 'm1',
        kind: HistoryWindowMutationKind.edit,
        message: message(1, text: 'local')));
    await store.recordMutation(HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 0,
        eventID: 'late-sdk',
        msgID: 'm1',
        kind: HistoryWindowMutationKind.edit,
        message: message(1, text: 'late'),
        sourceKey: 'sdk',
        revision: 1500));
    await store.closeIfOpen();
    expect(
        (await store.applyMutations(scope: scope(), messages: [message(1)]))
            .single
            .textElem!
            .text,
        'local');
    expect((await store.debugStatistics())['mutations'], 1);
  });

  test('two failed deletes restore the message in both completion orders',
      () async {
    for (final order in [
      ['a', 'b'],
      ['b', 'a']
    ]) {
      final messageID = 'm${order.first}';
      for (final token in ['a', 'b']) {
        await store.recordMutation(HistoryWindowMutation(
            ownerUserID: 'owner',
            conversationID: 'group_g',
            clearEpoch: 0,
            eventID: '$messageID-$token',
            msgID: messageID,
            kind: HistoryWindowMutationKind.delete,
            pending: true));
      }
      final original = message(1)..msgID = messageID;
      for (var i = 0; i < order.length; i++) {
        await store.recordMutation(HistoryWindowMutation(
            ownerUserID: 'owner',
            conversationID: 'group_g',
            clearEpoch: 0,
            eventID: 'restore-$i',
            msgID: messageID,
            kind: HistoryWindowMutationKind.restore,
            restoreMutationToken: '$messageID-${order[i]}'));
        expect(await store.applyMutations(scope: scope(), messages: [original]),
            i == 0 ? isEmpty : hasLength(1));
      }
    }
  });

  test(
      'three nested failed commands never resurrect another failed token in any order',
      () async {
    final orders = [
      [0, 1, 2],
      [0, 2, 1],
      [1, 0, 2],
      [1, 2, 0],
      [2, 0, 1],
      [2, 1, 0]
    ];
    for (var n = 0; n < orders.length; n++) {
      final id = 'nested-$n';
      for (var i = 0; i < 3; i++) {
        await store.recordMutation(HistoryWindowMutation(
            ownerUserID: 'owner',
            conversationID: 'group_g',
            clearEpoch: 0,
            eventID: '$id-$i',
            msgID: id,
            kind: HistoryWindowMutationKind.delete,
            pending: true));
      }
      for (var i = 0; i < 3; i++) {
        final token = '$id-${orders[n][i]}';
        final rollback = HistoryWindowMutation(
            ownerUserID: 'owner',
            conversationID: 'group_g',
            clearEpoch: 0,
            eventID: 'restore-$token',
            msgID: id,
            kind: HistoryWindowMutationKind.restore,
            restoreMutationToken: token);
        await store.recordMutation(rollback);
        await store.recordMutation(rollback);
        expect(
            await store.applyMutations(
                scope: scope(), messages: [message(1)..msgID = id]),
            i < 2 ? isEmpty : hasLength(1));
      }
    }
    expect((await store.debugStatistics())['mutation_pending'], 0);
  });

  test(
      'pending commands survive reopen, enforce eight slots, and settle independently of old rollback',
      () async {
    for (var i = 0; i < 8; i++) {
      await store.recordMutation(HistoryWindowMutation(
          ownerUserID: 'owner',
          conversationID: 'group_g',
          clearEpoch: 0,
          eventID: 'p$i',
          msgID: 'm1',
          kind: HistoryWindowMutationKind.delete,
          pending: true));
    }
    await expectLater(
        store.recordMutation(const HistoryWindowMutation(
            ownerUserID: 'owner',
            conversationID: 'group_g',
            clearEpoch: 0,
            eventID: 'overflow',
            msgID: 'm1',
            kind: HistoryWindowMutationKind.delete,
            pending: true)),
        throwsA(isA<HistoryWindowPendingLimit>()));
    await store.closeIfOpen();
    expect((await store.debugStatistics())['mutation_pending'], 8);
    expect((await store.debugStatistics())['mutations'], 0);
    expect(await store.applyMutations(scope: scope(), messages: [message(1)]),
        isEmpty);
    for (var i = 0; i < 8; i++) {
      await store.recordMutation(HistoryWindowMutation(
          ownerUserID: 'owner',
          conversationID: 'group_g',
          clearEpoch: 0,
          eventID: 'done$i',
          msgID: 'm1',
          kind: i == 0
              ? HistoryWindowMutationKind.settle
              : HistoryWindowMutationKind.restore,
          restoreMutationToken: 'p$i'));
    }
    await store.recordMutation(const HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 0,
        eventID: 'late-failure',
        msgID: 'm1',
        kind: HistoryWindowMutationKind.restore,
        restoreMutationToken: 'p0'));
    expect((await store.debugStatistics())['mutation_pending'], 0);
    expect((await store.debugStatistics())['mutations'], 1);
    expect(await store.applyMutations(scope: scope(), messages: [message(1)]),
        isEmpty);
  });

  test(
      'terminal verdicts and source clocks are bounded and old pending replay is rejected',
      () async {
    for (var i = 1; i <= 40; i++) {
      await store.recordMutation(HistoryWindowMutation(
          ownerUserID: 'owner',
          conversationID: 'group_g',
          clearEpoch: 0,
          eventID: 'p$i',
          msgID: 'm1',
          kind: HistoryWindowMutationKind.delete,
          pending: true,
          sourceKey: 'command:test',
          revision: i));
      await store.recordMutation(HistoryWindowMutation(
          ownerUserID: 'owner',
          conversationID: 'group_g',
          clearEpoch: 0,
          eventID: 'r$i',
          msgID: 'm1',
          kind: HistoryWindowMutationKind.restore,
          restoreMutationToken: 'p$i'));
    }
    await store.recordMutation(const HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 0,
        eventID: 'p1',
        msgID: 'm1',
        kind: HistoryWindowMutationKind.delete,
        pending: true,
        sourceKey: 'command:test',
        revision: 1));
    expect((await store.debugStatistics())['mutation_pending'], 0);
    expect((await store.debugStatistics())['mutation_terminal'], 16);
    for (var i = 0; i < 20; i++) {
      await store.recordMutation(HistoryWindowMutation(
          ownerUserID: 'owner',
          conversationID: 'group_g',
          clearEpoch: 0,
          eventID: 'source$i',
          msgID: 'm2',
          kind: HistoryWindowMutationKind.edit,
          message: message(2),
          sourceKey: 'sdk:$i',
          revision: 1));
    }
    expect((await store.debugStatistics())['mutation_versions'], 5);
  });

  test(
      'bounded scans advance through deleted rows in both directions without carrying payload pages',
      () async {
    for (var p = 0; p < 12; p++) {
      await store.savePage(page(
          'scan$p', List.generate(50, (i) => 600 - p * 50 - i),
          newer: p == 0 ? null : 'scan${p - 1}',
          older: p == 11 ? null : 'scan${p + 1}'));
    }
    for (var id = 101; id < 600; id++) {
      await store.recordMutation(HistoryWindowMutation(
          ownerUserID: 'owner',
          conversationID: 'group_g',
          clearEpoch: 0,
          eventID: 'delete$id',
          msgID: 'm$id',
          kind: HistoryWindowMutationKind.delete));
    }
    var boundary = const HistoryWindowBoundary(msgID: 'm600');
    var reads = 0;
    var totalVisible = <V2TimMessage>[];
    do {
      final result = await store.readAdjacent(
          scope: scope(),
          boundary: boundary,
          direction: HistoryWindowDirection.older,
          limit: 50);
      expect(result.pages.length, lessThanOrEqualTo(4));
      expect(result.scannedRows, lessThanOrEqualTo(200));
      expect(result.pages.every((p) => p.messages.isEmpty), isTrue);
      totalVisible.addAll(result.messages);
      reads++;
      if (!result.scanLimitReached) break;
      expect(result.status, HistoryWindowReadStatus.hit);
      expect(result.continuationBoundary!.msgID, isNot(boundary.msgID));
      boundary = result.continuationBoundary!;
    } while (reads < 10);
    expect(reads, lessThan(10));
    expect(totalVisible.first.msgID, 'm100');
    final newer = await store.readAdjacent(
        scope: scope(),
        boundary: const HistoryWindowBoundary(msgID: 'm100'),
        direction: HistoryWindowDirection.newer,
        limit: 50);
    expect(newer.scanLimitReached, isTrue);
    expect(newer.continuationBoundary!.msgID, isNot('m100'));
  });

  test(
      'authority mutations reject old clear epochs and invalid captured authorization',
      () async {
    await store.clearConversation(
        ownerUserID: 'owner', conversationID: 'group_g', clearEpoch: 1);
    await expectLater(
        store.recordMutation(HistoryWindowMutation(
            ownerUserID: 'owner',
            conversationID: 'group_g',
            clearEpoch: 0,
            eventID: 'old',
            msgID: 'm1',
            kind: HistoryWindowMutationKind.edit,
            message: message(1))),
        throwsA(isA<HistoryWindowStaleScope>()));
    await expectLater(
        store.recordMutation(HistoryWindowMutation(
            ownerUserID: 'owner',
            clearEpoch: 1,
            eventID: 'unknown-conv-old-owner',
            msgID: 'm1',
            kind: HistoryWindowMutationKind.revoke,
            isCurrent: () => false)),
        throwsA(isA<HistoryWindowStaleScope>()));
    await expectLater(
        store.recordMutation(HistoryWindowMutation(
            ownerUserID: 'owner',
            conversationID: 'group_g',
            clearEpoch: 1,
            eventID: 'wrong-owner',
            msgID: 'm1',
            kind: HistoryWindowMutationKind.delete,
            authorizationScope: scope(owner: 'another', epoch: 1))),
        throwsA(isA<HistoryWindowStaleScope>()));
    var checks = 0;
    await expectLater(
        store.recordMutation(HistoryWindowMutation(
            ownerUserID: 'owner',
            conversationID: 'group_g',
            clearEpoch: 1,
            eventID: 'invalidated-mid-transaction',
            msgID: 'm1',
            kind: HistoryWindowMutationKind.edit,
            message: message(1),
            sourceKey: 'sdk',
            revision: 100,
            isCurrent: () => ++checks == 1)),
        throwsA(isA<HistoryWindowStaleScope>()));
    expect((await store.debugStatistics())['mutations'], 0);
  });

  test(
      'expired scope cannot reopen after session LRU and in-flight expiry rolls back',
      () async {
    var valid = true;
    final leased = HistoryWindowScope(
        ownerUserID: 'owner',
        accountGeneration: 1,
        domainGeneration: 1,
        conversationID: 'group_g',
        clearEpoch: 0,
        sessionID: 'leased',
        isCurrent: () => valid);
    await store.savePage(page('lease', [1], s: leased));
    valid = false;
    await store.closeSession(leased);
    await store.closeSession(leased);
    for (var i = 0; i < 8; i++) {
      await store
          .savePage(page('p$i', [i + 2], s: scope(session: 'replacement$i')));
    }
    await expectLater(store.savePage(page('resurrect', [1], s: leased)),
        throwsA(isA<HistoryWindowStaleScope>()));
    expect((await store.readPage(scope: leased, pageKey: 'lease')).status,
        HistoryWindowReadStatus.stale);
    var checks = 0;
    final expiresDuringWrite = HistoryWindowScope(
        ownerUserID: 'owner',
        accountGeneration: 1,
        domainGeneration: 1,
        conversationID: 'group_g',
        clearEpoch: 0,
        sessionID: 'in-flight',
        isCurrent: () => ++checks == 1);
    await expectLater(
        store.savePage(page('must-rollback', [50], s: expiresDuringWrite)),
        throwsA(isA<HistoryWindowStaleScope>()));
    expect(
        (await store.readPage(
                scope: scope(session: 'in-flight'), pageKey: 'must-rollback'))
            .status,
        HistoryWindowReadStatus.miss);
  });

  test(
      'concurrent SQLite appends and pending commands preserve exact scalars and slot limits',
      () async {
    final receipts = await Future.wait(List.generate(
        200,
        (i) => store.appendDeferred(
            scope: scope(),
            eventID: 'e$i',
            ingressSequence: i,
            message: message(i))));
    expect(receipts.where((r) => r.inserted), hasLength(200));
    expect((await store.deferredState(scope())).receivedCount, 200);
    final outcomes = await Future.wait(List.generate(
        12,
        (i) => store
                .recordMutation(HistoryWindowMutation(
                    ownerUserID: 'owner',
                    conversationID: 'group_g',
                    clearEpoch: 0,
                    eventID: 'pending$i',
                    msgID: 'm1',
                    kind: HistoryWindowMutationKind.delete,
                    pending: true))
                .then((_) => true, onError: (Object error) {
              expect(error, isA<HistoryWindowPendingLimit>());
              return false;
            })));
    expect(outcomes.where((v) => v), hasLength(8));
    expect((await store.debugStatistics())['mutation_pending'], 8);
    expect((await store.debugStatistics())['deferred_bodies'], 0);
  });

  test(
      'explicit owner purge removes only exact account data and persistent facts',
      () async {
    for (final owner in ['owner', 'owner-extra']) {
      await store.savePage(page('a', [1], s: scope(owner: owner)));
      await store.appendDeferred(
          scope: scope(owner: owner),
          eventID: 'e1',
          ingressSequence: 1,
          message: message(1));
      await store.recordMutation(HistoryWindowMutation(
          ownerUserID: owner,
          clearEpoch: 0,
          eventID: 'd1',
          msgID: 'm1',
          kind: HistoryWindowMutationKind.delete));
    }
    await store.clearForOwner('owner');
    expect((await store.readPage(scope: scope(), pageKey: 'a')).status,
        HistoryWindowReadStatus.miss);
    expect((await store.deferredState(scope())).receivedCount, 0);
    expect(await store.applyMutations(scope: scope(), messages: [message(1)]),
        hasLength(1));
    expect(
        (await store.deferredState(scope(owner: 'owner-extra'))).receivedCount,
        1);
    expect(
        await store.applyMutations(
            scope: scope(owner: 'owner-extra'), messages: [message(1)]),
        isEmpty);
    expect((await store.debugStatistics())['mutations'], 1);
  });

  test('fully acknowledged bucket establishes new first and last boundaries',
      () async {
    await store.appendDeferred(
        scope: scope(),
        eventID: 'e100',
        ingressSequence: 100,
        message: message(100));
    await store.acknowledgeDeferred(
        scope: scope(), throughIngressSequence: 100);
    final next = await store.appendDeferred(
        scope: scope(),
        eventID: 'e101',
        ingressSequence: 101,
        message: message(101));
    expect(next.state.receivedCount, 1);
    expect(next.state.firstIngressSequence, 101);
    expect(next.state.lastIngressSequence, 101);
    expect(next.state.firstMessageID, 'm101');
    expect(next.state.lastMessageID, 'm101');
  });

  test(
      'deferred identities survive across conversations without copying SDK bodies',
      () async {
    for (var c = 0; c < 20; c++) {
      for (var i = 1; i <= 6; i++) {
        await store.appendDeferred(
            scope: scope(conv: 'group_$c', session: 's$c'),
            eventID: 'e$i',
            ingressSequence: i,
            message: message(i));
      }
    }
    expect((await store.debugStatistics())['deferred_bodies'], 0);
    expect((await store.debugStatistics())['deferred'], 120);
    expect(
        (await store.deferredState(scope(conv: 'group_0', session: 's0')))
            .receivedCount,
        6);
    expect(
        await store.readDeferredTail(
            scope: scope(conv: 'group_0', session: 's0')),
        isEmpty);
  });

  test('SDK-only ACK identities survive cache-sized replay and database reopen',
      () async {
    HistoryWindowDeferredReceipt? receipt;
    for (var i = 1; i <= 600; i++) {
      receipt = await store.appendDeferred(
          scope: scope(),
          eventID: 'received:m$i',
          ingressSequence: 0,
          hasStableIngressSequence: false,
          message: message(i));
    }
    await store.acknowledgeDeferred(
        scope: scope(),
        throughIngressSequence: receipt!.state.lastIngressSequence!);
    await store.closeIfOpen();
    for (final i in [1, 88, 599, 600]) {
      final replay = await store.appendDeferred(
          scope: scope(session: 'reopened'),
          eventID: 'received:m$i',
          ingressSequence: 0,
          hasStableIngressSequence: false,
          message: message(i));
      expect(replay.inserted, isFalse);
      expect(replay.state.receivedCount, 0);
      expect(replay.state.unreadCount, 0);
    }
    final next = await store.appendDeferred(
        scope: scope(session: 'reopened'),
        eventID: 'received:m601',
        ingressSequence: 0,
        hasStableIngressSequence: false,
        message: message(601));
    expect(next.inserted, isTrue);
    expect(next.state.receivedCount, 1);
    expect(next.state.lastIngressSequence, 601);
    final aliasReplay = await store.appendDeferred(
        scope: scope(session: 'reopened'),
        eventID: 'received:msg:m1',
        ingressSequence: 0,
        hasStableIngressSequence: false,
        message: message(1));
    expect(aliasReplay.inserted, isFalse);
    expect(aliasReplay.state.receivedCount, 1);
    expect((await store.debugStatistics())['deferred_bodies'], 0);
    await store.clearConversation(
        ownerUserID: 'owner', conversationID: 'group_g', clearEpoch: 1);
    expect((await store.debugStatistics())['deferred'], 0);
  });

  test('body-free boundary follows message order through partial ACK',
      () async {
    Future<HistoryWindowDeferredReceipt> append(int id) => store.appendDeferred(
        scope: scope(),
        eventID: 'received:m$id',
        ingressSequence: 0,
        hasStableIngressSequence: false,
        message: message(id));
    final first = await append(300);
    await append(100);
    final third = await append(200);
    expect(third.state.lastIngressSequence, 3);
    expect(third.state.lastMessageID, 'm300');
    expect(third.state.lastGroupMessageSeq, 300);
    await store.acknowledgeDeferred(
        scope: scope(),
        throughIngressSequence: first.state.lastIngressSequence!);
    final remaining = await store.deferredState(scope());
    expect(remaining.receivedCount, 2);
    expect(remaining.firstIngressSequence, 2);
    expect(remaining.lastIngressSequence, 3);
    expect(remaining.lastMessageID, 'm200');
    expect(remaining.lastGroupMessageSeq, 200);
    expect(await store.readDeferredTail(scope: scope()), isEmpty);
    await store.closeIfOpen();
    final reopened = await store.deferredState(scope());
    expect(reopened.lastMessageID, 'm200');
    expect(reopened.receivedCount, 2);
  });

  test('body-free latest boundary excludes confirmed deleted newest messages',
      () async {
    for (final id in [100, 200]) {
      await store.appendDeferred(
          scope: scope(),
          eventID: 'received:m$id',
          ingressSequence: 0,
          hasStableIngressSequence: false,
          message: message(id));
    }
    await store.recordMutation(const HistoryWindowMutation(
        ownerUserID: 'owner',
        conversationID: 'group_g',
        clearEpoch: 0,
        eventID: 'delete-latest',
        msgID: 'm200',
        kind: HistoryWindowMutationKind.delete));
    final state = await store.deferredState(scope());
    expect(state.receivedCount, 2);
    expect(state.lastIngressSequence, 2);
    expect(state.lastMessageID, 'm100');
    expect(state.lastGroupMessageSeq, 100);
    expect(
        await store.areDeferredMessagesAuthoritativelyDeleted(
            scope: scope(), throughIngressSequence: 2),
        isFalse);
  });

  test('acknowledgement watermark never consumes a new generation sequence',
      () async {
    await store.appendDeferred(
        scope: scope(),
        eventID: 'old',
        ingressSequence: 100,
        message: message(100));
    await store.acknowledgeDeferred(
        scope: scope(), throughIngressSequence: 100);
    final receipt = await store.appendDeferred(
        scope: scope(account: 2, domain: 2, session: 's2'),
        eventID: 'new',
        ingressSequence: 1,
        message: message(1));
    expect(receipt.inserted, isTrue);
    expect(receipt.state.receivedCount, 1);
    await store.closeIfOpen();
    expect(
        (await store.deferredState(scope(account: 2, domain: 2, session: 's2')))
            .receivedCount,
        1);
  });

  test(
      'clear, account generation, close and failed background append cannot leak scope or increment counters',
      () async {
    await store.savePage(page('a', [1]));
    await store.appendDeferred(
        scope: scope(), eventID: 'e1', ingressSequence: 1, message: message(1));
    SqfliteLifecycleGuard.instance.pauseWrites();
    await expectLater(
        store.appendDeferred(
            scope: scope(),
            eventID: 'e2',
            ingressSequence: 2,
            message: message(2)),
        throwsA(isA<SqfliteClosedForBackground>()));
    expect((await store.deferredState(scope())).receivedCount, 1);
    SqfliteLifecycleGuard.instance.resume();
    await store.clearConversation(
        ownerUserID: 'owner', conversationID: 'group_g', clearEpoch: 1);
    expect((await store.readPage(scope: scope(), pageKey: 'a')).status,
        HistoryWindowReadStatus.stale);
    expect((await store.deferredState(scope(epoch: 1))).receivedCount, 0);
    await expectLater(store.savePage(page('late', [2])),
        throwsA(isA<HistoryWindowStaleScope>()));
    await store.savePage(page('new', [3], s: scope(epoch: 1, account: 2)));
    await expectLater(
        store.savePage(page('old-account', [4], s: scope(epoch: 1))),
        throwsA(isA<HistoryWindowStaleScope>()));
    await store.closeSession(scope(epoch: 1, account: 2));
    await store.closeSession(scope(epoch: 1, account: 2));
    await expectLater(
        store.savePage(page('closed', [4], s: scope(epoch: 1, account: 2))),
        throwsA(isA<HistoryWindowStaleScope>()));
  });

  test('late history page keeps a realtime revoke in the stored payload',
      () async {
    await store.savePage(page('a', [20], root: true));
    await store.recordMutation(const HistoryWindowMutation(
      ownerUserID: 'owner',
      conversationID: 'group_g',
      clearEpoch: 0,
      eventID: 'revoke-20',
      msgID: 'm20',
      kind: HistoryWindowMutationKind.revoke,
    ));
    await store.savePage(page('a', [20], root: true));
    final stored =
        (await store.readPage(scope: scope(), pageKey: 'a')).pages.single;
    expect(stored.messages.single.status,
        MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED);
  });
}
