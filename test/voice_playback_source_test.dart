import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/voice_playback_source.dart';

void main() {
  test('empty realtime metadata does not hide a hydrated URL', () {
    expect(firstVoicePlaybackSource(['', '  ', ' https://host/voice ']),
        'https://host/voice');
  });

  testWidgets('first tap waits beyond 400 ms for the download', (tester) async {
    final download = Completer<String?>();
    var finished = false;
    final result = waitForVoicePlaybackSource(
      localSource: () => null,
      remoteSource: () => null,
      prepareLocal: () => download.future,
    ).then((value) { finished = true; return value; });
    await tester.pump(const Duration(milliseconds: 600));
    expect(finished, isFalse);
    download.complete('/cache/voice.amr');
    expect(await result, '/cache/voice.amr');
  });

  test('download failure re-reads metadata populated during the wait', () async {
    String? remote;
    expect(await waitForVoicePlaybackSource(
      localSource: () => null,
      remoteSource: () => remote,
      prepareLocal: () async {
        remote = 'https://host/voice';
        throw StateError('download unavailable');
      },
    ), 'https://host/voice');
  });

  test('cached audio starts without another download', () async {
    expect(await waitForVoicePlaybackSource(
      localSource: () => '/cache/voice.amr',
      remoteSource: () => null,
      prepareLocal: () => throw StateError('must not download'),
    ), '/cache/voice.amr');
  });

  testWidgets('timeout falls back to the current remote address', (tester) async {
    final download = Completer<String?>();
    final result = waitForVoicePlaybackSource(
      localSource: () => null,
      remoteSource: () => 'https://host/voice',
      prepareLocal: () => download.future,
    );
    await tester.pump(const Duration(seconds: 10));
    expect(await result, 'https://host/voice');
    download.complete(null);
  });
}
