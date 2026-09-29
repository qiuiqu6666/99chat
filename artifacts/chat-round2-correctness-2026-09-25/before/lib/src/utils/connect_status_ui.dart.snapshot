import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/services/auth_bootstrap_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/login_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/login_state.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/network_status_service.dart';

/// 五个主 Tab 顶部标题：区分 IM SDK 与自建后端未就绪时的展示态。
class ConnectStatusUi {
  ConnectStatusUi._();

  /// 后端认证是否可用；后台资料/会话同步不代表连接断开。
  static bool isBackendReady() {
    if (!ApiClient.isValidJwt(ApiClient.instance.token)) {
      return false;
    }
    switch (LoginCoordinator.instance.state.phase) {
      case LoginPhase.businessAuthenticating:
      case LoginPhase.businessAuthenticated:
      case LoginPhase.sessionRefreshing:
        return false;
      default:
        return true;
    }
  }

  /// 系统网络是否可用（飞行模式 / 无蜂窝与 Wi‑Fi 时为 false）。
  static bool isNetworkReady() {
    return NetworkStatusService.instance.status.value !=
        NetworkReachability.offline;
  }

  /// IM SDK 长连接是否已就绪（以 [onConnectSuccess] 为准，登录态 ≠ 已连上服务器）。
  static bool isImSdkReady(LocalSetting localSetting) {
    if (!isNetworkReady()) {
      return false;
    }
    if (localSetting.connectStatusForUi == ConnectStatus.failed) {
      return false;
    }
    if (!ImConnectStatusService.isSocketReady) {
      return false;
    }
    // UIKit 用户已就绪时，post-home 同步可能仍未推进 LoginPhase。
    // 连接标题不等待会话漫游、资料恢复等后台任务完成。
    if (AuthBootstrapService.instance.isCoreServicesUserReady()) {
      return true;
    }
    switch (LoginCoordinator.instance.state.phase) {
      case LoginPhase.imConnecting:
      case LoginPhase.homeEnteredSyncingIm:
        return false;
      default:
        break;
    }
    if (LoginCoordinator.instance.state.isImReady) {
      return true;
    }
    return localSetting.connectStatusForUi == ConnectStatus.success;
  }

  /// 主 Tab 大标题连接指示：busy/failed 时标题只显示转圈或错误图标。
  /// 标题只代表 IM 长连接；系统离线由聊天页细条承担，不在此把 socket 已就绪盖成 failed。
  static ConversationTabConnectIndicator conversationTabConnectIndicator(
    LocalSetting localSetting,
  ) {
    if (ImConnectStatusService.isSocketReady) {
      if (!isBackendReady()) {
        return ConversationTabConnectIndicator.busy;
      }
      return ConversationTabConnectIndicator.ready;
    }
    if (localSetting.connectStatusForUi == ConnectStatus.failed) {
      return ConversationTabConnectIndicator.failed;
    }
    if (!isNetworkReady() || !isBackendReady() || !isImSdkReady(localSetting)) {
      return ConversationTabConnectIndicator.busy;
    }
    return ConversationTabConnectIndicator.ready;
  }

  /// 消息 / 群聊 Tab 纯标题（不再附带连接状态小字）。
  static String formatConversationTabTitle({
    required AppI18n i18n,
    required String baseTitle,
    required LocalSetting localSetting,
  }) {
    return baseTitle;
  }
}

/// 主 Tab 大标题旁连接指示。
enum ConversationTabConnectIndicator { ready, busy, failed }
