import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/directory_list_style.dart';

/// Matches the group privacy control on every platform.
class GroupSettingsSwitch extends StatelessWidget {
  const GroupSettingsSwitch(
      {super.key,
      required this.value,
      required this.onChanged,
      this.activeColor});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 64,
        child: Align(
            alignment: Alignment.centerRight,
            child: Transform.scale(
                scale: .92,
                child: CupertinoSwitch(
                    value: value,
                    onChanged: onChanged,
                    activeTrackColor: activeColor))),
      );
}

/// Settings keep their controls on the right and ellipsize long labels.
class GroupSettingsTile extends StatelessWidget {
  const GroupSettingsTile(
      {super.key,
      required this.theme,
      required this.title,
      this.subtitle,
      this.leading,
      this.trailing,
      this.onTap,
      this.showDivider = true});

  final TUITheme theme;
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final textHeight = scaler.scale(16) * 1.25 +
        (subtitle == null ? 0 : 4 + scaler.scale(13) * 1.25);
    return Material(
      color: theme.conversationItemBgColor ?? theme.wideBackgroundColor,
      child: InkWell(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ConstrainedBox(
            constraints: BoxConstraints(
                minHeight:
                    math.max(subtitle == null ? 56 : 72, textHeight + 24)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: LayoutBuilder(
                  builder: (context, constraints) => Row(children: [
                        if (leading != null) ...[
                          leading!,
                          const SizedBox(width: 12)
                        ],
                        Expanded(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(title,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 16,
                                      height: 1.25,
                                      fontWeight: FontWeight.w400,
                                      color: theme.darkTextColor)),
                              if (subtitle != null) ...[
                                const SizedBox(height: 4),
                                Text(subtitle!,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 13,
                                        height: 1.25,
                                        color: theme.weakTextColor)),
                              ],
                            ])),
                        if (trailing != null) ...[
                          const SizedBox(width: 12),
                          ConstrainedBox(
                              constraints: BoxConstraints(
                                  maxWidth: constraints.maxWidth * .45),
                              child: trailing),
                        ],
                      ])),
            ),
          ),
          if (showDivider)
            Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Divider(
                    height: .6,
                    thickness: .6,
                    color: DirectoryListStyle.dividerColor(context))),
        ]),
      ),
    );
  }
}
