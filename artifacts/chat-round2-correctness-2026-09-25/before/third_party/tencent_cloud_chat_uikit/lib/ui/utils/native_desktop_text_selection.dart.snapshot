import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';

/// Bubbles native-desktop text selection state to the message row so a
/// non-empty selection can suppress the message-level right-click menu.
class NativeDesktopTextSelectionNotification extends Notification {
  const NativeDesktopTextSelectionNotification({
    required this.hasNonEmptySelection,
  });

  final bool hasNonEmptySelection;
}

/// Native desktop only: [SelectionArea] with the system copy menu.
class NativeDesktopSelectableMessageText extends StatefulWidget {
  const NativeDesktopSelectableMessageText({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<NativeDesktopSelectableMessageText> createState() =>
      _NativeDesktopSelectableMessageTextState();
}

class _NativeDesktopSelectableMessageTextState
    extends State<NativeDesktopSelectableMessageText> {
  bool _hasNonEmptySelection = false;

  void _publish(bool hasNonEmptySelection) {
    if (hasNonEmptySelection == _hasNonEmptySelection) {
      return;
    }
    _hasNonEmptySelection = hasNonEmptySelection;
    NativeDesktopTextSelectionNotification(
      hasNonEmptySelection: hasNonEmptySelection,
    ).dispatch(context);
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformUtils().isNativeDesktop) {
      return widget.child;
    }
    return SelectionArea(
      onSelectionChanged: (SelectedContent? content) {
        _publish(content?.plainText.isNotEmpty ?? false);
      },
      child: widget.child,
    );
  }
}
