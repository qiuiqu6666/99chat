import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/ime_insets_bridge.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/keyboard_viewport_transition_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const method = MethodChannel('ninechat/ime_insets');
  const events = MethodChannel('ninechat/ime_insets_events');
  var listens = 0;
  var cancels = 0;
  final bridges = <ImeInsetsBridge>[];
  final coordinators = <KeyboardViewportTransitionCoordinator>[];

  KeyboardViewportTransitionCoordinator coordinator() {
    final c = KeyboardViewportTransitionCoordinator(
        pauseMedia: () {}, resumeMedia: () {});
    c.applyLogicalInset(0, viewHeight: 800, displayHeight: 800);
    coordinators.add(c);
    return c;
  }

  ImeInsetsBridge bridge() {
    final b = ImeInsetsBridge();
    bridges.add(b);
    return b;
  }

  Future<void> send(double height) async {
    await messenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope({
        'visible': height > 0,
        'imeHeight': height,
        'device': 'legacy-android',
      }),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    listens = cancels = 0;
    messenger.setMockMethodCallHandler(
        method, (_) async => {'visible': false, 'imeHeight': 0});
    messenger.setMockMethodCallHandler(events, (call) async {
      if (call.method == 'listen') listens++;
      if (call.method == 'cancel') cancels++;
      return null;
    });
  });

  tearDown(() async {
    for (final b in bridges) {
      b.stop();
    }
    await Future<void>.delayed(Duration.zero);
    for (final c in coordinators) {
      c.dispose();
    }
    bridges.clear();
    coordinators.clear();
    messenger.setMockMethodCallHandler(method, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  test('native height raises input and hiding clears it without Flutter insets',
      () async {
    final c = coordinator();
    await bridge().start(c);
    await send(312);
    expect(c.effectiveInset.value, 312);
    expect(c.effectiveSource.value, KeyboardInsetSource.nativeIme);
    await send(0);
    expect(c.effectiveInset.value, 0);
  });

  test('returning from a second chat retains the first native subscription',
      () async {
    final first = coordinator();
    final second = coordinator();
    await bridge().start(first);
    final secondBridge = bridge();
    await secondBridge.start(second);
    expect(listens, 1);
    await send(280);
    expect(first.effectiveInset.value, 280);
    expect(second.effectiveInset.value, 280);
    secondBridge.stop();
    await Future<void>.delayed(Duration.zero);
    expect(cancels, 0);
    await send(320);
    expect(first.effectiveInset.value, 320);
    expect(second.effectiveInset.value, 280);
  });

  test('late initial snapshot cannot overwrite a newer keyboard event',
      () async {
    final snapshot = Completer<Object?>();
    messenger.setMockMethodCallHandler(method, (_) => snapshot.future);
    final c = coordinator();
    final start = bridge().start(c);
    await Future<void>.delayed(Duration.zero);
    await send(312);
    snapshot.complete({'visible': false, 'imeHeight': 0});
    await start;
    expect(c.effectiveInset.value, 312);
  });

  test('late snapshot after stop cannot update the previous chat', () async {
    final snapshot = Completer<Object?>();
    messenger.setMockMethodCallHandler(method, (_) => snapshot.future);
    final c = coordinator();
    final b = bridge();
    final start = b.start(c);
    await Future<void>.delayed(Duration.zero);
    b.stop();
    snapshot.complete({'visible': true, 'imeHeight': 312});
    await start;
    expect(c.effectiveInset.value, 0);
  });
}
