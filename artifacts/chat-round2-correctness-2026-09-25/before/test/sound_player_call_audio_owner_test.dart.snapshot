import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/sound_player_voice_route_bridge.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/sound_record.dart';

class _OwnerBridge implements SoundPlayerVoiceRouteBridge {
  _OwnerBridge({required this.owns});

  final bool owns;
  final ValueNotifier<SoundPlayerVoiceRoute> _notifier =
      ValueNotifier<SoundPlayerVoiceRoute>(SoundPlayerVoiceRoute.speaker);

  @override
  SoundPlayerVoiceRoute get currentRoute => _notifier.value;

  @override
  bool get isSpeaker => true;

  @override
  ValueListenable<SoundPlayerVoiceRoute> get routeNotifier => _notifier;

  @override
  bool get callOwnsAudioSession => owns;

  @override
  AudioSessionConfiguration playbackConfigFor(SoundPlayerVoiceRoute route) {
    return const AudioSessionConfiguration.music();
  }

  @override
  AudioSessionConfiguration voiceChatConfigFor(SoundPlayerVoiceRoute route) {
    return const AudioSessionConfiguration.speech();
  }

  @override
  Future<void> ensureReady() async {}

  @override
  Future<bool> applyCurrentRoute({
    bool configureSession = false,
    bool forRecording = false,
    bool activate = false,
  }) async =>
      true;

  @override
  Future<bool> setRoute(
    SoundPlayerVoiceRoute target, {
    bool configureSession = true,
    bool forRecording = false,
    bool activate = true,
    bool forceApply = false,
  }) async {
    _notifier.value = target;
    return true;
  }
}

void main() {
  tearDown(() {
    SoundPlayerVoiceRouteBridge.install(_OwnerBridge(owns: false));
  });

  test('default bridge does not claim call audio session', () {
    SoundPlayerVoiceRouteBridge.install(_OwnerBridge(owns: false));
    expect(soundPlayerVoiceRouteBridge.callOwnsAudioSession, isFalse);
    expect(SoundPlayer.shouldSkipPlaybackSessionMutation(), isFalse);
  });

  test('call owner skips IM voice session mutation', () {
    SoundPlayerVoiceRouteBridge.install(_OwnerBridge(owns: true));
    expect(soundPlayerVoiceRouteBridge.callOwnsAudioSession, isTrue);
    expect(SoundPlayer.shouldSkipPlaybackSessionMutation(), isTrue);
  });

  test('ensurePlaybackReady is a no-op when call owns session', () async {
    SoundPlayerVoiceRouteBridge.install(_OwnerBridge(owns: true));
    // Must not throw or hang when AudioSession would otherwise configure.
    await SoundPlayer.ensurePlaybackReady(force: true);
    expect(SoundPlayer.shouldSkipPlaybackSessionMutation(), isTrue);
  });
}
