import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_join_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/user_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var account = 0;
  final paths = <String>[];
  late void Function(RequestOptions, RequestInterceptorHandler) respond;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) {
      paths.add(request.path);
      respond(request, handler);
    }));
  });
  setUp(() async {
    paths.clear();
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance
        .saveToken('test-token', userId: 'efficiency${account++}');
  });
  test('duplicate public profile requests coalesce and reuse successful result',
      () async {
    final gate = Completer<void>();
    final entered = Completer<void>();
    respond = (request, handler) {
      if (!entered.isCompleted) entered.complete();
      gate.future.then((_) => handler.resolve(
              Response(requestOptions: request, statusCode: 200, data: {
            'data': {'userId': 'peer', 'nickname': 'Name'}
          })));
    };
    final first = UserApi.instance.tryFetchUserById('peer');
    final second = UserApi.instance.tryFetchUserById('peer');
    await entered.future.timeout(const Duration(seconds: 2));
    expect(paths, hasLength(1));
    gate.complete();
    expect((await first)?.userId, 'peer');
    expect((await second)?.userId, 'peer');
    await UserApi.instance.tryFetchUserById('peer');
    expect(paths, hasLength(1));
  });

  test('join applications read beyond 700 and passive refresh reuses snapshot',
      () async {
    respond = (request, handler) {
      final offset = request.queryParameters['offset'] as int;
      final count = (701 - offset).clamp(0, 100);
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'data': {
          'items': List.generate(
              count,
              (i) => {
                    'id': offset + i + 1,
                    'groupId': 'group',
                    'userId': 'peer',
                    'status': 'pending',
                  })
        }
      }));
    };
    expect(await GroupJoinApi.instance.fetchAllMyJoinApplications(),
        hasLength(701));
    expect(paths, hasLength(8));
    expect(await GroupJoinApi.instance.fetchAllMyJoinApplications(),
        hasLength(701));
    expect(paths, hasLength(8));
    await GroupJoinApi.instance.fetchAllMyJoinApplications(force: true);
    expect(paths, hasLength(16));
  });
}
