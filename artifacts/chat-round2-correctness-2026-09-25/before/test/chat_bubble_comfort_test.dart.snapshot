import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_message_grouping.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_bubble_text_color.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_text_bubble_layout.dart';

const bodyKey = ValueKey('body');
const footerKey = ValueKey('footer');
const bubbleKey = ValueKey('bubble');
const style = TextStyle(fontSize: 16, height: 1.3, color: Color(0xFF20242A));

Widget sample(String text,
    {bool receipt = true,
    bool read = false,
    double scale = 1,
    double width = 270}) {
  return MaterialApp(
      home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
        body: Align(
      alignment: Alignment.topLeft,
      child: Container(
        key: bubbleKey,
        constraints: BoxConstraints(maxWidth: width),
        padding: MessageBubbleTextColor.messageBubblePadding,
        child: ChatTextBubbleLayout(
          text: text,
          textStyle: style,
          timeText: '12:34',
          reserveReceipt: receipt,
          body: Text(text, key: bodyKey, style: style),
          metadata:
              Row(key: footerKey, mainAxisSize: MainAxisSize.min, children: [
            const Text('12:34', style: TextStyle(fontSize: 11, height: 1)),
            if (receipt) ...[
              const SizedBox(width: 4),
              SizedBox(width: read ? 16 : 12, height: 10)
            ],
          ]),
        ),
      ),
    )),
  ));
}

V2TimMessage msg(String sender, int seconds, {int type = 1}) =>
    V2TimMessage.fromJson({
      'message_msg_id': '$sender-$seconds',
      'message_server_time': seconds,
      'message_risk_type_identified': 0,
    })
      ..sender = sender
      ..elemType = type
      ..isSelf = false;

