import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String readNormalized(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('conversation share picker opens desktop dialog and keeps friend rows', () {
    final source = readNormalized(
      'lib/src/widgets/conversation_share_picker_page.dart',
    );

    final openAt = source.indexOf('static Future<ConversationShareTarget?> open(');
    expect(openAt, greaterThanOrEqualTo(0));
    final openEnd = source.indexOf(
      'State<ConversationSharePickerPage> createState()',
      openAt,
    );
    expect(openEnd, greaterThan(openAt));
    final open = source.substring(openAt, openEnd);
    expect(open, contains('DesktopModalLayout.isDesktop'));
    expect(open, contains('TUIKitWidePopup.isShow'));
    expect(open, contains('DesktopModalLayout.large'));
    expect(open, contains('Navigator('));
    expect(open, contains('hideAppBar: true'));

    expect(source, contains('final bool hideAppBar;'));
    expect(source, contains('if (!widget.embedded)'));

    final rowsAt = source.indexOf("zhHans: '选择朋友'");
    expect(rowsAt, greaterThanOrEqualTo(0));
    final rowsStart = source.lastIndexOf('if (!widget.embedded)', rowsAt);
    expect(rowsStart, greaterThanOrEqualTo(0));
    expect(source.substring(rowsStart, rowsAt), contains('if (!widget.embedded)'));
  });

  test('profile and qr share pickers use shared open helper', () {
    final profile = readNormalized('lib/src/user_profile.dart');
    final qr = readNormalized('lib/src/qr_code_page.dart');

    expect(profile, contains('ConversationSharePickerPage.open('));
    expect(profile, isNot(contains('_ShareContactPickerPage')));
    expect(qr, contains('ConversationSharePickerPage.open('));
    expect(qr, isNot(contains('_QRCodeSharePickerPage')));

    final buildAt = qr.indexOf('Widget build(BuildContext context) {');
    expect(buildAt, greaterThanOrEqualTo(0));
    final build = qr.substring(buildAt);
    expect(build, contains('if (!widget.embedded)'));
    expect(build, contains('Navigator('));
  });
}
