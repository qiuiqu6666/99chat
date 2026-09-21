import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/in_app_notification_sound.dart';
import 'package:tencent_cloud_chat_demo/src/services/notification_sound_playback.dart';

void main() {
  tearDown(() {
    InAppNotificationSound.soundEnabledResolver = null;
  });

  group('InAppNotificationSound.shouldPlaySound', () {
    test('null resolver allows play', () {
      InAppNotificationSound.soundEnabledResolver = null;
      expect(InAppNotificationSound.shouldPlaySound(), isTrue);
    });

    test('disabled resolver blocks non-force play', () {
      InAppNotificationSound.soundEnabledResolver = () => false;
      expect(InAppNotificationSound.shouldPlaySound(), isFalse);
      expect(InAppNotificationSound.shouldPlaySound(force: true), isTrue);
    });

    test('enabled resolver allows play', () {
      InAppNotificationSound.soundEnabledResolver = () => true;
      expect(InAppNotificationSound.shouldPlaySound(), isTrue);
    });
  });

  group('NotificationSoundPlayback', () {
    test('reuses one loaded asset across notifications and loads a new choice',
        () async {
      var now = 1000;
      final loads = <String>[];
      var starts = 0;
      final lane = NotificationSoundPlayback(
        canPlay: () => true,
        prepare: () async {},
        load: (asset) async => loads.add(asset),
        rewind: () async {},
        play: () async => starts++,
        onError: (_, __) async {},
        onFinished: () {},
        nowMs: () => now,
      );
      await lane.request('a');
      now += 1000;
      await lane.request('a');
      now += 1000;
      await lane.request('b');
      expect(loads, ['a', 'b']);
      expect(starts, 3);
      await lane.request('a');
      expect(starts, 3);
    });

    test('busy bursts drop and only the latest forced preview is queued',
        () async {
      final first = Completer<void>();
      final loads = <String>[];
      var starts = 0;
      final lane = NotificationSoundPlayback(
        canPlay: () => true,
        prepare: () async {},
        load: (asset) async => loads.add(asset),
        rewind: () async {},
        play: () {
          starts++;
          return starts == 1 ? first.future : Future.value();
        },
        onError: (_, __) async {},
        onFinished: () {},
      );
      final task = lane.request('a');
      for (var i = 0; i < 100; i++) {
        lane.request('ordinary');
      }
      lane.request('b', force: true);
      lane.request('c', force: true);
      first.complete();
      await task;
      expect(loads, ['a', 'c']);
      expect(starts, 2);
    });

    test('call starting during prepare prevents load and playback', () async {
      var allowed = true;
      var loads = 0;
      var starts = 0;
      final lane = NotificationSoundPlayback(
        canPlay: () => allowed,
        prepare: () async {
          allowed = false;
        },
        load: (_) async => loads++,
        rewind: () async {},
        play: () async => starts++,
        onError: (_, __) async {},
        onFinished: () {},
      );
      await lane.request('a');
      expect(loads, 0);
      expect(starts, 0);
    });

    test('load errors use fallback and the next attempt can reload', () async {
      var loads = 0;
      var errors = 0;
      final lane = NotificationSoundPlayback(
        canPlay: () => true,
        prepare: () async {},
        load: (_) async {
          if (++loads == 1) throw StateError('load');
        },
        rewind: () async {},
        play: () async {},
        onError: (_, __) async => errors++,
        onFinished: () {},
      );
      await lane.request('a');
      await lane.request('a', force: true);
      expect(loads, 2);
      expect(errors, 1);
    });
  });
}
