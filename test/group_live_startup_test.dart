import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_startup.dart';

GroupLivePlayInfo info(
        {String primary = 'https://host/live.flv',
        String protocol = 'flv',
        String rtc = ''}) =>
    GroupLivePlayInfo(
        liveSessionId: 's',
        roomName: 'r',
        protocol: protocol,
        playUrl: primary,
        anchorUserId: 'u',
        webrtcPlayUrl: rtc,
        fallbackFlvUrl: 'https://fallback/live.flv',
        fallbackHlsUrl: 'https://fallback/live.m3u8');

void main() {
  test('HTTP primary precedes fallback and unsupported signalling is excluded',
      () {
    expect(groupLiveHttpSources(info()).first, 'https://host/live.flv');
    expect(
        groupLiveHttpSources(
            info(primary: 'webrtc://host/live', protocol: 'webrtc')),
        ['https://fallback/live.flv', 'https://fallback/live.m3u8']);
    expect(
        groupLiveHttpSources(
                info(primary: 'https://host/signalling', protocol: 'webrtc'))
            .first,
        'https://fallback/live.flv');
    expect(
        groupLiveHttpSources(info(primary: 'https://fallback/live.flv')).length,
        2);
  });

  testWidgets('loading persists until frame, timeout can recover on late frame',
      (tester) async {
    final state = GroupLiveStartup();
    final frame = Completer<void>();
    state.waitForFrame(frame.future);
    expect(state.ready, isFalse);
    await tester.pump(const Duration(seconds: 12));
    expect(state.timedOut, isTrue);
    frame.complete();
    await tester.pump();
    expect(state.ready, isTrue);
    expect(state.timedOut, isFalse);
    state.dispose();
  });

  testWidgets(
      'obsolete frame and disposed timers cannot update current attempt',
      (tester) async {
    final state = GroupLiveStartup();
    final old = Completer<void>();
    final current = Completer<void>();
    state.waitForFrame(old.future);
    state.waitForFrame(current.future);
    old.complete();
    await tester.pump();
    expect(state.ready, isFalse);
    state.suspend();
    await tester.pump(const Duration(minutes: 1));
    expect(state.timedOut, isFalse);
    state.dispose();
    current.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
