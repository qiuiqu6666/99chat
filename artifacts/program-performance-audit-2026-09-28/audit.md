# 程序性能与稳定性深入排查

审计日期：2026-09-28（Asia/Taipei）。用户反馈重点：Android 最多，iOS 也有；启动、会话列表、聊天滚动、发图片。

**结论：当前代码中确实存在多个可以叠加的性能与恢复缺陷。最值得优先处理的是图片准备阶段的原尺寸内存峰值、聊天滚动的重复数据库确认、会话加载失去进展后的恢复缺口，以及消息洪峰中的无界待入队积压。** 小账号也可能遭遇启动/图片问题；大群、长聊天记录、离线消息多会放大另一些问题。

这里区分两种证据：诊断测试已复现的行为，以及当前源码/锁定依赖能确定、但尚未在受影响手机上测量的风险机制。测试中的虚拟时间、像素内存估算、桌面测试时长均不是手机实测性能。

## 优先处理的六条链路

| 优先级 | 场景 | 当前缺陷 | 用户可感知的结果 | 证据 |
|---|---|---|---|---|
| P1 | Android 发图片 | 压缩前先解码原始位图，准备并发固定为 2 | 多张大图时停顿、准备失败、内存压力 | 当前锁定 native 插件源码；未实测 OOM |
| P1 | 聊天滚动 | 无效已读确认被当作需要重新尝试，反复提交旧消息 ID | 滑动同时产生重复数据库事务 | 真实列表 + SQLite 诊断复现 |
| P1 | 会话列表 | 底层请求悬挂后，加载槽长期占用，再试仍加入旧 Future | 转圈、空列表/旧列表无法刷新 | 60 秒虚拟时间故障注入 |
| P2 | 恢复网络/离线消息洪峰 | 内部队列有限，但等待入队的闭包/Future 无上限 | 消息处理追不上时内存和等待时间累积 | 10,000 回调压力注入 |
| P1 | 启动 | 首帧前关键本地读取无可见失败恢复，多个非首屏预热串行等待 | 停在启动页、启动耗时随本地环境变化 | 安全存储异常/等待注入；启动顺序源码 |
| P1 | iOS 多图选择 | 相册返回 Dart 前已先导出、重编码整批图片 | 点完成后长时间无图片消息，多图内存峰值 | 当前锁定 iOS picker 源码；未真机压测 |

### 1. Android 图片压缩的限流位置太晚

[压缩调用](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/utils/chat_media_send_utils.dart:873>) 设置输出宽高和质量，但没有设置 `inSampleSize`。当前 `flutter_image_compress 2.5.1` 的默认值是 1；其 `flutter_image_compress_common 1.1.1` Android 实现先 `ARGB_8888 decodeFile`，然后缩放。OOM 后才 GC 并提高采样倍数重试。

[图片准备队列](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/data_services/message/outgoing_media_work_queue.dart:10>) 固定允许两张并行。按未压缩像素计算，12MP 一张约 45.8 MiB，48MP 一张约 183.1 MiB，两张 48MP 就约 366 MiB，还不包括缩放/旋转副本、编码缓冲和聊天图像缓存。输出缩小到 2560 并不限制最初解码的内存。

**建议**：先按目标尺寸计算 native 解码采样率，再按原始像素/设备预算控制并发。低内存设备的大图串行；保留 EXIF、HEIC、长图和清晰度验证。单纯调低 JPEG 质量解决不了前置位图分配。

### 2. 滚动会重复确认未匹配的旧消息

[列表](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart:5996>) 把阅读边界之后的整段旧消息放进确认队列；[返回处理](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart:6032>) 遇到合法的“没有匹配未读项”结果 `consumed=false` 时清掉去重签名。下一次滚动又能提交相同 ID。

[存储](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/history_window_store.dart:1683>) 即使最终没有匹配项，仍先加载状态并执行 SELECT/UPDATE。诊断在 100 条旧历史、1 条未进入阅读范围的新消息下，30 次小幅滚动产生 **43 次重复确认事务、3,483 个重复旧 ID**，剩余未读始终为 1。

合并复跑得到 38 次事务、3,078 个 ID；异步帧/数据库调度会影响具体次数，两次均确认同一重复工作机制。不能把该次数当作固定设备指标。

**建议**：区分成功但无变化、失败、所有者失效三种结果；无变化不撤销去重；在进入数据库前与待确认的消息集合求交集，避免确认整段旧尾部。修复时验证快速滚动、阅读窗口裁剪和跨账号保护。

### 3. 会话列表缺少悬挂请求的恢复出口

[ConversationTabStore](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_tab_store.dart:1038>) 合并同一次首屏请求本身是正确的，但等待 `_fetch` 的槽位没有应用级超时/失效恢复策略。诊断让一次 SDK 请求不返回，推进 60 秒后：`loading=true`，首轮没有完成；再次 `ensurePrimed` 仍只产生 1 次底层调用，继续等同一 Future。

