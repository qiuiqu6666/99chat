import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/history_window_trim_ui_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_pagination_scroll_physics.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_history_window_transition.dart';

class _Anchor {
  const _Anchor(this.id, this.top);
  final int id;
  final double top;
}

class _Ticket {
  _Ticket(this.before, this.after);
  List<int> before;
  List<int> after;
  bool released = false;
}

class _Harness {
  final transitionKey = GlobalKey<ChatHistoryWindowTransitionState>();
  bool retainViewport = false;
  final rows = ValueNotifier(List.generate(600, (i) => i));
  final scroll = AutoScrollController();
  final trim = HistoryWindowTrimUiController<_Ticket, _Anchor>();
  bool active = true;
  bool gesture = false;
  bool hideAnchor = false;
  bool removeAnchor = false;
  bool forceRemount = false;
  int prepareCount = 0;
  int commitCount = 0;
  int rollbackCount = 0;
  int finishCount = 0;
  int unmountedAttempts = 0;
  int restoreAttempts = 0;
  _Ticket? lastTicket;
  Completer<void>? persist;
  void Function()? afterCommit;
  void Function()? onRollback;

  double height(int id) => 43.0 + (id % 7) * 19.0;
  double offsetAt(int index) =>
      rows.value.take(index).fold(0.0, (sum, id) => sum + height(id));
  BuildContext? contextAt(int index) => scroll.tagMap[-index]?.context;
  RenderBox? viewport(BuildContext? context) => context == null
      ? null
      : Scrollable.maybeOf(context)?.context.findRenderObject() as RenderBox?;
  double? topFor(int id) {
    final index = rows.value.indexOf(id);
    final context = index < 0 ? null : contextAt(index);
    final target = context?.findRenderObject();
    final box = viewport(context);
    if (target is! RenderBox ||
        box == null ||
        !target.attached ||
        !target.hasSize) return null;
    return target.localToGlobal(Offset.zero, ancestor: box).dy;
  }

  _Anchor? capture() {
    _Anchor? best;
    var distance = double.infinity;
    for (final entry in scroll.tagMap.entries) {
      final index = -entry.key;
      if (index < 0 || index >= rows.value.length) continue;
      final id = rows.value[index];
      final top = topFor(id);
      final box = viewport(entry.value.context);
      if (top == null ||
          box == null ||
          top < 0 ||
          top + height(id) > box.size.height) continue;
      final nextDistance = (top - box.size.height / 3).abs();
      if (nextDistance < distance) {
        best = _Anchor(id, top);
        distance = nextDistance;
      }
    }
    return best;
  }

