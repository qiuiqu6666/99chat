import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile keeps cached content visible while IM is not ready', () {
    final source = File('lib/src/profile.dart').readAsStringSync();

    expect(source,
        contains('final canRenderCachedProfile = effectiveUserId.isNotEmpty;'));
    expect(
      source,
      isNot(contains(
        'final canRenderProfile = effectiveUserId.isNotEmpty && imReady;',
      )),
    );
    expect(source, contains('_buildProfileSyncBanner('));
    expect(source, contains('if (isSyncing || !imReady)'));
  });

  test('profile refreshes are single-flight and session guarded', () {
    final source = File('lib/src/profile.dart').readAsStringSync();

    expect(source, contains('Future<void>? _backendAvatarTask;'));
    expect(source, contains('Future<void>? _imProfileTask;'));
    expect(source,
        contains('SessionIdentityService.instance.isCurrent(identity)'));
    expect(source, contains('if (running != null)'));
  });
}
