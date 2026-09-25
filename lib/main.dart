import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
// ignore_for_file: unused_import, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform, pid;
import 'package:tencent_cloud_chat_demo/src/widgets/business_session_guard.dart';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:desktop_webview_window_for_is/desktop_webview_window_for_is.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:tencent_chat_i18n_tool/language_json/strings.g.dart';
import 'package:tencent_chat_i18n_tool/tools/i18n_tool.dart';
import 'package:tencent_cloud_chat_demo/custom_animation.dart';
import 'package:tencent_cloud_chat_demo/config.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/api_node_service.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_material_app_builder.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_route_lifecycle.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/route_visibility.dart';
import 'package:tencent_cloud_chat_demo/src/pages/app.dart';
import 'package:tencent_cloud_chat_demo/src/utils/launch_system_ui.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_repository_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/custom_sticker_package.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/language_switch_sheet.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_gate_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/device_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/android_performance_profile.dart';
import 'package:tencent_cloud_chat_demo/src/services/network_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/notification_settings_service.dart';
import 'package:tencent_cloud_chat_demo/src/platform/uikit_self_hosted_friend_bridge.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_join_application_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_entry_settings_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_unread_service.dart';
import 'package:tencent_cloud_chat_demo/src/platform/uikit_self_hosted_group_bridge.dart';
import 'package:tencent_cloud_chat_demo/src/platform/uikit_add_friend_bridge.dart';
import 'package:tencent_cloud_chat_demo/src/platform/uikit_permission_bridge.dart';
import 'package:tencent_cloud_chat_demo/src/platform/uikit_media_url_bridge.dart';
import 'package:tencent_cloud_chat_demo/src/platform/uikit_voice_to_text_bridge.dart';
import 'package:tencent_cloud_chat_demo/src/services/login_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/in_app_notification_sound.dart';
import 'package:tencent_cloud_chat_demo/src/services/ios_apns_push_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/push_registration_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_expiry_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/splash_config_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/auth_bootstrap_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_manager.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_version_check_service.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/forward_pick_pages.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_privacy_cover.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_popout_app.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/media_popout/desktop_media_popout_window.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/media_popout/media_popout_app.dart';
import 'package:tencent_cloud_chat_demo/src/provider/login_user_Info.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/starred_friend_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/provider/user_guide_provider.dart';
import 'package:tencent_cloud_chat_demo/utils/app_material_theme.dart';
import 'package:tencent_cloud_chat_demo/utils/theme.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_demo/src/utils/image_region_decoder.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_region_decode_hook.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_conversation_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
// IMP(ArchiveRegister)：注册仍保留的 UIKit 后端委托。
// 标准消息历史（包括 Community）由腾讯 IM SDK 提供；这里只保留清空同步、
// 会话归档与已读等业务写入，不能重新注册 Community 历史 reader。
import 'package:tencent_cloud_chat_demo/src/services/message_archive_history_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_history_clear_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_peer_read_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/message_history_coverage_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/message_media_metadata_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/agent_rebate_local/agent_rebate_entry_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_game_prefs.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_live_watch_float_prefs.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_game/privileged_game_user_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_game/sangong_my_config_service.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/archive_history_provider.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/archived_conversation_store.dart';

void main(List<String> args) {
  // Profile 用于真机性能诊断，需要保留 Dart/业务日志；仅 Release 静默。
  if (kReleaseMode) {
    debugPrint = _discardDebugPrint;
  }
  runZonedGuarded<void>(
    () => _startApp(args),
    (error, stack) {
      if (_isKnownWebNoise(error, stack)) {
        return;
      }
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
      ));
    },
    zoneSpecification: !kReleaseMode
        ? null
        : ZoneSpecification(
            print: (self, parent, zone, line) {},
          ),
  );
}

void _discardDebugPrint(String? message, {int? wrapWidth}) {}

Future<void> _warmWebBundledFonts() async {
  if (!kIsWeb) return;
  try {
    await Future.wait<Object?>([
      rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf'),
      rootBundle.load('assets/fonts/NotoSansSC-SemiBold.ttf'),
      rootBundle.load('assets/fonts/NotoSansSC-Bold.ttf'),
      rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'),
    ]);
  } catch (_) {
    // 字体资源缺失时不阻塞启动。
  }
}