  Widget build() => MaterialApp(
      home: ChatHistoryWindowTransition(
          key: transitionKey,
          child: Scaffold(
              body: Center(
                  child: SizedBox(
            width: 400,
            height: 500,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollStartNotification &&
                    notification.dragDetails != null) {
                  gesture = true;
                  trim.cancel();
                } else if (notification is ScrollEndNotification) {
                  gesture = false;
                }
                return false;
              },
              child: ValueListenableBuilder<List<int>>(
                valueListenable: rows,
                builder: (_, values, __) => CustomScrollView(
                  reverse: true,
                  controller: scroll,
                  cacheExtent: 0,
                  physics: const HistoryPaginationScrollPhysics(),
                  slivers: [
                    SliverList(
                        delegate: SliverChildBuilderDelegate(
                      (_, index) => AutoScrollTag(
                        key: ValueKey(values[index]),
                        controller: scroll,
                        index: -index,
                        child: SizedBox(
                            height: height(values[index]),
                            child: Text('message ${values[index]}')),
                      ),
                      childCount: values.length,
                      findChildIndexCallback: (key) {
                        final index =
                            values.indexOf((key as ValueKey<int>).value);
                        return index < 0 ? null : index;
                      },
                    ))
                  ],
                ),
              ),
            ),
          )))));

  Future<HistoryWindowTrimUiOutcome> run({required bool trimNewer}) => trim.run(
        beginVisualUpdate: retainViewport
            ? () => transitionKey.currentState!
                .begin(showProgress: false, requireSnapshot: true)
            : null,
        endVisualUpdate:
            retainViewport ? () => transitionKey.currentState!.finish() : null,
        isCurrentAndIdle: () =>
            active &&
            !gesture &&
            scroll.hasClients &&
            !scroll.position.isScrollingNotifier.value,
        capture: capture,
        prepare: (anchor) async {
          prepareCount++;
          if (persist != null) await persist!.future;
          final after =
              trimNewer ? rows.value.sublist(100) : rows.value.sublist(0, 500);
          if (removeAnchor) after.remove(anchor.id);
          return lastTicket = _Ticket(List.of(rows.value), after);
        },
        commit: (ticket) {
          commitCount++;
          rows.value = ticket.after;
          if (forceRemount) {
            // Force the former anchor outside the lazy cache on the first frame.
            scroll.jumpTo(0);
          }
          afterCommit?.call();
          return true;
        },
        nextFrame: () => WidgetsBinding.instance.endOfFrame,
        restore: (anchor, attempt) {
          restoreAttempts++;
          final index = rows.value.indexOf(anchor.id);
          if (index >= 0 && contextAt(index) == null) unmountedAttempts++;
          return HistoryWindowTrimViewportRestorer.restore(
            targetIndex: index < 0 ? null : index,
            viewportTop: anchor.top,
            position: scroll.hasClients ? scroll.position : null,
            contextForIndex: (index) => hideAnchor ? null : contextAt(index),
            mountedIndices: scroll.tagMap.keys.map((key) => -key),
            jumpTo: scroll.jumpTo,
          );
        },
        rollback: (ticket) async {
          rollbackCount++;
          // Latest authority wins: a withdrawal arriving during the transaction
          // must not be resurrected from ticket.before.
          rows.value = ticket.before.where((id) => id != 599).toList();
          onRollback?.call();
          return true;
        },
        finish: (ticket) {
          finishCount++;
          ticket.before = const [];
          ticket.after = const [];
          ticket.released = true;
        },
      );

  Future<void> close(WidgetTester tester) async {
    active = false;
    trim.dispose();
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
    rows.dispose();
  }
}

