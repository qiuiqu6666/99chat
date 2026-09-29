import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:tencent_cloud_chat_demo/src/models/message_notification_sound.dart';
import 'package:tencent_cloud_chat_demo/src/services/livekit_call_session.dart';
import 'package:tencent_cloud_chat_demo/src/services/notification_sound_playback.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/sound_record.dart';

/// 应用内消息横幅提示音。
class InAppNotificationSound {
  InAppNotificationSound._();

  static final AudioPlayer _player = AudioPlayer(
    handleAudioSessionActivation: false,
  );
  static bool _sessionConfigured = false;
  static final _playback = NotificationSoundPlayback(
    canPlay: () => !LiveKitCallSession.instance.isInCall,
    prepare: _ensureSession,
    load: (asset) async {
      await _player.setAsset(asset);
      await _player.setVolume(1);
    },
    rewind: () async {
      // Unlike stop(), pause preserves just_audio's native player/decoder.
      await _player.pause();
      await _player.seek(Duration.zero);
    },
    play: _player.play,
    onError: (error, stack) async {
      if (kDebugMode) {
        debugPrint('InAppNotificationSound fallback: $error\n$stack');
      }
      await _playSystemFallback();
    },
    onFinished: SoundPlayer.invalidatePlaybackSession,
  );

  /// 由 main.dart 注入，用于在无 [LocalSetting] 上下文时解析当前提示音。
  static String Function()? soundIdResolver;

  /// 由 main.dart 注入：是否允许应用内提示音（对应「消息提示音」开关）。
  /// `force: true`（设置页试听）不受此限制。
  static bool Function()? soundEnabledResolver;

  /// Whether a non-preview play is allowed by [soundEnabledResolver].
  static bool shouldPlaySound({bool force = false}) {
    if (force) return true;
    final enabled = soundEnabledResolver?.call();
    if (enabled == false) return false;
    return true;
  }

  static Future<void> playMessageReceived() async {
    final soundId =
        soundIdResolver?.call() ?? MessageNotificationSound.defaultId;
    await playSound(soundId);
  }

  static Future<void> playSound(String soundId, {bool force = false}) async {
    if (!shouldPlaySound(force: force)) return;
    final option = MessageNotificationSound.fromId(soundId);
    await _playback.request(option.assetPath, force: force);
  }

  static Future<void> _playSystemFallback() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint(
            'InAppNotificationSound system fallback failed: $error\n$stack');
      }
    }
  }

  static Future<void> _ensureSession() async {
    final session = await AudioSession.instance;
    if (!_sessionConfigured) {
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.ambient,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.mixWithOthers,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.sonification,
            usage: AndroidAudioUsage.notification,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientMayDuck,
          androidWillPauseWhenDucked: false,
        ),
      );
      _sessionConfigured = true;
      SoundPlayer.invalidatePlaybackSession();
    }
    try {
      await session.setActive(true);
    } catch (_) {}
  }
}
