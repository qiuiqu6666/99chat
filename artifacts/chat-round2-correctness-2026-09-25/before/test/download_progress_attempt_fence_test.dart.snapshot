import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_download_progress.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';

class _Finder implements MessageService {
  Completer<List<V2TimMessage>?> result = Completer<List<V2TimMessage>?>();
  @override
  Future<List<V2TimMessage>?> findMessages(
          {required List<String> messageIDList}) =>
      result.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Model extends TUIChatGlobalModel {
  int queueAdvances = 0;
  @override
  Future<void> downloadFile() async {
    queueAdvances++;
  }
}

V2TimMessageDownloadProgress progress({int error = 0}) =>
    V2TimMessageDownloadProgress(
      isFinish: error == 0,
      isError: error != 0,
      msgID: 'download-fence',
      totalSize: 100,
      currentSize: 100,
      type: 0,
      isSnapshot: false,
      path: '/old-attempt',
      errorCode: error,
      errorDesc: '',
    );
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Finder finder;
  late MessageService previous;
  late _Model model;
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() {
    previous = serviceLocator<MessageService>();
    serviceLocator.unregister<MessageService>();
    finder = _Finder();
    serviceLocator.registerSingleton<MessageService>(finder);
    model = _Model();
    model.setMessageProgress('download-fence', 20);
  });
  tearDown(() {
    model.dispose();
    serviceLocator.unregister<MessageService>();
    serviceLocator.registerSingleton<MessageService>(previous);
  });
  for (final error in [0, 5]) {
    test('stale terminal after pending SDK lookup cannot alter retry ($error)',
        () async {
      var current = true;
      final work = model.applyAppMessageDownloadProgress(progress(error: error),
          isCurrent: () => current);
      await Future<void>.value();
      current = false;
      model.setMessageProgress('download-fence', 40);
      finder.result.complete(null);
      await work;
      expect(model.getMessageProgress('download-fence'), 40);
      expect(model.queueAdvances, 0);
      expect(model.getFileMessageLocation('download-fence'), isEmpty);
      await Future<void>.delayed(const Duration(seconds: 2));
    });
  }
  test('delayed media completion rechecks attempt before adopting old path',
      () async {
    var current = true;
    final work = model.applyAppMessageDownloadProgress(progress(),
        isCurrent: () => current);
    final image = V2TimMessage.fromJson(
        {'message_msg_id': 'download-fence', 'message_risk_type_identified': 0})
      ..elemType = 3;
    finder.result.complete([image]);
    await work;
    current = false;
    model.setMessageProgress('download-fence', 40);
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(model.getMessageProgress('download-fence'), 40);
    expect(model.queueAdvances, 0);
    expect(model.getFileMessageLocation('download-fence'), isEmpty);
  });
  test('current terminal with empty SDK lookup still advances download queue',
      () async {
    final work = model.applyAppMessageDownloadProgress(progress(),
        isCurrent: () => true);
    finder.result.complete([]);
    await work;
    expect(model.getMessageProgress('download-fence'), 100);
    expect(model.queueAdvances, 1);
    expect(model.getFileMessageLocation('download-fence'), '/old-attempt');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
}
