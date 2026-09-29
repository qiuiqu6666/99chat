import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/history_window_trim_ui_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_history_window_transition.dart';

void main() {
  for (final interruptByDrag in [true, false]) {
    testWidgets(
        'trim yields to ${interruptByDrag ? 'the same drag' : 'the deadline'} without storage rollback',
        (tester) async {
      final key = GlobalKey<ChatHistoryWindowTransitionState>();
      final scroll = ScrollController(initialScrollOffset: 600);
      final trim = HistoryWindowTrimUiController<int, int>();
      final persistence = Completer<int?>();
      final layout = Completer<void>();
      var restores = 0;
      var rollbacks = 0;
      var finishes = 0;
      var settled = 0;
      var committed = false;
      int? generation;
      await tester.pumpWidget(MaterialApp(
          home: ChatHistoryWindowTransition(
        key: key,
        child: ListView.builder(
            controller: scroll,
            itemExtent: 60,
            itemCount: 100,
            itemBuilder: (_, i) => Text('row $i')),
      )));
      final pending = trim.run(
        isCurrentAndIdle: () => true,
        capture: () => 1,
        prepare: (_) => persistence.future,
        commit: (_) {
          committed = true;
          return true;
        },
        nextFrame: () => layout.future,
        restore: (_, __) {
          restores++;
          return false;
        },
        // A never-completing rollback models blocked SQLite. It must not run.
        rollback: (_) {
          rollbacks++;
          return Completer<bool>().future;
        },
        finish: (_) => finishes++,
        onWindowSettled: () => settled++,
        rollbackOnRestoreFailure: false,
        beginVisualUpdate: () {
          final started = key.currentState!.begin(
              requireSnapshot: true,
              showProgress: false,
              maxRetention: const Duration(milliseconds: 150),
              onInterrupted: trim.cancel);
          generation = key.currentState!.generation;
          return started;
        },
        endVisualUpdate: () async =>
            key.currentState!.release(expectedGeneration: generation),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(committed, isFalse);
      expect(find.byType(RawImage), findsNothing);
      // Pending persistence never owns input.
      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(600));
      persistence.complete(1);
      await tester.pump();
      await tester.pump();
      expect(committed, isTrue);
      expect(find.byType(RawImage), findsOneWidget);
      final before = scroll.offset;
      if (interruptByDrag) {
        final gesture =
            await tester.startGesture(tester.getCenter(find.byType(ListView)));
        await tester.pump();
        expect(find.byType(RawImage), findsNothing);
        await gesture.moveBy(const Offset(0, -120));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(before));
      } else {
        await tester.pump(const Duration(milliseconds: 151));
        expect(find.byType(RawImage), findsNothing);
        await tester.drag(find.byType(ListView), const Offset(0, 100));
        await tester.pumpAndSettle();
        expect(scroll.offset, lessThan(before));
      }
      final after = scroll.offset;
      layout.complete();
      await tester.pump();
      expect(await pending, HistoryWindowTrimUiOutcome.keptCommitted);
      expect(restores, 0, reason: 'late layout must not restore an old anchor');
      expect(rollbacks, 0);
      expect(finishes, 1);
      expect(settled, 1,
          reason: 'retained-window pagination cursors must rebase');
      expect(trim.isBusy, isFalse);
      expect(scroll.offset, after);
      await tester.pumpWidget(const SizedBox());
      trim.dispose();
      scroll.dispose();
    });
  }

  testWidgets('old trim cleanup cannot release a newer search transition',
      (tester) async {
    final key = GlobalKey<ChatHistoryWindowTransitionState>();
    await tester.pumpWidget(MaterialApp(
        home: ChatHistoryWindowTransition(
            key: key, child: const SizedBox.expand(child: Text('history')))));
    key.currentState!.begin(
        onInterrupted: () {}, maxRetention: const Duration(milliseconds: 150));
    final oldGeneration = key.currentState!.generation;
    final oldFinish = key.currentState!.finish();
    key.currentState!.release();
    key.currentState!.begin();
    key.currentState!.release(expectedGeneration: oldGeneration);
    await tester.pump();
    await oldFinish;
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(RawImage), findsOneWidget);
    key.currentState!.release();
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('failed anchor retains committed window and releases once', () async {
    final trim = HistoryWindowTrimUiController<int, int>();
    var rollbackCalls = 0;
    var finishCalls = 0;
    final result = await trim.run(
      isCurrentAndIdle: () => true,
      capture: () => 1,
      prepare: (_) async => 1,
      commit: (_) => true,
      nextFrame: () async {},
      restore: (_, __) => false,
      rollback: (_) async {
        rollbackCalls++;
        return true;
      },
      finish: (_) => finishCalls++,
      rollbackOnRestoreFailure: false,
    );
    expect(result, HistoryWindowTrimUiOutcome.keptCommitted);
    expect(rollbackCalls, 0);
    expect(finishCalls, 1);
    expect(trim.isBusy, isFalse);
  });
}
