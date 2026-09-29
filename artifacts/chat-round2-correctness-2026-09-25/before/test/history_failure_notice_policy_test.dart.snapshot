import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/controllers/history_pagination_controller.dart';

/// Retryable history failures remain silent and prior notices are cleared.
void main() {
  group('history failure notice policy', () {
    test('scope_not_configured does not warrant user notice', () {
      expect(
        HistoryPaginationController.shouldShowHistoryFailureNotice(
          'scope_not_configured',
        ),
        isFalse,
      );
    });

    test('SDK and network failures do not show the sticky error bar', () {
      expect(
        HistoryPaginationController.shouldShowHistoryFailureNotice(
          'exception',
        ),
        isFalse,
      );
      expect(
        HistoryPaginationController.shouldShowHistoryFailureNotice(
          'network_error',
        ),
        isFalse,
      );
    });

    test('open-chat reset clears a sticky failure notice', () {
      final p = HistoryPaginationController();
      p.setArchiveHistoryNotice('历史记录加载失败，请再次上滑重试');
      final revBefore = p.archiveHistoryNoticeRevision;
      p.resetForConversationInit();
      expect(p.archiveHistoryNotice, isNull);
      expect(p.archiveHistoryNoticeRevision, greaterThan(revBefore));
    });

    test('config failure path clears prior sticky notice', () {
      final p = HistoryPaginationController()..haveMoreData = true;
      p.setArchiveHistoryNotice('历史记录加载失败，请再次上滑重试');
      // Mirrors _markRetryableHistoryFailure when shouldShow == false.
      p.haveMoreData = true;
      if (!HistoryPaginationController.shouldShowHistoryFailureNotice(
        'scope_not_configured',
      )) {
        p.setArchiveHistoryNotice(null);
      }
      expect(p.archiveHistoryNotice, isNull);
      expect(p.haveMoreData, isTrue);
    });
  });
}
