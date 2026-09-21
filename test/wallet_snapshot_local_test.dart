import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_controller.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_repository.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_snapshot_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

class PendingWalletRepository implements WalletRepository {
  final response = Completer<WalletDto>();
  final started = Completer<void>();
  @override
  Future<WalletDto> getWallet() {
    if (!started.isCompleted) started.complete();
    return response.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WalletDto snapshot(String balance) => WalletDto(
      totalBal: balance,
      totalBalUsd: '12.30',
      trxAddr: 'test-address',
      coins: [
        CoinDto(
            name: 'USDT',
            code: 'USDT',
            sub: '¥6.639',
            bal: balance,
            fiat: '¥81.65',
            type: CoinType.usdt,
            logoUrl: 'https://example.test/coin.png',
            balMinor: 12345678,
            scale: 6,
            withdrawEnabled: false,
            priceChangePercent: -0.5)
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late WalletSnapshotLocalStore store;
  late String path;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final directory =
        await Directory.systemTemp.createTemp('wallet_snapshot_test_');
    path = '${directory.path}/snapshot.db';
    store = WalletSnapshotLocalStore(databasePath: path);
    addTearDown(() async {
      await store.close();
      for (final file in directory.listSync().whereType<File>()) {
        await file.delete();
      }
      await directory.delete();
    });
    await ApiClient.instance.saveToken('test-token', userId: 'wallet-owner-a');
  });

  test('snapshot survives database reopen with all coin display fields',
      () async {
    await store.write('wallet-owner-a', snapshot('12.345678'));
    await store.close();
    store = WalletSnapshotLocalStore(databasePath: path);
    final loaded = (await store.read('wallet-owner-a'))!;
    expect(loaded.totalBal, '12.345678');
    expect(loaded.totalBalUsd, '12.30');
    expect(loaded.trxAddr, 'test-address');
    final coin = loaded.coins.single;
    expect(coin.name, 'USDT');
    expect(coin.code, 'USDT');
    expect(coin.sub, '¥6.639');
    expect(coin.bal, '12.345678');
    expect(coin.fiat, '¥81.65');
    expect(coin.logoUrl, 'https://example.test/coin.png');
    expect(coin.balMinor, 12345678);
    expect(coin.scale, 6);
    expect(coin.withdrawEnabled, isFalse);
    expect(coin.depositEnabled, isTrue);
    expect(coin.priceChangePercent, -0.5);
    expect(await store.read('wallet-owner-b'), isNull);
    expect(await store.read(''), isNull);
  });

  test('cold controller shows disk coins before the network completes',
      () async {
    await store.write('wallet-owner-a', snapshot('10'));
    final repo = PendingWalletRepository();
    final controller = WalletController(repo: repo, localStore: store);
    addTearDown(controller.dispose);
    final loading = controller.load();
    await repo.started.future;
    expect(controller.totalBal, '10');
    expect(controller.coins.single.code, 'USDT');
    expect(controller.loading, isFalse);
    repo.response.complete(snapshot('20'));
    await loading;
    expect(controller.totalBal, '20');
    await store.close();
    expect((await store.read('wallet-owner-a'))!.totalBal, '20');
  });

  test('offline refresh retains disk data', () async {
    await store.write('wallet-owner-a', snapshot('10'));
    final repo = PendingWalletRepository();
    final controller = WalletController(repo: repo, localStore: store);
    addTearDown(controller.dispose);
    final loading = controller.load();
    await repo.started.future;
    repo.response.completeError(StateError('offline'));
    await loading;
    expect(controller.coins.single.bal, '10');
    expect(controller.loadFailed, isFalse);
    expect((await store.read('wallet-owner-a'))!.totalBal, '10');
  });

  test('empty successful response replaces removed currencies', () async {
    await store.write('wallet-owner-a', snapshot('10'));
    await store.write('wallet-owner-a',
        const WalletDto(totalBal: '0', trxAddr: '', coins: []));
    expect((await store.read('wallet-owner-a'))!.coins, isEmpty);
  });

  test('account switch rejects the previous account network response',
      () async {
    await store.write('wallet-owner-a', snapshot('10'));
    final repo = PendingWalletRepository();
    final controller = WalletController(repo: repo, localStore: store);
    addTearDown(controller.dispose);
    final loading = controller.load();
    await repo.started.future;
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance
        .saveToken('test-token-b', userId: 'wallet-owner-b');
    repo.response.complete(snapshot('999'));
    await loading;
    expect(controller.coins, isEmpty);
    expect((await store.read('wallet-owner-a'))!.totalBal, '10');
    expect(await store.read('wallet-owner-b'), isNull);
  });
}
