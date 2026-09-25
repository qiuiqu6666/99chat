import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/wallet_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/wallet_ledger_local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final client = ApiClient.instance;
  final store = WalletLedgerLocalStore.instance;
  const owner = 'scale-wallet-recovery';
  late List<Interceptor> saved;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await client.saveAuthenticatedUserIdIfCurrent(
        expectedToken: client.token, userId: owner);
    expect(store.currentOwnerUserId(), owner);
    await store.clearForOwner(owner);
    saved = client.dio.interceptors.toList();
    client.dio.interceptors.clear();
  });

  tearDown(() async {
    client.dio.interceptors
      ..clear()
      ..addAll(saved);
    await store.clearForOwner(owner);
    await client.clearToken();
    debugDefaultTargetPlatformOverride = null;
  });

  Map<String, dynamic> row(String id) => {
        'id': id,
        'ledgerType': 'GROUP_CREATE',
        'source': 'PLATFORM',
        'currency': '99',
        'amount': -100,
        'direction': 'OUT',
        'status': 'SUCCESS',
        'createdAt': '2026-09-25T04:00:00Z',
      };

  test(
      'snapshot continues after its visit budget and restarts on a changed head',
      () async {
    final pages = <int>[];
    var prefix = 'old';
    client.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) {
      final page = request.queryParameters['page'] as int;
      pages.add(page);
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'data': {
          'content': [
            row('$prefix-${page * 2}'),
            row('$prefix-${page * 2 + 1}')
          ]
        }
      }));
    }));
    await WalletApi.instance
        .getLedgerAll(pageSize: 2, maxPages: 3, awaitFirstPage: true);
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(pages, [0, 1, 2]);
    pages.clear();
    await WalletApi.instance
        .getLedgerAll(pageSize: 2, maxPages: 3, awaitFirstPage: true);
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(pages, [0, 3, 4]);
    pages.clear();
    prefix = 'new';
    await WalletApi.instance
        .getLedgerAll(pageSize: 2, maxPages: 3, awaitFirstPage: true);
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(pages, [0, 1, 2]);
  });

  test(
      'slow history refresh returns cached rows and reuses the original request',
      () async {
    var requests = 0;
    var slow = false;
    final release = Completer<void>();
    client.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) async {
      requests++;
      if (slow) await release.future;
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'data': {
          'content': [row(slow ? 'new-charge' : 'old-charge')]
        }
      }));
    }));
    expect(
        (await WalletApi.instance.getHistoryRecords()).single.id, 'old-charge');
    slow = true;
    final timer = Stopwatch()..start();
    final cached = await WalletApi.instance
        .getHistoryRecords()
        .timeout(const Duration(seconds: 5));
    expect(timer.elapsed, lessThan(const Duration(seconds: 4)));
    expect(cached.single.id, 'old-charge');
    expect(requests, 2);
    release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(requests, 2);
    // The late response was applied by the continuation, not a third request.
    const scope =
        '{"ledgerTypes":[],"source":"","currency":"","startTime":"","endTime":""}';
    expect(
        (await store.read(scopeKey: scope, ownerUserId: owner))
            .map((e) => e.id),
        contains('new-charge'));
  });
}
