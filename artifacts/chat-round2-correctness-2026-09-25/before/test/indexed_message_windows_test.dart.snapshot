import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_receipt.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/indexed_message_windows.dart';

class _CountedMessage extends V2TimMessage {
  _CountedMessage(String id)
      : super.fromJson({
          'message_msg_id': id,
          'message_server_time': 1,
          'message_risk_type_identified': 0
        });
  static int reads = 0;
  @override
  String? get msgID {
    reads++;
    return super.msgID;
  }

  @override
  set msgID(String? id) => super.msgID = id;
}

void main() {
  late IndexedMessageWindows windows;
  late WindowMessageReceiptCache receipts;
  setUp(() {
    windows = IndexedMessageWindows(
        onRetained: (keys) => receipts.retain(keys),
        onReleased: (keys) => receipts.release(keys),
        onWindowRemoved: (_) {},
        onCleared: () => receipts.clear());
    receipts = WindowMessageReceiptCache(
        isLoaded: windows.containsMessage, pendingLimit: 2);
  });
  V2TimMessageReceipt receipt(String id) =>
      V2TimMessageReceipt(userID: 'peer', msgID: id, timestamp: 1);

  test('500 indexed lookups do not rescan 10000 message identities', () {
    windows['a'] = List.generate(10000, (i) => _CountedMessage('m$i'));
    _CountedMessage.reads = 0;
    for (var i = 0; i < 500; i++) {
      expect(windows.find('m$i').single.key, 'a');
      receipts['m$i'] = receipt('m$i');
    }
    expect(_CountedMessage.reads, 0);
    expect(receipts.length, 500, reason: 'loaded receipts are not pending LRU');
  });

  test('replacement, shared IDs and alias removal keep only current objects',
      () {
    final old = _CountedMessage('m');
    final next = _CountedMessage('m');
    windows['a'] = [old];
    windows['alias'] = [old];
    receipts['m'] = receipt('m');
    windows['a'] = [next];
    windows.remove('alias');
    expect(windows.find('m').single.value, same(next));
    expect(receipts['m'], isNotNull);
    windows.remove('a');
    expect(windows.find('m'), isEmpty);
    expect(receipts, isEmpty);
  });

  test('in-place SDK ID adoption invalidates old ID and keeps client alias',
      () {
    final row = _CountedMessage('old')..id = 'client';
    windows['a'] = [row];
    receipts['old'] = receipt('old');
    row.msgID = 'server';
    expect(windows.find('old'), isEmpty);
    expect(windows.find('server').single.value, same(row));
    expect(windows.find('client').single.value, same(row));
    expect(receipts['old'], isNull);
  });

  test('bounded pending receipts promote to loaded and release with window',
      () {
    receipts['a'] = receipt('a');
    receipts['b'] = receipt('b');
    windows['chat'] = [_CountedMessage('a')];
    receipts['c'] = receipt('c');
    receipts['d'] = receipt('d');
    expect(receipts.keys.toSet(), {'a', 'c', 'd'});
    windows['chat'] = [];
    expect(receipts.keys.toSet(), {'c', 'd'});
    windows.clear();
    expect(receipts, isEmpty);
  });
}