void main() {
  test('grouping respects sender, elapsed time, dividers and revocation', () {
    final start = DateTime(2026, 9, 10, 12).millisecondsSinceEpoch ~/ 1000;
    final first = msg('a', start);
    expect(ChatMessageGrouping.joins(first, msg('a', start + 30)), true);
    expect(ChatMessageGrouping.joins(first, msg('b', start + 30)), false);
    expect(ChatMessageGrouping.joins(first, msg('a', start + 121)), false);
    expect(ChatMessageGrouping.joins(first, msg('a', start - 1)), false);
    expect(ChatMessageGrouping.joins(first, msg('a', start + 30, type: 11)),
        false);
    expect(ChatMessageGrouping.joins(first, msg('a', start + 30)..status = 6),
        false);
    expect(
        ChatMessageGrouping.joins(first,
            msg('a', start + 30)..cloudCustomData = '{"isRevoke": true}'),
        false);
    expect(ChatMessageGrouping.joins(null, first), false);
    final midnight = DateTime(2026, 9, 11).millisecondsSinceEpoch ~/ 1000;
    expect(
        ChatMessageGrouping.joins(
            msg('a', midnight - 10), msg('a', midnight + 10)),
        false);
  });

  testWidgets('short text fits on one line and receipt does not resize bubble',
      (tester) async {
    await tester.pumpWidget(sample('OK'));
    final size = tester.getSize(find.byKey(bubbleKey));
    final body = tester.getRect(find.byKey(bodyKey));
    final footer = tester.getRect(find.byKey(footerKey));
    expect(footer.bottom, closeTo(body.bottom, 1));
    await tester.pumpWidget(sample('OK', read: true));
    expect(tester.getSize(find.byKey(bubbleKey)), size);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiline plain text uses free room on its last line',
      (tester) async {
    await tester.pumpWidget(sample('A long first line\nOK'));
    final body = tester.getRect(find.byKey(bodyKey));
    final footer = tester.getRect(find.byKey(footerKey));
    expect(footer.bottom, closeTo(body.bottom, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('full last line gets an unobstructed separate footer',
      (tester) async {
    await tester.pumpWidget(sample('abcdefghijklmn', width: 250));
    final body = tester.getRect(find.byKey(bodyKey));
    final footer = tester.getRect(find.byKey(footerKey));
    expect(footer.top, greaterThanOrEqualTo(body.bottom));
    expect(tester.takeException(), isNull);
  });

  for (final text in ['https://example.com/test', 'Hello 😀', 'שלום']) {
    testWidgets('rich or bidi content has a safe footer: $text',
        (tester) async {
      await tester.pumpWidget(sample(text, scale: 2, width: 240));
      final body = tester.getRect(find.byKey(bodyKey));
      final footer = tester.getRect(find.byKey(footerKey));
      expect(footer.top, greaterThanOrEqualTo(body.bottom));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('large text remains inside a narrow bubble', (tester) async {
    await tester.pumpWidget(
        sample('Some text on a small screen', scale: 2, width: 220));
    final bubble = tester.getRect(find.byKey(bubbleKey));
    final footer = tester.getRect(find.byKey(footerKey));
    expect(footer.right, lessThanOrEqualTo(bubble.right));
    expect(footer.bottom, lessThanOrEqualTo(bubble.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('render a Chinese typography specimen', (tester) async {
    if (Platform.environment['CHAT_BUBBLE_PREVIEW'] != '1') return;
    await tester.runAsync(() async {
      final loader = FontLoader('ComfortPreview');
      loader.addFont(File('C:/Windows/Fonts/msyh.ttc')
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
      await loader.load();
    });
    tester.view.physicalSize = const Size(430, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final capture = GlobalKey();
    final previewStyle = style.copyWith(fontFamily: 'ComfortPreview');
    Widget bubble(String text, {bool self = false, double gap = 12}) => Padding(
          padding: EdgeInsets.only(bottom: gap),
          child: Align(
            alignment: self ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: MessageBubbleTextColor.messageBubblePadding,
              decoration: BoxDecoration(
                color: self ? const Color(0xFFDCEEFF) : Colors.white,
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(self ? 16 : 6),
                    topRight: Radius.circular(self ? 6 : 16),
                    bottomLeft: const Radius.circular(16),
                    bottomRight: const Radius.circular(16)),
                border: MessageBubbleTextColor.messageBubbleBorder(
                    isFromSelf: self),
              ),
              child: ChatTextBubbleLayout(
                text: text,
                textStyle: previewStyle,
                timeText: '12:34',
                reserveReceipt: self,
                body: Text(text, style: previewStyle),
                metadata: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('12:34',
                      style: TextStyle(
                          fontSize: 11, height: 1, color: Color(0xFF7A8792))),
                  if (self)
                    Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: SvgPicture.asset('assets/2.svg',
                            width: 16,
                            height: 10,
                            colorFilter: const ColorFilter.mode(
                                Color(0xFF3987BC), BlendMode.srcIn))),
                ]),
              ),
            ),
          ),
        );
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'ComfortPreview'),
      home: RepaintBoundary(
          key: capture,
          child: Scaffold(
            backgroundColor: const Color(0xFFF4F5F7),
            body: Padding(
              padding: const EdgeInsets.fromLTRB(22, 30, 22, 22),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('气泡排版预览',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text('正文 · 连续消息 · 时间与状态',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF7A8792))),
                    const SizedBox(height: 30),
                    bubble('今天的方案看过了吗？', gap: 5),
                    bubble('我把几个重点整理好了，发给你。'),
                    bubble('看过了，整体很清楚。', self: true, gap: 5),
                    bubble('好的', self: true),
                    bubble('长消息需要留一点阅读空间。\n文字不挤在一起，时间也不必单独占一整行。\n这样读起来会轻松一些。'),
                    bubble('收到，稍后一起确认。', self: true),
                    const Spacer(),
                    const Text('使用实际气泡布局组件渲染 · 排版样例',
                        style:
                            TextStyle(fontSize: 11, color: Color(0xFF7A8792))),
                  ]),
            ),
          )),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ImageByteFormat.png);
      final output = File('test_outputs/chat-bubble-comfort.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  });
}
