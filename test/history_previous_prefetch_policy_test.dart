import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/chat_list_pagination_ui_gate.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_previous_prefetch_policy.dart';

void main() {
  group('HistoryPreviousPrefetchPolicy', () {
    test('does not trigger when content cannot scroll', () {
      expect(
        HistoryPreviousPrefetchPolicy.isInPreviousPrefetchBand(
          pixels: 0,
          maxScrollExtent: 0,
          prefetchPx: 400,
          hasPixels: true,
          hasContentDimensions: true,
        ),
        isFalse,
      );
    });

    test('does not trigger when remaining is greater than prefetch', () {
      expect(
        HistoryPreviousPrefetchPolicy.isInPreviousPrefetchBand(
          pixels: 100,
          maxScrollExtent: 1000,
          prefetchPx: 400,
          hasPixels: true,
          hasContentDimensions: true,
        ),
        isFalse,
      );
    });

    test('triggers when remaining equals prefetch', () {
      expect(
        HistoryPreviousPrefetchPolicy.isInPreviousPrefetchBand(
          pixels: 600,
          maxScrollExtent: 1000,
          prefetchPx: 400,
          hasPixels: true,
          hasContentDimensions: true,
        ),
        isTrue,
      );
    });

    test('triggers when remaining is less than prefetch', () {
      expect(
        HistoryPreviousPrefetchPolicy.isInPreviousPrefetchBand(
          pixels: 900,
          maxScrollExtent: 1000,
          prefetchPx: 400,
          hasPixels: true,
          hasContentDimensions: true,
        ),
        isTrue,
      );
    });

    test('prefetch distance floors at top-near 160 when cacheExtent is 120', () {
      expect(
        HistoryPreviousPrefetchPolicy.prefetchDistancePx(120),
        ChatListPaginationUiGate.loadPreviousTopNearPx,
      );
    });

    test('prefetch distance uses cacheExtent 400', () {
      expect(HistoryPreviousPrefetchPolicy.prefetchDistancePx(400), 400);
    });

    test('remaining 300 does not show spinner', () {
      expect(
        HistoryPreviousPrefetchPolicy.shouldShowPreviousLoadSpinner(
          pixels: 700,
          maxScrollExtent: 1000,
          hasPixels: true,
          hasContentDimensions: true,
        ),
        isFalse,
      );
    });

    test('remaining 100 shows spinner', () {
      expect(
        HistoryPreviousPrefetchPolicy.shouldShowPreviousLoadSpinner(
          pixels: 900,
          maxScrollExtent: 1000,
          hasPixels: true,
          hasContentDimensions: true,
        ),
        isTrue,
      );
    });

    test('missing pixels or dimensions never trigger', () {
      expect(
        HistoryPreviousPrefetchPolicy.isInPreviousPrefetchBand(
          pixels: 900,
          maxScrollExtent: 1000,
          prefetchPx: 400,
          hasPixels: false,
          hasContentDimensions: true,
        ),
        isFalse,
      );
      expect(
        HistoryPreviousPrefetchPolicy.shouldShowPreviousLoadSpinner(
          pixels: 900,
          maxScrollExtent: 1000,
          hasPixels: true,
          hasContentDimensions: false,
        ),
        isFalse,
      );
    });
  });
}
