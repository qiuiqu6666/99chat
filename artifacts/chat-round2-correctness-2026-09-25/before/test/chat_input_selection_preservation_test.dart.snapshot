import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:extended_text_field/extended_text_field.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final longText = List.filled(30, '这是一段用于中间插入和选区替换的长文本。').join();
  late TUIChatSeparateViewModel model;
  late TIMUIKitInputTextFieldController input;
  late ValueNotifier<({String conversation, String? text})> draft;
  TextEditingController editor() => input.textEditingController!;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() {
    model = TUIChatSeparateViewModel()
      ..conversationID = 'c2c_selection'
      ..conversationType = ConvType.c2c
      ..chatConfig = const TIMUIKitChatConfig(isUseDraft: false);
    input = TIMUIKitInputTextFieldController();
    draft = ValueNotifier((conversation: model.conversationID, text: longText));
    final oldDevice = TUIKitScreenUtils.deviceType;
    TUIKitScreenUtils.deviceType = DeviceType.Mobile;
    addTearDown(() => TUIKitScreenUtils.deviceType = oldDevice);
  });
  tearDown(() {
    model.dispose();
    input.dispose();
    editor().dispose();
    draft.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    final onError = FlutterError.onError;
    try {
      await tester.pump();
    } finally {
      FlutterError.onError = onError;
    }
  }

  Future<void> mount(WidgetTester tester) async {
    final onError = FlutterError.onError;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<TUIChatGlobalModel>.value(
            value: serviceLocator<TUIChatGlobalModel>()),
        ChangeNotifierProvider<TUIChatSeparateViewModel>.value(value: model),
      ],
      child: MaterialApp(
          home: Scaffold(
        body: ValueListenableBuilder<({String conversation, String? text})>(
          valueListenable: draft,
          builder: (_, value, __) => TIMUIKitInputTextField(
            conversationID: value.conversation,
            currentConversation: V2TimConversation(
                conversationID: value.conversation,
                type: 1,
                userID: 'selection'),
            conversationType: ConvType.c2c,
            model: model,
            controller: input,
            initText: value.text,
            showSendAudio: false,
            showSendEmoji: false,
            showMorePanel: false,
          ),
        ),
      )),
    ));
    FlutterError.onError = onError;
    await tester.tap(find.byType(ExtendedTextField));
    await pump(tester);
  }

  for (final selected in [false, true]) {
    testWidgets(
        'draft echo preserves a middle ${selected ? 'selection' : 'caret'}',
        (tester) async {
      await mount(tester);
      final edited = longText.replaceRange(80, 80, '中间');
      final value = TextEditingValue(
        text: edited,
        selection: selected
            ? const TextSelection(baseOffset: 88, extentOffset: 82)
            : const TextSelection.collapsed(offset: 82),
      );
      tester.testTextInput.updateEditingValue(value);
      await pump(tester);
      // A later chat-page rebuild echoes the locally persisted text as initText.
      draft.value = (conversation: model.conversationID, text: edited);
      await pump(tester);
      expect(editor().value, value);
      final selection = editor().selection;
      final replacement =
          editor().text.replaceRange(selection.start, selection.end, '继续');
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: replacement,
        selection: TextSelection.collapsed(offset: selection.start + 2),
      ));
      await pump(tester);
      expect(
          editor().text,
          edited.replaceRange(
              value.selection.start, value.selection.end, '继续'));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final stale in [false, true]) {
    testWidgets(
        'draft echo preserves active Chinese composition (stale=$stale)',
        (tester) async {
      await mount(tester);
      final committed = longText.replaceRange(80, 80, '中');
      final composingText = committed.replaceRange(81, 81, 'ni');
      final value = TextEditingValue(
        text: composingText,
        selection: const TextSelection.collapsed(offset: 83),
        composing: const TextRange(start: 81, end: 83),
      );
      tester.testTextInput.updateEditingValue(value);
      await pump(tester);
      draft.value = (
        conversation: model.conversationID,
        text: stale ? committed : composingText
      );
      await pump(tester);
      expect(editor().value, value);
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: composingText.replaceRange(81, 83, '你'),
        selection: const TextSelection.collapsed(offset: 82),
      ));
      await pump(tester);
      expect(editor().text, committed.replaceRange(81, 81, '你'));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('a late draft cannot overwrite edits newer than its snapshot',
      (tester) async {
    await mount(tester);
    final older = longText.replaceRange(80, 80, '旧');
    final current = TextEditingValue(
      text: longText.replaceRange(80, 80, '新编辑'),
      selection: const TextSelection.collapsed(offset: 83),
    );
    tester.testTextInput.updateEditingValue(current);
    await pump(tester);
    draft.value = (conversation: model.conversationID, text: older);
    await pump(tester);
    expect(editor().value, current);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a loaded draft still populates an untouched editor',
      (tester) async {
    draft.value = (conversation: model.conversationID, text: null);
    await mount(tester);
    draft.value = (conversation: model.conversationID, text: longText);
    await pump(tester);
    expect(editor().text, longText);
    expect(editor().selection.baseOffset, longText.length);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an explicit replacement still replaces edited text',
      (tester) async {
    await mount(tester);
    editor().value = TextEditingValue(
        text: '$longText新编辑',
        selection: const TextSelection.collapsed(offset: 20));
    input.setTextField('主动替换', notifyChanged: false);
    await pump(tester);
    expect(editor().text, '主动替换');
    expect(editor().selection.baseOffset, 4);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('switching conversations applies the other draft',
      (tester) async {
    await mount(tester);
    editor().value = TextEditingValue(
        text: '$longText未完成',
        selection: const TextSelection.collapsed(offset: 20));
    draft.value = (conversation: 'c2c_another', text: '另一会话草稿');
    await pump(tester);
    expect(editor().text, '另一会话草稿');
    expect(editor().selection.baseOffset, '另一会话草稿'.length);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
