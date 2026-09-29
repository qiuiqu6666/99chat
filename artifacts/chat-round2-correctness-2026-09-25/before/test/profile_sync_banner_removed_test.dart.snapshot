import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile does not render a server sync banner', () {
    final source = File('lib/src/profile.dart').readAsStringSync();

    expect(source, isNot(contains('_buildProfileSyncBanner')));
    expect(source, isNot(contains('正在从服务器同步我的资料')));
    expect(source, isNot(contains('正在同步我的资料')));
    expect(source, contains('AuthApi.instance.fetchMe()'));
  });
}
