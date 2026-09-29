import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/api/device_api.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/services/desktop_login_session_service.dart';
import 'package:tencent_cloud_chat_demo/src/utils/desktop_login_platform.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/desktop_logged_in_layout.dart';
import 'package:tencent_cloud_chat_demo/utils/dio_error_message.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';

/// 电脑 / 网页端已登录页（在线会话 + 退出桌面端）。
class DesktopLoginSessionsPage extends StatefulWidget {
  const DesktopLoginSessionsPage({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      AppMaterialPageRoute(
        builder: (_) => const DesktopLoginSessionsPage(),
      ),
    );
  }

  @override
  State<DesktopLoginSessionsPage> createState() =>
      _DesktopLoginSessionsPageState();
}

class _DesktopLoginSessionsPageState extends State<DesktopLoginSessionsPage> {
  bool _loading = true;
  bool _busy = false;

  DesktopLoginSessionService get _service =>
      DesktopLoginSessionService.instance;

  @override
  void initState() {
    super.initState();
    _reload(initial: true);
  }

  Future<void> _reload({bool initial = false}) async {
    if (initial) {
      setState(() => _loading = true);
    }
    await _service.refresh(reason: 'detail_page', force: true);
    if (!mounted) {
      return;
    }
    setState(() => _loading = false);
    if (_service.devices.value.isEmpty) {
      Navigator.of(context).pop();
    }
  }

  String _headline(AppI18n i18n, List<UserDevice> devices) {
    if (devices.isEmpty) {
      return i18n.t(
        zhHans: '已登录',
        zhHant: '已登入',
        en: 'Signed in',
        ja: 'ログイン済み',
        ko: '로그인됨',
      );
    }
    final title = _deviceTitle(devices.first);
    return i18n.format(
      zhHans: '{title}已登录',
      zhHant: '{title}已登入',
      en: '{title} signed in',
      ja: '{title}はログイン済み',
      ko: '{title} 로그인됨',
      vars: {'title': title},
    );
  }

  String _deviceTitle(UserDevice device) {
    final model = device.model?.trim() ?? '';
    if (model.isNotEmpty) {
      return model;
    }
    return desktopPlatformDisplayName(device.platform);
  }

  Future<void> _signOutDesktop() async {
    if (_busy) {
      return;
    }
    final i18n = AppI18n.of(context);
    final devices = List.of(_service.devices.value);
    if (devices.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = true);
    try {
      for (final device in devices) {
        await DeviceApi.instance.kickDevice(device.deviceId);
      }
      await _service.refresh(reason: 'signed_out', force: true);
      if (!mounted) {
        return;
      }
      ToastUtils.toast(
        i18n.t(
          zhHans: '已退出该设备',
          zhHant: '已退出該裝置',
          en: 'Device signed out',
          ja: '端末をログアウトしました',
          ko: '기기가 로그아웃되었습니다',
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ToastUtils.toast(
        e is DioError
            ? DioErrorMessage.forApp(e)
            : DioErrorMessage.sanitizeUserText(
                e.toString(),
                fallback: i18n.t(
                  zhHans: '操作失败',
                  zhHant: '操作失敗',
                  en: 'Failed',
                  ja: '失敗しました',
                  ko: '실패했습니다',
                ),
              ),
      );
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    return ValueListenableBuilder<List<UserDevice>>(
      valueListenable: _service.devices,
      builder: (context, devices, _) {
        return DesktopLoggedInLayout(
          title: _headline(i18n, devices),
          closeTooltip: i18n.t(
            zhHans: '关闭',
            zhHant: '關閉',
            en: 'Close',
            ja: '閉じる',
            ko: '닫기',
          ),
          signOutText: i18n.t(
            zhHans: '退出桌面端',
            zhHant: '退出桌面端',
            en: 'Sign out desktop',
            ja: 'パソコンをログアウト',
            ko: '데스크톱 로그아웃',
          ),
          loading: _loading,
          busy: _busy,
          onClose: _busy ? null : () => Navigator.of(context).pop(),
          onSignOut: _signOutDesktop,
        );
      },
    );
  }
}
