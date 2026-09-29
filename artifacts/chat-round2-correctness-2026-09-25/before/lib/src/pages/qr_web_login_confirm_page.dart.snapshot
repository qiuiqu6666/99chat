import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_demo/src/api/auth_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/device_api.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/auth_localizations.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/settings_widgets.dart';
import 'package:tencent_cloud_chat_demo/src/services/desktop_login_session_service.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_demo/src/ui/app_tokens.dart';
import 'package:tencent_cloud_chat_demo/src/utils/immersive_app_system_ui.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/desktop_logged_in_layout.dart';
import 'package:tencent_cloud_chat_demo/utils/dio_error_message.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';

const String _kDesktopConfirmArt = 'assets/diann.png';

/// App：扫码后二次确认网页版登录。
class QrWebLoginConfirmPage extends StatefulWidget {
  const QrWebLoginConfirmPage({
    super.key,
    required this.sessionId,
    this.siteLabel,
  });

  final String sessionId;
  final String? siteLabel;

  @override
  State<QrWebLoginConfirmPage> createState() => _QrWebLoginConfirmPageState();
}

class _QrWebLoginConfirmPageState extends State<QrWebLoginConfirmPage> {
  bool _loading = true;
  bool _busy = false;
  bool _signedIn = false;
  String? _error;
  String? _siteLabel;

  AuthLocalizations get _strings => AuthLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    _siteLabel = widget.siteLabel;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_registerScan());
    });
  }

  Future<void> _registerScan() async {
    final strings = _strings;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result =
          await AuthApi.instance.scanQrLoginSession(widget.sessionId);
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _siteLabel = result.siteLabel?.trim().isNotEmpty == true
            ? result.siteLabel
            : _siteLabel;
      });
    } on DioError catch (e) {
      if (!mounted) {
        return;
      }
      final unavailable = e.response?.statusCode == 404;
      setState(() {
        _loading = false;
        _error = unavailable
            ? strings.qrLoginUnavailable
            : DioErrorMessage.fromQrWebLogin(e, strings);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = strings.requestFailed;
      });
    }
  }

  Future<void> _confirm(bool approve) async {
    if (_busy) {
      return;
    }
    final strings = _strings;
    setState(() => _busy = true);
    try {
      await AuthApi.instance.confirmQrLoginSession(
        sessionId: widget.sessionId,
        approve: approve,
      );
      if (approve) {
        unawaited(
          DesktopLoginSessionService.instance.refresh(
            reason: 'qr_web_confirmed',
            force: true,
          ),
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _busy = false;
          _signedIn = true;
        });
        return;
      }
      if (!mounted) {
        return;
      }
      ToastUtils.toast(strings.qrWebLoginCancelledToast);
      Navigator.of(context).pop(false);
    } on DioError catch (e) {
      if (!mounted) {
        return;
      }
      final unavailable = e.response?.statusCode == 404;
      ToastUtils.toast(
        unavailable
            ? strings.qrLoginUnavailable
            : DioErrorMessage.fromQrWebLogin(e, strings),
      );
      setState(() => _busy = false);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ToastUtils.toast(strings.requestFailed);
      setState(() => _busy = false);
    }
  }

  Future<void> _onClose() async {
    if (_busy) {
      return;
    }
    if (_signedIn || _loading || _error != null) {
      Navigator.of(context).pop(_signedIn);
      return;
    }
    await _confirm(false);
  }

  Future<void> _signOutDesktop() async {
    if (_busy) {
      return;
    }
    final strings = _strings;
    setState(() => _busy = true);
    try {
      await DesktopLoginSessionService.instance.refresh(
        reason: 'qr_web_sign_out',
        force: true,
      );
      final devices =
          List.of(DesktopLoginSessionService.instance.devices.value);
      for (final device in devices) {
        await DeviceApi.instance.kickDevice(device.deviceId);
      }
      await DesktopLoginSessionService.instance.refresh(
        reason: 'qr_web_signed_out',
        force: true,
      );
      if (!mounted) {
        return;
      }
      ToastUtils.toast(strings.qrWebLoginCancelledToast);
      Navigator.of(context).pop(true);
    } on DioError catch (e) {
      if (!mounted) {
        return;
      }
      ToastUtils.toast(DioErrorMessage.fromQrWebLogin(e, strings));
      setState(() => _busy = false);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ToastUtils.toast(strings.requestFailed);
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _strings;
    final label = (_siteLabel ?? '').trim();
    if (_signedIn) {
      return DesktopLoggedInLayout(
        title: strings.qrWebLoginLoggedInHeadline(label),
        closeTooltip: strings.qrWebLoginCancelAction,
        signOutText: strings.qrWebLoginSignOutDesktop,
        busy: _busy,
        onClose: _onClose,
        onSignOut: _signOutDesktop,
      );
    }
    final dark = settingsIsDark(context);
    final textColor = AppColors.text(dark: dark);
    final overlayStyle = immersiveOverlayForColors(
      statusBarBackground: AppColors.background(dark: dark),
      navigationBarBackground: AppColors.background(dark: dark),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: AppColors.background(dark: dark),
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: _busy ? null : _onClose,
                  icon: const Icon(Icons.close, size: 26),
                  color: AppTokens.accent,
                  tooltip: strings.qrWebLoginCancelAction,
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppTokens.accent,
                        ),
                      )
                    : Column(
                        children: [
                          const SizedBox(height: 56),
                          Image.asset(
                            _kDesktopConfirmArt,
                            width: 220,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 28),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              _error ??
                                  strings.qrWebLoginConfirmHeadline(label),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              if (!_loading && _error == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
                  child: Center(
                    child: _ConfirmLoginButton(
                      text: strings.qrWebLoginConfirmAction,
                      loading: _busy,
                      onPressed: _busy ? null : () => _confirm(true),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmLoginButton extends StatelessWidget {
  const _ConfirmLoginButton({
    required this.text,
    required this.loading,
    required this.onPressed,
  });

  final String text;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      height: 44,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppTokens.accent,
          disabledBackgroundColor:
              AppTokens.accent.withValues(alpha: 0.55),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}
