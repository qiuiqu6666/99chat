import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_chat_notification_clear_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_chat_notification_registry.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final service = ImChatNotificationClearService.instance;
  final registry = ImChatNotificationRegistry.instance;

  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    registry.clearAll();
    registry.register(
      threadId: 'c2c_unread',
      notificationId: 41,
      msgKey: 'unread-41',
    );
  });

  tearDown(() {
    registry.clearAll();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    test('background sync preserves unread notifications while $state',
        () async {
      binding.handleAppLifecycleStateChanged(state);

      await service.clearAllImChatNotifications(reason: 'offline_sync_ready');

      expect(registry.allImChatIds(), {41});
    });
  }

  test('foreground cleanup still clears existing notifications', () async {
    await service.clearAllImChatNotifications(reason: 'lifecycle_resumed');

    expect(registry.allImChatIds(), isEmpty);
  });

  test('backgrounding during an asynchronous cleanup stops the clear',
      () async {
    final clearing =
        service.clearAllImChatNotifications(reason: 'offline_sync_ready');
    // The first per-notification cancellation has yielded before bulk removal.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await clearing;

    expect(registry.allImChatIds(), {41});
  });

  test('skipped background cleanup can run after returning to foreground',
      () async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await service.clearAllImChatNotifications(reason: 'offline_sync_ready');
    expect(registry.allImChatIds(), {41});

    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await service.clearAllImChatNotifications(reason: 'lifecycle_resumed');
    expect(registry.allImChatIds(), isEmpty);
  });
}
