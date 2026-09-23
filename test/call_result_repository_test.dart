import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_bubble_insert_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_result_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_result_repository.dart';
import 'package:tencent_cloud_chat_demo/src/services/local_message_overlay_store.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/calling_message/calling_message_data_provider.dart';

void main() {
  group('CallResultRepository', () {
    test('cleared chat does not rehydrate old call bubbles', () async {
      SharedPreferences.setMockInitialValues({});
      const conversationId = 'c2c_peer_cleared_call_bubbles';
      final clearedAt = DateTime.now().millisecondsSinceEpoch;
      CallResultRecord record(String callId, int endedAtMs) => CallResultRecord(
            callId: callId,
            conversationId: conversationId,
            callerUserId: 'self',
            operatorUserId: 'self',
            peerUserId: 'peer_cleared_call_bubbles',
            protocolType: CallProtocolType.hangup,
            durationSec: 5,
            endedAtMs: endedAtMs,
            isOutgoing: true,
          );

      final oldCall = record('cleared_call_old', clearedAt - 1000);
      CallResultRepository.instance.save(oldCall);
      expect(CallBubbleInsertService.instance.insertTerminalBubble(oldCall),
          isTrue);
      expect(LocalMessageOverlayStore.instance.messagesFor(conversationId),
          hasLength(1));

      await CallResultRepository.instance
          .removeByConversationId(conversationId);
      LocalMessageOverlayStore.instance.clearConversation(conversationId);
      // The recent-calls endpoint can return this same old call later.
      CallResultRepository.instance.save(oldCall);
      expect(CallBubbleInsertService.instance.insertTerminalBubble(oldCall),
          isFalse);
      CallBubbleInsertService.instance
          .ensureConversationBubbles(conversationId);
      expect(LocalMessageOverlayStore.instance.messagesFor(conversationId),
          isEmpty);
      expect(
          CallResultRepository.instance.recordsForConversation(conversationId),
          isEmpty);

      final newCall = record('cleared_call_new', clearedAt + 60000);
      CallResultRepository.instance.save(newCall);
      expect(CallBubbleInsertService.instance.insertTerminalBubble(newCall),
          isTrue);
      expect(LocalMessageOverlayStore.instance.messagesFor(conversationId),
          hasLength(1));
      LocalMessageOverlayStore.instance.clearConversation(conversationId);
    });

    test('save and get by callId', () {
      const callId = 'invite_test_001';
      CallResultRepository.instance.save(
        CallResultRecord.fromCallEnd(
          callId: callId,
          conversationId: 'c2c_peer_a',
          callerUserId: 'self_a',
          operatorUserId: 'self_a',
          peerUserId: 'peer_b',
          reasonName: 'reject',
          durationSec: 0,
          isOutgoing: false,
        ),
      );

      final record = CallResultRepository.instance.get(callId);
      expect(record, isNotNull);
      expect(record!.operatorUserId, 'self_a');
      expect(record.callerUserId, 'self_a');
      expect(record.protocolType, CallProtocolType.reject);
    });

    test('server source overrides device source', () {
      const callId = 'invite_priority_001';
      CallResultRepository.instance.save(
        CallResultRecord.fromCallEnd(
          callId: callId,
          conversationId: 'c2c_peer_x',
          callerUserId: 'self_x',
          operatorUserId: 'self_x',
          peerUserId: 'peer_x',
          reasonName: 'cancel',
          durationSec: 0,
        ),
      );
      CallResultRepository.instance.save(
        CallResultRecord.fromServer(
          callId: callId,
          conversationId: 'c2c_peer_x',
          callerUserId: 'self_x',
          operatorUserId: 'peer_x',
          peerUserId: 'peer_x',
          result: 'rejected',
          durationSec: 0,
          occurredAtMs: 1741231296000,
        ),
      );

      final record = CallResultRepository.instance.get(callId);
      expect(record!.source, CallResultSource.server);
      expect(record.protocolType, CallProtocolType.reject);
      expect(record.operatorUserId, 'peer_x');
    });

    test('device source does not override existing server source', () {
      const callId = 'invite_priority_002';
      CallResultRepository.instance.save(
        CallResultRecord.fromServer(
          callId: callId,
          conversationId: 'c2c_peer_y',
          callerUserId: 'self_y',
          operatorUserId: 'peer_y',
          peerUserId: 'peer_y',
          result: 'rejected',
          durationSec: 0,
          occurredAtMs: 1741231296000,
        ),
      );
      CallResultRepository.instance.save(
        CallResultRecord.fromCallEnd(
          callId: callId,
          conversationId: 'c2c_peer_y',
          callerUserId: 'self_y',
          operatorUserId: 'self_y',
          peerUserId: 'peer_y',
          reasonName: 'cancel',
          durationSec: 0,
        ),
      );

      final record = CallResultRepository.instance.get(callId);
      expect(record!.source, CallResultSource.server);
      expect(record.protocolType, CallProtocolType.reject);
      expect(record.operatorUserId, 'peer_y');
    });

    test('canceled is not rolled back by a late accept', () {
      const callId = 'call_terminal_cancel_then_accept';
      CallResultRepository.instance.save(
        CallResultRecord.fromSignaling(
          callId: callId,
          action: 'cancel',
          peerUserId: 'peer_terminal_a',
        ),
      );
      CallResultRepository.instance.save(
        CallResultRecord.fromSignaling(
          callId: callId,
          action: 'accept',
          peerUserId: 'peer_terminal_a',
        ),
      );

      expect(
        CallResultRepository.instance.get(callId)!.effectiveStatus,
        CallSessionStatus.canceled,
      );
    });

    test('latestForConversation matches c2c conversation id', () {
      const callId = 'invite_latest_alias';
      CallResultRepository.instance.save(
        CallResultRecord(
          callId: callId,
          conversationId: 'c2c_alias_peer',
          callerUserId: 'self_z',
          operatorUserId: 'self_z',
          peerUserId: 'alias_peer',
          protocolType: CallProtocolType.cancel,
          durationSec: 0,
          endedAtMs: 1741231296000,
          isOutgoing: true,
        ),
      );
      expect(
        CallResultRepository.instance
            .latestForConversation('c2c_alias_peer')
            ?.callId,
        callId,
      );
    });

    test('ended is not rolled back by a late invite', () {
      const callId = 'call_terminal_end_then_invite';
      CallResultRepository.instance.save(
        CallResultRecord.fromSignaling(
          callId: callId,
          action: 'hangup',
          peerUserId: 'peer_terminal_b',
        ),
      );
      CallResultRepository.instance.save(
        CallResultRecord.fromSignaling(
          callId: callId,
          action: 'invite',
          peerUserId: 'peer_terminal_b',
        ),
      );

      expect(
        CallResultRepository.instance.get(callId)!.effectiveStatus,
        CallSessionStatus.ended,
      );
    });
  });

  group('CallResultRecord.protocolTypeFromServerResult', () {
    test('maps server results to protocol types', () {
      expect(CallResultRecord.protocolTypeFromServerResult('answered'),
          CallProtocolType.hangup);
      expect(CallResultRecord.protocolTypeFromServerResult('rejected'),
          CallProtocolType.reject);
      expect(CallResultRecord.protocolTypeFromServerResult('canceled'),
          CallProtocolType.cancel);
      expect(CallResultRecord.protocolTypeFromServerResult('busy'),
          CallProtocolType.lineBusy);
      expect(CallResultRecord.protocolTypeFromServerResult('missed'),
          CallProtocolType.timeout);
      expect(CallResultRecord.protocolTypeFromServerResult('failed'),
          CallProtocolType.timeout);
      expect(CallResultRecord.protocolTypeFromServerResult('weird'),
          CallProtocolType.unknown);
    });
  });
}
