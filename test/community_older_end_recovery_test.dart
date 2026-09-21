import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/controllers/history_pagination_controller.dart'
    show HistoryAvailability;
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/archive_history_provider.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

V2TimMessage _row(String conversationID, int seq) => V2TimMessage.fromJson({
      'message_msg_id': 'm$seq',
      'message_conv_id': conversationID,
      'message_conv_type': 2,
      'message_server_time': seq,
      'message_risk_type_identified': 0,
    })
      ..groupID = conversationID
      ..seq = '$seq'
      ..timestamp = seq
      ..status = 2
      ..elemType = 1
      ..textElem = V2TimTextElem(text: 'message $seq');

typedef _OlderRequest = ({
  HistoryMsgGetTypeEnum type,
  String? messageID,
  int seq,
  int count,
});

class _CommunityOlderSdk extends MessageService {
  late V2TimMessageListResult Function(_OlderRequest request) page;
  final requests = <_OlderRequest>[];

  @override
  Future<V2TimMessageListResult?> getHistoryMessageListWithComplete({
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
    return (await getHistoryMessageListWithStatus(
            getType: getType,
            userID: userID,
            groupID: groupID,
            lastMsgSeq: lastMsgSeq,
            count: count,
            lastMsgID: lastMsgID,
            lastMsg: lastMsg,
            messageTypeList: messageTypeList,
            messageSeqList: messageSeqList,
            timeBegin: timeBegin,
            timePeriod: timePeriod))
        .data;
  }

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
    final request = (
      type: getType,
      messageID: lastMsgID ?? lastMsg?.msgID,
      seq: int.tryParse(lastMsg?.seq ?? '') ?? lastMsgSeq,
      count: count,
    );
    requests.add(request);
    return MessageHistorySdkResult(
        code: 0, desc: 'controlled Community SDK page', data: page(request));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK call ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _CommunityOlderSdk sdk;
  late TUIChatGlobalModel global;
  late TUIChatSeparateViewModel model;
  var generation = 0;
  var archiveCalls = 0;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  setUp(() async {
    HistoryWindowRepositoryProvider.repository = null;
    await serviceLocator.unregister<MessageService>();
    sdk = _CommunityOlderSdk();
    serviceLocator.registerSingleton<MessageService>(sdk);
    await serviceLocator.unregister<TUIChatGlobalModel>();
    global = TUIChatGlobalModel();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
    final conv = '@TGS#community_end_recovery_${++generation}';
    model = TUIChatSeparateViewModel()
      ..conversationID = conv
      ..conversationType = ConvType.group
      ..groupType = GroupReceiptAllowType.community
      ..groupInfo = V2TimGroupInfo(groupID: conv, groupType: 'Community')
      ..chatConfig = const TIMUIKitChatConfig(
          isAutoReportRead: false, isShowReadingStatus: false)
      ..suppressReadReporting = true;
    global.configureMessageWriterScope(
        ownerUserID: 'community-end-recovery-owner',
        accountGeneration: generation,
        domainGeneration: 1);
    global.setMessageList(
        conv, [for (var seq = 100; seq >= 81; seq--) _row(conv, seq)],
        replace: true, applyMemoryWindow: false);
    archiveCalls = 0;
    ArchiveHistoryProvider.register((_) async {
      archiveCalls++;
      return ArchiveHistoryResult.empty;
    });
  });

  tearDown(() {
    ArchiveHistoryProvider.register(null);
    HistoryWindowRepositoryProvider.repository = null;
    model.dispose();
    global.clearData();
  });

  List<int> currentSeqs() => global
      .rawMessageList(model.conversationID)!
      .map((message) => int.parse(message.seq!))
      .toList();

  Future<bool> loadFromOldest() {
    final anchor = global.rawMessageList(model.conversationID)!.last;
    return model.loadChatRecord(
        count: 20,
        lastMsgID: anchor.msgID,
        lastMsgSeq: int.parse(anchor.seq!),
        lastMsg: anchor,
        direction: LoadDirection.previous);
  }

  void expectOlderGestureRemainsEligible(String reason) {
    // The production list accepts an older gesture only when haveMoreData is
    // true or availability is unknown. Calling loadChatRecord directly alone
    // would bypass that UI gate and conceal a permanently exhausted page.
    expect(model.historyAvailability, isNot(HistoryAvailability.exhausted),
        reason: reason);
    expect(
        model.haveMoreData ||
            model.historyAvailability == HistoryAvailability.unknown,
        isTrue,
        reason: reason);
  }

  test('a five-row synthesized finished page keeps Community older continuation',
      () async {
    sdk.page = (request) {
      final length = request.seq == 81 ? 5 : request.count;
      return V2TimMessageListResult(
        // Mirrors the native adapter's len < requested count synthesis. The
        // older source still has data beyond this short local/cloud batch.
        isFinished: length < request.count,
        messageList: [
          for (var index = 1; index <= length; index++)
            _row(model.conversationID, request.seq - index),
        ],
      );
    };

    expect(await loadFromOldest(), isTrue);
    expect(sdk.requests.first.count, 20);
    expect(sdk.requests.first.seq, 81);
    expect(currentSeqs(), containsAllInOrder([80, 79, 78, 77, 76]));
    expectOlderGestureRemainsEligible(
        'a nonempty short SDK page is not verified end-of-history proof');
    expect(global.messageHistoryCoverageFor(model.conversationID)?.olderExhausted,
        isNot(isTrue),
        reason: 'the shared coverage must retain continuation along with UI state');
    final previousOldest = currentSeqs().last;
    final requestsBeforeRetry = sdk.requests.length;
    expect(await loadFromOldest(), isTrue);
    expect(sdk.requests.length, greaterThan(requestsBeforeRetry));
    expect(sdk.requests[requestsBeforeRetry].seq, previousOldest);
    expect(currentSeqs().last, lessThan(previousOldest));
    expect(archiveCalls, 0);
  });

  test('a local short finished page cannot exhaust the Community cloud chain',
      () async {
    var cloudRecovered = false;
    sdk.page = (request) {
      final cloud =
          request.type == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG;
      if (cloud && !cloudRecovered) {
        return V2TimMessageListResult(isFinished: true, messageList: []);
      }
      final length = cloudRecovered ? request.count : 5;
      return V2TimMessageListResult(
        isFinished: length < request.count,
        messageList: [
          for (var index = 1; index <= length; index++)
            _row(model.conversationID, request.seq - index),
        ],
      );
    };

    expect(await loadFromOldest(), isTrue);
    expect(
        sdk.requests.map((request) => request.type),
        containsAll([
          HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
          HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
        ]));
    expect(currentSeqs(), [for (var seq = 100; seq >= 76; seq--) seq]);
    expectOlderGestureRemainsEligible(
        'a local cache end does not establish the remote Community boundary');

    cloudRecovered = true;
    final requestsBeforeRetry = sdk.requests.length;
    expect(await loadFromOldest(), isTrue);
    expect(sdk.requests[requestsBeforeRetry].type,
        HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG);
    expect(sdk.requests[requestsBeforeRetry].seq, 76,
        reason: 'retry must continue from the accepted local page boundary');
    expect(currentSeqs(), [for (var seq = 100; seq >= 56; seq--) seq]);
    expect(archiveCalls, 0);
  });

  test('a five-row cold initial Community window can continue loading older',
      () async {
    global.setMessageList(model.conversationID, [],
        replace: true, applyMemoryWindow: false);
    sdk.page = (request) => V2TimMessageListResult(
          isFinished: request.seq <= 0,
          messageList: request.seq <= 0
              ? [for (var seq = 100; seq >= 96; seq--) _row(model.conversationID, seq)]
              : [
                  for (var index = 1; index <= request.count; index++)
                    _row(model.conversationID, request.seq - index),
                ],
        );

    expect(
        await model.hydrateInitialHistoryPeekStyle(
            count: 20, retryDelays: [Duration.zero]),
        isTrue);
    expect(sdk.requests.first.count, 20);
    expect(currentSeqs(), containsAllInOrder([100, 99, 98, 97, 96]));
    expectOlderGestureRemainsEligible(
        'a five-row first screen must not hide the remaining Community history');
    final before = currentSeqs().last;
    final requestsBefore = sdk.requests.length;
    expect(await loadFromOldest(), isTrue);
    expect(sdk.requests[requestsBefore].seq, before);
    expect(currentSeqs().last, lessThan(before));
    expect(archiveCalls, 0);
  });

  test('reloading a short newest Community window preserves older continuation',
      () async {
    sdk.page = (request) => V2TimMessageListResult(
          isFinished: request.seq <= 0,
          messageList: request.seq <= 0
              ? [for (var seq = 100; seq >= 96; seq--) _row(model.conversationID, seq)]
              : [
                  for (var index = 1; index <= request.count; index++)
                    _row(model.conversationID, request.seq - index),
                ],
        );

    expect(
        await model.reloadNewestMessageWindow(
            count: 20, allowWhileReadingHistory: true),
        isTrue);
    expect(currentSeqs(), containsAllInOrder([100, 99, 98, 97, 96]));
    expectOlderGestureRemainsEligible(
        'returning to newest must not carry a short-page end into older history');
    expect(global.messageHistoryCoverageFor(model.conversationID)?.olderExhausted,
        isNot(isTrue));
    final previousOldest = currentSeqs().last;
    final requestsBefore = sdk.requests.length;
    expect(await loadFromOldest(), isTrue);
    expect(sdk.requests[requestsBefore].seq, previousOldest);
    expect(currentSeqs(),
        [for (var seq = 100; seq >= previousOldest - 20; seq--) seq]);
    expect(archiveCalls, 0);
  });

  test('an around-message short older side remains pageable in Community',
      () async {
    sdk.page = (request) {
      final newer =
          request.type == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG ||
              request.type == HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG;
      return V2TimMessageListResult(
        isFinished: !newer || request.seq + 5 >= 100,
        messageList: newer
            ? [
                for (var seq = (request.seq + 5).clamp(0, 100);
                    seq > request.seq;
                    seq--)
                  _row(model.conversationID, seq),
              ]
            : [
                for (var index = 1; index <= 5; index++)
                  _row(model.conversationID, request.seq - index),
              ],
      );
    };

    expect(
        await model.loadListForSpecificMessage(
            seq: 90, targetMessage: _row(model.conversationID, 90)),
        isTrue);
    expect(currentSeqs(), contains(90));
    expect(currentSeqs().last, lessThan(90));
    expectOlderGestureRemainsEligible(
        'the nonempty older side of an around window must remain pageable');
    final before = currentSeqs().last;
    expect(await loadFromOldest(), isTrue);
    expect(currentSeqs().last, lessThan(before));
    expect(archiveCalls, 0);
  });

  test('a rejected local gap cannot turn an empty cloud page into Community EOF',
      () async {
    var cloudRecovered = false;
    sdk.page = (request) {
      if (cloudRecovered) {
        return V2TimMessageListResult(
          isFinished: false,
          messageList: [
            for (var index = 1; index <= request.count; index++)
              _row(model.conversationID, request.seq - index),
          ],
        );
      }
      final cloud =
          request.type == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG;
      return V2TimMessageListResult(
        isFinished: true,
        messageList: cloud
            ? []
            : [for (var seq = 70; seq >= 66; seq--) _row(model.conversationID, seq)],
      );
    };
    final original = currentSeqs();

    expect(await loadFromOldest(), isFalse);
    expect(currentSeqs(), original,
        reason: 'local 70..66 is disconnected from the current oldest 81');
    expect(sdk.requests.map((request) => request.type),
        contains(HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG));
    expect(sdk.requests.every((request) => request.seq == 81), isTrue);
    expectOlderGestureRemainsEligible(
        'rejecting a disconnected local page must not prove remote EOF');

    final callsAfterFirstRejection = sdk.requests.length;
    final localCallsAfterFirstRejection = sdk.requests
        .where((request) =>
            request.type == HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG)
        .length;
    expect(await loadFromOldest(), isFalse);
    expect(sdk.requests.length, greaterThan(callsAfterFirstRejection),
        reason: 'the second attempt must really check cloud history again');
    expect(
        sdk.requests
            .where((request) =>
                request.type == HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG)
            .length,
        localCallsAfterFirstRejection,
        reason: 'the local fallback remains inside its five-second cooldown');
    expect(currentSeqs(), original);
    expectOlderGestureRemainsEligible(
        'skipping the recently rejected local fallback does not prove EOF');

    cloudRecovered = true;
    final requestsBeforeRetry = sdk.requests.length;
    expect(await loadFromOldest(), isTrue);
    expect(sdk.requests[requestsBeforeRetry].type,
        HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG);
    expect(sdk.requests[requestsBeforeRetry].seq, 81);
    expect(currentSeqs(), [for (var seq = 100; seq >= 61; seq--) seq]);
    expect(archiveCalls, 0);
  });

  for (final wrongDirection in [false, true]) {
    test(
        '${wrongDirection ? "wrong-direction" : "duplicate"} finished page does not poison the Community older gate',
        () async {
      var sourceRecovered = false;
      sdk.page = (request) => V2TimMessageListResult(
            isFinished: !sourceRecovered,
            messageList: sourceRecovered
                ? [
                    for (var index = 1; index <= request.count; index++)
                      _row(model.conversationID, request.seq - index),
                  ]
                : [
                    _row(model.conversationID, wrongDirection ? 82 : 81),
                  ],
          );
      final original = currentSeqs();

      expect(await loadFromOldest(), isFalse);
      expect(currentSeqs(), original);
      expect(sdk.requests, isNotEmpty);
      expect(sdk.requests.every((request) => request.seq == 81), isTrue,
          reason: 'a rejected page must not advance the older cursor');
      expectOlderGestureRemainsEligible(
          'a rejected finished page must allow another deliberate older gesture');

      sourceRecovered = true;
      final requestsBeforeRetry = sdk.requests.length;
      expect(await loadFromOldest(), isTrue);
      expect(sdk.requests[requestsBeforeRetry].seq, 81);
      expect(currentSeqs(), [for (var seq = 100; seq >= 61; seq--) seq]);
      expect(archiveCalls, 0);
    });
  }

  test('an empty finished Community boundary stays exhausted without a loop',
      () async {
    sdk.page = (_) =>
        V2TimMessageListResult(isFinished: true, messageList: []);
    final original = currentSeqs();

    expect(await loadFromOldest(), isFalse);
    expect(currentSeqs(), original);
    expect(model.historyAvailability, HistoryAvailability.exhausted);
    expect(model.haveMoreData, isFalse);
    expect(model.isLoadingChatHistory, isFalse);
    final callsAtEnd = sdk.requests.length;
    await Future<void>.delayed(Duration.zero);
    expect(sdk.requests.length, callsAtEnd);
    expect(model.historyAvailability, HistoryAvailability.exhausted);
    expect(archiveCalls, 0);
  });
}
