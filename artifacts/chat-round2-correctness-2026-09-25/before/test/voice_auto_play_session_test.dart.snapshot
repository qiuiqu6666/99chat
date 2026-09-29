import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/voice_auto_play_session.dart';

V2TimMessage row(int n, {bool sound = true}) => V2TimMessage.fromJson({
      'message_msg_id': 'm$n',
      'message_seq': '$n',
      'message_server_time': n,
      'message_status': 2,
      'message_risk_type_identified': 0,
    })
      ..msgID = 'm$n'
      ..id = 'local$n'
      ..timestamp = n
      ..seq = '$n'
      ..status = 2
      ..elemType = sound
          ? MessageElemType.V2TIM_ELEM_TYPE_SOUND
          : MessageElemType.V2TIM_ELEM_TYPE_TEXT;

Future<void> flush() => Future<void>.delayed(Duration.zero);

class Harness {
  Harness(this.rows) {
    session = VoiceAutoPlaySession(
      messagesNewestFirst: () => rows,
      loadNewer: (anchor) async {
        historyReads.add(anchor.msgID!);
        return await loader?.call(anchor) ?? [];
      },
      play: (message, valid) async {
        played.add(message.msgID!);
        if (player != null) return player!(message, valid);
        unawaited(session.completed(message.msgID!));
        return true;
      },
      onSelected: (message) => selected = message.msgID,
      onWaiting: () => selected = null,
      onError: (error, stack) => errors.add(error),
    );
  }

  List<V2TimMessage> rows;
  final played = <String>[];
  final historyReads = <String>[];
  final errors = <Object>[];
  String? selected;
  late VoiceAutoPlaySession session;
  Future<List<V2TimMessage>> Function(V2TimMessage)? loader;
  Future<bool> Function(V2TimMessage, bool Function())? player;
}

