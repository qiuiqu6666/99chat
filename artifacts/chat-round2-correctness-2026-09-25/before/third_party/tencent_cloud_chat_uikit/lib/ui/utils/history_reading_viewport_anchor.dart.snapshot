import 'package:flutter/rendering.dart';

/// Tracks a real row's sliver layout offset, which excludes user scrolling and
/// does not depend on estimated total extent or post-paint screen transforms.
class HistoryReadingViewportAnchor {
  HistoryReadingViewportAnchor._(this._sliver, this._offset);

  final RenderSliverMultiBoxAdaptor _sliver;
  double _offset;

  static (RenderSliverMultiBoxAdaptor, double)? _location(RenderObject? row) {
    var child = row;
    while (child != null && child.attached) {
      final parent = child.parent;
      if (parent is RenderSliverMultiBoxAdaptor) {
        final data = child.parentData;
        if (data is! SliverMultiBoxAdaptorParentData ||
            data.layoutOffset == null) {
          return null;
        }
        final sign =
            parent.constraints.growthDirection == GrowthDirection.forward
                ? 1.0
                : -1.0;
        return (
          parent,
          sign * (parent.constraints.precedingScrollExtent + data.layoutOffset!)
        );
      }
      child = parent;
    }
    return null;
  }

  static HistoryReadingViewportAnchor? capture(RenderObject? row) {
    final location = _location(row);
    return location == null
        ? null
        : HistoryReadingViewportAnchor._(location.$1, location.$2);
  }

  double? correctionFor(RenderObject? row) {
    final location = _location(row);
    if (location == null || !identical(location.$1, _sliver)) return null;
    final delta = location.$2 - _offset;
    _offset = location.$2;
    return delta.abs() > 0.5 ? delta : 0.0;
  }
}
