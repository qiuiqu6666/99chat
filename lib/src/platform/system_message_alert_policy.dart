import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';

/// 系统消息提醒真值（好友申请等同系统消息）。
///
/// 进程内前台/后台/锁屏必须遵守本策略。杀进程后的远程 APNS 音震取决于
/// 服务端载荷，客户端无法在展示前改写，不能把前台修好当成后台完成。
class SystemMessageAlertDecision {
  const SystemMessageAlertDecision({
    required this.postNotice,
    required this.playSound,
    required this.playVibration,
  });

  final bool postNotice;
  final bool playSound;
  final bool playVibration;
}

class SystemMessageAlertPolicy {
  SystemMessageAlertPolicy._();

  static const String androidChannelSoundVibrate =
      'system_message_sound_vibrate';
  static const String androidChannelSound = 'system_message_sound';
  static const String androidChannelVibrate = 'system_message_vibrate';
  static const String androidChannelSilent = 'system_message_silent';

  /// Wired from [NotificationSettingsService.attach]. Null → 不允许通知.
  static LocalSetting? Function()? settingsResolver;

  static LocalSetting? currentSettings() => settingsResolver?.call();

  static bool allowsNotice(LocalSetting? settings) {
    if (settings == null) {
      return false;
    }
    return settings.notifySystemMessage;
  }

  static bool playSound(LocalSetting? settings) {
    return allowsNotice(settings) && settings!.notifyMessageSound;
  }

  static bool playVibration(LocalSetting? settings) {
    return allowsNotice(settings) && settings!.notifyVibration;
  }

  static SystemMessageAlertDecision decide(LocalSetting? settings) {
    if (!allowsNotice(settings)) {
      return const SystemMessageAlertDecision(
        postNotice: false,
        playSound: false,
        playVibration: false,
      );
    }
    return SystemMessageAlertDecision(
      postNotice: true,
      playSound: settings!.notifyMessageSound,
      playVibration: settings.notifyVibration,
    );
  }

  static String androidChannelId({
    required bool playSound,
    required bool playVibration,
  }) {
    if (playSound && playVibration) {
      return androidChannelSoundVibrate;
    }
    if (playSound) {
      return androidChannelSound;
    }
    if (playVibration) {
      return androidChannelVibrate;
    }
    return androidChannelSilent;
  }
}
