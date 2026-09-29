# Android 后台更新实现与验证（2026-09-28）

实现：安卓发现新版本后交给系统 `DownloadManager` 在 Wi-Fi 或移动网络下载。传输与页面、Flutter isolate 和 App 进程解耦；App 在前台轮询完成状态，后台完成时保留系统通知，回到前台复查后弹出安装提示。安装仍由用户在 Android 安装器中确认。

## 关键行为

- 同版本请求合并；切换/撤回版本时取消旧任务并清除旧提示，旧异步结果不能覆盖新状态。
- 状态查询、安装及下载排队均有超时和锁释放；安装失败、权限拒绝、下载失败可在手动“检查更新”后重试。
- 安装前在后台线程确认文件非空、下载字节完整、APK 可解析、包名/版本号/构建号与服务器发布信息相符，且签名与已安装 App 兼容。只有验证通过才展示安装提示。
- `apkUrl`（可选）优先作为直链；旧 `downloadUrl` 如为 `.apk` 直链也可使用。旧 `https://down.99chat.vip` 网盘页改走已实测的 `https://image.99chat.vip/app-release.apk`，并带版本/构建查询参数隔离 CDN 缓存。其他网页地址继续走原有浏览器更新流程。
- 只清理自己创建的系统下载任务和私有安装包；不会删除其它下载。原有 iOS/Web 更新流程不变。

实现文件：`lib/src/services/app_update_service.dart`、`android_update_download.dart`、`android_update_prompt_service.dart`、`android/app/src/main/kotlin/vip/ninechat/pro/update/`、`android/app/src/main/AndroidManifest.xml`。

## 真实下载验证

- OSS 原站 `https://99chat-attachments.oss-cn-hongkong.aliyuncs.com/app-release.apk`：HEAD 和分段 GET 均为 HTTP 400，响应代码 `ApkDownloadForbidden`，提示需使用绑定 CNAME。
- 用户提供的 `https://image.99chat.vip/app-release.apk`：HEAD 200，分段 GET 206，`Content-Type: application/vnd.android.package-archive`；完整下载 350,324,280 字节。
- 完整文件 MD5 `743E6287319BB3B994C24318F5D7BFE9`，与 HTTP ETag 相符；SHA-256 `17AF7112DF7AE719BBECEF899720237012F1F597F4FC675AA0DC06B689D00ECA`。`apksigner verify` 成功。
- 文件包名 `chat.chat99.chatpro`，版本 `3.0.1`、构建号 `20`。初次验证时仓库是 `3.0.1+20`；用户随后要求将本地构建号调整为 19，以便测试 19 → 20 升级。
- 文件证书主体为 `CN=Android Debug`，SHA-256 `11a45a150c067c5e51a45354a914e7ef7722328be4b8ae1e9fa9a0045ef1f579`。本地生成的 19 号调试包使用同一签名，可作为测试升级源；如现网安装包使用不同签名，系统会拒绝覆盖安装。正式发版需使用与现网一致、长期保存的正式签名密钥。

## 检查结果

- Flutter 更新相关 5 个测试文件：58 项通过，包括并发、超时、后台恢复、权限拒绝、撤回版本、更新地址选择和旧版弹窗行为。
- Android/JUnit：21 项通过，其中新增 APK 包名、版本、签名与轮换策略测试 12 项。
- `:app:compileDebugKotlin` 与 `:app:testDebugUnitTest` 通过。新增 Dart 文件静态检查无问题；现有 `app_update_service.dart` 仍有一个旧的 `url_launcher` 依赖声明提示。
- 未在真实设备安装。19 号本地包与远端 20 号 APK 具备测试升级所需的版本差与匹配签名，但两者证书均为 Debug；正式上线前仍需按 Wi-Fi、移动网络、后台/杀进程、权限同意/拒绝、下载失败/重试完整验收，并确认现网签名兼容。未修改现网后台配置或发布安装包。

## 后续构建号调整

- 按用户要求将 `pubspec.yaml` 从 `3.0.1+20` 改为 `3.0.1+19`，保留原有其它依赖修改。
- `flutter build apk --debug --no-pub --target-platform android-arm64` 构建成功。`build/app/outputs/flutter-apk/app-debug.apk` 经 `aapt` 确认为 `chat.chat99.chatpro`、`versionName=3.0.1`、`versionCode=19`；`apksigner` 验证签名与远端 20 号 APK 相同。
- 没有在设备上执行降级、安装或升级。已有 20 号应用的设备通常不能直接覆盖安装 19 号包；测试应使用独立测试设备或隔离测试环境。

Android 依据：[DownloadManager](https://developer.android.com/reference/android/app/DownloadManager)、[FileProvider](https://developer.android.com/reference/androidx/core/content/FileProvider)、[后台启动 Activity 限制](https://developer.android.com/guide/components/activities/background-starts)。

## 19 号包仍跳外链：后续排查与修复

- 实测连接的手机已安装 `3.0.1` / 构建号 `19`。其日志显示版本检查访问 `https://apiios.99chat.vip/api/v1/platform/contact`。旧客户端代码将此接口的 `X-Client-Platform` 固定为 `iOS`；现在改为真实平台。接口的匿名 Android 请求（含 `X-App-Version=3.0.1`、`X-App-Version-Code=19`、`X-App-Channel=official`）返回 `1.0.0+1`、`OPTIONAL`、`https://99chat.com/download`。该下载地址当前重定向到 HTML 网页，不是 APK。手机请求另带 `X-Device-Id` 灰度标识，因此匿名响应不能证明手机当时收到完全相同的版本字段。
- 修复了两条路径：Android 版本检查使用 Android 发布通道；当后台仍下发旧版元数据时，仅对已校验的 `3.0.1+20` 公开 APK 使用内置发行信息。构建号已到 20、后台关闭更新或发布更高版本时都不使用该兜底。后台恰好下发 `3.0.1+20` 但仍给出已知网页地址时，也改为内部下载 APK。
- 版本检查增加了不包含下载 URL、令牌或设备 ID 的诊断日志：本地/远端版本、信息来源、发布策略、是否有 APK 直链。当前手机的更新偏好文件为空，没有正在恢复的应用自有下载任务。
- 修复后的相关 Flutter 测试 72 项通过；重新生成 `3.0.1+19` Android 调试包成功。包签名与已验证的远端 20 号 APK 相同，SHA-256 为 `AC1F5072F2112AF8CDE46E3887B255F6FD74540A4EF79AAE591A48CDDB29C162`。
- 修复包尚未安装到手机；手机继续运行旧 19 号包时仍会走旧逻辑。长期方案是把服务端 Android 发布配置改为真实 `version/build/apkUrl`，并使用正式签名发布 APK，不依赖内置 20 号兜底。
