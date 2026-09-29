// Diagnostic assertions reproduce current behavior; they are not acceptance tests.
// ignore_for_file: avoid_print, depend_on_referenced_packages
import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_manager.dart';
import '../../../test/session_manager_test.dart' as fixture;

class PendingReconnectIm extends fixture.FakeImClient {
  bool holdConnections = false;
  final pending = <Completer<void>>[];
  @override
  Future<void> connect({required String userId, required String userSig}) {
    connectCalls++;
    connectedUsers.add(userId);
    if (!holdConnections) return Future<void>.value();
    final gate = Completer<void>();
    pending.add(gate);
    return gate.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('A05 cached restore reconnects twice and repeats for an already ready session', () {
    fakeAsync((clock) {
      final store = fixture.FakeSessionStore()
        ..token = 'audit-token'
        ..userId = 'audit-owner'
        ..credential = (1, 'cached');
      final auth = fixture.FakeAuthRepository()
        ..meCall = (() async => fixture.me('audit-owner'))
        ..sigCall = (() async => fixture.sig('audit-owner'));
      final im = fixture.FakeImClient();
      final session = SessionManager(store: store, auth: auth, im: im);
      session.restore();
      clock.flushMicrotasks();
      expect(session.state.isReady, isTrue);
      expect(im.connectCalls, 2);
      session.restore();
      clock.flushMicrotasks();
      expect(im.connectCalls, 4);
      expect(auth.meCalls, 2);
      expect(auth.sigCalls, 2);
      print('A05 two restores => connectCalls=${im.connectCalls}, '
          'fetchMe=${auth.meCalls}, fetchCredential=${auth.sigCalls}');
      session.dispose();
    });
  });

  test('A06 repeated disconnect can overlap two reconnect login attempts', () {
    fakeAsync((clock) {
      final store = fixture.FakeSessionStore()
        ..token = 'audit-token'
        ..userId = 'audit-owner';
      final auth = fixture.FakeAuthRepository()
        ..meCall = (() async => fixture.me('audit-owner'))
        ..sigCall = (() async => fixture.sig('audit-owner'));
      final im = PendingReconnectIm();
      final session = SessionManager(store: store, auth: auth, im: im);
      session.restore();
      clock.flushMicrotasks();
      expect(session.state.isReady, isTrue);
      expect(im.connectCalls, 1);
      im.holdConnections = true;
      im.bridge!.onDisconnected!(1, 'injected disconnect one');
      clock.elapse(const Duration(seconds: 2));
      clock.flushMicrotasks();
      expect(im.pending.length, 1);
      im.bridge!.onDisconnected!(1, 'injected disconnect two');
      clock.elapse(const Duration(seconds: 5));
      clock.flushMicrotasks();
      expect(im.pending.length, 2);
      expect(im.connectCalls, 3);
      print('A06 first reconnect still pending; concurrentReconnects='
          '${im.pending.length}, totalConnectCalls=${im.connectCalls}');
      for (final gate in im.pending) {
        gate.complete();
      }
      clock.flushMicrotasks();
      session.dispose();
    });
  });
}
