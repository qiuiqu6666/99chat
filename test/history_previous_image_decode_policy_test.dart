import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_previous_image_decode_policy.dart';

void main() {
  group('HistoryPreviousImageDecodePolicy', () {
    test('queues offscreen rows while deferring, including local files', () {
      expect(
        HistoryPreviousImageDecodePolicy.shouldQueueHistoryImageDecode(
          isVisible: false,
          deferHeavyPresentation: true,
          previousPageBurstActive: false,
        ),
        isTrue,
      );
    });

    test('does not queue visible rows while scrolling outside a page burst', () {
      expect(
        HistoryPreviousImageDecodePolicy.shouldQueueHistoryImageDecode(
          isVisible: true,
          deferHeavyPresentation: true,
          previousPageBurstActive: false,
        ),
        isFalse,
      );
    });

    test('queues visible rows during previous-page burst', () {
      expect(
        HistoryPreviousImageDecodePolicy.shouldQueueHistoryImageDecode(
          isVisible: true,
          deferHeavyPresentation: true,
          previousPageBurstActive: true,
        ),
        isTrue,
      );
    });

    test('does not queue idle offscreen rows without defer', () {
      expect(
        HistoryPreviousImageDecodePolicy.shouldQueueHistoryImageDecode(
          isVisible: false,
          deferHeavyPresentation: false,
          previousPageBurstActive: false,
        ),
        isFalse,
      );
    });
  });
}
