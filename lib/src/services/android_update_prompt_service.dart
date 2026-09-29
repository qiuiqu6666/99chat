import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';

import 'android_update_download.dart';

/// Only a verified APK produces an update dialog. The root navigator is
/// resolved at display time, never retained from a settings/home page.
class AndroidUpdatePromptService with WidgetsBindingObserver {
  AndroidUpdatePromptService._()
      : download = AndroidUpdateDownloadController(
            MethodChannelAndroidUpdateGateway());
  @visibleForTesting
  AndroidUpdatePromptService.forTesting(this.download);
  static final instance = AndroidUpdatePromptService._();
  final AndroidUpdateDownloadController download;
  bool _disposed = false;
  bool _attached = false;
  bool _foreground = true;
  bool _showing = false;
  ModalRoute<dynamic>? _dialogRoute;
  AndroidUpdateRequest? _dialogRequest;
  String? _promptedKey;
  String? _permissionKey;
  String? _lastLoggedState;
  Timer? _promptRetry;

  void _attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    download.addListener(_changed);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    if (!_foreground) download.setForeground(false);
  }

  Future<void> prepare(AndroidUpdateRequest request,
      {required bool manual}) async {
    _attach();
    if (manual || download.snapshot.request?.key != request.key) {
      _promptedKey = null;
    }
    await download.prepare(request, retry: manual);
    if (manual && !download.snapshot.ready) {
      _toast(
          download.snapshot.downloading
              ? '更新正在后台下载，下载完成后会提示安装'
              : '更新下载暂时失败，请稍后重新检查更新',
          download.snapshot.downloading
              ? 'Downloading the update in the background. You will be prompted when it is ready.'
              : 'Unable to download the update. Please check for updates again.');
    }
    _changed();
  }

  Future<void> restore() async {
    _attach();
    await download.refresh();
  }

  Future<void> cancel() async {
    _promptRetry?.cancel();
    _permissionKey = null;
    _promptedKey = null;
    await download.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _promptRetry?.cancel();
    download.setForeground(_foreground);
    if (_foreground) {
      // Unknown-source settings can return before the Activity gains focus.
      _promptRetry = Timer(const Duration(milliseconds: 500), () async {
        final key = _permissionKey;
        if (key != null && _foreground) {
          _permissionKey = null;
          await download.refresh();
          if (download.snapshot.request?.key == key &&
              download.snapshot.ready) {
            await _install(requestPermission: false);
          }
        }
        _changed();
      });
    }
  }

  void _changed() {
    if (_disposed) return;
    final value = download.snapshot;
    final shown = _dialogRequest;
    if (shown != null &&
        (!value.ready ||
            value.request?.key != shown.key ||
            value.request?.mandatory != shown.mandatory)) {
      _closeOwnedDialog();
      _promptedKey = null;
    }
    final marker = '${value.request?.key}:${value.state}:${value.reason}';
    if (_lastLoggedState != marker) {
      _lastLoggedState = marker;
      developer.log(
          'state=${value.state} key=${value.request?.key.substring(0, 12)} build=${value.request?.build} reason=${value.reason}',
          name: 'ninechat.update');
    }
    if (value.state == 'installed') {
      unawaited(cancel());
      return;
    }
    final request = value.request;
    if (!value.ready ||
        request == null ||
        !_foreground ||
        _permissionKey != null ||
        _showing ||
        _promptedKey == request.key) {
      return;
    }
    final context = AppNavigator.context;
    if (context == null || !context.mounted || AppDialog.isShowing) {
      _promptRetry?.cancel();
      _promptRetry = Timer(const Duration(seconds: 2), _changed);
      return;
    }
    unawaited(_showReady(request, AppI18n.of(context)));
  }

  Future<void> _showReady(AndroidUpdateRequest request, AppI18n i18n) async {
    _showing = true;
    _dialogRequest = request;
    _promptedKey = request.key;
    final ready = i18n.t(
        zhHans: '新版本 v${request.version} 已下载完成，是否立即安装？',
        zhHant: '新版本 v${request.version} 已下載完成，是否立即安裝？',
        en: 'Version ${request.version} is ready. Install now?',
        ja: 'バージョン ${request.version} の準備ができました。インストールしますか？',
        ko: '${request.version} 버전 다운로드가 완료되었습니다. 설치할까요?');
    try {
      await AppDialog.showUpdateDialog(
        title: i18n.t(
            zhHans: '新版本已准备好',
            zhHant: '新版本已準備好',
            en: 'Update Ready',
            ja: '更新の準備が完了しました',
            ko: '업데이트 준비 완료'),
        message: request.notes.isEmpty ? ready : '$ready\n\n${request.notes}',
        confirmText: i18n.t(
            zhHans: '立即安装',
            zhHant: '立即安裝',
            en: 'Install Now',
            ja: '今すぐインストール',
            ko: '지금 설치'),
        showCloseButton: !request.mandatory,
        onRouteReady: (route) {
          _dialogRoute = route;
          // Withdrawal may arrive before the dialog's first layout.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_disposed) {
              _closeOwnedDialog();
            } else {
              _changed();
            }
          });
        },
        onConfirm: () {
          if (download.snapshot.request?.key == request.key) {
            unawaited(_install());
          }
        },
      );
    } catch (_) {
      _promptedKey = null;
    } finally {
      _showing = false;
      _dialogRoute = null;
      _dialogRequest = null;
      _promptRetry?.cancel();
      if (!_disposed) {
        _promptRetry = Timer(const Duration(seconds: 1), _changed);
      }
    }
  }

  Future<void> _install({bool requestPermission = true}) async {
    if (!_foreground || _disposed) return;
    final key = download.snapshot.request?.key;
    developer.log(
        'install_requested build=${download.snapshot.request?.build} permissionPrompt=$requestPermission',
        name: 'ninechat.update');
    final result = await download.install(requestPermission: requestPermission);
    developer.log('install_result result=$result', name: 'ninechat.update');
    if (_disposed || key != download.snapshot.request?.key) return;
    if (result == 'permission_required') {
      _permissionKey = key;
      _toast('请允许安装此来源的应用，返回后将继续安装',
          'Allow installation from this source, then return to continue.');
    } else if (result != 'installer_opened') {
      _toast('暂时无法安装，请重新点击安装并检查安装权限',
          'Unable to install. Check installation permission and try again.');
      _promptedKey = null;
      // Recheck native state if a file was deleted or replaced after prompting.
      await download.refresh();
      _changed();
    }
  }

  void _toast(String chinese, String english) {
    final context = AppNavigator.context;
    if (_disposed || context == null || !context.mounted || !_foreground) {
      return;
    }
    final i18n = AppI18n.of(context);
    ToastUtils.toast(i18n.t(
        zhHans: chinese,
        zhHant: chinese,
        en: english,
        ja: english,
        ko: english));
  }

  @visibleForTesting
  void dispose() {
    _disposed = true;
    _promptRetry?.cancel();
    _closeOwnedDialog();
    WidgetsBinding.instance.removeObserver(this);
    download.removeListener(_changed);
    download.dispose();
  }

  void _closeOwnedDialog() {
    final route = _dialogRoute;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }
}
