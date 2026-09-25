import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/c2c_friend_message_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';

class _RelationAdapter implements HttpClientAdapter {
  _RelationAdapter(this.respond);

  final Future<bool> Function() respond;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<dynamic>? cancelFuture) async {
    expect(options.path, endsWith('/friends/peer_accept_refresh/relation'));
    final allowed = await respond();
    return ResponseBody.fromString(
      jsonEncode({
        'peerUserId': 'peer_accept_refresh',
        'isFriend': allowed,
        'inMyFriendList': allowed,
        'canMessage': allowed,
        'peerDeletedMe': !allowed,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const peer = 'peer_accept_refresh';
  late HttpClientAdapter previousAdapter;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    previousAdapter = ApiClient.instance.dio.httpClientAdapter;
    await ApiClient.instance.saveToken(
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      userId: 'account-a',
    );
    C2cFriendMessageGuard.debugReset();
    MeFriendApi.instance.invalidateRelation(peer);
    PeerProfileRefreshBus.instance.clear();
  });

  tearDown(() async {
    FriendSyncService.instance.debugProtocolSync = null;
    FriendSyncService.instance.debugOwnerUserId = null;
    ApiClient.instance.dio.httpClientAdapter = previousAdapter;
    C2cFriendMessageGuard.debugReset();
    MeFriendApi.instance.invalidateRelation(peer);
    PeerProfileRefreshBus.instance.clear();
    await ApiClient.instance.clearToken();
  });

  test('forced UI refresh replaces a cached non-friend without restarting',
      () async {
    var calls = 0;
    ApiClient.instance.dio.httpClientAdapter =
        _RelationAdapter(() async => ++calls > 1);
    expect(await C2cFriendMessageGuard.refreshCanSendToForUi(peer), isFalse);

    expect(
      await C2cFriendMessageGuard.refreshCanSendToForUi(peer,
          forceNetwork: true),
      isTrue,
    );
    expect(calls, 2);
    // A reopened chat uses the refreshed permission in the same process.
    expect(C2cFriendMessageGuard.cachedCanSendToSync(peer), isTrue);
    expect((await MeFriendApi.instance.tryFetchRelation(peer))!.canMessage,
        isTrue);
    expect(calls, 2);
  });

  test('forced send permission refresh bypasses the relation cache', () async {
    var calls = 0;
    ApiClient.instance.dio.httpClientAdapter =
        _RelationAdapter(() async => ++calls > 1);
    expect(await C2cFriendMessageGuard.canSendTo(peer), isFalse);
    expect(
      await C2cFriendMessageGuard.refreshAndCanSendTo(peer, forceNetwork: true),
      isTrue,
    );
    expect(calls, 2);
  });

  for (final ui in [true, false]) {
    test(
        'late negative ${ui ? 'UI' : 'send'} request cannot replace acceptance',
        () async {
      final entered = Completer<void>();
      final release = Completer<bool>();
      var calls = 0;
      ApiClient.instance.dio.httpClientAdapter = _RelationAdapter(() async {
        if (++calls == 1) {
          entered.complete();
          return release.future;
        }
        return true;
      });
      final old = ui
          ? C2cFriendMessageGuard.refreshCanSendToForUi(peer)
          : C2cFriendMessageGuard.canSendTo(peer);
      await entered.future;
      try {
        final refreshed = ui
            ? await C2cFriendMessageGuard.refreshCanSendToForUi(peer,
                forceNetwork: true)
            : await C2cFriendMessageGuard.refreshAndCanSendTo(peer,
                forceNetwork: true);
        expect(refreshed, isTrue);
        expect(calls, 2);
      } finally {
        release.complete(false);
      }
      // A superseded UI result is unknown, so it cannot display a blocked bar.
      expect(await old, ui ? isNull : isTrue);
      expect(C2cFriendMessageGuard.cachedCanSendToSync(peer), isTrue);
      expect((await MeFriendApi.instance.tryFetchRelation(peer))!.canMessage,
          isTrue);
      expect(calls, 2);
    });
  }

  for (final ui in [true, false]) {
    test(
        'another contact changing cannot discard ${ui ? 'UI' : 'send'} refresh',
        () async {
      final entered = Completer<void>();
      final release = Completer<bool>();
      ApiClient.instance.dio.httpClientAdapter = _RelationAdapter(() async {
        entered.complete();
        return release.future;
      });
      final pending = ui
          ? C2cFriendMessageGuard.refreshCanSendToForUi(peer,
              forceNetwork: true)
          : C2cFriendMessageGuard.refreshAndCanSendTo(peer, forceNetwork: true);
      await entered.future;
      C2cFriendMessageGuard.invalidate('another_contact', clearTrusted: true);
      release.complete(true);
      expect(await pending, isTrue);
      expect(C2cFriendMessageGuard.cachedCanSendToSync(peer), isTrue);
    });
  }

  test('session reset still discards a pending permission result', () async {
    final entered = Completer<void>();
    final release = Completer<bool>();
    ApiClient.instance.dio.httpClientAdapter = _RelationAdapter(() async {
      entered.complete();
      return release.future;
    });
    final pending = C2cFriendMessageGuard.refreshCanSendToForUi(peer);
    await entered.future;
    C2cFriendMessageGuard.clearSession();
    release.complete(true);
    expect(await pending, isNull);
    expect(C2cFriendMessageGuard.cachedCanSendToSync(peer), isNull);
  });

  for (final allowed in [true, false]) {
    test(
        'friend hint refreshes open chat before contacts finish, server allows=$allowed',
        () async {
      var calls = 0;
      ApiClient.instance.dio.httpClientAdapter =
          _RelationAdapter(() async => ++calls > 1 && allowed);
      expect(await C2cFriendMessageGuard.refreshCanSendToForUi(peer), isFalse);
      final contacts = Completer<void>();
      FriendSyncService.instance.debugOwnerUserId = 'account-a';
      FriendSyncService.instance.debugProtocolSync = (_) => contacts.future;
      final refreshed = Completer<bool?>();
      void onProfileRefresh() {
        if (PeerProfileRefreshBus.instance.matchesLatest(peer) &&
            !refreshed.isCompleted) {
          refreshed.complete(C2cFriendMessageGuard.refreshCanSendToForUi(peer));
        }
      }

      PeerProfileRefreshBus.instance.revision.addListener(onProfileRefresh);
      try {
        await FriendSyncService.instance.onBecameFriends(
          peerUserId: 'c2c_$peer',
          reason: 'friend_request_accepted',
        );
        expect(contacts.isCompleted, isFalse);
        expect(await refreshed.future.timeout(const Duration(seconds: 3)),
            allowed);
        expect(calls, 2);
        // A historical or unverified tip alone must never grant permission.
        expect(C2cFriendMessageGuard.hasFreshTrustedCanSendHint(peer), isFalse);
        expect(C2cFriendMessageGuard.cachedCanSendToSync(peer), allowed);
      } finally {
        PeerProfileRefreshBus.instance.revision
            .removeListener(onProfileRefresh);
        // Fence off the intentionally delayed contacts task before releasing it.
        FriendSyncService.instance.debugOwnerUserId = 'account-b';
        contacts.complete();
        await Future<void>.delayed(Duration.zero);
      }
    });
  }

  test('fresh server rejection still blocks after friendship is removed',
      () async {
    var calls = 0;
    ApiClient.instance.dio.httpClientAdapter =
        _RelationAdapter(() async => ++calls == 1);
    expect(await C2cFriendMessageGuard.refreshCanSendToForUi(peer), isTrue);
    expect(
      await C2cFriendMessageGuard.refreshCanSendToForUi(peer,
          forceNetwork: true),
      isFalse,
    );
    expect(calls, 2);
  });
}
