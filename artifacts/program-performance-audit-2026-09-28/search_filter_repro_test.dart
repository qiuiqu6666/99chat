// Audit reproduction asserting the current late-result defect.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_param.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_result_item.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_search_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/core_services_implements.dart';
import 'package:tencent_cloud_chat_uikit/data_services/conversation/conversation_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/friendShip/friendship_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';

class AuditCore extends CoreServicesImpl {
  @override
  LoginInfo get loginInfo => LoginInfo(userID: 'audit-search-owner');
}
class AuditFriendships implements FriendshipServices {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class AuditGroups implements GroupServices {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class AuditConversations implements ConversationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class AuditMessages implements MessageService {
  final localStarted = Completer<void>();
  final localResponse = Completer<V2TimValueCallback<V2TimMessageSearchResult>>();
  @override
  Future<V2TimValueCallback<V2TimMessageSearchResult>> searchCloudMessages({
    required V2TimMessageSearchParam searchParam,
  }) async => V2TimValueCallback(code: 6001, desc: 'audit cloud unavailable');
  @override
  Future<V2TimValueCallback<V2TimMessageSearchResult>> searchLocalMessages({
    required V2TimMessageSearchParam searchParam,
  }) {
    if (!localStarted.isCompleted) localStarted.complete();
    return localResponse.future;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('reproduces late local results repopulating a disposed filter page', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.instance.saveToken('audit-test-token', userId: 'audit-search-owner');
    await serviceLocator.reset();
    final messages = AuditMessages();
    serviceLocator.registerSingleton<CoreServicesImpl>(AuditCore()..isLoginSuccess = true);
    serviceLocator.registerSingleton<FriendshipServices>(AuditFriendships());
    serviceLocator.registerSingleton<GroupServices>(AuditGroups());
    serviceLocator.registerSingleton<ConversationService>(AuditConversations());
    serviceLocator.registerSingleton<MessageService>(messages);
    final model = TUISearchViewModel();
    final request = model.searchConversationWithFilter(
      conversationId: 'c2c_audit-old-peer',
      userID: 'audit-old-peer', reset: true,
      userIDList: ['audit-old-peer'],
    );
    await messages.localStarted.future;
    // Exactly the lifecycle call made by the filter page dispose().
    model.clearConversationFilterResults();
    expect(model.conversationFilterMessages, isEmpty);
    messages.localResponse.complete(V2TimValueCallback(
      code: 0, desc: 'ok',
      data: V2TimMessageSearchResult(messageSearchResultItems: [
        V2TimMessageSearchResultItem(
          conversationID: 'c2c_audit-old-peer', messageCount: 1,
          messageList: [V2TimMessage.fromJson({
            'message_risk_type_identified': 0,
            'message_msg_id': 'stale-old-page-message',
            'message_server_time': 10,
          })],
        ),
      ]),
    ));
    await request;
    expect(model.conversationFilterMessages.single.msgID, 'stale-old-page-message');
    model.dispose();
    await serviceLocator.reset();
    await ApiClient.instance.clearToken();
  });
}
