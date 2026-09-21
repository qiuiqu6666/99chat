import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_stream.dart';

void main() {
  test('take clips by character count', () {
    expect(AiAssistantStream.take('你好AI', 0), '');
    expect(AiAssistantStream.take('你好AI', 2), '你好');
    expect(AiAssistantStream.take('你好AI', 8), '你好AI');
  });
}
