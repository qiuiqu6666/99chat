import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_draft.dart';

void main() {
  test('bytes formats empty and scales', () {
    expect(AiAssistantDraftFormats.bytes(null), '--');
    expect(AiAssistantDraftFormats.bytes(0), '--');
    expect(AiAssistantDraftFormats.bytes(512), '512 B');
    expect(AiAssistantDraftFormats.bytes(2048), '2.0 KB');
    expect(AiAssistantDraftFormats.bytes(1048576), '1.0 MB');
  });
}
