import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/user_api.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'peer_hydrate_1';
  final dio = ApiClient.instance.dio;
  late List<Interceptor> saved;
  late PresenceProvider presence;
  late int staleTs;
  late int freshTs;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    TIMUIKitCore.getInstance();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Reset the writer's committed mirror together with mock preferences.
    await ContactSocialCacheStore.clearPresenceLastSeen();
    await ContactSocialCacheStore.clearPresenceVisibility();
    saved = dio.interceptors.toList();
    dio.interceptors.clear();
    staleTs = DateTime.now()
        .subtract(const Duration(hours: 3))
        .millisecondsSinceEpoch;
    freshTs = DateTime.now()
        .subtract(const Duration(hours: 1))
        .millisecondsSinceEpoch;
    await ContactSocialCacheStore.mergePresenceLastSeen({userId: staleTs});
    await ContactSocialCacheStore.mergePresenceVisibility({
      userId: LastActiveVisibility.hidden,
    });
    presence = PresenceProvider();
    await _waitUntil(
      () =>
          presence.lastSeenOf(userId) != null &&
          presence.visibilityOf(userId) != null,
      'hydrate did not load lastSeen/visibility',
    );
  });

  tearDown(() async {
    presence.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    dio.interceptors.clear();
    dio.interceptors.addAll(saved);
  });

  test('hydrate paints cache then refresh overwrites lastSeen and visibility',
      () async {
    expect(presence.lastSeenOf(userId), staleTs);
    expect(
      presence.visibilityOf(userId),
      LastActiveVisibility.hidden,
    );
    expect(
      presence.listLabelFor(
        userId: userId,
        imOnline: false,
        isMutualFriend: true,
      ),
      presence.hiddenLastActiveLabelFromTimestamp(staleTs),
    );

    final paths = <String>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      paths.add(request.path);
      handler.resolve(Response(
        requestOptions: request,
        statusCode: 200,
        data: {
          'code': 0,
          'data': {
            'lastSeen': {userId: freshTs},
            'lastActiveVisibility': {
              userId: LastActiveVisibility.everyone,
            },
          },
        },
      ));
    }));

    presence.refresh([userId]);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(paths, contains('/presence/last-seen'));
    expect(presence.lastSeenOf(userId), freshTs);
    expect(
      presence.visibilityOf(userId),
      LastActiveVisibility.everyone,
    );
    expect(
      presence.listLabelFor(
        userId: userId,
        imOnline: false,
        isMutualFriend: true,
      ),
      presence.lastActiveLabelFromTimestamp(freshTs),
    );
  });

  test('hydrate then ensure does not refetch last-seen', () async {
    final paths = <String>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      paths.add(request.path);
      handler.resolve(Response(
        requestOptions: request,
        statusCode: 200,
        data: {
          'code': 0,
          'data': {
            'lastSeen': {userId: freshTs},
            'lastActiveVisibility': {
              userId: LastActiveVisibility.everyone,
            },
          },
        },
      ));
    }));

    presence.ensure([userId]);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(paths.contains('/presence/last-seen'), isFalse);
    expect(presence.lastSeenOf(userId), staleTs);
    expect(
      presence.visibilityOf(userId),
      LastActiveVisibility.hidden,
    );
  });
}

Future<void> _waitUntil(bool Function() ready, String message) async {
  for (var i = 0; i < 50; i++) {
    if (ready()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail(message);
}
