import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_reconcile_service.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';

RelationshipFriendEntry _friend(String id) {
  return RelationshipFriendEntry(
    userId: id,
    displayName: id,
    faceUrl: '',
    remark: '',
    sortKey: ImSdkRelationshipDirectory.sortKeyFor(
      id: id,
      displayName: id,
      azTag: 'A',
    ),
  );
}

RelationshipGroupEntry _group(String id) {
  return RelationshipGroupEntry(
    groupId: id,
    groupName: id,
    faceUrl: '',
    groupType: 'Work',
    sortKey: ImSdkRelationshipDirectory.sortKeyFor(
      id: id,
      displayName: id,
      azTag: 'A',
    ),
  );
}

void main() {
  test('scheduled cancel does not consume reconcile once', () async {
    final directory = ImSdkRelationshipDirectory();
    final service = ImSdkRelationshipReconcileService.forTest(
      directory: directory,
      loadFriends: () async => <RelationshipFriendEntry>[_friend('a')],
      loadGroups: () async => <RelationshipGroupEntry>[_group('g')],
      canRunNow: () => true,
    );
    service.holdNextRun();
    final pending = service.requestRelationshipReconcile(reason: 'test');
    expect(service.friendReconcilePhase, ImSdkRelationshipPhase.scheduled);
    service.onSessionInvalidated();
    service.releaseIdleHold();
    await pending;
    expect(service.friendReconcilePhase, ImSdkRelationshipPhase.idle);
    expect(service.debugFriendGetCount, 0);

    await service.requestRelationshipReconcile(reason: 'retry');
    expect(service.friendReconcilePhase, ImSdkRelationshipPhase.completed);
    expect(service.debugFriendGetCount, 1);
  });

  test('sdk failure returns to idle and allows next legal trigger', () async {
    final directory = ImSdkRelationshipDirectory();
    var shouldFail = true;
    final service = ImSdkRelationshipReconcileService.forTest(
      directory: directory,
      loadFriends: () async {
        if (shouldFail) {
          throw StateError('sdk');
        }
        return <RelationshipFriendEntry>[_friend('a')];
      },
      loadGroups: () async => <RelationshipGroupEntry>[_group('g')],
      canRunNow: () => true,
    );
    await service.requestRelationshipReconcile(reason: 'fail');
    expect(service.friendReconcilePhase, ImSdkRelationshipPhase.idle);
    shouldFail = false;
    await service.requestRelationshipReconcile(reason: 'conversation_sync_finished');
    expect(service.friendReconcilePhase, ImSdkRelationshipPhase.completed);
    expect(directory.hasCompleteFriendSnapshot, isTrue);
  });

  test('first connect is not a reconnect cycle', () async {
    final directory = ImSdkRelationshipDirectory();
    final service = ImSdkRelationshipReconcileService.forTest(
      directory: directory,
      loadFriends: () async => <RelationshipFriendEntry>[_friend('a')],
      loadGroups: () async => <RelationshipGroupEntry>[_group('g')],
      canRunNow: () => true,
    );
    await service.requestFirstSnapshot(reason: 'im_login');
    await service.requestRelationshipReconcile(reason: 'conversation_sync_finished');
    final gets = service.debugFriendGetCount;
    service.onSocketConnectSuccess();
    await Future<void>.delayed(Duration.zero);
    expect(service.debugFriendGetCount, gets);
    expect(service.reconnectEpoch, 0);

    service.onSocketDisconnectedAfterConnected();
    service.onSocketConnectSuccess();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.reconnectEpoch, 1);
    expect(service.debugFriendGetCount, gets + 1);
  });

  test('cold start group list is first plus reconcile only', () async {
    final directory = ImSdkRelationshipDirectory();
    final service = ImSdkRelationshipReconcileService.forTest(
      directory: directory,
      loadFriends: () async => <RelationshipFriendEntry>[_friend('a')],
      loadGroups: () async => <RelationshipGroupEntry>[_group('g')],
      canRunNow: () => true,
    );
    await service.requestFirstSnapshot(reason: 'im_login');
    await service.requestFirstSnapshot(reason: 'enter_my_groups');
    await service.requestRelationshipReconcile(
      reason: 'conversation_sync_finished',
    );
    await service.requestRelationshipReconcile(reason: 'login_delay_fallback');
    expect(service.debugGroupGetCount, 2);
  });

  test('finish and fallback do not double reconcile', () async {
    var pending = true;
    var finished = false;
    final directory = ImSdkRelationshipDirectory();
    final service = ImSdkRelationshipReconcileService.forTest(
      directory: directory,
      loadFriends: () async => <RelationshipFriendEntry>[_friend('a')],
      loadGroups: () async => <RelationshipGroupEntry>[_group('g')],
      isSyncPending: () => pending,
      hasHandledFinish: () => finished,
      canRunNow: () => true,
      fallbackDelay: Duration.zero,
      handshakeTimeout: const Duration(milliseconds: 30),
    );
    await service.requestFirstSnapshot(reason: 'im_login');
    pending = false;
    finished = true;
    await service.requestRelationshipReconcile(
      reason: 'conversation_sync_finished',
    );
    final gets = service.debugFriendGetCount;
    await service.requestRelationshipReconcile(reason: 'login_delay_fallback');
    expect(service.debugFriendGetCount, gets);
  });

  test('groupEntryFromSdk keeps memberCount and role', () {
    final info = V2TimGroupInfo(
      groupID: 'g1',
      groupType: 'Work',
      groupName: 'Alpha',
      memberCount: 17,
      role: 400,
    );
    final entry = ImSdkRelationshipReconcileService.groupEntryFromSdk(info);
    expect(entry.memberCount, 17);
    expect(entry.role, 400);
    expect(entry.toV2TimGroupInfo().memberCount, 17);
  });

  test('overlayFriendDisplay fills nick and face without overwriting SDK remark', () {
    final sdk = ImSdkRelationshipReconcileService.friendEntryFromSdk(
      V2TimFriendInfo(
        userID: 'u1',
        friendRemark: '备注甲',
        userProfile: V2TimUserFullInfo(userID: 'u1'),
      ),
    );
    final overlaid = ImSdkRelationshipReconcileService.overlayFriendDisplay(
      entry: sdk,
      localRemark: '本地备注',
      localNickname: '昵称乙',
      localFaceUrl: 'https://example/a.png',
    );
    expect(overlaid.remark, '备注甲');
    expect(overlaid.nickname, '昵称乙');
    expect(overlaid.faceUrl, 'https://example/a.png');
    expect(overlaid.displayName, '备注甲');
    expect(overlaid.toV2TimFriendInfo().userProfile?.nickName, '昵称乙');
  });
}
