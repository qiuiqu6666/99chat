import 'package:characters/characters.dart';

class AiAssistantStream {
  AiAssistantStream._();

  static String take(String full, int count) {
    if (count <= 0) {
      return '';
    }
    final characters = full.characters;
    if (count >= characters.length) {
      return full;
    }
    return characters.take(count).toString();
  }
}
