import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('_getHeaderTitleText no longer concatenates member count', () {
    final source = File('lib/src/chat.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final at = source.indexOf('String _getHeaderTitleText() {');
    expect(at, greaterThanOrEqualTo(0));
    final fn = source.substring(at, source.indexOf('\n  }', at) + 4);
    expect(fn.contains('return _getTitle();'), isTrue);
    expect(fn.contains(r'$showName (${_groupMemberCount'), isFalse);
  });

  test('group header keeps a second member-count row', () {
    final source = File('lib/src/widgets/chat_header_title.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final buildAt = source.indexOf('Widget build(BuildContext context) {');
    expect(buildAt, greaterThanOrEqualTo(0));
    final build = source.substring(buildAt);
    expect(
      build.contains('if (widget.convType == ConvType.group)'),
      isTrue,
    );
    expect(build.contains("zhHans: '{option1}位成员'"), isTrue);
    expect(
      build.contains('SizedBox(\n                      height: AppResponsive.isDesktop(context) ? 16 : 13.2,'),
      isTrue,
    );
    expect(
      build.contains('if (!TUIKitScreenUtils.isWideLayout(context))'),
      isTrue,
    );
  });
}
