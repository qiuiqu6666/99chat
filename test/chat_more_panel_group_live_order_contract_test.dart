import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('group live icon is tinted and occupies the eighth group slot', () {
    final chatSource = File('lib/src/chat.dart').readAsStringSync();
    final panelSource = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKitTextField/tim_uikit_more_panel.dart',
    ).readAsStringSync();

    expect(
      chatSource.contains(
        "MorePanelStyles.pngIcon(theme, 'assets/chat_more/group_live.png')",
      ),
      isTrue,
    );
    expect(panelSource.contains('color: iconColor(theme)'), isTrue);
    expect(
      panelSource.contains('colorBlendMode: BlendMode.srcIn'),
      isTrue,
    );

    final configStart =
        chatSource.indexOf('MorePanelConfig _buildMorePanelConfig');
    expect(configStart, greaterThanOrEqualTo(0));
    final configSource = chatSource.substring(configStart);
    final contact =
        configSource.indexOf('_buildContactCardMorePanelItems(theme)');
    final favorite =
        configSource.indexOf('_buildFavoriteMorePanelItems(theme)');
    final wallet = configSource.indexOf('_buildWalletMorePanelItems(theme)');
    final groupLive = configSource.indexOf('...groupLiveItems,');
    expect(contact, greaterThanOrEqualTo(0));
    expect(favorite, greaterThan(contact));
    expect(wallet, greaterThan(favorite));
    expect(groupLive, greaterThan(wallet));
  });

  test('group live menu is restricted to managers and keyed by permission', () {
    final source = File('lib/src/chat.dart').readAsStringSync();
    final start = source.indexOf('bool _canShowGroupLiveMenu()');
    final end = source.indexOf('void _seedGroupLiveFromIndex()', start);
    final menu = source.substring(start, end);
    expect(menu, contains('GroupRolePolicy.isManagerRole(role)'));
    expect(menu, contains('if (!_canShowGroupLiveMenu())'));
    expect(menu, contains('await GroupInfoResolver.instance.myRole(groupId)'));
    expect(source, contains(r'groupLiveMenu:${_canShowGroupLiveMenu()}'));
  });
}
