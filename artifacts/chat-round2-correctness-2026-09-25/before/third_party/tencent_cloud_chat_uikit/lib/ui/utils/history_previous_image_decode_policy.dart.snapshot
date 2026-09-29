/// Whether a history image bubble should wait in the per-frame decode queue.
class HistoryPreviousImageDecodePolicy {
  HistoryPreviousImageDecodePolicy._();

  static bool shouldQueueHistoryImageDecode({
    required bool isVisible,
    required bool deferHeavyPresentation,
    required bool previousPageBurstActive,
  }) {
    if (!deferHeavyPresentation && !previousPageBurstActive) {
      return false;
    }
    if (!isVisible) {
      return true;
    }
    return previousPageBurstActive;
  }
}
