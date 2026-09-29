import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_bubble_insert_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_result_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_result_repository.dart';
import 'package:tencent_cloud_chat_demo/src/services/local_message_overlay_store.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/calling_message/calling_message_data_provider.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

V2TimMessage _inviteOnly(String callId) {
  final payload = jsonEncode(<String, dynamic>{
    'businessID': 'lk_call',
    'action': 'invite',
    'callId': callId,
  });
  final message = V2TimMessage.fromJson(<String, dynamic>{
    'message_server_time': 100,
    'message_is_from_self': true,
    'message_status': 2,
    'message_custom_str': payload,
    'message_risk_type_identified': 0,
    'message_sender_group_member_info': <String, dynamic>{},
    'message_group_at_user_array': <String>[],
  });
  message.elemType = MessageElemType.V2TIM_ELEM_TYPE_CUSTOM;
  message.customElem = V2TimCustomElem(data: payload);
  message.timestamp = 100;
  message.msgID = 'invite_$callId';
  return message;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  group('CallBubbleInsertService.buildTerminalBubbleMessage', () {
    test('rehydrated call payload survives SDK JSON and overlay copies', () {
      final record = CallResultRecord(
        callId: 'call_clone_roundtrip',
        conversationId: 'c2c_peer_a',
        callerUserId: 'peer_a',
        operatorUserId: 'peer_a',
        peerUserId: 'peer_a',
        protocolType: CallProtocolType.hangup,
        durationSec: 42,
        endedAtMs: 1784077700000,
        isOutgoing: false,
        mediaType: 'video',
      );
      final original =
          CallBubbleInsertService.buildTerminalBubbleMessage(record)!;
      final restored = V2TimMessage.fromJson(original.toJson());
      expect(restored.customElem?.data, original.customElem!.data);
      expect(restored.localCustomData, original.localCustomData);
      expect(restored.msgID, original.msgID);
      final store = LocalMessageOverlayStore.instance;
      store.resetForTesting();
      addTearDown(store.resetForTesting);
      expect(store.upsert(record.conversationId, restored), isTrue);
      final displayed = store.messagesFor(record.conversationId).single;
      expect(displayed, isNot(same(restored)));
      expect(displayed.customElem, isNot(same(restored.customElem)));
      final payload = jsonDecode(displayed.customElem!.data!) as Map;
      expect(payload['businessID'], 'lk_call');
      expect(payload['action'], 'hangup');
      expect(payload['duration'], 42);
      expect(payload['mediaType'], 'video');
      final provider = CallingMessageDataProvider(displayed);
      expect(provider.isCallingSignal, isTrue);
      expect(provider.shouldDisplayInHistory, isTrue);
      expect(provider.protocolType, CallProtocolType.hangup);
      expect(provider.content, contains('42'));
      // A view's copy must not erase the stored payload or force another
      // upsert of the same recovered call on every rebuild.
      displayed.customElem!.data = '';
      expect(store.messagesFor(record.conversationId).single.customElem!.data,
          original.customElem!.data);
      expect(store.upsert(record.conversationId, restored), isFalse);
    });

    test('hangup bubble is history-visible with duration', () {
      final record = CallResultRecord(
        callId: 'call_insert_1',
        conversationId: 'c2c_peer_a',
        callerUserId: 'self_a',
        operatorUserId: 'self_a',
        peerUserId: 'peer_a',
        protocolType: CallProtocolType.hangup,
        durationSec: 42,
        endedAtMs: 1784077700000,
        isOutgoing: true,
        mediaType: 'video',
      );
      final message =
          CallBubbleInsertService.buildTerminalBubbleMessage(record);
      expect(message, isNotNull);
      final provider = CallingMessageDataProvider(message!);
      expect(provider.shouldDisplayInHistory, isTrue);
      expect(provider.protocolType, CallProtocolType.hangup);
      expect(provider.content, contains('42'));
      expect(message.localCustomData, contains('localCallBubble'));
    });

    test('c2c bubble userID is the peer, never self', () {
      final record = CallResultRecord(
        callId: 'call_peer_user',
        conversationId: 'c2c_peer_a',
        callerUserId: 'self_a',
        operatorUserId: 'self_a',
        peerUserId: 'peer_a',
        protocolType: CallProtocolType.cancel,
        durationSec: 0,
        endedAtMs: 1784077700000,
        isOutgoing: true,
      );
      final message =
          CallBubbleInsertService.buildTerminalBubbleMessage(record)!;
      expect(message.userID, 'peer_a');
      expect(message.groupID, isNull);
    });

    test('group bubble sets groupID from conversationId', () {
      final record = CallResultRecord(
        callId: 'call_group_user',
        conversationId: 'group_room1',
        callerUserId: 'self_a',
        operatorUserId: 'self_a',
        peerUserId: 'peer_a',
        protocolType: CallProtocolType.cancel,
        durationSec: 0,
        endedAtMs: 1784077700000,
        isOutgoing: true,
      );
      final message =
          CallBubbleInsertService.buildTerminalBubbleMessage(record)!;
      expect(message.groupID, 'room1');
    });
  });

  group('CallBubbleInsertService.hasTerminalBubbleForCallId', () {
    test('invite-only mid-state does not block insert', () {
      expect(
        CallBubbleInsertService.hasTerminalBubbleForCallId(
          <V2TimMessage>[_inviteOnly('call_x')],
          callId: 'call_x',
        ),
        isFalse,
      );
    });

    test('local marker counts as terminal bubble', () {
      final record = CallResultRecord(
        callId: 'call_y',
        conversationId: 'c2c_peer_a',
        callerUserId: 'self_a',
        operatorUserId: 'self_a',
        peerUserId: 'peer_a',
        protocolType: CallProtocolType.hangup,
        durationSec: 3,
        endedAtMs: 1784077700000,
        isOutgoing: true,
      );
      final bubble =
          CallBubbleInsertService.buildTerminalBubbleMessage(record)!;
      expect(
        CallBubbleInsertService.hasTerminalBubbleForCallId(
          <V2TimMessage>[bubble],
          callId: 'call_y',
        ),
        isTrue,
      );
    });
  });

  group('CallBubbleInsertService mid-call records stay off history', () {
    CallResultRecord ringingRecord(String callId) => CallResultRecord(
          callId: callId,
          conversationId: 'c2c_peer_ringing',
          callerUserId: 'self_a',
          operatorUserId: 'self_a',
          peerUserId: 'peer_ringing',
          protocolType: CallProtocolType.send,
          durationSec: 0,
          endedAtMs: 0,
          isOutgoing: true,
          status: CallSessionStatus.ringing,
        );

    CallResultRecord hangupRecord(String callId) => CallResultRecord(
          callId: callId,
          conversationId: 'c2c_peer_ringing',
          callerUserId: 'self_a',
          operatorUserId: 'self_a',
          peerUserId: 'peer_ringing',
          protocolType: CallProtocolType.hangup,
          durationSec: 12,
          endedAtMs: 1784077700000,
          isOutgoing: true,
        );

    test('upsertLifecycleBubble ignores RINGING', () {
      final store = LocalMessageOverlayStore.instance;
      store.resetForTesting();
      addTearDown(store.resetForTesting);
      final record = ringingRecord('call_ring_upsert');
      expect(
        CallBubbleInsertService.instance.upsertLifecycleBubble(
          record,
          reason: 'test_ringing',
        ),
        isFalse,
      );
      expect(store.messagesFor(record.conversationId), isEmpty);
    });

    test('insertTerminalBubble ignores RINGING and keeps hangup', () {
      final store = LocalMessageOverlayStore.instance;
      store.resetForTesting();
      addTearDown(store.resetForTesting);
      final ringing = ringingRecord('call_ring_insert');
      expect(
        CallBubbleInsertService.instance.insertTerminalBubble(ringing),
        isFalse,
      );
      expect(store.messagesFor(ringing.conversationId), isEmpty);
      final hangup = hangupRecord('call_hang_insert');
      expect(
        CallBubbleInsertService.instance.insertTerminalBubble(hangup),
        isTrue,
      );
      expect(store.messagesFor(hangup.conversationId), hasLength(1));
    });

    test('ensureConversationBubbles projects only terminal records', () {
      final store = LocalMessageOverlayStore.instance;
      store.resetForTesting();
      addTearDown(store.resetForTesting);
      const convId = 'c2c_peer_ringing_rehydrate';
      CallResultRepository.instance.save(
        CallResultRecord(
          callId: 'call_rehydrate_ring',
          conversationId: convId,
          callerUserId: 'self_a',
          operatorUserId: 'self_a',
          peerUserId: 'peer_ringing_rehydrate',
          protocolType: CallProtocolType.send,
          durationSec: 0,
          endedAtMs: 0,
          isOutgoing: true,
          status: CallSessionStatus.ringing,
        ),
      );
      CallResultRepository.instance.save(
        CallResultRecord(
          callId: 'call_rehydrate_hang',
          conversationId: convId,
          callerUserId: 'self_a',
          operatorUserId: 'self_a',
          peerUserId: 'peer_ringing_rehydrate',
          protocolType: CallProtocolType.hangup,
          durationSec: 8,
          endedAtMs: 1784077800000,
          isOutgoing: true,
        ),
      );
      CallBubbleInsertService.instance.ensureConversationBubbles(convId);
      final displayed = store.messagesFor(convId);
      expect(displayed, hasLength(1));
      expect(displayed.single.msgID, 'local_call_bubble_call_rehydrate_hang');
    });
  });
}
