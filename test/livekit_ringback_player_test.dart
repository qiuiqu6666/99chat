import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Exercise the actual just_audio player with only its native backend replaced.
// ignore: depend_on_referenced_packages
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/livekit_call_ringtone.dart';
import 'package:tencent_cloud_chat_demo/src/services/livekit_call_session.dart';

class _Audio extends JustAudioPlatform {
  int loads = 0;
  int plays = 0;
  final initialPositions = <Duration?>[];
  final seekPositions = <Duration?>[];
  Completer<void> loadGate = Completer<void>();
  final players = <String, _Player>{};
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async =>
      players[request.id] = _Player(request.id, this);
  @override
  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    players.remove(request.id)?.finish();
    return DisposePlayerResponse();
  }
}

class _Player extends AudioPlayerPlatform {
  _Player(super.id, this.owner);
  final _Audio owner;
  final events = StreamController<PlaybackEventMessage>.broadcast();
  final disposed = Completer<void>();
  Completer<PlayResponse>? pending;
  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => events.stream;
  void finish() {
    if (!disposed.isCompleted) disposed.complete();
    if (pending?.isCompleted == false) pending!.complete(PlayResponse());
    pending = null;
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    owner.loads++;
    owner.initialPositions.add(request.initialPosition);
    await Future.any([owner.loadGate.future, disposed.future]);
    events.add(PlaybackEventMessage(
      processingState: ProcessingStateMessage.ready,
      updateTime: DateTime.now(),
      updatePosition: Duration.zero,
      bufferedPosition: const Duration(seconds: 2),
      duration: const Duration(seconds: 48),
      icyMetadata: null,
      currentIndex: 0,
      androidAudioSessionId: null,
    ));
    return LoadResponse(duration: const Duration(seconds: 48));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) {
    owner.plays++;
    return (pending = Completer<PlayResponse>()).future;
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    finish();
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    owner.seekPositions.add(request.position);
    return SeekResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();
  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();
  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async =>
      SetPitchResponse();
  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
          SetSkipSilenceRequest request) async =>
      SetSkipSilenceResponse();
  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();
  @override
  Future<SetShuffleModeResponse> setShuffleMode(
          SetShuffleModeRequest request) async =>
      SetShuffleModeResponse();
  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
          SetShuffleOrderRequest request) async =>
      SetShuffleOrderResponse();
  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
          SetAndroidAudioAttributesRequest request) async =>
      SetAndroidAudioAttributesResponse();
  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
              SetAutomaticallyWaitsToMinimizeStallingRequest request) async =>
          SetAutomaticallyWaitsToMinimizeStallingResponse();
}

Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 200; i++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Ringback player did not reach the expected state');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('loading notifications coalesce; hangup stops loop and next call plays',
      () async {
    SharedPreferences.setMockInitialValues({});
    final cache = Directory('test_outputs/ringback_audio_cache').absolute;
    await cache.create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => cache.path,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'),
      (_) async => null,
    );
    final original = JustAudioPlatform.instance;
    final audio = _Audio();
    JustAudioPlatform.instance = audio;
    final ringtone = LiveKitCallRingtone.instance;
    final session = LiveKitCallSession.instance;
    try {
      await session.prepareOutgoingPending(calleeUserId: 'peer', video: false);
      // Opening a caller page attaches the player before invite has returned.
      await ringtone.ensureAttached();
      await _until(() => audio.loads == 1);
      for (var i = 0; i < 20; i++) {
        await session.setMicrophoneEnabled(false);
      }
      expect(audio.loads, 1);
      audio.loadGate.complete();
      await _until(() => audio.plays == 1);
      expect(session.callId, isEmpty);
      expect(audio.initialPositions.single, const Duration(seconds: 2));
      expect(audio.seekPositions, isNot(contains(Duration.zero)));
      await session.cancelOutgoing().timeout(const Duration(seconds: 2));
      await ringtone.stop().timeout(const Duration(seconds: 2));
      expect(audio.players, isEmpty);
      // A new asset load must remain cancellable before it has completed.
      audio.loadGate = Completer<void>();
      final previousLoads = audio.loads;
      await session.prepareOutgoingPending(calleeUserId: 'peer', video: false);
      await _until(() => audio.loads > previousLoads);
      await session.cancelOutgoing().timeout(const Duration(seconds: 2));
      await ringtone.stop().timeout(const Duration(seconds: 2));
      expect(audio.plays, 1);
      expect(audio.players, isEmpty);
      audio.loadGate.complete();
      await session.prepareOutgoingPending(calleeUserId: 'peer', video: true);
      await _until(() => audio.plays == 2);
      expect(audio.initialPositions.last, const Duration(seconds: 2));
      await session.cancelOutgoing().timeout(const Duration(seconds: 2));
      await ringtone.stop().timeout(const Duration(seconds: 2));
      expect(audio.players, isEmpty);
    } finally {
      if (!audio.loadGate.isCompleted) audio.loadGate.complete();
      if (session.isBusy) await session.cancelOutgoing();
      await ringtone.stop();
      JustAudioPlatform.instance = original;
    }
  });
}
