import 'package:flutter/widgets.dart';

/// Keeps the primary chat surface at a stable element-tree position while
/// asynchronously discovered floating controls are added or removed.
class ChatStableOverlayStack extends StatelessWidget {
  const ChatStableOverlayStack({
    super.key,
    required this.primary,
    this.overlays = const <Widget>[],
  });

  final Widget primary;
  final List<Widget> overlays;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: <Widget>[primary, ...overlays],
    );
  }
}
