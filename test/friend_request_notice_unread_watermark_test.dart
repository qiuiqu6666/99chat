import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/friend_request_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_request_notice_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <RequestOptions>[];
  late List<Map<String, Object>> incomingItems;
  var account = 0;
  late String owner;

  FriendRequestRecord requestAt({
    required int id,
    required int createdAtMs,
    String user = 'friend',
  }) {
    return FriendRequestRecord.fromPendingJson(
      {
        'id': id,
        'fromUserId': user,
        'createdAt': createdAtMs,
        'status': 'pending',
      },
      direction: FriendRequestDirection.incoming,
    );
  }

  Map<String, Object> itemAt({
    required int id,
    required int createdAtMs,
    String user = 'friend',
  }) {
    return {
      'id': id,
      'fromUserId': user,
      'createdAt': createdAtMs,
      'status': 'pending',
    };
  }

  String watermarkKey() =>
      '${friendRequestReadWatermarkStorageKey}_${ChatIdFormat.rawUserUid(owner)}';

  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(onRequest: (request, handler) {
        requests.add(request);
        if (request.path.contains('/friend-requests/incoming')) {
          handler.resolve(
            Response(
              requestOptions: request,
              statusCode: 200,
              data: {'items': incomingItems},
            ),
          );
          return;
        }
        handler.resolve(
          Response(
            requestOptions: request,
            statusCode: 200,
            data: {'items': []},
          ),
        );
      }),
    );
  });

  setUp(() async {
    requests.clear();
    incomingItems = <Map<String, Object>>[];
    SessionIdentityService.instance.invalidate();
    await FriendRequestNoticeService.instance.stop();
    SharedPreferences.setMockInitialValues({});
    owner = 'friend-wm-${account++}';
    await ApiClient.instance.saveToken('test-token', userId: owner);
  });

  tearDown(() async {
    await FriendRequestNoticeService.instance.stop();
  });

  test('older pending stay read after commit watermark', () {
    const tA = 1700000000000;
    const tB = 1700000001000;
    const tC = 1700000002000;
    final a = requestAt(id: 1, createdAtMs: tA, user: 'a');
    final b = requestAt(id: 2, createdAtMs: tB, user: 'b');
    final c = requestAt(id: 3, createdAtMs: tC, user: 'c');
    final watermark = watermarkFromObserved(
      [a, b, c],
      const FriendRequestReadWatermark.empty(),
    );
    expect(watermark.createdAtMs, tC);
    expect(
      computeFriendRequestUnreadCount(
        pending: [a, b, c],
        watermark: watermark,
      ),
      0,
    );
  });

  test('a later request after watermark is unread', () {
    const seenAt = 1700000002000;
    final watermark = FriendRequestReadWatermark(
      createdAtMs: seenAt,
      idsAtCreatedAt: const {'3'},
    );
    final replayed = [
      requestAt(id: 1, createdAtMs: 1700000000000, user: 'a'),
      requestAt(id: 2, createdAtMs: 1700000001000, user: 'b'),
      requestAt(id: 3, createdAtMs: seenAt, user: 'c'),
    ];
    expect(
      computeFriendRequestUnreadCount(
        pending: replayed,
        watermark: watermark,
      ),
      0,
    );
    final withNew = [
      ...replayed,
      requestAt(id: 4, createdAtMs: seenAt + 1000, user: 'd'),
    ];
    expect(
      computeFriendRequestUnreadCount(
        pending: withNew,
        watermark: watermark,
      ),
      1,
    );
  });

  test('same createdAt with a new request id stays unread', () {
    const createdAt = 1700000002000;
    final watermark = FriendRequestReadWatermark(
      createdAtMs: createdAt,
      idsAtCreatedAt: const {'3'},
    );
    final sameMsNewId = requestAt(id: 9, createdAtMs: createdAt, user: 'e');
    expect(isFriendRequestAfterReadWatermark(sameMsNewId, watermark), isTrue);
  });

  test('commitObservedAsRead persists owner watermark and clears badge',
      () async {
    const tA = 1700000000000;
    const tB = 1700000001000;
    const tC = 1700000002000;
    incomingItems = [
      itemAt(id: 1, createdAtMs: tA, user: 'a'),
      itemAt(id: 2, createdAtMs: tB, user: 'b'),
      itemAt(id: 3, createdAtMs: tC, user: 'c'),
    ];
    final notice = FriendRequestNoticeService.instance;
    notice.pendingApplicationCount.value = 3;
    await notice.commitObservedAsRead();
    expect(notice.pendingApplicationCount.value, 0);
    expect(requests, isNotEmpty);
    expect(
      requests.every((request) => request.path.contains('/friend-requests/incoming')),
      isTrue,
    );
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(watermarkKey());
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    expect(decoded['createdAt'], tC);
    expect(decoded.containsKey('now'), isFalse);
    expect(
      DateTime.now().millisecondsSinceEpoch - (decoded['createdAt'] as int),
      greaterThan(1000),
    );
  });

  test('stop clears memory but keeps owner watermark prefs', () async {
    incomingItems = [
      itemAt(id: 1, createdAtMs: 1700000000000, user: 'a'),
      itemAt(id: 2, createdAtMs: 1700000001000, user: 'b'),
      itemAt(id: 3, createdAtMs: 1700000002000, user: 'c'),
    ];
    final notice = FriendRequestNoticeService.instance;
    notice.pendingApplicationCount.value = 3;
    await notice.commitObservedAsRead();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(watermarkKey()), isNotNull);
    await notice.stop();
    expect(notice.pendingApplicationCount.value, 0);
    expect(prefs.getString(watermarkKey()), isNotNull);
    await notice.ensureWatermarkLoaded();
    final restored = FriendRequestReadWatermark.fromJsonString(
      prefs.getString(watermarkKey()),
    );
    final replayed = [
      requestAt(id: 1, createdAtMs: 1700000000000, user: 'a'),
      requestAt(id: 2, createdAtMs: 1700000001000, user: 'b'),
      requestAt(id: 3, createdAtMs: 1700000002000, user: 'c'),
    ];
    expect(
      computeFriendRequestUnreadCount(
        pending: replayed,
        watermark: restored,
      ),
      0,
    );
  });

  test('clearForOwner deletes the owner watermark', () async {
    incomingItems = [
      itemAt(id: 1, createdAtMs: 1700000000000, user: 'a'),
    ];
    final notice = FriendRequestNoticeService.instance;
    notice.pendingApplicationCount.value = 1;
    await notice.commitObservedAsRead();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(watermarkKey()), isNotNull);
    await notice.clearForOwner(owner);
    expect(prefs.getString(watermarkKey()), isNull);
    expect(
      computeFriendRequestUnreadCount(
        pending: [requestAt(id: 1, createdAtMs: 1700000000000, user: 'a')],
        watermark: const FriendRequestReadWatermark.empty(),
      ),
      1,
    );
  });

  test('commit fetches at notice layer when badge is set without observed rows',
      () async {
    incomingItems = [
      itemAt(id: 8, createdAtMs: 1700000005000, user: 'late'),
    ];
    final notice = FriendRequestNoticeService.instance;
    notice.pendingApplicationCount.value = 2;
    await notice.commitObservedAsRead();
    expect(notice.pendingApplicationCount.value, 0);
    expect(requests, hasLength(1));
    expect(requests.single.path.contains('/friend-requests/incoming'), isTrue);
  });
}
