import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';

void main() {
  test('takeSearchHomePreview keeps the first 5 items', () {
    expect(takeSearchHomePreview([1, 2, 3, 4, 5, 6, 7]), [1, 2, 3, 4, 5]);
  });

  test('takeSearchHomePreview returns the original list when short', () {
    final items = [1, 2, 3];
    expect(takeSearchHomePreview(items), same(items));
  });

  test('takeSearchHomePreview returns empty for empty input', () {
    expect(takeSearchHomePreview(<int>[]), isEmpty);
  });

  test('takeSearchHomePreview honors a custom limit', () {
    expect(takeSearchHomePreview([1, 2, 3], limit: 2), [1, 2]);
  });

  test('takeSearchHomePreview keeps the original list when limit is not positive',
      () {
    final items = [1, 2, 3];
    expect(takeSearchHomePreview(items, limit: 0), same(items));
  });
}
