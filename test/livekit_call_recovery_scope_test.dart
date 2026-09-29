import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/livekit_call_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/livekit_call_credentials.dart';
import 'package:tencent_cloud_chat_demo/src/services/livekit_call_session.dart';
import 'package:tencent_cloud_chat_demo/src/services/livekit_call_types.dart';

class _Api extends Fake implements LiveKitCallApi {
  final pending = <Completer<LiveKitCallCredentials>>[];
  @override
  Future<LiveKitCallCredentials> fetchToken({required String callId}) {
    final gate = Completer<LiveKitCallCredentials>();
    pending.add(gate);
    return gate.future;
  }
}

class _Room extends Fake implements Room {
  int disconnects = 0;
  Completer<void>? disconnectGate;
  @override
  Future<void> disconnect() async {
    disconnects++;
    await disconnectGate?.future;
  }
}

LiveKitCallCredentials _creds(String id) => LiveKitCallCredentials(
    callId: id,
    roomName: id,
    url: 'wss://example.invalid',
    token: 'synthetic',
    mediaType: 'audio',
    callerUserId: '10001',
    calleeUserId: '10002');

Future<void> _turn() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('connecting phase still expires at the original ring deadline', () {
    final deadline = DateTime.utc(2026, 1, 1, 0, 0, 0);
    expect(
      shouldReconcileStaleRinging(
        phase: LiveKitCallPhase.connecting,
        ringDeadline: deadline,
        now: deadline,
      ),
      isTrue,
    );
    expect(
      shouldReconcileStaleRinging(
        phase: LiveKitCallPhase.connecting,
        ringDeadline: deadline,
        now: deadline.subtract(const Duration(seconds: 1)),
      ),
      isFalse,
    );
  });

  test(
      'connect wait times out but cleans media if native connect completes late',
      () async {
    final physicalConnect = Completer<void>();
    var current = true;
    var lateCleanupCalls = 0;
    final wait = awaitLiveKitRoomConnect(
      connect: () => physicalConnect.future,
      timeout: const Duration(milliseconds: 10),
      isCurrent: () => current,
      onLateSuccess: () => lateCleanupCalls++,
    );

    final timeoutResult = await wait.then<Object?>(
      (_) => null,
      onError: (Object error, StackTrace _) => error,
    );
    expect(timeoutResult.toString(), contains('TimeoutException'));
    current = false;
    physicalConnect.complete();
    await _turn();
    expect(lateCleanupCalls, 1);
  });

  for (final recovering in [false, true]) {
    for (final fails in [false, true]) {
      test(
          'old ${recovering ? 'recovery' : 'refresh'} ${fails ? 'failure' : 'success'} cannot modify new call',
          () async {
        final api = _Api();
        final session = LiveKitCallSession.forTesting(api: api);
        final oldRoom = _Room();
        final newRoom = _Room();
        final newCreds = _creds('B');
        session.debugAdoptConnected(oldRoom, _creds('A'));
        final old = session.debugRefreshCredentials(recovering: recovering);
        await _turn();
        session.debugAdoptConnected(newRoom, newCreds);
        if (fails) {
          api.pending.single.completeError(StateError('old failure'));
        } else {
          api.pending.single.complete(_creds('A'));
        }
        await old;
        expect(session.credentials, same(newCreds));
        expect(session.room, same(newRoom));
        expect(session.phase, LiveKitCallPhase.connected);
        expect(oldRoom.disconnects, 0);
        expect(newRoom.disconnects, 0);
        session.dispose();
      });
    }
  }

  test(
      'same-call refresh joins one flight and old finally cannot clear new flight',
      () async {
    final api = _Api();
    final session = LiveKitCallSession.forTesting(api: api);
    session.debugAdoptConnected(_Room(), _creds('A'));
    final a = session.debugRefreshCredentials();
    expect(session.debugRefreshCredentials(), same(a));
    await _turn();
    session.debugAdoptConnected(_Room(), _creds('B'));
    final b = session.debugRefreshCredentials();
    await _turn();
    api.pending[0].complete(_creds('A'));
    await a;
    expect(session.debugRefreshCredentials(), same(b));
    expect(api.pending, hasLength(2));
    api.pending[1].completeError(StateError('transient failure'));
    await b;
    final retry = session.debugRefreshCredentials();
    await _turn();
    expect(api.pending, hasLength(3));
    session.debugAdoptConnected(_Room(), _creds('C'));
    api.pending[2].complete(_creds('B'));
    await retry;
    session.dispose();
  });

  test('token timeout releases flight and its late result stays ignored',
      () async {
    final api = _Api();
    final session = LiveKitCallSession.forTesting(
        api: api, tokenRequestTimeout: const Duration(milliseconds: 30));
    final initial = _creds('A');
    final room = _Room();
    session.debugAdoptConnected(room, initial);
    await session.debugRefreshCredentials();
    final retry = session.debugRefreshCredentials();
    await _turn();
    expect(api.pending, hasLength(2));
    api.pending[0].complete(_creds('A'));
    await _turn();
    expect(session.credentials, same(initial));
    expect(room.disconnects, 0);
    api.pending[1].completeError(StateError('temporary'));
    await retry;
    expect(session.phase, LiveKitCallPhase.connected);
    session.dispose();
  });

  test(
      'replacement while old room disconnects cannot connect or publish to new room',
      () async {
    final api = _Api();
    final session = LiveKitCallSession.forTesting(api: api);
    final room = _Room()..disconnectGate = Completer<void>();
    session.debugAdoptConnected(room, _creds('A'));
    final refresh = session.debugRefreshCredentials();
    await _turn();
    api.pending.single.complete(_creds('A'));
    await _turn();
    expect(room.disconnects, 1);
    final next = _Room();
    final creds = _creds('B');
    session.debugAdoptConnected(next, creds);
    room.disconnectGate!.complete();
    await refresh;
    expect(session.credentials, same(creds));
    expect(next.disconnects, 0);
    session.dispose();
  });

  test(
      'throwing end notification still releases captured resources exactly once',
      () async {
    var released = 0;
    await completeCallCleanup(notify: () {
      throw StateError('notification');
    }, release: () async {
      released++;
    });
    expect(released, 1);
    await completeCallCleanup(
        notify: () {},
        release: () async {
          released++;
        });
    expect(released, 2);
  });
}
