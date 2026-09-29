import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// Feed-level single post-layout probe of [KeepAliveParentDataMixin.keptAlive].
///
/// One [ConversationRowRetention]-shaped owner holds [mountedHosts] and runs
/// at most one probe per frame. Rows must not register their own post-frame
/// callbacks. Evict → dispose may take a later sliver GC; tests pump until
/// that GC, they do not expect dispose on the evict frame.
void main() {
  testWidgets('scroll out row0: keptAlive, retained, not disposed', (
    tester,
  ) async {
    final world = _ProbeWorld();
    await tester.pumpWidget(world.build());
    await world.pumpProbe(tester);

    expect(world.stats.initOf(0), 1);
    expect(world.stats.disposeOf(0), 0);

    await world.scrollToIndex(tester, 3);
    expect(world.host(0)?.isKeptAlive, isTrue);
    expect(world.owner.lruContains(0), isTrue);
    expect(world.stats.disposeOf(0), 0);
    expect(world.stats.live.contains(0), isTrue);
  });

  testWidgets('scroll out row1 then row2: evict row0 and dispose after GC', (
    tester,
  ) async {
    final world = _ProbeWorld();
    await tester.pumpWidget(world.build());
    await world.pumpProbe(tester);

    await world.scrollToIndex(tester, 3);
    expect(world.owner.lruContains(0), isTrue);

    await world.scrollToIndex(tester, 4);
    expect(world.owner.lruContains(1), isTrue);

    await world.scrollToIndex(tester, 5);
    expect(world.owner.lruContains(0), isFalse);
    final evicted = world.host(0);
    if (evicted != null) {
      expect(evicted.wantKeepAliveValue, isFalse);
    }

    await world.pumpUntilDisposed(tester, 0);
    expect(world.stats.disposeOf(0), 1);
    expect(world.stats.live.contains(0), isFalse);
    expect(world.owner.lruLength, lessThanOrEqualTo(_ProbeWorld.lruLimit));
    expect(world.stats.liveCount, lessThanOrEqualTo(world.maxLiveBound));
  });

  testWidgets('scroll back reuses kept State without a new initState', (
    tester,
  ) async {
    final world = _ProbeWorld();
    await tester.pumpWidget(world.build());
    await world.pumpProbe(tester);

    final firstInit = world.stats.initOf(0);
    await world.scrollToIndex(tester, 3);
    await world.scrollToIndex(tester, 0);

    expect(world.stats.initOf(0), firstInit);
    expect(world.stats.live.contains(0), isTrue);
  });

  testWidgets(
    'scrolling past 30 items keeps liveStateCount bounded',
    (tester) async {
      final world = _ProbeWorld(itemCount: 40);
      await tester.pumpWidget(world.build());
      await world.pumpProbe(tester);

      for (var i = 0; i <= 30; i++) {
        await world.scrollToIndex(tester, i);
      }

      expect(world.owner.lruLength, lessThanOrEqualTo(_ProbeWorld.lruLimit));
      expect(
        world.stats.liveCount,
        lessThanOrEqualTo(world.maxLiveBound),
        reason: 'live states must not grow linearly with scroll distance',
      );
    },
  );

  testWidgets(
    'ten round-trips: reuse recent rows, init does not keep growing',
    (tester) async {
      final world = _ProbeWorld(itemCount: 24);
      await tester.pumpWidget(world.build());
      await world.pumpProbe(tester);

      for (var round = 0; round < 10; round++) {
        await world.scrollToIndex(tester, 8);
        await world.scrollToIndex(tester, 3);
      }

      expect(world.stats.liveCount, lessThanOrEqualTo(world.maxLiveBound));
      expect(
        world.stats.initCount,
        lessThanOrEqualTo(world.maxInitAfterRoundTrips),
      );
      expect(
        world.stats.disposeCount,
        world.owner.evictionCount,
        reason: 'final dispose count should match eviction after GC pumps',
      );
    },
  );
}

class _ProbeWorld {
  _ProbeWorld({this.itemCount = 40});

  static const double itemExtent = 80;
  static const double viewport = 400;
  static const double cacheExtent = 160;
  static const int lruLimit = 2;

  final int itemCount;
  final _RowStats stats = _RowStats();
  final ScrollController controller = ScrollController();
  late final _ProbeOwner owner = _ProbeOwner(limit: lruLimit);

  int get viewportRows => (viewport / itemExtent).ceil();
  int get cacheRows => (cacheExtent / itemExtent).ceil();
  int get maxLiveBound => viewportRows + cacheRows * 2 + lruLimit + 4;
  int get maxInitAfterRoundTrips =>
      10 * (viewportRows + cacheRows * 2);

  _ProbeRowState? host(int id) => owner.hostById(id);

