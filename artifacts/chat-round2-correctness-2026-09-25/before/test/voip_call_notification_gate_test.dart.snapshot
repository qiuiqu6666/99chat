import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/livekit_call_signaling.dart';

void main() {
  test('native VoIP path gates on call notification preference', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(source, contains('callNotificationEnabledDefaultsKey'));
    expect(source, contains('isCallNotificationEnabled()'));
    expect(source, contains('cacheCallNotificationEnabled'));
    expect(source, contains('report then end'));
    expect(source, contains('CallKit 已立刻结束'));
    expect(source, contains('onVoipPush'));
  });

  test('Flutter voip handler still presents in-app UI when call notify is off', () {
    final coordinator =
        File('lib/src/services/incoming_call_coordinator.dart').readAsStringSync();
    final settings =
        File('lib/src/services/notification_settings_service.dart').readAsStringSync();
    expect(coordinator, contains('resolveAllowsCallNotify'));
    expect(coordinator, contains('present in-app fullscreen'));
    expect(
      coordinator,
      isNot(contains('voip push ignored — call notifications disabled')),
    );
    expect(settings, contains('_resolveAllowsCallNotify'));
    expect(settings, contains('ensureObserversAttached'));
    expect(
      settings,
      isNot(contains('voip push ignored — call notifications disabled')),
    );
  });

  test('lk_call invite still opens fullscreen when call notifications are off', () {
    final source =
        File('lib/src/services/livekit_call_signaling.dart').readAsStringSync();
    expect(source, contains('allowsCallNotify'));
    expect(source, contains('shouldOpenInAppIncomingCallPage'));
    expect(source, contains('still present in-app fullscreen'));
    expect(
      source,
      isNot(contains('invite ignored — call notifications disabled')),
    );
  });

  test('in-app fullscreen opens even when call notifications are off', () {
    expect(
      shouldOpenInAppIncomingCallPage(
        callNotificationEnabled: false,
        systemIncomingUiAlreadyPresent: true,
      ),
      isTrue,
    );
    expect(
      shouldOpenInAppIncomingCallPage(
        callNotificationEnabled: false,
        systemIncomingUiAlreadyPresent: false,
      ),
      isTrue,
    );
    expect(
      shouldOpenInAppIncomingCallPage(
        callNotificationEnabled: true,
        systemIncomingUiAlreadyPresent: true,
      ),
      isFalse,
    );
    expect(
      shouldOpenInAppIncomingCallPage(
        callNotificationEnabled: true,
        systemIncomingUiAlreadyPresent: false,
      ),
      isTrue,
    );
  });

  test('ended VoIP still forwards to Dart handler after stopping CallKit', () {
    final source =
        File('lib/src/services/ios_apns_push_service.dart').readAsStringSync();
    final start = source.indexOf('if (VoipPushPayload.shouldEndCall(data))');
    expect(start, greaterThanOrEqualTo(0));
    final next = source.indexOf(
      'if (!VoipPushPayload.isCallPushType(type))',
      start,
    );
    expect(next, greaterThan(start));
    final block = source.substring(start, next);
    expect(block, contains('await endVoipCallKit()'));
    expect(block, contains('_onVoipPush'));
    expect(block, contains('await endHandler(data)'));
    expect(block.indexOf('_onVoipPush'), lessThan(block.lastIndexOf('return;')));
  });

  test('coordinator ends stale VoIP before call-type gate', () {
    final coordinator =
        File('lib/src/services/incoming_call_coordinator.dart').readAsStringSync();
    final handle = coordinator.indexOf('Future<void> handleVoipPush');
    expect(handle, greaterThanOrEqualTo(0));
    final endCall =
        coordinator.indexOf('VoipPushPayload.shouldEndCall(data)', handle);
    final callType =
        coordinator.indexOf('VoipPushPayload.isCallPushType(type)', handle);
    expect(endCall, greaterThan(handle));
    expect(callType, greaterThan(endCall));
    final endBlock = coordinator.substring(endCall, callType);
    expect(endBlock, contains('noteInviteHandled'));
    expect(endBlock, contains('handleRemoteAction'));
    expect(endBlock, contains('endVoipCallKit'));
  });

  test('session maps timeout/busy and exposes stale ringing reconcile', () {
    final source =
        File('lib/src/services/livekit_call_session.dart').readAsStringSync();
    expect(source, contains("case 'timeout':"));
    expect(source, contains("case 'busy':"));
    expect(source, contains('reason: AppCallEndReason.noResponse'));
    expect(source, contains('Future<void> reconcileStaleRinging'));
    expect(source, contains('_ringDeadline'));
  });

  test('resume reconciles stale ringing before restoring call page', () {
    final source =
        File('lib/src/services/livekit_call_system_ui.dart').readAsStringSync();
    final start = source.indexOf(
      '} else if (state == AppLifecycleState.resumed)',
    );
    expect(start, greaterThanOrEqualTo(0));
    final end = source.indexOf(
      'Future<void> _ensureCallPageForAndroidPip',
      start,
    );
    final block = source.substring(start, end);
    expect(
      block.indexOf('reconcileStaleRinging'),
      lessThan(block.indexOf('ensureCallPageVisible')),
    );
  });

  test('openCallPage refuses to push when session is not in a call', () {
    final source =
        File('lib/src/services/livekit_call_navigator.dart').readAsStringSync();
    final start = source.indexOf('static Future<void> openCallPage');
    final end = source.indexOf('static Future<void> bringCallPageToFront', start);
    final block = source.substring(start, end);
    final check = block.indexOf('!LiveKitCallSession.instance.isInCall');
    final latch = block.indexOf('_open = true;');
    expect(check, greaterThanOrEqualTo(0));
    expect(latch, greaterThan(check));
  });

  test('native shouldEndVoipCall treats timeout as terminal', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final start = source.indexOf('private func shouldEndVoipCall');
    expect(start, greaterThanOrEqualTo(0));
    final end = source.indexOf('private func shouldPresentVoipCall', start);
    final block = source.substring(start, end);
    expect(block, contains('"timeout"'));
    expect(block, contains('"busy"'));
    expect(block, contains('action != "invite"'));
  });
}
