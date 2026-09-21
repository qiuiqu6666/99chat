class IMDemoConfig {
  /// 仅作 IM SDK 冷启兜底：正式环境应以后端 UserSig 返回的 `sdkAppId` 为准。
  static const int sdkAppID = 1600155864;

  static const String appName = '99chat';
  static const String androidApplicationId = 'vip.99chat.pro';
  static const String iosBundleId = 'vip.99chat.pro';
  static const String iosVoIPBundleId = 'vip.99chat.pro.voip';
  static const String appVersion = '1.0.0';
  /// 分发渠道，用于 `GET /api/v1/platform/splash?channel=...`。
  static const String appChannel = String.fromEnvironment(
    'APP_CHANNEL',
    defaultValue: 'official',
  );
  static const double appBarTitleFontSize = 17;

  /// 五个主 Tab 顶栏大标题（消息 / 群聊 / 通讯录 / 钱包 / 我的）。
  static const double mainTabAppBarTitleFontSize = 22;
  static const double mainTabAppBarTitleFontSizeDesktop = 20;

  /// App/桌面默认主服务。Web：本地 run 默认用此地址；release 打包默认同源
  ///（见 [ApiClient.resolveBaseUrl]）。可用 `--dart-define=API_BASE_URL` 覆盖。
  /// 与 [ApiNodeService] 唯一启用节点（CN）保持一致。
  static const String smsLoginHttpBase = 'http://119.28.179.146:8081';

  /// 三公 HTTP 覆盖地址（可选）。默认使用主服务 `${smsLoginHttpBase}/sangong`。
  /// 也可用 `--dart-define=SANGONG_HTTP_BASE=...` 覆盖。
  static const String sangongGameSettingsHttpBase = String.fromEnvironment(
    'SANGONG_SETTINGS_HTTP_BASE',
    defaultValue: '',
  );

  /// @Deprecated 已废弃：管理鉴权改为主服务 JWT，不再使用 X-Settings-Key。
  static const String sangongSettingsWriteKey = String.fromEnvironment(
    'SANGONG_SETTINGS_WRITE_KEY',
    defaultValue: '',
  );
  /// 业务实时 TCP 地址。`https` 走 TLS，`http`/无 scheme 走明文。
  /// 可用 `--dart-define=REALTIME_TCP_BASE=...` 覆盖。
  /// 与 [ApiNodeService] 唯一启用节点（CN）保持一致。
  static const String realtimeTcpBase = String.fromEnvironment(
    'REALTIME_TCP_BASE',
    defaultValue: 'http://43.154.162.29:8082',
  );

  /// 当 [realtimeTcpBase] 未带端口且非 https 时的默认端口。
  static const int realtimeTcpPort =
      int.fromEnvironment('REALTIME_TCP_PORT', defaultValue: 8082);
  static const String defaultRegisterAvatarUrl = '';

  /// 平台支付助手真实 IM UserID：昵称为「99Pay支付助手」。
  static const String platformOfficialAccountId = '99Chat';
  /// 仅作占位；展示名一律以 IM 真实 nickName / 会话 showName 为准，前端不写死。
  static const String platformOfficialAccountName = '99Pay支付助手';
  static const String platformOfficialAccountFaceUrl = '';

  static const String systemWelcomeAccountId = '';
  static const String systemWelcomeAccountName = '';
  static const String systemWelcomeAccountFaceUrl = '';

  /// 平台消息账号真实 IM UserID。
  static const String cloudOfficialAccountId = '99Messenger';
  static const String cloudOfficialAccountName = '99Messenger';
  static const String cloudOfficialAccountFaceUrl = '';

  static const List<String> customerServiceUserList = <String>[];

  /// 仅在「选择联系人/会话」类入口隐藏的系统账号 UserID（区分大小写）。
  /// 不影响会话列表与消息列表的展示。
  static const List<String> hiddenPickerUserIds = <String>[
    '99Chat',
    '99Messenger',
  ];

  /// 在消息列表与聊天页恒显示「在线」并在昵称后加认证 V 徽章的账号（区分大小写）。
  /// 须填 IM 真实 userID；展示昵称（如「99Pay支付助手」）仅作兼容匹配。
  static const List<String> verifiedBadgeUserIds = <String>[
    '99Chat', // 支付助手会话真实 userID（昵称多为「99Pay支付助手」）
    '99Pay支付助手', // 兼容：误把昵称当 userID 的环境
    '99Messenger',
  ];

  /// IM 控制台 iOS APNs BusinessID（Debug/开发证书）
  static const int apnsCertificateIDDebug = 17535;

  /// IM 控制台 iOS APNs BusinessID（Release/生产证书）
  static const int apnsCertificateIDRelease = 17535;

  static const int voipCertificateID = 17536;

  /// Android 离线推送：极光 AppKey。
  /// 生产环境建议通过 --dart-define=JPUSH_APPKEY=xxx 注入，
  /// Android Manifest 占位符同名从 local.properties / 环境变量读取。
  static const String jpushAppKey =
      String.fromEnvironment('JPUSH_APPKEY', defaultValue: '');

  static const String jpushChannel =
      String.fromEnvironment('JPUSH_CHANNEL', defaultValue: 'developer-default');

  static const bool androidJPushEnabled =
      bool.fromEnvironment('ANDROID_JPUSH_ENABLED', defaultValue: true);

  /// JPush 唤醒：不接厂商通道时建议开启，提高 App 被杀后的推送送达率。
  static const bool androidJPushWakeEnabled =
      bool.fromEnvironment('ANDROID_JPUSH_WAKE_ENABLED', defaultValue: true);

  static const bool androidJPushAutoWakeupEnabled =
      bool.fromEnvironment('ANDROID_JPUSH_AUTO_WAKEUP_ENABLED', defaultValue: true);

  /// Android 合规保活：仅使用系统认可的前台服务，
  /// 不做无通知后台常驻、不做双进程守护。
  static const bool androidKeepAliveEnabled =
      bool.fromEnvironment('ANDROID_KEEP_ALIVE_ENABLED', defaultValue: true);

  /// 登录后引导用户关闭电池优化（国产 ROM 后台推送依赖此项）。
  static const bool androidBatteryOptGuideEnabled =
      bool.fromEnvironment('ANDROID_BATTERY_OPT_GUIDE_ENABLED', defaultValue: true);

  /// 自建系统 Push（APNs / 极光 + /me/push-token），不依赖腾讯 IM offline push。
  static const bool selfHostedPushEnabled =
      bool.fromEnvironment('SELF_HOSTED_PUSH_ENABLED', defaultValue: true);

  /// 腾讯 IM 语音转文字语言（仅 `VOICE_TO_TEXT_PROVIDER=tencent` 时本地录音转写生效）。
  static const String voiceToTextLanguage =
      String.fromEnvironment('VOICE_TO_TEXT_LANGUAGE', defaultValue: '');

  /// 本地录音松手转文字提供方：`xfyun`（默认，讯飞流式听写）或 `tencent`。
  /// 已发送语音长按转文字固定走 Deepgram。
  static const String voiceToTextProvider =
      String.fromEnvironment('VOICE_TO_TEXT_PROVIDER', defaultValue: 'xfyun');

  /// [Deepgram](https://developers.deepgram.com/) API Key（已发送语音长按转文字）。
  /// 生产环境建议通过 --dart-define=DEEPGRAM_API_KEY=... 注入。
  static const String deepgramApiKey = String.fromEnvironment(
    'DEEPGRAM_API_KEY',
    defaultValue: '2a07be7e0a788591d3726b22fbdaaeef9946c2f0',
  );

  /// Deepgram 模型，默认 nova-2。
  static const String deepgramModel =
      String.fromEnvironment('DEEPGRAM_MODEL', defaultValue: 'nova-2');

  /// Deepgram 语言代码；空字符串表示自动检测。中文可设 `zh`。
  static const String deepgramLanguage =
      String.fromEnvironment('DEEPGRAM_LANGUAGE', defaultValue: 'zh');

  /// 讯飞开放平台应用凭证（[语音听写流式](https://www.xfyun.cn/doc/asr/voicedictation/API.html) +
  /// [录音文件转写](https://www.xfyun.cn/doc/spark/asr_llm/Ifasr_llm.html)）。
  /// 生产环境建议通过 --dart-define 注入，勿提交到仓库。
  static const String xfyunAppId =
      String.fromEnvironment('XFYUN_APP_ID', defaultValue: '418714d6');
  static const String xfyunApiKey =
      String.fromEnvironment('XFYUN_API_KEY', defaultValue: '5f8ffacf161194ad3c9d42908753a226');
  static const String xfyunApiSecret =
      String.fromEnvironment('XFYUN_API_SECRET', defaultValue: 'ZWE1YjIxMzE2NWY1ZjE0MDM1MWE3Mjcy');

  /// 讯飞流式听写：zh_cn / en_us 等。
  static const String xfyunIatLanguage =
      String.fromEnvironment('XFYUN_IAT_LANGUAGE', defaultValue: 'zh_cn');

  /// 讯飞流式听写方言：mandarin 等。
  static const String xfyunIatAccent =
      String.fromEnvironment('XFYUN_IAT_ACCENT', defaultValue: 'mandarin');

  /// 讯飞录音文件转写语种：autodialect / autominor。
  static const String xfyunFileLanguage =
      String.fromEnvironment('XFYUN_FILE_LANGUAGE', defaultValue: 'autodialect');

  /// 腾讯云直播 Licence（V2TXLivePlayer ≥ 10.7 必填）。
  /// 默认已内置；仍可用 `--dart-define=TENCENT_LIVE_LICENCE_URL/KEY` 覆盖。
  static const String tencentLiveLicenceUrl = String.fromEnvironment(
    'TENCENT_LIVE_LICENCE_URL',
    defaultValue:
        'https://1464538038.trtcube-license.cn/license/v2/1464538038_1/v_cube.license',
  );
  static const String tencentLiveLicenceKey = String.fromEnvironment(
    'TENCENT_LIVE_LICENCE_KEY',
    defaultValue: 'a6101a518beec2da64738a996f47c676',
  );
}

/// 聊天气泡/预览使用的视频引擎（灰度开关，见迁移计划 P1–P3）。
enum ChatVideoEngine {
  /// [awesome_video_player] — 替代 better_player_plus，默认。
  awesome,

  /// 纯 [video_player] + 自研缓存（P2）。
  unifiedVideoPlayer,

  /// unifiedVideoPlayer + fvp 后端与图集 Player 池（P3）。
  unifiedWithFvp,
}

class ChatVideoFeatureFlags {
  ChatVideoFeatureFlags._();

  static const ChatVideoEngine engine = ChatVideoEngine.awesome;

  /// 图集视频是否使用 Player 池（P3，默认关闭）。
  static const bool useGalleryVideoPlayerPool =
      bool.fromEnvironment('USE_GALLERY_VIDEO_PLAYER_POOL', defaultValue: false);
}