/// IMP(ArchiveRegister)：注册仍保留的 UIKit 后端委托。
///
/// 必须在 runApp 之前调用，且必须在 ApiClient.bootstrap 之后（register 内的
/// 清空同步依赖 ApiClient.dio；历史 reader 不在产品启动时注册。
void installBackendServices() {
  HistoryWindowRepositoryProvider.repository =
      kIsWeb ? null : HistoryWindowStore.instance;
  // All clients use cloud archive state: no SP restore or optimistic mutation.
  setArchivedConversationPersistToDisk(false);
  if (!kIsWeb && PlatformUtils().isDesktop) {
    ActiveChatRegistry.instance.setListVisibleAlongsideChat(true);
    ConversationPerfGateLog.enabled = true;
  }
  // (1) 保留清空记录同步；不注册 Community 历史 reader。
  MessageArchiveHistoryService.register();
  // (2) 清档回调：本端清空聊天记录时通知后端归档清理。
  ConversationHistoryClearService.register();
  // (3) 对方已读 → 会话列表 lastMessage.isPeerRead 写回。
  ConversationPeerReadSyncService.register();
  ImageRegionDecodeHook.decode = ImageRegionDecoder.decode;
  // ignore: avoid_print
  print(
    '[Bootstrap] backend services registered: archiveProvider isAvailable=${ArchiveHistoryProvider.isAvailable}',
  );
}

/// 启动阶段主动触发 msg_history 数据库首次打开（含 PRAGMA busy_timeout 失败恢复）。
///
/// 背景：用户冷启动后第一次进入任意聊天页时，MessageHistoryCoverageStore._openDbOnce
/// 会跑 PRAGMA busy_timeout = 5000，iOS sqflite_darwin 在某些时机抛
/// SqfliteDatabaseException(SQLITE_OK)，错误被 ignored 但首次 open + 恢复路径
/// 会抢占约 74ms，污染 push_after_wait 阶段（首屏体感从 21ms 退化到 168ms）。
/// 在 runApp 之前 fire-and-forget 触发一次，确保 DB 已 warm，后续会话走 existing 缓存。
void _warmupMessageCoverageStore() {
  unawaited(() async {
    try {
      final owner = MessageHistoryCoverageStore.instance.currentOwnerUserId();
      if (owner.isEmpty) return;
      // 用一个不会被用到的 placeholder convID，确保：
      //   (a) 走 _openDb 完整路径（key 非空才会触达）；
      //   (b) 不会污染任何真实会话的 coverage 缓存。
      await MessageHistoryCoverageStore.instance.loadForOwner(
        owner,
        '__warmup__',
      );
      // ignore: avoid_print
      print('[Bootstrap] msg_history DB warmup done');
    } catch (e) {
      // 预热失败不阻塞启动；下次会话进入时仍会走 _openDb 路径。
      // ignore: avoid_print
      print('[Bootstrap] msg_history DB warmup failed (ignored): $e');
    }
  }());
}

/// 把 agent_rebate_entry_v1.db 的当前 owner 行一次性灌进内存映射。
///
/// 背景：AgentRebateEntryLocalStore.readCachedSync 只查内存映射，进程被杀后清零；
/// 冷启动后如果没人把磁盘数据预热回来，didUpdateWidget 同步读永远返回 null，
/// 反水浮窗首屏必须等 650ms scheduler + 网络抖动才显。
/// 在 runApp 之前 fire-and-forget 触发一次；失败不阻塞启动。
Future<void> _warmupAgentRebateEntryStore() async {
  try {
    final owner = AgentRebateEntryLocalStore.instance.currentOwnerUserId();
    if (owner.isEmpty) return;
    final count =
        await AgentRebateEntryLocalStore.instance.preloadForOwner(owner);
    // ignore: avoid_print
    print('[Bootstrap] agent_rebate entry DB warmup done count=$count');
  } catch (e) {
    // ignore: avoid_print
    print('[Bootstrap] agent_rebate entry DB warmup failed (ignored): $e');
  }
}

void _detachMediaKitDebugReferenceHolder() {
  if (kReleaseMode) {
    return;
  }
  try {
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'com.alexmercerind.media_kit.NativeReferenceHolder.$pid',
    );
    if (file.existsSync()) {
      file.deleteSync();
    }
  } catch (_) {}
}

