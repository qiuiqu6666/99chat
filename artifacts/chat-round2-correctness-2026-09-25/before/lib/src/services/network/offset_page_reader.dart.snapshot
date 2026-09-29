/// Read offset pages to a short terminal page. Fail atomically if the server
/// repeats a full page, rather than publishing a partial snapshot as complete.
Future<List<T>> readAllOffsetPages<T>({
  required Future<List<T>> Function(int offset, int limit) load,
  required Object Function(T item) identity,
  int limit = 100,
  int maxPages = 10000,
}) async {
  final rows = <Object, T>{};
  var offset = 0;
  for (var pageIndex = 0; pageIndex < maxPages; pageIndex++) {
    final page = await load(offset, limit);
    final before = rows.length;
    for (final item in page) {
      rows[identity(item)] = item;
    }
    if (page.length < limit) return rows.values.toList();
    if (rows.length == before) {
      throw StateError('offset pagination made no progress');
    }
    offset += page.length;
  }
  throw StateError('offset pagination exceeded page budget');
}
