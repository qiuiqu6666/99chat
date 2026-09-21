import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';

void main() {
  test('progress stays off once any result is visible', () {
    expect(
      showGlobalSearchLinearProgress(
        hasKeyword: true,
        hasResults: true,
        friendSearchLoading: true,
        groupSearchLoading: true,
        messageLocalLoading: true,
      ),
      isFalse,
    );
  });

  test('progress is on only while fast lanes search and nothing is visible', () {
    expect(
      showGlobalSearchLinearProgress(
        hasKeyword: true,
        hasResults: false,
        friendSearchLoading: false,
        groupSearchLoading: false,
        messageLocalLoading: true,
      ),
      isTrue,
    );
    expect(
      showGlobalSearchLinearProgress(
        hasKeyword: true,
        hasResults: false,
        friendSearchLoading: false,
        groupSearchLoading: false,
        messageLocalLoading: false,
      ),
      isFalse,
    );
  });

  test('empty waits for completed key even if fast lanes already finished', () {
    expect(
      showGlobalSearchEmpty(
        hasKeyword: true,
        keyword: '张三',
        completedGlobalSearchKey: '',
        hasResults: false,
      ),
      isFalse,
    );
    expect(
      showGlobalSearchEmpty(
        hasKeyword: true,
        keyword: '张三',
        completedGlobalSearchKey: '张三',
        hasResults: false,
      ),
      isTrue,
    );
  });

  test('empty is hidden when any section has results', () {
    expect(
      showGlobalSearchEmpty(
        hasKeyword: true,
        keyword: '张三',
        completedGlobalSearchKey: '张三',
        hasResults: true,
      ),
      isFalse,
    );
  });
}
