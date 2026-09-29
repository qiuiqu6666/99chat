import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/android_update_download.dart';

const updateRequest = AndroidUpdateRequest(
  url: 'https://example.com/app.apk',
  version: '3.0.2',
  build: 21,
  mandatory: false,
);

class FakeUpdateGateway implements AndroidUpdateGateway {
  AndroidUpdateSnapshot current = const AndroidUpdateSnapshot('missing');
  Future<AndroidUpdateSnapshot> Function(AndroidUpdateRequest)? onEnsure;
  Future<AndroidUpdateSnapshot> Function()? onStatus;
  Future<String> Function()? onInstall;
  Future<void> Function()? onCancel;
  int ensureCalls = 0, statusCalls = 0, installCalls = 0, cancelCalls = 0;
  final retries = <bool>[];
  final permissions = <bool>[];

  @override
  Future<AndroidUpdateSnapshot> ensure(AndroidUpdateRequest request,
      {required bool retry}) {
    ensureCalls++;
    retries.add(retry);
    return onEnsure?.call(request) ?? Future.value(current);
  }

  @override
  Future<AndroidUpdateSnapshot> status() {
    statusCalls++;
    return onStatus?.call() ?? Future.value(current);
  }

  @override
  Future<String> install(String key, {required bool requestPermission}) {
    installCalls++;
    permissions.add(requestPermission);
    return onInstall?.call() ?? Future.value('installer_opened');
  }

