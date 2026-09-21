import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/archive_history_provider.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

V2TimMessage _row(String conversationID, int seq) => V2TimMessage.fromJson({
      'message_msg_id': 'm$seq',
      'message_seq': '$seq',
      'message_conv_id': conversationID,
      'message_conv_type': 2,
      'message_server_time': seq,
      'message_status': 2,
      'message_risk_type_identified': 0,
    })
      ..groupID = conversationID
      ..seq = '$seq'
      ..timestamp = seq
      ..status = 2
      ..elemType = 1
      ..textElem = V2TimTextElem(text: 'message $seq');

class _CommunitySdk extends MessageService {
  Future<V2TimMessageListResult> Function()? page;
  bool fail = false;
  int cloudCalls = 0;
  int localCalls = 0;

  Future<V2TimMessageListResult> _read(HistoryMsgGetTypeEnum getType) async {
    final isCloud =
        getType == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG ||
            getType == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG;
    if (isCloud) {
      cloudCalls++;
    } else {
      localCalls++;
    }
    if (fail) {
      throw StateError('controlled SDK history failure');
    }
    final readPage = page;
    if (readPage == null) {
      throw StateError('SDK page not configured');
    }
    return readPage();
  }

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
    return _read(getType);
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
    return MessageHistorySdkResult(
      code: 0,
      desc: 'controlled SDK page',
      data: await _read(getType),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK call ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  var generation = 0;
  late _CommunitySdk sdk;
  late TUIChatSeparateViewModel model;
  late TUIChatGlobalModel global;
  late String conversationID;
  var archiveCalls = 0;

  setUp(() async {
    await serviceLocator.unregister<MessageService>();
    sdk = _CommunitySdk();
    serviceLocator.registerSingleton<MessageService>(sdk);

    await serviceLocator.unregister<TUIChatGlobalModel>();
    global = TUIChatGlobalModel();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(global);

    conversationID = '@TGS#community_sdk_${++generation}';
    model = TUIChatSeparateViewModel()
      ..conversationID = conversationID
      ..conversationType = ConvType.group
      ..groupType = GroupReceiptAllowType.community
      ..groupInfo = V2TimGroupInfo(
        groupID: conversationID,
        groupType: 'Community',
      )
      ..chatConfig = const TIMUIKitChatConfig(
        isAutoReportRead: false,
        isShowReadingStatus: false,
      )
      ..suppressReadReporting = true;

    global.configureMessageWriterScope(
      ownerUserID: 'community-sdk-test-owner',
      accountGeneration: generation,
      domainGeneration: 1,
    );
    global.setMessageList(
      conversationID,
      <V2TimMessage>[
        _row(conversationID, 100),
        _row(conversationID, 99),
      ],
      replace: true,
      applyMemoryWindow: false,
    );

    archiveCalls = 0;
    ArchiveHistoryProvider.register((_) async {
      archiveCalls++;
      return ArchiveHistoryResult.empty;
    });
  });

  tearDown(() async {
    ArchiveHistoryProvider.register(null);
    model.dispose();
    global.clearData();
  });

  test('non-empty Community SDK older page is committed without archive',
      () async {
    sdk.page = () async => V2TimMessageListResult(
          isFinished: false,
          messageList: <V2TimMessage>[
            _row(conversationID, 98),
            _row(conversationID, 97),
          ],
        );

    final loaded = await model.loadChatRecord(
      count: 2,
      lastMsgID: 'm99',
      lastMsgSeq: 99,
    );

    expect(loaded, isTrue);
    expect(sdk.cloudCalls, greaterThan(0));
    expect(archiveCalls, 0);
    expect(
      global.rawMessageList(conversationID)!.map((message) => message.msgID),
      containsAllInOrder(<String>['m100', 'm99', 'm98', 'm97']),
    );
  });

  test('empty Community SDK page never requests archive history', () async {
    sdk.page = () async => V2TimMessageListResult(
          isFinished: true,
          messageList: <V2TimMessage>[],
        );

    final loaded = await model.loadChatRecord(
      count: 2,
      lastMsgID: 'm99',
      lastMsgSeq: 99,
    );

    expect(loaded, isFalse);
    expect(archiveCalls, 0);
    expect(
      global.rawMessageList(conversationID)!.map((message) => message.msgID),
      <String>['m100', 'm99'],
    );
    expect(model.haveMoreData, isFalse);
  });

  test('SDK failure preserves the window and remains retryable', () async {
    sdk.fail = true;
    sdk.page = () async => V2TimMessageListResult(
          isFinished: false,
          messageList: <V2TimMessage>[_row(conversationID, 98)],
        );

    final failed = await model.loadChatRecord(
      count: 2,
      lastMsgID: 'm99',
      lastMsgSeq: 99,
    );

    expect(failed, isFalse);
    expect(model.haveMoreData, isTrue);
    expect(archiveCalls, 0);
    expect(
      global.rawMessageList(conversationID)!.map((message) => message.msgID),
      <String>['m100', 'm99'],
    );

    sdk.fail = false;
    final retried = await model.loadChatRecord(
      count: 2,
      lastMsgID: 'm99',
      lastMsgSeq: 99,
    );

    expect(retried, isTrue);
    expect(archiveCalls, 0);
    expect(
      global.rawMessageList(conversationID)!.map((message) => message.msgID),
      contains('m98'),
    );
  });
}
