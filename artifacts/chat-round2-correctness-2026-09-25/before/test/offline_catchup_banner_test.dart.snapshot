import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/notification_settings_service.dart';

void main() {
  test('messages sent before coming online do not qualify as live banners', () {
    final onlineSince = DateTime.fromMillisecondsSinceEpoch(1800000000000);
    expect(
      NotificationSettingsService.isOfflineCatchupMessage(
        timestamp: 1700000000,
        onlineSince: onlineSince,
      ),
      isTrue,
    );
    expect(
      NotificationSettingsService.isOfflineCatchupMessage(
        timestamp: 1800000010,
        onlineSince: onlineSince,
      ),
      isFalse,
    );
  });

  test('home cannot lift banner suppression while offline sync is pending', () {
    final service = NotificationSettingsService.instance;
    service.beginColdStartBannerSuppression();
    service.endColdStartBannerSuppression();
    expect(service.debugAwaitingOfflineMessageSync, isTrue);
    service.markOfflineMessageSyncFinished(grace: Duration.zero);
    expect(service.debugAwaitingOfflineMessageSync, isFalse);
  });
}