这证明的是客户端对“底层不返回”的恢复缺口，并不能证明腾讯 SDK 在所有网络故障下都会永远不回调。普通完成的失败请求与真正悬挂不同。

**建议**：给 UI 等待和请求世代分别设置边界，允许用户看见缓存及恢复入口。超时后旧响应必须经世代检查才能提交，不能直接启动多个互相覆盖的请求。

### 4. 消息入口的等待队列实际没有内存上限

[ImMailboxRouter.dispatch](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/im_mailbox.dart:92>) 每次立即分配 Completer、保留事件并串接 `_admissionTail`。`maxQueuedEvents` 只限制内部 scheduler；超过上限的事件仍在等待入队链中保留。

诊断将内部队列上限设为 8、阻塞第一个处理器，并投入 10,000 个回调，仍得到 **1 个活动处理器、9,999 个待办**。单个处理器超时也只是完成调用方的错误 Future，不会取消真实工作。[详细调用来源和限制](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/program-performance-audit-2026-09-28/chat-audit.md>) 见聊天审计。

**建议**：把消息先可靠落盘，再以有界内存取批；对可以合并的状态事件只保留最新版本，消息内容本身不可直接丢弃。把“等待入队”也纳入积压指标和限额，并设计存储/处理停滞后的恢复流程。

### 5. 首屏前初始化失败，会停在用户没有恢复入口的位置

[移动端启动](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/main.dart:355>) 在 `runApp` 前等待节点偏好、已读屏障、安全存储、启动图和本地设置；随后还等待代理入口数据库、游戏/浮窗设置及平台初始化。Android/iOS 都在 `finishDeferredBootstrap` 完成后才运行应用。

[ApiClient.bootstrap/loadToken](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/api/api_client.dart:812>) 对安全存储读取没有本地恢复或超时处理。诊断注入读取异常，异常直接向外抛出；注入未完成读取，bootstrap 保持未完成，释放读取后才继续。外层 zone 仅报告错误，没有绘制失败/重试页面。[启动页 watchdog](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/app.dart:453>) 要等应用创建后才能生效，且本身只是观测日志。

**建议**：先建立可渲染的启动状态机，严格区分凭证状态未知、可离线使用和确实登出；对系统存储失败显示重试/恢复。代理/游戏/浮窗等可选预热挪到首屏后按需执行。不能为了启动快，在身份未确认时直接当作登录成功。

首屏前等待的总时间尚未真机测量；没有把每项本地读取都断言为独立瓶颈。SessionManager 现有 8 秒 UI 预算及登录单飞测试通过，这个预算覆盖不到 `runApp` 之前的上述阶段。

### 6. iOS 系统相册在应用限流之前已有整批媒体处理

[系统选择参数](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/utils/chat_gallery_pick_utils.dart:24>) 最多 9 项、未指定尺寸；[聊天发送入口](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_more_panel.dart:1750>) 等整个 picker Future 才进入占位/发送流程。

当前 `image_picker_ios 0.8.13+7` 会先关闭选择器，为结果建立异步保存操作，读取完整图片数据并转 JPEG/PNG，等待全部保存操作结束才回调 Flutter。该 operation queue 未设置应用级并发上限；`requestFullMetadata=false` 也没有跳过图片重编码。实际并发由系统调度，不能假定固定同时处理 9 张。

**建议**：把导出也纳入并发/像素预算，优先文件形式导出并避免重复编码；为云图片下载、文件准备、上传分别给出反馈。详见[媒体审计](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/program-performance-audit-2026-09-28/media-social-audit.md>)的精确插件路径。

## 其他常用区域

- **通讯录**：分批加载仍反复从有序 ID 表头跳过已处理项，再为新增好友线性找插入位置；大通讯录会累积重复扫描/复制。细节和规模边界见[通讯录/钱包审计](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/program-performance-audit-2026-09-28/contacts-wallet-audit.md>)。
- **搜索**：本地降级查询可能连续扫描大量历史，没有单次交互的总页数/耗时上限；旧本地查询缺少请求世代检查，页面清空/退出后仍会写回共享结果，后一问题已在真实搜索模型中复现。
- **钱包/红包**：WalletStore 的余额/支付方式缓存没有与账号和请求世代绑定。已复现清缓存后旧请求写回，以及旧强制刷新覆盖新余额。钱包流水加载中切筛选条件也会丢弃新请求，标签变了但仍显示旧条件结果。这是显示状态稳定性问题；本次没有证据表明发生了实际资金损失。
- **朋友圈/收藏大图预览**：当前图片缺 `sourceMessage` 尺寸时，预览降采样返回空目标，原 provider 被直接解码；列表缩略图本身已有尺寸限制，问题在打开的大图。
- **Android 相册返回恢复**：当前系统 picker 路径未读回插件的 lost-data 缓存。宿主进程在外部相册期间被系统回收后，已选图片没有应用恢复流程。需要持久化账号/目标并恢复待确认文件，不能恢复后自动发到另一聊天。
- **启动诊断缺口**：[StartupPerfLog](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/startup_perf_log.dart:33>) 的 `consoleLoggingEnabled` 只有 `kDebugMode`，而 Timeline 输出也放在该条件内；Profile 模式实际没有这些启动阶段输出，与注释和诊断目标不一致。审计期间另一个任务新增了聊天恢复日志，本报告没有把全程序断言为“完全没有日志”。

