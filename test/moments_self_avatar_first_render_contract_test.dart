import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('moments primes the self avatar from local profile before network', () {
    final source =
        File('lib/src/pages/moments/moments_page.dart').readAsStringSync();

    expect(
      source,
      contains('UserProfileLocalService.instance.read(selfId)'),
    );
    expect(source, contains('AuthApi.instance.fetchMe()'));
    expect(source, contains('saveMeResult(me)'));
    expect(
      source,
      contains('UserAvatarHelper.usableAvatarOrEmpty(liveSelfAvatar)'),
    );
    expect(
      source,
      contains('final selfAvatar = _selfAvatarOverride.isNotEmpty'),
    );
  });

  test('profile passes its loaded self avatar into moments', () {
    final source = File('lib/src/profile.dart').readAsStringSync();

    expect(source, contains('await _loadBackendAvatar();'));
    expect(source, contains('profileAvatarUrl:'));
    expect(source, contains('_backendAvatarUrl.isEmpty ? null'));
  });
}