Future<void> _startMultiWindow(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  _detachMediaKitDebugReferenceHolder();
  MediaKit.ensureInitialized();
  final windowId = int.parse(args[1]);
  final argumentJson = args.length > 2 ? args[2] : '';
  Map<String, dynamic>? decoded;
  try {
    final raw = jsonDecode(argumentJson);
    if (raw is Map) {
      decoded = Map<String, dynamic>.from(raw);
    }
  } catch (_) {}
  if (decoded != null && decoded['kind'] == 'media') {
    debugPrint('[ChatImg] event=popout_engine_start');
    await _bootstrapMediaPopout();
    runApp(MediaPopoutApp(
      windowId: windowId,
      argumentJson: argumentJson,
    ));
    return;
  }
  runApp(GroupLivePopoutApp(
    windowId: windowId,
    argumentJson: argumentJson,
  ));
}

Future<void> _bootstrapMediaPopout() async {
  LocaleSettings.setLocale(AppLocale.zhHans);
  await ApiNodeService.instance.hydrate();
  await ApiClient.instance.bootstrap();
  setupServiceLocator();
  TIMUIKitCore.getInstance();
  UikitMediaUrlBridge.install();
  ImageRegionDecodeHook.decode = ImageRegionDecoder.decode;
  installForwardPickPages();
  try {
    final localSetting = LocalSetting(autoLoad: false);
    await localSetting.loadSettingsFromLocal();
    LocaleSettings.setLocale(
      LanguageSwitchSheet.toAppLocale(localSetting.language),
    );
  } catch (_) {}
  try {
    final login = await TIMUIKitCore.getSDKInstance().getLoginUser();
    if ((login.data ?? '').trim().isNotEmpty) {
      unawaited(serviceLocator<TUIFriendShipViewModel>().loadData());
      unawaited(
        serviceLocator<TUIConversationViewModel>().loadData(count: 100),
      );
    }
  } catch (_) {}
}

