import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inline watch banner binds bottom bar copy from session fields', () {
    final source = File(
      'lib/src/widgets/group_live/group_live_inline_watch_banner.dart',
    ).readAsStringSync();

    expect(source.contains('正在直播 · 公平公开'), isFalse);
    expect(source.contains('主播在线讲解 · 开奖过程透明可见'), isFalse);
    expect(source.contains('roomName: widget.session.roomName'), isTrue);
    expect(source.contains('description: widget.session.description'), isTrue);
    expect(source.contains('全屏观看'), isTrue);
    expect(source.contains('anchorFaceUrl: widget.anchorFaceUrl'), isTrue);
    expect(source.contains('AppUserAvatar'), isTrue);
    expect(source.contains('resolveChatPeerFaceUrl'), isTrue);
    expect(source.contains('assets/live/liveee.webp'), isFalse);
    expect(source.contains('height: 88'), isTrue);

    final barAt = source.indexOf('class _WatchingBottomBar');
    expect(barAt, greaterThanOrEqualTo(0));
    final barBody = source.substring(barAt);
    expect(barBody.contains('color: Colors.transparent'), isTrue);
    expect(
      barBody.contains('BorderSide(color: Colors.white, width: 1)'),
      isTrue,
    );
    expect(barBody.contains('Color(0xFF1F2329)'), isFalse);
  });
}
