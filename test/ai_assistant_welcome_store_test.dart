import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/ai_assistant_welcome_store.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('dismiss A does not hide welcome for B', () async {
    await AiAssistantWelcomeStore.dismiss('user-a');
    expect(await AiAssistantWelcomeStore.isDismissed('user-a'), isTrue);
    expect(await AiAssistantWelcomeStore.isDismissed('user-b'), isFalse);
  });

  test('empty userId does not persist', () async {
    await AiAssistantWelcomeStore.dismiss('');
    await AiAssistantWelcomeStore.dismiss('   ');
    expect(await AiAssistantWelcomeStore.isDismissed(''), isFalse);
    expect(await AiAssistantWelcomeStore.isDismissed('   '), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  test('whitespace userId shares rawUserUid key', () async {
    const padded = '  demo-user  ';
    const trimmed = 'demo-user';
    expect(ChatIdFormat.rawUserUid(padded), ChatIdFormat.rawUserUid(trimmed));
    await AiAssistantWelcomeStore.dismiss(padded);
    expect(await AiAssistantWelcomeStore.isDismissed(trimmed), isTrue);
  });

  test('guide dismiss A does not hide guide for B', () async {
    await AiAssistantWelcomeStore.dismissGuide('user-a');
    expect(await AiAssistantWelcomeStore.isGuideDismissed('user-a'), isTrue);
    expect(await AiAssistantWelcomeStore.isGuideDismissed('user-b'), isFalse);
  });

  test('empty userId does not persist guide', () async {
    await AiAssistantWelcomeStore.dismissGuide('');
    expect(await AiAssistantWelcomeStore.isGuideDismissed(''), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });
}
