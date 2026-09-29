import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_repository.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_store.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/record/wallet_record_controller.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/record/wallet_record_models.dart';

class ControlledWalletRepository implements WalletRepository {
  final wallets = <Completer<WalletDto>>[];
  final methods = <Completer<List<WalletPayMethodDto>>>[];
  final cards = <Completer<WalletOrderCardDto>>[];
  @override
  Future<List<WalletPayMethodDto>> getPayMethods() {
    final pending = Completer<List<WalletPayMethodDto>>();
    methods.add(pending);
    return pending.future;
  }

  @override
  Future<WalletOrderCardDto> getWalletOrderCard(
      {required String type,
      required String orderId,
      required String clientOrderId,
      String? currency,
      int? amount,
      String? status,
      String? greeting}) {
    final pending = Completer<WalletOrderCardDto>();
    cards.add(pending);
    return pending.future;
  }

  final records = <Completer<List<WalletRecordDto>>>[];
  final filters = <HistoryRecordFilter>[];
  @override
  Future<WalletDto> getWallet() {
    final pending = Completer<WalletDto>();
    wallets.add(pending);
    return pending.future;
  }

  @override
  Future<List<WalletRecordDto>> getWalletRecordsByFilter(
      HistoryRecordFilter filter) {
    filters.add(filter);
    final pending = Completer<List<WalletRecordDto>>();
    records.add(pending);
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WalletDto snapshot(String balance) =>
    WalletDto(totalBal: balance, trxAddr: '', coins: []);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    WalletStore.instance.clear();
  });
  tearDown(() async {
    WalletStore.instance.clear();
    await ApiClient.instance.clearToken();
  });

  test('clear prevents late wallet refill and returns a superseded result',
      () async {
    final repo = ControlledWalletRepository();
    final task = WalletStore.instance.getWallet(repo: repo);
    final rejected = expectLater(task, throwsA(isA<StateError>()));
    WalletStore.instance.clear();
    repo.wallets.single.complete(snapshot('old'));
    await rejected;
    expect(WalletStore.instance.cachedWallet, isNull);
  });

  test('new forced wallet wins even when old response completes last',
      () async {
    final repo = ControlledWalletRepository();
    final old = WalletStore.instance.getWallet(repo: repo, force: true);
    final next = WalletStore.instance.getWallet(repo: repo, force: true);
    repo.wallets[1].complete(snapshot('new'));
    await next;
    repo.wallets[0].complete(snapshot('old'));
    expect((await old).totalBal, 'new');
    expect(WalletStore.instance.cachedWallet!.totalBal, 'new');
  });

  test('direct wallet update cannot be overwritten by earlier fetch', () async {
    final repo = ControlledWalletRepository();
    final task = WalletStore.instance.getWallet(repo: repo);
    WalletStore.instance.updateWallet(snapshot('direct'));
    repo.wallets.single.complete(snapshot('old'));
    expect((await task).totalBal, 'direct');
    expect(WalletStore.instance.cachedWallet!.totalBal, 'direct');
  });

  test('account change hides cache before any network refresh', () async {
    await ApiClient.instance.saveToken('test-token', userId: 'owner-a');
    WalletStore.instance.updateWallet(snapshot('owner-a-balance'));
    await ApiClient.instance.saveToken('test-token-b', userId: 'owner-b');
    expect(WalletStore.instance.cachedWallet, isNull);
  });

  test('busy history retains only latest filter and fetches it', () async {
    final repo = ControlledWalletRepository();
    final controller = WalletRecordController(repo: repo);
    addTearDown(controller.dispose);
    final task = controller.load();
    controller.setFilter(HistoryRecordFilter.redPacket);
    controller.setFilter(HistoryRecordFilter.transfer);
    repo.records[0].complete([]);
    await Future<void>.delayed(Duration.zero);
    expect(
        repo.filters, [HistoryRecordFilter.all, HistoryRecordFilter.transfer]);
    repo.records[1].complete([]);
    await task;
    expect(controller.filter, HistoryRecordFilter.transfer);
    expect(controller.loading, isFalse);
    expect(controller.err, isEmpty);
  });
  test(
      'pay-method clear rejects a late failure without fallback from another scope',
      () async {
    final repo = ControlledWalletRepository();
    final pending = WalletStore.instance.getPayMethods(repo: repo);
    final rejected = expectLater(pending, throwsA(isA<StateError>()));
    WalletStore.instance.clear();
    WalletStore.instance.updatePayMethods([]);
    repo.methods.single.completeError(StateError('old failure'));
    await rejected;
    expect(WalletStore.instance.cachedPayMethods, isEmpty);
  });

  test(
      'invalidating an inflight order cannot refill any alias or clear its successor',
      () async {
    final repo = ControlledWalletRepository();
    final store = WalletStore.instance;
    Future<WalletOrderCardDto> load() => store.getOrderCard(
        repo: repo,
        type: 'transfer',
        orderId: 'order',
        clientOrderId: 'client');
    final old = load();
    final rejected = expectLater(old, throwsA(isA<StateError>()));
    store.invalidateOrderCard(
        type: 'transfer', orderId: 'order', clientOrderId: 'client');
    final latest = load();
    const card = WalletOrderCardDto(
        ok: true,
        type: 'transfer',
        status: 'complete',
        amount: '1',
        coin: 'USDT',
        title: 'Transfer',
        msg: '');
    repo.cards.first.complete(card);
    await rejected;
    expect(identical(load(), latest), isTrue);
    expect(repo.cards.length, 2);
    repo.cards.last.complete(card);
    await latest;
    expect(
        store.peekOrderCard(
            type: 'transfer', orderId: 'order', clientOrderId: 'client'),
        same(card));
    store.clear();
    expect(
        store.peekOrderCard(
            type: 'transfer', orderId: 'order', clientOrderId: 'client'),
        isNull);
  });
  test('old wallet failure resolves to the newer successful force result',
      () async {
    final repo = ControlledWalletRepository();
    final old = WalletStore.instance.getWallet(repo: repo, force: true);
    final next = WalletStore.instance.getWallet(repo: repo, force: true);
    repo.wallets.last.complete(snapshot('latest'));
    await next;
    repo.wallets.first.completeError(StateError('old network failure'));
    expect((await old).totalBal, 'latest');
  });

  test('two pending local orders with no server id never share a card flight',
      () async {
    final repo = ControlledWalletRepository();
    final store = WalletStore.instance;
    final a = store.getOrderCard(
        repo: repo, type: 'transfer', orderId: '', clientOrderId: 'client-a');
    final b = store.getOrderCard(
        repo: repo, type: 'transfer', orderId: '', clientOrderId: 'client-b');
    final count = repo.cards.length;
    for (final pending in repo.cards) {
      pending.complete(const WalletOrderCardDto(
          ok: true,
          type: 'transfer',
          status: 'pending',
          amount: '1',
          coin: 'USDT',
          title: 'Transfer',
          msg: ''));
    }
    await Future.wait([a, b]);
    expect(count, 2);
  });
}
