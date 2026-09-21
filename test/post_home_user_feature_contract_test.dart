import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HomeBootstrap is the only post-home IM scheduler', () {
    final home =
        File('lib/src/bootstrap/home_bootstrap.dart').readAsStringSync();
    expect(home, contains('HomePostImSyncService.instance.run'));

    final dartFiles = Directory('lib/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in dartFiles) {
      if (file.path.endsWith('home_bootstrap.dart')) {
        continue;
      }
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('NativePostHomeBootstrapQueue')),
        reason: file.path,
      );
    }
  });

  test('post-home work starts after the real first frame gate', () {
    final home =
        File('lib/src/bootstrap/home_bootstrap.dart').readAsStringSync();
    final page = File('lib/src/pages/home_page.dart').readAsStringSync();
    expect(home, contains('_waitForHomeFrame'));
    expect(home, contains('markHomeFirstFrameReady'));
    expect(page, contains('markHomeFirstFrameReady'));
    expect(home, isNot(contains('Duration(milliseconds: 250)')));
  });

  test('local archive ids hydrate before conversation first window', () {
    final home =
        File('lib/src/bootstrap/home_bootstrap.dart').readAsStringSync();
    final archive = home.indexOf("'archive_local_ids'");
    final local = home.indexOf("'conversation_local_projection'");
    final realtime =
        home.indexOf('HomeRealtimeConnectionStateMachine.instance.start');

    expect(archive, greaterThanOrEqualTo(0));
    expect(local, greaterThan(archive));
    expect(realtime, greaterThan(local));
    expect(
      home.substring(local, realtime),
      contains('ChatSessionController.instance.restoreProjection'),
    );
  });

  test('IM login attaches realtime bindings before HomePage', () {
    final session =
        File('lib/src/session/session_manager.dart').readAsStringSync();
    expect(session, contains('_startAccountRealtime('));
    expect(session, contains('ListenerStore.attachRealtimeBindings'));
  });

  test(
      'realtime connection is owned by an independent background state machine',
      () {
    final home =
        File('lib/src/bootstrap/home_bootstrap.dart').readAsStringSync();
    final machine = File(
      'lib/src/services/home_realtime_connection_state_machine.dart',
    ).readAsStringSync();

    expect(home, contains('HomeRealtimeConnectionStateMachine.instance.start'));
    expect(home, isNot(contains('ListenerStore.attachRealtimeBindings')));
    expect(machine, contains('SessionIdentityService.instance.isCurrent'));
    expect(machine, contains('int _generation = 0'));
    expect(machine, contains('Timer? _retryTimer'));
    expect(machine, contains('HomeRealtimeConnectionPhase.ready'));
    expect(machine, contains('HomeRealtimeConnectionPhase.failed'));
  });

  test('native post-home work is represented by one serialized scheduler task',
      () {
    final home =
        File('lib/src/bootstrap/home_bootstrap.dart').readAsStringSync();
    expect(home, contains("'native_post_home'"));
    expect(home, contains('for (final task in _nativeSideEffectTasks())'));
    expect(home, contains('await _runWithRetry(task, identity, generation)'));
  });

  test('native post-home side effects belong to HomeBootstrap', () {
    final home =
        File('lib/src/bootstrap/home_bootstrap.dart').readAsStringSync();
    final queue = File(
      'lib/src/services/home_post_im_sync_service.dart',
    ).readAsStringSync();

    for (final task in <String>[
      "'archived_sync'",
      "'folder_sync'",
      "'pin_sync'",
      "'avatar_push'",
      "'stickers'",
      "'group_notice'",
      "'moments_cover_cache'",
    ]) {
      expect(home, contains(task));
    }
    // Per-conversation mute state is reconciled on demand or by explicit
    // settings changes. A full `/conversation-notify/batch` must not be part
    // of the post-home startup queue.
    expect(home, isNot(contains("'notify_sync'")));
    expect(queue, isNot(contains('_runSideEffects')));
    expect(queue, isNot(contains('ConversationNotifySyncService')));
    expect(queue, isNot(contains('friend_contact_incremental')));
    expect(queue, isNot(contains('FriendSyncService.instance.syncFull')));
    expect(queue, isNot(contains('group_change_events')));
    expect(queue, isNot(contains('group_live_index')));
    expect(queue, contains('bootstrapTypedFirstScreen'));
    expect(home, isNot(contains('idle_group_change_events')));
    expect(home, contains('idle_group_live_index'));
    expect(home, isNot(contains('idle_group_entity_incremental')));
    expect(home, contains('idle_group_notice_incremental'));
    expect(home, isNot(contains('idle_group_member_pending')));
    expect(home, isNot(contains('syncPendingEligible')));
    expect(home, isNot(contains('maxGroups: 5')));
    expect(home,
        isNot(contains('ActiveChatRegistry.instance.activeConversationId')));
    expect(home, isNot(contains('realtime_group_member_incremental')));
    expect(queue, isNot(contains('GroupEntityIncrementalSyncService')));
    expect(queue, isNot(contains('GroupNoticeIncrementalSyncService')));
    expect(queue, isNot(contains('GroupMemberIncrementalSyncService')));
  });

  test('group full sync does not fan out hidden post-snapshot work', () {
    final source = File(
      'lib/src/services/group_local/group_membership_sync_service.dart',
    ).readAsStringSync();
    final syncFullStart = source.indexOf('Future<void> syncFull(');
    expect(syncFullStart, greaterThanOrEqualTo(0));
    final syncFullEnd = source.indexOf(
        'Future<bool> _shouldSkipNetworkSyncFull', syncFullStart);
    expect(syncFullEnd, greaterThan(syncFullStart));
    final body = source.substring(syncFullStart, syncFullEnd);
    expect(body, isNot(contains('GroupEntityIncrementalSyncService')));
    expect(body, isNot(contains('GroupNoticeIncrementalSyncService')));
    expect(body, isNot(contains('syncAllJoined(')));
    expect(body, isNot(contains('syncMyEvents(')));
  });

  test('home/auth notice bootstrap does not start a global poll', () {
    final home =
        File('lib/src/bootstrap/home_bootstrap.dart').readAsStringSync();
    final auth =
        File('lib/src/services/auth_bootstrap_service.dart').readAsStringSync();
    expect(home, contains('startFallbackPolling: false'));
    expect(auth, contains('startFallbackPolling: false'));
  });

  test('login schedulers do not refresh the joined-group directory', () {
    final home =
        File('lib/src/bootstrap/home_bootstrap.dart').readAsStringSync();
    final postHome = File(
      'lib/src/services/home_post_im_sync_service.dart',
    ).readAsStringSync();
    final auth =
        File('lib/src/services/auth_bootstrap_service.dart').readAsStringSync();
    final login =
        File('lib/src/services/login_coordinator.dart').readAsStringSync();

    // Joined groups and friend relations come from IM SDK listeners / list
    // APIs. Home idle must not run directory reconcile or change-event pages.
    expect(home, isNot(contains("'idle_group_membership'")));
    expect(home, isNot(contains('GroupMembershipSyncService.instance.syncFull')));
    expect(home, isNot(contains('GroupChangeEventSyncService')));
    expect(home, isNot(contains('FriendContactIncrementalSyncService')));
    expect(home, contains('ContactsProtocolSyncService.instance.attach'));
    final idle = home.substring(
      home.indexOf('Future<void> _startLowPriorityNetworkIdle('),
      home.indexOf('Future<void> _onRealtimeReady('),
    );
    expect(idle, isNot(contains('ContactsProtocolSyncService')));
    expect(home, isNot(contains('GroupMemberIncrementalSyncService')));
    expect(postHome,
        isNot(contains('GroupMembershipSyncService.instance.syncFull')));
    expect(auth, isNot(contains('FriendSyncService.instance.syncFull')));
    final friend = File(
      'lib/src/services/friend_local/friend_sync_service.dart',
    ).readAsStringSync();
    final notice = File(
      'lib/src/services/friend_request_notice_service.dart',
    ).readAsStringSync();
    expect(friend, isNot(contains('Future<void> syncFull(')));
    expect(friend, isNot(contains('FriendContactIncrementalSyncService')));
    expect(notice, isNot(contains('_contactSyncTimer')));
    expect(notice, isNot(contains('kickContactSyncBurst')));
    expect(notice, isNot(contains('_syncFriendContactDifference')));
    expect(
        auth, isNot(contains('GroupMembershipSyncService.instance.syncFull')));
    expect(auth, isNot(contains('refreshImUIKitLists')));
    expect(login, isNot(contains('refreshImUIKitLists')));
    expect(home, isNot(contains('requestRelationshipReconcile')));
    expect(home, isNot(contains('getJoinedGroupList')));
  });

  test('conversation sync may calibrate lists after session sync, not as ready',
      () {
    final sync = File(
      'lib/src/services/conversation_local/conversation_sync_service.dart',
    ).readAsStringSync();
    expect(sync, contains('requestRelationshipReconcile'));
    expect(sync, isNot(contains('relationshipReady')));
  });

  test('conversation sync does not auto-start multi-conversation history warm',
      () {
    final sync = File(
      'lib/src/services/conversation_local/conversation_sync_service.dart',
    ).readAsStringSync();

    expect(sync, isNot(contains('scheduleHistoryWarmWhenIdle')));
    expect(sync, isNot(contains('scheduleAfterConversationSync')));
  });
}
