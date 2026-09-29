/// Stable merge after sorting only the new run. Geometric publication keeps
/// the sum of prefix copies linear while construction can yield every slice.
List<T> mergeContactProjection<T>(
    List<T> current, List<T> added, int Function(T, T) compare) {
  final next = List<T>.of(added)..sort(compare);
  final merged = <T>[];
  var a = 0;
  var b = 0;
  while (a < current.length && b < next.length) {
    if (compare(current[a], next[b]) <= 0) {
      merged.add(current[a++]);
    } else {
      merged.add(next[b++]);
    }
  }
  merged.addAll(current.skip(a));
  merged.addAll(next.skip(b));
  return merged;
}

int contactProjectionPublishSize(int published, {int firstScreen = 80}) =>
    published < firstScreen ? firstScreen : published;
