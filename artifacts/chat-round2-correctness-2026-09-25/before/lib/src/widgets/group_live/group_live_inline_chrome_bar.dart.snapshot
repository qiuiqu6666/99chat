import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_cast_button.dart';

class GroupLiveInlineChromeBar extends StatelessWidget {
  const GroupLiveInlineChromeBar({
    super.key,
    required this.showLiveStatus,
    required this.showMediaButtons,
    required this.onClose,
    this.muted = false,
    this.isFullScreen = false,
    this.onToggleMute,
    this.onToggleFullscreen,
  });

  final bool showLiveStatus;
  final bool showMediaButtons;
  final bool muted;
  final bool isFullScreen;
  final VoidCallback? onToggleMute;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showLiveStatus) _liveCluster(i18n) else const SizedBox.shrink(),
        const Expanded(child: SizedBox.shrink()),
        if (showMediaButtons) ...[
          _iconButton(
            tooltip: muted ? 'Unmute' : 'Mute',
            icon: muted
                ? Icons.volume_off_outlined
                : Icons.volume_up_outlined,
            onPressed: onToggleMute!,
          ),
          const GroupLiveCastButton(
            iconColor: Colors.white,
            iconSize: 22,
            padding: EdgeInsets.all(6),
          ),
          _iconButton(
            tooltip: isFullScreen ? 'Exit fullscreen' : 'Fullscreen',
            icon: isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
            onPressed: onToggleFullscreen!,
          ),
        ],
        _iconButton(
          tooltip: i18n.t(
            zhHans: '关闭',
            zhHant: '關閉',
            en: 'Close',
            ja: '閉じる',
            ko: '닫기',
          ),
          icon: Icons.close,
          onPressed: onClose,
        ),
      ],
    );
  }

  Widget _liveCluster(AppI18n i18n) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFC4F53),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              i18n.t(
                zhHans: '直播中',
                zhHant: '直播中',
                en: 'Live',
                ja: '配信中',
                ko: '라이브',
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      icon: Icon(icon, color: Colors.white, size: 22),
      onPressed: onPressed,
    );
  }
}
