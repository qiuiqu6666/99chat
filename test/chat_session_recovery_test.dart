import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_history_sync_coordinator.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/life_cycle/chat_life_cycle.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_recovery_trace.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_history_recovery_notice.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_history_window_transition.dart';

class _Global extends TUIChatGlobalModel {
  Future<void> Function()? preflight;
  List<V2TimMessage>? aliasWindow;
  @override
  int rawMessageCount(String conversationID) => aliasWindow != null
      ? (conversationID.startsWith('c2c_') ? aliasWindow!.length : 0)
      : super.rawMessageCount(conversationID);
  @override
  List<V2TimMessage>? rawMessageList(String conversationID) =>
      aliasWindow != null && conversationID.startsWith('c2c_')
          ? aliasWindow
          : super.rawMessageList(conversationID);
  @override
  Future<void> syncHistoryClearEpochFromWindowStore(
      String conversationID) async {
    await preflight?.call();
  }
}

class _Sdk extends MessageService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  int historyCalls = 0;
  final revoked = <String>[];
  final revokeReplies = <Completer<V2TimCallback>>[];
  List<V2TimMessage> page = [];
  @override
  Future<MessageHistorySdkResult> getHistoryMessageListWithStatus({
    HistoryMsgGetTypeEnum getType =
        HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
    String? userID,
    String? groupID,
    int lastMsgSeq = -1,
    required int count,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    List<int>? messageTypeList,
    List<int>? messageSeqList,
    int? timeBegin,
    int? timePeriod,
  }) async {
    historyCalls++;
    return MessageHistorySdkResult(
        code: 0,
        desc: 'ok',
        data: V2TimMessageListResult(isFinished: true, messageList: page));
  }

  @override
  Future<V2TimCallback> revokeMessage(
      {required String msgID,
      Object? webMessageInstance,
      V2TimMessage? message}) {
    revoked.add(msgID);
    final response = Completer<V2TimCallback>();
    revokeReplies.add(response);
    return response.future;
  }
}

class _Repository implements HistoryWindowRepository {
  Future<void> Function(HistoryWindowMutation)? write;
  Future<List<V2TimMessage>> Function(List<V2TimMessage>)? read;
  final mutations = <HistoryWindowMutation>[];
  @override
  Future<void> recordMutation(HistoryWindowMutation mutation) async {
    mutations.add(mutation);
    await write?.call(mutation);
  }

