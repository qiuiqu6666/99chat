import 'package:tencent_cloud_chat_sdk/enum/log_level_enum.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/tim_uikit_config.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tuikit_info_toast.dart';
import 'package:tencent_cloud_chat_demo/src/platform/uikit_avatar_preview_bridge.dart';
import 'package:tencent_cloud_chat_demo/src/services/platform_official_account_service.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'im_event_bridge.dart';

class UIKitBootstrap {
  UIKitBootstrap._();
  static final instance = UIKitBootstrap._();
  bool _initialized = false;

  Future<void> initialize(
      {required int sdkAppId, required ImEventBridge events}) async {
    if (_initialized) return;
    final ok = await TIMUIKitCore.getInstance().init(
      sdkAppID: sdkAppId,
      loglevel: LogLevelEnum.V2TIM_LOG_NONE,
      listener: events.listener(),
      config: TIMUIKitConfig(
        isShowOnlineStatus: true,
        shouldHideUserFromPickers: (userId) =>
            PlatformOfficialAccountService.shouldHideFromContactAndPickers(
          userId,
        ),
        saveAvatarPreview: UikitAvatarPreviewBridge.savePreview,
        prepareWebAvatarPreviewUrl:
            UikitAvatarPreviewBridge.prepareWebPreviewUrl,
      ),
    );
    if (ok != true) throw StateError('UIKit 初始化失败');
    TUIKitInfoToast.presenter = (message) => ToastUtils.toast(message);
    _initialized = true;
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    await TIMUIKitCore.getInstance().logout();
    _initialized = false;
  }
}
