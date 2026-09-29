import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/friend_request_api.dart';
import 'package:tencent_cloud_chat_demo/src/friend_application_helper.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_join_application_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_system_notice_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_request_notice_service.dart';
import 'package:tencent_cloud_chat_demo/src/models/friend_request_record.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <RequestOptions>[];
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  var account = 0;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      respond(request, handler);
    }));
  });
  setUp(() async {
    requests.clear();
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance
        .saveToken('test-token', userId: 'notice-page-${account++}');
    GroupJoinApplicationService.instance.clearSession();
    GroupSystemNoticeService.instance.clearSession();
  });

  Map<String, Object> item(int i) => {
        'id': i + 1,
        'noticeId': 'notice$i',
        'groupId': 'group1',
        'fromUserId': 'user$i',
        'createdAtMs': 1700000000000 - i * 1000,
        'status': 'pending',
        'type': 'member_added',
      };
  void success(RequestOptions request, RequestInterceptorHandler handler,
      {int total = 45}) {
    final offset = request.queryParameters['offset'] as int;
    final limit = request.queryParameters['limit'] as int;
    expect(limit, 20);
    handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
      'data': {
        'items': List.generate(total, item).skip(offset).take(limit).toList(),
        'total': total
      }
    }));
  }

  for (final applications in [true, false]) {
    final name = applications ? 'applications' : 'system notices';
    test('$name requests one page then appends, with stable retry offset',
        () async {
      Future<void> refresh() => applications
          ? GroupJoinApplicationService.instance.refresh(syncMembership: false)
          : GroupSystemNoticeService.instance.refresh();
      Future<void> more() => applications
          ? GroupJoinApplicationService.instance.loadMore()
          : GroupSystemNoticeService.instance.loadMore();
      int count() => applications
          ? GroupJoinApplicationService.instance.applications.length
          : GroupSystemNoticeService.instance.notices.length;
      respond = success;
      await refresh();
      expect(requests, hasLength(1));
      expect(count(), 20);
      final gate = Completer<void>();
      respond = (request, handler) {
        gate.future
            .then((_) => handler.reject(DioError(requestOptions: request)));
      };
      final pending = more();
      await more();
      gate.complete();
      await pending;
      expect(count(), 20);
      respond = success;
      await more();
      expect(count(), 40);
      await more();
      expect(count(), 45);
      await more();
      expect(requests.map((request) => request.queryParameters['offset']),
          [0, 20, 20, 40]);
    });

    test('$name ignores old page after refresh and session clear', () async {
      Future<void> refresh() => applications
          ? GroupJoinApplicationService.instance.refresh(syncMembership: false)
          : GroupSystemNoticeService.instance.refresh();
      Future<void> more() => applications
          ? GroupJoinApplicationService.instance.loadMore()
          : GroupSystemNoticeService.instance.loadMore();
      int count() => applications
          ? GroupJoinApplicationService.instance.applications.length
          : GroupSystemNoticeService.instance.notices.length;
      respond = success;
      await refresh();
      final entered = Completer<void>();
      final gate = Completer<void>();
      respond = (request, handler) {
        if (request.queryParameters['offset'] == 0) {
          success(request, handler);
        } else {
          entered.complete();
          gate.future.then((_) => success(request, handler));
        }
      };
      final pending = more();
      await entered.future;
      await refresh();
      gate.complete();
      await pending;
      expect(count(), 20);
      GroupJoinApplicationService.instance.clearSession();
      GroupSystemNoticeService.instance.clearSession();
      expect(count(), 0);
    });
  }

  test('same-limit requests do not coalesce across account generations',
      () async {
    final waiting = <RequestInterceptorHandler>[];
    final firstEntered = Completer<void>();
    final secondEntered = Completer<void>();
    respond = (_, handler) {
      waiting.add(handler);
      if (waiting.length == 1) firstEntered.complete();
      if (waiting.length == 2) secondEntered.complete();
    };
    final first = FriendRequestApi.instance.fetchIncomingPending(limit: 20);
    await firstEntered.future;
    SessionIdentityService.instance.invalidate();
    final second = FriendRequestApi.instance.fetchIncomingPending(limit: 20);
    await secondEntered.future.timeout(const Duration(seconds: 3));
    expect(requests, hasLength(2));
    for (var index = 0; index < waiting.length; index++) {
      waiting[index].resolve(
          Response(requestOptions: requests[index], statusCode: 200, data: {
        'items': [
          {'id': index + 1, 'fromUserId': 'user$index'}
        ]
      }));
    }
    expect((await first).single.id, 1);
    expect((await second).single.id, 2);
  });

  test('reading displayed requests no longer changes the entry badge', () {
    final notice = FriendRequestNoticeService.instance;
    notice.pendingApplicationCount.value = 5;
    final row = FriendRequestRecord.fromPendingJson(
        {'id': 321, 'fromUserId': 'friend'},
        direction: FriendRequestDirection.incoming);
    notice.markLoadedRequestsRead([row]);
    notice.markLoadedRequestsRead([row]);
    expect(notice.pendingApplicationCount.value, 5);
    expect(requests, isEmpty);
  });

  test(
      'friend list starts with limit20 and history cursor belongs to the returned page',
      () async {
    respond = (request, handler) {
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'data': {
          'items': [],
          'content': [],
          'hasMore': true,
          'nextCursor': 'next'
        }
      }));
    };
    await FriendApplicationHelper.loadRequestWindow(incoming: true, limit: 20);
    await FriendApplicationHelper.loadRequestWindow(incoming: false, limit: 20);
    final first =
        await FriendRequestApi.instance.fetchHandledHistoryPage(limit: 20);
    expect(first.nextCursor, 'next');
    final second = await FriendRequestApi.instance
        .fetchHandledHistoryPage(cursor: first.nextCursor, limit: 20);
    expect(second.hasMore, isFalse,
        reason: 'a repeated cursor must not create an infinite load loop');
    expect(requests.map((request) => request.queryParameters['limit']),
        [20, 20, 20, 20]);
    expect(requests.last.queryParameters['cursor'], 'next');
  });
}
