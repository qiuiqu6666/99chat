import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';

/// Subscriber controls notifications here; publishing remains unavailable.
class ChannelNotificationToggleBar extends StatelessWidget {
  const ChannelNotificationToggleBar({
    super.key,
    required this.muted,
    required this.busy,
    required this.onTap,
  });

  final bool muted;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    return Container(
      height: 54,
      width: double.infinity,
      color: Colors.white,
      alignment: Alignment.center,
      child: TextButton(
        key: const ValueKey('channel-notification-toggle'),
        onPressed: busy ? null : onTap,
        child: Text(
          muted
              ? i18n.t(zhHans: '静音', zhHant: '靜音', en: 'Muted',
                  ja: 'ミュート', ko: '음소거')
              : i18n.t(zhHans: '接收通知', zhHant: '接收通知',
                  en: 'Receive notifications', ja: '通知を受け取る',
                  ko: '알림 받기'),
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF2388F0),
          ),
        ),
      ),
    );
  }
}
