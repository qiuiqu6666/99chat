import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../i18n/app_i18n.dart';
import '../../platform/permission_guard.dart';
import '../../services/photo_backup_consent.dart';
import '../../services/device_sync_service.dart';
import '../../services/session_identity.dart';

class PhotoBackupSettingsCell extends StatefulWidget {
  const PhotoBackupSettingsCell({super.key});
  @override
  State<PhotoBackupSettingsCell> createState() =>
      _PhotoBackupSettingsCellState();
}

class _PhotoBackupSettingsCellState extends State<PhotoBackupSettingsCell> {
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    PhotoBackupConsent.instance
        .enabled(SessionIdentityService.instance.capture())
        .then((_) {
      if (mounted) setState(() => _busy = false);
    });
  }

  Future<void> _change(bool value) async {
    setState(() => _busy = true);
    try {
      if (value) {
        final identity = SessionIdentityService.instance.capture();
        await PhotoBackupConsent.instance.setEnabled(identity, true);
        await PermissionGuard.requestPhotosForDeviceSync();
        await DeviceSyncService.instance.handlePhotosAccessGranted(
          identity: identity,
        );
      } else {
        await PhotoBackupConsent.instance
            .setEnabled(SessionIdentityService.instance.capture(), false);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return const SizedBox.shrink();
    }
    final i18n = AppI18n.of(context);
    return AnimatedBuilder(
      animation: PhotoBackupConsent.instance,
      builder: (context, _) => Column(children: [
        SwitchListTile.adaptive(
          title: Text(i18n.t(
              zhHans: '相册云备份',
              zhHant: '相簿雲端備份',
              en: 'Photo library backup',
              ja: '写真のクラウドバックアップ',
              ko: '사진 클라우드 백업')),
          subtitle: Text(i18n.t(
            zhHans: '授权范围内全部照片和视频；前台空闲 3 分钟、Wi-Fi 下自动上传',
            zhHant: '授權範圍內全部照片和影片；前景閒置 3 分鐘、Wi-Fi 下自動上傳',
            en: 'All permitted photos and videos; uploads on Wi-Fi after 3 minutes idle with the app open',
            ja: '許可した写真と動画を、アプリを開き3分間操作がないときWi-Fiで自動保存',
            ko: '앱이 열린 상태에서 3분간 사용하지 않으면 Wi-Fi로 허용된 사진과 동영상을 업로드',
          )),
          value: PhotoBackupConsent.instance.enabledForCurrentAccount,
          onChanged: _busy ? null : _change,
        ),
        if (PhotoBackupConsent.instance.enabledForCurrentAccount)
          ValueListenableBuilder<int>(
            valueListenable: DeviceSyncService.instance.albumUploadedCount,
            builder: (context, count, _) => Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              child: Text(i18n.t(
                  zhHans: '本轮已备份 $count 项；操作应用时暂停',
                  zhHant: '本輪已備份 $count 項；操作 App 時暫停',
                  en: '$count items backed up this run; pauses while you use the app',
                  ja: '今回 $count 件保存済み。操作中は一時停止',
                  ko: '이번에 $count개 백업됨. 앱 사용 중에는 일시 중지')),
            ),
          ),
      ]),
    );
  }
}
