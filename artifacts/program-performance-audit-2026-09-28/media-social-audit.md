# 图片/媒体与朋友圈性能稳定性只读审计

日期：2026-09-28。审计工作区：`C:\Users\ASUS\Downloads\Telegram Desktop\99999999`。未修改产品源码或已有文件。

用户补充后重点收敛到 Android / iOS 发图片、相册返回与图片预览。以下属于源码可证实的风险机制，不把内存估算当作真机测量，也不把所有用户反馈归因到同一个问题。

## 证据边界

- 已读 gitnexus-debugging 技能，先 `list_repos`，指定 `repo=99chat-unread-rebound` 查询及 context，再核对源码。
- 初始旧 MCP 索引出现 uid/路径异常，未作为证据。主代理已刷新为 `D:\codex-task-cache\program-performance-audit-full-20260928`，indexedAt `2026-09-27T17:57:41Z`（本地 9 月 28 日），76209 nodes / 174266 edges。随后通过指定该 storage 的 CLI context 复核：`sendImageMessage → prepareImageForChatSend`；`_MorePanelState._sendImageMessage → pickSystemGalleryMedia`；`_ImageScreenState._resolveImageProvider` 和 `_ChatMediaGalleryImagePageState._resolveImageProvider → wrapPreviewDecode`。返回正常完整 UID/路径，再以工作区源码确认行为。
- Native 插件证据来自本机 `.dart_tool/package_config.json` 对应 Pub Cache，版本与 `pubspec.lock` 一致：`flutter_image_compress 2.5.1`、`flutter_image_compress_common 1.1.1`、`image_picker_ios 0.8.13+7`、`image_picker_android 0.8.13+17`。这证明当前工作区解析的依赖行为，不保证线上已安装包包含相同构建。
- 主代理已有后台模拟器 PSS 约 693 MiB 的采样；不能凭该采样证明以下任意项已经发生、不能证明泄漏，模拟器也不作为真机性能基准。

## 1. P1：Android 图片压缩先解码整张原图，2 张并发可能产生数百 MiB 瞬时内存

**触发**：聊天一次发送多张高像素 JPEG/PNG（文件不足附件分流阈值、进入常规压缩分支），尤其低内存 Android 手机。48MP 照片即使压缩文件仅几 MiB，仍有 48M 像素。

**路径范围**：常规 `sendImageMessage` 压缩管线，系统相册、自定义相册、相机只要进入此分支都适用；GIF、小 JPEG 跳过压缩，超过附件分流阈值走 backend 的文件不属于这条压缩链。固定 2 并发是单个聊天准备队列，不代表进程所有图片工作最多 2 项。

**工作区证据**：
- `third_party/tencent_cloud_chat_uikit/lib/ui/utils/chat_media_send_utils.dart:873-882` 调用 `FlutterImageCompress.compressAndGetFile`，传入目标宽高、quality=88，却不传 `inSampleSize`。
- `third_party/tencent_cloud_chat_uikit/lib/data_services/message/outgoing_media_work_queue.dart:10` 的 `imagePreparation` 固定并发 2。
- `third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:6911-6919` 在该队列里执行压缩。

**当前依赖证据**（根目录 `C:/Users/ASUS/AppData/Local/Pub/Cache/hosted/pub.dev/`）：
- `flutter_image_compress-2.5.1/lib/flutter_image_compress.dart:97` 默认 `inSampleSize=1`。
- `flutter_image_compress_common-1.1.1/android/src/main/kotlin/com/fluttercandies/flutter_image_compress/handle/common/CommonHandler.kt:121-131` 以 ARGB_8888、给定 sample 完整 `decodeFile`，之后才调用缩放压缩。
- 同文件 `143-155` 在 OutOfMemoryError 后 `System.gc()` 并增加 sample 重试。缩放不是解码前的预算控制。

**因果**：限制输出 2560 边长并不限制最初的像素分配。12MP × 4 字节约 45.8 MiB；48MP × 4 字节约 183.1 MiB；两张 48MP 原始 bitmap 约 366 MiB，尚未包括缩放/旋转副本、编码数组、Flutter 图像缓存、聊天页面。后台线程仍会竞争内存带宽并引发 GC，低内存下可出现明显停顿、失败或被系统回收。

