import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/keyboard_viewport_transition_coordinator.dart';

void main() {
  test('raw inset is kept when the view height already shrank', () {
    final c = KeyboardViewportTransitionCoordinator(
      pauseMedia: () {},
      resumeMedia: () {},
    );
    c.applyLogicalInset(
      300,
      viewHeight: 500,
      displayHeight: 800,
    );
    expect(c.inset.value, 300);
    c.applyLogicalInset(
      300,
      viewHeight: 800,
      displayHeight: 800,
    );
    expect(c.inset.value, 300);
    c.applyLogicalInset(
      0,
      viewHeight: 500,
      displayHeight: 800,
    );
    expect(c.inset.value, 0);
    c.dispose();
  });

  test('occupied edge locks until occupied returns to zero', () {
    var pause = 0;
    var resume = 0;
    var beginCb = 0;
    var endCb = 0;
    final c = KeyboardViewportTransitionCoordinator(
      onBegin: () => beginCb++,
      onEnd: () => endCb++,
      pauseMedia: () => pause++,
      resumeMedia: () => resume++,
    );
    for (var i = 1; i <= 15; i++) {
      c.applyLogicalInset(
        i * 20.0,
        viewHeight: 800,
        displayHeight: 800,
      );
    }
    expect(c.metricsCount, 15);
    expect(c.beginCount, 1);
    expect(beginCb, 1);
    expect(c.isAnimating, isTrue);
    expect(c.phase.value, KeyboardTransitionPhase.occupied);
    expect(c.settleCount, 0);
    expect(endCb, 0);
    expect(pause, 1);
    expect(resume, 0);
    expect(c.jumpCountDuringTransition, 0);

    c.applyLogicalInset(0, viewHeight: 800, displayHeight: 800);
    expect(c.isAnimating, isFalse);
    expect(c.phase.value, KeyboardTransitionPhase.idle);
    expect(c.beginCount, 1);
    expect(c.settleCount, 1);
    expect(endCb, 1);
    expect(pause, 1);
    expect(resume, 1);
    c.dispose();
  });

  test('metrics while occupied do not re-begin or unlock', () {
    final c = KeyboardViewportTransitionCoordinator(
      pauseMedia: () {},
      resumeMedia: () {},
    );
    c.applyLogicalInset(40, viewHeight: 800, displayHeight: 800);
    expect(c.isAnimating, isTrue);
    expect(c.beginCount, 1);
    for (var i = 1; i <= 7; i++) {
      c.applyLogicalInset(
        40.0 + i * 20.0,
        viewHeight: 800,
        displayHeight: 800,
      );
    }
    expect(c.beginCount, 1);
    expect(c.isAnimating, isTrue);
    expect(c.settleCount, 0);
    c.dispose();
  });

  test('inset=0 viewHeight drop still occupies', () {
    var pause = 0;
    var resume = 0;
    final c = KeyboardViewportTransitionCoordinator(
      pauseMedia: () => pause++,
      resumeMedia: () => resume++,
    );
    c.applyLogicalInset(0, viewHeight: 800, displayHeight: 800);
    expect(c.beginCount, 0);
    expect(c.isAnimating, isFalse);
    expect(c.inset.value, 0);
    for (var i = 1; i <= 15; i++) {
      c.applyLogicalInset(
        0,
        viewHeight: 800 - i * 20.0,
        displayHeight: 800,
      );
    }
    expect(c.inset.value, 0);
    expect(c.metricsCount, 15);
    expect(c.beginCount, 1);
    expect(c.isAnimating, isTrue);
    expect(c.phase.value, KeyboardTransitionPhase.occupied);
    expect(c.settleCount, 0);
    expect(pause, 1);
    expect(resume, 0);
    c.applyLogicalInset(0, viewHeight: 800, displayHeight: 800);
    expect(c.isAnimating, isFalse);
    expect(c.settleCount, 1);
    expect(c.inset.value, 0);
    expect(pause, 1);
    expect(resume, 1);
    c.dispose();
  });

  test('occupied false edge ends once without a later unlock', () {
    var endCb = 0;
    final c = KeyboardViewportTransitionCoordinator(
      onEnd: () => endCb++,
      pauseMedia: () {},
      resumeMedia: () {},
    );
    c.applyLogicalInset(120, viewHeight: 800, displayHeight: 800);
    c.applyLogicalInset(0, viewHeight: 800, displayHeight: 800);
    expect(c.isAnimating, isFalse);
    expect(endCb, 1);
    expect(c.settleCount, 1);
    c.applyLogicalInset(0, viewHeight: 800, displayHeight: 800);
    expect(endCb, 1);
    expect(c.beginCount, 1);
    c.dispose();
  });

  test('flutter inset wins over native', () {
    final c = KeyboardViewportTransitionCoordinator(
      pauseMedia: () {},
      resumeMedia: () {},
    );
    c.applyNativeIme(visible: true, imeHeight: 200);
    c.applyLogicalInset(300, viewHeight: 800, displayHeight: 800);
    expect(c.effectiveInset.value, 300);
    expect(c.effectiveSource.value, KeyboardInsetSource.flutterInset);
    c.dispose();
  });

  test('flutter 0 native 312 uses nativeIme', () {
    final c = KeyboardViewportTransitionCoordinator(
      pauseMedia: () {},
      resumeMedia: () {},
    );
    c.applyLogicalInset(0, viewHeight: 800, displayHeight: 800);
    c.applyNativeIme(visible: true, imeHeight: 312);
    expect(c.effectiveInset.value, 312);
    expect(c.effectiveSource.value, KeyboardInsetSource.nativeIme);
    expect(c.inset.value, 0);
    expect(c.isAnimating, isTrue);
    c.dispose();
  });

  test('shrink used when flutter and native are zero', () {
    final c = KeyboardViewportTransitionCoordinator(
      pauseMedia: () {},
      resumeMedia: () {},
    );
    c.applyLogicalInset(0, viewHeight: 520, displayHeight: 800);
    expect(c.effectiveInset.value, 280);
    expect(c.effectiveSource.value, KeyboardInsetSource.viewportShrink);
    expect(c.inset.value, 0);
    c.dispose();
  });

  test('cached used when occupied via nativeVisible and focused', () {
    final c = KeyboardViewportTransitionCoordinator(
      pauseMedia: () {},
      resumeMedia: () {},
    );
    c.seedCachedHeight(305);
    c.setInputHasFocus(true);
    c.applyLogicalInset(0, viewHeight: 800, displayHeight: 800);
    c.applyNativeIme(visible: true, imeHeight: 0);
    expect(c.effectiveInset.value, 305);
    expect(c.effectiveSource.value, KeyboardInsetSource.cached);
    c.dispose();
  });

  test('estimated when occupied via nativeVisible, focused, no cache', () {
    final c = KeyboardViewportTransitionCoordinator(
      pauseMedia: () {},
      resumeMedia: () {},
    );
    c.setInputHasFocus(true);
    c.applyLogicalInset(0, viewHeight: 800, displayHeight: 800);
    c.applyNativeIme(visible: true, imeHeight: 0);
    expect(c.effectiveInset.value, 288);
    expect(c.effectiveSource.value, KeyboardInsetSource.estimated);
    expect(c.effectiveInset.value >= 240, isTrue);
    expect(c.effectiveInset.value <= 360, isTrue);
    c.dispose();
  });

  test('focus true with no occupancy yields 0', () {
    final c = KeyboardViewportTransitionCoordinator(
      pauseMedia: () {},
      resumeMedia: () {},
    );
    c.seedCachedHeight(305);
    c.setInputHasFocus(true);
    c.applyLogicalInset(0, viewHeight: 800, displayHeight: 800);
    expect(c.effectiveInset.value, 0);
    expect(c.effectiveSource.value, KeyboardInsetSource.none);
    c.dispose();
  });

  test('occupied false even with cache yields 0', () {
    final c = KeyboardViewportTransitionCoordinator(
      pauseMedia: () {},
      resumeMedia: () {},
    );
    c.seedCachedHeight(305);
    c.setInputHasFocus(true);
    c.applyNativeIme(visible: true, imeHeight: 312);
    c.applyNativeIme(visible: false, imeHeight: 0);
    expect(c.effectiveInset.value, 0);
    expect(c.effectiveSource.value, KeyboardInsetSource.none);
    expect(c.inset.value, 0);
    c.dispose();
  });
}
