import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat header does not refresh member count from realtime events', () {
    final source = File('lib/src/chat.dart').readAsStringSync();

    expect(source, isNot(contains('_loadGroupMemberCount(force: true)')));
    expect(source, isNot(contains('GroupMetadataRefreshCoordinator.instance.refresh')));
    expect(source, isNot(contains('syncForGroup(')));
    expect(source, isNot(contains('loadGroupMembersForOpenShell')));
    expect(source, contains('GroupLocalStore.instance.commitListenable'));
    expect(source, contains('GroupLocalStore.instance.cacheHydration'));
  });

  test('conversation list rebuilds group identity from Store commits', () {
    final source = File('lib/src/conversation.dart').readAsStringSync();
    expect(source, contains('_onGroupStoreCommitForDisplay'));
    expect(source, contains('GroupLocalStore.instance.commitListenable'));
    expect(
      source,
      contains('ChatSessionController.instance.bumpRowRevisions'),
    );
  });

  test('conversation fingerprint includes local display identity', () {
    final source = File(
      'lib/src/chat_session/conversation_projection_fingerprint.dart',
    ).readAsStringSync();
    expect(source, contains('localDisplayIdentityFragment'));
    expect(source, contains('GroupLocalStore.instance.readCached'));
    expect(source, contains('UserProfileLocalService.instance.readCached'));
  });

  test('membership list sync does not write group metadata memberCount', () {
    final source = File(
      'lib/src/services/group_local/group_membership_sync_service.dart',
    ).readAsStringSync();
    final incremental = File(
      'lib/src/services/group_local/group_member_incremental_sync_service.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('patchMemberCountForSync')));
    expect(source, isNot(contains('memberCount: page.total')));
    expect(source, isNot(contains('incrementIfMissing')));
    expect(incremental, isNot(contains('patchMemberCountForSync')));
  });

  test('realtime membership changes trigger the metadata coordinator', () {
    final source = File(
      'lib/src/services/group_local/group_sync_service.dart',
    ).readAsStringSync();

    expect(
      source,
      contains(RegExp(
        r'GroupMetadataRefreshCoordinator\.instance\s*\.refresh',
      )),
    );
    expect(source, contains('force: true'));
  });

  test('group entity incremental sync is removed', () {
    expect(
      File('lib/src/bootstrap/home_bootstrap.dart').existsSync(),
      isTrue,
    );
    expect(
      File(
        'lib/src/services/group_local/group_entity_incremental_sync_service.dart',
      ).existsSync(),
      isFalse,
    );
    final home =
        File('lib/src/bootstrap/home_bootstrap.dart').readAsStringSync();
    expect(home, isNot(contains('GroupEntityIncrementalSyncService')));
    expect(home, isNot(contains('idle_group_entity_incremental')));
  });
}