**可信度**：高（当前依赖实现与调用参数直接吻合）；真实峰值、失败率需真机压测。

**修复方向**：根据已读取的原图尺寸，在 native decode 前计算保留目标清晰度所需的 sample；给图片准备过程增加像素/内存预算，低端机大图串行，避免靠 OOM 后重试降采样。保留方向校正与长图清晰度验收。

## 2. P1：iOS 相册返回前先并发导出并重编码所有原图，应用的压缩队列尚未介入

**触发**：iOS 从系统相册选择多张大图或云端图片后点击完成。用户已看到相册退出，图片消息却还未出现。

**路径范围**：手机聊天更多面板的系统 `getMedia` 路径（当前默认）及使用同一 iOS image_picker 的入口；不是所有自定义 AssetEntity 相册导出路径。宽布局中的独立 custom picker 实现不能直接用这条机制解释。

**工作区证据**：
- `third_party/tencent_cloud_chat_uikit/lib/ui/utils/chat_gallery_pick_utils.dart:24-34` 系统选择允许 9 项，仅指定 `requestFullMetadata=false`，未指定 maxWidth/maxHeight。
- 同文件 `68-77` Android/iOS 常规聊天走系统 picker。
- `third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_more_panel.dart:1750-1766` 等待系统 picker 的整个 Future 完成，才释放 overlay 并调用消息占位/发送分发。

**当前依赖证据**（Pub Cache 根同上）：
- `image_picker_ios-0.8.13+7/ios/image_picker_ios/Sources/image_picker_ios/FLTImagePickerPlugin.m:475-529` 先 dismiss picker，再为每个结果创建异步 save operation，`NSOperationQueue` 未设应用级并发上限；Flutter 回调依赖所有 save operations 完成。
- 同目录 `FLTPHPickerSaveImageToPathOperation.m:95-109,128-144` 读取每张完整 NSData、构造 UIImage，随后保存图片。
- `FLTImagePickerPhotoAssetUtil.m:80-96` 每张都会执行 convertImage；`FLTImagePickerMetaDataUtil.m:75-94` 转 JPEG/PNG，即使 requestFullMetadata=false 也不绕开这步。

**因果**：在 Dart 的 2 张压缩队列前，已经发生一次多图原始解码/重编码；导出全部完成后才返回文件列表，随后 app 再次压缩。造成“完成后卡住一会儿”和多图内存峰值；云资源中的最慢一张还会延迟整批返回。requestFullMetadata=false 不等于原文件零拷贝。

**可信度**：高（当前锁定插件源码）；并发实际调度数由 OS 决定，不声称固定 9 张同时解码。

**修复方向**：将移动端 picker 导出改成有界并发的文件表示导出/流式结果，能复用原文件时避免先完整重编码；若先采用尺寸提示需用 HEIC、GIF、方向、长截图回归，不能只降低 JPEG quality。把“选中已接受”“云端下载”“准备”“上传”分开反馈，避免相册结束后全程无进度。

## 3. P2：朋友圈、收藏等无消息元数据的当前大图预览绕过了降采样保护

**触发**：Android/iOS 打开朋友圈/收藏中的高分辨率图、超长截图；以及任何以空 sourceMessage 调用 ImageScreen 的入口。相邻预热已经有界，本项针对正在显示的大图。

**证据**：
- `lib/src/pages/moments/moments_image_preview.dart:211-253` 用 originalPath 构造原始 CachedNetworkImageProvider / FileImage，ImageGalleryItem 与 ImageScreen 没传 sourceMessage，也没把 MomentAttachment 的宽高传入预算。
- `lib/src/pages/favorites/favorite_image_preview.dart:66-86` 同样调用 ImageScreen 而无 sourceMessage。
- `third_party/tencent_cloud_chat_uikit/lib/ui/widgets/image_screen.dart:1472-1486` 将空 message 传给 wrapPreviewDecode。
- `third_party/tencent_cloud_chat_uikit/lib/ui/utils/image_preview_resolution_utils.dart:430-437,1076-1090` 取不到宽高时变成 0；`940-942` 直接返回空 decode target；`1059-1073` 的 target.shouldResize=false 返回原 provider。
- `third_party/tencent_cloud_chat_uikit/lib/ui/utils/chat_message_preview_image_resolver.dart:516-529` 本地 FileImage 在 normal route 还会提前原样返回。

