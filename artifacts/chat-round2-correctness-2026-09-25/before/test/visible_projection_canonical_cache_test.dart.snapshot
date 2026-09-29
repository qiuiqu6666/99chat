import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';

void main() {
  test('history storage key collapses bare and prefixed conversation ids', () {
    expect(
      TUIChatGlobalModel.canonicalHistoryStorageKey('acnj6oxey9'),
      'c2c_acnj6oxey9',
    );
    expect(
      TUIChatGlobalModel.canonicalHistoryStorageKey('c2c_acnj6oxey9'),
      'c2c_acnj6oxey9',
    );
    expect(
      TUIChatGlobalModel.canonicalHistoryStorageKey(
          'group_@TGS#_mc2SX4NMM62CZ'),
      '@TGS#_mc2SX4NMM62CZ',
    );
    expect(
      TUIChatGlobalModel.canonicalHistoryStorageKey('@TGS#_mc2SX4NMM62CZ'),
      '@TGS#_mc2SX4NMM62CZ',
    );
  });
}
