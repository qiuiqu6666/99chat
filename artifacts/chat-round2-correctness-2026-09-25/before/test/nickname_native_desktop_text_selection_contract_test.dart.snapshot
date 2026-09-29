import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sideCard;
  late String messageHeader;
  late String rowDetector;
  late String memberCard;
  late String listItem;

  setUpAll(() {
    final settings = File('lib/src/pages/c2c_chat_settings_page.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final sideAt = settings.indexOf('Widget _buildTelegramSideCard(');
    final buildAt = settings.indexOf('Widget build(BuildContext context)', sideAt);
    expect(sideAt, greaterThanOrEqualTo(0));
    expect(buildAt, greaterThan(sideAt));
    sideCard = settings.substring(sideAt, buildAt);

    final memberAt = settings.indexOf('Widget _memberCard(');
    expect(memberAt, greaterThanOrEqualTo(0));
    expect(memberAt, lessThan(sideAt));
    memberCard = settings.substring(memberAt, sideAt);

    listItem = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKItMessageList/tim_uikit_chat_history_message_list_item.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final headerAt = listItem.indexOf('Widget _messageHeader(');
    final nextAt =
        listItem.indexOf('int _estimateMobileTooltipItemCount(', headerAt);
    expect(headerAt, greaterThanOrEqualTo(0));
    expect(nextAt, greaterThan(headerAt));
    messageHeader = listItem.substring(headerAt, nextAt);

    final detectorAt =
        listItem.indexOf('behavior: rowUiState.isMultiSelect');
    expect(detectorAt, greaterThanOrEqualTo(0));
    rowDetector = listItem.substring(detectorAt, detectorAt + 700);
  });

  test('side-card display name is wrapped for native desktop selection', () {
    expect(
      sideCard.contains('NativeDesktopSelectableMessageText('),
      isTrue,
    );
    expect(
      sideCard.contains('child: Text(\n                          name,'),
      isTrue,
    );
    expect(sideCard.contains('if (PlatformUtils().isNativeDesktop)'), isTrue);
    expect(sideCard.contains('ScrollConfiguration'), isTrue);
    expect(sideCard.contains('PointerDeviceKind.mouse'), isTrue);
  });

  test('_memberCard still opens profile via InkWell and is not this change', () {
    expect(memberCard.contains('onTap: _openPeerProfile'), isTrue);
    expect(
      memberCard.contains('NativeDesktopSelectableMessageText('),
      isFalse,
    );
  });

  test('_messageHeader wraps sender name for native desktop selection', () {
    expect(
      messageHeader.contains('NativeDesktopSelectableMessageText('),
      isTrue,
    );
    expect(
      messageHeader.contains('child: Text(\n                    name,'),
      isTrue,
    );
    expect(messageHeader.contains('maxLines: 1'), isTrue);
  });

  test('row onTap is null on native desktop when not multi-select', () {
    expect(
      rowDetector.contains(
        'onTap: PlatformUtils().isNativeDesktop &&\n'
        '                        !rowUiState.isMultiSelect\n'
        '                    ? null',
      ),
      isTrue,
    );
    expect(rowDetector.contains('setMessageItemChecked'), isTrue);
  });

  test('TelegramMessageLongPressDetector remains the mobile bubble path', () {
    final wrapAt = listItem.indexOf('Widget wrapBubblePressHandlers');
    expect(wrapAt, greaterThanOrEqualTo(0));
    final wrap = listItem.substring(wrapAt, wrapAt + 2800);
    expect(wrap.contains('return TelegramMessageLongPressDetector('), isTrue);
  });
}
