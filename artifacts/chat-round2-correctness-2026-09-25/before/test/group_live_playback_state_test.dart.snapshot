import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_playback_state.dart';

void main() {
  late StreamController<String> errors;
  late StreamController<Duration> positions;
  late StreamController<bool> completed;
  late GroupLivePlaybackState playback;
  late List<String> commands;
  Future<void> Function(String)? openOverride;

  setUp(() {
    errors = StreamController<String>.broadcast(sync: true);
    positions = StreamController<Duration>.broadcast(sync: true);
    completed = StreamController<bool>.broadcast(sync: true);
    commands = [];
    openOverride = null;
    playback = GroupLivePlaybackState(
      openUrl: (url) async {
        commands.add(url);
        await openOverride?.call(url);
      },
      pause: () async {
        commands.add('pause');
      },
      errors: errors.stream,
      positions: positions.stream,
      completed: completed.stream,
    );
  });
  tearDown(() async {
    playback.dispose();
    await errors.close();
    await positions.close();
    await completed.close();
  });

  test('MPV seek diagnostics do not hide a live stream', () {
    errors.add('Cannot seek in this stream.\n');
    errors.add("You can force it with '--force-seekable=yes'.\n");
    expect(playback.error, isNull);
    errors.add('Connection refused');
    expect(playback.error, '直播播放异常，请重试');
    // A seek diagnostic must not erase a real failure either.
    errors.add('Cannot seek in this stream.');
    expect(playback.error, isNotNull);
  });

  test('progress clears failures; repeated positions do not', () {
    positions.add(const Duration(seconds: 10));
    errors.add('decoder failed');
    positions.add(const Duration(seconds: 10));
    expect(playback.error, isNotNull);
    positions.add(const Duration(seconds: 11));
    expect(playback.error, isNull);
  });

  test('EOF then foreground reopens URL without seeking', () async {
    await playback.open('https://example.com/live.flv');
    completed.add(true);
    expect(playback.error, isNotNull);
    await playback.pause();
    await playback.resume();
    await playback.resume();
    expect(commands, [
      'https://example.com/live.flv',
      'pause',
      'https://example.com/live.flv',
    ]);
    expect(playback.error, isNull);
  });

  test('open acknowledgement cannot erase a stream error', () async {
    openOverride = (_) async {
      errors.add('network failure');
    };
    await playback.open('https://example.com/live.flv');
    expect(playback.error, isNotNull);
    openOverride = null;
    await playback.retry();
    expect(playback.error, isNull);
    expect(commands.length, 2);
  });

  test('exceptions are contained and retry works', () async {
    openOverride = (_) async {
      throw StateError('open failed');
    };
    await playback.open('https://example.com/live.flv');
    expect(playback.error, '直播连接失败，请重试');
    openOverride = null;
    await playback.retry();
    expect(playback.error, isNull);
  });

  test('invalid addresses do not reach the native player', () async {
    for (final url in ['', 'file:///tmp/live', 'https://']) {
      await playback.open(url);
      expect(playback.error, '直播地址无效');
    }
    expect(commands, isEmpty);
  });

  test('URL changes coalesce and preserve the latest request', () async {
    final first = playback.open('https://example.com/old');
    final second = playback.open('https://example.com/new');
    await Future.wait([first, second]);
    expect(commands, ['https://example.com/new']);
  });

  test('pause waits for open; foreground joins the latest live URL', () async {
    final gate = Completer<void>();
    openOverride = (_) => gate.future;
    final opening = playback.open('https://example.com/old');
    await Future<void>.delayed(Duration.zero);
    final paused = playback.pause();
    final changed = playback.open('https://example.com/new');
    final resumed = playback.resume();
    gate.complete();
    await Future.wait([opening, paused, changed, resumed]);
    expect(commands,
        ['https://example.com/old', 'pause', 'https://example.com/new']);
  });
}
