import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_pipeline_clock.dart';

void main() {
  test('group bare id shares the prefixed clock', () {
    ChatPipelineClock.instance.start('group_m22ASP2N5CO');
    expect(ChatPipelineClock.instance.offsetMs('group_m22ASP2N5CO'), greaterThanOrEqualTo(0));
    expect(ChatPipelineClock.instance.offsetMs('m22ASP2N5CO'), greaterThanOrEqualTo(0));
    expect(
      ChatPipelineClock.normalizeKey(
        rawConversationId: 'm22ASP2N5CO',
        groupId: 'm22ASP2N5CO',
      ),
      'group_m22ASP2N5CO',
    );
    ChatPipelineClock.instance.clear('group_m22ASP2N5CO');
  });
}
