import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_bubble_insert_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_result_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_result_repository.dart';
import 'package:tencent_cloud_chat_demo/src/services/local_message_overlay_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/calling_message/calling_message_data_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final service = CallBubbleInsertService.instance;
  final overlays = LocalMessageOverlayStore.instance;
  setUp(overlays.resetForTesting);
  tearDown(overlays.resetForTesting);

  CallResultRecord observation(String id, String action) =>
      CallResultRecord.fromSignaling(
        callId: id,
        action: action,
        conversationId: 'c2c_peer',
        callerUserId: 'self',
        calleeUserId: 'peer',
        peerUserId: 'peer',
        isOutgoing: true,
        occurredAtMs: 1784077600000,
      );

  test('one publication after ringing, accepted, ended and duplicate signals',
      () {
    var publications = 0;
    void onChange() {
      publications++;
    }

    overlays.addListener(onChange);
    addTearDown(() => overlays.removeListener(onChange));
    const id = 'central-lifecycle';
    expect(service.accept(observation(id, 'invite')), isFalse);
    expect(service.accept(observation(id, 'accept')), isFalse);
    expect(overlays.messagesFor('c2c_peer'), isEmpty);
    expect(publications, 0);
    final ended = observation(id, 'hangup');
    expect(service.accept(ended), isTrue);
    expect(service.accept(ended), isFalse);
    expect(service.accept(observation(id, 'invite')), isFalse);
    expect(overlays.messagesFor('c2c_peer'), hasLength(1));
    expect(publications, 1);
    expect(
        CallingMessageDataProvider(overlays.messagesFor('c2c_peer').single)
            .shouldDisplayInHistory,
        isTrue);
  });

  test('account generation change rejects a delayed result before publication',
      () {
    final identity = SessionIdentityService.instance.capture();
    SessionIdentityService.instance.invalidate(reason: 'test');
    expect(
        service.accept(observation('stale-call', 'hangup'), identity: identity),
        isFalse);
    expect(CallResultRepository.instance.get('stale-call'), isNull);
    expect(overlays.messagesFor('c2c_peer'), isEmpty);
  });

  test('server enrichment updates one stable bubble, including zero duration',
      () {
    const id = 'central-server';
    service.accept(observation(id, 'hangup'));
    final first = overlays.messagesFor('c2c_peer').single;
    expect(CallingMessageDataProvider(first).shouldDisplayInHistory, isTrue);
    service.accept(CallResultRecord.fromServer(
      callId: id,
      conversationId: 'c2c_peer',
      callerUserId: 'self',
      operatorUserId: 'peer',
      peerUserId: 'peer',
      result: 'answered',
      durationSec: 25,
      occurredAtMs: 1784077625000,
      status: CallSessionStatus.ended,
      isOutgoing: true,
    ));
    final rows = overlays.messagesFor('c2c_peer');
    expect(rows, hasLength(1));
    expect(rows.single.msgID, first.msgID);
    expect(CallingMessageDataProvider(rows.single).hangupDurationSec, 25);
  });
}
