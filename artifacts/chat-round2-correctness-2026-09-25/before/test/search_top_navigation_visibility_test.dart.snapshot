import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/search.dart';

void main() {
  test('conversation search hides its top navigation', () {
    expect(
      shouldShowSearchTopNavigation(
        isWideScreen: false,
        isConversation: true,
      ),
      isFalse,
    );
  });

  test('global narrow search keeps its top navigation', () {
    expect(
      shouldShowSearchTopNavigation(
        isWideScreen: false,
        isConversation: false,
      ),
      isTrue,
    );
  });

  test('wide search does not add route-level top navigation', () {
    expect(
      shouldShowSearchTopNavigation(
        isWideScreen: true,
        isConversation: false,
      ),
      isFalse,
    );
  });
}
