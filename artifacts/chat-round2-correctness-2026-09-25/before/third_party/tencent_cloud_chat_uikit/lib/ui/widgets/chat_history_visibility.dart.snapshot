import 'package:flutter/widgets.dart';

/// Keep the scroll tree mounted while a search jump measures hidden rows.
/// Removing the Opacity/IgnorePointer wrappers at reveal would replace the
/// Scrollable and discard the position that was just verified.
class ChatHistoryVisibility extends StatelessWidget {
  const ChatHistoryVisibility({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: visible ? 1 : 0,
        child: IgnorePointer(ignoring: !visible, child: child),
      );
}
