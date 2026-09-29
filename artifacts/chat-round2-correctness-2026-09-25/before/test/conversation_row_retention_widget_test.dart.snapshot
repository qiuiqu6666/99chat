import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_row_retention.dart';

void main() {
  setUp(() {
    ConversationPerfFlags.debugConversationRowRetentionOverride = true;
  });

  tearDown(() {
    ConversationPerfFlags.debugConversationRowRetentionOverride = null;
  });

  testWidgets('off: leaving near cache disposes and remount inits again', (
    tester,
  ) async {
    ConversationPerfFlags.debugConversationRowRetentionOverride = false;
    final world = _HostWorld();
    await tester.pumpWidget(world.build());
    await tester.pumpAndSettle();
    expect(world.inits[0], 1);

    await world.scrollToIndex(tester, 8);
    expect(world.disposes[0] ?? 0, greaterThan(0));

    await world.scrollToIndex(tester, 0);
    expect(world.inits[0], greaterThan(1));
    world.retention.dispose();
  });

  testWidgets('on: keptAlive row is reused until LRU evicts and GC disposes', (
    tester,
  ) async {
    final world = _HostWorld();
    await tester.pumpWidget(world.build());
    await world.pumpProbe(tester);

    expect(world.inits[0], 1);
    await world.scrollToIndex(tester, 3);
    expect(world.disposes[0] ?? 0, 0);
    expect(world.inits[0], 1);

    await world.scrollToIndex(tester, 4);
    await world.scrollToIndex(tester, 5);
    await world.pumpUntilDisposed(tester, 0);
    expect(world.disposes[0], 1);
    expect(world.retention.keepAliveCount, lessThanOrEqualTo(2));
    world.retention.dispose();
  });
}

class _HostWorld {
  static const double itemExtent = 80;
  static const double viewport = 400;
  static const double cacheExtent = 160;

  final ConversationRowRetention retention = ConversationRowRetention(limit: 2);
  final ScrollController controller = ScrollController();
  final Map<int, int> inits = <int, int>{};
  final Map<int, int> disposes = <int, int>{};

  Widget build() {
    final retain = ConversationPerfFlags.conversationRowRetentionEnabled;
    return MaterialApp(
      home: SizedBox(
        height: viewport,
        width: 320,
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) {
            retention.scheduleProbe();
            return false;
          },
          child: ListView.builder(
            controller: controller,
            itemExtent: itemExtent,
            cacheExtent: cacheExtent,
            addAutomaticKeepAlives: retain,
            itemCount: 40,
            itemBuilder: (context, index) {
              final identity = 'row_$index';
              final child = _CountRow(
                id: index,
                extent: itemExtent,
                inits: inits,
                disposes: disposes,
              );
              if (!retain) {
                return child;
              }
              return ConversationRowRetentionHost(
                key: ValueKey(identity),
                identity: identity,
                retention: retention,
                child: child,
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> pumpProbe(WidgetTester tester) async {
    retention.scheduleProbe();
    await tester.pump();
    await tester.pump();
  }

  Future<void> scrollToIndex(WidgetTester tester, int index) async {
    final target = (index * itemExtent).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    controller.jumpTo(target);
    retention.scheduleProbe();
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> pumpUntilDisposed(WidgetTester tester, int id) async {
    for (var i = 0; i < 8; i++) {
      if ((disposes[id] ?? 0) > 0) {
        return;
      }
      retention.scheduleProbe();
      await tester.pump();
    }
  }
}

class _CountRow extends StatefulWidget {
  const _CountRow({
    required this.id,
    required this.extent,
    required this.inits,
    required this.disposes,
  });

  final int id;
  final double extent;
  final Map<int, int> inits;
  final Map<int, int> disposes;

  @override
  State<_CountRow> createState() => _CountRowState();
}

class _CountRowState extends State<_CountRow> {
  @override
  void initState() {
    super.initState();
    widget.inits[widget.id] = (widget.inits[widget.id] ?? 0) + 1;
  }

  @override
  void dispose() {
    widget.disposes[widget.id] = (widget.disposes[widget.id] ?? 0) + 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: widget.extent, child: Text('row-${widget.id}'));
  }
}
