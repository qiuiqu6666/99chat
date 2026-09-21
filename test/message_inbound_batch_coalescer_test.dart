// fake_async is supplied by flutter_test.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_inbound_batch_coalescer.dart';

V2TimMessage message(int id) => V2TimMessage.fromJson({
      'message_msg_id': '$id',
      'message_risk_type_identified': 0,
      'message_elem_array': <dynamic>[],
    });

void main() {
  test('continuous arrivals flush by first arrival deadline in order', () {
    fakeAsync((clock) {
      final received = <List<String?>>[];
      final coalescer = MessageInboundBatchCoalescer(
        onFlush: (_, batch) => received.add(batch.map((m) => m.msgID).toList()),
      );
      for (var i = 0; i < 20; i++) {
        coalescer.enqueue('chat', message(i));
        clock.elapse(const Duration(milliseconds: 20));
      }
      expect(received.first, ['0', '1', '2']);
      expect(received.length, greaterThanOrEqualTo(6));
      coalescer.flushAll();
      expect(received.expand((batch) => batch), List.generate(20, (i) => '$i'));
      coalescer.dispose();
    });
  });

  test('size flush cancels deadline and next batch gets a fresh deadline', () {
    fakeAsync((clock) {
      final sizes = <int>[];
      final coalescer = MessageInboundBatchCoalescer(
        maxBatchSize: 3,
        onFlush: (_, batch) => sizes.add(batch.length),
      );
      for (var i = 0; i < 3; i++) {
        coalescer.enqueue('chat', message(i));
      }
      expect(sizes, [3]);
      clock.elapse(const Duration(milliseconds: 40));
      coalescer.enqueue('chat', message(3));
      clock.elapse(const Duration(milliseconds: 10));
      expect(sizes, [3]);
      clock.elapse(const Duration(milliseconds: 40));
      expect(sizes, [3, 1]);
      coalescer.dispose();
    });
  });

  test('conversations have independent deadlines and disposal cancels work',
      () {
    fakeAsync((clock) {
      final conversations = <String>[];
      final coalescer = MessageInboundBatchCoalescer(
        onFlush: (id, _) => conversations.add(id),
      );
      coalescer.enqueue('a', message(1));
      clock.elapse(const Duration(milliseconds: 30));
      coalescer.enqueue('b', message(2));
      clock.elapse(const Duration(milliseconds: 20));
      expect(conversations, ['a']);
      coalescer.dispose();
      clock.elapse(const Duration(seconds: 1));
      expect(conversations, ['a']);
      expect(coalescer.pendingCountFor('b'), 0);
    });
  });
}
