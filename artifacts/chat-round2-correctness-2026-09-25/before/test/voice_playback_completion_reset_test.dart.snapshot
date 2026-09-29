import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('voice playback enters playing before play and resets after completion',
      () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/utils/sound_record.dart',
    ).readAsStringSync();
    final playStart = source.indexOf('static Future<void> _playInternal({');
    final playEnd = source.indexOf('static Future<void> pause()', playStart);
    final playBody = source.substring(playStart, playEnd);
    final playing = playBody.indexOf('_setPhase(VoicePlaybackPhase.playing)');
    final play = playBody.indexOf('await _audioPlayer.play()');
    expect(playing, greaterThanOrEqualTo(0));
    expect(play, greaterThanOrEqualTo(0));
    expect(playing, lessThan(play));

    final completionStart =
        source.indexOf('static void _onPlayerStateChanged(');
    final completionEnd =
        source.indexOf('/// AVPlayer/ExoPlayer', completionStart);
    final completionBody = source.substring(completionStart, completionEnd);
    expect(completionBody, contains('Future<void>.delayed(Duration.zero'));
    expect(completionBody, contains('_setPhase(VoicePlaybackPhase.idle)'));
    expect(completionBody, contains('_activeMessageKeys.isNotEmpty'));
  });
}