void _startApp(List<String> args) {
  if (args.isNotEmpty && args.first == 'multi_window') {
    unawaited(_startMultiWindow(args));
    return;
  }
  StartupPerfLog.mark('start', <String, Object>{
    'platform': Platform.operatingSystem,
    'buildMode': StartupPerfLog.buildMode,
    'consoleLogging': StartupPerfLog.consoleLoggingEnabled,
  });
  if (runWebViewTitleBarWidget(args)) {
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  StartupPerfLog.mark('flutter_binding_ready');
  MediaKit.ensureInitialized();
  StartupPerfLog.mark('media_kit_ready');
  if (!kIsWeb && Platform.isAndroid) {
    final picker = ImagePickerPlatform.instance;
    if (picker is ImagePickerAndroid) {
      // Android 12 及以下也优先尝试系统 Photo Picker；不可用时插件会回退到
      // 系统文档选择器，聊天页仍保留自定义相册作为异常兜底。
      picker.useAndroidPhotoPicker = true;
    }
  }
  // 保留足够的头像/缩略图解码缓存，同时限制长时间媒体会话的位图上限；
  // 384MB 在锁屏恢复时容易与消息列表重建叠加造成内存压力和 GC 卡顿。
  void configureImageCache() {
    if (!kIsWeb && Platform.isAndroid) {
      final profile = AndroidPerformanceProfile.instance;
      PaintingBinding.instance.imageCache.maximumSize =
          profile.imageCacheMaximumSize;
      PaintingBinding.instance.imageCache.maximumSizeBytes =
          profile.imageCacheMaximumSizeBytes;
      return;
    }
    PaintingBinding.instance.imageCache.maximumSize = 1200;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 192 << 20;
  }

  // 首次 ImageCache 配：Android 端 AndroidPerformanceProfile 尚未初始化，
  // 配额用 medium 默认值；Android 分支在 finishDeferredBootstrap 之后会
  // await initialize() 后再 configureImageCache() 一次（用真 tier）。
  configureImageCache();
  StartupPerfLog.mark('image_cache_configured');
  _installWebErrorGuard();
  // 冷启动与原生闪屏对齐：沉浸式透明系统栏
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(LaunchSystemUi.overlayStyle);
  StartupPerfLog.mark('system_ui_configured');
  // 全局loading
  configLoading();
  // AutoSizeUtil.setStandard(375, isAutoTextSize: true);
  // Default to Simplified Chinese until the saved language is loaded.
  WidgetsFlutterBinding.ensureInitialized();
  LocaleSettings.setLocale(AppLocale.zhHans);

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])
      .then((_) async {
    StartupPerfLog.mark('orientation_ready');
    ApiClient.onAuthExpired = SessionExpiryService.instance.handleExpired;
    ApiClient.onAccountDisabled =
        SessionExpiryService.instance.handleAccountDisabled;
    SessionManager.instance.onSessionInvalidated =
        SessionExpiryService.instance.handleImSessionInvalidated;
    // 节点选择须在首次 Dio 请求前恢复，否则会打到编译期默认域名。
    StartupPerfLog.mark('node_hydrate_start');
    await ApiNodeService.instance.hydrate();
    StartupPerfLog.mark('node_hydrate_done');
    StartupPerfLog.mark('api_bootstrap_start');
    await ApiClient.instance.bootstrap();
    // 版本检测属于启动能力，独立于登录链路；失败不阻塞首屏。
    unawaited(StartupVersionCheckService.instance.check());
    // 注册 App 前后台切换监听：恢复前台 + 距上次成功 >1h 时自动重拉
    StartupVersionCheckService.instance.attachLifecycleObserver();
    StartupPerfLog.mark('api_bootstrap_done');
    if (!kIsWeb) {
      StartupPerfLog.mark('splash_prepare_start');
      await SplashConfigService.instance.prepareForLaunch();
      StartupPerfLog.mark('splash_prepare_done');
    }
    if (IMDemoConfig.selfHostedPushEnabled && PlatformUtils().isIOS) {
      StartupPerfLog.mark('apns_install_start');
      // 不阻塞冷启动：APNS install 约 1.2s，后台执行。
      // push 回调通过 NotificationSettingsService.instance.handleVoipPushPayloadForBootstrap
      // 异步接收，对冷启动体验无影响。
      unawaited(IosApnsPushService.instance.install(
        onVoipPush: NotificationSettingsService
            .instance.handleVoipPushPayloadForBootstrap,
      ));
      StartupPerfLog.mark('apns_install_done');
    }
    StartupPerfLog.mark('platform_bridges_start');
    UikitPermissionBridge.install();
    DeviceSyncService.installPermissionHooks();
    UikitMediaUrlBridge.install();
    DesktopMediaPopout.install();
    UikitAddFriendBridge.install();
    UikitSelfHostedFriendBridge.install();
    UikitVoiceToTextBridge.install();
    UikitSelfHostedGroupBridge.install();
    StartupPerfLog.mark('platform_bridges_done');
    installForwardPickPages();
    // IMP(ArchiveRegister)：注册 3 个 UIKit 委托到本地自建后端实现。
    // 必须在 ApiClient.bootstrap 之后、runApp 之前调用。
    installBackendServices();
    // 主动预热 msg_history DB（避开首次进入聊天页时的 ~74ms sqflite open 开销）。
    _warmupMessageCoverageStore();
    // 主动预热 msg_media DB（避开首次进入聊天页时的 PRAGMA 异常同步栈 trace 阻塞 paint）。
    unawaited(MessageMediaMetadataStore.warmUp());
    final localSetting = LocalSetting(autoLoad: false);
    // 让 SDK 回调路径（无 BuildContext）在收到 onConnectSuccess /
    // onDisconnected 时也能同步 UI 状态。修复标题 stuck failed 的根因。
    ImConnectStatusService.instance.attach(localSetting);

    Future<void> finishDeferredBootstrap() async {
      StartupPerfLog.mark('deferred_bootstrap_start');
      // 进首页前最后一个 await 优化：
      // NetworkStatusService.start() 内做 `connectivity.checkConnectivity()` +
      // listen subscription，结果通过 ValueNotifier 异步推到 UI；首帧
      // 短暂显示 `unknown`，下一帧 connectivity 回调后切到正确值。
      // 所有读点（home_page / chat_connect_status_strip）用
      // ValueListenableBuilder 自动跟随 status 变化重建，无需在 start 完成
      // 后才 runApp。
      unawaited(NetworkStatusService.instance.start());
      unawaited(GroupNoticeUnreadService.instance.ensureLoaded());
      unawaited(GroupNoticeEntrySettingsService.instance.ensureLoaded());
      StartupPerfLog.mark('local_setting_load_start');
      await localSetting.loadSettingsFromLocal();
      // owner 已从本地设置恢复，此时明确等待代理入口快照灌入内存。
      // 聊天页随后同步 readCachedSync，首帧即可决定是否显示浮窗。
      await _warmupAgentRebateEntryStore();
      // 三公浮窗偏好同样在首帧前进入内存，避免先按默认位置/可见性
      // 绘制，再在 SharedPreferences 返回后跳动或消失。
      await GroupGamePrefs.instance.preload();
      await GroupLiveWatchFloatPrefs.instance.preload();
      // 决定三公入口是否存在的两份状态也必须在 runApp 前从本地恢复。
      // activateSession 内的网络刷新是 fire-and-forget，这里只等待本地读取。
      await Future.wait<void>([
        PrivilegedGameUserService.instance.activateSession(),
        SangongMyConfigService.instance.ensureHydrated(),
      ]);
      StartupPerfLog.mark('local_setting_load_done');
      InAppNotificationSound.soundIdResolver =
          () => localSetting.messageNotificationSoundId;
      InAppNotificationSound.soundEnabledResolver =
          () => localSetting.notifyMessageSound;
      NotificationSettingsService.instance.attach(localSetting);
      if (!kIsWeb) {
        await NotificationSettingsService.instance
            .ensureSelfHostedPushTapHandler();
      }
      final language = LocalSetting.normalizeLanguage(localSetting.language);
      localSetting.updateLanguageWithoutWriteLocal(language);
      LocaleSettings.setLocale(LanguageSwitchSheet.toAppLocale(language));
      StartupPerfLog.mark('deferred_bootstrap_done');
    }

    if (kIsWeb) {
      // Web：预热内置字体后再 runApp，避免首帧仍走 gstatic 回退。
      await _warmWebBundledFonts();
      StartupPerfLog.mark('run_app_start');
      runApp(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => LoginUserInfo()),
              ChangeNotifierProvider(create: (_) => DefaultThemeData()),
              ChangeNotifierProvider(create: (_) => CustomStickerPackageData()),
              ChangeNotifierProvider.value(value: localSetting),
              ChangeNotifierProvider.value(value: LoginCoordinator.instance),
              ChangeNotifierProvider.value(value: SessionManager.instance),
              ChangeNotifierProvider(create: (_) => UserGuideProvider()),
              ChangeNotifierProvider(create: (_) => PresenceProvider()),
              ChangeNotifierProvider.value(value: StarredFriendProvider.shared),
            ],
            child: const TUIKitDemoApp(),
          ),
        ),
      );
      StartupPerfLog.mark('run_app_returned');
      unawaited(finishDeferredBootstrap());
      return;
    }

    await finishDeferredBootstrap();
    if (Platform.isAndroid) {
      await AndroidPerformanceProfile.instance.initialize();
      configureImageCache();
    }
    StartupPerfLog.mark('run_app_start');
    runApp(
      // runAutoApp(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => LoginUserInfo()),
            ChangeNotifierProvider(create: (_) => DefaultThemeData()),
            ChangeNotifierProvider(create: (_) => CustomStickerPackageData()),
            ChangeNotifierProvider.value(value: localSetting),
            ChangeNotifierProvider.value(value: LoginCoordinator.instance),
            ChangeNotifierProvider.value(value: SessionManager.instance),
            ChangeNotifierProvider(create: (_) => UserGuideProvider()),
            ChangeNotifierProvider(create: (_) => PresenceProvider()),
            ChangeNotifierProvider.value(value: StarredFriendProvider.shared),
          ],
          child: const TUIKitDemoApp(),
        ),
      ),
    );
    StartupPerfLog.mark('run_app_returned');
    // 不阻塞冷启动：拉取/下载供下次 LaunchPage 使用（Web 无启动页，跳过）。
    if (!kIsWeb) {
      unawaited(SplashConfigService.instance.refreshInBackground());
    }
  });

  if (PlatformUtils().isDesktop) {
    doWhenWindowReady(() {
      const initialSize = Size(1060, 740);
      appWindow.minSize = const Size(880, 600);
      appWindow.alignment = Alignment.center;
      appWindow.size = initialSize;
      appWindow.show();
      appWindow.size = initialSize;
    });
  }

  // );
}

