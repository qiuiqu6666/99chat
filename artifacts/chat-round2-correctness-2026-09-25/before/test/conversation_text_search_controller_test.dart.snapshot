import 'dart:async';
import 'dart:io';
// fake_async is supplied by flutter_test.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/search_account_owner.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_state.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_param.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_result_item.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/controllers/conversation_text_search_controller.dart';

typedef Reply = V2TimValueCallback<V2TimMessageSearchResult>;

V2TimMessage message(String id, [int timestamp = 10]) => V2TimMessage.fromJson({
      'message_risk_type_identified': 0,
      'message_msg_id': id,
      'message_server_time': timestamp,
    });

Reply reply({
  List<V2TimMessage> rows = const [],
  String conversation = 'group_room',
  String cursor = '',
  int? total,
}) =>
    Reply(
      code: 0,
      desc: 'ok',
      data: V2TimMessageSearchResult(
        totalCount: total ?? rows.length,
        searchCursor: cursor,
        messageSearchResultItems: [
          V2TimMessageSearchResultItem(
            conversationID: conversation,
            messageCount: total ?? rows.length,
            messageList: rows,
          ),
        ],
      ),
    );

class Request {
  Request(this.cloud, this.param);
  final bool cloud;
  final V2TimMessageSearchParam param;
  final result = Completer<Reply>();
}

