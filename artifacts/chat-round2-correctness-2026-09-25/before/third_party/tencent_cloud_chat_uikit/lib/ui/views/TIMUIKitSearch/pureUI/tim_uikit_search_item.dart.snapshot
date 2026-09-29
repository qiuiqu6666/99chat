import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/directory_list_style.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/directory_list_row.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_statelesswidget.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

class TIMUIKitSearchItem extends TIMUIKitStatelessWidget {
  final double horizontalPadding;
  final bool showDivider;
  final String faceUrl;
  final String showName;
  final int avatarType;
  final String lineOne;
  final Widget? lineOneWidget;
  final String? lineOneRight;
  final String? lineTwo;
  final Widget? lineTwoWidget;
  final VoidCallback? onClick;

  TIMUIKitSearchItem(
      {Key? key,
      this.horizontalPadding = 0,
      this.showDivider = true,
      required this.faceUrl,
      required this.showName,
      this.avatarType = 1,
      required this.lineOne,
      this.lineOneWidget,
      this.lineTwo,
      this.lineTwoWidget,
      this.lineOneRight,
      this.onClick})
      : super(key: key);

  static const int _messagePreviewMaxLines = 2;

  Widget _renderLineOneRight(String? text, TUITheme theme) {
    if (text == null || text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: theme.weakTextColor,
        ),
      ),
    );
  }

  Widget _renderLineTwo(
      BuildContext context, String? text, Widget? widgetLine, TUITheme theme) {
    if (widgetLine != null) {
      return DefaultTextStyle.merge(
          style:
              TextStyle(color: theme.weakTextColor, fontSize: 13, height: 1.35),
          maxLines: _messagePreviewMaxLines,
          overflow: TextOverflow.ellipsis,
          child: widgetLine);
    }
    if (text == null || text.isEmpty) {
      return const SizedBox.shrink();
    }
    final preview = Text(
      text,
      maxLines: _messagePreviewMaxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: theme.weakTextColor,
        height: 1.35,
        fontSize: DirectoryListStyle.subtitleSize,
      ),
    );
    return TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop
        ? SelectionArea(child: preview)
        : preview;
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final TUITheme theme = value.theme;

    final titleStyle = TextStyle(
        color: theme.darkTextColor,
        fontSize: DirectoryListStyle.titleSize,
        height: DirectoryListStyle.lineHeight,
        fontWeight: FontWeight.w500);
    final hasSubtitle = lineTwoWidget != null || (lineTwo?.isNotEmpty ?? false);
    return Material(
      color: theme.conversationItemBgColor ?? theme.wideBackgroundColor,
      child: InkWell(
        onTap: onClick,
        child: DirectoryListRow(
          horizontalPadding: horizontalPadding,
          showDivider: showDivider,
          avatar: Avatar(
              faceUrl: faceUrl,
              showName: showName,
              type: avatarType,
              borderRadius: BorderRadius.circular(999),
              isShowBigWhenClick: false),
          title: LayoutBuilder(
              builder: (context, constraints) => Row(children: [
                    Expanded(
                        child: DefaultTextStyle.merge(
                            style: titleStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            child: lineOneWidget ??
                                Text(lineOne,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: titleStyle))),
                    if (lineOneRight?.isNotEmpty ?? false)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * 0.4),
                        child: _renderLineOneRight(lineOneRight, theme),
                      ),
                  ])),
          subtitle: hasSubtitle
              ? _renderLineTwo(context, lineTwo, lineTwoWidget, theme)
              : null,
        ),
      ),
    );
  }
}
