import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_i18n_tool/language_json/strings.g.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_mention_nav.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('userOrGroupNotFoundMessage simplified Chinese copy', () {
    final previous = LocaleSettings.currentLocale;
    LocaleSettings.setLocale(AppLocale.zhHans);
    addTearDown(() => LocaleSettings.setLocale(previous));

    expect(
      ChatIdMentionNavigator.userOrGroupNotFoundMessage(AppI18n.current),
      '该用户或群聊不存在',
    );
  });
}
