# Android 日常使用性能审计
日期：2026-09-16

## 结论

100 个好友、20 个活跃群本身不应要求整份群成员常驻或每次进入重新扫描。当前代码已有分页、消息窗口、通知合并和缓存上限，但仍发现 **9 类应处理的性能问题**。优先处理 Android 系统通知主线程等待、大群单成员更新全量读取、扫码主线程图像处理；再处理启动图和群直播重复刷新。

本轮是检查与取证，没有修改业务实现。新增了两个可复现诊断文件和结果文件。本报告不等同于全功能真机认证，也不把“存在昂贵路径”直接等同于每次都会掉帧。

### 规模解释

- 基线：100 个好友，20 个活跃群，重点考察 6000 人群。
- 若 20 个群均为 6000 人，则理论上有 120000 条“群—成员关系”；这不是 120000 个不同用户，也不代表代码会自动加载全部关系。
- 只有在群成员已缓存、特定功能确实走全量路径时，才使用 6000 行放大计算。
- 消息频率、设备档位、刷新率和媒体比例尚未指定；不能仅从群数量推出 FPS、温度或耗电。

## 检查范围与证据

检查当前生产目录 lib、定制 UIKit，以及 Android 原生插件。检查了启动/恢复、会话列表、收发消息与历史窗口、群资料与成员、在线状态/好友、SQLite、媒体与扫码、通知、直播、红包/账单、朋友圈和后台工作门控。设置、通话、设备同步等做了结构性检查；未实际执行转账、发送消息、通话或改变手机账号数据。

GitNexus 已重新索引：2908 个文件，75288 个节点，174936 条边。索引包含备份目录；结论只采用当前生产文件。索引报告了超大文件跳过、动态调用遗漏和执行流截断，因此图查询是定位辅助，不能凭“零调用”证明没有风险；相应路径已以源码核对。Git 元数据不完整，不能给出基于提交的精确差异结论。

## 优先处理的问题

### 1. P1：系统通知在 Android 平台主线程等待头像，最长 12 秒

**触发**：实际走本地系统通知路径，尤其后台活跃群通知集中到达、头像下载慢或不可用时。

**证据**：普通 MethodChannel handler 直接调用 showChatNotification；内部每次创建单线程执行器，再立即调用 future.get(12, TimeUnit.SECONDS)。把下载提交到线程并没有消除调用线程的等待。头像连接/读取超时分别为 8/10 秒，未见跨通知头像缓存；新建执行器也没有显式 shutdown。

**影响**：平台 UI 与输入响应被网络耗时牵制，存在应用无响应风险；大量通知还有线程与重复下载开销。不是每条聊天消息都必然走此路径，也未在真机主动制造超时。

**建议**：立即用默认/缓存头像发布通知；后台共享有界执行器下载并按通知 ID 更新；合并同头像下载、限制图像解码尺寸、明确取消和关闭生命周期。

**验收**：离线、头像超时、100 条通知突发时，通知发布不阻塞平台主线程；后台任务数量有上限。

源码：[通知调用入口](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/android/app/src/main/kotlin/vip/ninechat/pro/notification/AppSystemNotificationPlugin.kt:42>)；[同步等待头像](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/android/app/src/main/kotlin/vip/ninechat/pro/notification/AppSystemNotificationPlugin.kt:288>)；[头像网络加载](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/android/app/src/main/kotlin/vip/ninechat/pro/notification/NotificationAvatarLoader.kt:11>)。

### 2. P1：更新一个群成员，先读取整个群成员表

**触发**：名片变化、角色变化、禁言事件；批量设置成员角色。

**证据**：patchUser 调用 readAll，再 indexWhere 找一个用户，最后 upsertMany 一条。TCP 的 member_profile_changed、member_role_changed、member_muted 都能进入这条路径。批量角色修改还先 readAll 一次，再对每个接受的用户调用 patchUser。

