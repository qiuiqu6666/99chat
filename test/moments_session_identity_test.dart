import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/moments/moments_feed_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/moments/moments_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/moments/moments_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Dio dio;
  late List<Interceptor> originalInterceptors;
  Interceptor? delayedFeed;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SessionIdentityService.instance.invalidate(reason: 'test_setup');
    await ApiClient.instance
        .saveToken('moments-owner-a-token', userId: 'moments_owner_a');
    MomentsStore.debugAccountScopeOverride = 'moments_owner_a';
    dio = ApiClient.instance.dio;
    originalInterceptors = List<Interceptor>.of(dio.interceptors);
    dio.interceptors.clear();
  });

  tearDown(() async {
    dio.interceptors
      ..clear()
      ..addAll(originalInterceptors);
    await MomentsLocalStore.instance.clearForOwner('moments_owner_a');
    await MomentsLocalStore.instance.clearForOwner('moments_owner_b');
    await MomentsLocalStore.instance.closeIfOpen();
    MomentsStore.debugAccountScopeOverride = null;
    SessionIdentityService.instance.invalidate(reason: 'test_teardown');
    await ApiClient.instance.clearToken();
  });

  test('late feed page cannot enter the new account state or cache', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    delayedFeed = InterceptorsWrapper(onRequest: (options, handler) async {
      if (options.path != '/moments/feed') {
        handler.next(options);
        return;
      }
      entered.complete();
      await release.future;
      handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'momentId': 'old-account-moment',
              'author': <String, dynamic>{
                'userId': 'moments_owner_a',
                'nickname': '旧账号',
              },
              'text': 'old account response',
              'createdAt': '2026-09-28T00:00:00Z',
            },
          ],
          'hasMore': false,
        },
      ));
    });
    dio.interceptors.add(delayedFeed!);

    final controller = MomentsFeedController();
    final loading = controller.load();
    await entered.future;

    MomentsStore.debugAccountScopeOverride = 'moments_owner_b';
    await ApiClient.instance
        .saveToken('moments-owner-b-token', userId: 'moments_owner_b');
    SessionIdentityService.instance.invalidate(reason: 'test_account_switch');
    release.complete();
    await loading;

    expect(controller.posts, isEmpty);
    expect(await MomentsStore.loadLocalFeed(), isEmpty);
    MomentsStore.debugAccountScopeOverride = 'moments_owner_a';
    expect(await MomentsStore.loadLocalFeed(), isEmpty);
  });
}
