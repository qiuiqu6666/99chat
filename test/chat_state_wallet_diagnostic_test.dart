// Correctness regressions for the confirmed REST projection boundary.
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/red_packet_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_conversation_cards.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_repository.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_repository_provider.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_store.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/chat_cards/red_packet_card.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/chat_cards/transfer_card.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/custom_message_element.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/custom_message_parse_cache.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_chat_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_presenter.dart';

Map<String, dynamic> payload(String order, String type) => {
      'cardId': '${type == 'wallet_transfer' ? 'transfer' : 'rp'}:$order',
      'orderId': order,
      'customType': type,
      'senderUserId': 'owner',
      'conversationId': 'peer',
      'isGroup': false,
      'paymentState': 'COMMITTED',
      'timestamp': 100,
      'amount': 100,
      'currency': '99',
      'status': 'success',
      'packetType': 'NORMAL_C2C',
      'cardStateVersion': 1,
    };
V2TimMessage message(String id, Map<String, dynamic> data) =>
    V2TimMessage.fromJson({'message_risk_type_identified': 0})
      ..msgID = id
      ..id = id
      ..sender = 'owner'
      ..userID = 'peer'
      ..elemType = 2
      ..timestamp = 100
      ..status = 2
      ..isSelf = true
      ..customElem = V2TimCustomElem(data: jsonEncode(data));

