import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String readNormalized(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('desktop new friends and group notice replace contacts column', () {
    final contact = readNormalized('lib/src/contact.dart');
    final newContactAt = contact.indexOf('case "newContact":');
    final groupListAt = contact.indexOf('case "groupList":');
    expect(newContactAt, greaterThanOrEqualTo(0));
    expect(groupListAt, greaterThan(newContactAt));
    final newContact = contact.substring(newContactAt, groupListAt);
    expect(newContact, contains('DesktopContactSubpageHost.open'));
    expect(newContact, contains('DesktopContactSubpage.newFriends'));
    expect(newContact, isNot(contains('TUIKitWidePopup.showPopupWindow')));

    final groupNoticeAt = contact.indexOf('case "groupNotice":');
    expect(groupNoticeAt, greaterThan(groupListAt));
    final groupNoticeEnd = contact.indexOf('default:', groupNoticeAt);
    expect(groupNoticeEnd, greaterThan(groupNoticeAt));
    final groupNotice = contact.substring(groupNoticeAt, groupNoticeEnd);
    expect(groupNotice, contains('DesktopContactSubpageHost.open'));
    expect(groupNotice, contains('DesktopContactSubpage.groupNotice'));
    expect(groupNotice, isNot(contains('DesktopGroupNoticeHost.open')));

    final home = readNormalized(
      'lib/src/pages/cross_platform/wide_screen/home_page.dart',
    );
    final navAt = home.indexOf('void onNavChange(int index)');
    expect(navAt, greaterThanOrEqualTo(0));
    final navEnd = home.indexOf('setState(() {', navAt);
    expect(navEnd, greaterThan(navAt));
    final nav = home.substring(navAt, navEnd);
    expect(nav, contains('if (index == 2)'));
    expect(nav, contains('DesktopContactSubpageHost.close()'));

    final navigateAt = home.indexOf('_navigateToChat(V2TimConversation conversation');
    expect(navigateAt, greaterThanOrEqualTo(0));
    final navigateEnd = home.indexOf('Future<void> getLoginUserInfo()', navigateAt);
    expect(navigateEnd, greaterThan(navigateAt));
    expect(
      home.substring(navigateAt, navigateEnd),
      isNot(contains('DesktopContactSubpageHost.close')),
    );

    final contacts = readNormalized(
      'lib/src/pages/cross_platform/wide_screen/contact_and_profile.dart',
    );
    expect(contacts, contains('columnEmbedded: true'));
    expect(contacts, contains('contactsColumnEmbedded: true'));
    expect(contacts, contains('idleDetail:'));
    expect(contacts, contains('onOpenConversation:'));

    final newContactSource = readNormalized('lib/src/newContact.dart');
    expect(newContactSource, contains('final bool columnEmbedded;'));
    expect(newContactSource, contains('widget.onSelectRecord'));
    expect(
      newContactSource,
      contains('final ValueChanged<V2TimConversation>? onOpenConversation;'),
    );
    final openFriendAt = newContactSource.indexOf('Future<void> _openFriendChat(');
    expect(openFriendAt, greaterThanOrEqualTo(0));
    final openFriendEnd =
        newContactSource.indexOf('Future<void> _openAuditPage(', openFriendAt);
    expect(openFriendEnd, greaterThan(openFriendAt));
    final openFriend = newContactSource.substring(openFriendAt, openFriendEnd);
    expect(openFriend, contains('widget.onOpenConversation'));
    expect(
      openFriend.indexOf('widget.onOpenConversation'),
      lessThan(openFriend.indexOf('openOrReuseAppChat')),
    );

    final audit = readNormalized('lib/src/friend_request_audit_page.dart');
    expect(audit, contains('final bool embedded;'));
    final completeAt = audit.indexOf('void _completeAfterAudit()');
    expect(completeAt, greaterThanOrEqualTo(0));
    final completeEnd = audit.indexOf('Future<void> _handleAccept()', completeAt);
    expect(completeEnd, greaterThan(completeAt));
    final complete = audit.substring(completeAt, completeEnd);
    expect(complete, contains('if (widget.embedded)'));
    final embeddedAt = complete.indexOf('if (widget.embedded)');
    final embeddedReturn = complete.indexOf('return;', embeddedAt);
    expect(embeddedReturn, greaterThan(embeddedAt));
    final embeddedPath = complete.substring(embeddedAt, embeddedReturn);
    expect(embeddedPath, isNot(contains('Navigator.of(context).pop')));

    final groupList = readNormalized('lib/src/all_group_application_list.dart');
    expect(
      groupList,
      isNot(contains('if (widget.shellEmbedded || widget.contactsColumnEmbedded)')),
    );
    expect(groupList, contains('if (widget.shellEmbedded)'));
    expect(groupList, contains('if (widget.contactsColumnEmbedded)'));

    final dualAt = groupList.indexOf('Widget _buildDesktopDualPane(');
    expect(dualAt, greaterThanOrEqualTo(0));
    final dualEnd = groupList.indexOf('Widget build(BuildContext context)', dualAt);
    expect(dualEnd, greaterThan(dualAt));
    final dual = groupList.substring(dualAt, dualEnd);
    expect(dual, contains('? 300'));
    expect(dual, contains('if (widget.contactsColumnEmbedded)'));
    expect(dual, contains('_buildEmbeddedTitleBar('));

    final titleBarAt = groupList.indexOf('Widget _buildEmbeddedTitleBar(');
    expect(titleBarAt, greaterThanOrEqualTo(0));
    expect(titleBarAt, lessThan(dualAt));
    expect(
      groupList.substring(titleBarAt, dualAt),
      contains('height: 52'),
    );

    final openGroupAt = groupList.indexOf('Future<void> _openGroupChat(');
    expect(openGroupAt, greaterThanOrEqualTo(0));
    final openGroupEnd =
        groupList.indexOf('Future<void> _openApplicationDetail(', openGroupAt);
    expect(openGroupEnd, greaterThan(openGroupAt));
    final openGroup = groupList.substring(openGroupAt, openGroupEnd);
    expect(openGroup, contains('if (!widget.contactsColumnEmbedded)'));
    final skipCloseAt = openGroup.indexOf('if (!widget.contactsColumnEmbedded)');
    final callbackAt = openGroup.indexOf('widget.onOpenConversation!(conversation)');
    expect(callbackAt, greaterThan(skipCloseAt));
    expect(
      openGroup.substring(skipCloseAt, callbackAt),
      contains('widget.onClose?.call()'),
    );
  });
}
