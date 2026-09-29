import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/ui/app_tokens.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/user_profile/user_profile_game_admin_panel.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/user_profile/user_profile_game_ledger_sheet.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

/// 宽屏资料页右侧：仅特权用户可见的三公管理栏。
class UserProfileGamePrivilegeSideColumn extends StatelessWidget {
  const UserProfileGamePrivilegeSideColumn({
    super.key,
    required this.theme,
    required this.targetUserId,
    required this.displayName,
  });

  final TUITheme theme;
  final String targetUserId;
  final String displayName;

  static const double width = 360;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final bg = theme.conversationItemBgColor ??
        theme.wideBackgroundColor ??
        Colors.white;
    final headerBg = theme.appbarBgColor ?? bg;
    final textColor = theme.darkTextColor ?? AppTokens.textPrimaryLight;
    final line = theme.weakDividerColor ?? AppTokens.borderLight;

    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            left: BorderSide(color: line.withValues(alpha: 0.9)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              decoration: BoxDecoration(
                color: headerBg,
                border: Border(
                  bottom: BorderSide(color: line.withValues(alpha: 0.85)),
                ),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                i18n.t(
                  zhHans: '游戏管理',
                  zhHant: '遊戲管理',
                  en: 'Game Admin',
                  ja: 'ゲーム管理',
                  ko: '게임 관리',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            UserProfileGameAdminPanel(
              targetUserId: targetUserId,
              displayName: displayName,
              embedded: true,
            ),
            Expanded(
              child: UserProfileGameLedgerSheet(
                imUserId: targetUserId,
                displayName: displayName,
                embedded: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
