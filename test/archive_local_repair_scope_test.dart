import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/archive_im_local_persist_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/archive_history_provider.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class _HistorySdk extends MessageService {
  final requests = <({String? group, String? user, String? cursor})>[];
  Future<V2TimMessageListResult?> Function(int call)? read;

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
    expect(getType, HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG);
    expect(count, 100);
    expect(lastMsgSeq, -1);
    expect(lastMsgID, lastMsg?.msgID);
    requests.add((group: groupID, user: userID, cursor: lastMsg?.msgID));
    return read!(requests.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK call ${invocation.memberName}');
}

V2TimMessage _message(String id, {int status = 2, int timestamp = 100}) =>
    V2TimMessage.fromJson({
      'message_msg_id': id,
      'message_server_time': timestamp,
      'message_status': status,
      'message_risk_type_identified': 0,
    });

V2TimMessageListResult _page({int offset = 0, bool finished = false}) =>
    V2TimMessageListResult(
      isFinished: finished,
      messageList: List.generate(
        100,
        (index) => _message('144115268026882536-1784319908-${offset + index}'),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _HistorySdk sdk;
  late ArchiveImLocalPersistService repair;
  late List<String> deleted;

  Future<int> run({String id = '@TGS#repair', bool isGroup = true}) =>
      repair.purgeSpuriousLocalImported(isGroup: isGroup, conversationID: id);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance
        .saveToken('repair-test-token', userId: 'repair-owner');
    sdk = _HistorySdk();
    serviceLocator.registerSingleton<MessageService>(sdk);
    deleted = [];
    repair = ArchiveImLocalPersistService.forTest(
        deleteLocalMessage: (message) async {
      deleted.add(message.msgID!);
      return 0;
    });
  });

  tearDown(() async {
    ArchiveHistoryProvider.registerHistoryClearedAtResolver(null);
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance.clearToken();
    await serviceLocator.unregister<MessageService>();
  });

  test('ordinary chat entry no longer schedules whole-history repair', () {
    final source = File('lib/src/chat.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _prepareOpenHistoryGate(');
    final end =
        source.indexOf('Future<void> _runOpenHistoryEnrichment(', start);
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final gate = source.substring(start, end);
    expect(gate, contains('ensureLocalSnapshotForOpen'));
    expect(gate, contains('_markChatOpenHistoryReady()'));
    expect(gate, isNot(contains('purgeSpuriousLocalImported')));
    expect(source, isNot(contains('ArchiveImLocalPersistService')));
  });

  test(
      'unchanged SDK page stops after one repeated cursor, keeps real messages',
      () async {
    sdk.read = (_) async => _page();
    expect(await run(), 0);
    expect(sdk.requests.length, 2);
    expect(sdk.requests.first.cursor, isNull);
    expect(sdk.requests.last.cursor, '144115268026882536-1784319908-99');
    expect(deleted, isEmpty);
  });

  test('finished full page ends repair without an extra read', () async {
    sdk.read = (_) async => _page(finished: true);
    expect(await run(), 0);
    expect(sdk.requests.length, 1);
    expect(deleted, isEmpty);
  });

  test('unusable tail ends repair without restarting from latest', () async {
    sdk.read = (_) async => _page()..messageList.last.msgID = '';
    expect(await run(), 0);
    expect(sdk.requests.length, 1);
  });

  test('advancing repair only deletes local imported fake IDs once', () async {
    sdk.read = (call) async {
      if (call == 1) {
        return _page()
          ..messageList[0] = _message('legacy-100-1', status: 5)
          ..messageList[1] =
              _message('144115268026882536-1784319908-1', status: 5);
      }
      return V2TimMessageListResult(isFinished: true, messageList: [
        _message('legacy-100-1', status: 5),
        _message('legacy-100-2', status: 5),
        _message('sent-100-3'),
      ]);
    };
    expect(await run(), 2);
    expect(sdk.requests.length, 2);
    expect(deleted, ['legacy-100-1', 'legacy-100-2']);
  });

  test('same account and canonical conversation share in-flight repair',
      () async {
    final response = Completer<V2TimMessageListResult>();
    sdk.read = (_) => response.future;
    final first = run();
    final second = run(id: 'group_@TGS#repair');
    expect(sdk.requests.length, 1);
    response.complete(_page(finished: true));
    expect(await first, 0);
    expect(await second, 0);
  });

  test('group and C2C with the same raw ID do not share a repair', () async {
    final response = Completer<V2TimMessageListResult>();
    sdk.read = (_) => response.future;
    final group = run(id: 'peer');
    final c2c = run(id: 'c2c_peer', isGroup: false);
    expect(sdk.requests.length, 2);
    expect(sdk.requests.map((r) => r.group), ['peer', null]);
    expect(sdk.requests.map((r) => r.user), [null, 'peer']);
    response.complete(_page(finished: true));
    await Future.wait([group, c2c]);
  });

  test('account switch discards late scan and new owner starts its own repair',
      () async {
    final oldResponse = Completer<V2TimMessageListResult>();
    sdk.read = (call) async => call == 1
        ? await oldResponse.future
        : V2TimMessageListResult(isFinished: true, messageList: [
            _message('newowner-100-1', status: 5),
          ]);
    final oldRepair = run();
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance.saveToken('next-token', userId: 'next-owner');
    expect(await run(), 1);
    oldResponse
        .complete(V2TimMessageListResult(isFinished: false, messageList: [
      _message('oldowner-100-1', status: 5),
    ]));
    expect(await oldRepair, 0);
    expect(sdk.requests.length, 2);
    expect(deleted, ['newowner-100-1']);
  });

  test('same-owner session generation change cancels remaining deletions',
      () async {
    final firstDelete = Completer<int>();
    repair =
        ArchiveImLocalPersistService.forTest(deleteLocalMessage: (message) {
      deleted.add(message.msgID!);
      return firstDelete.future;
    });
    sdk.read =
        (_) async => V2TimMessageListResult(isFinished: true, messageList: [
              _message('legacy-100-1', status: 5),
              _message('legacy-100-2', status: 5),
            ]);
    final pending = run();
    for (var i = 0; i < 10 && deleted.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(deleted, ['legacy-100-1']);
    SessionIdentityService.instance.invalidate();
    firstDelete.complete(0);
    await pending;
    expect(deleted, ['legacy-100-1']);
  });

  test('clear watermark blocks old history without scanning SDK storage',
      () async {
    ArchiveHistoryProvider.registerHistoryClearedAtResolver(
        (_) async => 100000);
    final visible =
        await ArchiveHistoryProvider.filterMessagesAfterHistoryClear(
      conversationID: '@TGS#repair',
      messages: [
        _message('old', timestamp: 99),
        _message('at-clear', timestamp: 100),
        _message('new', timestamp: 101),
      ],
    );
    expect(visible.map((m) => m.msgID), ['new']);
    expect(sdk.requests, isEmpty);
    expect(deleted, isEmpty);
  });
}
