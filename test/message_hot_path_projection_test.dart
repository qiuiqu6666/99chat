import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/tencent_advanced_message_adapter.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_receipt.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_delta.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class _NoJsonText extends V2TimTextElem {
  _NoJsonText(String text) : super(text: text);
  @override
  Map<String, dynamic> toJson() =>
      throw StateError('text hot path serialized JSON');
}

class _ProbeModel extends TUIChatGlobalModel {
  final readUpserts = <int>[];
  @override
  MessageCommitResult? commitMessageDelta(
    MessageDelta<V2TimMessage> delta, {
    bool applyMemoryWindow = true,
    bool memoryWindowPreferLatest = false,
    bool forcePublishForRevoke = false,
  }) {
    if (delta.kind == MessageDeltaKind.readReceipt)
      readUpserts.add(delta.upserts.length);
    return super.commitMessageDelta(delta,
        applyMemoryWindow: applyMemoryWindow,
        memoryWindowPreferLatest: memoryWindowPreferLatest,
        forcePublishForRevoke: forcePublishForRevoke);
  }
}

V2TimMessage _message(int index) => V2TimMessage.fromJson({
      'message_msg_id': 'm$index',
      'message_server_time': index,
      'message_risk_type_identified': 0,
    })
      ..userID = 'hot-peer'
      ..isSelf = true
      ..elemType = 1
      ..textElem = V2TimTextElem(text: 'text$index');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  test('text signatures skip model JSON while observing in-place changes', () {
    final message = _message(1)..textElem = _NoJsonText('same;:text');
    String signature() =>
        TUIChatGlobalModel.messageListCommitSignatureForTesting([message]);
    var before = signature();
    final edits = <void Function()>[
      () => message.textElem!.text = 'changed',
      () => message.isRead = true,
      () => message.isPeerRead = true,
      () => message.revokeReason = 'revoked',
      () => message.status = 3,
      () => message.progress = 80,
      () => message.localCustomData = 'local',
      () => message.cloudCustomData = 'cloud',
      () => message.timestamp = 2,
      () => message.id = 'client',
    ];
    for (final edit in edits) {
      edit();
      final after = signature();
      expect(after, isNot(before));
      before = after;
    }
    expect(signature(), before);
    message.textElem = V2TimTextElem(text: 'normal');
    message.customElem = V2TimCustomElem(data: 'card1');
    before = signature();
    message.customElem!.data = 'card2';
    expect(signature(), isNot(before));
  });
  test('text signature fields cannot collide on delimiters or null strings',
      () {
    final a = _message(1)
      ..localCustomData = 'a;:b'
      ..cloudCustomData = 'c';
    final b = _message(1)
      ..localCustomData = 'a'
      ..cloudCustomData = 'b;:c';
    expect(TUIChatGlobalModel.messageListCommitSignatureForTesting([a]),
        isNot(TUIChatGlobalModel.messageListCommitSignatureForTesting([b])));
    a.localCustomData = null;
    b.localCustomData = 'null';
    b.cloudCustomData = a.cloudCustomData;
    expect(TUIChatGlobalModel.messageListCommitSignatureForTesting([a]),
        isNot(TUIChatGlobalModel.messageListCommitSignatureForTesting([b])));
  });
  test('one peer receipt burst produces one delta containing only changed rows',
      () async {
    final model = _ProbeModel();
    model.configureMessageWriterScope(
        ownerUserID: 'read-owner', accountGeneration: 1, domainGeneration: 1);
    const conv = 'c2c_hot-peer';
    model.setMessageList(conv, List.generate(100, (i) => _message(100 - i)),
        replace: true);
    model.applyAppC2CReadReceipts(List.generate(
        50, (i) => V2TimMessageReceipt(userID: 'hot-peer', timestamp: i + 1)));
    expect(model.readUpserts, [50]);
    final rows = model.rawMessageList(conv)!;
    expect(rows.where((m) => m.isPeerRead == true).length, 50);
    expect(
        rows.where((m) => m.timestamp! > 50).every((m) => m.isPeerRead != true),
        isTrue);
    model.applyAppC2CReadReceipts(
        [V2TimMessageReceipt(userID: 'hot-peer', timestamp: 60)]);
    expect(model.readUpserts, [50, 10]);
    model.applyAppC2CReadReceipts([
      V2TimMessageReceipt(userID: 'hot-peer', timestamp: 0),
      V2TimMessageReceipt(userID: 'hot-peer', timestamp: 60),
    ]);
    expect(model.readUpserts, [50, 10, 40]);

    expect(
        model.rawMessageList(conv)!.where((m) => m.isPeerRead == true).length,
        100);
    await Future<void>.delayed(const Duration(milliseconds: 70));
    model.dispose();
  });
  test('generic timestamp-zero C2C receipt only marks the addressed message',
      () async {
    final model = _ProbeModel();
    model.configureMessageWriterScope(
        ownerUserID: 'read-owner', accountGeneration: 1, domainGeneration: 1);
    const conv = 'c2c_hot-peer';
    model.setMessageList(conv, [_message(2), _message(1)], replace: true);
    ImReadReceiptBatch([
      V2TimMessageReceipt(
          userID: 'hot-peer', msgID: 'm1', timestamp: 0, isPeerRead: true)
    ]).applyTo(model);
    expect(model.getMessageReadReceipt('m1')?.isPeerRead, isTrue);
    expect(model.rawMessageList(conv)!.first.isPeerRead, isNot(true));
    expect(model.getMessageReadReceipt('m2')?.isPeerRead, isNot(true));
    expect(model.readUpserts, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 70));
    model.dispose();
  });
}
