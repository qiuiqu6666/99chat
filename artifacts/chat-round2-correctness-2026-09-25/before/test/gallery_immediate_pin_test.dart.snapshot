import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  test('explicit batch pin works without any list insertion notification', () {
    final model = serviceLocator<TUIChatGlobalModel>();
    final before = model.pinToBottomRequestSeq;
    model.requestPinToBottom('c2c_direct-batch', immediate: true);
    expect(model.pinToBottomRequestSeq, before + 1);
    expect(model.pinToBottomForce, isTrue);
    expect(model.pinToBottomImmediate, isTrue);
    model.requestPinToBottom('c2c_direct-batch', force: true);
    expect(model.pinToBottomImmediate, isFalse);
  });

  test('nested picker and alias coalescing retain immediate batch intent', () {
    final model = serviceLocator<TUIChatGlobalModel>();
    model.setCurrentConversation(CurrentConversation('batch-alias', ConvType.c2c),
        notify: false);
    addTearDown(model.clearCurrentConversation);
    final before = model.pinToBottomRequestSeq;
    model.beginMediaPickerOverlay();
    model.beginMediaPickerOverlay();
    model.requestPinToBottom('c2c_batch-alias', immediate: true);
    model.requestPinToBottom('batch-alias');
    model.endMediaPickerOverlay();
    expect(model.pinToBottomRequestSeq, before);
    model.endMediaPickerOverlay();
    expect(model.pinToBottomRequestSeq, before + 1);
    expect(model.pinToBottomRequestConvId, 'batch-alias');
    expect(model.pinToBottomImmediate, isTrue);
    expect(model.pinToBottomForce, isTrue);
  });

  test('switching chat drops picker intent instead of leaking into later pins',
      () {
    final model = serviceLocator<TUIChatGlobalModel>();
    model.setCurrentConversation(CurrentConversation('c2c_old-batch', ConvType.c2c),
        notify: false);
    addTearDown(model.clearCurrentConversation);
    final before = model.pinToBottomRequestSeq;
    model.beginMediaPickerOverlay();
    model.requestPinToBottom('c2c_old-batch', immediate: true);
    model.setCurrentConversation(CurrentConversation('c2c_new-batch', ConvType.c2c),
        notify: false);
    model.endMediaPickerOverlay();
    expect(model.pinToBottomRequestSeq, before);
    model.requestPinToBottom('c2c_old-batch', force: true);
    expect(model.pinToBottomImmediate, isFalse);
  });
}