  @override
  Future<List<V2TimMessage>> applyMutations(
          {required HistoryWindowScope scope,
          required List<V2TimMessage> messages}) async =>
      await read?.call(messages) ?? messages;
  @override
  Future<void> closeSession(HistoryWindowScope scope) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

V2TimMessage _row(String conv, int n) => V2TimMessage.fromJson({
      'message_msg_id': 'm$n',
      'message_server_time': n,
      'message_risk_type_identified': 0,
    })
      ..userID = conv
      ..id = 'local$n'
      ..isSelf = true
      ..status = 2
      ..elemType = 1
      ..textElem = V2TimTextElem(text: 'row$n');

void main() {
  test('old pagination completion cannot release a new visit priority', () {
    final coordinator = ConversationHistorySyncCoordinator.instance;
    final oldOwner = coordinator.beginUserOlderPagination('c2c_overlap');
    final newOwner = coordinator.beginUserOlderPagination('c2c_overlap');
    coordinator.endUserOlderPagination('c2c_overlap', oldOwner);
    expect(coordinator.isUserOlderPaginationActive('c2c_overlap'), isTrue);
    coordinator.endUserOlderPagination('c2c_overlap', oldOwner);
    expect(coordinator.isUserOlderPaginationActive('c2c_overlap'), isTrue);
    coordinator.endUserOlderPagination('c2c_overlap', newOwner);
    expect(coordinator.isUserOlderPaginationActive('c2c_overlap'), isFalse);
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  late _Global global;
  late TUIChatSeparateViewModel model;
  late _Sdk sdk;
  var serial = 0;
  setUp(() async {
    HistoryWindowRepositoryProvider.repository = null;
    await serviceLocator.unregister<TUIChatGlobalModel>();
    await serviceLocator.unregister<MessageService>();
    sdk = _Sdk();
    serviceLocator.registerSingleton<MessageService>(sdk);
    global = _Global();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
    model = TUIChatSeparateViewModel()
      ..conversationID = 'recovery${++serial}'
      ..conversationType = ConvType.c2c
      ..suppressReadReporting = true
      ..chatConfig = const TIMUIKitChatConfig(isShowReadingStatus: false);
    global.configureMessageWriterScope(
        ownerUserID: 'owner', accountGeneration: serial, domainGeneration: 1);
    global.appMessageReconciliationNetworkStateProvider =
        () => MessageReconciliationNetworkState.online;
    global.setMessageList(
        model.conversationID, [_row(model.conversationID, 100)],
        applyMemoryWindow: false);
    sdk.page = [_row(model.conversationID, 99)];
  });
  tearDown(() {
    model.dispose();
    HistoryWindowRepositoryProvider.repository = null;
  });
  Future<bool> load() => model.loadChatRecord(
      count: 20, lastMsgID: 'm100', lastMsg: _row(model.conversationID, 100));

  testWidgets(
      'visit binding completes before alias disk read and a repeated init does not race',
      (tester) async {
    final repository = _Repository();
    HistoryWindowRepositoryProvider.repository = repository;
    final pending = Completer<List<V2TimMessage>>();
    var reads = 0;
    repository.read = (_) {
      reads++;
      return pending.future;
    };
    global.aliasWindow = [_row(model.conversationID, 100)];
    final conv = model.conversationID;
    var done = false;
    unawaited(Future<void>.sync(() => (model as dynamic)
            .initForEachConversation(ConvType.c2c, 'c2c_$conv', null))
        .then((_) => done = true));
    expect(global.currentSelectedConv, conv);
    await (model as dynamic)
        .initForEachConversation(ConvType.c2c, 'c2c_$conv', null);
    expect(reads, 1);
    await tester.pump(const Duration(seconds: 21));
    expect(done, isTrue);
    pending.complete(global.aliasWindow!);
    global.aliasWindow = null;
    await tester.pump();
  });

  testWidgets(
      'initial hydration disk wait expires without a late window replacement',
      (tester) async {
    final repository = _Repository();
    HistoryWindowRepositoryProvider.repository = repository;
    final pending = Completer<List<V2TimMessage>>();
    repository.read = (_) => pending.future;
    var done = false;
    unawaited(model
        .hydrateInitialHistoryPeekStyle(plainOpen: true)
        .then((_) => done = true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 21));
    expect(done, isTrue);
    expect(model.isLoadingChatHistory, isFalse);
    pending.complete([_row(model.conversationID, 50)]);
    await tester.pump();
    expect(global.rawMessageList(model.conversationID)!.map((m) => m.msgID),
        isNot(contains('m50')));
  });

  testWidgets(
      'preflight exception releases pagination and the same page can retry',
      (tester) async {
    global.preflight = () async => throw StateError('disk failed');
    expect(await load(), isFalse);
    expect(model.isLoadingChatHistory, isFalse);
    expect(sdk.historyCalls, 0);
    global.preflight = null;
    await load();
    expect(sdk.historyCalls, greaterThan(0));
    expect(global.rawMessageList(model.conversationID)!.map((m) => m.msgID),
        contains('m99'));
    expect(model.isLoadingChatHistory, isFalse);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('hung preflight times out, retries, and ignores late completion',
      (tester) async {
    final pending = Completer<void>();
    global.preflight = () => pending.future;
    var done = false;
    unawaited(load().then((_) => done = true));
    await tester.pump();
    expect(model.isLoadingChatHistory, isTrue);
    await tester.pump(const Duration(seconds: 21));
    expect(done, isTrue);
    expect(model.isLoadingChatHistory, isFalse);
    global.preflight = null;
    await load();
    final calls = sdk.historyCalls;
    pending.complete();
    await tester.pump();
    expect(sdk.historyCalls, calls);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('old preflight cannot adopt a new conversation after its await',
      (tester) async {
    final pending = Completer<void>();
    global.preflight = () => pending.future;
    final result = load();
    model.conversationID = 'another-peer';
    pending.complete();
    expect(await result, isFalse);
    expect(sdk.historyCalls, 0);
    expect(model.isLoadingChatHistory, isFalse);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets(
      'hung host history callback releases its lock and cannot publish late',
      (tester) async {
    final pending = Completer<List<V2TimMessage>>();
    var entered = false;
    model.lifeCycle = ChatLifeCycle(didGetHistoricalMessageList: (_) {
      entered = true;
      return pending.future;
    });
    unawaited(load());
    await tester.pump();
    expect(entered, isTrue);
    await tester.pump(const Duration(seconds: 21));
    expect(model.isLoadingChatHistory, isFalse);
    model.lifeCycle = null;
    sdk.page = [_row(model.conversationID, 98)];
    await load();
    pending.complete([_row(model.conversationID, 50)]);
    await tester.pump();
    expect(global.rawMessageList(model.conversationID)!.map((m) => m.msgID),
        isNot(contains('m50')));
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets(
      'revoke preflight failure leaves the row and permits the next revoke',
      (tester) async {
    final repository = _Repository();
    HistoryWindowRepositoryProvider.repository = repository;
    repository.write = (_) async => throw StateError('disk failed');
    await model.revokeMsg('m100', false);
    expect(sdk.revoked, isEmpty);
    expect(global.rawMessageList(model.conversationID)!.first.status, 2);
    repository.write = null;
    await model.revokeMsg('local100', false);
    expect(sdk.revoked, ['m100']);
    sdk.revokeReplies.single.complete(V2TimCallback(code: 0, desc: 'ok'));
    await tester.pump();
  });

  testWidgets(
      'revoke stops before SDK if its view changes during durable preparation',
      (tester) async {
    final repository = _Repository();
    HistoryWindowRepositoryProvider.repository = repository;
    final pending = Completer<void>();
    repository.write =
        (mutation) => mutation.pending ? pending.future : Future.value();
    final originalConv = model.conversationID;
    final result = model.revokeMsg('m100', false);
    model.conversationID = 'another-peer';
    pending.complete();
    await result;
    expect(sdk.revoked, isEmpty);
    expect(repository.mutations.last.kind, HistoryWindowMutationKind.restore);
    expect(repository.mutations.last.conversationID, 'c2c_$originalConv');
  });

  testWidgets(
      'revoke SDK timeout restores retryability and accepts late SDK success',
      (tester) async {
    await model.revokeMsg('m100', false);
    expect(sdk.revoked, ['m100']);
    await tester.pump(const Duration(seconds: 21));
    expect(global.rawMessageList(model.conversationID)!.first.status, 2);
    expect(sdk.revoked.length, 1,
        reason: 'unknown outcome must not auto-resend');
    sdk.revokeReplies.single
        .complete(V2TimCallback(code: 0, desc: 'late success'));
    await tester.pump();
    expect(global.rawMessageList(model.conversationID)!.first.status, 6);
    expect(
        ChatRecoveryTrace.recentEvents
            .any((e) => e.contains('revoke_sdk_late_result')),
        isTrue);
  });

  testWidgets(
      'settle retries a transient disk failure without sending the SDK command twice',
      (tester) async {
    final repository = _Repository();
    HistoryWindowRepositoryProvider.repository = repository;
    var settles = 0;
    repository.write = (mutation) async {
      if (mutation.kind == HistoryWindowMutationKind.settle && ++settles == 1) {
        throw StateError('disk temporarily unavailable');
      }
    };
    await model.revokeMsg('m100', false);
    sdk.revokeReplies.single.complete(V2TimCallback(code: 0, desc: 'ok'));
    await tester.pump();
    expect(settles, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(settles, 2);
    expect(sdk.revoked, ['m100']);
    expect(
        ChatRecoveryTrace.recentEvents.any((event) =>
            event.contains('mutation_completion_retry') &&
            event.contains('msg=m100')),
        isTrue);
  });

  testWidgets(
      'hung revoke preparation expires before SDK and compensates its late token',
      (tester) async {
    final repository = _Repository();
    HistoryWindowRepositoryProvider.repository = repository;
    final pending = Completer<void>();
    repository.write =
        (mutation) => mutation.pending ? pending.future : Future.value();
    var done = false;
    unawaited(model.revokeMsg('m100', false).then((_) => done = true));
    await tester.pump(const Duration(seconds: 21));
    expect(done, isTrue);
    expect(sdk.revoked, isEmpty);
    expect(repository.mutations.first.isCurrent!(), isFalse);
    repository.write = null;
    await model.revokeMsg('m100', false);
    expect(sdk.revoked, ['m100']);
    pending.complete();
    sdk.revokeReplies.single.complete(V2TimCallback(code: 0, desc: 'ok'));
    await tester.pump();
    expect(
        repository.mutations
            .any((m) => m.kind == HistoryWindowMutationKind.restore),
        isTrue);
  });

  testWidgets('abandoned transition releases input without a finish callback',
      (tester) async {
    final key = GlobalKey<ChatHistoryWindowTransitionState>();
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
        home: ChatHistoryWindowTransition(
            key: key,
            child: Center(
                child: TextButton(
                    onPressed: () => taps++, child: const Text('touch'))))));
    key.currentState!.begin(retainViewport: false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 26));
    await tester.tap(find.text('touch'));
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('blank history exposes retry and hung retries release the button',
      (tester) async {
    var calls = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChatHistoryRecoveryNotice(
                conversationID: 'peer',
                onRetry: () {
                  calls++;
                  return pending.future;
                }))));
    await tester.pump(const Duration(seconds: 13));
    await tester.tap(find.text('重新加载'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 26));
    await tester.tap(find.text('重新加载'));
    expect(calls, 2);
    pending.complete();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
  });
}