**放大**：本地缓存 6000 人时，单个修改转换 6000 条记录；修改 k 人约产生 (k+1) 次整群读取，而非只读目标 k 人。

**本机实验**：5 个有效样本的中位数：readAll 6000 行 10.374 ms；按 ID 读 1 行 0.460 ms；当前 patchUser 15.143 ms。SQLite FFI 的墙钟耗时包括异步数据库等待，不能说全部时间都阻塞 Android UI。

**建议**：按 owner/group/user 主键读取与更新；批量事件按用户去重后一次查目标集合、一次事务提交，保持既有会话/权威数据保护。

**验收**：6000 人群修改 1 人不解码其余 5999 人；批量修改不产生 k 次全表读取。

源码：[patchUser](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/services/group_local/group_member_local_store.dart:1251>)；[角色批量修改](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/services/group_local/group_membership_sync_service.dart:1448>)；[实时成员事件](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/services/group_local/group_membership_sync_service.dart:3179>)。

### 3. P1：相册扫码同时存在原生和 Dart 主线程图像处理

**触发**：从相册扫描大图；常规识别失败后进入灰度增强兜底。

**原生证据**：QrImageNormalizePlugin 的默认 MethodChannel handler 直接执行 decodeFile、Exif 旋转、缩放和 JPEG 压缩写文件，没有移交工作线程；默认允许规范化长边 4096。

**Dart 证据**：_writeEnhancedGrayJpeg 在 await 读文件后同步执行 decodeImage、grayscale、adjustColor、encodeJpg。方法声明 async 不会把这段 CPU 计算搬到另一 isolate。外层 timeout 也不能抢占已经执行中的同步计算。

**本机实验**：2048×1536 合成 JPEG 的同类增强链路，AOT 中位数 725.147 ms。只是 Windows CPU 微基准，不能换算为手机实际卡顿时长。

**建议**：原生解码移入有界后台执行器，Dart 增强移至 compute/Isolate 或统一原生处理；控制像素预算；超时后取消或丢弃后续结果并清理临时文件。

源码：[原生 normalize](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/android/app/src/main/kotlin/vip/ninechat/pro/qr/QrImageNormalizePlugin.kt:33>)；[Dart 灰度增强](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/utils/qr_gallery_decoder.dart:260>)；[调用与超时](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/utils/qr_gallery_decoder.dart:148>)。

### 4. P2：启动图每次校验完整解码，且冷启动等待它

**触发**：已有有效远程启动图缓存；或后台下载新的启动图。

**证据**：启动阶段 await prepareForLaunch；它读取缓存后调用同步 _passesIntegrity，执行 MD5（配置有时）和 img.decodeImage。宽高限制在完整解码之后检查。下载后的校验也复用此函数。

**本机实验**：1080×1920、约 247 KB 合成 JPEG，仅解码中位数 75.585 ms，不含文件 I/O 和校验。原图小于 1 MB 并不意味着解码便宜。

**建议**：首次下载时离线程完整校验；后续启动使用文件元数据/校验结果；确需校验时移出首帧关键路径，并先检查图像头与像素上限。

源码：[启动等待](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/main.dart:355>)；[缓存准备](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/services/splash_config_service.dart:35>)；[完整解码](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/services/splash_config_service.dart:214>)。

### 5. P2：无直播的群聊也轮询；不变状态仍触发聊天页 setState

**触发**：群聊页面驻留，直播状态没有变化。

**证据**：聊天页面启动 12 秒轮询。GroupLiveChatState.refresh 在 finally 无条件 notifyListeners；聊天页 _onGroupLiveStateChanged 直接 setState。外层 _loadGroupLiveCurrent 在 await 后做的指纹比较已经来不及阻止这次通知。

**放大**：单个驻留群聊约 300 次请求/小时以及对应无效通知；不是 20 个群必然各有一个计时器。

