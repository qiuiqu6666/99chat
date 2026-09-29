import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_param.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_result_item.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_search_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/conversation/conversation_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/core_services_implements.dart';
import 'package:tencent_cloud_chat_uikit/data_services/friendShip/friendship_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

typedef _Reply = V2TimValueCallback<V2TimMessageSearchResult>;
class _Core extends CoreServicesImpl {
  @override
  LoginInfo get loginInfo => LoginInfo(userID: 'search-owner');
}
class _Friends implements FriendshipServices {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Groups implements GroupServices {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Conversations implements ConversationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Messages implements MessageService {
  Future<_Reply> Function(V2TimMessageSearchParam)? cloud;
  Future<_Reply> Function(V2TimMessageSearchParam)? local;
  int cloudCalls = 0;
  int localCalls = 0;
  @override
  Future<_Reply> searchCloudMessages({required V2TimMessageSearchParam searchParam}) {
    cloudCalls++;
    return cloud?.call(searchParam) ?? Future.value(_Reply(code: 6001, desc: 'unavailable'));
  }
  @override
  Future<_Reply> searchLocalMessages({required V2TimMessageSearchParam searchParam}) {
    localCalls++;
    return local?.call(searchParam) ?? Future.value(_Reply(code: 6001, desc: 'unavailable'));
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _History implements TUIChatGlobalModel {
  int calls = 0;
  final cursors = <String?>[];
  bool repeatedCursor = false;
  bool fail = false;
  Future<void>? gate;
  int? matchingPage;
  @override
  Future<V2TimMessageListResult?> getHistoryMessageListThroughIm06({
    HistoryMsgGetTypeEnum getType = HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
    String? userID, String? groupID, int lastMsgSeq = -1, required int count,
    String? lastMsgID, V2TimMessage? lastMsg, List<int>? messageTypeList,
    List<int>? messageSeqList, int? timeBegin, int? timePeriod,
  }) async {
    calls++;
    cursors.add(lastMsgID);
    await gate;
    if (fail) return null;
    // Finite even on the broken implementation: the regression must fail,
    // not hang the test runner while proving the missing scan budget.
    final rows = calls > 8 ? <V2TimMessage>[] : [
      for (var i = 0; i < count; i++)
        _message('page${repeatedCursor ? 1 : calls}-$i')
          ..sender = calls == matchingPage ? 'wanted' : 'other'
          ..elemType = 1,
    ];
    return V2TimMessageListResult(isFinished: rows.isEmpty, messageList: rows);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
V2TimMessage _message(String id) => V2TimMessage.fromJson({
  'message_risk_type_identified': 0, 'message_msg_id': id, 'message_server_time': 10,
});
_Reply _reply(String conversation, String id) => _Reply(code: 0, desc: 'ok',
  data: V2TimMessageSearchResult(messageSearchResultItems: [
    V2TimMessageSearchResultItem(conversationID: conversation, messageCount: 1,
      messageList: [_message(id)]),
  ]));
Future<void> _turns() async {
  for (var i = 0; i < 8; i++) { await Future<void>.delayed(Duration.zero); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Messages messages;
  late _History history;
  TUISearchViewModel? model;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.instance.saveToken('synthetic-search-owner-token', userId: 'search-owner');
    await serviceLocator.reset();
    messages = _Messages();
    history = _History();
    serviceLocator.registerSingleton<CoreServicesImpl>(_Core()..isLoginSuccess = true);
    serviceLocator.registerSingleton<FriendshipServices>(_Friends());
    serviceLocator.registerSingleton<GroupServices>(_Groups());
    serviceLocator.registerSingleton<ConversationService>(_Conversations());
    serviceLocator.registerSingleton<MessageService>(messages);
    serviceLocator.registerSingleton<TUIChatGlobalModel>(history);
    model = TUISearchViewModel();
  });
  tearDown(() async {
    model?.dispose();
    await serviceLocator.reset();
    await ApiClient.instance.clearToken();
  });
  Future<void> search([String peer = 'old', bool reset = true]) => model!.searchConversationWithFilter(
    conversationId: 'c2c_$peer', userID: peer, reset: reset, userIDList: ['wanted']);

  test('cleared filter ignores late local success', () async {
    final pending = Completer<_Reply>();
    messages.local = (_) => pending.future;
    final task = search();
    await _turns();
    model!.clearConversationFilterResults();
    pending.complete(_reply('c2c_old', 'stale'));
    await task;
    expect(model!.conversationFilterMessages, isEmpty);
    expect(model!.conversationFilterLoading, isFalse);
  });

  test('new query replaces a busy query and old finally cannot end its loading', () async {
    final old = Completer<_Reply>();
    final fresh = Completer<_Reply>();
    messages.local = (param) => param.conversationID == 'c2c_old' ? old.future : fresh.future;
    final first = search();
    await _turns();
    final second = search('new');
    await _turns();
    old.complete(_reply('c2c_old', 'stale'));
    await first;
    final stillLoading = model!.conversationFilterLoading;
    fresh.complete(_reply('c2c_new', 'fresh'));
    await second;
    expect(messages.localCalls, 2);
    expect(stillLoading, isTrue);
    expect(model!.conversationFilterMessages.map((m) => m.msgID), ['fresh']);
  });

  test('old cloud error cannot disable the new query cloud lane', () async {
    final old = Completer<_Reply>();
    messages.cloud = (param) => param.conversationID == 'c2c_old'
        ? old.future : Future.value(_Reply(code: 0, desc: 'ok',
          data: V2TimMessageSearchResult(searchCursor: 'next', messageSearchResultItems: [])));
    final first = search();
    await _turns();
    await search('new');
    old.completeError(StateError('late cloud failure'));
    await first;
    await search('new', false);
    expect(messages.cloudCalls, 3);
    expect(messages.localCalls, 0);
  });

  test('same account new session invalidates a pending filter', () async {
    final pending = Completer<_Reply>();
    messages.local = (_) => pending.future;
    final task = search();
    await _turns();
    SessionIdentityService.instance.invalidate(reason: 'test relogin');
    pending.complete(_reply('c2c_old', 'previous-session'));
    await task;
    expect(model!.conversationFilterMessages, isEmpty);
  });

  test('disposing model during local request prevents late notification', () async {
    final pending = Completer<_Reply>();
    messages.local = (_) => pending.future;
    final task = search();
    await _turns();
    model!.dispose();
    model = null;
    pending.complete(_reply('c2c_old', 'disposed'));
    await expectLater(task, completes);
  });

  for (final lane in ['filter', 'file', 'assets']) {
    test('$lane history fallback stops after three pages without a match', () async {
      if (lane == 'filter') {
        await search();
        expect(model!.conversationFilterHasMore, isTrue);
        expect(model!.conversationFilterLoading, isFalse);
      } else if (lane == 'file') {
        await model!.loadMediaAndFileForConversation('c2c_old', reset: true, keyword: 'missing');
        expect(model!.mediaFileHasMore, isTrue);
        expect(model!.mediaFileLoading, isFalse);
      } else {
        await model!.loadConversationAssets('c2c_old', reset: true);
        expect(model!.conversationAssetHasMore, isTrue);
        expect(model!.conversationAssetLoading, isFalse);
      }
      expect(history.calls, lessThanOrEqualTo(3));
    });
  }
  test('continuing a scan starts from saved cursor and finds page four', () async {
    history.matchingPage = 4;
    await search();
    expect(model!.conversationFilterMessages, isEmpty);
    expect(history.calls, 3);
    await search('old', false);
    expect(history.cursors[3], 'page3-49');
    expect(model!.conversationFilterMessages.first.msgID, 'page4-0');
  });
  test('repeated cursor stops the current scan without exhausting history', () async {
    history.repeatedCursor = true;
    await search();
    expect(history.calls, lessThanOrEqualTo(2));
    expect(model!.conversationFilterHasMore, isTrue);
    expect(model!.conversationFilterLoading, isFalse);
  });
  test('clearing during history fallback prevents late page and next read', () async {
    final pending = Completer<void>();
    history.gate = pending.future;
    history.matchingPage = 1;
    final task = search();
    await _turns();
    model!.clearConversationFilterResults();
    pending.complete();
    await task;
    expect(model!.conversationFilterMessages, isEmpty);
    expect(history.calls, 1);
  });
  test('history failure stays resumable instead of reporting no more data', () async {
    history.fail = true;
    await search();
    expect(model!.conversationFilterHasMore, isTrue);
    expect(model!.conversationFilterScanError, isNotNull);
    expect(model!.conversationFilterLoading, isFalse);
  });
  test('asset page becoming hidden stops follow-up reads', () async {
    final pending = Completer<void>();
    history.gate = pending.future;
    var visible = true;
    final task = model!.loadConversationAssets('c2c_old', reset: true,
        isVisible: () => visible);
    await _turns();
    visible = false;
    pending.complete();
    await task;
    expect(history.calls, 1);
    expect(model!.conversationAssetLoading, isFalse);
    expect(model!.conversationAssetHasMore, isTrue);
  });
}
