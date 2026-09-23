import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function() respond;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
          Future<dynamic>? cancelFuture) =>
      respond();
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const peer = 'peer_cache_consistency';
  late HttpClientAdapter previousAdapter;
  ResponseBody relation(bool value) => ResponseBody.fromString(
          jsonEncode({
            'peerUserId': peer,
            'isFriend': value,
            'inMyFriendList': value,
            'canMessage': value,
            'peerDeletedMe': !value,
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    previousAdapter = ApiClient.instance.dio.httpClientAdapter;
    await ApiClient.instance.saveToken(
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        userId: 'account-a');
    MeFriendApi.instance.invalidateRelation(peer);
  });
  tearDown(() async {
    ApiClient.instance.dio.httpClientAdapter = previousAdapter;
    MeFriendApi.instance.invalidateRelation(peer);
    await ApiClient.instance.clearToken();
  });

  test('invalidated in-flight relation cannot repopulate the cache', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    ApiClient.instance.dio.httpClientAdapter = _Adapter(() async {
      calls++;
      if (calls == 1) {
        entered.complete();
        await release.future;
        return relation(true);
      }
      return relation(false);
    });
    final old = MeFriendApi.instance.tryFetchRelation(peer);
    await entered.future;
    MeFriendApi.instance.invalidateRelation(peer);
    release.complete();
    expect(await old, isNull);
    expect(
        (await MeFriendApi.instance.tryFetchRelation(peer))!.isFriend, isFalse);
    expect(calls, 2);
  });

  test('another account cannot reuse the previous account relation', () async {
    var calls = 0;
    ApiClient.instance.dio.httpClientAdapter =
        _Adapter(() async => relation(++calls == 1));
    expect(
        (await MeFriendApi.instance.tryFetchRelation(peer))!.isFriend, isTrue);
    await ApiClient.instance.saveToken(
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        userId: 'account-b');
    expect(
        (await MeFriendApi.instance.tryFetchRelation(peer))!.isFriend, isFalse);
    expect(calls, 2);
  });
}