  Widget build() {
    return MaterialApp(
      home: SizedBox(
        height: viewport,
        width: 320,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            owner.scheduleProbe();
            return false;
          },
          child: ListView.builder(
            controller: controller,
            itemExtent: itemExtent,
            cacheExtent: cacheExtent,
            addAutomaticKeepAlives: true,
            itemCount: itemCount,
            itemBuilder: (context, index) {
              return _ProbeRow(
                id: index,
                extent: itemExtent,
                stats: stats,
                owner: owner,
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> pumpProbe(WidgetTester tester) async {
    owner.scheduleProbe();
    await tester.pump();
    await tester.pump();
  }

  Future<void> scrollToIndex(WidgetTester tester, int index) async {
    final target = (index * itemExtent).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    controller.jumpTo(target);
    owner.scheduleProbe();
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> pumpUntilDisposed(WidgetTester tester, int id) async {
    for (var i = 0; i < 8; i++) {
      if (worldDisposed(id)) {
        return;
      }
      owner.scheduleProbe();
      await tester.pump();
    }
  }

  bool worldDisposed(int id) => stats.disposeOf(id) > 0;
}

class _ProbeOwner {
  _ProbeOwner({required this.limit});

  final int limit;
  final Set<_ProbeRowState> mountedHosts = <_ProbeRowState>{};
  final LinkedHashMap<int, _ProbeRowState> _lru =
      LinkedHashMap<int, _ProbeRowState>();
  bool _probeScheduled = false;
  int evictionCount = 0;

  int get lruLength => _lru.length;

  bool lruContains(int id) => _lru.containsKey(id);

  _ProbeRowState? hostById(int id) {
    for (final host in mountedHosts) {
      if (host.widget.id == id) {
        return host;
      }
    }
    return null;
  }

  void register(_ProbeRowState host) {
    mountedHosts.add(host);
    scheduleProbe();
  }

  void unregister(_ProbeRowState host) {
    mountedHosts.remove(host);
    _lru.remove(host.widget.id);
  }

  void scheduleProbe() {
    if (_probeScheduled) {
      return;
    }
    _probeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _probeScheduled = false;
      probe();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void probe() {
    final kept = <_ProbeRowState>[];
    for (final host in mountedHosts) {
      if (!host.mounted) {
        continue;
      }
      if (host.isKeptAlive) {
        kept.add(host);
      } else {
        _lru.remove(host.widget.id);
      }
    }
    for (final host in kept) {
      _tryRetain(host);
    }
  }

  void _tryRetain(_ProbeRowState host) {
    final id = host.widget.id;
    _lru.remove(id);
    while (_lru.length >= limit) {
      final oldestId = _lru.keys.first;
      final oldest = _lru.remove(oldestId)!;
      evictionCount += 1;
      oldest.dropKeepAlive();
    }
    _lru[id] = host;
  }
}

class _RowStats {
  final Map<int, int> init = <int, int>{};
  final Map<int, int> dispose = <int, int>{};
  final Set<int> live = <int>{};

  int initOf(int id) => init[id] ?? 0;
  int disposeOf(int id) => dispose[id] ?? 0;
  int get liveCount => live.length;
  int get initCount => init.values.fold(0, (a, b) => a + b);
  int get disposeCount => dispose.values.fold(0, (a, b) => a + b);
}

class _ProbeRow extends StatefulWidget {
  const _ProbeRow({
    required this.id,
    required this.extent,
    required this.stats,
    required this.owner,
  });

  final int id;
  final double extent;
  final _RowStats stats;
  final _ProbeOwner owner;

  @override
  State<_ProbeRow> createState() => _ProbeRowState();
}

class _ProbeRowState extends State<_ProbeRow>
    with AutomaticKeepAliveClientMixin {
  bool _wantKeepAlive = true;

  bool get wantKeepAliveValue => _wantKeepAlive;

  @override
  bool get wantKeepAlive => _wantKeepAlive;

  bool get isKeptAlive {
    RenderObject? node = context.findRenderObject();
    while (node != null) {
      final parentData = node.parentData;
      if (parentData is KeepAliveParentDataMixin) {
        return parentData.keptAlive;
      }
      node = node.parent;
    }
    return false;
  }

  void dropKeepAlive() {
    if (!_wantKeepAlive) {
      return;
    }
    _wantKeepAlive = false;
    if (mounted) {
      updateKeepAlive();
    }
  }

  @override
  void initState() {
    super.initState();
    widget.stats.init[widget.id] = widget.stats.initOf(widget.id) + 1;
    widget.stats.live.add(widget.id);
    widget.owner.register(this);
  }

  @override
  void dispose() {
    widget.owner.unregister(this);
    widget.stats.live.remove(widget.id);
    widget.stats.dispose[widget.id] = widget.stats.disposeOf(widget.id) + 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SizedBox(
      height: widget.extent,
      child: Text('row-${widget.id}'),
    );
  }
}
