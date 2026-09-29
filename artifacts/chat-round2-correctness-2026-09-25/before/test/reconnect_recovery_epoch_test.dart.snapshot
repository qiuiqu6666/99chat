import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/reconnect_recovery_epoch.dart';

void main() {
  test('cold-start first connect success does not advance the epoch', () {
    final epoch = ReconnectRecoveryEpoch();
    expect(epoch.onConnectSuccess(), isFalse);
    expect(epoch.epoch, 0);
  });

  test('repeated connect success without a drop does not advance', () {
    final epoch = ReconnectRecoveryEpoch();
    epoch.onConnectSuccess();
    epoch.onConnectSuccess();
    epoch.onConnectSuccess();
    expect(epoch.epoch, 0);
  });

  test('a real drop followed by connect success advances exactly once', () {
    final epoch = ReconnectRecoveryEpoch();
    epoch.onConnectSuccess();
    epoch.onDisconnectedAfterConnected();
    expect(epoch.hasPendingDrop, isTrue);
    expect(epoch.onConnectSuccess(), isTrue);
    expect(epoch.epoch, 1);
    expect(epoch.hasPendingDrop, isFalse);
    // Handshake display churn after success is not a drop.
    expect(epoch.onConnectSuccess(), isFalse);
    expect(epoch.epoch, 1);
  });

  test('multiple drops before one success advance once', () {
    final epoch = ReconnectRecoveryEpoch();
    epoch.onConnectSuccess();
    epoch.onDisconnectedAfterConnected();
    epoch.onDisconnectedAfterConnected();
    epoch.onDisconnectedAfterConnected();
    expect(epoch.onConnectSuccess(), isTrue);
    expect(epoch.epoch, 1);
  });

  test('resetLaunchSession clears the pending drop but never rewinds', () {
    final epoch = ReconnectRecoveryEpoch();
    epoch.onConnectSuccess();
    epoch.onDisconnectedAfterConnected();
    epoch.onConnectSuccess();
    epoch.onDisconnectedAfterConnected();
    epoch.resetLaunchSession();
    expect(epoch.hasPendingDrop, isFalse);
    expect(epoch.epoch, 1);
    expect(epoch.onConnectSuccess(), isFalse);
    expect(epoch.epoch, 1);
  });
}