Future<T> _finish<T>(WidgetTester tester, Future<T> future) async {
  T? result;
  Object? error;
  var done = false;
  future.then((value) {
    result = value;
    done = true;
  }, onError: (Object value) {
    error = value;
    done = true;
  });
  for (var i = 0; i < 50 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(done, isTrue, reason: 'trim must finish in bounded layout attempts');
  if (error != null) throw error!;
  return result as T;
}

Future<_Anchor> _mount(WidgetTester tester, _Harness harness,
    {int index = 290}) async {
  await tester.pumpWidget(harness.build());
  harness.scroll.jumpTo(harness.offsetAt(index));
  await tester.pump();
  // The lazy sliver's max extent estimate can initially clamp the jump.
  harness.scroll.jumpTo(harness.offsetAt(index));
  await tester.pump();
  final anchor = harness.capture();
  expect(anchor, isNotNull);
  return anchor!;
}

void main() {
  for (final rollback in [false, true]) {
    testWidgets('trim hides every displaced frame (rollback=$rollback)',
        (tester) async {
      final harness = _Harness()
        ..retainViewport = true
        ..hideAnchor = rollback;
      final anchor = await _mount(tester, harness);
      var done = false;
      final result = harness.run(trimNewer: true).then((value) {
        done = true;
        return value;
      });
      Object? retainedImage;
      var displacedFrames = 0;
      for (var frame = 0; frame < 40 && !done; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final top = harness.topFor(anchor.id);
        if (top == null || (top - anchor.top).abs() > 1) {
          displacedFrames++;
          expect(find.byType(RawImage), findsOneWidget,
              reason: 'frame $frame must still show the pre-trim viewport');
          final image = tester.widget<RawImage>(find.byType(RawImage)).image;
          retainedImage ??= image;
          expect(image, same(retainedImage));
          final opacity = tester.widget<Opacity>(find
              .descendant(
                  of: find.byKey(harness.transitionKey),
                  matching: find.byType(Opacity))
              .first);
          expect(opacity.opacity, 0,
              reason: 'no live rows may paint through snapshot gaps');
        }
      }
      expect(done, isTrue);
      expect(
          await result,
          rollback
              ? HistoryWindowTrimUiOutcome.rolledBack
              : HistoryWindowTrimUiOutcome.restored);
      expect(displacedFrames, greaterThan(0));
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);
      expect(harness.topFor(anchor.id), closeTo(anchor.top, 1));
      expect(harness.trim.isBusy, isFalse);
      await harness.close(tester);
    });
  }

  testWidgets('unavailable snapshot skips membership commit and releases lane',
      (tester) async {
    final harness = _Harness()..retainViewport = true;
    await _mount(tester, harness);
    final boundary = tester.renderObject(find
        .descendant(
            of: find.byKey(harness.transitionKey),
            matching: find.byType(RepaintBoundary))
        .first);
    boundary.markNeedsPaint();
    expect(await _finish(tester, harness.run(trimNewer: true)),
        HistoryWindowTrimUiOutcome.skipped);
    expect(harness.commitCount, 0);
    expect(harness.rows.value.length, 600);
    expect(harness.finishCount, 1);
    expect(find.byType(RawImage), findsNothing);
    // Failed acquisition must not leave the shared transition busy.
    expect(await _finish(tester, harness.run(trimNewer: true)),
        HistoryWindowTrimUiOutcome.restored);
    await harness.close(tester);
  });

  for (final newer in [false, true]) {
    testWidgets(
        'reverse uneven rows trim ${newer ? 'newer' : 'older'} side '
        'and preserve real visible ID within one pixel', (tester) async {
      final harness = _Harness();
      final anchor = await _mount(tester, harness);
      final oldIndex = harness.rows.value.indexOf(anchor.id);
      expect(await _finish(tester, harness.run(trimNewer: newer)),
          HistoryWindowTrimUiOutcome.restored);
      expect(harness.rows.value.length, 500);
      expect(harness.topFor(anchor.id), closeTo(anchor.top, 1));
      expect(harness.rows.value.indexOf(anchor.id),
          newer ? oldIndex - 100 : oldIndex);
      expect(harness.rollbackCount, 0);
      expect(harness.finishCount, 1);
      expect(harness.lastTicket!.before, isEmpty);
      await harness.close(tester);
    });
  }

  testWidgets('retained anchor outside lazy cache is remounted by new index',
      (tester) async {
    final harness = _Harness()..forceRemount = true;
    final anchor = await _mount(tester, harness, index: 180);
    expect(await _finish(tester, harness.run(trimNewer: true)),
        HistoryWindowTrimUiOutcome.restored);
    expect(harness.unmountedAttempts, greaterThan(0));
    expect(harness.topFor(anchor.id), closeTo(anchor.top, 1));
    expect(harness.restoreAttempts, lessThanOrEqualTo(8));
    await harness.close(tester);
  });

  testWidgets(
      'unrecoverable unmounted anchor rolls back latest authority and '
      'releases all ticket references', (tester) async {
    final harness = _Harness()..hideAnchor = true;
    await _mount(tester, harness);
    expect(await _finish(tester, harness.run(trimNewer: true)),
        HistoryWindowTrimUiOutcome.rolledBack);
    expect(harness.rollbackCount, 1);
    expect(harness.rows.value.length, 599);
    expect(harness.rows.value, isNot(contains(599)));
    expect(harness.finishCount, 1);
    expect(harness.lastTicket!.released, isTrue);
    expect(harness.restoreAttempts, 16);
    await harness.close(tester);
  });

  testWidgets('deleted anchor cannot be mistaken for the old row index',
      (tester) async {
    final harness = _Harness()..removeAnchor = true;
    await _mount(tester, harness);
    expect(await _finish(tester, harness.run(trimNewer: true)),
        HistoryWindowTrimUiOutcome.rolledBack);
    expect(harness.rollbackCount, 1);
    expect(harness.finishCount, 1);
    await harness.close(tester);
  });

  testWidgets('real drag and ballistic motion cannot admit a trim',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    expect(
        await harness.run(trimNewer: true), HistoryWindowTrimUiOutcome.skipped);
    expect(harness.prepareCount, 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(await _finish(tester, harness.run(trimNewer: true)),
        HistoryWindowTrimUiOutcome.restored);
    await harness.close(tester);
  });

  testWidgets('gesture after async persistence prevents commit',
      (tester) async {
    final harness = _Harness()..persist = Completer<void>();
    await _mount(tester, harness);
    final result = harness.run(trimNewer: true);
    expect(harness.prepareCount, 1);
    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();
    harness.persist!.complete();
    expect(await _finish(tester, result), HistoryWindowTrimUiOutcome.skipped);
    expect(harness.commitCount, 0);
    expect(harness.finishCount, 1);
    await gesture.up();
    await tester.pumpAndSettle();
    await harness.close(tester);
  });

  testWidgets('route or overlay excursion cancels even after returning idle',
      (tester) async {
    final harness = _Harness()..persist = Completer<void>();
    await _mount(tester, harness);
    final result = harness.run(trimNewer: true);
    harness.active = false;
    harness.trim.cancel();
    harness.active = true;
    harness.persist!.complete();
    expect(await _finish(tester, result), HistoryWindowTrimUiOutcome.skipped);
    expect(harness.commitCount, 0);
    expect(harness.finishCount, 1);
    await harness.close(tester);
  });

  testWidgets('cancel after commit rolls back without stale pixel writes',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    harness.afterCommit = () {
      harness.gesture = true;
      harness.trim.cancel();
    };
    expect(await _finish(tester, harness.run(trimNewer: true)),
        HistoryWindowTrimUiOutcome.rolledBack);
    expect(harness.rollbackCount, 1);
    expect(harness.restoreAttempts, 0);
    expect(harness.finishCount, 1);
    await harness.close(tester);
  });

  testWidgets('dispose during prepare releases without committing off-route',
      (tester) async {
    final harness = _Harness()..persist = Completer<void>();
    await _mount(tester, harness);
    final result = harness.run(trimNewer: false);
    harness.active = false;
    harness.trim.dispose();
    harness.persist!.complete();
    expect(await _finish(tester, result), HistoryWindowTrimUiOutcome.skipped);
    expect(harness.commitCount, 0);
    expect(harness.finishCount, 1);
    await harness.close(tester);
  });

  testWidgets('rollback failure still releases ticket and serial lane',
      (tester) async {
    final harness = _Harness()..hideAnchor = true;
    await _mount(tester, harness);
    harness.onRollback = () => throw StateError('injected rollback failure');
    expect(await _finish(tester, harness.run(trimNewer: true)),
        HistoryWindowTrimUiOutcome.rollbackFailed);
    expect(harness.finishCount, 1);
    expect(harness.trim.isBusy, isFalse);
    await harness.close(tester);
  });

  test('real history page wires durable trim, fresh pixel resolution and gates',
      () {
    final page = File('third_party/tencent_cloud_chat_uikit/lib/ui/views/'
            'TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart')
        .readAsStringSync();
    expect(page, contains('_historyWindowTrimUi.run('));
    expect(page, contains('capture: _captureVisiblePaginationViewportAnchor'));
    expect(page, contains('global.prepareHistoryWindowTrim('));
    expect(page, contains('global.commitHistoryWindowTrim(ticket)'));
    expect(page, contains('rollback: global.rollbackHistoryWindowTrim'));
    expect(page, contains('finish: global.finishHistoryWindowTrim'));
    expect(page, contains('HistoryWindowTrimViewportRestorer.restore('));
    expect(page, contains('resolvedGlobalIndex: index'));
    expect(page, contains('globalModel.historyWindowCanReadNewer('));
    expect(page, contains('global.historyWindowPaginationBlocked('));
    expect(page, isNot(contains('reason: \'page_dispose\'')));
  });
}
