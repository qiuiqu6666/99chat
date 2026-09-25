import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:tencent_cloud_chat_demo/src/services/livekit_call_session.dart';
import 'package:tencent_cloud_chat_demo/src/services/notification_settings_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/livekit_call_types.dart';

/// Shared ringtone policy for playback and media-session handoff.
bool shouldPlayRingtone({
  required LiveKitCallPhase phase,
  required bool hasRoom,
  bool isOutgoing = false,
  bool allowsIncomingRingtone = true,
}) {
  switch (phase) {
    case LiveKitCallPhase.ringingOut:
      // The caller joins the media room before the peer answers.
      return true;
    case LiveKitCallPhase.ringingIn:
      return !hasRoom && allowsIncomingRingtone;
    case LiveKitCallPhase.connecting:
      return isOutgoing;
    case LiveKitCallPhase.connected:
    case LiveKitCallPhase.ended:
    case LiveKitCallPhase.idle:
      return false;
  }
}

/// Plays legacy TUICallKit dial/ring tones for LiveKit call phases.
///
/// - Outgoing waiting: `phone_dialing.mp3`
/// - Incoming waiting: `phone_ringing.mp3`
/// Stops on connect / end / reject / cancel.
///
/// Ringtone only plays assets; AudioSession is owned by LiveKit / CallKit.
class LiveKitCallRingtone {
  LiveKitCallRingtone._();

  static final LiveKitCallRingtone instance = LiveKitCallRingtone._();

  static const String dialingAsset = 'assets/call_sounds/phone_dialing.mp3';
  static const String ringingAsset = 'assets/call_sounds/phone_ringing.mp3';

  final AudioPlayer _player = AudioPlayer(
    // We explicitly activate the short-lived ringtone session below. Without
    // this, outgoing ringing happens before LiveKit/CallKit owns AVAudioSession
    // and the player can be "playing" with no audible output on iOS.
    handleAudioSessionActivation: false,
  );
  AudioSession? _audioSession;
  bool _attached = false;
  String? _playingAsset;
  int _playGen = 0;
  Future<void> _commands = Future<void>.value();

  Future<void> ensureAttached() async {
    if (_attached) {
      _onSession();
      return;
    }
    LiveKitCallSession.instance.addListener(_onSession);
    _attached = true;
    _onSession();
  }

  Future<void> stop() async {
    _playGen++;
    _playingAsset = null;
    // Interrupt an asset load immediately; hangup/media handoff must not
    // wait behind a native load that may need stop() to finish.
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _commands.then((_) => action()).catchError((Object error) {
      debugPrint('LiveKitCallRingtone: audio command failed: $error');
    });
    _commands = next;
    return next;
  }

  Future<void> _prepareAudioSession(int generation) async {
    // A pre-connected caller still needs ringback, but LiveKit now owns the
    // session category/route. Do not replace voiceChat with music playback.
    if (generation != _playGen || LiveKitCallSession.instance.room != null) {
      return;
    }
    final session = _audioSession ??= await AudioSession.instance;
    if (generation != _playGen || LiveKitCallSession.instance.room != null) {
      return;
    }
    // Configure each new waiting period: the previous call may have changed
    // AVAudioSession's category even though this player instance survived.
    await session.configure(AudioSessionConfiguration.music());
    if (generation != _playGen || LiveKitCallSession.instance.room != null) {
      return;
    }
    // Keep this session active while waiting. LiveKit/CallKit will replace
    // the category when the call connects; we deliberately do not deactivate
    // here because that can race with the connection handoff.
    await session.setActive(true);
  }

  void _onSession() {
    final session = LiveKitCallSession.instance;
    final phase = session.phase;
    final hasRoom = session.room != null;
    if (!shouldPlayRingtone(
      phase: phase,
      hasRoom: hasRoom,
      isOutgoing: session.role == AppCallRole.caller,
      allowsIncomingRingtone:
          NotificationSettingsService.instance.allowsCallRingtone,
    )) {
      unawaited(stop());
      return;
    }
    switch (phase) {
      case LiveKitCallPhase.ringingOut:
      case LiveKitCallPhase.connecting:
        unawaited(_playLoop(dialingAsset, phase));
        break;
      case LiveKitCallPhase.ringingIn:
        unawaited(_playLoop(ringingAsset, phase));
        break;
      case LiveKitCallPhase.connected:
      case LiveKitCallPhase.ended:
      case LiveKitCallPhase.idle:
        unawaited(stop());
        break;
    }
  }

  Future<void> _playLoop(String asset, LiveKitCallPhase phase) async {
    if (_playingAsset == asset) {
      // Includes setup in flight, so repeated room notifications cannot
      // continually restart setAsset before playback gets a chance to begin.
      return;
    }
    final gen = ++_playGen;
    _playingAsset = asset;
    await _enqueue(() async {
      if (gen != _playGen) return;
      try {
        await _prepareAudioSession(gen);
        if (gen != _playGen) return;
        await _player.stop();
        if (gen != _playGen) return;
        await _player.setLoopMode(LoopMode.one);
        if (gen != _playGen) return;
        // phone_dialing.mp3 starts with ~1.98 seconds of silence. Start at
        // its first audible tone so page entry gives immediate feedback.
        // The full asset still loops with its original ringback cadence.
        await _player.setAsset(
          asset,
          initialPosition: asset == dialingAsset
              ? const Duration(seconds: 2)
              : Duration.zero,
        );
        if (gen != _playGen) return;
        await _player.setVolume(1);
        if (gen != _playGen) return;
        // play() completes only when looping stops; never hold the command
        // queue on it, otherwise accept/hangup cannot stop the waiting tone.
        unawaited(_player.play().catchError((Object error) {
          if (gen == _playGen) {
            _playingAsset = null;
          }
          debugPrint('LiveKitCallRingtone: playback failed: $error');
        }));
        if (kDebugMode) {
          debugPrint(
            'LiveKitCallRingtone: playing $asset phase=$phase '
            'hasRoom=${LiveKitCallSession.instance.room != null}',
          );
        }
      } catch (e, st) {
        if (gen == _playGen) {
          _playingAsset = null;
        }
        if (kDebugMode) {
          debugPrint('LiveKitCallRingtone: play failed: $e\n$st');
        }
      }
    });
  }
}