  @override
  Future<void> cancel() {
    cancelCalls++;
    return onCancel?.call() ?? Future.value();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeUpdateGateway gateway;
  late AndroidUpdateDownloadController controller;
  setUp(() {
    gateway = FakeUpdateGateway();
    controller = AndroidUpdateDownloadController(gateway,
        operationTimeout: const Duration(milliseconds: 20));
  });
  tearDown(() => controller.dispose());

  test('repeated checks share one enqueue and completed APK is reusable',
      () async {
    final pending = Completer<AndroidUpdateSnapshot>();
    gateway.onEnsure = (_) => pending.future;
    final first = controller.prepare(updateRequest);
    final second = controller.prepare(updateRequest);
    expect(identical(first, second), isTrue);
    expect(gateway.ensureCalls, 1);
    pending
        .complete(const AndroidUpdateSnapshot('ready', request: updateRequest));
    await first;
    expect(controller.snapshot.ready, isTrue);
  });

  test('sync exception releases prepare lock and manual retry reaches native',
      () async {
    gateway.onEnsure = (_) => throw StateError('unavailable');
    await controller.prepare(updateRequest);
    expect(controller.snapshot.state, 'unavailable');
    gateway.onEnsure = null;
    gateway.current =
        const AndroidUpdateSnapshot('running', request: updateRequest);
    await controller.prepare(updateRequest, retry: true);
    expect(gateway.retries, [false, true]);
    expect(controller.snapshot.downloading, isTrue);
  });

  test('timeout releases lock and late old result cannot replace retry',
      () async {
    final pending = Completer<AndroidUpdateSnapshot>();
    gateway.onEnsure = (_) => pending.future;
    await controller.prepare(updateRequest);
    expect(controller.snapshot.state, 'unavailable');
    gateway.onEnsure = null;
    gateway.current =
        const AndroidUpdateSnapshot('ready', request: updateRequest);
    await controller.prepare(updateRequest, retry: true);
    pending.complete(
        const AndroidUpdateSnapshot('failed', request: updateRequest));
    await Future<void>.delayed(Duration.zero);
    expect(controller.snapshot.ready, isTrue);
  });

  test('superseding a release ignores its delayed completion', () async {
    final pending = Completer<AndroidUpdateSnapshot>();
    const replacement = AndroidUpdateRequest(
        url: 'https://example.com/new.apk',
        version: '3.0.3',
        build: 22,
        mandatory: true);
    gateway.onEnsure = (_) => pending.future;
    final old = controller.prepare(updateRequest);
    gateway.onEnsure = null;
    gateway.current =
        const AndroidUpdateSnapshot('ready', request: replacement);
    await controller.prepare(replacement);
    pending
        .complete(const AndroidUpdateSnapshot('ready', request: updateRequest));
    await old;
    expect(controller.snapshot.request?.key, replacement.key);
  });

  test('old ready state is immediately disabled during replacement', () async {
    gateway.current =
        const AndroidUpdateSnapshot('ready', request: updateRequest);
    await controller.refresh();
    final pending = Completer<AndroidUpdateSnapshot>();
    gateway.onEnsure = (_) => pending.future;
    final prepare = controller.prepare(updateRequest, retry: true);
    expect(await controller.install(), 'not_ready');
    pending.complete(gateway.current);
    await prepare;
    expect(gateway.installCalls, 0);
  });

  test('late refresh cannot resurrect a cancelled download', () async {
    final pending = Completer<AndroidUpdateSnapshot>();
    gateway.onStatus = () => pending.future;
    final refresh = controller.refresh();
    await controller.cancel();
    pending
        .complete(const AndroidUpdateSnapshot('ready', request: updateRequest));
    await refresh;
    expect(controller.snapshot.state, 'missing');
  });

  test('late cancel result cannot clear a subsequent request', () async {
    final pending = Completer<void>();
    gateway.onCancel = () => pending.future;
    final cancel = controller.cancel();
    gateway.current =
        const AndroidUpdateSnapshot('ready', request: updateRequest);
    await controller.prepare(updateRequest);
    pending.complete();
    await cancel;
    expect(controller.snapshot.ready, isTrue);
  });

  test('installation requires verified ready state', () async {
    for (final state in [
      'missing',
      'running',
      'paused',
      'failed',
      'unavailable'
    ]) {
      gateway.current = AndroidUpdateSnapshot(state, request: updateRequest);
      await controller.refresh();
      expect(await controller.install(), 'not_ready');
    }
    expect(gateway.installCalls, 0);
  });

  test('installation coalesces taps and releases lock after an exception',
      () async {
    gateway.current =
        const AndroidUpdateSnapshot('ready', request: updateRequest);
    await controller.refresh();
    final pending = Completer<String>();
    gateway.onInstall = () => pending.future;
    final first = controller.install();
    final second = controller.install();
    expect(identical(first, second), isTrue);
    pending.completeError(StateError('installer missing'));
    expect(await first, 'unavailable');
    gateway.onInstall = null;
    expect(await controller.install(), 'installer_opened');
    expect(gateway.installCalls, 2);
  });

  test('installation timeout allows retry', () async {
    gateway.current =
        const AndroidUpdateSnapshot('ready', request: updateRequest);
    await controller.refresh();
    gateway.onInstall = () => Completer<String>().future;
    expect(await controller.install(), 'unavailable');
    gateway.onInstall = null;
    expect(
        await controller.install(requestPermission: false), 'installer_opened');
    expect(gateway.permissions, [true, false]);
  });

  test('failed status query recovers on subsequent refresh', () async {
    gateway.onStatus = () => throw StateError('provider unavailable');
    await controller.refresh();
    gateway.onStatus = null;
    gateway.current =
        const AndroidUpdateSnapshot('ready', request: updateRequest);
    await controller.refresh();
    expect(controller.snapshot.ready, isTrue);
  });

  testWidgets(
      'background stops polling but retains native download; resume restores',
      (tester) async {
    gateway.current =
        const AndroidUpdateSnapshot('running', request: updateRequest);
    await controller.prepare(updateRequest);
    controller.setForeground(false);
    await tester.pump(const Duration(seconds: 10));
    expect(gateway.statusCalls, 0);
    expect(gateway.cancelCalls, 0);
    gateway.current =
        const AndroidUpdateSnapshot('ready', request: updateRequest);
    controller.setForeground(true);
    await tester.pump();
    expect(controller.snapshot.ready, isTrue);
  });

  test(
      'platform bridge permits metered downloads and preserves release metadata',
      () async {
    const channel = MethodChannel('ninechat/app_update');
    MethodCall? sent;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      sent = call;
      return {'state': 'queued', 'request': updateRequest.toMap()};
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final result = await MethodChannelAndroidUpdateGateway()
        .ensure(updateRequest, retry: true);
    expect(sent?.method, 'ensure');
    expect(sent?.arguments['allowMetered'], isTrue);
    expect(sent?.arguments['retry'], isTrue);
    expect(result.request?.key, updateRequest.key);
  });
}
