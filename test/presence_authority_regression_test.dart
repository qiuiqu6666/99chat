import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/services/coalesced_presence_cache.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_status.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const peer = 'presence-authority-peer';
  final fresh =
      DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
  final stale = fresh - 86400000;
  late PresenceProvider presence;
  late List<Interceptor> interceptors;
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    TIMUIKitCore.getInstance();
  });
  setUp(() async {
    await ContactSocialCacheStore.clearPresenceLastSeen();
    await ContactSocialCacheStore.clearPresenceVisibility();
    interceptors = ApiClient.instance.dio.interceptors.toList();
    ApiClient.instance.dio.interceptors.clear();
    presence = PresenceProvider();
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() async {
    presence.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    ApiClient.instance.dio.interceptors
      ..clear()
      ..addAll(interceptors);
  });

  test('old route seeds cannot rewind memory, disk or visible label', () async {
    presence.applyPresenceChanged(
        peerUserId: peer,
        lastActiveAt: fresh,
        lastActiveVisibility: 'everyone',
        online: false);
    presence.applyPresenceBatch(lastSeen: {peer: stale});
    expect(presence.lastSeenOf(peer), fresh);
    expect(
        presence.labelFor(
            userId: peer,
            imOnline: false,
            isMutualFriend: true,
            lastActiveAtOverride: stale),
        presence.lastActiveLabelFromTimestamp(fresh));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect((await ContactSocialCacheStore.readPresenceLastSeen())[peer], fresh);
  });

  test('late HTTP reply cannot rewind a newer realtime timestamp', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (request, handler) async {
        started.complete();
        await release.future;
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'data': {
            'lastSeen': {peer: stale},
            'lastActiveVisibility': {peer: 'everyone'}
          }
        }));
      },
    ));
    presence.refresh([peer], urgent: true, includeVisibility: false);
    await started.future;
    presence.applyPresenceChanged(
        peerUserId: peer,
        lastActiveAt: fresh,
        lastActiveVisibility: 'everyone',
        online: false);
    release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(presence.lastSeenOf(peer), fresh);
    expect((await ContactSocialCacheStore.readPresenceLastSeen())[peer], fresh);
  });

  test('disk hydration cannot restore an earlier login session', () async {
    presence.dispose();
    await ContactSocialCacheStore.mergePresenceLastSeen({peer: fresh});
    presence = PresenceProvider();
    presence.clearSessionState();
    await Future<void>.delayed(Duration.zero);
    expect(presence.lastSeenOf(peer), isNull);
  });

  test('late disk hydration preserves fresh realtime time and privacy',
      () async {
    presence.dispose();
    await ContactSocialCacheStore.mergePresenceLastSeen({peer: stale});
    await ContactSocialCacheStore.mergePresenceVisibility({peer: 'everyone'});
    presence = PresenceProvider();
    presence.applyPresenceChanged(
        peerUserId: peer,
        lastActiveAt: fresh,
        lastActiveVisibility: 'hidden',
        online: false);
    await Future<void>.delayed(Duration.zero);
    expect(presence.lastSeenOf(peer), fresh);
    expect(presence.visibilityOf(peer), 'hidden');
  });

  test('coalesced timestamps preserve newest pending and persisted values',
      () async {
    final cache = CoalescedPresenceCache(preserveMaxNumbers: true);
    await Future.wait([
      cache.merge('presence-authority-test', {peer: fresh}),
      cache.merge('presence-authority-test', {peer: stale}),
    ]);
    // A fresh writer must also compare with disk, not only its memory mirror.
    await CoalescedPresenceCache(preserveMaxNumbers: true)
        .merge('presence-authority-test', {peer: stale});
    final prefs = await SharedPreferences.getInstance();
    expect(
        jsonDecode(prefs.getString('presence-authority-test')!)[peer], fresh);
    await cache.clear('presence-authority-test');
    await cache.merge('presence-authority-test', {peer: stale});
    expect(
        jsonDecode(prefs.getString('presence-authority-test')!)[peer], stale);
  });

  test(
      'SDK callback publishes a fresh status list without mutating old indexes',
      () {
    final model = serviceLocator<TUIFriendShipViewModel>();
    model.userStatusList = [V2TimUserStatus(userID: peer, statusType: 1)];
    final previous = model.userStatusList;
    final index = {for (final status in previous) status.userID: status};
    CoreServicesImpl().updateUserStatusList([
      V2TimUserStatus(userID: peer, statusType: 2),
    ]);
    expect(identical(previous, model.userStatusList), isFalse);
    expect(index[peer]?.statusType, 1);
    expect(model.userStatusList.single.statusType, 2);
    model.userStatusList = [];
  });
}
