import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/c2c_peer_rejected_tip_message.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/native_im/adapter/tim_manager.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/error_message_converter.dart';

class _TestClockManager implements TIMManager {
  @override
  int getServerTime() => 1700000000;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected native call: ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TIMManager originalNativeManager;
  late HistoryWindowRepository? previousRepository;
  late TUIChatGlobalModel global;

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    setupServiceLocator();
    originalNativeManager = TIMManager.instance;
    TIMManager.instance = _TestClockManager();
  });

  setUp(() {
    previousRepository = HistoryWindowRepositoryProvider.repository;
    HistoryWindowRepositoryProvider.repository = null;
    global = TUIChatGlobalModel();
    global.configureMessageWriterScope(
      ownerUserID: 'peer-rejected-owner',
      accountGeneration: 1,
      domainGeneration: 1,
    );
  });

  tearDown(() {
    global.dispose();
    HistoryWindowRepositoryProvider.repository = previousRepository;
  });

  tearDownAll(() {
    TIMManager.instance = originalNativeManager;
  });

  test('insertPeerRejectedLocalTip only inserts a local CUSTOM tip for 20007',
      () {
    const convID = 'send-peer';
    global.insertPeerRejectedLocalTip(convID, 0, clientId: 'local-0');
    global.insertPeerRejectedLocalTip(convID, 20011, clientId: 'local-11');
    expect(global.rawMessageList(convID) ?? const [], isEmpty);

    global.insertPeerRejectedLocalTip(convID, 20007, clientId: 'local-7');
    final list = global.rawMessageList(convID) ?? const [];
    expect(list, hasLength(1));
    final tip = list.single;
    expect(isC2cPeerRejectedTipMessage(tip), isTrue);
    expect(tip.elemType, MessageElemType.V2TIM_ELEM_TYPE_CUSTOM);
    expect(
      getC2cPeerRejectedTipDisplayText(tip.customElem),
      ErrorMessageConverter.getErrorMessage(20007),
    );
    expect(tip.id, 'peer-rejected:local-7');
  });

  test('insertPeerRejectedLocalTip dedupes the same clientId event', () {
    const convID = 'send-peer';
    global.insertPeerRejectedLocalTip(convID, 20007, clientId: 'same-local');
    global.insertPeerRejectedLocalTip(convID, 20007, clientId: 'same-local');
    expect(global.rawMessageList(convID), hasLength(1));
  });
}
