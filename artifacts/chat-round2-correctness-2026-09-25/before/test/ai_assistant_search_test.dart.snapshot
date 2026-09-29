import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_models.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_search.dart';

void main() {
  test('thinking message does not match', () {
    const message = AiAssistantMessage(
      role: AiAssistantRole.assistant,
      time: '',
      outputKind: AiAssistantOutputKind.thinking,
      text: '99ChatAI 介绍',
    );
    expect(AiAssistantSearch.matches(message, 'chat'), isFalse);
  });

  test('text match is case insensitive', () {
    const message = AiAssistantMessage(
      role: AiAssistantRole.user,
      time: '',
      text: '99ChatAI 介绍',
    );
    expect(AiAssistantSearch.matches(message, 'chat'), isTrue);
    expect(AiAssistantSearch.matches(message, 'zzz'), isFalse);
  });

  test('file name can match without text', () {
    const message = AiAssistantMessage(
      role: AiAssistantRole.user,
      time: '',
      files: <AiAssistantFileRef>[
        AiAssistantFileRef(
          name: 'Q3数据.xlsx',
          sizeLabel: '860 KB',
          kind: AiAssistantFileKind.excel,
        ),
      ],
    );
    expect(AiAssistantSearch.matches(message, 'xlsx'), isTrue);
  });

  test('matchIndexes keeps first hit only', () {
    const messages = <AiAssistantMessage>[
      AiAssistantMessage(
        role: AiAssistantRole.user,
        time: '',
        text: '99ChatAI 介绍',
      ),
      AiAssistantMessage(
        role: AiAssistantRole.user,
        time: '',
        text: 'hello',
      ),
    ];
    expect(AiAssistantSearch.matchIndexes(messages, 'chat'), <int>[0]);
  });

  test('highlight splits case-insensitive hits', () {
    const base = TextStyle(fontSize: 14);
    const hit = TextStyle(fontSize: 14, backgroundColor: Color(0x44FF0000));
    final spans = AiAssistantSearch.highlight(
      'AaBbAa',
      'aa',
      base: base,
      hit: hit,
    );
    expect(spans.length, 3);
    expect((spans[0] as TextSpan).text, 'Aa');
    expect((spans[0] as TextSpan).style, hit);
    expect((spans[1] as TextSpan).text, 'Bb');
    expect((spans[1] as TextSpan).style, base);
    expect((spans[2] as TextSpan).text, 'Aa');
    expect((spans[2] as TextSpan).style, hit);
  });

  test('copyText keeps original case and line breaks', () {
    const message = AiAssistantMessage(
      role: AiAssistantRole.assistant,
      time: '',
      outputKind: AiAssistantOutputKind.text,
      text: '99ChatAI 介绍',
    );
    expect(AiAssistantSearch.copyText(message), '99ChatAI 介绍');
    const thinking = AiAssistantMessage(
      role: AiAssistantRole.assistant,
      time: '',
      outputKind: AiAssistantOutputKind.thinking,
      text: '99ChatAI 介绍',
    );
    expect(AiAssistantSearch.copyText(thinking), '');
  });
}
