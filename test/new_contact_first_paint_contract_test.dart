import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new contact page shows loading state while requests are pending', () {
    final source = File('lib/src/newContact.dart').readAsStringSync();

    expect(source, contains('if (_loadingPendingRequests &&'));
    expect(
        source, contains('child: CircularProgressIndicator(strokeWidth: 2.5)'));
    expect(source, contains('_buildPageScaffold(context, showAppBar: true)'));
  });

  test('incoming and sent friend requests load concurrently', () {
    final source = File('lib/src/newContact.dart').readAsStringSync();
    final controller =
        File('lib/src/services/friend_request_list_controller.dart')
            .readAsStringSync();
    final loadStart =
        controller.indexOf('Future<void> _load({required bool reset}) async');
    final loadEnd = controller.indexOf('\n  @override', loadStart);

    expect(loadStart, greaterThanOrEqualTo(0));
    expect(loadEnd, greaterThan(loadStart));

    final loader = controller.substring(loadStart, loadEnd);
    expect(loader, contains('await Future.wait(List.generate(3'));
    expect(loader, contains('await loadIncoming(limit)'));
    expect(loader, contains('await loadSent(limit)'));
    expect(source, contains('await _requestList.refresh()'));
  });

  test('friend request actions use compact action and passive accepted state',
      () {
    final source = File('lib/src/newContact.dart').readAsStringSync();
    final verifyStart = source.indexOf('Widget _buildVerifyButton(');
    final statusStart = source.indexOf('Widget _buildStatusPill(', verifyStart);
    final selectionStart =
        source.indexOf('Widget _buildSelectionIndicator(', statusStart);

    expect(verifyStart, greaterThanOrEqualTo(0));
    expect(statusStart, greaterThan(verifyStart));
    expect(selectionStart, greaterThan(statusStart));

    final verify = source.substring(verifyStart, statusStart);
    expect(verify, contains('DirectoryActionButton('));

    final status = source.substring(statusStart, selectionStart);
    expect(status, contains('DirectoryStatusBadge('));
    expect(source, contains('DirectoryStatusKind.accepted'));
    expect(source, contains('DirectoryStatusKind.rejected'));
    expect(source, contains('DirectoryStatusKind.pending'));
  });
}
