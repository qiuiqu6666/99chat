import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/friend_request_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/friend_request_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_request_list_controller.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/notice_load_more.dart';

FriendRequestRecord row(int id) => FriendRequestRecord(
      id: id,
      userID: 'user$id',
      nickname: '',
      faceUrl: '',
      addWording: '',
      addSource: '',
      addTime: 10000 - id,
      status: 'pending',
      direction: FriendRequestDirection.incoming,
    );
FriendRequestPage page(int start, int count,
        {bool more = true, String? cursor}) =>
    FriendRequestPage(
        items: List.generate(count, (i) => row(start + i)),
        hasMore: more,
        nextCursor: cursor);

void main() {
  test('first page shows newest 20; later windows only load on demand',
      () async {
    final limits = <int>[];
    final cursors = <String?>[];
    final controller = FriendRequestListController(
      loadIncoming: (limit) async {
        limits.add(limit);
        return page(0, limit);
      },
      loadSent: (limit) async => page(100, 4, more: false),
      loadHistory: (cursor) async {
        cursors.add(cursor);
        return page(200, 1, more: false);
      },
      captureCurrentGuard: () => () => true,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(limits, [20]);
    expect(cursors, [null]);
    expect(controller.visibleKeys, hasLength(20));
    expect(controller.visibleKeys, contains(row(0).identityKey));
    await controller.loadMore();
    expect(limits, [20, 40]);
    expect(cursors, [null]);
    expect(controller.visibleKeys, hasLength(40));
  });

  test('repeated bottom events share work; failure retries the same window',
      () async {
    final limits = <int>[];
    final gate = Completer<FriendRequestPage>();
    var fail = true;
    final controller = FriendRequestListController(
      loadIncoming: (limit) async {
        limits.add(limit);
        if (limit == 20) return page(0, 20);
        if (fail) return gate.future;
        return page(0, 25, more: false);
      },
      loadSent: (_) async => page(100, 0, more: false),
      loadHistory: (_) async => page(200, 0, more: false),
      captureCurrentGuard: () => () => true,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    final pending = controller.loadMore();
    await controller.loadMore();
    gate.completeError(StateError('offline'));
    await pending;
    expect(limits, [20, 40]);
    expect(controller.failed, isTrue);
    expect(controller.incoming, hasLength(20));
    fail = false;
    await controller.loadMore();
    expect(limits, [20, 40, 40]);
    expect(controller.incoming, hasLength(25));
    expect(controller.hasMore, isFalse);
  });

  test('refresh and account changes discard delayed history pages', () async {
    final gate = Completer<FriendRequestPage>();
    var owner = 0;
    final controller = FriendRequestListController(
      loadIncoming: (_) async => page(0, 0, more: false),
      loadSent: (_) async => page(0, 0, more: false),
      loadHistory: (cursor) async =>
          cursor == null ? page(0, 20, cursor: 'older') : await gate.future,
      captureCurrentGuard: () {
        final captured = owner;
        return () => owner == captured;
      },
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    final oldPage = controller.loadMore();
    await controller.refresh();
    gate.complete(page(20, 20, more: false));
    await oldPage;
    expect(controller.history, hasLength(20));
    final second = controller.loadMore();
    owner++;
    await second;
    expect(controller.history, hasLength(20));
  });

  test('failed refresh retries first page instead of using an old cursor',
      () async {
    final cursors = <String?>[];
    var fail = false;
    final controller = FriendRequestListController(
      loadIncoming: (_) async => page(0, 0, more: false),
      loadSent: (_) async => page(0, 0, more: false),
      loadHistory: (cursor) async {
        cursors.add(cursor);
        if (fail) throw StateError('offline');
        return page(0, 20, cursor: 'older');
      },
      captureCurrentGuard: () => () => true,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    fail = true;
    await controller.refresh();
    fail = false;
    await controller.loadMore();
    expect(cursors, [null, null, null]);
    expect(controller.history, hasLength(20));
  });

  testWidgets(
      'layout does not fetch; downward scroll does; loading blocks duplicates',
      (tester) async {
    var calls = 0;
    var loading = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
        MaterialApp(home: StatefulBuilder(builder: (context, setState) {
      rebuild = setState;
      return Scaffold(
          body: NoticeLoadMore(
        hasMore: true,
        loading: loading,
        onLoadMore: () async {
          calls++;
          rebuild(() => loading = true);
        },
        child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: 20,
            itemExtent: 50,
            itemBuilder: (_, index) => Text('row$index')),
      ));
    })));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
}
