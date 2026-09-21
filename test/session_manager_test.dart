import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_expiry_service.dart';
import 'package:tencent_cloud_chat_demo/src/api/auth_api.dart';
import 'package:tencent_cloud_chat_demo/src/session/auth_repository.dart';
import 'package:tencent_cloud_chat_demo/src/session/im_client.dart';
import 'package:tencent_cloud_chat_demo/src/session/im_event_bridge.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_manager.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_state.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_store.dart';

MeResult me(String userId) => MeResult(
      userId: userId,
      phone: '',
      phoneMasked: '',
      nickname: userId,
    );

UserSigResult sig(String userId) => UserSigResult(
      sdkAppId: 1,
      userId: userId,
      userSig: 'sig-$userId',
      expiresIn: 3600,
    );

class FakeSessionStore extends SessionStore {
  String? token;
  String? userId;
  (int, String)? credential;
  bool cleared = false;

  @override
  Future<String?> readBusinessToken() async => token;

  @override
  Future<String?> readUserId() async => userId;

  @override
  Future<void> saveBusinessSession({
    required String token,
    required String userId,
  }) async {
    this.token = token;
    this.userId = userId;
  }

  @override
  Future<void> saveImCredential({
    required int sdkAppId,
    required String userSig,
    required int expiresIn,
  }) async {
    credential = (sdkAppId, userSig);
  }

  @override
  Future<(int, String)?> readImCredential() async => credential;

  @override
  Future<void> clear() async {
    cleared = true;
    token = null;
    userId = null;
    credential = null;
  }
}

class FakeAuthRepository extends AuthRepository {
  Future<MeResult> Function()? meCall;
  Future<UserSigResult> Function()? sigCall;
  int meCalls = 0;
  int sigCalls = 0;

  @override
  Future<MeResult> fetchMe() async {
    meCalls++;
    final call = meCall;
    if (call == null) throw StateError('fetchMe not configured');
    return call();
  }

  @override
  Future<UserSigResult> fetchImCredential() async {
    sigCalls++;
    final call = sigCall;
    if (call == null) throw StateError('fetchImCredential not configured');
    return call();
  }
}

class FakeImClient extends ImClient {
  ImEventBridge? bridge;
  int initializeCalls = 0;
  int connectCalls = 0;
  final List<String> connectedUsers = <String>[];
  bool failConnect = false;
  ImClientException? connectError;
  bool failDisconnect = false;
  int disposeCalls = 0;

  @override
  void setEventBridge(ImEventBridge events) => bridge = events;

  @override
  Future<void> initialize(int sdkAppId) async => initializeCalls++;

  @override
  Future<void> connect(
      {required String userId, required String userSig}) async {
    connectCalls++;
    if (connectError != null) throw connectError!;
    if (failConnect) throw const ImClientException('network');
    connectedUsers.add(userId);
  }

  @override
  Future<void> disconnect() async {
    if (failDisconnect) throw StateError('SDK teardown failed');
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  void emitUserSigExpired() => bridge?.onUserSigExpired?.call();

  void emitKickedOffline() => bridge?.onKickedOffline?.call();
}

SessionManager manager({
  required FakeSessionStore store,
  required FakeAuthRepository auth,
  required FakeImClient im,
}) =>
    SessionManager(store: store, auth: auth, im: im);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('restores with a valid cached UserSig before calling auth APIs',
      () async {
    final store = FakeSessionStore()
      ..token = 'token'
      ..userId = 'a'
      ..credential = (1, 'cached');
    final auth = FakeAuthRepository();
    auth.meCall = () async => me('a');
    auth.sigCall = () async => sig('a');
    final im = FakeImClient();

    final session = manager(store: store, auth: auth, im: im);
    await session.restore();

    expect(session.state.phase, SessionPhase.ready);
    expect(im.connectedUsers, ['a']);
    expect(auth.meCalls, 1);
  });

  test('does not initialize IM when the cached business session is expired',
      () async {
    final store = FakeSessionStore()
      ..token = 'token'
      ..userId = 'a'
      ..credential = (1, 'cached');
    final auth = FakeAuthRepository();
    auth.meCall = () => throw const SessionAuthExpiredException();
    final im = FakeImClient();
    final session = manager(store: store, auth: auth, im: im);

    await session.restore();

    expect(session.state.phase, SessionPhase.loggedOut);
    expect(im.initializeCalls, 0);
    expect(im.connectCalls, 0);
    expect(store.cleared, isTrue);
  });

