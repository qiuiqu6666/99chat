import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';

/// Shared search entry for the conversation and contacts tabs.
class ConversationSearchBar extends StatelessWidget {
  const ConversationSearchBar({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<DefaultThemeData>(context).theme;
    final iconColor =
        (theme.appbarTextColor ?? const Color(0xFF979797)).withValues(alpha: 0.7);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: theme.appbarBgColor ?? Colors.white,
          boxShadow: const [],
          border: Border(
            bottom: BorderSide(
              color: theme.weakDividerColor ?? const Color(0xFFE5E6E9),
              width: 0.6,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Container(
            decoration: BoxDecoration(
              color: theme.inputFillColor ?? const Color(0xFFF7F7F8),
              borderRadius: const BorderRadius.all(Radius.circular(10)),
            ),
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.search, color: iconColor, size: 19),
                  const SizedBox(width: 8),
                  Text(
                    AppI18n.of(context).t(
                      zhHans: '搜索',
                      zhHant: '搜尋',
                      en: 'Search',
                      ja: '検索',
                      ko: '검색',
                    ),
                    style: TextStyle(
                      color: iconColor,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
