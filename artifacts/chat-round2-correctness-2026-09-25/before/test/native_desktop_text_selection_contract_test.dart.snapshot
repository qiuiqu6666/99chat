import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/native_desktop_text_selection.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';

void main() {
  test('isNativeDesktop matches isDesktop and is not web', () {
    expect(PlatformUtils().isNativeDesktop, PlatformUtils().isDesktop);
    expect(PlatformUtils().isNativeDesktop, isTrue);
    expect(PlatformUtils().isWeb, isFalse);
  });

  testWidgets('isWideLayout is width >= 900', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(899, 600)),
        child: Builder(
          builder: (context) {
            expect(TUIKitScreenUtils.isWideLayout(context), isFalse);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(900, 600)),
        child: Builder(
          builder: (context) {
            expect(TUIKitScreenUtils.isWideLayout(context), isTrue);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });

  testWidgets('empty selection opens the message menu on secondary tap',
      (tester) async {
    var menuCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _NativeDesktopMenuHarness(
            onMessageMenu: () => menuCalls++,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('bubble')),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    expect(menuCalls, 1);
  });

  testWidgets('non-empty selection suppresses the message menu', (tester) async {
    var menuCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _NativeDesktopMenuHarness(
            onMessageMenu: () => menuCalls++,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('mark-selected')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('bubble')),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    expect(menuCalls, 0);
  });

  test('TelegramMessageLongPressDetector is unchanged and still the mobile path',
      () {
    final detector = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKItMessageList/tim_uikit_telegram_message_context_controller.dart',
    ).readAsStringSync();
    expect(detector.contains('class TelegramMessageLongPressDetector'), isTrue);
    expect(
      detector.contains('LongPressGestureRecognizer'),
      isTrue,
    );

    final listItem = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKItMessageList/tim_uikit_chat_history_message_list_item.dart',
    ).readAsStringSync();
    final wrapAt = listItem.indexOf('Widget wrapBubblePressHandlers');
    expect(wrapAt, greaterThanOrEqualTo(0));
    final wrap = listItem.substring(wrapAt, wrapAt + 2800);
    expect(wrap.contains('if (PlatformUtils().isNativeDesktop)'), isTrue);
    expect(wrap.contains('return TelegramMessageLongPressDetector('), isTrue);
    final nativeAt = wrap.indexOf('if (PlatformUtils().isNativeDesktop)');
    final desktopAt = wrap.indexOf('if (isDesktopScreen)');
    expect(nativeAt, greaterThanOrEqualTo(0));
    expect(desktopAt, greaterThan(nativeAt));
  });
}

class _NativeDesktopMenuHarness extends StatefulWidget {
  const _NativeDesktopMenuHarness({required this.onMessageMenu});

  final VoidCallback onMessageMenu;

  @override
  State<_NativeDesktopMenuHarness> createState() =>
      _NativeDesktopMenuHarnessState();
}

class _NativeDesktopMenuHarnessState extends State<_NativeDesktopMenuHarness> {
  bool _hasSelection = false;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<NativeDesktopTextSelectionNotification>(
      onNotification: (notification) {
        _hasSelection = notification.hasNonEmptySelection;
        return true;
      },
      child: Builder(
        builder: (innerContext) {
          return Column(
            children: [
              TextButton(
                key: const ValueKey<String>('mark-selected'),
                onPressed: () {
                  NativeDesktopTextSelectionNotification(
                    hasNonEmptySelection: true,
                  ).dispatch(innerContext);
                },
                child: const Text('select'),
              ),
              GestureDetector(
                key: const ValueKey<String>('bubble'),
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: (_) {
                  if (_hasSelection) {
                    return;
                  }
                  widget.onMessageMenu();
                },
                child: const SizedBox(width: 180, height: 80),
              ),
            ],
          );
        },
      ),
    );
  }
}
