import 'dart:async';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:camerawesome/pigeon.dart';
import 'package:camerawesome/src/orchestrator/camera_context.dart';
import 'package:camerawesome/src/widgets/preview/awesome_preview_fit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('switching cameras keeps the active video aspect ratio', () async {
    final context = _SwitchCameraContext(
      SensorConfig.single(aspectRatio: CameraAspectRatios.ratio_16_9),
    );
    final state = _SwitchCameraState(context);
    addTearDown(context.disposeConfigs);

    await state.switchCameraSensor();
    expect(context.sensorConfig.sensors.single.position, SensorPosition.front);
    expect(context.sensorConfig.aspectRatio, CameraAspectRatios.ratio_16_9);

    await state.switchCameraSensor();
    expect(context.sensorConfig.sensors.single.position, SensorPosition.back);
    expect(context.sensorConfig.aspectRatio, CameraAspectRatios.ratio_16_9);
  });

  testWidgets('sensor change is published after the native camera switches',
      (tester) async {
    final nativeSwitch = Completer<void>();
    final nativeStarted = Completer<void>();
    final channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.CameraInterface.setSensor',
      CameraInterface.codec,
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockDecodedMessageHandler(channel, (message) async {
      nativeStarted.complete();
      await nativeSwitch.future;
      return <Object?>[null];
    });
    addTearDown(() => messenger.setMockDecodedMessageHandler(channel, null));

    final initial =
        SensorConfig.single(aspectRatio: CameraAspectRatios.ratio_16_9);
    final context = CameraContext.create(
      initial,
      initialCaptureMode: CaptureMode.video,
      saveConfig: null,
      exifPreferences: ExifPreferences(saveGPSLocation: false),
      filter: AwesomeFilter.None,
      enablePhysicalButton: false,
    );
    final next = SensorConfig.single(
      sensor: Sensor.position(SensorPosition.front),
      aspectRatio: CameraAspectRatios.ratio_16_9,
    );
    final switching = context.setSensorConfig(next);
    await nativeStarted.future;
    expect(context.sensorConfig, same(initial));

    nativeSwitch.complete();
    await switching;
    expect(context.sensorConfig, same(next));
    next.dispose();
    await context.sensorConfigController.close();
  });

  Future<Rect> pumpPreview(WidgetTester tester, CameraPreviewFit fit) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final frameKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: PreviewFitWidget(
          alignment: Alignment.center,
          constraints: const BoxConstraints.tightFor(width: 400, height: 800),
          previewFit: fit,
          previewSize: PreviewSize(width: 900, height: 1600),
          scale: 1,
          maxSize: const Size(400, 800),
          child: ColoredBox(key: frameKey, color: Colors.red),
        ),
      ),
    );
    return tester.getRect(find.byKey(frameKey));
  }

  testWidgets('cover crops the same amount from the left and right',
      (tester) async {
    final frame = await pumpPreview(tester, CameraPreviewFit.cover);

    expect(frame.left, closeTo(-25, 0.01));
    expect(frame.right, closeTo(425, 0.01));
    expect(frame.top, closeTo(0, 0.01));
    expect(frame.bottom, closeTo(800, 0.01));
  });

  testWidgets('contain keeps the full frame centered', (tester) async {
    final frame = await pumpPreview(tester, CameraPreviewFit.contain);

    expect(frame.left, closeTo(0, 0.01));
    expect(frame.right, closeTo(400, 0.01));
    expect(frame.top, closeTo(44.44, 0.02));
    expect(frame.bottom, closeTo(755.56, 0.02));
  });
}

class _SwitchCameraContext implements CameraContext {
  _SwitchCameraContext(this._config) {
    _configs.add(_config);
  }

  SensorConfig _config;
  final List<SensorConfig> _configs = [];

  @override
  SensorConfig get sensorConfig => _config;

  @override
  Future<void> setSensorConfig(SensorConfig config) async {
    _config = config;
    _configs.add(config);
  }

  void disposeConfigs() {
    for (final config in _configs) {
      config.dispose();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SwitchCameraState extends CameraState {
  _SwitchCameraState(super.context);

  @override
  CaptureMode get captureMode => CaptureMode.video;

  @override
  void dispose() {}

  @override
  void setState(CaptureMode captureMode) {}
}
