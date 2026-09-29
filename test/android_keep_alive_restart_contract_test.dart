import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual stop disables every native restart path', () {
    final root = 'android/app/src/main/kotlin/vip/ninechat/pro/keepalive';
    final scheduler = File('$root/KeepAliveScheduler.kt').readAsStringSync();
    final service =
        File('$root/KeepAliveForegroundService.kt').readAsStringSync();
    final alarm = File('$root/KeepAliveAlarmReceiver.kt').readAsStringSync();
    final boot = File('$root/KeepAliveRestartReceiver.kt').readAsStringSync();
    final worker = File('$root/KeepAliveWatchdogWorker.kt').readAsStringSync();

    expect(scheduler, contains('fun disableAndCancel'));
    expect(scheduler, contains('KEY_ENABLED, false'));
    expect(scheduler, contains('if (!isEnabled(appContext))'));
    expect(scheduler, contains('alarmManager.cancel(pendingIntent)'));
    expect(
        service, contains('KeepAliveScheduler.disableAndCancel(appContext)'));
    expect(service,
        contains('KeepAliveScheduler.scheduleRestart(applicationContext'));
    expect(alarm, contains('if (!KeepAliveScheduler.isEnabled(context))'));
    expect(boot, contains('if (!KeepAliveScheduler.isEnabled(context))'));
    expect(worker,
        contains('if (!KeepAliveScheduler.isEnabled(applicationContext))'));
  });
}
