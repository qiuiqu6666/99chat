import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_markdown.dart';

void main() {
  test('splits jammed numbered bold titles into sections', () {
    const raw =
        '开头说明：**1.先打招呼、确认关系**一开始简单测试。**2.确认业务情况**对方说六合彩在开。';
    final normalized = AiAssistantMarkdown.normalize(raw);
    expect(normalized, contains('开头说明：\n\n**1.先打招呼、确认关系**\n\n一开始简单测试。'));
    expect(normalized, contains('\n\n**2.确认业务情况**\n\n对方说六合彩在开。'));
  });

  test('breaks jammed dash speaker lines and closing beat', () {
    const raw =
        '**4.讨论软件版本**-gov2siarv7说撤回不了。-q14gkm5swv说可以撤回。整体看，这是对接。';
    final normalized = AiAssistantMarkdown.normalize(raw);
    expect(normalized, contains('**4.讨论软件版本**'));
    expect(normalized, contains('\n- gov2siarv7说撤回不了。'));
    expect(normalized, contains('\n- q14gkm5swv说可以撤回。'));
    expect(normalized, contains('\n\n整体看，这是对接。'));
  });

  test('keeps ordinary inline bold', () {
    const raw = '目前只有一个**六合彩**在开。';
    expect(AiAssistantMarkdown.normalize(raw), raw);
  });
}