**复现**：新增诊断测试连续返回两次 active=false，实际发生 2 次请求与 2 次通知。

**建议**：在状态对象内部比较语义后再通知；顶栏单独监听；无活跃直播时降低轮询或按事件刷新；让各种入口共用请求去重。

源码：[状态刷新](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/services/group_live/group_live_chat_state.dart:41>)；[12 秒周期](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/chat.dart:373>)；[页面监听者](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/chat.dart:3896>)。

### 6. P2：红包成员、主播回显绕过有界成员窗口

**触发**：已缓存较大群成员列表后，首次打开该群红包成员选择；回显现有直播主播。

**证据**：WalletApi.getRedPacketMembers 调用 readAll 并转换全部记录；WalletStore._members 按群保留整个列表，没有成员条数/LRU 上限。直播 _seedAnchorFromSession 为查一个主播也调用 _loadLocalMembers → readAll。

**放大**：若逐个使用 20 个均已缓存 6000 人的群红包选择，理论可保留约 120000 个成员条目；实际取决于缓存与使用路径。普通聊天打开不等于触发此行为。

**建议**：红包选择使用分页和按需搜索；主播按单个 ID 查；成员缓存设会话隔离、TTL/LRU 与总条数预算。

源码：[红包读取](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/api/wallet_api.dart:1252>)；[红包成员缓存](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/pages/wallet/wallet_store.dart:91>)；[主播回显](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/pages/group_live/group_live_authorize_page.dart:120>)。

### 7. P2：在线状态缓存整表 JSON 重写，隐私补查逐用户请求

**触发**：通讯录/成员可见区域需要补齐在线隐私信息，或收到在线状态变化；长期浏览很多不同群成员后缓存扩大。

**证据**：_prefetchVisibility 单轮最多 40 人，逐人 await 隐私接口，每成功一人调用一次 mergePresenceVisibility。后者读取/解析整个 SharedPreferences JSON、合并一小条、重新编码写整个对象。lastSeen 使用相同整表读改写方式，未见持久缓存总容量或按时间清理。

**影响**：100 好友时 CPU 成本较小，但长期缓存数千群成员后，网络请求数和重复 JSON/平台写入放大。不能把本机 40 次累计耗时直接算成同一帧阻塞。

**本机实验**：模拟 40 次 JSON 整表合并，100 人约 0.793 ms，6000 人约 46.849 ms；不含 SharedPreferences I/O，生产中各次操作会被网络等待分开。

**建议**：优先使用批量在线状态返回的隐私字段；缺失部分合并补查；单写入队列、内存合并后批量落盘；增加总容量与过期清理。

源码：[逐人隐私加载](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/provider/presence_provider.dart:586>)；[整表 lastSeen 写入](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/services/contact_social_cache_store.dart:144>)；[整表隐私写入](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/services/contact_social_cache_store.dart:182>)。

### 8. P2：账单页全量缓存建组件、补资料请求跟随全列表

**触发**：账单历史累计较多、已缓存多页后再次打开页面。

**证据**：默认 getHistoryRecordsByFilter(page:0,size:20) 实际走 getLedgerAll，返回整个 scope 缓存并后台补分页（默认每页 100、最多 20 页）。页面 ListView(children: _buildGroupedChildren(list)) 预先创建所有记录的 Widget 配置；每次 build 还安排整列表资料补齐。缺少 payer 的红包记录逐订单请求详情。

**澄清**：已缓存时不会等全量网络才显示；ListView 仍可延迟布局，但上层 Widget 列表创建与资料扫描是全量的。

**建议**：分页查询本地账单与惰性分组 builder；资料补齐只覆盖可见记录，批量去重、限制并发和离页取消；后台补页遵守用户交互门控。

源码：[账单默认路径](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/api/wallet_api.dart:993>)；[缓存及后台补页](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/api/wallet_api.dart:651>)；[账单页面构建](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/pages/wallet/record/wallet_record_screen.dart:316>)；[逐订单补发红包人](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/lib/src/pages/wallet/record/wallet_record_screen.dart:438>)。

