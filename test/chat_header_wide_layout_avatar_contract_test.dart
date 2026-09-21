import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ChatHeaderTitle hides avatar only when isWideLayout', () {
    final source = File('lib/src/widgets/chat_header_title.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final buildAt = source.indexOf('Widget build(BuildContext context) {');
    final lastBuildAt = source.lastIndexOf('Widget build(BuildContext context) {');
    expect(buildAt, lastBuildAt);
    expect(buildAt, greaterThanOrEqualTo(0));
    final build = source.substring(buildAt);

    final gateAt = build.indexOf('if (!TUIKitScreenUtils.isWideLayout(context))');
    expect(gateAt, greaterThanOrEqualTo(0));
    final avatarAt = build.indexOf('AppGroupAvatar(');
    final c2cAt = build.indexOf('chat_header_avatar_c2c_');
    final gapAt = build.indexOf('const SizedBox(width: 10)');
    expect(avatarAt, greaterThan(gateAt));
    expect(c2cAt, greaterThan(gateAt));
    expect(gapAt, greaterThan(gateAt));

    final gateSlice = build.substring(gateAt, gateAt + 80);
    expect(gateSlice.contains('getFormFactor'), isFalse);
    expect(gateSlice.contains('isNativeDesktop'), isFalse);
    expect(gateSlice.contains('AppResponsive.isDesktop'), isFalse);
    expect(build.contains('onTap: widget.onTap'), isTrue);
  });
}
