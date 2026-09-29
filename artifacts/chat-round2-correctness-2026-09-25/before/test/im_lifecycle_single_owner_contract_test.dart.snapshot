import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ImClient owns SDK lifecycle and receives typed bridge events', () {
    final client = File('lib/src/session/im_client.dart').readAsStringSync();
    final bridge =
        File('lib/src/session/im_event_bridge.dart').readAsStringSync();
    final manager =
        File('lib/src/session/session_manager.dart').readAsStringSync();

    expect(client, contains('UIKitBootstrap.instance.initialize'));
    expect(client, contains('UIKitBootstrap.instance.dispose'));
    expect(client, contains('TencentImSDKPlugin.v2TIMManager.login'));
    expect(bridge, contains('V2TimSDKListener'));
    expect(manager, contains('setEventBridge'));
    expect(manager, contains('onUserSigExpired'));
    expect(manager, contains('onKickedOffline'));
    final authSession =
        File('lib/src/services/auth_session_service.dart').readAsStringSync();
    expect(authSession, contains('SessionManager.instance.signOut'));
  });

  test('page code does not register the SDK lifecycle listener directly', () {
    final app = File('lib/src/pages/app.dart').readAsStringSync();
    expect(app, isNot(contains('V2TIMManager.addIMSDKListener')));
    expect(app, isNot(contains('V2TimSDKListener(')));
    expect(app, contains('SessionManager.instance.restore()'));
  });

  test(
      'terminal SessionManager sign out invalidates the process identity fence',
      () {
    final session =
        File('lib/src/session/session_manager.dart').readAsStringSync();
    expect(session, contains('SessionIdentityService.instance.invalidate'));
    expect(session, contains('invalidateIdentity = true'));
    final account = File('lib/src/services/account_session_service.dart')
        .readAsStringSync();
    expect(account, contains('invalidateIdentity: false'));
    expect(account, isNot(contains('uninitializeImSdkForAccountBoundary')));
    final authSession =
        File('lib/src/services/auth_session_service.dart').readAsStringSync();
    expect(authSession, isNot(contains('uninitializeImSdkForAccountBoundary')));
  });
}