### 9. P2（依赖后端条件）：成员页管理员筛选失败时连续扫描普通成员

**触发**：后端 role 过滤没有生效，返回混合成员页。

**证据**：loadManagementMembers 发现第一页不满足角色过滤后进入 _collectMixedManagementPages，最多连续 40 页，每页 50。此工作发生在成员页/管理页，不是刚修复的资料页入口。

**影响**：可拉取约 2000 人的数据但 6000 人群仍不完整；到达上限后没有“管理成员不完整”的状态，容易将不完整结果当完整快照。既有请求成本，也有身份展示正确性风险。

**建议**：优先确认后端角色过滤契约；失败时明确不完整并提供重试，不自动遍历普通成员；如果确需兼容扫描，应可取消、低优先级并暴露分页/完整性状态。

源码：[筛选与扫描分支](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_group_profile_model.dart:1011>)；[40 页扫描](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_group_profile_model.dart:1142>)。

## 暂不作为高优先级结论的项目

- 原生 NativeMediaPreviewActivity 本地图片在 onBindViewHolder 中直接 decodeFile，远程使用无界缓存线程池且解码不采样，是潜在大图风险。但当前 Dart 生产代码未找到 NativeMediaPreviewBridge.open 调用者，所以未把它当作日常默认入口已经触发的问题。[原生图片加载](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/android/app/src/main/kotlin/vip/ninechat/pro/media/NativeMediaPreviewActivity.kt:274>)
- 成员搜索 SQL 使用 instr(lower(...))，群内模糊搜索需扫描候选数据；但 UI 已有 300 ms 防抖、每页 50 条、代次保护，不应误报为“每按键扫描 6000 人并渲染全量”。
- 收到新消息会摄取发送者公开资料，但桥接层已有内容相同跳过、每用户 2 秒限流，不能说每条消息必然写一次用户资料库。新发送者突发的批量写入仍值得 Profile 测量。
- 朋友圈使用 SliverChildBuilderDelegate 和受限缩略图解码；已看见保护，不直接判为全量渲染。
- Android 图片缓存按 memoryClass 分档，GroupMemberStore 当前有群/成员容量上限；这不能覆盖 WalletStore 等独立缓存。
- 通话时钟已局部刷新，设备照片同步有交互暂停和权限门控；没有证据把这些一概列为持续耗电根因。

## 真机只读快照：只能辅助定位

设备：连接的 Android 16 真机，应用版本 3.0.1，包标记 DEBUGGABLE。未确认该设备账号正好具备题设数据量，也未确认安装包与当前源码完全一致。未重装或操作业务界面。

- PSS 293849 KB，约 287 MiB；RSS 416728 KB，约 407 MiB。
- 系统 gfxinfo 累计 1466 帧，171 个 janky frames（11.66%），P95 53 ms。
- 这些是未清零、用户操作不受控的 Android 窗口累计统计，不是 Flutter UI/raster 帧时间分解，也不是本次题设场景测量。不能由此给出发布版“11.66% 掉帧”的结论或确定某条源码是根因。
- 现有 VM 采样脚本未找到名为 main 的 isolate，故没有可靠 Dart CPU/分配采样；未将错误值补为零。

原始聚合结果：[运行时快照](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/test_outputs/android-small-account-audit-runtime.json>)。

## 验证结果与缺口

选取 12 个现有性能/行为测试文件：**97 通过、6 失败**。另新增 **2 个诊断测试通过**，记录现状，不表示已修复性能问题。

失败项：