void main() {
  test('continues 80 voices without any bubble or a 32-item limit', () async {
    final h = Harness([for (var i = 80; i >= 1; i--) row(i)]);
    h.session.start(row(1));
    await h.session.completed('m1');
    expect(h.played, [for (var i = 2; i <= 80; i++) 'm$i']);
    expect(h.session.enabled, isTrue);
    expect(h.session.waiting, isTrue);
    expect(h.selected, isNull);
  });

  test('server acknowledgement keeps the original completion alias', () async {
    final a = row(1);
    final h = Harness([row(2), a]);
    h.session.start(a);
    a.msgID = 'acknowledged1';
    expect(h.session.currentMessageId, 'acknowledged1');
    expect(h.session.currentClientMessageId, 'local1');
    await h.session.completed('local1');
    expect(h.played, ['m2']);
  });

  test('duplicate completion cannot skip the current voice', () async {
    final h = Harness([row(3), row(2), row(1)]);
    final playing = Completer<bool>();
    h.player = (message, valid) => playing.future;
    h.session.start(row(1));
    final chain = h.session.completed('local1');
    await flush();
    await h.session.completed('m1');
    expect(h.played, ['m2']);
    h.session.cancel();
    playing.complete(true);
    await chain;
    expect(h.played, ['m2']);
  });

  test('manual pause cancels continuation before playback Future settles',
      () async {
    final h = Harness([row(4), row(3), row(2), row(1)]);
    final playing = Completer<bool>();
    h.player = (message, valid) => playing.future;
    h.session.start(row(1));
    final chain = h.session.completed('m1');
    await flush();
    h.session.cancel();
    playing.complete(true);
    await chain;
    await h.session.completed('m2');
    h.session.messagesChanged();
    expect(h.played, ['m2']);
    expect(h.session.enabled, isFalse);
  });

  test('leaving during history fetch cannot start the downloaded next voice',
      () async {
    final h = Harness([row(1)]);
    final page = Completer<List<V2TimMessage>>();
    h.loader = (_) => page.future;
    h.session.start(row(1));
    final chain = h.session.completed('m1');
    await flush();
    h.session.cancel();
    page.complete([row(2)]);
    await chain;
    expect(h.played, isEmpty);
  });

  test(
      'download token is invalid immediately on stop or a new manual selection',
      () async {
    final h = Harness([row(10), row(2), row(1)]);
    final downloaded = Completer<bool>();
    bool Function()? oldToken;
    h.player = (_, valid) {
      oldToken = valid;
      return downloaded.future;
    };
    h.session.start(row(1));
    final chain = h.session.completed('m1');
    await flush();
    expect(oldToken!(), isTrue);
    h.session.start(row(10));
    expect(oldToken!(), isFalse);
    downloaded.complete(false);
    await chain;
    expect(h.session.currentMessageId, 'm10');
    expect(h.played, ['m2']);
  });

  test('newer history pages continue beyond the memory window', () async {
    final h = Harness([row(1)]);
    h.loader = (anchor) async => switch (anchor.msgID) {
          'm1' => [row(3), row(2)],
          'm3' => [row(4)],
          _ => [],
        };
    h.session.start(row(1));
    await h.session.completed('m1');
    expect(h.played, ['m2', 'm3', 'm4']);
    expect(h.historyReads, ['m1', 'm3', 'm4']);
  });

  test(
      'an evicted anchor fetches intervening voices before the distant live edge',
      () async {
    final h = Harness([row(1)]);
    h.session.start(row(1));
    h.rows = [row(4)];
    h.loader = (anchor) async => anchor.msgID == 'm1' ? [row(3), row(2)] : [];
    await h.session.completed('m1');
    expect(h.played, ['m2', 'm3', 'm4']);
  });

  test('text-only pages advance the cursor, not terminate voice playback',
      () async {
    final h = Harness([row(1)]);
    h.loader = (anchor) async => switch (anchor.msgID) {
          'm1' => [row(3, sound: false), row(2, sound: false)],
          'm3' => [row(4)],
          _ => [],
        };
    h.session.start(row(1));
    await h.session.completed('m1');
    expect(h.played, ['m4']);
    expect(h.historyReads, ['m1', 'm3', 'm4']);
  });

  test('repeated SDK pages stop fetching instead of looping', () async {
    final h = Harness([row(1)]);
    h.loader = (_) async => [row(2, sound: false), row(1)];
    h.session.start(row(1));
    await h.session.completed('m1');
    expect(h.historyReads, ['m1', 'm2']);
    expect(h.session.waiting, isTrue);
  });

  test('more than 32 unavailable voices are skipped', () async {
    final h = Harness([for (var i = 40; i >= 1; i--) row(i)]);
    h.player = (message, valid) async {
      if (message.msgID != 'm40') return false;
      unawaited(h.session.completed('m40'));
      return true;
    };
    h.session.start(row(1));
    await h.session.completed('m1');
    expect(h.played.last, 'm40');
    expect(h.played.length, 39);
  });

  test('new incoming voices resume at the tail, UI notifications do not poll',
      () async {
    final h = Harness([row(1)]);
    h.session.start(row(1));
    await h.session.completed('m1');
    for (var i = 0; i < 20; i++) {
      h.session.messagesChanged();
    }
    expect(h.historyReads.length, 1);
    h.rows = [row(3), row(2), row(1)];
    h.session.messagesChanged();
    await flush();
    expect(h.played, ['m2', 'm3']);
    expect(h.session.enabled, isTrue);
    h.session.cancel();
    h.rows = [row(4), ...h.rows];
    h.session.messagesChanged();
    await flush();
    expect(h.played, ['m2', 'm3']);
  });

  test('history errors are reported without an unhandled Future or loop',
      () async {
    final h = Harness([row(1)]);
    h.loader = (_) async => throw StateError('offline');
    h.session.start(row(1));
    await h.session.completed('m1');
    expect(h.errors, hasLength(1));
    expect(h.historyReads, ['m1']);
    expect(h.session.waiting, isTrue);
    h.session.cancel();
  });
}