void main() {
  late ConversationTextSearchController controller;
  late List<Request> requests;
  late String owner;
  late List<Map<String, Object?>> traces;

  setUp(() {
    owner = 'owner';
    requests = [];
    traces = [];
    controller = ConversationTextSearchController(
      read: ({required cloud, required param}) {
        final request = Request(cloud, param);
        requests.add(request);
        return request.result.future;
      },
      ownerId: () => owner,
      onChanged: () {},
      onTrace: (event, fields) => traces.add({'event': event, ...fields}),
      debounce: Duration.zero,
    );
  });
  tearDown(() => controller.clear(notify: false));

  test('rapid queries keep only latest pending work in each source', () async {
    final searches = <Future<void>>[];
    for (var i = 0; i < 100; i++) {
      searches.add(controller.search('query$i', 'group_room'));
    }
    expect(requests, hasLength(2));
    requests[0].result.complete(reply(rows: [message('stale')]));
    // Local lane can progress independently of a slow old cloud request.
    await Future<void>.delayed(Duration.zero);
    expect(requests, hasLength(3));
    expect(requests[2].cloud, false);
    expect(requests[2].param.keywordList, ['query99']);
    requests[2].result.complete(reply(rows: [message('latest')]));
    await Future<void>.delayed(Duration.zero);
    expect(controller.messages.single.msgID, 'latest');
    requests[1].result.complete(reply());
    await Future<void>.delayed(Duration.zero);
    expect(requests, hasLength(4));
    expect(requests[3].param.keywordList, ['query99']);
    requests[3].result.complete(reply());
    await Future.wait(searches);
    expect(controller.messages.single.msgID, 'latest');
  });

  test('UI timeout keeps SDK slots occupied and expires queued requests', () {
    fakeAsync((clock) {
      final calls = <Request>[];
      final search = ConversationTextSearchController(
        ownerId: () => 'owner',
        onChanged: () {},
        timeout: const Duration(milliseconds: 20),
        read: ({required cloud, required param}) {
          final call = Request(cloud, param);
          calls.add(call);
          return call.result.future;
        },
      );
      unawaited(search.search('old', 'group_room'));
      clock.elapse(const Duration(milliseconds: 21));
      expect(search.loading, false);
      unawaited(search.search('expired', 'group_room'));
      clock.elapse(const Duration(milliseconds: 21));
      expect(calls, hasLength(2));
      calls[0].result.complete(reply());
      calls[1].result.complete(reply());
      clock.flushMicrotasks();
      expect(calls, hasLength(2));
      unawaited(search.search('retry', 'group_room'));
      expect(calls, hasLength(4));
      calls[2].result.complete(reply());
      calls[3].result.complete(reply());
      clock.flushMicrotasks();
      expect(search.hasError, false);
      search.clear(notify: false);
    });
  });

  test('clear prevents queued SDK work from starting', () async {
    final first = controller.search('old', 'group_room');
    final pending = controller.search('new', 'group_room');
    controller.clear();
    await pending;
    requests[0].result.complete(reply());
    requests[1].result.complete(reply());
    await first;
    expect(requests, hasLength(2));
  });

  test(
      'same-turn responses coalesce notification and duplicate pages reuse list',
      () {
    fakeAsync((clock) {
      var notifications = 0;
      final calls = <Request>[];
      final search = ConversationTextSearchController(
        ownerId: () => 'owner',
        onChanged: () => notifications++,
        read: ({required cloud, required param}) {
          final call = Request(cloud, param);
          calls.add(call);
          return call.result.future;
        },
      );
      unawaited(search.search('word', 'group_room'));
      expect(notifications, 1);
      calls[0].result.complete(reply(rows: [message('one')], total: 2));
      calls[1].result.complete(reply(rows: [message('one')]));
      clock.flushMicrotasks();
      clock.elapse(Duration.zero);
      expect(notifications, 2);
      final list = search.messages;
      unawaited(search.loadMore());
      calls[2].result.complete(reply(rows: [message('one')], total: 2));
      clock.flushMicrotasks();
      expect(identical(search.messages, list), true);
      expect(search.hasMore, false);
      search.clear(notify: false);
    });
  });

  test('cold-start native login searches with empty UIKit profile and identity',
      () async {
    final sources = <bool>[];
    final search = ConversationTextSearchController(
      ownerId: () => resolveSearchAccountOwner(
        session: const SessionState(phase: SessionPhase.ready, userId: 'owner'),
        authenticatedUserId: 'owner',
      ),
      onChanged: () {},
      read: ({required cloud, required param}) async {
        sources.add(cloud);
        expect(param.keywordList, ['周']);
        return reply(rows: cloud ? [] : [message('found')]);
      },
    );
    await search.search('周', 'group_room');
    expect(sources, [false, true]);
    expect(search.messages.single.msgID, 'found');
    expect(search.hasError, isFalse);
    search.clear(notify: false);
  });

  test('same-owner relogin discards old results before starting a new search',
      () async {
    var accountGeneration = 0;
    final search = ConversationTextSearchController(
      ownerId: () => owner,
      accountGeneration: () => accountGeneration,
      onChanged: () {},
      read: ({required cloud, required param}) {
        final request = Request(cloud, param);
        requests.add(request);
        return request.result.future;
      },
    );
    final old = search.search('周', 'group_room');
    accountGeneration++;
    requests[0].result.complete(reply(rows: [message('stale')]));
    requests[1].result.complete(reply());
    await old;
    expect(search.messages, isEmpty);
    final retry = search.loadMore();
    expect(requests, hasLength(4));
    expect(requests[2].param.pageIndex, 0);
    requests[2].result.complete(reply(rows: [message('current')]));
    requests[3].result.complete(reply());
    await retry;
    expect(search.messages.single.msgID, 'current');
    search.clear(notify: false);
  });

  test('cloud empty does not hide a matching SDK-local message', () async {
    final done = controller.search('周', 'group_room');
    requests[0].result.complete(reply(rows: [message('local')]));
    requests[1].result.complete(reply());
    await done;
    expect(controller.messages.single.msgID, 'local');
    expect(controller.completed, isTrue);
    expect(controller.loading, isFalse);
    expect(controller.hasError, isFalse);
    expect(controller.hasMore, isFalse);
    final responses = traces.where((event) => event['event'] == 'response');
    expect(
        responses.map((event) => event['source']).toSet(), {'local', 'cloud'});
    expect(responses.map((event) => event['rawRows']), [1, 0]);
    expect(traces.last['event'], 'complete');
    expect(traces.last['rows'], 1);
    expect(traces.toString(), isNot(contains('周')));
  });

  test('cloud results are visible while local search is still pending',
      () async {
    final done = controller.search('周', 'group_room');
    requests[1].result.complete(reply(rows: [message('cloud')]));
    await Future<void>.delayed(Duration.zero);
    expect(controller.messages.single.msgID, 'cloud');
    expect(controller.loading, isTrue);
    expect(controller.completed, isFalse);
    requests[0].result.complete(reply());
    await done;
    expect(controller.messages.single.msgID, 'cloud');
  });

  test('retry works when SDK login becomes ready after the first attempt',
      () async {
    owner = '';
    await controller.search('周', 'group_room');
    expect(requests, isEmpty);
    expect(controller.hasError, isTrue);
    owner = 'owner';
    final retry = controller.loadMore();
    expect(requests, hasLength(2));
    requests[0].result.complete(reply(rows: [message('found')]));
    requests[1].result.complete(reply());
    await retry;
    expect(controller.hasError, isFalse);
    expect(controller.messages.single.msgID, 'found');
  });

  test('timeouts finish loading as an error without discarding matches',
      () async {
    final search = ConversationTextSearchController(
      read: ({required cloud, required param}) => cloud
          ? Completer<Reply>().future
          : Future.value(reply(rows: [message('local')])),
      ownerId: () => owner,
      onChanged: () {},
      timeout: const Duration(milliseconds: 20),
    );
    await search.search('周', 'group_room');
    expect(search.messages.single.msgID, 'local');
    expect(search.loading, isFalse);
    expect(search.cloudFailed, isTrue);
    search.clear(notify: false);
  });

  test('search errors are distinct from a successful empty search', () async {
    final done = controller.search('周', 'group_room');
    requests[0].result.complete(reply());
    requests[1].result.complete(Reply(code: 6011, desc: 'not connected'));
    await done;
    expect(controller.messages, isEmpty);
    expect(controller.hasError, isTrue);
    expect(controller.cloudErrorCode, 6011);
    final retry = controller.loadMore();
    expect(requests.length, 3);
    expect(requests.last.cloud, isTrue);
    expect(requests.last.param.searchCursor, '');
    requests.last.result.complete(reply(rows: [message('found')]));
    await retry;
    expect(controller.hasError, isFalse);
    expect(controller.messages.single.msgID, 'found');
  });

  test('old failures cannot disable cloud search or change the new cursor',
      () async {
    final old = controller.search('张', 'group_room');
    final current = controller.search('周', 'group_room');
    expect(requests, hasLength(2));
    requests[0].result.complete(reply(rows: [message('old')]));
    requests[1].result.complete(Reply(code: -1, desc: 'old failure'));
    await old;
    expect(requests, hasLength(4));
    requests[2].result.complete(reply());
    requests[3].result.complete(reply(rows: [message('new')], cursor: 'next'));
    await current;
    expect(controller.keyword, '周');
    final discarded = traces.where((event) => event['event'] == 'discard');
    expect(discarded, hasLength(2));
    expect(discarded.map((event) => event['reason']).toSet(),
        {'query_or_account_changed'});
    expect(controller.messages.map((m) => m.msgID), ['new']);
    expect(controller.hasError, isFalse);
    final more = controller.loadMore();
    expect(requests.last.param.searchCursor, 'next');
    requests.last.result.complete(reply());
    await more;
  });

  test('clearing input invalidates the debounce and pending responses',
      () async {
    controller.schedule('张', 'group_room');
    controller.clear();
    await Future<void>.delayed(Duration.zero);
    expect(requests, isEmpty);
    final done = controller.search('周', 'group_room');
    controller.clear();
    for (final request in requests) {
      request.result.complete(reply(rows: [message('stale')]));
    }
    await done;
    expect(controller.keyword, '');
    expect(controller.messages, isEmpty);
    expect(controller.loading, isFalse);
  });

  test('local pagination owns its cursor and ignores repeated load-more taps',
      () async {
    final first = controller.search('周', 'group_room');
    expect(requests[0].param.pageIndex, 0);
    requests[0].result.complete(reply(rows: [message('one')], total: 2));
    requests[1].result.complete(reply());
    await first;
    final more = controller.loadMore();
    await controller.loadMore();
    expect(requests.length, 3);
    expect(requests.last.param.pageIndex, 1);
    requests.last.result.complete(Reply(code: -1, desc: 'failed page'));
    await more;
    expect(controller.messages.single.msgID, 'one');
    final retry = controller.loadMore();
    expect(requests.last.param.pageIndex, 1);
    requests.last.result.complete(reply(rows: [message('two')], total: 2));
    await retry;
    expect(controller.messages, hasLength(2));
    expect(controller.hasMore, isFalse);
  });

  test('group ID aliases match without accepting another conversation',
      () async {
    final done = controller.search('周', 'group_@TGS#_RoomA');
    requests[0].result.complete(reply(
          rows: [message('match')],
          conversation: 'group_group_@TGS#_RoomA',
        ));
    requests[1].result.complete(reply(
          rows: [message('wrong')],
          conversation: 'c2c_RoomA',
        ));
    await done;
    expect(controller.messages.map((m) => m.msgID), ['match']);
  });

  test('local and cloud matches merge by identity and sort by time', () async {
    final done = controller.search('周', 'group_room');
    requests[0]
        .result
        .complete(reply(rows: [message('same'), message('old', 1)]));
    requests[1]
        .result
        .complete(reply(rows: [message('same'), message('new', 20)]));
    await done;
    expect(controller.messages.map((m) => m.msgID), ['new', 'same', 'old']);
  });

  test('a changed account cannot publish the old account response', () async {
    final done = controller.search('周', 'group_room');
    owner = 'other-owner';
    controller.clear();
    for (final request in requests) {
      request.result.complete(reply(rows: [message('old-owner')]));
    }
    await done;
    expect(controller.messages, isEmpty);
  });

  test('debounce immediately marks the current query as loading', () async {
    controller.schedule('周', 'group_room');
    expect(controller.loading, isTrue);
    expect(controller.completed, isFalse);
    controller.schedule('李', 'group_room');
    await Future<void>.delayed(Duration.zero);
    expect(requests, hasLength(2));
    for (final request in requests) {
      expect(request.param.keywordList, ['李']);
      request.result.complete(reply());
    }
    await Future<void>.delayed(Duration.zero);
    expect(controller.completed, isTrue);
  });

  test(
      'page distinguishes pending/failed search and does not advance UI cursors',
      () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitSearch/'
      'tim_uikit_search_msg_detail.dart',
    ).readAsStringSync();
    expect(source, contains('isLoading: isLoading'));
    expect(source, contains('hasSearchError'));
    expect(source, contains('textSearch.loadMore()'));
    expect(source, isNot(contains('currentPage = currentPage + 1')));
  });
}
