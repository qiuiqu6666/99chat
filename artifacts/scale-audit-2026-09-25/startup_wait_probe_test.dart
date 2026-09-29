// Simulated time and injected stores/transports; no real SDK or HTTP calls.
// ignore_for_file: avoid_print
import 'dart:async';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/auth_api.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_manager.dart';
import '../../test/session_manager_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('diagnostic: restore has no local deadline for a pending auth operation',
      () {
    fakeAsync((clock) {
      final pending = Completer<MeResult>();
      final store = fixture.FakeSessionStore()
        ..token = 'synthetic-token'
        ..userId = 'audit'
        ..credential = (1, 'synthetic-cache');
      final auth = fixture.FakeAuthRepository()
        ..meCall = (() => pending.future)
        ..sigCall = (() async => fixture.sig('audit'));
      final im = fixture.FakeImClient();
      final manager = SessionManager(store: store, auth: auth, im: im);
      var finished = false;
      manager.restore().then((_) => finished = true);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 60));
      print(
          'SCALE_AUDIT cold_restore pendingAuth virtualSeconds=60 finished=$finished imInitializeCalls=${im.initializeCalls}');
      expect(finished, isFalse);
      expect(im.initializeCalls, 0);
      pending.complete(fixture.me('audit'));
      clock.flushMicrotasks();
      expect(finished, isTrue);
      manager.dispose();
    });
  });
  test('diagnostic: restore has no local deadline for a pending IM login', () {
    fakeAsync((clock) {
      final store = fixture.FakeSessionStore()
        ..token = 'synthetic-token'
        ..userId = 'audit'
        ..credential = (1, 'synthetic-cache');
      final auth = fixture.FakeAuthRepository()
        ..meCall = (() async => fixture.me('audit'))
        ..sigCall = (() async => fixture.sig('audit'));
      final im = _ScaleAuditPendingIm();
      final manager = SessionManager(store: store, auth: auth, im: im);
      var finished = false;
      manager.restore().then((_) => finished = true);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 60));
      print(
          'SCALE_AUDIT cold_restore pendingIm virtualSeconds=60 finished=$finished phase=${manager.state.phase}');
      expect(finished, isFalse);
      im.pending.complete();
      clock.flushMicrotasks();
      expect(finished, isTrue);
      manager.dispose();
    });
  });
}

class _ScaleAuditPendingIm extends fixture.FakeImClient {
  final pending = Completer<void>();
  @override
  Future<void> connect({required String userId, required String userSig}) =>
      pending.future;
}
