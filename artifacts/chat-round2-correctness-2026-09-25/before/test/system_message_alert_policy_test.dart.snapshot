import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/platform/system_message_alert_policy.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SystemMessageAlertPolicy.settingsResolver = null;
  });

  LocalSetting settings({
    bool systemMessage = true,
    bool sound = true,
    bool vibration = true,
  }) {
    final local = LocalSetting(autoLoad: false);
    local.notifySystemMessage = systemMessage;
    local.notifyMessageSound = sound;
    local.notifyVibration = vibration;
    return local;
  }

  group('SystemMessageAlertPolicy truth table', () {
    test('missing LocalSetting does not notify', () {
      final decision = SystemMessageAlertPolicy.decide(null);
      expect(decision.postNotice, isFalse);
      expect(decision.playSound, isFalse);
      expect(decision.playVibration, isFalse);
      expect(SystemMessageAlertPolicy.allowsNotice(null), isFalse);
    });

    test('system message off blocks notice sound and vibration', () {
      final decision = SystemMessageAlertPolicy.decide(
        settings(systemMessage: false, sound: true, vibration: true),
      );
      expect(decision.postNotice, isFalse);
      expect(decision.playSound, isFalse);
      expect(decision.playVibration, isFalse);
    });

    test('notice on sound off vibration off is silent display', () {
      final decision = SystemMessageAlertPolicy.decide(
        settings(systemMessage: true, sound: false, vibration: false),
      );
      expect(decision.postNotice, isTrue);
      expect(decision.playSound, isFalse);
      expect(decision.playVibration, isFalse);
    });

    test('notice on sound on vibration off plays sound only', () {
      final decision = SystemMessageAlertPolicy.decide(
        settings(systemMessage: true, sound: true, vibration: false),
      );
      expect(decision.postNotice, isTrue);
      expect(decision.playSound, isTrue);
      expect(decision.playVibration, isFalse);
    });

    test('notice on sound off vibration on vibrates only', () {
      final decision = SystemMessageAlertPolicy.decide(
        settings(systemMessage: true, sound: false, vibration: true),
      );
      expect(decision.postNotice, isTrue);
      expect(decision.playSound, isFalse);
      expect(decision.playVibration, isTrue);
    });

    test('all on posts with sound and vibration', () {
      final decision = SystemMessageAlertPolicy.decide(
        settings(systemMessage: true, sound: true, vibration: true),
      );
      expect(decision.postNotice, isTrue);
      expect(decision.playSound, isTrue);
      expect(decision.playVibration, isTrue);
    });
  });

  group('Android system-message channel mapping', () {
    test('matches native channel ids', () {
      expect(
        SystemMessageAlertPolicy.androidChannelId(
          playSound: true,
          playVibration: true,
        ),
        'system_message_sound_vibrate',
      );
      expect(
        SystemMessageAlertPolicy.androidChannelId(
          playSound: true,
          playVibration: false,
        ),
        'system_message_sound',
      );
      expect(
        SystemMessageAlertPolicy.androidChannelId(
          playSound: false,
          playVibration: true,
        ),
        'system_message_vibrate',
      );
      expect(
        SystemMessageAlertPolicy.androidChannelId(
          playSound: false,
          playVibration: false,
        ),
        'system_message_silent',
      );
    });
  });

  test('friend notice consumes the policy and does not play sound first', () {
    final source = File(
      'lib/src/services/friend_request_notice_service.dart',
    ).readAsStringSync();
    expect(source, contains('SystemMessageAlertPolicy.decide'));
    expect(source, contains('if (!decision.postNotice)'));
    expect(source, contains('useSystemMessageChannel: true'));
    expect(source, contains('enableReminderHaptic: playVibration'));
    expect(source, contains('if (playSound)'));
    expect(source, contains('InAppNotificationSound.playMessageReceived()'));
    expect(
      source.indexOf('SystemMessageAlertPolicy.decide'),
      lessThan(source.indexOf('InAppNotificationSound.playMessageReceived()')),
    );
  });

  test('native iOS willPresent and UserDefaults keys exist', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(source, contains('systemMessageNoticeEnabledDefaultsKey'));
    expect(source, contains('notifyMessageSoundEnabledDefaultsKey'));
    expect(source, contains('notifyVibrationEnabledDefaultsKey'));
    expect(source, contains('cacheSystemMessageAlertPreferences'));
    expect(source, contains('isFriendRequestNoticeType'));
    expect(source, contains('isSystemMessageNoticeEnabled'));
  });

  test('Android plugin uses dedicated system-message channels not DEFAULT_ALL', () {
    final source = File(
      'android/app/src/main/kotlin/vip/ninechat/pro/notification/AppSystemNotificationPlugin.kt',
    ).readAsStringSync();
    expect(source, contains('SystemMessageChannelPolicy.channelId'));
    expect(source, contains('useSystemMessageChannel'));
    expect(source, contains('ensureSystemMessageChannels'));
    expect(source, contains('CHAT_CHANNEL_ID = "message_push_channel"'));
  });
}
