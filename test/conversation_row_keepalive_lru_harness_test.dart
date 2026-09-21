import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Anti-regression: `init wantKeepAlive=true` + retain on [State.deactivate]
/// does **not** bound the Sliver keepAlive bucket.
///
/// Flutter moves keepAlive children into the bucket **without** deactivating
/// the Element, so [State.deactivate] never runs `tryRetain` and eviction
/// never fires. Do not "simplify" production retention back to deactivate.
void main() {
  testWidgets(
    'deactivate retain never sees keepAlive bucket entry',
    (tester) async {
      final world = _DeactivateRetainWorld(itemCount: 40);
      await tester.pumpWidget(world.build());
      await tester.pumpAndSettle();

      await world.scrollToIndex(tester, 12);
      await tester.pumpAndSettle();

      expect(
        world.lru.length,
        0,
        reason: 'deactivate is not a keepAlive-bucket enter signal',
      );
      expect(
        world.stats.disposeCount,
        0,
        reason: 'no deactivate → no eviction → no dispose',
      );
    },
  );

  testWidgets(
    'init wantKeepAlive plus deactivate retain grows live states with distance',
    (tester) async {
      final world = _DeactivateRetainWorld(itemCount: 40);
      await tester.pumpWidget(world.build());
      await tester.pumpAndSettle();

      for (var i = 0; i <= 30; i++) {
        await world.scrollToIndex(tester, i);
      }
      await tester.pumpAndSettle();

      expect(
        world.stats.liveCount,
        world.itemCount,
        reason: 'every armed row stays in the keepAlive bucket',
      );
      expect(world.stats.disposeCount, 0);
      expect(
        world.stats.liveCount,
        greaterThan(world.maxLiveBoundIfLruWorked),
        reason: 'live State count tracks scroll distance, not LRU=2',
      );
    },
  );
}

class _DeactivateRetainWorld {
  _DeactivateRetainWorld({this.itemCount = 40});

  static const double itemExtent = 80;
  static const double viewport = 400;
  static const double cacheExtent = 160;
  static const int lruLimit = 2;

  final int itemCount;
  final _RowStats stats = _RowStats();
  final _RetainLru lru = _RetainLru(lruLimit);

  int get maxLiveBoundIfLruWorked =>
      (viewport / itemExtent).ceil() +
      (cacheExtent / itemExtent).ceil() * 2 +
      lruLimit +
      2;

  Widget build() {
    return MaterialApp(
      home: SizedBox(
        height: viewport,
        width: 320,
        child: ListView.builder(
          itemExtent: itemExtent,
          cacheExtent: cacheExtent,
          addAutomaticKeepAlives: true,
          itemCount: itemCount,
          itemBuilder: (context, index) {
            return _DeactivateRetainRow(
              id: index,
              extent: itemExtent,
              stats: stats,
              lru: lru,
            );
          },
        ),
      ),
    );
  }

  Future<void> scrollToIndex(WidgetTester tester, int index) async {
    final list = tester.state<ScrollableState>(find.byType(Scrollable));
    final target = (index * itemExtent).clamp(
      0.0,
      list.position.maxScrollExtent,
    );
    list.position.jumpTo(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }
}

class _RowStats {
  final Map<int, int> init = <int, int>{};
  final Map<int, int> dispose = <int, int>{};
  final Set<int> live = <int>{};

  int initOf(int id) => init[id] ?? 0;
  int disposeOf(int id) => dispose[id] ?? 0;
  int get liveCount => live.length;
  int get disposeCount => dispose.values.fold(0, (a, b) => a + b);
}

class _RetainLru {
  _RetainLru(this.limit);

  final int limit;
  final LinkedHashMap<int, VoidCallback> _ids =
      LinkedHashMap<int, VoidCallback>();

  int get length => _ids.length;

  void tryRetain(int id, VoidCallback onEvicted) {
    _ids.remove(id);
    while (_ids.length >= limit) {
      final oldest = _ids.keys.first;
      final drop = _ids.remove(oldest)!;
      drop();
    }
    _ids[id] = onEvicted;
  }

  void remove(int id) {
    _ids.remove(id);
  }
}

class _DeactivateRetainRow extends StatefulWidget {
  const _DeactivateRetainRow({
    required this.id,
    required this.extent,
    required this.stats,
    required this.lru,
  });

  final int id;
  final double extent;
  final _RowStats stats;
  final _RetainLru lru;

  @override
  State<_DeactivateRetainRow> createState() => _DeactivateRetainRowState();
}

class _DeactivateRetainRowState extends State<_DeactivateRetainRow>
    with AutomaticKeepAliveClientMixin {
  bool _wantKeepAlive = true;

  @override
  bool get wantKeepAlive => _wantKeepAlive;

  @override
  void initState() {
    super.initState();
    widget.stats.init[widget.id] = widget.stats.initOf(widget.id) + 1;
    widget.stats.live.add(widget.id);
  }

  @override
  void deactivate() {
    widget.lru.tryRetain(widget.id, () {
      _wantKeepAlive = false;
      if (mounted) {
        updateKeepAlive();
      }
    });
    super.deactivate();
  }

  @override
  void dispose() {
    widget.stats.live.remove(widget.id);
    widget.stats.dispose[widget.id] = widget.stats.disposeOf(widget.id) + 1;
    widget.lru.remove(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final parentData = context.findRenderObject()?.parentData;
    final keptAlive =
        parentData is KeepAliveParentDataMixin && parentData.keptAlive;
    return SizedBox(
      height: widget.extent,
      child: Text('row-${widget.id} kept=$keptAlive'),
    );
  }
}
