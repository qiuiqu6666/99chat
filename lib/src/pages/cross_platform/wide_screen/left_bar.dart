import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/cupertino.dart';
import 'package:tencent_cloud_chat_demo/src/conversation.dart';
import 'package:tencent_cloud_chat_demo/src/pages/home_page.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/ui/app_tokens.dart';
import 'package:tencent_cloud_chat_demo/utils/theme.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/user_avatar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_scope_unread_badge.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/friend_request_unread_badge.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';

class LeftBar extends StatefulWidget {
  final int index;
  final ValueChanged<int> onChange;
  final double topInset;

  const LeftBar({
    Key? key,
    required this.index,
    required this.onChange,
    this.topInset = 40,
  }) : super(key: key);

  @override
  State<LeftBar> createState() => _LeftBarState();
}

class _LeftBarState extends State<LeftBar> {
  Color _inactiveIconColor(bool isDark) {
    return AppTokens.desktopNavRailInactive(isDark);
  }

  Widget _badgeOverlay({required Widget icon, required Widget badge}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          top: -5,
          left: 12,
          child: UnconstrainedBox(child: badge),
        ),
      ],
    );
  }

  List<NavigationBarData> getBottomNavigatorList(
      BuildContext context, theme, bool isDark) {
    final primary = theme.primaryColor ?? CommonColor.primaryColor;
    final inactive = _inactiveIconColor(isDark);
    return [
      NavigationBarData(
        index: 0,
        title: '\u6d88\u606f',
        selectedIcon: _badgeOverlay(
          icon: ColorFiltered(
            colorFilter: ColorFilter.mode(primary, BlendMode.srcATop),
            child: Image.asset(
              "assets/chat_active.png",
              width: 24,
              height: 24,
            ),
          ),
          badge: const ConversationScopeUnreadBadge(
            scope: ConversationListScope.c2c,
          ),
        ),
        unselectedIcon: _badgeOverlay(
          icon: ColorFiltered(
            colorFilter: ColorFilter.mode(inactive, BlendMode.srcATop),
            child: Image.asset(
              "assets/chat.png",
              width: 24,
              height: 24,
            ),
          ),
          badge: const ConversationScopeUnreadBadge(
            scope: ConversationListScope.c2c,
          ),
        ),
      ),
      NavigationBarData(
        index: 1,
        title: '\u7fa4\u804a',
        selectedIcon: _badgeOverlay(
          icon: ColorFiltered(
            colorFilter: ColorFilter.mode(primary, BlendMode.srcATop),
            child: Image.asset(
              "assets/group_conv.png",
              width: 24,
              height: 24,
            ),
          ),
          badge: const ConversationScopeUnreadBadge(
            scope: ConversationListScope.group,
          ),
        ),
        unselectedIcon: _badgeOverlay(
          icon: ColorFiltered(
            colorFilter: ColorFilter.mode(inactive, BlendMode.srcATop),
            child: Image.asset(
              "assets/group_conv.png",
              width: 24,
              height: 24,
            ),
          ),
          badge: const ConversationScopeUnreadBadge(
            scope: ConversationListScope.group,
          ),
        ),
      ),
      NavigationBarData(
        index: 2,
        title: '\u901a\u8baf\u5f55',
        selectedIcon: _badgeOverlay(
          icon: ColorFiltered(
            colorFilter: ColorFilter.mode(primary, BlendMode.srcATop),
            child: Image.asset(
              "assets/contact_active.png",
              width: 24,
              height: 24,
            ),
          ),
          badge: const ContactUnreadBadge(
            width: 16,
            height: 16,
          ),
        ),
        unselectedIcon: _badgeOverlay(
          icon: ColorFiltered(
            colorFilter: ColorFilter.mode(inactive, BlendMode.srcATop),
            child: Image.asset(
              "assets/contact.png",
              width: 24,
              height: 24,
            ),
          ),
          badge: const ContactUnreadBadge(
            width: 16,
            height: 16,
          ),
        ),
      ),
      NavigationBarData(
        index: 3,
        title: '\u6211\u7684',
        selectedIcon: ColorFiltered(
          colorFilter: ColorFilter.mode(
            theme.primaryColor ?? hexToColor("3370ff"),
            BlendMode.srcATop,
          ),
          child: Image.asset(
            "assets/profile_active.png",
            width: 24,
            height: 24,
          ),
        ),
        unselectedIcon: ColorFiltered(
          colorFilter: ColorFilter.mode(inactive, BlendMode.srcATop),
          child: Image.asset(
            "assets/profile.png",
            width: 24,
            height: 24,
          ),
        ),
      ),
    ];
  }

  List<Widget> bottomNavigatorList(
      BuildContext context, theme, bool isDark) {
    final selectedBackgroundColor =
        (theme.primaryColor ?? hexToColor("3370ff")).withValues(alpha: 0.22);
    final selectedTextColor = const Color(0xFFFFFFFF);
    final unselectedTextColor = AppTokens.desktopNavRailLabel(isDark);
    return getBottomNavigatorList(context, theme, isDark).map((e) {
      return Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: widget.index == e.index ? selectedBackgroundColor : null,
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: GestureDetector(
          onTap: () {
            widget.onChange(e.index!);
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  child: widget.index == e.index
                      ? e.selectedIcon
                      : e.unselectedIcon,
                ),
                const SizedBox(height: 4),
                Text(
                  e.title,
                  style: TextStyle(
                    color: widget.index == e.index
                        ? selectedTextColor
                        : unselectedTextColor,
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                )
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final themeData = Provider.of<DefaultThemeData>(context);
    final theme = themeData.theme;
    final isDark = themeData.currentThemeType == ThemeType.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        if (widget.topInset > 0)
          SizedBox(
            height: widget.topInset,
            child: MoveWindow(
              child: Container(),
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: bottomNavigatorList(context, theme, isDark),
        ),
        Expanded(
            child: MoveWindow(
          child: Container(),
        )),
        UserAvatar(
          onChangeIndex: widget.onChange,
        ),
      ],
    );
  }
}
