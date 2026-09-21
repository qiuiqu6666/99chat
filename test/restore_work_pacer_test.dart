import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/restore_work_pacer.dart';

void main() {
  test('first page is immediate; later pages yield, and chats slow recovery',
      () async {
    var chat = false;
    final delays = <Duration>[];
    final pacer = RestoreWorkPacer(
      canStartBackgroundWork: () => true,
      isScrolling: () => false,
      isForeground: () => true,
      hasOpenChat: () => chat,
      delay: (duration) async => delays.add(duration),
    );
    expect(
        await pacer.beforePage(isCurrent: () => true, firstPage: true), isTrue);
    expect(delays, isEmpty);
    await pacer.beforePage(isCurrent: () => true);
    chat = true;
    await pacer.beforePage(isCurrent: () => true);
    expect(delays,
        [const Duration(milliseconds: 32), const Duration(milliseconds: 200)]);
  });

  test('scrolling and background both pause until usable again', () async {
    var scrolling = true;
    var foreground = false;
    var ticks = 0;
    final pacer = RestoreWorkPacer(
      canStartBackgroundWork: () => true,
      isScrolling: () => scrolling,
      isForeground: () => foreground,
      hasOpenChat: () => false,
      delay: (_) async {
        ticks++;
        if (ticks == 1) scrolling = false;
        if (ticks == 2) foreground = true;
      },
    );
    expect(
        await pacer.beforePage(isCurrent: () => true, firstPage: true), isTrue);
    expect(ticks, 2);
  });

  test('chat/keyboard/search interaction pauses even without feed scrolling',
      () async {
    var idle = false;
    var waits = 0;
    final pacer = RestoreWorkPacer(
      isScrolling: () => false,
      isForeground: () => true,
      hasOpenChat: () => true,
      canStartBackgroundWork: () => idle,
      delay: (_) async {
        waits++;
        idle = true;
      },
    );
    expect(
        await pacer.beforePage(isCurrent: () => true, firstPage: true), true);
    expect(waits, 1);
  });

  test('account change while paused cancels without granting a page', () async {
    var current = true;
    var ticks = 0;
    final pacer = RestoreWorkPacer(
      canStartBackgroundWork: () => true,
      isScrolling: () => true,
      isForeground: () => false,
      hasOpenChat: () => false,
      delay: (_) async {
        ticks++;
        current = false;
      },
    );
    expect(await pacer.beforePage(isCurrent: () => current, firstPage: true),
        isFalse);
    expect(ticks, 1);
    expect(await pacer.beforePage(isCurrent: () => current), isFalse);
    expect(ticks, 1);
  });
}
