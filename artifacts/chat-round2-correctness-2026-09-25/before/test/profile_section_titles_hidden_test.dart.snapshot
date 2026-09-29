import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile menu section titles stay hidden', () {
    final source = File('lib/src/profile.dart').readAsStringSync();

    for (final title in <String>[
      '我的内容',
      '我的內容',
      '通讯与通知',
      '通訊與通知',
      '应用与系统',
      '應用與系統',
    ]) {
      expect(source.contains(title), isFalse,
          reason: 'Unexpected title: $title');
    }

    expect(source.contains('ProfileMenuIcons.favorites'), isTrue);
    expect(source.contains('ProfileMenuIcons.call'), isTrue);
    expect(source.contains('ProfileMenuIcons.notification'), isTrue);
    expect(source.contains('ProfileMenuIcons.shareApp'), isTrue);
    expect(source.contains('ProfileMenuIcons.settings'), isTrue);
  });
}
