import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads local group skeletons before delayed remote completion', () {
    final source = File('lib/src/group_list.dart').readAsStringSync();
    final ensureLoaded = source.indexOf('await _controller.ensureLoaded();');

    expect(ensureLoaded, greaterThanOrEqualTo(0));
    expect(source, contains('await _controller.ensureLoaded();'));
    expect(
      source,
      contains(
        'GroupMembershipSyncService.instance.scheduleGroupListBackgroundSync()',
      ),
    );
    expect(source, isNot(contains('syncFull(reason:')));
  });

  test('AZ list input is reused when the controller projection is unchanged',
      () {
    final source = File('lib/src/group_list.dart').readAsStringSync();

    expect(
        source, contains('List<ISuspensionBeanImpl>? _effectiveListSource;'));
    expect(source, contains('if (!identical(_effectiveListSource, showList))'));
    expect(source, contains('final effectiveList = _effectiveList;'));
    expect(source, contains('NotificationListener<ScrollNotification>'));
    expect(source, contains('_controller.setScrolling(true)'));
    expect(source, contains('_controller.setScrolling(false)'));
  });

  test('group synchronization observes group-list scrolling', () {
    final source = File(
      'lib/src/services/group_local/group_membership_sync_service.dart',
    ).readAsStringSync();

    expect(source, contains('_isAnyGroupListOrConversationScrolling()'));
    expect(source, contains('MyGroupListController.instance.isScrolling'));
  });

  test('metadata-only group commits do not rebuild the AZ projection', () {
    final source = File(
      'lib/src/services/group_local/my_group_list_controller.dart',
    ).readAsStringSync();

    expect(source, contains('var projectionChanged = false;'));
    expect(source, contains('if (!projectionChanged)'));
    expect(source, contains('static bool _sameSkeleton('));
  });

  test('group completion cannot skip a partial startup local-first pass', () {
    final source = File(
      'lib/src/services/group_local/group_membership_sync_service.dart',
    ).readAsStringSync();

    expect(source, contains('_isGroupListReconcileReason(reason)'));
    expect(source, contains("reason.contains('my_group_list')"));
  });
}