  test('fetches a fresh UserSig when the cached credential is expired',
      () async {
    final store = FakeSessionStore()
      ..token = 'token'
      ..userId = 'a';
    final auth = FakeAuthRepository();
    auth.meCall = () async => me('a');
    auth.sigCall = () async => sig('a');
    final im = FakeImClient();

    final session = manager(store: store, auth: auth, im: im);
    await session.restore();

    expect(session.state.phase, SessionPhase.ready);
    expect(auth.meCalls, 1);
    expect(auth.sigCalls, 1);
  });

  test('reconnects after a temporary network failure', () async {
    final store = FakeSessionStore();
    final auth = FakeAuthRepository();
    auth.meCall = () async => me('a');
    auth.sigCall = () async => sig('a');
    final im = FakeImClient()..failConnect = true;
    final session = manager(store: store, auth: auth, im: im);

    await session.establishFromSavedBusinessSession(
        token: 'token', userId: 'a');
    expect(session.state.phase, SessionPhase.offline);
    im.failConnect = false;
    await Future<void>.delayed(const Duration(milliseconds: 2200));

    expect(session.state.phase, SessionPhase.ready);
    expect(im.connectedUsers, ['a']);
  });

  test(
      'logs out instead of entering offline when the business token is invalid',
      () async {
    final store = FakeSessionStore()
      ..token = 'token'
      ..userId = 'a';
    final auth = FakeAuthRepository();
    auth.meCall = () => throw const SessionAuthExpiredException();
    auth.sigCall = () async => sig('a');
    final session = manager(
      store: store,
      auth: auth,
      im: FakeImClient(),
    );

    await session.restore();

    expect(session.state.phase, SessionPhase.loggedOut);
    expect(store.cleared, isTrue);
  });

  test('signOut invalidates an in-flight login', () async {
    final store = FakeSessionStore();
    final meGate = Completer<MeResult>();
    final auth = FakeAuthRepository();
    auth.meCall = () => meGate.future;
    auth.sigCall = () async => sig('a');
    final session = manager(
      store: store,
      auth: auth,
      im: FakeImClient(),
    );
    final login = session.establishFromSavedBusinessSession(
      token: 'token',
      userId: 'a',
    );
    await Future<void>.delayed(Duration.zero);
    final logout = session.signOut();
    meGate.complete(me('a'));
    await Future.wait([login, logout]);

    expect(session.state.phase, SessionPhase.loggedOut);
  });

  test('cancels an old account reconnect when switching accounts', () async {
    final store = FakeSessionStore();
    final auth = FakeAuthRepository();
    auth.meCall = () async => me('b');
    auth.sigCall = () async => sig('b');
    final im = FakeImClient()..failConnect = true;
    final session = manager(store: store, auth: auth, im: im);

    await session.establishFromSavedBusinessSession(
        token: 'a-token', userId: 'a');
    await session.establishFromSavedBusinessSession(
        token: 'b-token', userId: 'b');
    im.failConnect = false;
    await Future<void>.delayed(const Duration(milliseconds: 2200));

    expect(session.state.userId, 'b');
    expect(session.state.phase, SessionPhase.ready);
    expect(im.connectedUsers.where((id) => id == 'a'), isEmpty);
  });

  test('refreshes UserSig after the IM expiration callback', () async {
    final store = FakeSessionStore();
    final auth = FakeAuthRepository();
    auth.meCall = () async => me('a');
    auth.sigCall = () async => sig('a');
    final im = FakeImClient();
    final session = manager(store: store, auth: auth, im: im);

    await session.establishFromSavedBusinessSession(
        token: 'token', userId: 'a');
    final before = im.connectCalls;
    im.emitUserSigExpired();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(session.state.phase, SessionPhase.ready);
    expect(im.connectCalls, greaterThan(before));
  });

