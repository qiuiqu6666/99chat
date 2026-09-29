import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_reconcile_service.dart';

RelationshipFriendEntry friend(String id) => RelationshipFriendEntry(
    userId: id, displayName: id, faceUrl: '', remark: '', sortKey: id);
RelationshipGroupEntry group(String id) => RelationshipGroupEntry(
    groupId: id, groupName: id, faceUrl: '', groupType: 'Work', sortKey: id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => ActiveChatRegistry.instance.reset());

  for (final oldFails in [false, true]) {
    test(
        'old ${oldFails ? 'failure' : 'success'} cannot consume new session snapshot',
        () async {
      final directory = ImSdkRelationshipDirectory();
      final oldFriends = Completer<List<RelationshipFriendEntry>>();
      final oldGroups = Completer<List<RelationshipGroupEntry>>();
      var friendCalls = 0;
      var groupCalls = 0;
      final service = ImSdkRelationshipReconcileService.forTest(
        directory: directory,
        loadFriends: () => ++friendCalls == 1
            ? oldFriends.future
            : Future.value([friend('new-friend')]),
        loadGroups: () => ++groupCalls == 1
            ? oldGroups.future
            : Future.value([group('new-group')]),
        canRunNow: () => true,
      );
      addTearDown(() => service.onSessionInvalidated());
      service.resetForSession(100);
      final oldTask = service.requestFirstSnapshot(reason: 'old');
      await Future<void>.delayed(Duration.zero);
      service.resetForSession(101);
      service.holdNextRun();
      final newTask = service.requestFirstSnapshot(reason: 'new');
      if (oldFails) {
        oldFriends.completeError(StateError('old failure'));
        oldGroups.completeError(StateError('old failure'));
      } else {
        oldFriends.complete([friend('old-friend')]);
        oldGroups.complete([group('old-group')]);
      }
      await oldTask;
      expect(service.friendFirstPhase, ImSdkRelationshipPhase.scheduled);
      expect(service.groupFirstPhase, ImSdkRelationshipPhase.scheduled);
      service.releaseIdleHold();
      await newTask;
      expect(friendCalls, 2);
      expect(groupCalls, 2);
      expect(directory.friendOrderedIds, ['new-friend']);
      expect(directory.groupOrderedIds, ['new-group']);
    });
  }

  test('directory reset never reuses an outstanding capture token', () {
    final directory = ImSdkRelationshipDirectory();
    final oldFriend = directory.beginFriendCapture();
    final oldGroup = directory.beginGroupCapture();
    directory.reset();
    final nextFriend = directory.beginFriendCapture();
    final nextGroup = directory.beginGroupCapture();
    expect(nextFriend, isNot(oldFriend));
    expect(nextGroup, isNot(oldGroup));
    directory.dropFriendCapture(oldFriend);
    directory.dropGroupCapture(oldGroup);
    directory
        .applyFriendSnapshot(captureId: nextFriend, entries: [friend('new')]);
    directory.applyGroupSnapshot(captureId: nextGroup, entries: [group('new')]);
    expect(directory.hasCompleteFriendSnapshot, isTrue);
    expect(directory.hasCompleteGroupSnapshot, isTrue);
  });

  test('active chat past deadline defers rather than runs calibration',
      () async {
    ActiveChatRegistry.instance.enter('c2c_busy');
    var calls = 0;
    final service = ImSdkRelationshipReconcileService.forTest(
      directory: ImSdkRelationshipDirectory(),
      loadFriends: () async {
        calls++;
        return [];
      },
      loadGroups: () async {
        calls++;
        return [];
      },
      uiIdleTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(() => service.onSessionInvalidated());
    await service.requestRelationshipReconcile(reason: 'busy');
    expect(calls, 0);
    expect(
        service.friendReconcilePhase, isNot(ImSdkRelationshipPhase.completed));
    ActiveChatRegistry.instance.leave('c2c_busy');
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(calls, 2);
    expect(service.friendReconcilePhase, ImSdkRelationshipPhase.completed);
  });
}
