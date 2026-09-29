import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_pagination_continuity.dart';

V2TimMessage message(int n, {required bool group}) {
  return V2TimMessage.fromJson(<String, dynamic>{
    'message_server_time': n,
    'message_risk_type_identified': 0,
    'message_status': 2,
    'message_custom_str': '',
    'message_sender_group_member_info': <String, dynamic>{},
    'message_group_at_user_array': <String>[],
  })
    ..msgID = 'm$n'
    ..elemType = 1
    ..isSelf = false
    ..groupID = group ? '@TGS#continuity' : null
    ..seq = group ? '$n' : '${100 - n}'
    // Group chronology must survive non-monotonic server timestamps.
    ..timestamp = group ? 100 - n : n;
}

void main() {
  for (final group in [true, false]) {
    final label = group ? 'group' : 'C2C';
    test('$label exposes an overtaken hidden row without reentering', () {
      final rows = [for (var n = 1; n <= 4; n++) message(n, group: group)];
      final hidden = {
        for (final n in [1, 3]) TUIChatGlobalModel.messageDedupKey(rows[n])
      };
      final visible = TUIChatGlobalModel.filterHiddenProjectionForTesting(
        authoritativeMessages: rows.reversed,
        hiddenKeys: hidden,
      );
      expect(visible.map((m) => m.msgID), ['m3', 'm2', 'm1']);
      expect(rows, hasLength(4));
      // Releasing the tail restores all rows exactly once.
      hidden.clear();
      expect(
          TUIChatGlobalModel.filterHiddenProjectionForTesting(
            authoritativeMessages: rows,
            hiddenKeys: hidden,
          ).map((m) => m.msgID),
          ['m1', 'm2', 'm3', 'm4']);
    });

    test('$label accepts missing page after realtime advances the head', () {
      expect(
          HistoryPaginationContinuity.canPrependNewerBatch(
            existingNewestFirst: [(seq: 3, timestamp: 300)],
            incomingNewerNewestFirst: [(seq: 2, timestamp: 200)],
            requestedAnchor: (seq: 1, timestamp: 100),
            isGroup: group,
          ),
          isTrue);
    });
  }

  test('group newer seq is valid despite timestamp regression', () {
    expect(
        HistoryPaginationContinuity.canPrependNewerBatch(
          existingNewestFirst: [(seq: 3, timestamp: 100)],
          incomingNewerNewestFirst: [(seq: 2, timestamp: 90)],
          requestedAnchor: (seq: 1, timestamp: 110),
          isGroup: true,
        ),
        isTrue);
  });

  test('direction errors are checked against request anchor', () {
    expect(
        HistoryPaginationContinuity.canPrependNewerBatch(
          existingNewestFirst: const [],
          incomingNewerNewestFirst: [(seq: 9, timestamp: 200)],
          requestedAnchor: (seq: 10, timestamp: 100),
          isGroup: true,
        ),
        isFalse);
  });
}
