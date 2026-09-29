import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('artifacts/group-name-card-recovery-2026-09-28/baseline/group_profile.dart').readAsStringSync();
  final modelSource = File(
    'artifacts/group-name-card-recovery-2026-09-28/baseline/model.dart',
  ).readAsStringSync();

  test('group profile rebuilds from the versioned GroupLocalStore commit', () {
    expect(source, contains('GroupLocalStore.instance.commitListenable'));
    expect(source, contains('Listenable.merge(<Listenable>['));
  });

  test('Store row owns notice and member count including empty notice', () {
    expect(source, contains('model.displayedMemberCount('));
    expect(source, contains('cachedCount: localRecord?.memberCount'));
    expect(source, contains('GroupDisplayResolver.resolveNoticeFromSources('));
  });

  test('member commits update the loaded profile window', () {
    expect(modelSource, contains('.addListener(_onLocalMemberCommit)'));
    expect(modelSource, contains('_drainDurableMemberProjection'));
    expect(modelSource, contains('replaceGroupSnapshot'));
    expect(modelSource, contains('hasCompleteMemberSnapshot'));
    expect(source, contains('model.displayedMemberCount('));
  });
}
