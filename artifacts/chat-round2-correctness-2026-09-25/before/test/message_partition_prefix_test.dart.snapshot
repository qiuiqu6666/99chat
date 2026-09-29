import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_partition_prefix.dart';

V2TimMessage row(int n, {String? text}) => V2TimMessage.fromJson({
      'message_msg_id': 'sdk-$n',
      'message_server_time': 1789064000 + n,
      'message_risk_type_identified': 0,
    })
      ..elemType = 1
      ..textElem = V2TimTextElem(text: text ?? 'IM_PERF_$n');

List<V2TimMessage> display(List<V2TimMessage> newestFirst) =>
    TUIChatGlobalModel.attachTimeDividersForTesting(
      newestFirst.reversed.toList(),
    ).reversed.toList();

void main() {
  test('every 20-row history page retains SDK rows when the old divider moves',
      () {
    final messages = List.generate(100, (i) => row(100 - i));
    var cached = display(messages.take(20).toList());
    for (var count = 40; count <= 100; count += 20) {
      final next = display(messages.take(count).toList());
      // The previous head and first 16 rows are unchanged, but its old tail
      // divider is now occupied by an SDK row. The old fast path lost this row.
      expect(next.take(16), cached.take(16));
      expect(next.first, same(cached.first));
      expect(
          retainsMessagePartitionPrefix(
              current: next, unread: [], read: cached),
          isFalse);
      cached = next; // The production fallback rebuilds these partitions.
      expect(cached.where((m) => m.elemType == 1).map((m) => m.msgID),
          messages.take(count).map((m) => m.msgID));
    }
  });

  test('two moved business rows cannot consume two SDK rows at a page boundary',
      () {
    final rows = List.generate(40, (i) => row(40 - i));
    final tipA = row(-1)..elemType = 2;
    final tipB = row(-2)..elemType = 2;
    final cached = [...rows.take(20), tipA, tipB];
    final next = [...rows, tipA, tipB];
    expect(next.take(16), cached.take(16));
    expect(
        retainsMessagePartitionPrefix(current: next, unread: [], read: cached),
        isFalse);
    // Demonstrates the failure this gate prevents: an unchecked tail append
    // skips the two real messages replacing the old business placeholders.
    final unchecked = [...cached, ...next.skip(cached.length)];
    expect(unchecked.where((m) => m.elemType == 1).length, 38);
    expect(next.where((m) => m.elemType == 1).length, 40);
  });

  test(
      'unchanged prefix still permits incremental append across both partitions',
      () {
    final rows = List.generate(22, (i) => row(22 - i));
    final unread = rows.take(3).toList().reversed.toList();
    final read = rows.sublist(3, 20);
    expect(
        retainsMessagePartitionPrefix(
            current: rows, unread: unread, read: read),
        isTrue);
    final appendedRead = [...read, ...rows.skip(unread.length + read.length)];
    expect([...unread.reversed, ...appendedRead], rows);
  });

  test('same server ID with a replaced payload requires a partition rebuild',
      () {
    final rows = List.generate(22, (i) => row(22 - i));
    final previous = rows.take(20).toList();
    rows[18] = row(4, text: 'edited');
    expect(rows[18].msgID, previous[18].msgID);
    expect(
        retainsMessagePartitionPrefix(
            current: rows, unread: [], read: previous),
        isFalse);
  });
}
