import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_refresh_bus.dart';

void main() {
  const groupId = '@TGS#NOTICE_SUPPRESS';

  tearDown(() {
    GroupNoticeRefreshBus.instance.clearPopupSuppress(groupId);
    GroupNoticeRefreshBus.instance.setSideProfilePanelOpen(false);
  });

  test('shouldSuppressPopup is true after suppress and false after clear', () {
    final bus = GroupNoticeRefreshBus.instance;
    expect(bus.shouldSuppressPopup(groupId), isFalse);
    bus.suppressPopupFor(groupId);
    expect(bus.shouldSuppressPopup(groupId), isTrue);
    expect(bus.shouldSuppressPopup('  $groupId  '), isTrue);
    expect(bus.shouldSuppressPopup('@TGS#OTHER'), isFalse);
    expect(bus.isSideProfilePanelOpen, isFalse);
    bus.clearPopupSuppress(groupId);
    expect(bus.shouldSuppressPopup(groupId), isFalse);
  });

  test('suppressPopupFor does not change isSideProfilePanelOpen', () {
    final bus = GroupNoticeRefreshBus.instance;
    bus.setSideProfilePanelOpen(true);
    bus.suppressPopupFor(groupId);
    expect(bus.isSideProfilePanelOpen, isTrue);
    bus.clearPopupSuppress(groupId);
    expect(bus.isSideProfilePanelOpen, isTrue);
    bus.setSideProfilePanelOpen(false);
  });
}