1. android_perf_p0_contract_test：源码字符串契约未匹配；包含换行/旧结构假设，不能直接证明重复去重仍存在。
2. low_end_performance_contract_test：folder_full_index 字符串未匹配。
3. 同文件：home_post_startup 字符串未匹配。
4. conversation_projection_coalescing_test：100 次 patch 的 contentRevision 期望合并一次，实际从 2 到 102；独立重跑可复现。当前 getter 已转发底层 store revision，内容变更与页面通知不是同一个指标。不能据此断言渲染了 100 帧；应改为统计实际通知、build 和投影耗时。
5. group_member_on_demand_test：将 3000 人塞进当前每群容量 256 的 LRU 后期待 user0017 仍存在，结果为空；夹具与新容量策略不一致，需重新验证真实按需补齐路径。
6. bounded_history_global_test：10000 条真实入站处理后，期待热缓冲 120 条，实际 0；需要厘清当前 SQL/热缓冲职责。该测试在此断言停止，不能声称它已经验证了后面的 durable count 和返回最新行为。

以上失败需要单独清理/排查；本轮不篡改断言来制造“全部通过”。

新诊断与结果：

- [Flutter 诊断测试](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/test/performance_small_account_audit_test.dart>)：6000 人 SQLite 对比与直播不变通知复现。
- [SQLite 结果](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/test_outputs/android-small-account-audit-sqlite.json>)。
- [AOT CPU 微基准](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/tool/perf_small_account_audit.dart>)。
- [CPU 结果](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/99999999/test_outputs/android-small-account-audit-host-cpu.json>)。

本机测试时间受 Debug/JIT/FFI、机器负载影响。CPU 微基准使用 Windows AOT，各 2 次预热、7 次取样；SQLite 为 Flutter 测试与 FFI，各 1 次预热、5 次取样。均不能外推 Android 实际帧率。

## 推荐修复顺序

1. 通知主线程等待；群成员点更新全表读取。
2. 扫码原生/Dart CPU 迁移，启动图离首帧校验。
3. 直播不变通知、红包/主播按需数据、在线状态合并落盘。
4. 账单分页与可见资料补齐；后端角色过滤和不完整状态。
5. 校正测试指标后做 Android Profile 真机场景验收。

## Android Profile 验收矩阵

必须在受控测试账号上验证，记录设备型号、内存档位、刷新率、包模式、数据规模、网络条件与消息速率。以下是计划场景，不是已经执行的压测。

| 场景 | 数据/操作 | 核心指标 |
|---|---|---|
| 冷启动/恢复 | 冷启动 10 次，后台 5 分钟后恢复 10 次 | 首个可交互帧、首屏数据就绪、UI/raster P50/P95/P99 |
| 会话列表 | 100 好友、20 群，持续快滑和切标签 | 每帧 build/raster、GC、请求数量、隐藏页面工作 |
| 活跃聊天 | 当前群聊天，其余群持续来消息；总速率 1/10/50 条每秒分别测 | 输入延迟、帧耗时、SQL 队列、未读正确性 |
| 历史回看 | 上翻历史期间持续来消息，再返回最新 | 窗口上限、滚动锚点、内存、未读/消息完整性 |
| 群成员 | 6000 人本地缓存，进出20次、滚动、搜索、成员变化 | 冷/热请求数，点更新读取行数，分页位置 |
| 图片/扫码 | 1080p 启动图、普通照片/长图、4096 边扫码 | 主线程连续 CPU、解码峰值、临时文件、取消行为 |
| 通知 | 头像缓存命中/离线/慢网；突发100条 | 平台主线程等待、执行器线程数、重复下载、通知及时性 |
| 红包/账单 | 大群选成员；有2000条历史账单 | 首屏构建数、后台请求、内存增长、离页取消 |
| 长时间使用 | 20 群轮换并混合图文，持续30–60分钟 | PSS趋势、活跃订阅/计时器/线程数、温度与帧率下降 |

60 Hz 一帧约16.7 ms，120 Hz约8.3 ms；应分别看 UI 和 raster 耗时，不能把数据库异步总耗时或 HTTP 延迟直接当作掉帧时长。

