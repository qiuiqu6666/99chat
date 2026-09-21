import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:provider/provider.dart';

class DesktopConversationMenuItem {
  const DesktopConversationMenuItem({
    required this.label,
    required this.onSelect,
    this.destructive = false,
  });

  final String label;
  final FutureOr<void> Function() onSelect;
  final bool destructive;
}

Future<void> showDesktopConversationContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required List<DesktopConversationMenuItem> items,
}) async {
  if (items.isEmpty) {
    return;
  }
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) {
    return;
  }
  final theme = Provider.of<DefaultThemeData>(context, listen: false).theme;
  final selected = await showMenu<int>(
    context: context,
    elevation: 8,
    color: theme.wideBackgroundColor ??
        theme.conversationItemBgColor ??
        Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    position: RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      overlay.size.width - globalPosition.dx,
      overlay.size.height - globalPosition.dy,
    ),
    items: [
      for (var i = 0; i < items.length; i++)
        PopupMenuItem<int>(
          value: i,
          height: 36,
          child: Text(
            items[i].label,
            style: TextStyle(
              fontSize: 14,
              height: 1.25,
              color: items[i].destructive
                  ? const Color(0xFFE53935)
                  : (theme.darkTextColor ??
                      theme.conversationItemTitleTextColor),
            ),
          ),
        ),
    ],
  );
  if (selected == null || !context.mounted) {
    return;
  }
  await items[selected].onSelect();
}
