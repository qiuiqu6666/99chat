import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/home_tab_activity.dart';

/// Creates only tabs the user has opened, then retains their page state.
/// Offstage/TickerMode alone cannot prevent initState, layout or image decode.
class HomeTabStack extends StatefulWidget {
  const HomeTabStack({
    super.key,
    required this.index,
    required this.builders,
    required this.routeVisible,
  });

  final int index;
  final List<WidgetBuilder> builders;
  final bool routeVisible;

  @override
  State<HomeTabStack> createState() => _HomeTabStackState();
}

class _HomeTabStackState extends State<HomeTabStack> {
  final Set<int> _visited = {};

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.index);
    return IndexedStack(
      index: widget.index,
      children: List.generate(widget.builders.length, (index) {
        final active = widget.routeVisible && widget.index == index;
        return HomeTabActivity(
          isActive: active,
          child: TickerMode(
            enabled: active,
            child: IgnorePointer(
              ignoring: !active,
              child: RepaintBoundary(
                child: _visited.contains(index)
                    ? widget.builders[index](context)
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        );
      }),
    );
  }
}