**因果**：标称的 40MP/长边限制依赖聊天 message 元数据；空元数据会退回无界原图解码。48MP 一张约 183 MiB 未压缩像素，超长图还可能超过纹理尺寸，导致打开迟缓、黑图或系统内存压力。

**可信度**：高（可直接跟踪 null → 0 → 无 ResizeImage）。不主张所有聊天气泡都会全尺寸解码；气泡和相邻图已有保护。

**修复方向**：未知元数据必须先按物理屏幕双边上限 decode，再异步解析真实尺寸；把媒体元数据参数独立于 V2TimMessage，朋友圈/收藏显式传尺寸。按缩放升级原图时仍遵守像素/长边预算。

## 4. P2：Android 系统相册返回的数据恢复缺口，进程被回收后所选图片静默丢失

**触发**：App 启动外部相册/相机后 Android 回收宿主进程（内存紧张、后台限制），用户完成选择回到被重建的 App。

**证据**：
- 当前聊天路径为 `chat_gallery_pick_utils.dart:28` 的 ImagePickerPlatform.getMedia，`tim_uikit_more_panel.dart:1751` 只等待当前进程 Future。
- 已在 `lib` 及 vendored UI kit 全部 Dart 文件检索 `retrieveLostData|getLostData|readLostData`，无恢复调用；GitNexus 对 `retrieveLostData` 查询也为空（不能仅依赖图空结果，已文本确认）。
- 当前 `image_picker_android-0.8.13+17/android/src/main/java/io/flutter/plugins/imagepicker/ImagePickerDelegate.java:986-999`：pending callback 不存在时，结果写入 cache.saveResult；只有正常 callback 存在才回传给 Flutter。

**因果**：进程重建后旧 Future 与临时会话目标均已丢失；插件虽缓存选图结果，App 没有读回机制，表现为相册完成后重启/图片没发。该项是系统回收后的恢复缺陷，不是“App 自己导致每一次进程回收”的证据。

**可信度**：高（恢复入口缺失）；需通过“选择器开启时杀宿主进程”验证用户体验，避免混用强制停止 App 的不同系统语义。

**修复方向**：启动/恢复时读回 lost-data，持久化发起前账户与会话目标；恢复后展示待确认文件，验证账号与目标再提交，不能把旧图自动发到当前打开的另一会话。

## 已排除或未升级为结论

- 朋友圈列表缩略图 `moments_media_thumbnail.dart:31-57` 已按显示框设置内存与磁盘尺寸，未将“列表全原图解码”当现存问题。
- 发送主链已有本地占位、2 张压缩并发、3 个媒体发送槽、文件头异步读、稳定路径避免重复复制、账号检查；不是“完全没有限流/全在 UI isolate 同步压缩”。
- `NativeMediaPreviewActivity.kt:277` 有同步整图解码，但当前 Dart 到 NativeMediaPreviewBridge 的业务调用未找到，因此未将未接入路径作为实际用户主因。
- 自定义相册旧路径有每张最长 3×20 秒重试，但 Android/iOS 当前常规聊天走系统相册；不把旧路径当主要发图路径。
- 相册全局 overlay 超时释放不完整有条件风险：45 秒 timer 仅解本地 busy，global overlay 在 action Future 最终返回前仍保持。若插件永不回调，会持续压制聊天 notify；普通慢选择最终返回会清理，缺少实际悬挂复现，暂列待故障注入验证而非已发生根因。
- 未做 iOS 设备实测；未进行通话压力测试。本轮通话仅初步扫描，不给出不受支持的“通话泄漏”结论。

## 建议验证顺序

1. Android 低内存真机发送 1/2/9 张 12MP 与 48MP JPEG，记录 native heap、PSS、GC、每阶段时长、首占位帧；对比预采样后结果。
2. iOS 选择 9 张本地高像素图，单独量“点击完成→Flutter收到列表”的时长与 memory footprint，再测含 1 张 iCloud 图片的组合。
3. 两平台打开收藏/朋友圈 48MP 和窄长图，确认首屏 decode 不超过屏幕预算且缩放升级仍有预算。
4. Android 外部相册停留时回收宿主进程，再完成选择；检查可恢复待发送项及会话隔离。