class TUIKitDemoApp extends StatelessWidget {
  const TUIKitDemoApp({super.key});
  @override
  Widget build(BuildContext context) {
    final themeModel = context.watch<DefaultThemeData>();
    return ValueListenableBuilder<bool>(
      valueListenable: LaunchSystemUi.startupPhaseListenable,
      builder: (context, _, __) {
        final systemOverlayStyle = LaunchSystemUi.overlayForApp(context);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: systemOverlayStyle,
          child: AppPrivacyCover(
            child: MaterialApp(
              navigatorKey: AppNavigator.key,
              title: '99chat',
              debugShowCheckedModeBanner: false,
              locale: TranslationProvider.of(context).flutterLocale,
              supportedLocales: LocaleSettings.supportedLocales,
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              themeMode: themeModel.materialThemeMode,
              theme: buildAppMaterialTheme(DefTheme.blueTheme, isDark: false),
              darkTheme:
                  buildAppMaterialTheme(DefTheme.darkTheme, isDark: true),
              home: const TencentChatApp(),
              routes: {
                '/homePage': (_) => const TencentChatApp(),
                '/login': (_) => const TencentChatApp(),
              },
              builder: (context, child) =>
                  AnnotatedRegion<SystemUiOverlayStyle>(
                value: LaunchSystemUi.overlayForApp(context),
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) =>
                      DeviceSyncService.instance.markUserActive(),
                  onPointerMove: (_) =>
                      DeviceSyncService.instance.markUserActive(),
                  onPointerSignal: (_) =>
                      DeviceSyncService.instance.markUserActive(),
                  child: BusinessSessionGuard(
                    child: AppMaterialAppBuilder(child: child),
                  ),
                ),
              ),
              navigatorObservers: [
                appRouteObserver,
                AppRouteLifecycleObserver(),
              ],
            ),
          ),
        );
      },
    );
  }
}

