import 'dart:async';
// fake_async is supplied by flutter_test.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_removal_work.dart';

void main() {
  test('rejoin waits for destructive work already in flight', () {
    fakeAsync((clock) {
      final work = GroupRemovalWork();
      final deleting = Completer<void>();
      var restored = false;
      var continuedCleanup = false;
      work.run(
          key: 'group',
          hide: () async {},
          cleanup: (isCurrent) async {
            await deleting.future;
            if (isCurrent()) continuedCleanup = true;
          },
          isCurrent: () => true,
          onError: (e, s) => fail('$e'));
      clock.elapse(const Duration(milliseconds: 350));
      work.prepareRejoin('group').then((_) => restored = true);
      clock.flushMicrotasks();
      expect(restored, isFalse);
      deleting.complete();
      clock.flushMicrotasks();
      expect(restored, isTrue);
      expect(continuedCleanup, isFalse);
    });
  });

  test('rejoin waits for an in-flight hide and cancels its cleanup', () {
    fakeAsync((clock) {
      final work = GroupRemovalWork();
      final hidden = Completer<void>();
      var restored = false, cleaned = false;
      var secondRestored = false;
      work.run(
          key: 'group',
          hide: () => hidden.future,
          cleanup: (_) async {
            cleaned = true;
          },
          isCurrent: () => true,
          onError: (e, s) => fail('$e'));
      work.prepareRejoin('group').then((_) => restored = true);
      work.prepareRejoin('group').then((_) => secondRestored = true);
      clock.flushMicrotasks();
      expect(restored, isFalse);
      expect(secondRestored, isFalse);
      hidden.complete();
      clock.flushMicrotasks();
      expect(restored, isTrue);
      clock.elapse(const Duration(seconds: 1));
      expect(cleaned, isFalse);
      expect(secondRestored, isTrue);
    });
  });

  test(
      'navigation finishes before heavy work; UI and realtime share one removal',
      () {
    fakeAsync((clock) {
      final work = GroupRemovalWork();
      final hidden = Completer<void>();
      final cleaned = Completer<void>();
      var hides = 0, cleanups = 0;
      var ready = false;
      Future<void> remove() => work.run(
          key: 'owner|group',
          hide: () {
            hides++;
            return hidden.future;
          },
          cleanup: (_) {
            cleanups++;
            return cleaned.future;
          },
          isCurrent: () => true,
          onError: (e, s) => fail('$e'));
      final first = remove();
      expect(identical(first, remove()), isTrue);
      first.then((_) => ready = true);
      hidden.complete();
      clock.flushMicrotasks();
      expect(ready, isTrue);
      expect(cleanups, 0);
      clock.elapse(const Duration(milliseconds: 350));
      expect(cleanups, 1);
      cleaned.complete();
      clock.flushMicrotasks();
      remove();
      clock.elapse(const Duration(seconds: 1));
      expect(hides, 1);
      expect(cleanups, 1);
    });
  });

  for (final invalidate in ['rejoin', 'logout', 'account']) {
    test('$invalidate invalidates deferred destructive work', () {
      fakeAsync((clock) {
        final work = GroupRemovalWork();
        var current = true, cleanup = false;
        work.run(
            key: 'group',
            hide: () async {},
            cleanup: (_) async {
              cleanup = true;
            },
            isCurrent: () => current,
            onError: (e, s) => fail('$e'));
        clock.flushMicrotasks();
        if (invalidate == 'rejoin') work.invalidate('group');
        if (invalidate == 'logout') work.clear();
        if (invalidate == 'account') current = false;
        clock.elapse(const Duration(seconds: 1));
        expect(cleanup, isFalse);
      });
    });
  }

  test('cleanup error permits retry while successful cleanup remains coalesced',
      () {
    fakeAsync((clock) {
      final work = GroupRemovalWork();
      var attempts = 0, errors = 0;
      Future<void> remove() => work.run(
          key: 'group',
          hide: () async {},
          cleanup: (_) async {
            if (++attempts == 1) throw StateError('db busy');
          },
          isCurrent: () => true,
          onError: (_, __) => errors++);
      remove();
      clock.elapse(const Duration(seconds: 1));
      remove();
      clock.elapse(const Duration(seconds: 1));
      remove();
      clock.elapse(const Duration(seconds: 1));
      expect(errors, 1);
      expect(attempts, 2);
    });
  });
}
