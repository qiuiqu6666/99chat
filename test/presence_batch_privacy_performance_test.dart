import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    TIMUIKitCore.getInstance();
  });
  final dio = ApiClient.instance.dio;
  late List<Interceptor> saved;
  late PresenceProvider presence;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    saved = dio.interceptors.toList();
    dio.interceptors.clear();
    presence = PresenceProvider();
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() async {
    presence.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    dio.interceptors.clear();
    dio.interceptors.addAll(saved);
  });

  test('100 users with batch privacy need one request and retain hidden state', () async {
    final paths = <String>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      paths.add(request.path);
      final ids = (request.data as Map)['userIds'] as List;
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0, 'data': {
          'lastSeen': {for (final id in ids) id: 1700000000000},
          'lastActiveVisibility': {for (final id in ids) id: id == 'u0' ? 'hidden' : 'everyone'},
        }
      }));
    }));
    presence.ensure(List.generate(100, (i) => 'u$i'));
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(paths, ['/presence/last-seen']);
    expect(presence.lastSeenOf('u99'), 1700000000000);
    expect(presence.shouldShowPresence('u0', isMutualFriend: true), isFalse);
  });

  test('batch privacy omissions use fallback only when requested', () async {
    final paths = <String>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      paths.add(request.path);
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0, 'data': request.path == '/presence/last-seen'
            ? {'lastSeen': {'u1': 1700000000000}, 'lastActiveVisibility': {}}
            : {'lastActiveVisibility': 'hidden'},
      }));
    }));
    presence.ensure(['u1']);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(paths, ['/presence/last-seen', '/users/u1/online-privacy-protection']);
    expect(presence.shouldShowPresence('u1', isMutualFriend: true), isFalse);
    paths.clear();
    presence.clearSessionState();
    presence.ensure(['u1'], includeVisibility: false);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(paths, ['/presence/last-seen']);
  });

  test('clearing a pending session allows new fetch and drops old response', () async {
    final pending = <(RequestOptions, RequestInterceptorHandler)>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      pending.add((request, handler));
    }));
    void respond(int index) {
      final (request, handler) = pending[index];
      final id = ((request.data as Map)['userIds'] as List).single;
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'code': 0, 'data': {'lastSeen': {id: 1700000000000}, 'lastActiveVisibility': {id: 'hidden'}}
      }));
    }
    presence.ensure(['old']);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    presence.clearSessionState();
    presence.ensure(['new']);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(pending.length, 2);
    respond(1);
    respond(0);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(presence.lastSeenOf('old'), isNull);
    expect(presence.lastSeenOf('new'), 1700000000000);
  });
}
