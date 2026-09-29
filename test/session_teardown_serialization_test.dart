import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_manager.dart';
import 'session_manager_test.dart' as f;

class _HeldIm extends f.FakeImClient {
  Completer<void>? loginGate;
  Completer<void>? disconnectGate;
  int activeLogin = 0;
  int disconnects = 0;
  bool overlapped = false;
  @override
  Future<void> connect(
      {required String userId, required String userSig}) async {
    activeLogin++;
    try {
      await loginGate?.future;
      await super.connect(userId: userId, userSig: userSig);
    } finally {
      activeLogin--;
    }
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    overlapped |= activeLogin != 0;
    await disconnectGate?.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('new login waits for old teardown before persisting or becoming ready',
      () async {
    final store = f.FakeSessionStore()
      ..token = 'old'
      ..userId = 'old';
    final auth = f.FakeAuthRepository()
      ..meCall = (() async => f.me('new'))
      ..sigCall = (() async => f.sig('new'));
    final im = _HeldIm()..disconnectGate = Completer<void>();
    final session = SessionManager(store: store, auth: auth, im: im);
    final logout = session.signOut(invalidateIdentity: false);
    final login = session.establishFromSavedBusinessSession(
        token: 'new-token', userId: 'new');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final prematureReady = session.state.isReady;
    final prematureToken = store.token;
    im.disconnectGate!.complete();
    await logout;
    await login;
    expect(prematureReady, isFalse);
    expect(prematureToken, isNull);
    expect(session.state.isReady, isTrue);
    expect(session.state.userId, 'new');
    expect(store.token, 'new-token');
    expect(im.connectedUsers, ['new']);
  });
  test('native logout waits for the actual prior SDK login', () async {
    final store = f.FakeSessionStore();
    final auth = f.FakeAuthRepository()
      ..meCall = (() async => f.me('old'))
      ..sigCall = (() async => f.sig('old'));
    final im = _HeldIm()..loginGate = Completer<void>();
    final session = SessionManager(store: store, auth: auth, im: im);
    final login = session.establishFromSavedBusinessSession(
        token: 'old-token', userId: 'old');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(im.activeLogin, 1);
    final logout = session.signOut(invalidateIdentity: false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final prematureDisconnect = im.disconnects;
    im.loginGate!.complete();
    await login;
    await logout;
    expect(prematureDisconnect, 0);
    expect(im.overlapped, isFalse);
    expect(store.token, isNull);
    expect(session.state.isLoggedOut, isTrue);
  });

  test(
      'hung native login does not hold logout and late cleanup preserves new credentials',
      () async {
    final store = f.FakeSessionStore();
    var accountNumber = 0;
    final auth = f.FakeAuthRepository()
      ..meCall = (() async => f.me(accountNumber == 0 ? 'old' : 'new'))
      ..sigCall = (() async => f.sig(accountNumber == 0 ? 'old' : 'new'));
    final im = _HeldIm()..loginGate = Completer<void>();
    final session = SessionManager(
      store: store,
      auth: auth,
      im: im,
      imOperationWaitBudget: const Duration(seconds: 2),
      signOutWaitBudget: const Duration(milliseconds: 30),
    );

    final oldLogin = session.establishFromSavedBusinessSession(
      token: 'old-token',
      userId: 'old',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(im.activeLogin, 1);

    await session
        .signOut(invalidateIdentity: false)
        .timeout(const Duration(milliseconds: 250));
    expect(session.state.isLoggedOut, isTrue);
    expect(store.token, isNull);
    expect(im.disconnects, 0);

    accountNumber = 1;
    final newLogin = session.establishFromSavedBusinessSession(
      token: 'new-token',
      userId: 'new',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(store.token, 'new-token');
    expect(im.connectedUsers, isEmpty);

    im.loginGate!.complete();
    await Future.wait<void>([oldLogin, newLogin]);
    expect(session.state.isReady, isTrue);
    expect(session.state.userId, 'new');
    expect(store.token, 'new-token');
    // The uncancellable native login may finish after logout begins; the
    // serialized teardown disconnects it before the new account is admitted.
    expect(im.connectedUsers, ['old', 'new']);
    expect(im.overlapped, isFalse);
    expect(im.disconnects, 1);
  });
}
