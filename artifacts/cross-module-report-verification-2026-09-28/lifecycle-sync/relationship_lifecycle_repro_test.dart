// Audit reproductions of existing behavior. These assertions describe defects.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_reconcile_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => ActiveChatRegistry.instance.reset());

  test('A07 production idle predicate is bypassed after deadline', () async {
    ActiveChatRegistry.instance.enter('c2c_audit-active-chat');
    var friendCalls = 0;
    var groupCalls = 0;
    final service = ImSdkRelationshipReconcileService.forTest(
      directory: ImSdkRelationshipDirectory(),
      loadFriends: () async { friendCalls++; return []; },
      loadGroups: () async { groupCalls++; return []; },
      // No canRunNow override: exercises the real ActiveChatRegistry predicate.
      uiIdleTimeout: const Duration(milliseconds: 30),
    );
    final task = service.requestRelationshipReconcile(reason: 'A07-audit');
    expect(friendCalls, 0);
    expect(groupCalls, 0);
    await task.timeout(const Duration(seconds: 2));
    expect(ActiveChatRegistry.instance.activeConversationId,
        'c2c_audit-active-chat');
    expect(friendCalls, 1);
    expect(groupCalls, 1);
  });

  for (final oldFails in [false, true]) {
    test('A08 late old ${oldFails ? 'error' : 'success'} suppresses the new session job', () async {
      final directory = ImSdkRelationshipDirectory();
      final oldFriends = Completer<List<RelationshipFriendEntry>>();
      final oldGroups = Completer<List<RelationshipGroupEntry>>();
      var friendCalls = 0;
      var groupCalls = 0;
      final service = ImSdkRelationshipReconcileService.forTest(
        directory: directory,
        loadFriends: () { friendCalls++; return oldFriends.future; },
        loadGroups: () { groupCalls++; return oldGroups.future; },
        canRunNow: () => true,
      );
      service.resetForSession(100);
      final oldTask = service.requestFirstSnapshot(reason: 'old-session');
      await Future<void>.delayed(Duration.zero);
      expect(friendCalls, 1);
      expect(groupCalls, 1);

      service.resetForSession(101);
      service.holdNextRun();
      final newTask = service.requestFirstSnapshot(reason: 'new-session');
      expect(service.friendFirstPhase, ImSdkRelationshipPhase.scheduled);
      expect(service.groupFirstPhase, ImSdkRelationshipPhase.scheduled);
      if (oldFails) {
        oldFriends.completeError(StateError('late old failure'));
        oldGroups.completeError(StateError('late old failure'));
      } else {
        oldFriends.complete([]);
        oldGroups.complete([]);
      }
      await oldTask;
      final stalePhase = oldFails
          ? ImSdkRelationshipPhase.idle : ImSdkRelationshipPhase.completed;
      expect(service.friendFirstPhase, stalePhase);
      expect(service.groupFirstPhase, stalePhase);
      service.releaseIdleHold();
      await newTask;
      expect(friendCalls, 1, reason: 'new session never fetched friends');
      expect(groupCalls, 1, reason: 'new session never fetched groups');
      expect(directory.hasCompleteFriendSnapshot, isFalse);
      expect(directory.hasCompleteGroupSnapshot, isFalse);
    });
  }
}
