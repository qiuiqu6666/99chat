import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/chat_page_ui_notifiers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TUIChatGlobalModel global;
  late ChatPageUiNotifiers page;

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    setupServiceLocator();
  });

  setUp(() {
    global = serviceLocator<TUIChatGlobalModel>();
    page = ChatPageUiNotifiers();
    global.setCurrentConversation(
      CurrentConversation('c2c_open_lock', ConvType.c2c),
      notify: false,
    );
  });

  tearDown(() {
    global.setChatListUserScrolling(false);
    global.detachOpenChatPageUi(
      historyPosition: page.historyPosition,
      userScrolling: page.userScrolling,
    );
    global.clearOpenChatBottomCapsuleLock('c2c_open_lock');
    page.dispose();
  });

  test('pin alone does not unlock while open hydrate is still in flight',
      () async {
    global.attachOpenChatPageUi(
      conversationId: 'c2c_open_lock',
      historyPosition: page.historyPosition,
      userScrolling: page.userScrolling,
    );
    final hydrate = Completer<bool>();
    unawaited(
      global.ensureOpenHydrate(
        'c2c_open_lock',
        requestSignature: 'open-lock-test',
        load: () => hydrate.future,
        canPublish: () => true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(global.isOpenChatBottomCapsuleLocked('c2c_open_lock'), isTrue);

    global.markOpenChatFirstPinSettled('c2c_open_lock');
    expect(global.isOpenChatBottomCapsuleLocked('c2c_open_lock'), isTrue);

    hydrate.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(global.isOpenChatBottomCapsuleLocked('c2c_open_lock'), isTrue);
  });

  test('lock expires after settle window once pin and hydrate are done',
      () async {
    global.beginOpenChatBottomCapsuleLock(
      'c2c_open_lock',
      lockMilliseconds: 800,
    );
    global.markOpenChatHydrateSettled('c2c_open_lock');
    global.markOpenChatFirstPinSettled('c2c_open_lock');
    expect(global.isOpenChatBottomCapsuleLocked('c2c_open_lock'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(global.isOpenChatBottomCapsuleLocked('c2c_open_lock'), isFalse);
  });

  test('user scrolling releases the first-open capsule lock', () {
    global.attachOpenChatPageUi(
      conversationId: 'c2c_open_lock',
      historyPosition: page.historyPosition,
      userScrolling: page.userScrolling,
    );
    expect(global.isOpenChatBottomCapsuleLocked('c2c_open_lock'), isTrue);
    global.setChatListUserScrolling(true);
    expect(global.isOpenChatBottomCapsuleLocked('c2c_open_lock'), isFalse);
  });

  test('timeout alone releases the lock without pin/hydrate marks', () async {
    global.beginOpenChatBottomCapsuleLock(
      'c2c_open_lock',
      lockMilliseconds: 40,
    );
    expect(global.isOpenChatBottomCapsuleLocked('c2c_open_lock'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(global.isOpenChatBottomCapsuleLocked('c2c_open_lock'), isFalse);
  });
}
