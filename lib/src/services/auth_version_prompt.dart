import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/auth_failure_policy.dart';
import '../widgets/message_notification_banner.dart';

class AuthVersionPrompt {
  static bool _showing = false;
  static Future<void> show(AuthVersionFailure failure) async {
    final context = AppNavigator.context;
    if (_showing || context == null || !context.mounted) return;
    _showing = true;
    try {
      await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: const Text('需要升级'),
                content: SingleChildScrollView(
                    child: Text([
                  failure.message,
                  if (failure.changelog.isNotEmpty) failure.changelog,
                  if (failure.downloadUri == null) '服务器未提供有效下载地址，请联系客服获取更新。',
                ].join('\n\n'))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('关闭')),
                  if (failure.downloadUri != null)
                    TextButton(
                        onPressed: () async {
                          var opened = false;
                          try {
                            opened = await launchUrl(failure.downloadUri!,
                                mode: LaunchMode.externalApplication);
                          } catch (_) {}
                          if (!dialogContext.mounted) return;
                          if (!opened) {
                            ScaffoldMessenger.maybeOf(dialogContext)
                                ?.showSnackBar(const SnackBar(
                                    content: Text('无法打开下载地址，请稍后再试')));
                          }
                        },
                        child: const Text('立即升级')),
                ],
              ));
    } catch (_) {
      // UI failure must not replace the original HTTP error.
    } finally {
      _showing = false;
    }
  }
}
