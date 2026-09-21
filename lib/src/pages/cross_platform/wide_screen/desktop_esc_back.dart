import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_archive_host.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_contact_subpage_host.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_create_group_host.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_group_notice_host.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_profile_host.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/wide_popup.dart';

typedef DesktopEscHandler = bool Function();

/// 宽屏 / 桌面：Esc 关闭当前层并返回上一页。窄屏不处理。
class DesktopEscBack {
  DesktopEscBack._();

  static final List<DesktopEscHandler> _handlers = <DesktopEscHandler>[];

  static void register(DesktopEscHandler handler) {
    _handlers.remove(handler);
    _handlers.add(handler);
  }

  static void unregister(DesktopEscHandler handler) {
    _handlers.remove(handler);
  }

  static bool handle() {
    if (EasyLoading.isShow) {
      return false;
    }
    if (TUIKitWidePopup.entry != null) {
      TUIKitWidePopup.forceDismiss();
      return true;
    }
    if (_popInnermostNavigator()) {
      return true;
    }
    for (var i = _handlers.length - 1; i >= 0; i--) {
      if (_handlers[i]()) {
        return true;
      }
    }
    if (DesktopCreateGroupHost.isOpen) {
      DesktopCreateGroupHost.close();
      return true;
    }
    if (DesktopGroupNoticeHost.isOpen) {
      DesktopGroupNoticeHost.close();
      return true;
    }
    if (DesktopArchiveHost.isOpen) {
      DesktopArchiveHost.close();
      return true;
    }
    if (DesktopContactSubpageHost.isOpen) {
      DesktopContactSubpageHost.close();
      return true;
    }
    if (DesktopProfileHost.isOpen) {
      DesktopProfileHost.close();
      return true;
    }
    return false;
  }

  static bool _popInnermostNavigator() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final root = AppNavigator.key.currentState;
    final start = focusContext ?? root?.context;
    if (start == null) {
      return false;
    }
    NavigatorState? nav = Navigator.maybeOf(start);
    while (nav != null) {
      if (nav.canPop()) {
        unawaited(nav.maybePop());
        return true;
      }
      nav = nav.context.findAncestorStateOfType<NavigatorState>();
    }
    if (root != null && root.canPop()) {
      unawaited(root.maybePop());
      return true;
    }
    return false;
  }
}

class DesktopEscBackBinder extends StatefulWidget {
  const DesktopEscBackBinder({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopEscBackBinder> createState() => _DesktopEscBackBinderState();
}

class _DesktopEscBackBinderState extends State<DesktopEscBackBinder> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }
    if (event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed) {
      return false;
    }
    if (!mounted) {
      return false;
    }
    if (TUIKitScreenUtils.getFormFactor(context) != DeviceType.Desktop) {
      return false;
    }
    return DesktopEscBack.handle();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
