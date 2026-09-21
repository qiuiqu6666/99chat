import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/utils/latest_chat_preview.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';

void main() {
  V2TimMessage message(String id, int time) =>
      V2TimMessage.fromJson({'message_msg_id': id, 'message_server_time': time,
          'message_risk_type_identified': 0});
  V2TimMessage? select(List<V2TimMessage?> candidates, {int cleared = 0}) =>
      latestChatPreview(candidates: candidates, clearedAtMs: cleared,
          timestampMs: (message) => (message?.timestamp ?? 0) * 1000);

  test('live preview supersedes the entry snapshot and older disk row', () {
    final live = message('new', 30);
    expect(select([live, message('disk', 20), message('entry', 10)]), same(live));
  });
  test('older live or disk rows cannot regress a newer entry preview', () {
    final entry = message('entry', 30);
    expect(select([message('live', 10), message('disk', 20), entry]), same(entry));
  });
  test('equal timestamps prefer current preview including revoked updates', () {
    final live = message('same', 30)..revokeReason = 'recalled';
    expect(select([live, message('same', 30)]), same(live));
  });
  test('clear boundary excludes stale snapshots but allows new arrivals', () {
    expect(select([null, message('disk', 20), message('entry', 10)], cleared: 20000), isNull);
    final live = message('new', 21);
    expect(select([live, message('disk', 20)], cleared: 20000), same(live));
  });
}
