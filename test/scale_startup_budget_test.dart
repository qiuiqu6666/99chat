import 'dart:async';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/auth_api.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_manager.dart';
import 'package:tencent_cloud_chat_demo/src/session/auth_repository.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_state.dart';
import 'session_manager_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'startup budget releases UI, keeps auth single flight and rejects late 401',
      () {
    fakeAsync((clock) {
      final pending = Completer<MeResult>();
      final store = fixture.FakeSessionStore()
        ..token = 'token'
        ..userId = 'a'
        ..credential = (1, 'cached');
      final auth = fixture.FakeAuthRepository()
        ..meCall = (() => pending.future);
      final im = fixture.FakeImClient();
      final session = SessionManager(store: store, auth: auth, im: im);
      var finished = false;
      session.restore().then((_) => finished = true);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 9));
      expect(finished, isTrue);
      expect(session.state.phase, SessionPhase.offline);
      expect(im.initializeCalls, 0);
      session.restore();
      session.scheduleReconnect('a');
      clock.elapse(const Duration(seconds: 10));
      expect(auth.meCalls, 1);
      pending.completeError(const SessionAuthExpiredException());
      clock.flushMicrotasks();
      expect(session.state.isLoggedOut, isTrue);
      expect(store.cleared, isTrue);
      session.dispose();
    });
  });
  test(
      'slow SDK login releases UI without a second login and accepts late success',
      () {
    fakeAsync((clock) {
      final store = fixture.FakeSessionStore()
        ..token = 'token'
        ..userId = 'a'
        ..credential = (1, 'cached');
      final auth = fixture.FakeAuthRepository()
        ..meCall = (() async => fixture.me('a'))
        ..sigCall = (() => Completer<UserSigResult>().future);
      final im = _PendingIm();
      final session = SessionManager(store: store, auth: auth, im: im);
      var finished = false;
      session.restore().then((_) => finished = true);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 9));
      expect(finished, isTrue);
      expect(session.state.phase, SessionPhase.offline);
      session.scheduleReconnect('a');
      clock.elapse(const Duration(seconds: 10));
      expect(im.connectCalls, 1);
      im.pending.complete();
      clock.flushMicrotasks();
      expect(session.state.isReady, isTrue);
      session.dispose();
    });
  });
}

class _PendingIm extends fixture.FakeImClient {
  final pending = Completer<void>();
  @override
  Future<void> connect({required String userId, required String userSig}) {
    connectCalls++;
    return pending.future;
  }
}
