import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_conversation_cards.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/utils/chat_message_overlay_projection.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

Map<String, dynamic> packet(String id, int time, {bool group = false}) => {
      'cardId': 'rp:$id',
      'orderId': id,
      'customType': 'wallet_red_packet',
      'senderUserId': 'owner',
      'conversationId': group ? '@TGS#room' : 'peer',
      'isGroup': group,
      'paymentState': 'COMMITTED',
      'cardStateVersion': 1,
      'timestamp': time,
      'status': 'success',
    };

V2TimMessage sdk(int time, {bool group = false, Map<String, dynamic>? card}) =>
    V2TimMessage.fromJson({'message_risk_type_identified': 0})
      ..msgID = 'sdk-$time'
      ..id = 'sdk-$time'
      ..seq = '$time'
      ..timestamp = time
      ..sender = 'owner'
      ..userID = group ? '' : 'peer'
      ..groupID = group ? '@TGS#room' : ''
      ..isSelf = true
      ..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC
      ..elemType = card == null ? 1 : 2
      ..customElem =
          card == null ? null : V2TimCustomElem(data: jsonEncode(card));

// The same two-stage projection used by chat.dart, inspected at every arrival.
List<V2TimMessage> project(
    WalletConversationCards feed, List<V2TimMessage> rows,
    {bool exhausted = false, bool latest = true, int clearEpoch = 0}) {
  final formal = feed.formalRows(rows, clearEpoch: clearEpoch);
  return projectChatMessageOverlays(
    formalMessages: formal,
    overlays: feed.displayRows,
    olderHistoryExhausted: exhausted,
    includesLatestEdge: latest,
  ).where((row) => row.elemType != 11).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.instance.saveToken('projection-test', userId: 'owner');
  });
  tearDown(() => ApiClient.instance.clearToken());

  for (final group in [false, true]) {
    final label = group ? 'group' : 'C2C';
    WalletConversationCards feedWith(WalletCardPageReader read) =>
        WalletConversationCards(
            target: group ? '@TGS#room' : 'peer', group: group, reader: read);

    test(
        '$label REST first never publishes old cards into an unresolved window',
        () async {
      final reply = Completer<Map<String, dynamic>>();
      final feed = feedWith((_) => reply.future);
      addTearDown(feed.dispose);
      final loading = feed.refresh();
      final frames = <List<String?>>[];
      var window = <V2TimMessage>[];
      void publish() =>
          frames.add(project(feed, window).map((m) => m.msgID).toList());
      feed.addListener(publish);
      publish();
      reply.complete({
        'cards': [
          packet('old', 100, group: group),
          packet('current', 550, group: group)
        ]
      });
      await loading;
      expect(frames, [isEmpty, isEmpty],
          reason:
              'REST completion before SDK must not flash a wallet-only history');
      window = [sdk(600, group: group), sdk(500, group: group)];
      publish();
      expect(
          frames.last, ['sdk-600', 'local_wallet_card:rp:current', 'sdk-500']);
      expect(window.map((m) => m.msgID), ['sdk-600', 'sdk-500']);
      // Pagination reaches the old packet; it remains available in business cache.
      expect(
          project(feed, [...window, sdk(50, group: group)]).map((m) => m.msgID),
          [
            'sdk-600',
            'local_wallet_card:rp:current',
            'sdk-500',
            'local_wallet_card:rp:old',
            'sdk-50'
          ]);
    });

    test('$label SDK first and repeated status refresh keep identity and order',
        () async {
      var data = packet('current', 550, group: group);
      final feed = feedWith((_) async => {
            'cards': [data, packet('old', 100, group: group)]
          });
      addTearDown(feed.dispose);
      final window = [sdk(600, group: group), sdk(500, group: group)];
      expect(project(feed, window).map((m) => m.msgID), ['sdk-600', 'sdk-500']);
      await feed.refresh();
      final before =
          project(feed, window).map((m) => (m.msgID, m.timestamp)).toList();
      data = {
        ...data,
        'cardStateVersion': 2,
        'status': 'received',
        'updatedAt': '2030-01-01T00:00:00Z'
      };
      await feed.refresh();
      expect(project(feed, window).map((m) => (m.msgID, m.timestamp)), before);
      final physical =
          sdk(555, group: group, card: packet('current', 550, group: group));
      final rows = project(feed, [window.first, physical, window.last]);
      expect(rows.map((m) => m.msgID), ['sdk-600', 'sdk-555', 'sdk-500']);
      expect(rows[1].timestamp, 555);
      expect(rows[1].seq, '555');
      expect(jsonDecode(rows[1].customElem!.data!)['status'], 'received');
    });

    test(
        '$label confirmed empty chat retains wallet-only history, search gap does not',
        () async {
      final feed = feedWith((_) async => {
            'cards': [packet('old', 100, group: group)]
          });
      addTearDown(feed.dispose);
      await feed.refresh();
      expect(project(feed, [], latest: false), isEmpty);
      expect(project(feed, [], exhausted: true, latest: false), isEmpty);
      expect(project(feed, [], exhausted: true).single.msgID,
          'local_wallet_card:rp:old');
      expect(
          project(feed, [sdk(600, group: group), sdk(500, group: group)],
              latest: false),
          hasLength(2));
    });

    test('$label clear followed by delayed REST does not recreate old cards',
        () async {
      final reply = Completer<Map<String, dynamic>>();
      final feed = feedWith((_) => reply.future);
      addTearDown(feed.dispose);
      final request = feed.refresh();
      project(feed, [], clearEpoch: 200000);
      reply.complete({
        'cards': [packet('old', 100, group: group)]
      });
      await request;
      expect(project(feed, [], exhausted: true), isEmpty);
    });

    for (final self in [true, false]) {
      test(
          '$label revoked ${self ? 'self' : 'peer'} IM row remains revoked after REST',
          () async {
        final data = {
          ...packet('revoked', 100, group: group),
          if (!self) 'senderUserId': 'peer',
          if (!self && !group) 'conversationId': 'owner',
        };
        final feed = feedWith((_) async => {
              'cards': [data]
            });
        addTearDown(feed.dispose);
        final revoked = sdk(100, group: group, card: data)
          ..sender = self ? 'owner' : 'peer'
          ..isSelf = self
          ..status = MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED;
        expect(project(feed, [revoked]).single, same(revoked));
        await feed.refresh();
        final rows = project(feed, [revoked]);
        expect(rows.single, same(revoked));
        expect(
            rows.single.status, MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED);
        expect(feed.displayRows, isEmpty);
        // Once observed, a tombstone must survive this page leaving the window.
        expect(project(feed, [], exhausted: true), isEmpty);
      });
    }

    test(
        '$label SDK tombstone arriving before REST survives window replacement',
        () async {
      final data = packet('revoked-early', 100, group: group);
      final feed = feedWith((_) async => {
            'cards': [data]
          });
      addTearDown(feed.dispose);
      final revoked = sdk(100, group: group, card: data)
        ..status = MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED;
      expect(project(feed, [revoked]).single, same(revoked));
      await feed.refresh();
      expect(project(feed, [], exhausted: true), isEmpty);
      final staleReceipt = sdk(101, group: group, card: data);
      final result = project(feed, [staleReceipt, revoked]);
      expect(result, [same(revoked)]);
      expect(staleReceipt.status, MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
          reason: 'projection must not mutate the original SDK receipt');
    });

    test('$label reopening with warm REST still waits for its own SDK window',
        () async {
      final data = packet('old', 100, group: group);
      for (var visit = 0; visit < 3; visit++) {
        final feed = feedWith((_) async => {
              'cards': [data]
            });
        try {
          await feed.refresh();
          expect(project(feed, []), isEmpty);
          final window = [sdk(600, group: group), sdk(500, group: group)];
          final before =
              project(feed, window).map((m) => (m.msgID, m.timestamp)).toList();
          await feed.refresh();
          expect(
              project(feed, window).map((m) => (m.msgID, m.timestamp)), before);
        } finally {
          feed.dispose();
        }
      }
    });

    test(
        '$label late reply after route disposal cannot contaminate a new route',
        () async {
      final reply = Completer<Map<String, dynamic>>();
      final old = feedWith((_) => reply.future);
      final pending = old.refresh();
      old.dispose();
      final next = feedWith((_) async => {'cards': []});
      addTearDown(next.dispose);
      reply.complete({
        'cards': [packet('old', 100, group: group)]
      });
      await pending;
      expect(project(next, [], exhausted: true), isEmpty);
      expect(old.displayRows, isEmpty);
    });
  }

  test(
      'account switch rejects a late REST reply even with confirmed empty history',
      () async {
    final reply = Completer<Map<String, dynamic>>();
    final feed = WalletConversationCards(
        target: 'peer', group: false, reader: (_) => reply.future);
    addTearDown(feed.dispose);
    final pending = feed.refresh();
    SessionIdentityService.instance
        .invalidate(reason: 'wallet-projection-test');
    reply.complete({
      'cards': [packet('old', 100)]
    });
    await pending;
    expect(project(feed, [], exhausted: true), isEmpty);
  });
}
