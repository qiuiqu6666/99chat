import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_notice_mention_text.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/special_text/chat_id_mention_text.dart';

void main() {
  const style = TextStyle(fontSize: 18, height: 1.5);

  Future<void> pumpNotice(
    WidgetTester tester, {
    required String text,
    required ValueChanged<String> onTapMention,
    required ValueChanged<String> onTapUrl,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupNoticeMentionText(
            text: text,
            style: style,
            onTapMention: onTapMention,
            onTapUrl: onTapUrl,
          ),
        ),
      ),
    );
  }

  testWidgets('@uid is tappable with parseRawId token', (tester) async {
    final mentions = <String>[];
    final urls = <String>[];
    const raw = '@alice_01';
    await pumpNotice(
      tester,
      text: 'hello $raw thanks',
      onTapMention: mentions.add,
      onTapUrl: urls.add,
    );

    final span = _spanWithText(tester, raw);
    expect(span, isNotNull);
    _tap(span!);
    expect(mentions, <String>[ChatIdMentionText.parseRawId(raw)]);
    expect(urls, isEmpty);
  });

  testWidgets('multiple @ mentions tap independently', (tester) async {
    final mentions = <String>[];
    await pumpNotice(
      tester,
      text: 'hi @Bob_User and @alice_01',
      onTapMention: mentions.add,
      onTapUrl: (_) {},
    );

    _tap(_spanWithText(tester, '@Bob_User')!);
    _tap(_spanWithText(tester, '@alice_01')!);
    expect(mentions, <String>['Bob_User', 'alice_01']);
  });

  testWidgets('TGS# mention keeps parseRawId token', (tester) async {
    const full = '@TGS#_@TGS#cL54PNMM62CN';
    final mentions = <String>[];
    await pumpNotice(
      tester,
      text: 'join $full please',
      onTapMention: mentions.add,
      onTapUrl: (_) {},
    );

    _tap(_spanWithText(tester, full)!);
    expect(mentions, <String>[ChatIdMentionText.parseRawId(full)]);
  });

  testWidgets('http https www urls are tappable with raw href', (tester) async {
    final urls = <String>[];
    const http = 'http://example.com/a';
    const https = 'https://example.com/b';
    const www = 'www.example.com/c';
    await pumpNotice(
      tester,
      text: 'see $http $https $www',
      onTapMention: (_) {},
      onTapUrl: urls.add,
    );

    _tap(_spanWithText(tester, http)!);
    _tap(_spanWithText(tester, https)!);
    _tap(_spanWithText(tester, www)!);
    expect(urls, <String>[http, https, www]);
  });

  testWidgets('adjacent url and mention stay independently tappable',
      (tester) async {
    final mentions = <String>[];
    final urls = <String>[];
    const mention = '@alice_01';
    const url = 'https://example.com/path';
    await pumpNotice(
      tester,
      text: 'see $mention $url',
      onTapMention: mentions.add,
      onTapUrl: urls.add,
    );

    _tap(_spanWithText(tester, mention)!);
    _tap(_spanWithText(tester, url)!);
    expect(mentions, <String>['alice_01']);
    expect(urls, <String>[url]);
  });

  testWidgets('overlapping mention inside url yields only the url',
      (tester) async {
    final mentions = <String>[];
    final urls = <String>[];
    const url = 'https://example.com/@alice_01';
    await pumpNotice(
      tester,
      text: url,
      onTapMention: mentions.add,
      onTapUrl: urls.add,
    );

    expect(_spanWithText(tester, '@alice_01'), isNull);
    _tap(_spanWithText(tester, url)!);
    expect(mentions, isEmpty);
    expect(urls, <String>[url]);
  });

  testWidgets('plain text without @ or url has no gestures', (tester) async {
    var mentionTaps = 0;
    var urlTaps = 0;
    await pumpNotice(
      tester,
      text: '今晚九点开会，请准时参加',
      onTapMention: (_) => mentionTaps++,
      onTapUrl: (_) => urlTaps++,
    );

    expect(_tappableSpans(tester), isEmpty);
    expect(mentionTaps, 0);
    expect(urlTaps, 0);
  });

  testWidgets('spaced remark is not guessed as a user id', (tester) async {
    final mentions = <String>[];
    await pumpNotice(
      tester,
      text: '@C 先生 Li的外部托 你好',
      onTapMention: mentions.add,
      onTapUrl: (_) {},
    );

    _tap(_spanWithText(tester, '@C')!);
    expect(mentions, <String>['C']);
    expect(_spanWithText(tester, '@C 先生 Li的外部托'), isNull);
  });
}

List<TextSpan> _tappableSpans(WidgetTester tester) {
  final rich = tester.widget<RichText>(find.byType(RichText));
  final spans = <TextSpan>[];
  rich.text.visitChildren((span) {
    if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
      spans.add(span);
    }
    return true;
  });
  return spans;
}

TextSpan? _spanWithText(WidgetTester tester, String text) {
  for (final span in _tappableSpans(tester)) {
    if (span.text == text) {
      return span;
    }
  }
  return null;
}

void _tap(TextSpan span) {
  (span.recognizer as TapGestureRecognizer).onTap!.call();
}
