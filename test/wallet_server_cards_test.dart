import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/wallet_api.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/api_wallet_repository.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_order.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_order_service.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_pending_store.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_card_send_service.dart';

WalletOrderDraft draft({bool server = true}) => WalletOrderDraft(
  clientOrderId: 'red_packet_001', type: WalletOrderType.redPacket,
  amountText: '1', amountMinor: 100, coin: '99', network: '',
  businessType: 'wallet_red_packet', conversationId: 'group_001',
  serverManagedCard: server,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient.instance;
  final store = WalletPendingStore();
  late List<Interceptor> saved;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await api.saveToken('wallet-test-token', userId: 'wallet-test-owner');
    await store.clear();
    saved = api.dio.interceptors.toList();
    api.dio.interceptors.clear();
  });
  tearDown(() async {
    api.dio.interceptors..clear()..addAll(saved);
    await store.clear();
    await api.clearToken();
  });

  test('server ownership survives disk round trip and all draft updates', () {
    final restored = WalletOrderDraft.fromJson(draft().toJson()).copyWith(
      serverOrderId: '123', orderState: 'success', ownerUserId: 'owner',
    );
    expect(restored.serverManagedCard, isTrue);
    expect(restored.needsChatCard, isFalse);
    final legacyJson = draft(server: false).toJson()..remove('serverManagedCard');
    expect(WalletOrderDraft.fromJson(legacyJson).needsChatCard, isTrue);
  });

  test('unknown payment stays queryable but never enters client card retries', () async {
    final service = WalletOrderService(store: store);
    final result = await service.run(draft(), (_) async {
      throw WalletSubmitException(requestSent: true, message: 'timeout');
    });
    expect(result.state, WalletOrderState.unknown);
    expect((await store.load()).single.serverManagedCard, isTrue);
    expect(await WalletCardSendService(pendingStore: store).retryPayloads(), isEmpty);
    var queries = 0;
    await service.refreshPending((pending) async {
      queries++;
      expect(pending.clientOrderId, 'red_packet_001');
      return const WalletOrderResult(ok: true, state: WalletOrderState.success, orderId: '12', data: {'cardDeliveryState': 'SENT'});
    });
    expect(queries, 1);
    expect(await store.load(), isEmpty);
  });

  test('new payments use server endpoints without legacy fallback', () async {
    final paths = <String>[];
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (req, handler) {
      paths.add(req.path);
      handler.resolve(Response(requestOptions: req, statusCode: 200, data: {
        'id': '12', 'clientOrderId': 'client', 'status': 'COMPLETED', 'serverManagedCard': true,
      }));
    }));
    final transfer = await WalletApi.instance.createTransfer(toUserId: '2', currency: '99',
      amount: 100, payPin: 'test-only', clientOrderId: 'client');
    await WalletApi.instance.sendRedPacket({'clientPacketId': 'client'});
    expect(paths, ['/wallet/card-orders/transfer', '/wallet/card-orders/red-packet']);
    expect(transfer.state, WalletOrderState.success);
    expect(transfer.data['serverManagedCard'], isTrue);
  });

  test('restart recovery uses client ID even before the numeric order ID arrived', () async {
    final paths = <String>[];
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (req, handler) {
      paths.add(req.path);
      handler.resolve(Response(requestOptions: req, statusCode: 200, data: {
        'id': '42', 'clientOrderId': draft().clientOrderId, 'status': 'COMPLETED',
      }));
    }));
    final result = await const ApiWalletRepository().queryOrderStatus(draft());
    expect(result.orderId, '42');
    expect(result.state, WalletOrderState.success);
    expect(paths, ['/wallet/card-orders/red_packet_001']);
  });

  test('late/not-yet-visible recovery response cannot trigger a second payment', () async {
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (req, handler) {
      expect(req.method, 'GET');
      handler.reject(DioError(requestOptions: req, response: Response(requestOptions: req, statusCode: 404)));
    }));
    final result = await const ApiWalletRepository().queryOrderStatus(draft());
    expect(result.state, WalletOrderState.unknown);
    expect(result.ok, isTrue);
  });
}
