import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Exercise the real just_audio -> SoundPlayer -> conversation callback path.
// ignore: depend_on_referenced_packages
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_sound_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/sound_player_voice_route_bridge.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/sound_record.dart';

class _AudioPlatform extends JustAudioPlatform {
  _Player? latest;
  final players = <String, _Player>{};
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    return players[request.id] = latest = _Player(request.id);
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    players.remove(request.id)?.finish();
    return DisposePlayerResponse();
  }
}

class _Player extends AudioPlayerPlatform {
  _Player(super.id);
  final events = StreamController<PlaybackEventMessage>.broadcast();
  Completer<PlayResponse>? pendingPlay;
  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => events.stream;

  void emit(ProcessingStateMessage state) {
    events.add(PlaybackEventMessage(
      processingState: state,
      updateTime: DateTime.now(),
      updatePosition: Duration.zero,
      bufferedPosition: const Duration(seconds: 10),
      duration: const Duration(seconds: 10),
      icyMetadata: null,
      currentIndex: 0,
      androidAudioSessionId: null,
    ));
  }

  void finish() {
    final pending = pendingPlay;
    pendingPlay = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(PlayResponse());
    }
  }

  void completeVoice() {
    emit(ProcessingStateMessage.completed);
    finish();
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    emit(ProcessingStateMessage.ready);
    return LoadResponse(duration: const Duration(seconds: 10));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) {
    return (pendingPlay ??= Completer<PlayResponse>()).future;
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    finish();
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async => SeekResponse();
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

class _RouteBridge implements SoundPlayerVoiceRouteBridge {
  final route = ValueNotifier(SoundPlayerVoiceRoute.speaker);
  @override
  SoundPlayerVoiceRoute get currentRoute => route.value;
  @override
  bool get isSpeaker => true;
  @override
  ValueListenable<SoundPlayerVoiceRoute> get routeNotifier => route;
  @override
  bool get callOwnsAudioSession => false;
  @override
  AudioSessionConfiguration playbackConfigFor(SoundPlayerVoiceRoute route) =>
      const AudioSessionConfiguration.music();
  @override
  AudioSessionConfiguration voiceChatConfigFor(SoundPlayerVoiceRoute route) =>
      const AudioSessionConfiguration.speech();
  @override
  Future<void> ensureReady() async {}
  @override
  Future<bool> applyCurrentRoute(
          {bool configureSession = false,
          bool forRecording = false,
          bool activate = false}) async =>
      true;
  @override
  Future<bool> setRoute(SoundPlayerVoiceRoute target,
          {bool configureSession = true,
          bool forRecording = false,
          bool activate = true,
          bool forceApply = false}) async =>
      true;
}

class _GlobalWithEmptyHistory extends TUIChatGlobalModel {
  @override
  Future<V2TimMessageListResult?> getHistoryMessageListThroughIm06({
    HistoryMsgGetTypeEnum getType =
        HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
    String? userID,
    String? groupID,
    int lastMsgSeq = -1,
    required int count,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    List<int>? messageTypeList,
    List<int>? messageSeqList,
    int? timeBegin,
    int? timePeriod,
  }) async =>
      V2TimMessageListResult(messageList: [], isFinished: true);
}

Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 200; i++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail(
      'Playback did not reach the expected state: ${SoundPlayer.currentPhase}, ${SoundPlayer.playingMessageId}, native=${SoundPlayer.processingState} playing=${SoundPlayer.isPlaying}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'real player events continue without bubbles; pause and route exit cancel',
      () async {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.ryanheise.audio_session'),
            (_) async => null);
    final platform = _AudioPlatform();
    JustAudioPlatform.instance = platform;
    SoundPlayerVoiceRouteBridge.install(_RouteBridge());
    final directory = await Directory.systemTemp.createTemp('voice-chain-');
    final audio = File('${directory.path}/voice.aac')..writeAsBytesSync([0]);
    await serviceLocator.unregister<TUIChatGlobalModel>();
    final global = _GlobalWithEmptyHistory();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
    global.configureMessageWriterScope(
        ownerUserID: 'voice-test', accountGeneration: 1, domainGeneration: 1);
    final model = TUIChatSeparateViewModel()
      ..conversationID = 'voice-peer'
      ..conversationType = ConvType.c2c
      ..suppressReadReporting = true;
    final rows = [
      for (var i = 5; i >= 1; i--)
        V2TimMessage.fromJson({
          'message_msg_id': 'voice$i',
          'message_seq': '$i',
          'message_server_time': i,
          'message_status': 2,
          'message_risk_type_identified': 0,
        })
          ..msgID = 'voice$i'
          ..elemType = 4
          ..isSelf = true
          ..userID = 'voice-peer'
          ..soundElem = V2TimSoundElem(path: audio.path, duration: 10),
    ];
    global.setMessageList('voice-peer', rows,
        replace: true, applyMemoryWindow: false);
    try {
      // No TIMUIKitSoundElem is created at all. Only the model owns a callback.
      model.enableVoiceAutoPlayChain(message: rows.last);
      model.currentPlayedMsgId = 'voice1';
      final manual = SoundPlayer.handleBubbleTap(
          messageId: 'voice1', resolveUrl: () async => audio.path);
      await until(() =>
          platform.latest?.pendingPlay != null &&
          SoundPlayer.playingMessageId == 'voice1');
      for (var i = 2; i <= 4; i++) {
        platform.latest!.completeVoice();
        await until(() =>
            SoundPlayer.playingMessageId == 'voice$i' &&
            platform.latest?.pendingPlay != null);
        expect(model.currentPlayedMsgId, 'voice$i');
      }
      await manual;
      model.disableVoiceAutoPlayChain();
      await SoundPlayer.handleBubbleTap(
          messageId: 'voice4', resolveUrl: () async => audio.path);
      expect(SoundPlayer.currentPhase, VoicePlaybackPhase.paused);
      expect(model.voiceAutoPlayChainEnabled, isFalse);

      model.enableVoiceAutoPlayChain(message: rows[1]);
      final resumed = SoundPlayer.handleBubbleTap(
          messageId: 'voice4', resolveUrl: () async => audio.path);
      await until(() =>
          platform.latest?.pendingPlay != null &&
          SoundPlayer.currentPhase == VoicePlaybackPhase.playing);
      platform.latest!.completeVoice();
      await until(() =>
          SoundPlayer.playingMessageId == 'voice5' &&
          platform.latest?.pendingPlay != null);
      platform.latest!.completeVoice();
      await until(() => model.currentPlayedMsgId.isEmpty);
      expect(model.voiceAutoPlayChainEnabled, isTrue);
      final incoming = V2TimMessage.fromJson({
        'message_msg_id': 'voice6',
        'message_seq': '6',
        'message_server_time': 6,
        'message_status': 2,
        'message_risk_type_identified': 0,
      })
        ..msgID = 'voice6'
        ..elemType = 4
        ..isSelf = true
        ..userID = 'voice-peer'
        ..soundElem = V2TimSoundElem(path: audio.path, duration: 10);
      // Realtime first publishes a lightweight row; the completed-download
      // cache is the stable source while its full sound payload is hydrated.
      global.setFileMessageLocation('voice6', audio.path);
      await global.applyAppRealtimeMessage(incoming,
          ingressEventID: 'voice-new', ingressSequence: 6);
      await until(() =>
          SoundPlayer.playingMessageId == 'voice6' &&
          platform.latest?.pendingPlay != null);
      model.stopVoiceAutoPlay();
      await resumed;
      await until(() => SoundPlayer.currentPhase == VoicePlaybackPhase.idle);
      expect(model.voiceAutoPlayChainEnabled, isFalse);
      expect(model.currentPlayedMsgId, isEmpty);
      expect(SoundPlayer.playingMessageId, isNull);
    } finally {
      model.dispose();
      await SoundPlayer.stop();
      await directory.delete(recursive: true);
    }
  });
}
