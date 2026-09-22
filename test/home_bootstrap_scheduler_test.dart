import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scheduler gates post-home work on the first frame', () {
    final source =
        File('lib/src/bootstrap/home_bootstrap.dart').readAsStringSync();
    final wait =
        source.indexOf('await _waitForHomeFrame(identity, generation)');
    final localProjection = source.indexOf("'conversation_local_projection'");
    final idleLane = source.indexOf('_startLowPriorityNetworkIdle(');
    expect(wait, greaterThanOrEqualTo(0));
    expect(localProjection, greaterThan(wait));
    expect(idleLane, greaterThan(localProjection));
    expect(source, contains('markHomeFirstFrameReady'));
  });

  test('scheduler rejects stale completion after reset', () {
    final source =
        File('lib/src/bootstrap/home_bootstrap.dart').readAsStringSync();
    expect(source, contains('final generation = ++_generation'));
    expect(source, contains('generation == _generation'));
    expect(source, contains('SessionManager.instance.sessionGeneration'));
    final reset = source.substring(source.indexOf('void reset('));
    expect(reset, contains('_generation++'));
    expect(reset, contains('gate.complete()'));
  });

  test('scheduler executes one task at a time and records each attempt', () {
    final source =
        File('lib/src/bootstrap/home_bootstrap.dart').readAsStringSync();
    expect(source, contains('for (final task in _nativeSideEffectTasks(identity))'));
    expect(source, contains('await _runWithRetry(task, identity, generation)'));
    expect(source, contains("'home_task_start'"));
    expect(source, contains("'home_task_retry'"));
    expect(source, contains("'home_task_finish'"));
  });

  test('scheduler does not retry terminal auth failures', () {
    final source =
        File('lib/src/bootstrap/home_bootstrap.dart').readAsStringSync();
    expect(source, contains('_isTerminalAuthError(error)'));
    expect(source, contains('SessionAuthExpiredException'));
    expect(source, contains("statusCode == 401"));
    expect(source, contains("'auth_terminal'"));
  });

  test('auth_ok data reconciliation belongs to HomeBootstrap', () {
    final home =
        File('lib/src/bootstrap/home_bootstrap.dart').readAsStringSync();
    final friend = File(
      'lib/src/services/friend_local/friend_sync_service.dart',
    ).readAsStringSync();
    final group = File(
      'lib/src/services/group_local/group_membership_sync_service.dart',
    ).readAsStringSync();
    final notice = File(
      'lib/src/services/friend_request_notice_service.dart',
    ).readAsStringSync();

    expect(home, contains('HomeRealtimeConnectionStateMachine.instance.start'));
    expect(home, contains('_startIdentityBindings('));
    expect(home, isNot(contains('addAuthOkListener(_onRealtimeAuthOk)')));
    expect(home, isNot(contains('friend_incremental_idle')));
    expect(home, isNot(contains('FriendContactIncrementalSyncService')));
    expect(home, contains('ContactsProtocolSyncService.instance.attach'));
    expect(home, contains('ContactsProtocolSyncService.instance.detach'));
    final idle = home.substring(
      home.indexOf('Future<void> _startLowPriorityNetworkIdle('),
      home.indexOf('Future<void> _onRealtimeReady('),
    );
    expect(idle, isNot(contains('ContactsProtocolSyncService')));
    expect(home, isNot(contains('_startRealtimeCatchUp')));
    expect(home, contains('_waitForUiIdle'));
    expect(home, isNot(contains('readTopActiveGroupIds')));
    expect(home, isNot(contains('realtime_group_member_incremental')));
    expect(home, isNot(contains('idle_group_member_pending')));
    expect(home, isNot(contains('syncPendingEligible')));
    expect(friend, isNot(contains('onAuthOk =')));
    expect(friend, isNot(contains('_onTcpAuthOk')));
    expect(group, isNot(contains('onAuthOk =')));
    expect(group, isNot(contains('_onTcpAuthOk')));
    expect(notice, isNot(contains("reason: 'tcp_auth_ok'")));
    expect(notice, isNot(contains('FriendContactIncrementalSyncService')));
  });

  test('friend request polling is outside the post-frame deferred queue', () {
    final source =
        File('lib/src/bootstrap/home_bootstrap.dart').readAsStringSync();
    expect(source, isNot(contains('notification_permission')));
    expect(source, contains("'friend_request_notice_idle'"));
    expect(source, contains('_startIdentityBindings('));
    expect(
        source, contains('Future<void>.delayed(const Duration(seconds: 30))'));
    final idle = source.substring(
      source.indexOf('Future<void> _startLowPriorityNetworkIdle('),
      source.indexOf('Future<void> _onRealtimeReady('),
    );
    expect(idle, contains("'device_sync'"));
    expect(idle, isNot(contains("'friend_request_notice_idle'")));
    expect(idle, isNot(contains("'push_registration'")));
  });
}
