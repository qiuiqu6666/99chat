import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/overflow_text_marquee.dart';

void main() {
  const style = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);

  testWidgets('short text stays a single static line', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: OverflowTextMarquee(
              text: '短标题',
              style: style,
              height: 20,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(OverflowTextMarquee), findsOneWidget);
    expect(find.text('短标题'), findsOneWidget);
  });

  testWidgets('long text duplicates for seamless scroll', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 80,
            child: OverflowTextMarquee(
              text: '直播发包！全网最公平公开！拒绝套路、不透明',
              style: style,
              height: 20,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(OverflowTextMarquee), findsOneWidget);
    expect(find.text('直播发包！全网最公平公开！拒绝套路、不透明'), findsNWidgets(2));
  });

  test('notice and inline live scroll while top live banner stays static', () {
    final notice =
        File('lib/src/widgets/group_notice_marquee.dart').readAsStringSync();
    expect(notice, contains('OverflowTextMarquee'));
    expect(notice, isNot(contains('AnimationController')));

    final topBanner = File('lib/src/widgets/group_live/group_live_top_banner.dart')
        .readAsStringSync();
    expect(topBanner, isNot(contains('OverflowTextMarquee')));

    final inline = File(
      'lib/src/widgets/group_live/group_live_inline_watch_banner.dart',
    ).readAsStringSync();
    expect(inline, contains('OverflowTextMarquee'));
  });
}