void _installWebErrorGuard() {
  if (!kIsWeb) {
    return;
  }

  final oldFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (_isKnownWebNoise(details.exception, details.stack)) {
      return;
    }
    oldFlutterError?.call(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    if (_isKnownWebNoise(error, stack)) {
      return true;
    }
    return false;
  };
}

bool _isKnownWebNoise(Object error, StackTrace? stack) {
  if (!kIsWeb) {
    return false;
  }

  final message = error.toString();
  final trace = stack?.toString() ?? '';

  // dio 4.0.6 web XHR adapter double-completes when connectTimeout is set.
  if (trace.contains('browser_adapter.dart') ||
      trace.contains('dio_fixed_browser_adapter_web.dart')) {
    if (message.contains('Future already completed') ||
        message.contains('Bad state') ||
        message == 'Error' ||
        message.startsWith('Error:')) {
      return true;
    }
  }

  if (message.contains('Assertion failed') &&
      trace.contains('mouse_tracker.dart')) {
    return true;
  }

  return false;
}

void configLoading() {
  EasyLoading.instance
    ..displayDuration = const Duration(milliseconds: 2000)
    ..indicatorType = EasyLoadingIndicatorType.fadingCircle
    ..loadingStyle = EasyLoadingStyle.custom
    ..indicatorSize = 38.0
    ..radius = 18.0
    ..progressColor = const Color(0xFF2B72FF)
    ..backgroundColor = Colors.white
    ..indicatorColor = const Color(0xFF2B72FF)
    ..textColor = const Color(0xFF111111)
    ..maskColor = Colors.black.withOpacity(0.18)
    ..boxShadow = [
      BoxShadow(
        color: Colors.black.withOpacity(0.12),
        blurRadius: 28,
        offset: const Offset(0, 14),
      ),
    ]
    ..userInteractions = true
    ..dismissOnTap = false
    ..customAnimation = CustomAnimation();
}
