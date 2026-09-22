import 'dart:math' as math;
import 'dart:ui';

/// Two-dimensional source regions. Zoom changes sampling, never the logical
/// image geometry; the viewer's transform owns visual zoom and translation.
class ImagePreviewRegionGrid {
  ImagePreviewRegionGrid(
      {required this.source,
      required this.display,
      required double pixelRatio,
      required double zoom}) {
    final requested = (display.width / source.width) * pixelRatio * zoom;
    // Powers of two prevent restarting every request on every pinch frame.
    sampling = math.min(
        1.0,
        math
            .pow(2, (math.log(requested.clamp(1e-12, 1e12)) / math.ln2).ceil())
            .toDouble());
    sourceSide = math.max(1, (tileSide / sampling).floor());
    columns = (source.width / sourceSide).ceil();
    rows = (source.height / sourceSide).ceil();
  }

  static const int tileSide = 512;
  final Size source;
  final Size display;
  late final double sampling;
  late final int sourceSide;
  late final int columns;
  late final int rows;
  String get signature => '${source.width}:${source.height}:$sourceSide';

  Rect sourceRect(int index) {
    final x = (index % columns) * sourceSide;
    final y = (index ~/ columns) * sourceSide;
    return Rect.fromLTWH(
        x.toDouble(),
        y.toDouble(),
        math.min(sourceSide.toDouble(), source.width - x),
        math.min(sourceSide.toDouble(), source.height - y));
  }

  Size decodeSize(int index) {
    final rect = sourceRect(index);
    return Size((rect.width * sampling).ceil().clamp(1, tileSide).toDouble(),
        (rect.height * sampling).ceil().clamp(1, tileSide).toDouble());
  }

  Rect displayRect(int index) {
    final rect = sourceRect(index);
    final scale = display.width / source.width;
    return Rect.fromLTWH(rect.left * scale, rect.top * scale,
        rect.width * scale, rect.height * scale);
  }

  List<int> visible(Rect viewport, {int limit = 48}) {
    final clipped = viewport.intersect(Offset.zero & display);
    if (clipped.isEmpty) return const [];
    final side = sourceSide * display.width / source.width;
    final left = (clipped.left / side).floor().clamp(0, columns - 1);
    final right = (clipped.right / side).ceil().clamp(1, columns);
    final top = (clipped.top / side).floor().clamp(0, rows - 1);
    final bottom = (clipped.bottom / side).ceil().clamp(1, rows);
    // Walk from the visible center outward without allocating a list for
    // millions of regions when given an extreme image or display resolution.
    final cx = ((left + right - 1) / 2).floor();
    final cy = ((top + bottom - 1) / 2).floor();
    final result = <int>[];
    for (var radius = 0; result.length < limit; radius++) {
      var any = false;
      for (var y = math.max(top, cy - radius);
          y <= math.min(bottom - 1, cy + radius);
          y++) {
        for (var x = math.max(left, cx - radius);
            x <= math.min(right - 1, cx + radius);
            x++) {
          if (math.max((x - cx).abs(), (y - cy).abs()) != radius) continue;
          any = true;
          result.add(y * columns + x);
          if (result.length == limit) return result;
        }
      }
      if (!any) break;
    }
    return result;
  }
}
