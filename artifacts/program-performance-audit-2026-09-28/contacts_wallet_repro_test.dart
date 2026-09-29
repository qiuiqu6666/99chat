// Read-only audit reproductions. These tests assert the CURRENT defects,
// not the desired behavior, and do not modify product sources.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_repository.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_store.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/record/wallet_record_controller.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/record/wallet_record_models.dart';

class DelayedAuditRepository implements WalletRepository {
  final walletResponse = Completer<WalletDto>();
  final recordsResponse = Completer<List<WalletRecordDto>>();
  int walletCalls = 0;
  final filters = <HistoryRecordFilter>[];

  @override
  Future<WalletDto> getWallet() {
    walletCalls++;
    return walletResponse.future;
  }

  @override
  Future<List<WalletRecordDto>> getWalletRecordsByFilter(
      HistoryRecordFilter filter) {
    filters.add(filter);
    return recordsResponse.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WalletDto snapshot(String balance) =>
    WalletDto(totalBal: balance, trxAddr: 'audit-address', coins: []);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    WalletStore.instance.clear();
  });
  tearDown(WalletStore.instance.clear);

  test('reproduces clear followed by stale in-flight wallet cache refill', () async {
    final repo = DelayedAuditRepository();
    final oldRequest = WalletStore.instance.getWallet(repo: repo);
    WalletStore.instance.clear();
    expect(WalletStore.instance.cachedWallet, isNull);
    repo.walletResponse.complete(snapshot('old-100'));
    await oldRequest;
    expect(WalletStore.instance.cachedWallet!.totalBal, 'old-100');
    final nextRepo = DelayedAuditRepository();
    final next = await WalletStore.instance.getWallet(repo: nextRepo);
    expect(next.totalBal, 'old-100');
    expect(nextRepo.walletCalls, 0);
  });

  test('reproduces older forced wallet response overwriting a newer response', () async {
    final oldRepo = DelayedAuditRepository();
    final newRepo = DelayedAuditRepository();
    final oldRequest = WalletStore.instance.getWallet(repo: oldRepo, force: true);
    final newRequest = WalletStore.instance.getWallet(repo: newRepo, force: true);
    newRepo.walletResponse.complete(snapshot('new-200'));
    await newRequest;
    expect(WalletStore.instance.cachedWallet!.totalBal, 'new-200');
    oldRepo.walletResponse.complete(snapshot('old-100'));
    await oldRequest;
    expect(WalletStore.instance.cachedWallet!.totalBal, 'old-100');
  });

  test('reproduces record filter change dropped during in-flight loading', () async {
    final repo = DelayedAuditRepository();
    final controller = WalletRecordController(repo: repo);
    final request = controller.load();
    controller.setFilter(HistoryRecordFilter.redPacket);
    expect(controller.filter, HistoryRecordFilter.redPacket);
    expect(repo.filters, [HistoryRecordFilter.all]);
    repo.recordsResponse.complete([]);
    await request;
    await Future<void>.delayed(Duration.zero);
    expect(repo.filters, [HistoryRecordFilter.all]);
    expect(controller.loading, isFalse);
    controller.dispose();
  });
}
