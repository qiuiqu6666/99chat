// P1-4: visible projection 签名比对，避免 cache 反复失效。
//
// _computeMessageListSignature 是 tui_chat_global_model.dart 的私有方法，
// 这里只覆盖其签名语义：(msgID|seq) 拼接 + Object.hashAll。
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';

int _signature(List<V2TimMessage> messages) {
  if (messages.isEmpty) return 0;
  final ids = <String>[];
  for (final m in messages) {
    final id = (m.msgID ?? m.id ?? '').trim();
    final seq = (m.seq ?? '').trim();
    ids.add('$id|$seq');
  }
  return Object.hashAll(ids);
}

V2TimMessage _msg({String? msgID, String? seq, String? id}) =>
    V2TimMessage.fromJson({
      'message_msg_id': msgID,
      'message_server_time': 1,
      'message_risk_type_identified': 0,
    })..id = id..seq = seq..elemType = 1;

void main() {
  group('P1-4 visible projection signature', () {
    test('empty list hashes to 0', () {
      expect(_signature(<V2TimMessage>[]), 0);
    });

    test('same content produces same signature', () {
      final a = <V2TimMessage>[
        _msg(msgID: 'm1', seq: '10'),
        _msg(msgID: 'm2', seq: '11'),
      ];
      final b = <V2TimMessage>[
        _msg(msgID: 'm1', seq: '10'),
        _msg(msgID: 'm2', seq: '11'),
      ];
      expect(_signature(a), _signature(b));
    });

    test('different order produces different signature', () {
      final a = <V2TimMessage>[
        _msg(msgID: 'm1', seq: '10'),
        _msg(msgID: 'm2', seq: '11'),
      ];
      final b = <V2TimMessage>[
        _msg(msgID: 'm2', seq: '11'),
        _msg(msgID: 'm1', seq: '10'),
      ];
      expect(_signature(a), isNot(_signature(b)));
    });

    test('one new message produces different signature', () {
      final a = <V2TimMessage>[
        _msg(msgID: 'm1', seq: '10'),
        _msg(msgID: 'm2', seq: '11'),
      ];
      final b = <V2TimMessage>[
        _msg(msgID: 'm1', seq: '10'),
        _msg(msgID: 'm2', seq: '11'),
        _msg(msgID: 'm3', seq: '12'),
      ];
      expect(_signature(a), isNot(_signature(b)));
    });

    test('falling back from msgID to id is consistent', () {
      final a = <V2TimMessage>[
        _msg(id: 'fallback-id', seq: '5'),
      ];
      final b = <V2TimMessage>[
        _msg(id: 'fallback-id', msgID: null, seq: '5'),
      ];
      expect(_signature(a), _signature(b));
    });
  });
}
