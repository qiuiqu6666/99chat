import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/voice_output_route_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('speaker and earpiece keep distinct playback session modes', () {
    final speaker = VoiceOutputRouteService.playbackConfigFor(
      VoiceOutputRoute.speaker,
    );
    final earpiece = VoiceOutputRouteService.playbackConfigFor(
      VoiceOutputRoute.earpiece,
    );

    expect(speaker.avAudioSessionCategory, AVAudioSessionCategory.playback);
    expect(
      earpiece.avAudioSessionCategory,
      AVAudioSessionCategory.playAndRecord,
    );
  });

  test('native route is restored after session activation', () {
    final source = File(
      'lib/src/services/voice_output_route_service.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final activate = source.indexOf('await session.setActive(true)');
    final nativeRoute = source.indexOf(
      'await _applyNativeRoute(requestedRoute)',
    );

    expect(activate, greaterThan(-1));
    expect(nativeRoute, greaterThan(activate));
  });

  test('user route intent is stored before asynchronous native work', () {
    final source = File(
      'lib/src/services/voice_output_route_service.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final setterStart = source.indexOf('static Future<bool> setRoute(');
    final setterEnd = source.indexOf(
      'static Future<void> _applyNativeRoute(',
      setterStart,
    );
    final setter = source.substring(setterStart, setterEnd);
    final persist = setter.indexOf('routeNotifier.value = route');
    final session =
        setter.indexOf('final session = await AudioSession.instance');

    expect(persist, greaterThan(-1));
    expect(session, greaterThan(persist));
  });

  test('every new voice source reapplies current route before play', () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/utils/sound_record.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final playStart = source.indexOf('static Future<void> _playInternal({');
    final playEnd = source.indexOf(
      'static Future<void> pause()',
      playStart,
    );
    final playSource = source.substring(playStart, playEnd);
    final setSource = playSource.indexOf('await _audioPlayer.setAudioSource(');
    final applyRoute =
        playSource.indexOf('await _applyOutputRoute(configureSession: true)');
    final play = playSource.indexOf('await _audioPlayer.play()');

    expect(setSource, greaterThan(-1));
    expect(applyRoute, greaterThan(setSource));
    expect(play, greaterThan(applyRoute));
  });

  test('actual playing state reasserts route after player takes control', () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/utils/sound_record.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(
      source,
      contains(
          'if (state.playing) {\n      _reassertRouteAfterPlaybackStarted();'),
    );
    expect(source, contains('Duration(milliseconds: 160)'));
    expect(source, contains('await _applyOutputRoute();'));
    expect(
      source,
      contains(
        'if (_playbackPhase == VoicePlaybackPhase.loading ||',
      ),
    );
  });

  test('live speaker toggle reconfigures session and resumes current playback',
      () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/utils/sound_record.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final start = source.indexOf('static Future<bool> _setSpeakerOnInternal(');
    final end = source.indexOf('static Future<bool> toggleSpeaker(');
    expect(start, greaterThan(-1));
    expect(end, greaterThan(start));
    final body = source.substring(start, end);
    expect(body, contains('configureSession: true'));
    expect(body, contains('configureSession: false'));
    expect(body, contains('forceApply: true'));
    expect(body, contains('await _audioPlayer.pause()'));
    expect(body, contains('unawaited(_audioPlayer.play()'));
    expect(body, contains('_applyingRouteChange = true'));
    expect(body, contains('Duration(milliseconds: 400)'));
    expect(body, contains('final resumeKeys = Set<String>.from(_activeMessageKeys)'));
    expect(body, isNot(contains('if (!success) {\n        return false;')));

    final playerSource = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/utils/sound_record.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(
      playerSource,
      contains(
        'if (state.processingState == ProcessingState.completed) {\n'
        '      if (_applyingRouteChange) {\n'
        '        return;',
      ),
    );
    final persistSource = File(
      'lib/src/services/voice_output_route_service.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(persistSource, contains('unawaited(_persistImPreference(route))'));
  });

  test('session reconfigure during route switch does not user-pause playback',
      () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/utils/sound_record.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(source, contains('if (_applyingRouteChange) {\n        return;'));
  });

  test('legacy iOS recorder/player do not mutate the shared audio session', () {
    for (final path in <String>[
      'third_party/flutter_plugin_record_plus/ios/Classes/DPAudioRecorder.m',
      'third_party/flutter_plugin_record_plus/ios/Classes/DPAudioPlayer.m',
    ]) {
      final source = File(path).readAsStringSync().replaceAll('\r\n', '\n');
      expect(source, isNot(contains('setCategory:')));
      expect(source, isNot(contains('setActive:')));
      expect(source, isNot(contains('overrideOutputAudioPort(')));
    }
  });

  test('CallKit playAndRecord configuration does not request A2DP', () {
    final source = File(
      'ios/Runner/SelfHostedVoipCallKit.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final start = source.indexOf('private func configureAudioSession()');
    final end = source.indexOf('private func deactivateAudioSession()', start);
    expect(start, greaterThan(-1));
    expect(end, greaterThan(start));
    expect(source.substring(start, end), isNot(contains('allowBluetoothA2DP')));
  });

  test('tooltip rebuilds speaker/earpiece labels from route notifier', () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKItMessageList/tim_uikit_chat_message_tooltip.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(
      source,
      contains('SoundPlayer.outputRouteListenable.addListener'),
    );
    expect(
      source,
      contains("SoundPlayer.speakerOn ? '听筒' : '扬声器'"),
    );
    expect(source, contains('SoundPlayer.ensureRouteReady'));
    expect(
      source,
      contains("SoundPlayer.speakerOn ? _tipLabel('听筒') : _tipLabel('扬声器')"),
    );
    final app = File('lib/src/pages/app.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(app, contains('VoiceOutputRouteService.imVoiceRouteNotifier'));
    expect(app, contains('VoiceOutputRouteService.setImVoiceRoute'));
  });

  test('IM preference load and persist survive process-style reload', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VoiceOutputRouteService.debugResetImPreferenceForTest();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(VoiceOutputRouteService.imVoiceRoutePrefsKey);
    await VoiceOutputRouteService.ensureImPreferenceLoaded();
    expect(VoiceOutputRouteService.imVoiceRoute, VoiceOutputRoute.speaker);

    await prefs.setString(
      VoiceOutputRouteService.imVoiceRoutePrefsKey,
      'earpiece',
    );
    VoiceOutputRouteService.debugResetImPreferenceForTest();
    await VoiceOutputRouteService.ensureImPreferenceLoaded();
    expect(VoiceOutputRouteService.imVoiceRoute, VoiceOutputRoute.earpiece);
  });

  test('setImVoiceRoute writes prefs; setRoute does not', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VoiceOutputRouteService.debugResetImPreferenceForTest();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(VoiceOutputRouteService.imVoiceRoutePrefsKey);
    try {
      await VoiceOutputRouteService.setImVoiceRoute(
        VoiceOutputRoute.earpiece,
        configureSession: false,
        activate: false,
      );
    } catch (_) {}
    await Future<void>.delayed(Duration.zero);
    expect(VoiceOutputRouteService.imVoiceRoute, VoiceOutputRoute.earpiece);
    expect(
      prefs.getString(VoiceOutputRouteService.imVoiceRoutePrefsKey),
      'earpiece',
    );

    VoiceOutputRouteService.debugResetImPreferenceForTest();
    await prefs.remove(VoiceOutputRouteService.imVoiceRoutePrefsKey);
    try {
      await VoiceOutputRouteService.setRoute(VoiceOutputRoute.earpiece);
    } catch (_) {}
    expect(
      prefs.getString(VoiceOutputRouteService.imVoiceRoutePrefsKey),
      isNull,
    );
    expect(VoiceOutputRouteService.imVoiceRoute, VoiceOutputRoute.speaker);
  });

  test('call paths do not persist IM preference and restore after hangup', () {
    final livekit = File('lib/src/services/livekit_call_session.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(livekit, isNot(contains('setImVoiceRoute')));
    expect(livekit, isNot(contains('imVoiceRoutePrefsKey')));
    expect(
      livekit,
      contains('unawaited(VoiceOutputRouteService.reapplyImVoiceRouteToLive())'),
    );

    final callManager = File(
      'third_party/tencent_calls_uikit/lib/src/impl/call_manager.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(callManager, contains('return VoiceOutputRoute.speaker;'));
    expect(
      callManager,
      isNot(contains('return VoiceOutputRouteService.currentRoute;')),
    );

    final callState = File(
      'third_party/tencent_calls_uikit/lib/src/impl/call_state.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(
      callState,
      contains('unawaited(VoiceOutputRouteService.reapplyImVoiceRouteToLive())'),
    );
  });

  test('play applies IM route only after preference is loaded', () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/utils/sound_record.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final playStart = source.indexOf('static Future<void> _playInternal({');
    final playEnd = source.indexOf(
      'static Future<void> pause()',
      playStart,
    );
    final playSource = source.substring(playStart, playEnd);
    final ensureReady =
        playSource.indexOf('await soundPlayerVoiceRouteBridge.ensureReady()');
    final applyRoute =
        playSource.indexOf('await _applyOutputRoute(configureSession: true)');
    expect(ensureReady, greaterThan(-1));
    expect(applyRoute, greaterThan(ensureReady));
  });
}
