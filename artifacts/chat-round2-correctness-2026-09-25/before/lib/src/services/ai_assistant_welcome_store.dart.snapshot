import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

class AiAssistantWelcomeStore {
  AiAssistantWelcomeStore._();

  static const String _prefix = 'ai_assistant_welcome_dismissed_';
  static const String _guidePrefix = 'ai_assistant_guide_dismissed_';

  static String keyFor(String userId) {
    return '$_prefix${ChatIdFormat.rawUserUid(userId)}';
  }

  static String guideKeyFor(String userId) {
    return '$_guidePrefix${ChatIdFormat.rawUserUid(userId)}';
  }

  static Future<bool> isDismissed(String userId) async {
    final owner = ChatIdFormat.rawUserUid(userId);
    if (owner.isEmpty) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyFor(owner)) ?? false;
  }

  static Future<void> dismiss(String userId) async {
    final owner = ChatIdFormat.rawUserUid(userId);
    if (owner.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyFor(owner), true);
  }

  static Future<bool> isGuideDismissed(String userId) async {
    final owner = ChatIdFormat.rawUserUid(userId);
    if (owner.isEmpty) {
      return true;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(guideKeyFor(owner)) ?? false;
  }

  static Future<void> dismissGuide(String userId) async {
    final owner = ChatIdFormat.rawUserUid(userId);
    if (owner.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(guideKeyFor(owner), true);
  }
}
