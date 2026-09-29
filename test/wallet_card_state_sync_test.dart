import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_repository.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_store.dart';

class _Cards implements WalletRepository {
  final requests = <Completer<WalletOrderCardDto>>[];
  @override
  Future<WalletOrderCardDto> getWalletOrderCard({
    required String type,
    required String orderId,
    required String clientOrderId,
    String? currency,
    int? amount,
    String? status,
    String? greeting,
  }) {
    final request = Completer<WalletOrderCardDto>();
    requests.add(request);
    return request.future;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    WalletStore.instance.clear();
  });
  tearDown(() => WalletStore.instance.clear());

  Future<WalletOrderCardDto> load(_Cards repo, String status) =>
      WalletStore.instance.getOrderCard(
        repo: repo, type: 'wallet_red_packet', orderId: '7', clientOrderId: 'cid',
        amount: 10000, currency: '99', status: status,
      );
  void invalidate() => WalletStore.instance.invalidateOrderCard(
        type: 'wallet_red_packet', orderId: '7', clientOrderId: 'cid',
      );
  WalletOrderCardDto card(String status) => WalletOrderCardDto(
        ok: true, type: 'wallet_red_packet', status: status,
        amount: '100.00', coin: '99', title: '红包', msg: '',
      );

  test('a rejected order cannot be revived from a forged success payload', () async {
    final repo = _Cards();
    final result = load(repo, 'success');
    repo.requests.single.complete(WalletOrderCardDto.invalidCard());
    expect((await result).invalid, isTrue);
    expect((await load(repo, 'success')).invalid, isTrue);
    expect(repo.requests.length, 1);
  });

  test('claim update invalidates every alias and late pre-claim response cannot revert it', () async {
    final repo = _Cards();
    final before = load(repo, 'active');
    final staleRejected = expectLater(before, throwsA(isA<StateError>()));
    invalidate();
    final after = load(repo, 'empty');
    repo.requests[1].complete(card('empty'));
    expect((await after).status, 'empty');
    repo.requests[0].complete(card('active'));
    await staleRejected;
    expect((await load(repo, 'empty')).status, 'empty');
    expect(repo.requests.length, 2);
  });

  test('partial-claim revision refetches even while status remains active', () async {
    final repo = _Cards();
    final before = load(repo, 'active');
    repo.requests.single.complete(card('active'));
    await before;
    invalidate();
    final after = load(repo, 'active');
    expect(repo.requests.length, 2);
    repo.requests.last.complete(card('claimed'));
    expect((await after).status, 'claimed');
  });
}
