import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_anchor.dart';

/// Keep the selected message at the origin of a centered reverse viewport.
/// Newer rows grow before that origin; older rows grow after it. SDK pages
/// therefore need no correction based on a lazy sliver's estimated height.
int searchHistorySplitIndex(
    List<V2TimMessage?> newestFirst, MessageAnchor anchor) {
  return math.max(0, newestFirst.indexWhere(anchor.matches));
}

/// Space required to center an edge result, reduced by actual sliver extent.
/// Keep the sliver in the tree even when its height reaches zero.
class SearchHistoryEdgeSpace extends StatelessWidget {
  const SearchHistoryEdgeSpace({
    super.key,
    required this.newer,
    this.enabled = true,
  });

  final bool newer;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
        builder: (_, constraints) {
          final viewport = constraints.viewportMainAxisExtent;
          final occupied = constraints.precedingScrollExtent;
          final remaining =
              newer ? viewport / 2 - occupied : (viewport - occupied) / 2;
          return SliverToBoxAdapter(
            child: SizedBox(height: enabled ? math.max(0.0, remaining) : 0),
          );
        },
      );
}
