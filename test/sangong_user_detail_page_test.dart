import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/models/sangong_account_flow_entry.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_game/sangong_user_detail_page.dart';

void main() {
  test('summary selects only the requested user, never their descendants', () {
    final rows = [
      {'imUserId': 'child', 'todayUp': 99999},
      {'imUserId': 'owner', 'todayUp': 100},
    ];
    expect(sangongOwnSummary(rows, 'owner')['todayUp'], 100);
    expect(sangongOwnSummary(rows, 'absent'), isEmpty);
  });
  test('natural day uses Shanghai date across UTC midnight', () {
    final entry = SangongAccountFlowEntry.fromJson({
      'createdAt': '2026-09-15T16:00:00.000Z',
    });
    expect(sangongEntryOnDate(entry, '2026-09-16'), isTrue);
    expect(sangongEntryOnDate(entry, '2026-09-15'), isFalse);
    expect(
        sangongEntryOnDate(SangongAccountFlowEntry.fromJson({}), '2026-09-16'),
        isFalse);
    expect(
        sangongEntryOnDate(
            SangongAccountFlowEntry.fromJson({
              'createdAt': '2026-09-16T00:30:00+08:00',
            }),
            '2026-09-16'),
        isTrue);
  });
}
