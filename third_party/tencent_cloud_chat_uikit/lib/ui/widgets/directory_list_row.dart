import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/directory_list_style.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';

/// Shared layout for people, picker results and notices. Uses a minimum height
/// so translated actions and scaled text can grow without clipping.
class DirectoryListRow extends StatelessWidget {
  const DirectoryListRow({
    super.key,
    required this.avatar,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.horizontalPadding = 16,
    this.showDivider = true,
  });

  final Widget avatar;
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final double horizontalPadding;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final desktop =
        TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;
    final avatarSize = DirectoryListStyle.avatarSize(desktop);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: DirectoryListStyle.rowHeight(context, desktop: desktop) -
              DirectoryListStyle.dividerThickness,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: DirectoryListStyle.verticalPadding,
          ),
          child: LayoutBuilder(builder: (context, constraints) {
            final stackTrailing = trailing != null &&
                (constraints.maxWidth < 320 ||
                    MediaQuery.textScalerOf(context).scale(16) > 22);
            return Row(children: [
              if (leading != null) ...[
                SizedBox(width: 32, child: Center(child: leading)),
                const SizedBox(width: 8),
              ],
              SizedBox(width: avatarSize, height: avatarSize, child: avatar),
              const SizedBox(width: DirectoryListStyle.avatarTextGap),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    if (subtitle != null) ...[
                      const SizedBox(height: DirectoryListStyle.textGap),
                      subtitle!,
                    ],
                    if (stackTrailing) ...[
                      const SizedBox(height: 6),
                      trailing!,
                    ],
                  ],
                ),
              ),
              if (trailing != null && !stackTrailing) ...[
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: constraints.maxWidth * .32),
                  child: trailing,
                ),
              ],
            ]);
          }),
        ),
      ),
      if (showDivider)
        Padding(
          padding: EdgeInsets.only(
            left: horizontalPadding +
                (leading == null ? 0 : 40) +
                avatarSize +
                DirectoryListStyle.avatarTextGap,
          ),
          child: Divider(
            height: DirectoryListStyle.dividerThickness,
            thickness: DirectoryListStyle.dividerThickness,
            color: DirectoryListStyle.dividerColor(context),
          ),
        ),
    ]);
  }
}

class DirectoryStatusLabel extends StatelessWidget {
  const DirectoryStatusLabel(
      {super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: color,
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w500)),
      );
}

enum DirectoryActionTone { primary, secondary }

/// Compact list-row action shared by friend requests and group notices.
class DirectoryActionButton extends StatelessWidget {
  const DirectoryActionButton({
    super.key,
    required this.label,
    required this.primaryColor,
    required this.onPressed,
    this.tone = DirectoryActionTone.primary,
    this.loading = false,
  });

  final String label;
  final Color primaryColor;
  final VoidCallback? onPressed;
  final DirectoryActionTone tone;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = !loading && onPressed != null;
    final primary = tone == DirectoryActionTone.primary;
    final foreground = primary ? Colors.white : primaryColor;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 64, minHeight: 34),
        child: Material(
          color: primary ? primaryColor : Colors.transparent,
          shape: StadiumBorder(
            side: primary
                ? BorderSide.none
                : BorderSide(color: primaryColor.withValues(alpha: .28)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: loading
                    ? SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: foreground,
                        ),
                      )
                    : Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 14,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum DirectoryStatusKind { accepted, rejected, pending, notice, neutral }

/// Passive list-row state. It intentionally has no gesture handler so it
/// cannot be mistaken for an action button.
class DirectoryStatusBadge extends StatelessWidget {
  const DirectoryStatusBadge({
    super.key,
    required this.label,
    required this.textColor,
    required this.backgroundColor,
    this.kind = DirectoryStatusKind.neutral,
  });

  final String label;
  final Color textColor;
  final Color backgroundColor;
  final DirectoryStatusKind kind;

  IconData get _icon => switch (kind) {
        DirectoryStatusKind.accepted => Icons.check_rounded,
        DirectoryStatusKind.rejected => Icons.close_rounded,
        DirectoryStatusKind.pending => Icons.schedule_rounded,
        DirectoryStatusKind.notice => Icons.notifications_none_rounded,
        DirectoryStatusKind.neutral => Icons.info_outline_rounded,
      };

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        child: Container(
          constraints: const BoxConstraints(minHeight: 30),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, size: 15, color: textColor),
              const SizedBox(width: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
}
