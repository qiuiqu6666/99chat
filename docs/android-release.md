# Android 发布包

默认发布 ARM64 APK。需要兼容 32 位 Android 时，额外生成 ARM32 APK，按设备架构分发。不要把所有架构装进同一个 APK。x64 主要供模拟器验证使用。

## Windows 打包入口

在项目根目录执行：

```powershell
./tool/build_android_release.ps1
# 同时生成两个独立 APK：
./tool/build_android_release.ps1 -Architectures arm64,arm32
# Flutter 不在 PATH 中时：
./tool/build_android_release.ps1 -Flutter E:/flutter/flutter/bin/flutter.bat
```

可通过 `-DartDefine @('KEY=value')`、`-DartDefineFromFile path/to/config.json` 传入现有构建配置。不要在版本库中提交密钥。

脚本会检查生成的 APK：必须只包含指定架构，必须包含 Flutter 引擎和应用库，构建元数据版本必须与 `pubspec.yaml` 一致，并且不能重新打入已移除的可变字体。任一检查失败即报错，不应发布该 APK。

各架构保持相同构建号，例如 `3.0.1+21`。已覆盖 Flutter 默认给分架构 APK 添加的 `1000/2000/3000` 偏移，避免以后切回单包时被系统判断为降级。

输出：

- ARM64：`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- ARM32：`build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`

## 其他系统或直接使用 Flutter

```sh
flutter build apk --release --split-per-abi --target-platform android-arm64
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
```

不拆包时，Gradle 默认将 release 限制为 ARM64；显式传入单个 `android-arm` 或 `android-x64` 目标也会使用对应架构。分架构打包时不再额外限定 ARM64，避免 ARM32 包缺少原生库。`flutter build appbundle` 也不受单 APK 默认架构限制，继续由应用商店按设备分发。

## 体积与回归

- release 开启 R8 代码裁剪和 Android 资源裁剪；腾讯 SDK 的 JNI 保留规则在 `android/app/proguard-rules.pro` 中。
- 中文字体保留 Regular、SemiBold、Bold。移除了没有界面引用的 Variable 字体打包声明及网页端预加载，源字体文件仍保留在仓库中。
- 录音转码、WebRTC 通话、IM、播放器和扫码依赖仍然保留。
- 发布前至少检查冷启动、登录、消息收发、录音发送、通话、扫码和视频播放。构建通过不能替代这些真机回归。
- 体积应以本次新生成 APK 为准，不能读取旧 `app-release.apk` 来判断分架构构建结果。

参考：[Flutter Android 发布](https://docs.flutter.dev/deployment/android)、[默认 ABI 过滤行为](https://docs.flutter.dev/release/breaking-changes/default-abi-filters-android)。