class _LocalCards implements WalletRepository {
  @override
  Future<WalletOrderCardDto> getWalletOrderCard(
          {required String type,
          required String orderId,
          required String clientOrderId,
          String? currency,
          int? amount,
          String? status,
          String? greeting}) async =>
      WalletStore.buildLocalOrderCard(
          type: type,
          currency: currency,
          amount: amount,
          status: status,
          greeting: greeting)!;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.instance.saveToken('diagnostic-test', userId: 'owner');
    configureWalletRepository(_LocalCards());
    await RedPacketLocalStore.instance
        .markOpened(orderId: '7', ownerUserId: 'owner');
    WalletStore.instance.clear();
    CustomMessageParseCache.instance.clear();
  });
  tearDown(() async {
    WalletStore.instance.clear();
    clearWalletRepositoryForTest();
    await ApiClient.instance.clearToken();
  });

  test('REST mismatch cannot change same msgID business family', () async {
    var data = payload('7', 'wallet_red_packet');
    final feed = WalletConversationCards(
        target: 'peer',
        group: false,
        reader: (_) async => {
              'cards': [data]
            });
    addTearDown(feed.dispose);
    final canonical = message('red-msg', payload('7', 'wallet_red_packet'));
    await feed.refresh();
    expect(
        jsonDecode(feed.formalRows([canonical]).single.customElem!.data!)[
            'customType'],
        'wallet_red_packet');
    // Fault injection: a REST record reuses rp:7 with a conflicting business type.
    // This test does not claim that the production server emitted this record.
    data = {...data, 'customType': 'wallet_group_transfer'};
    await feed.refresh();
    final projected = feed.formalRows([canonical]).single;
    expect(projected.msgID, canonical.msgID);
    expect(jsonDecode(canonical.customElem!.data!)['customType'],
        'wallet_red_packet');
    expect(jsonDecode(projected.customElem!.data!)['customType'],
        'wallet_red_packet');
  });

  for (final family in [
    'wallet_red_packet',
    'wallet_transfer',
    'wallet_group_transfer'
  ]) {
    test('$family accepts same entity newer version only', () async {
      var data = payload('7', family);
      final feed = WalletConversationCards(
          target: 'peer',
          group: false,
          reader: (_) async => {
                'cards': [data]
              });
      addTearDown(feed.dispose);
      final canonical = message('entity', data);
      await feed.refresh();
      data = {...data, 'status': 'received', 'cardStateVersion': 2};
      await feed.refresh();
      final projected = feed.formalRows([canonical]).single;
      expect(jsonDecode(projected.customElem!.data!)['status'], 'received');
      expect(jsonDecode(projected.customElem!.data!)['customType'], family);
      expect(jsonDecode(canonical.customElem!.data!)['status'], 'success');
    });
  }
  for (final (im, rest) in [
    ('wallet_red_packet', 'wallet_transfer'),
    ('wallet_red_packet', 'wallet_group_transfer'),
    ('wallet_transfer', 'wallet_red_packet'),
    ('wallet_transfer', 'wallet_group_transfer'),
    ('wallet_group_transfer', 'wallet_red_packet'),
    ('wallet_group_transfer', 'wallet_transfer'),
  ]) {
    for (final version in [1, 2]) {
      test('$im rejects $rest at version $version', () async {
        final canonical = message('entity', payload('7', im));
        var data = payload('7', im);
        final feed = WalletConversationCards(
            target: 'peer',
            group: false,
            reader: (_) async => {
                  'cards': [data]
                });
        addTearDown(feed.dispose);
        await feed.refresh();
        feed.formalRows([canonical]);
        data = {...data, 'customType': rest, 'cardStateVersion': version};
        await feed.refresh();
        expect(
            jsonDecode(feed.formalRows([canonical]).single.customElem!.data!)[
                'customType'],
            im);
        expect(feed.displayRows, isEmpty);
      });
    }
  }
  test('equal version payload conflict retains previously accepted projection',
      () async {
    var data = payload('7', 'wallet_red_packet');
    final feed = WalletConversationCards(
        target: 'peer',
        group: false,
        reader: (_) async => {
              'cards': [data]
            });
    addTearDown(feed.dispose);
    final canonical = message('entity', data);
    await feed.refresh();
    data = {...data, 'amount': 999};
    await feed.refresh();
    expect(
        jsonDecode(
            feed.formalRows([canonical]).single.customElem!.data!)['amount'],
        100);
  });
  test('optional client order ID may be absent from REST when order ID matches',
      () async {
    final canonical = message('entity', {
      ...payload('7', 'wallet_red_packet'),
      'clientOrderId': 'client-7',
    });
    final feed = WalletConversationCards(
        target: 'peer',
        group: false,
        reader: (_) async => {
              'cards': [
                {
                  ...payload('7', 'wallet_red_packet'),
                  'cardStateVersion': 2,
                  'status': 'received',
                }
              ]
            });
    addTearDown(feed.dispose);
    await feed.refresh();
    final projected = feed.formalRows([canonical]).single;
    expect(projected.msgID, canonical.msgID);
    expect(jsonDecode(projected.customElem!.data!)['status'], 'received');
  });
  test('REST family collision on the same order cannot create a second card',
      () async {
    final canonical = message('transfer-msg', {
      ...payload('7', 'wallet_transfer'),
      'clientOrderId': 'same-client-order'
    });
    final feed = WalletConversationCards(
        target: 'peer',
        group: false,
        reader: (_) async => {
              'cards': [
                {
                  ...payload('7', 'wallet_red_packet'),
                  'clientOrderId': 'same-client-order'
                }
              ]
            });
    addTearDown(feed.dispose);
    await feed.refresh();
    final projected = feed.formalRows([canonical]);
    expect(projected.single.msgID, canonical.msgID);
    expect(jsonDecode(projected.single.customElem!.data!)['customType'],
        'wallet_transfer');
    expect(feed.displayRows, isEmpty);
  });
  for (final field in [
    'orderId',
    'clientOrderId',
    'senderUserId',
    'conversationId'
  ]) {
    test('rejects identity conflict in $field even on first REST response',
        () async {
      final original = {
        ...payload('7', 'wallet_red_packet'),
        'clientOrderId': 'client7'
      };
      final canonical = message('entity', original);
      final feed = WalletConversationCards(
          target: 'peer',
          group: false,
          reader: (_) async => {
                'cards': [
                  {...original, field: 'wrong'}
                ]
              });
      addTearDown(feed.dispose);
      await feed.refresh();
      expect(feed.formalRows([canonical]).single.customElem!.data,
          canonical.customElem!.data);
    });
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
        '$platform 50 preview round trips retain real wallet widget business type',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final navigator = GlobalKey<NavigatorState>();
      final global = serviceLocator<TUIChatGlobalModel>();
      final chat = TIMUIKitChatController();
      final scroll = ScrollController();
      final red = message('red-msg', payload('7', 'wallet_red_packet'));
      final transfer = message('transfer-msg', payload('8', 'wallet_transfer'));
      var rest = payload('7', 'wallet_red_packet');
      final feed = WalletConversationCards(
          target: 'peer',
          group: false,
          reader: (_) async => {
                'cards': [rest]
              });
      addTearDown(feed.dispose);
      await tester.runAsync(feed.refresh);
      var rows = [red, transfer];
      late StateSetter rebuild;
      late BuildContext chatContext;
      final png = Uint8List.fromList(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS1sAAAAASUVORK5CYII='));
      await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<TUIChatGlobalModel>.value(value: global),
            ChangeNotifierProvider(create: (_) => DefaultThemeData()),
          ],
          child: MaterialApp(
              navigatorKey: navigator,
              home: StatefulBuilder(builder: (context, setState) {
                rebuild = setState;
                chatContext = context;
                return Scaffold(
                    body:
                        ListView(controller: scroll, reverse: true, children: [
                  Image.memory(png, height: 40),
                  for (final row in feed.formalRows(rows))
                    CustomMessageElem(
                        key: ValueKey(
                            CustomMessageElem.walletMessageWidgetKey(row)),
                        message: row,
                        isShowJump: false,
                        chatController: chat),
                  const SizedBox(height: 500),
                ]));
              }))));
      await tester.pump(const Duration(milliseconds: 100));
      for (var cycle = 0; cycle < 50; cycle++) {
        // Four schedules: immediate back, update while covered, scroll after pop,
        // and a row reorder before opening (not a real history prepend).
        if (cycle % 4 == 3) rebuild(() => rows = [transfer, red]);
        await tester.pump();
        global.saveScrollBeforeMediaPreview('peer');
        final preview = pushMediaPreview<void>(
            context: chatContext,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            restoreChatScrollConversationID: 'peer',
            child: Scaffold(body: Center(child: Image.memory(png))));
        await tester.pump();
        // Complete REST while the image route covers the chat. An illegal
        // newer family must not replace the physical IM row on resume.
        if (cycle % 4 == 1) {
          rest = {
            ...rest,
            'customType': 'wallet_group_transfer',
            'cardStateVersion': cycle + 2
          };
          await tester.runAsync(feed.refresh);
        }
        if (cycle % 4 == 1) {
          rebuild(() => rows = [
                message('red-msg', payload('7', 'wallet_red_packet')),
                transfer
              ]);
        }
        navigator.currentState!.pop();
        await tester.pump();
        await preview;
        await tester.pump(const Duration(milliseconds: 20));
        if (cycle % 4 == 2) {
          scroll.jumpTo(20);
          await tester.pump();
          scroll.jumpTo(0);
        }
        expect(find.byType(RedPacketCard), findsOneWidget,
            reason: 'cycle $cycle');
        expect(find.byType(TransferCard), findsOneWidget,
            reason: 'cycle $cycle');
        expect(jsonDecode(red.customElem!.data!)['customType'],
            'wallet_red_packet');
        expect(global.shouldLockChatScrollForMediaPreview, isFalse);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      scroll.dispose();
      debugDefaultTargetPlatformOverride = null;
      debugPrint(
          'CHAT_TRACE event=preview_cycles_complete platform=$platform cycles=50 canonicalType=wallet_red_packet widgetType=RedPacketCard');
    });
  }

  testWidgets('late packet metadata cannot write into a reused State',
      (tester) async {
    final dio = ApiClient.instance.dio;
    final saved = dio.interceptors.toList();
    final requests = <RequestOptions>[];
    final replies = <RequestInterceptorHandler>[];
    dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (r, h) {
        requests.add(r);
        replies.add(h);
      }));
    addTearDown(() {
      dio.interceptors
        ..clear()
        ..addAll(saved);
    });
    final chat = TIMUIKitChatController();
    final global = serviceLocator<TUIChatGlobalModel>();
    final a = payload('7', 'wallet_red_packet')..remove('packetType');
    final b = payload('8', 'wallet_red_packet');
    await tester.runAsync(() => RedPacketLocalStore.instance
        .markOpened(orderId: '8', ownerUserId: 'owner'));
    Widget tree(Map<String, dynamic> data) => MultiProvider(
            providers: [
              ChangeNotifierProvider<TUIChatGlobalModel>.value(value: global),
              ChangeNotifierProvider(create: (_) => DefaultThemeData()),
            ],
            child: MaterialApp(
                home: Scaffold(
                    body: CustomMessageElem(
                        key: const ValueKey('deliberately-reused-state'),
                        message: message('row', data),
                        isShowJump: false,
                        chatController: chat))));
    await tester.pumpWidget(tree(a));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(requests.any((r) => r.path.endsWith('/7')), isTrue);
    final oldState = tester.state(find.byType(CustomMessageElem));
    await tester.pumpWidget(tree(b));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.state(find.byType(CustomMessageElem)), same(oldState));
    final before =
        tester.widget<RedPacketCard>(find.byType(RedPacketCard)).typeLabel;
    for (var i = 0; i < replies.length; i++) {
      replies[i].resolve(
          Response(requestOptions: requests[i], statusCode: 200, data: {
        'data': {'id': '7', 'status': 'success', 'packetType': 'EXCLUSIVE'}
      }));
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<RedPacketCard>(find.byType(RedPacketCard)).typeLabel,
        before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
