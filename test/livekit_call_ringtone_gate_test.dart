import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/livekit_call_ringtone.dart';
import 'package:tencent_cloud_chat_demo/src/services/livekit_call_types.dart';

void main() {
  group('shouldPlayRingtone', () {
    test('ringingOut keeps ringback after joining the room before answer', () {
      expect(
        shouldPlayRingtone(
          phase: LiveKitCallPhase.ringingOut,
          hasRoom: false,
        ),
        isTrue,
      );
      expect(
        shouldPlayRingtone(
          phase: LiveKitCallPhase.ringingOut,
          hasRoom: true,
        ),
        isTrue,
      );
    });

    test('incoming mute preference does not mute outgoing ringback', () {
      for (final hasRoom in [false, true]) {
        expect(
          shouldPlayRingtone(
            phase: LiveKitCallPhase.ringingOut,
            hasRoom: hasRoom,
            allowsIncomingRingtone: false,
          ),
          isTrue,
        );
      }
      expect(
        shouldPlayRingtone(
          phase: LiveKitCallPhase.ringingIn,
          hasRoom: false,
          allowsIncomingRingtone: false,
        ),
        isFalse,
      );
    });

    test('ringingIn plays only without room', () {
      expect(
        shouldPlayRingtone(
          phase: LiveKitCallPhase.ringingIn,
          hasRoom: false,
        ),
        isTrue,
      );
      expect(
        shouldPlayRingtone(
          phase: LiveKitCallPhase.ringingIn,
          hasRoom: true,
        ),
        isFalse,
      );
    });

    test('outgoing connecting keeps ringback until connected', () {
      for (final hasRoom in [false, true]) {
        expect(
          shouldPlayRingtone(
            phase: LiveKitCallPhase.connecting,
            hasRoom: hasRoom,
            isOutgoing: true,
          ),
          isTrue,
        );
      }
    });

    test('incoming connecting and finished phases never play', () {
      for (final phase in [
        LiveKitCallPhase.connecting,
        LiveKitCallPhase.connected,
        LiveKitCallPhase.ended,
        LiveKitCallPhase.idle,
      ]) {
        expect(
          shouldPlayRingtone(phase: phase, hasRoom: false),
          isFalse,
          reason: '$phase hasRoom=false',
        );
        expect(
          shouldPlayRingtone(phase: phase, hasRoom: true),
          isFalse,
          reason: '$phase hasRoom=true',
        );
      }
    });

    test('outgoing acceptance and end stop ringback even with a room', () {
      for (final phase in [
        LiveKitCallPhase.connected,
        LiveKitCallPhase.ended,
        LiveKitCallPhase.idle,
      ]) {
        expect(
          shouldPlayRingtone(
            phase: phase,
            hasRoom: true,
            isOutgoing: true,
          ),
          isFalse,
        );
      }
    });
  });
}
