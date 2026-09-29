import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  testWidgets(
      'inactive commits update their cache without evaluating active selectors',
      (tester) async {
    final handler = FlutterError.onError;
    Future<void> pump([Duration? duration]) async {
      await tester.pump(duration);
      FlutterError.onError = handler;
    }

    final model = TUIChatGlobalModel();
    model.configureMessageWriterScope(
        ownerUserID: 'reader', accountGeneration: 1, domainGeneration: 1);
    model.setCurrentConversation(
        CurrentConversation('c2c_reader', ConvType.c2c),
        notify: false);
    await pump();
    var notifications = 0;
    model.addListener(() => notifications++);
    V2TimMessage message(String id) => V2TimMessage.fromJson({
          'message_risk_type_identified': 0,
          'message_msg_id': id,
          'message_server_time': 10,
        })
          ..elemType = 1;
    for (var i = 0; i < 30; i++) {
      model.setMessageList('c2c_other', [message('other_$i')], replace: true);
    }
    await pump();
    expect(model.rawMessageList('c2c_other')!.first.msgID, 'other_29');
    expect(model.messageListRevisionFor('c2c_other'), greaterThan(0));
    expect(notifications, 0);
    for (var i = 0; i < 8; i++) {
      await model.applyAppRealtimeMessage(message('group_$i')
        ..groupID = '@TGS#background'
        ..isSelf = false);
    }
    await pump(const Duration(milliseconds: 500));
    expect(model.rawMessageCount('@TGS#background'), 0);
    // A retained cache still receives new content without notifying the active
    // page. Only an entirely unopened conversation skips message projection.
    model.setMessageList('@TGS#background', [message('cached')], replace: true);
    await model.applyAppRealtimeMessage(message('cached_new')
      ..groupID = '@TGS#background'
      ..isSelf = false);
    await pump(const Duration(milliseconds: 500));
    expect(model.rawMessageCount('@TGS#background'), 2);
    expect(notifications, 0);
    model.setC2cMessageEditStatus('other', 0);
    model.markMessageChangedByMessage('c2c_other', message('other_29'));
    await pump();
    expect(notifications, 0);
    model.setMessageList('c2c_reader', [message('active')], replace: true);
    await pump();
    expect(notifications, 1);
    model
        .setCurrentConversation(CurrentConversation('c2c_other', ConvType.c2c));
    expect(model.rawMessageList('c2c_other')!.first.msgID, 'other_29');
    await pump();
    model.clearData();
    await pump(const Duration(seconds: 2));
    model.dispose();
  });
}
