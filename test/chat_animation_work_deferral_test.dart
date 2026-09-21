import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_gallery_pick_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/keyboard_viewport_transition_coordinator.dart';

void main() {
  testWidgets('IME updates layout immediately but saves only the settled height',
      (tester) async {
    final saved = <double>[];
    final coordinator = KeyboardViewportTransitionCoordinator(
      pauseMedia: () {},
      resumeMedia: () {},
      persistTrustedHeight: saved.add,
    );
    addTearDown(coordinator.dispose);
    for (final height in [80.0, 140.0, 220.0, 300.0]) {
      coordinator.applyLogicalInset(height, viewHeight: 800, displayHeight: 800);
      expect(coordinator.effectiveInset.value, height);
      await tester.pump(const Duration(milliseconds: 50));
      expect(saved, isEmpty);
    }
    await tester.pump(const Duration(milliseconds: 200));
    expect(saved, [300]);
    coordinator.applyLogicalInset(180, viewHeight: 800, displayHeight: 800);
    await tester.pump(const Duration(milliseconds: 50));
    coordinator.applyLogicalInset(0, viewHeight: 800, displayHeight: 800);
    await tester.pump(const Duration(milliseconds: 300));
    expect(saved, [300]);
    coordinator.applyLogicalInset(300, viewHeight: 800, displayHeight: 800);
    await tester.pump(const Duration(milliseconds: 300));
    expect(saved, [300]);
    coordinator.applyLogicalInset(340, viewHeight: 800, displayHeight: 800);
    await tester.pump(const Duration(milliseconds: 250));
    expect(saved, [300, 340]);
  });

  testWidgets('reset and disposal cancel pending height persistence', (tester) async {
    final saved = <double>[];
    final coordinator = KeyboardViewportTransitionCoordinator(
      pauseMedia: () {}, resumeMedia: () {}, persistTrustedHeight: saved.add,
    );
    coordinator.applyNativeIme(visible: true, imeHeight: 300);
    coordinator.reset();
    await tester.pump(const Duration(milliseconds: 300));
    expect(saved, isEmpty);
    coordinator.applyNativeIme(visible: true, imeHeight: 320);
    coordinator.dispose();
    await tester.pump(const Duration(milliseconds: 300));
    expect(saved, isEmpty);
  });

  testWidgets('picker handoff follows real reverse animation completion', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const SizedBox(),
    ));
    final route = PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => const SizedBox(),
      reverseTransitionDuration: const Duration(milliseconds: 600),
    );
    unawaited(navigatorKey.currentState!.push(route));
    await tester.pumpAndSettle();
    navigatorKey.currentState!.pop();
    var released = false;
    final waiting = ChatGalleryPickUtils.waitForPickerDismissSettle(
      routeCompleted: route.completed.then<void>((_) {}),
    ).then((_) => released = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(released, isFalse);
    await tester.pumpAndSettle();
    await waiting;
    expect(released, isTrue);
  });

  testWidgets('stalled picker transition has a bounded fallback', (tester) async {
    final neverCompleted = Completer<void>();
    var released = false;
    final waiting = ChatGalleryPickUtils.waitForPickerDismissSettle(
      routeCompleted: neverCompleted.future,
    ).then((_) => released = true);
    await tester.pump(const Duration(milliseconds: 999));
    expect(released, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    await waiting;
    expect(released, isTrue);
    neverCompleted.complete();
    await tester.pump();
  });
}
