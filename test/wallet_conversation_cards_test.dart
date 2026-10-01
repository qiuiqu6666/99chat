import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_latest_window_trust.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_conversation_cards.dart';

Map<String, dynamic> card(String id) => {
      'cardId': 'transfer:$id',
      'orderId': id,
      'customType': 'wallet_transfer',
      'senderUserId': 'owner',
      'conversationId': 'peer',
      'isGroup': false,
      'paymentState': 'COMMITTED',
      'cardDeliveryState': 'RECONCILING',
      'timestamp': 100,
      'amount': 100,
      'status': 'success',
    };
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.instance.saveToken('test-token', userId: 'owner');
  });
  tearDown(() async => ApiClient.instance.clearToken());

  test(
      'actual REST reader unwraps envelopes and never calls a payment endpoint',
      () async {
    final dio = ApiClient.instance.dio;
    final saved = dio.interceptors.toList();
    dio.interceptors.clear();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (req, handler) {
      expect(req.method, 'GET');
      expect(req.path, '/wallet/card-orders/conversation');
      handler.resolve(Response(requestOptions: req, statusCode: 200, data: {
        'data': {
          'cards': [card('1')]
        }
      }));
    }));
    final feed = WalletConversationCards(target: 'peer', group: false);
    try {
      await feed.refresh();
      expect(feed.displayRows.length, 1);
    } finally {
      feed.dispose();
      dio.interceptors
        ..clear()
        ..addAll(saved);
    }
  });

  test('business pagination loads missing cards without duplication', () async {
    final feed = WalletConversationCards(
        target: 'peer',
        group: false,
        reader: (query) async {
          if (query['before'] == null)
            return {
              'cards': [card('2')],
              'nextBefore': '2026-09-28T00:00:00Z',
              'nextBeforeId': 'transfer:2'
            };
          expect(query['beforeId'], 'transfer:2');
          return {
            'cards': [card('1')]
          };
        });
    addTearDown(feed.dispose);
    await feed.refresh();
    await feed.refresh();
    expect(feed.displayRows.map((m) => m.msgID).toSet(),
        {'local_wallet_card:transfer:1', 'local_wallet_card:transfer:2'});
  });

  test('cleared history cannot be restored by a later business-card refresh',
      () async {
    final feed = WalletConversationCards(
        target: 'peer',
        group: false,
        reader: (_) async => {
              'cards': [
                card('1'),
                {...card('2'), 'timestamp': 201}
              ]
            });
    addTearDown(feed.dispose);
    await feed.refresh();
    feed.formalRows([], clearEpoch: 200000);
    expect(feed.displayRows.single.msgID, 'local_wallet_card:transfer:2');
    await feed.refresh();
    expect(feed.displayRows.single.msgID, 'local_wallet_card:transfer:2');
  });

  test('older claim revisions cannot replace the current card state', () async {
    var version = 2;
    final feed = WalletConversationCards(
        target: 'peer',
        group: false,
        reader: (_) async => {
              'cards': [
                {...card('1'), 'cardStateVersion': version}
              ]
            });
    addTearDown(feed.dispose);
    await feed.refresh();
    version = 1;
    await feed.refresh();
    expect(
        jsonDecode(
            feed.displayRows.single.customElem!.data!)['cardStateVersion'],
        2);
  });

  test('no IM message is required to render the committed card', () async {
    final feed = WalletConversationCards(
        target: 'peer',
        group: false,
        reader: (_) async => {
              'cards': [card('1')]
            });
    addTearDown(feed.dispose);
    await feed.refresh();
    expect(feed.formalRows([]), isEmpty);
    expect(feed.displayRows.single.msgID, 'local_wallet_card:transfer:1');
    expect(
        jsonDecode(feed.displayRows.single.customElem!.data!)['amount'], 100);
    expect(feed.displayRows.single.isSelf, isTrue);
    expect(isConfirmedServerRow(feed.displayRows.single), isFalse);
  });
  test('late and duplicate IM receipts project to one stable business card',
      () async {
    final feed = WalletConversationCards(
        target: 'peer',
        group: false,
        reader: (_) async => {
              'cards': [card('1')]
            });
    addTearDown(feed.dispose);
    await feed.refresh();
    V2TimMessage transport(String id) =>
        V2TimMessage.fromJson({'message_risk_type_identified': 0})
          ..msgID = id
          ..sender = 'owner'
          ..userID = 'peer'
          ..elemType = 2
          ..seq = id == 'a' ? '10' : '11'
          ..timestamp = 101
          ..customElem = V2TimCustomElem(data: jsonEncode(card('1')));
    final physical = [transport('a'), transport('b')];
    final projected = feed.formalRows(physical);
    expect(projected.single.msgID, 'b');
    expect(projected.single.seq, '11');
    expect(isConfirmedServerRow(projected.single), isTrue);
    expect(feed.displayRows, isEmpty);
    expect(physical.map((m) => m.msgID), ['a', 'b']);
    expect(physical.map((m) => m.seq), ['10', '11']);
  });
  test(
      'late responses after account invalidation cannot populate the new account',
      () async {
    final reply = Completer<Map<String, dynamic>>();
    final feed = WalletConversationCards(
        target: 'peer', group: false, reader: (_) => reply.future);
    addTearDown(feed.dispose);
    final request = feed.refresh();
    SessionIdentityService.instance.invalidate(reason: 'test');
    reply.complete({
      'cards': [card('1')]
    });
    await request;
    expect(feed.displayRows, isEmpty);
  });
  test(
      'wrong-conversation data and failed refresh cannot invent or erase cards',
      () async {
    var fail = false;
    final feed = WalletConversationCards(
        target: 'peer',
        group: false,
        reader: (_) async {
          if (fail) throw Exception('offline');
          return {
            'cards': [
              card('1'),
              {...card('2'), 'conversationId': 'another'}
            ]
          };
        });
    addTearDown(feed.dispose);
    await feed.refresh();
    expect(feed.displayRows.length, 1);
    fail = true;
    await feed.refresh();
    expect(feed.displayRows.length, 1);
  });
}