  test('coalesces repeated UserSig expiration callbacks', () async {
    final store = FakeSessionStore();
    final auth = FakeAuthRepository();
    auth.meCall = () async => me('a');
    auth.sigCall = () async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return sig('a');
    };
    final im = FakeImClient();
    final session = manager(store: store, auth: auth, im: im);

    await session.establishFromSavedBusinessSession(
      token: 'token',
      userId: 'a',
    );
    final callsBeforeRefresh = auth.sigCalls;
    im.emitUserSigExpired();
    im.emitUserSigExpired();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(auth.sigCalls, callsBeforeRefresh + 1);
    expect(session.state.phase, SessionPhase.ready);
  });

  test('kicked offline logs out and does not schedule reconnect', () async {
    final store = FakeSessionStore();
    final auth = FakeAuthRepository();
    auth.meCall = () async => me('a');
    auth.sigCall = () async => sig('a');
    final im = FakeImClient();
    final session = manager(store: store, auth: auth, im: im);

    await session.establishFromSavedBusinessSession(
      token: 'token',
      userId: 'a',
    );
    im.emitKickedOffline();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(session.state.phase, SessionPhase.loggedOut);
    expect(store.cleared, isTrue);
  });

  for (final reason in SessionInvalidationReason.values) {
    testWidgets(
        '${reason.name} clears session, shows one notice and replaces chat with login',
        (tester) async {
      final store = FakeSessionStore();
      final auth = FakeAuthRepository()
        ..meCall = (() async => me('a'))
        ..sigCall = (() async => sig('a'));
      final im = FakeImClient();
      final session = manager(store: store, auth: auth, im: im);
      final navigator = GlobalKey<NavigatorState>();
      final events = <String>[];
      final notices = <String>[];
      final clearGate = Completer<void>();
      final expiry = SessionExpiryService(
        markInvalidated: (reason, _) => events.add(reason.name),
        clearSession: (reason) async {
          events.add('clear:$reason');
          await clearGate.future;
          await session.signOut();
        },
        showMessage: (message) {
          expectSync(store.cleared, isTrue);
          notices.add(message);
          events.add('notice');
        },
        navigateToLogin: () {
          events.add('login');
          navigator.currentState!.pushAndRemoveUntil(
            MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Login'))),
            (_) => false,
          );
        },
      );
      session.onSessionInvalidated = expiry.handleImSessionInvalidated;
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Chat')),
      ));
      await session.establishFromSavedBusinessSession(
          token: 'token', userId: 'a');
      if (reason == SessionInvalidationReason.kickedOffline) {
        im.emitKickedOffline();
        im.emitKickedOffline();
      } else {
        auth.sigCall = () => throw const SessionAuthExpiredException();
        im.emitUserSigExpired();
        im.emitUserSigExpired();
      }
      await tester.pump();
      expect(session.state.isLoggedOut, isTrue);
      final connectCalls = im.connectCalls;
      expect(find.text('Chat'), findsOneWidget);
      clearGate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Login'), findsOneWidget);
      expect(find.text('Chat'), findsNothing);
      expect(navigator.currentState!.canPop(), isFalse);
      expect(notices, hasLength(1));
      expect(notices.single, isNotEmpty);
      expect(events, [
        reason.name,
        'clear:${reason == SessionInvalidationReason.kickedOffline ? 'kicked_offline' : 'session_expired'}',
        'notice',
        'login'
      ]);
      expect(store.token, isNull);
      expect(store.credential, isNull);
      await tester.pump(const Duration(seconds: 35));
      expect(im.connectCalls, connectCalls);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test(
      'SDK rejection of a fresh UserSig ends the session instead of retrying forever',
      () async {
    final store = FakeSessionStore();
    final auth = FakeAuthRepository()
      ..meCall = (() async => me('a'))
      ..sigCall = (() async => sig('a'));
    final im = FakeImClient()
      ..connectError =
          const ImClientException('invalid signature', code: 70003);
    final session = manager(store: store, auth: auth, im: im);
    final reasons = <SessionInvalidationReason>[];
    session.onSessionInvalidated = (reason) async {
      reasons.add(reason);
      await session.signOut();
    };
    await session.establishFromSavedBusinessSession(
        token: 'token', userId: 'a');
    expect(reasons, [SessionInvalidationReason.credentialsExpired]);
    expect(session.state.isLoggedOut, isTrue);
    expect(store.cleared, isTrue);
  });

  test('kick fences a pending UserSig refresh so it cannot restore credentials',
      () async {
    final store = FakeSessionStore();
    final auth = FakeAuthRepository()
      ..meCall = (() async => me('a'))
      ..sigCall = (() async => sig('a'));
    final im = FakeImClient();
    final session = manager(store: store, auth: auth, im: im);
    await session.establishFromSavedBusinessSession(
        token: 'token', userId: 'a');
    final gate = Completer<UserSigResult>();
    auth.sigCall = () => gate.future;
    im.emitUserSigExpired();
    final calls = im.connectCalls;
    im.emitKickedOffline();
    await Future<void>.delayed(Duration.zero);
    gate.complete(sig('a'));
    await Future<void>.delayed(Duration.zero);
    expect(session.state.isLoggedOut, isTrue);
    expect(store.credential, isNull);
    expect(im.connectCalls, calls);
  });

  test('SDK disconnect failure still disposes SDK and clears saved credentials',
      () async {
    final store = FakeSessionStore()..token = 'token';
    final im = FakeImClient()..failDisconnect = true;
    final session = manager(store: store, auth: FakeAuthRepository(), im: im);
    await expectLater(session.signOut(), throwsStateError);
    expect(store.cleared, isTrue);
    expect(im.disposeCalls, 1);
    expect(session.state.isLoggedOut, isTrue);
  });
}
