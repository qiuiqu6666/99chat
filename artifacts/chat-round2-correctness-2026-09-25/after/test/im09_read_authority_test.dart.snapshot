import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/tencent_conversation_read_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';

class _FakeMessageService implements MessageService {
  final calls = <String>[];
  Completer<V2TimCallback>? pending;

  @override
  Future<V2TimCallback> markC2CMessageAsRead({required String userID}) {
    calls.add('c2c:$userID');
    return pending?.future ?? Future.value(_success());
  }

  @override
  Future<V2TimCallback> markGroupMessageAsRead({required String groupID}) {
    calls.add('group:$groupID');
    return pending?.future ?? Future.value(_success());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

V2TimCallback _success() => V2TimCallback(code: 0, desc: 'ok');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('page lifecycle without a watermark never invokes a full SDK clear',
      () async {
    final service = _FakeMessageService();
    final result = await TencentConversationReadService.markRead(
        messageService: service,
        conversationID: 'c2c_bob',
        isGroup: false,
        capturedIdentity:
            SessionIdentityService.instance.capture(ownerUserId: 'alice'));
    expect(result.desc, 'read_watermark_unavailable');
    expect(service.calls, isEmpty);
  });

  test('normalizes explicit C2C and group clears before the SDK authority call',
      () async {
    final service = _FakeMessageService();
    final identity =
        SessionIdentityService.instance.capture(ownerUserId: 'alice');

    final c2c = await TencentConversationReadService.markRead(
      messageService: service,
      conversationID: 'c2c_bob',
      isGroup: false,
      capturedIdentity: identity,
      explicitFullConversationClear: true,
    );
    final group = await TencentConversationReadService.markRead(
      messageService: service,
      conversationID: 'group_@TGS#room',
      isGroup: true,
      capturedIdentity: identity,
      explicitFullConversationClear: true,
    );

    expect(c2c.code, 0);
    expect(group.code, 0);
    expect(service.calls, ['c2c:bob', 'group:@TGS#room']);
  });

  test('rejects a successful SDK result that returns after account switch',
      () async {
    final service = _FakeMessageService();
    final pending = Completer<V2TimCallback>();
    service.pending = pending;
    final identity =
        SessionIdentityService.instance.capture(ownerUserId: 'alice');

    final future = TencentConversationReadService.markRead(
      messageService: service,
      conversationID: 'c2c_bob',
      isGroup: false,
      capturedIdentity: identity,
      explicitFullConversationClear: true,
    );
    await Future<void>.delayed(Duration.zero);
    SessionIdentityService.instance.invalidate(reason: 'test_account_switch');
    pending.complete(_success());

    final result = await future;
    expect(result.code, -1);
    expect(result.desc, 'stale_identity');
    expect(service.calls, ['c2c:bob']);
  });

  test('read SDK mutations stay inside the authority and SDK implementation',
      () {
    const allowed = <String>{
      'lib/src/services/im/tencent_conversation_read_service.dart',
      'third_party/tencent_cloud_chat_uikit/lib/data_services/message/'
          'message_service_implement.dart',
    };
    final directCall = RegExp(
      r'\.(?:markC2CMessageAsRead|markGroupMessageAsRead|'
      r'cleanConversationUnreadMessageCount)\(',
    );
    final actual = <String>{};
    for (final root in <String>[
      'lib',
      'third_party/tencent_cloud_chat_uikit/lib',
    ]) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (directCall.hasMatch(entity.readAsStringSync())) {
          actual.add(entity.path.replaceAll('\\', '/'));
        }
      }
    }
    expect(actual, allowed);
  });
}
