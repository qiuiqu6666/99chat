import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/api_wallet_repository.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_order.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_order_service.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_pending_store.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_payment_presentation.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_card_send_service.dart';

class _FailAfterSubmitStore extends WalletPendingStore {
  var writes = 0;
  @override
  Future<void> put(WalletOrderDraft draft) async {
    if (++writes > 1) throw StateError('storage unavailable');
    await super.put(draft);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = WalletPendingStore();
  const draft = WalletOrderDraft(
      clientOrderId: 'delivery-recovery',
      type: WalletOrderType.transfer,
      amountText: '1',
      amountMinor: 100,
      coin: '99',
      network: '',
      businessType: 'wallet_transfer',
      conversationId: 'receiver',
      serverManagedCard: true);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.instance.saveToken('test-token', userId: 'delivery-owner');
    await store.clear();
  });
  tearDown(() async {
    await store.clear();
    await ApiClient.instance.clearToken();
  });

  test('unknown outcome keeps the same intent ID across release and retry',
      () async {
    final service = WalletOrderService(store: store);
    await service.run(
        draft,
        (_) async =>
            throw WalletSubmitException(requestSent: true, message: 'timeout'));
    service.release();
    service.cancel();
    expect(service.start('transfer'), draft.clientOrderId);
    await service.refreshPending((_) async => const WalletOrderResult(
        ok: true,
        state: WalletOrderState.success,
        data: {'cardDeliveryState': 'SENT'}));
    expect(service.start('transfer'), isNot(draft.clientOrderId));
  });

  test(
      'local storage failure after payment response cannot become payment failure',
      () async {
    final service = WalletOrderService(store: _FailAfterSubmitStore());
    final result = await service.run(
        draft,
        (_) async => const WalletOrderResult(
            ok: true,
            state: WalletOrderState.success,
            orderId: 'committed',
            data: {'cardDeliveryState': 'PENDING'}));
    expect(result.state, WalletOrderState.success);
    expect((await store.load()).single.clientOrderId, draft.clientOrderId);
  });

  test('gateway errors retain the payment ID rather than reporting rejection',
      () async {
    final dio = ApiClient.instance.dio;
    final original = dio.interceptors.toList();
    dio.interceptors.clear();
    dio.interceptors.add(InterceptorsWrapper(
        onRequest: (req, handler) => handler.reject(DioError(
            requestOptions: req,
            response: Response(
                requestOptions: req,
                statusCode: 502,
                data: 'gateway failed')))));
    try {
      final service = WalletOrderService(store: store);
      final result = await service.run(
          draft,
          (id) => const ApiWalletRepository().transfer(WalletTransferReq(
              clientOrderId: id,
              toUserId: 'receiver',
              toName: 'receiver',
              amt: '1',
              amountMinor: '100',
              coin: '99',
              payId: '99',
              net: '',
              pwd: 'test-only',
              memo: '')));
      expect(result.state, WalletOrderState.unknown);
      expect(service.start('transfer'), draft.clientOrderId);
    } finally {
      dio.interceptors
        ..clear()
        ..addAll(original);
    }
  });

  test(
      'committed payment survives restart and query failure until card is delivered',
      () async {
    await WalletOrderService(store: store).run(
        draft,
        (_) async => const WalletOrderResult(
            ok: true,
            state: WalletOrderState.success,
            orderId: '1',
            data: {'serverManagedCard': true, 'cardDeliveryState': 'PENDING'}));
    expect((await store.load()).single.needsOrderStatusQuery, isTrue);
    expect(await WalletCardSendService(pendingStore: store).retryPayloads(),
        isEmpty);
    final restarted = WalletOrderService(store: store);
    await restarted.refreshPending((_) async =>
        const WalletOrderResult(ok: true, state: WalletOrderState.unknown));
    expect((await store.load()).single.orderState, 'success');
    await restarted.refreshPending((_) async => const WalletOrderResult(
        ok: true,
        state: WalletOrderState.success,
        data: {'cardDeliveryState': 'RECONCILING'}));
    expect((await store.load()).single.cardSendStatus, 'reconciling');
    await restarted.refreshPending((_) async => const WalletOrderResult(
        ok: true,
        state: WalletOrderState.success,
        data: {'cardDeliveryState': 'SENT'}));
    expect(await store.load(), isEmpty);
  });

  test('failed status request cannot discard a committed payment delivery task',
      () async {
    await store
        .put(draft.copyWith(orderState: 'success', cardSendStatus: 'pending'));
    await WalletOrderService(store: store).refreshPending((_) async =>
        const WalletOrderResult(ok: false, state: WalletOrderState.failed));
    expect((await store.load()).single.orderState, 'success');
  });

  test('unknown payment and undelivered card never present delivery success',
      () {
    for (final state in [
      WalletOrderState.unknown,
      WalletOrderState.accepted,
      WalletOrderState.pending
    ]) {
      expect(WalletPaymentPresentation(state, null).paymentCommitted, isFalse);
    }
    const result = WalletOrderResult(
        ok: true,
        state: WalletOrderState.success,
        data: {'serverManagedCard': true, 'cardDeliveryState': 'RECONCILING'});
    const presentation =
        WalletPaymentPresentation(WalletOrderState.success, result);
    expect(presentation.paymentCommitted, isTrue);
    expect(presentation.deliveryPending, isTrue);
  });

  test('capacity never evicts unresolved deliveries', () async {
    for (var i = 0; i < 55; i++) {
      await store.put(WalletOrderDraft.fromJson({
        ...draft.toJson(),
        'clientOrderId': 'pending-$i',
        'orderState': 'success',
      }));
    }
    expect((await store.load()).length, 55);
    expect((await store.load()).every((item) => item.needsOrderStatusQuery),
        isTrue);
  });
}
