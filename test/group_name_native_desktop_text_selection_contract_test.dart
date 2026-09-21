import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String buildCard;
  late String memberRow;

  setUpAll(() {
    final source = File('lib/src/pages/group_chat_settings_side_card.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final cardAt = source.indexOf('Widget _buildCard(');
    final memberAt = source.indexOf('Widget _memberRow({');
    expect(cardAt, greaterThanOrEqualTo(0));
    expect(memberAt, greaterThan(cardAt));
    buildCard = source.substring(cardAt, memberAt);
    memberRow = source.substring(memberAt);
  });

  test('_buildCard wraps group name for native desktop selection', () {
    expect(
      buildCard.contains('NativeDesktopSelectableMessageText('),
      isTrue,
    );
    expect(
      buildCard.contains('child: Text(\n                        name,'),
      isTrue,
    );
    expect(buildCard.contains('if (PlatformUtils().isNativeDesktop)'), isTrue);
    expect(buildCard.contains('ScrollConfiguration'), isTrue);
    expect(buildCard.contains('PointerDeviceKind.mouse'), isTrue);
    expect(
      buildCard.contains('NotificationListener<ScrollNotification>'),
      isTrue,
    );
    expect(buildCard.contains('_maybeLoadMoreMembers'), isTrue);
  });

  test('_memberRow is not wrapped for text selection', () {
    expect(
      memberRow.contains('NativeDesktopSelectableMessageText('),
      isFalse,
    );
    expect(memberRow.contains('widget.onOpenUser(userId)'), isTrue);
  });
}