## 已排除的误判

- 当前聊天已有历史限窗、行复用、局部提交、后台停工和大量异步操作；没有把“全程序都在主线程同步运行”当作结论。
- 首页启动链虽然先等归档云同步，但当前可见会话 Tab 另有独立首屏投影路径，SessionManager 也有实时连接入口。不能断言一次归档请求必然堵死整个首页。
- 朋友圈列表缩略图、图片预取以及部分 Android 设备分档已存在，未重复报告为缺失。
- 未接入的 NativeMediaPreview 路径、非主流旧选择器路径没有被当作当前主要瓶颈。
- 现有测试中 3 个失败是旧源码字符串契约与当前实现不同，不据此宣称实际性能下降。

## 本次验证与运行证据

1. 现有性能/启动/生命周期相关回归：**71 项，68 通过、3 失败**。失败为 `android_perf_p0_contract_test` 的旧 dedupe 字符串和 `low_end_performance_contract_test` 的旧文件夹/首页调度字符串。完整日志：[baseline-tests.log](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/program-performance-audit-2026-09-28/baseline-tests.log>)。
2. 新增诊断只放在审计目录，用于断言当前缺陷，而非把缺陷当正确产品契约：启动 2 项、会话/入口队列 2 项、滚动数据库 1 项、钱包 3 项、搜索生命周期 1 项，共 **9 项复现断言通过**。其中前 8 项也进行了合并复跑，搜索验证在通讯录/钱包日志内。源码与日志均在本目录。
3. 对已连接 Android x64/API 28 环境中现有 `3.0.1+20` 进程只读采样：总 PSS **709,326 KiB ≈ 693 MiB**，Native Heap PSS **600,146 KiB ≈ 586 MiB**，窗口处于后台。说明该运行实例内存较高，不能凭单次采样证明泄漏，也不能归因到某个模块。该环境非目标用户真机基准，已安装包也未证明等同于当前未提交代码。
4. 该进程 crash buffer 无记录；不能据此排除历史闪退。`gfxinfo` 只有 2 帧且无法代表 Flutter 场景，不使用其中的 50% jank 数字作结论。

## 修复与验收顺序

先处理 **图片解码预算 → 滚动重复确认 → 会话加载恢复 → 消息积压控制 → 首屏启动状态机**。这几项分别覆盖内存、数据库操作放大、等待失去进展和启动失败；仅调整动画或缓存容量无法解决全部问题。

验收至少包含：低内存 Android 与普通 Android 各一台、iPhone 一台；启动冷/热缓存；弱网/断网恢复；100/1000/3000 条历史且有新消息时滚动；1/2/9 张 12MP/48MP 图片；相册期间宿主被系统回收。记录首屏可操作耗时、build/raster p95/p99、PSS/native heap 峰值、重复 ACK 数、待入队峰值和恢复耗时。原有日志或单元测试通过不能替代这组场景。

## 审计范围与可追溯性

- 工作区 HEAD：`0e7aa83bc5b096a99ff8bb424842404a3c901cb7`。开始时已有聊天恢复等未提交修改；审计期间另有任务修改 `main.dart` 并新增恢复日志。报告按最终复核的对应代码说明，未覆盖/回滚他人修改。
- 本审计没有修改产品源码、没有提交代码或部署。只新增审计报告、诊断测试、运行记录与外置索引。
- 已按 GitNexus 图优先流程定位，再逐行验证。初始 MCP 索引存在乱码/错误符号映射，因此未信任其“exact”标签。随后用 CLI 重建完整尺寸范围的索引（上限 2048 KiB，含大聊天文件），在 `D:/codex-task-cache/program-performance-audit-full-20260928` 成功生成 **76,209 节点、174,266 关系、654 流程**，索引时间 `2026-09-27T17:57:41Z`。MCP 仍读旧缓存时，最终复核使用该新索引的 CLI。
- 图分析器仍报告动态调用/跨语言及流程截断边界，空调用链不等于没有调用；最终结论以源码和诊断复现交叉验证。刷新日志：[graph-refresh.log](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/program-performance-audit-2026-09-28/graph-refresh.log>)。
- 主要覆盖客户端启动、列表、聊天、消息入口、媒体、通讯录、搜索及钱包状态；通话/设置仅有限抽查。没有线上服务端压测、受影响用户 trace、iOS 实机或 Android 真机长时间压力数据，不能把上述机制等同于所有反馈的唯一原因。
