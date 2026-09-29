import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/api/platform_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_version_check_service.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/utils/app_version.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:url_launcher/url_launcher.dart';

/// 升级策略分流结果
enum UpdateOutcome {
  /// 不弹窗（服务端 policy == none 或 无新版本）
  noPrompt,
  /// 弹可关闭窗（policy == optional）
  optional,
  /// 弹不可关闭窗（policy == force / gray 或服务端配错降级）
  mandatory,
}

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  bool _checking = false;
  bool _automaticCheckCompleted = false;

  /// 按 platform-and-feedback.md §6.1 判定升级策略。
  /// 返回 [UpdateOutcome] 决定是否弹窗 + 是否可关闭。
  UpdateOutcome evaluateUpdatePolicy({
    required PlatformContactInfo info,
    required String currentVersion,
    required int currentBuildNumber,
  }) {
    final policy = info.updatePolicy;
    // none 直接不弹
    if (policy == UpdatePolicy.none) {
      return UpdateOutcome.noPrompt;
    }
    // optional / gray / force 都弹；force + gray 不可关闭
    if (policy == UpdatePolicy.optional) {
      return UpdateOutcome.optional;
    }
    // force/gray：还要看阈值（minVersionCode/minVersion）是否真的低于当前
    final meetsThreshold = _isBelowThreshold(
      info: info,
      currentVersion: currentVersion,
      currentBuildNumber: currentBuildNumber,
    );
    if (meetsThreshold) {
      return UpdateOutcome.mandatory;
    }
    // force/gray 但当前已超过阈值 → 按可选处理
    return UpdateOutcome.optional;
  }

  /// 服务端配的 force/gray 阈值判定
  bool _isBelowThreshold({
    required PlatformContactInfo info,
    required String currentVersion,
    required int currentBuildNumber,
  }) {
    if (info.minVersionCode != null) {
      return currentBuildNumber < info.minVersionCode!;
    }
    final minVersion = info.minVersion;
    if (minVersion != null && minVersion.isNotEmpty) {
      return compareVersions(currentVersion, minVersion) < 0;
    }
    // 没给阈值 → 默认低于（即触发强制）
    return true;
  }

  /// 公开的版本比较：按 semver 语义。
  ///   1. 用 `+` / `-` 把字符串拆成"主版本"和"尾部标签"
  ///   2. 主版本按 `.` 拆段逐段比数字，空段视为 0
  ///   3. 主版本相等时，无尾部标签 > 有尾部标签
  ///   4. 都有尾部标签时按字符串比
  /// 这样 1.0.2+1 == 1.0.2，2.0.0-rc1 == 2.0.0 等符合预期。
  static int compareVersions(String a, String b) {
    final (mainA, tagA) = _splitMainAndTag(a);
    final (mainB, tagB) = _splitMainAndTag(b);
    final pa = mainA.split('.');
    final pb = mainB.split('.');
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final sa = i < pa.length ? pa[i] : '0';
      final sb = i < pb.length ? pb[i] : '0';
      final ia = int.tryParse(sa);
      final ib = int.tryParse(sb);
      final int c;
      if (ia != null && ib != null) {
        c = ia.compareTo(ib);
      } else {
        c = sa.compareTo(sb);
      }
      if (c != 0) return c;
    }
    // 主版本相同，比尾部标签：有 > 无
    if (tagA.isEmpty && tagB.isEmpty) return 0;
    if (tagA.isEmpty) return 1;
    if (tagB.isEmpty) return -1;
    return tagA.compareTo(tagB);
  }

  static (String main, String tag) _splitMainAndTag(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return ('', '');
    // + 后面是 build 号，不参与版本比较
    final plusIdx = raw.indexOf('+');
    final main =
        plusIdx >= 0 ? raw.substring(0, plusIdx) : raw;
    // - 后面是预发布标签
    final dashIdx = main.indexOf('-');
    if (dashIdx < 0) return (main, '');
    return (main.substring(0, dashIdx), main.substring(dashIdx + 1));
  }

  Future<void> check(
    BuildContext context, {
    required bool manual,
  }) async {
    if (_checking || (!manual && _automaticCheckCompleted)) {
      return;
    }
    _checking = true;
    try {
      final info = await StartupVersionCheckService.instance.fetch(
        force: manual,
      );
      if (info == null) {
        throw const FormatException('Unable to load platform contact info');
      }
      final clientVersion = await AppVersion.getClientVersion();
      final clientParts = clientVersion.split('+');
      final localVersion = clientParts.first.trim();
      final localBuild =
          clientParts.length > 1 ? int.tryParse(clientParts[1].trim()) ?? 0 : 0;
      final remoteVersion = info.version.trim();
      final remoteBuild = int.tryParse(info.build.trim()) ?? 0;
      if (remoteVersion.isEmpty) {
        throw const FormatException('Missing remote version');
      }

      // 按服务端 updateType 决定升级策略
      final outcome = evaluateUpdatePolicy(
        info: info,
        currentVersion: localVersion,
        currentBuildNumber: localBuild,
      );
      final versionComparison = compareVersions(remoteVersion, localVersion);
      final hasNewVersion = versionComparison > 0 ||
          (versionComparison == 0 && remoteBuild > localBuild);
      // 无新版本 + 不强制 → 不弹窗
      final isMandatory = outcome == UpdateOutcome.mandatory;
      final shouldPrompt = (outcome != UpdateOutcome.noPrompt) &&
          (hasNewVersion || isMandatory);
      if (!manual) {
        _automaticCheckCompleted = true;
      }
      if (!context.mounted) {
        return;
      }

      final i18n = AppI18n.of(context);
      if (!shouldPrompt) {
        if (manual) {
          ToastUtils.toast(i18n.t(
            zhHans: '当前已是最新版本',
            zhHant: '目前已是最新版本',
            en: 'You are using the latest version.',
            ja: '最新バージョンを使用しています。',
            ko: '현재 최신 버전을 사용 중입니다.',
          ));
        }
        return;
      }

      if (!manual && AppDialog.isShowing) {
        _automaticCheckCompleted = false;
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (context.mounted) {
            check(context, manual: false);
          }
        });
        return;
      }

      final downloadUrl = info.downloadUrl.trim();
      final changelogText = (info.changelog ?? '').trim();
      // 中文标题：force → "发现新版本！"；optional/gray → "发现新版本"
      final titleText = info.updatePolicy == UpdatePolicy.force
          ? i18n.t(
              zhHans: '发现新版本！',
              zhHant: '發現新版本！',
              en: 'Update Required',
              ja: '更新が必要',
              ko: '업데이트 필요',
            )
          : i18n.t(
              zhHans: '发现新版本',
              zhHant: '發現新版本',
              en: 'Update Available',
              ja: '新しいバージョン',
              ko: '새 버전 발견',
            );
      // changelog 优先，否则用通用文案；\n 会被 Text 自动换行
      final messageText = changelogText.isNotEmpty
          ? changelogText
          : i18n.t(
              zhHans: '发现新版本 v$remoteVersion，是否立即更新？',
              zhHant: '發現新版本 v$remoteVersion，是否立即更新？',
              en: 'Version $remoteVersion is available. Update now?',
              ja: 'バージョン $remoteVersion が利用可能です。更新しますか？',
              ko: '새 버전 $remoteVersion이 있습니다. 지금 업데이트하시겠습니까?',
            );

      Future<void> launchDownload() async {
        final uri = Uri.tryParse(downloadUrl);
        if (uri == null ||
            !uri.hasScheme ||
            !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          if (!context.mounted) return;
          ToastUtils.toast(i18n.t(
            zhHans: '无法打开下载页面',
            zhHant: '無法開啟下載頁面',
            en: 'Unable to open the download page.',
            ja: 'ダウンロードページを開けません。',
            ko: '다운로드 페이지를 열 수 없습니다.',
          ));
        }
      }

      // 按 updateType 决定弹窗可关闭性：
      //   none → 不弹（已 early-return）
      //   optional → 单按钮 + X（可关闭）
      //   force / gray → 单按钮 + 无 X（不可关闭）
      await AppDialog.showUpdateDialog(
        title: titleText,
        message: messageText,
        confirmText: i18n.t(
          zhHans: '立即更新',
          zhHant: '立即更新',
          en: 'Update Now',
          ja: '今すぐ更新',
          ko: '지금 업데이트',
        ),
        showCloseButton: info.updatePolicy.showCloseButton,
        onConfirm: launchDownload,
      );
    } catch (_) {
      if (manual && context.mounted) {
        final i18n = AppI18n.of(context);
        ToastUtils.toast(i18n.t(
          zhHans: '检查更新失败，请稍后重试',
          zhHant: '檢查更新失敗，請稍後再試',
          en: 'Unable to check for updates. Please try again later.',
          ja: '更新を確認できません。しばらくしてから再試行してください。',
          ko: '업데이트를 확인할 수 없습니다. 잠시 후 다시 시도해 주세요.',
        ));
      }
    } finally {
      _checking = false;
    }
  }
}
