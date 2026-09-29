import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/android_keep_alive_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('android_keep_alive');
  final service = AndroidKeepAliveService.instance;

  setUp(() {
    service.debugSetAndroidOverride(true);
  });

  tearDown(() async {
    await service.stop();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    service.debugSetAndroidOverride(null);
  });

  test('completed native start future does not block a later restart',
      () async {
    final delayedStart = Completer<bool>();
    var starts = 0;
    var stops = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'start') {
        starts++;
        if (starts == 1) return delayedStart.future;
        return true;
      }
      if (call.method == 'stop') {
        stops++;
        return true;
      }
      if (call.method == 'isRunning') return false;
      return null;
    });

    final first = service.start();
    await Future<void>.delayed(Duration.zero);
    await service.stop();
    delayedStart.complete(true);
    await first;
    await service.start();

    expect(starts, 2);
    expect(stops, 1);
  });
}
