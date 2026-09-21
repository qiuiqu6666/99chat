import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wide wechat rows keep single-line titles and empty moments value', () {
    final source = File('lib/src/user_profile.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    final rowStart = source.indexOf('Widget _buildWideWeChatRow({');
    final rowEnd = source.indexOf('Widget _buildWideWeChatSection(');
    expect(rowStart, greaterThanOrEqualTo(0));
    expect(rowEnd, greaterThan(rowStart));
    final row = source.substring(rowStart, rowEnd);
    expect(row, contains('width: 108,'));
    expect(row, contains('maxLines: 1,'));

    final settingsStart = source.indexOf('Widget _buildWideProfileSettings(');
    final settingsEnd = source.indexOf('Widget _buildWideFooterActionButton({');
    expect(settingsStart, greaterThanOrEqualTo(0));
    expect(settingsEnd, greaterThan(settingsStart));
    final settings = source.substring(settingsStart, settingsEnd);

    expect(settings, contains("zhHans: '99Chat ID'"));
    expect(settings, contains("zhHant: '99Chat ID'"));
    expect(settings, contains("en: '99Chat ID'"));
    expect(settings, contains("ja: '99Chat ID'"));
    expect(settings, contains("ko: '99Chat ID'"));
    expect(settings, isNot(contains("zhHans: '账号'")));

    expect(settings, contains("value: '\$_commonGroupCount'"));

    final momentsAt = settings.indexOf("zhHans: '朋友圈'");
    expect(momentsAt, greaterThanOrEqualTo(0));
    final momentsEnd = settings.indexOf('_buildWideSwitchRow(', momentsAt);
    expect(momentsEnd, greaterThan(momentsAt));
    final moments = settings.substring(momentsAt, momentsEnd);
    expect(moments, contains("value: ''"));
    expect(moments, isNot(contains('_wideNotSetLabel()')));

    final loadStart = source.indexOf('Future<void> _loadCommonGroupCount() async {');
    final loadEnd = source.indexOf('void _openCommonGroupsPage() {');
    expect(loadStart, greaterThanOrEqualTo(0));
    expect(loadEnd, greaterThan(loadStart));
    final load = source.substring(loadStart, loadEnd);
    expect(load, contains('ProfilePageNav.isSelfUser(widget.userID)'));
    expect(load, isNot(contains('widget.isSelf')));
  });
}
