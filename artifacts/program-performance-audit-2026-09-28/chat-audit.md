# 会话列表、聊天滚动与消息入口审计

审计日期：2026-09-28。当前工作区包含其他任务的未提交聊天修复，并且审计期间仍有诊断文件新增。本报告以报告生成前重读的源码为准；产品源码未修改，未访问用户账号或线上服务。文件指纹见 `chat-audited-source-hashes.json`。

优先处理 **旧历史滚动重复已读事务**，这是本轮已在真实生产列表和 SQLite 实现上复现的无效工作。会话首屏等待没有应用层截止时间、消息待准入队列没有内存上限，是两个独立的稳定性风险。以下优先级表示修复建议，不表示已经测得线上发生率。

## 1. P1：有新消息等待时，滚动旧历史会反复提交相同旧消息的已读事务

**触发条件**：正在查看与最新尾部存在间隔的旧历史，收到一条新消息；当前可见的旧消息并不是待消费的新消息。此时移动旧历史视口，甚至在相同阅读边缘附近轻微来回移动，也会触发。

**直接证据**：新诊断使用生产 `TIMUIKitHistoryMessageList`、生产 `TUIChatGlobalModel`、生产 `HistoryWindowStore` 和真实本地 SQLite；只注入历史 SDK 与简单固定高度消息气泡。在 100 条旧消息、一条新消息等待的情况下，30 次 1 像素交替滚动产生 **43 次重复 ACK 事务、3,483 个重复提交的旧消息 ID**，新消息仍未读，数量仍为 1。测试通过表示复现成立，不表示问题已修复。没有使用这些桌面测试耗时来推算手机 FPS。

- `third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart:6253`：滚动监听调度可见性确认。
- 同文件 `5952`：寻找阅读边缘时从整个内存窗口起点遍历；`5989`、`5996` 又遍历阅读边缘后的整个旧尾段，并全部加入待 ACK Map。
- 同文件 `6024`：每 120 个 ID 分批调用 `acknowledgeVisibleHistoryMessages`；`6032-6033` 在返回 `false` 时清空 `_visibleIncomingProgressSignature`。
- `third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_bounded_history.dart:887-896`：合法的“没有新 ID 被消费”也返回 `false`。UI 把正常无变化结果当成应重新采样，使原来的去重签名失效。
- `lib/src/services/history_window_store.dart:1666-1709`：无匹配仍进入写事务，检查 scope、读取状态、查询 ID，并执行一次无匹配 UPDATE。

**为什么会卡**：手势期间重复分配/遍历消息 ID，重复投递 SQLite 事务。长历史阅读窗允许达到 3,000 条（`chat_message_window_policy.dart:22`），重复尾段工作随窗口增长。它还会与新消息的持久化、历史分页竞争本地资源；低端 Android 更容易感知。代码机制与无效 SQL 已确认；具体真机帧耗时和线上贡献比例尚未测量。

**修复方向**：区分 `changed / noChange / stale / retryableFailure`；正常无变化应保留阅读签名。只提交本次新增越过的阅读边缘或尚未确认的消息 ID，且在账号、访问代次、历史窗口代次变化时失效。保留现有精确 ID、已读权限和生命周期隔离，不应简单跳过所有 ACK。

证据：`chat_scroll_ack_probe_test.dart`、`chat-scroll-ack-probe.log`。

## 2. P1：会话列表首屏/分页依赖的 SDK 请求可无限占用单飞状态，重进也只等待旧请求

**触发条件**：腾讯 SDK `getConversationListByFilter` 的 Future 长时间不返回，例如插件/原生会话库繁忙或 SDK 异常。不是声称 SDK 在正常网络下必然不返回。

- `lib/src/services/conversation_local/conversation_tab_store.dart:3087-3093`：直接 await SDK，未设置应用层截止时间。
- 同文件 `2856`：第一页与续页都等待 `_fetch`。
- 同文件 `2793-2801`：`_loadInFlight[type]` 只有请求结束后才在 finally 清除。
- 同文件 `1063-1075`：再次 `ensurePrimed` 只加入同一个 pending Future。请求未结束时，没有本层的失败状态或重新获取机会。
- `lib/src/chat_session/chat_session_controller.dart:526-537`：当前首屏明确不再使用应用 SQLite 镜像，而是等待 SDK 窗口。
- `lib/src/conversation.dart:1659-1669`：显示中的列表首屏走这条调用链。

**本地复现**：注入一个不结束的 SDK Future，虚拟推进 60 秒，再次调用 `ensurePrimed`。结果为 `calls=1 loading=true firstDone=false retryDone=false rows=0`。原 Future 完成后两次调用才同时结束。

**用户表现**：冷启动列表长时间空白/加载；如果在续页触发，则表现为后续会话迟迟不出现。这里是无结束等待，不是主线程同步阻塞。

**修复方向**：为页面等待建立明确预算和可恢复失败状态；超时后允许新一代读取且拒绝旧响应覆盖。SDK 操作自身未必可以取消，不能仅增加 `Future.timeout` 然后无限重复启动 SDK 请求，应同时约束在途任务和迟到响应。

**可信度**：应用层状态无法自行恢复已由虚拟时间测试确认；真实 SDK 是否/多久触发该分支，需要用户设备记录。本报告不把它写成所有启动都等待 60 秒。

证据：`chat_diagnostic_probes_test.dart`、`chat-diagnostic-probes.log`。

## 3. P2：消息队列只限制已准入部分，SDK 突发消息仍能无限保留在待准入链

**触发条件**：后台回前台、离线消息集中到达、活跃群消息突发；同一会话的处理速度暂时慢于回调速度。

- `lib/src/services/im/tencent_advanced_message_adapter.dart:317-330`：`onRecvNewMessage` 为同步 Dart 回调，调用 `_submitMessage` 后返回。
- 同文件 `870-871`：`_submit` 使用 `unawaited(_attemptSubmit(...))`。本应用没有把下游等待反馈到 SDK 回调生产速率。
- 同文件 `507-520`：普通 SDK 消息的在途 Future 还保留在 `_sdkRealtimePending`，仅对相同 ID 单飞，没有总数上限。
- `lib/src/services/conversation_local/conversation_sync_service.dart:880-881`：普通 SDK 消息进入 `_messageMailbox.dispatch`。
- `lib/src/services/im/im_mailbox.dart:97-101`：每次 dispatch 新建结果 Completer，递增 `_waitingAdmissions`，并把捕获整个 event/payload 的闭包接入 `_admissionTail`。
- 同文件 `102-105`：只检查内部 `_scheduler.queuedCount`，超出的事件仍保留在无上限的 Future 闭包链。生产默认值为 8 个 worker、4096 个已准入队列项（`47-49`），不是全部待处理事件上限。
- 同文件 `116-133`：30 秒 handler 超时只通知调用方，并不释放仍在执行的处理槽；这是避免并发写的必要保护，也意味着没有真实结束的工作不会因为这个计时器而疏通队列。

**本地复现**：将可配置已准入上限设为 8，模拟同一会话 10,000 条回调并暂缓第一个 handler，观察到 active=1、retainedPending=9,999。释放 handler 后全部完成。现有 `test/chat_runtime_ingress_order_test.dart:151` 也以 maxQueued=1 / 1000 条验证保留 999 条，说明当前语义就是保存到外层等待区。

**影响**：内存中的 event、消息对象和 Future 数量仍按积压消息数增长；低内存设备可出现 GC 增多、长尾排队和闪退风险。并未在手机上复现 OOM，不能称为已确认的线上崩溃原因。原生 SDK 内部是否另有节流未验证；可以确认的是本应用 Dart 回调没有 await 下游准入。

**修复方向**：给外层准入也建立内存预算；普通可从 SDK 历史恢复的消息可以合并为会话脏标记/恢复水位，业务命令必须先保证持久化再释放对象。把已准入、等待准入、最老等待时长同时纳入诊断；处理超时要能恢复实际资源，保留同会话顺序及写入互斥。

证据：`chat_diagnostic_probes_test.dart`、`chat-diagnostic-probes.log`。

## 范围、已排除项与限制

- 已读：会话首屏、typed SDK 窗口/单飞、列表行复用和后台隐藏门控、消息入口/队列/持久化协调、实时收消息、聊天历史内存窗、滚动可见性与精确已读、部分历史合并去重和重试。
- 未把已经存在的有界历史窗、会话行复用、头像缓存分级、普通收消息绕开 durable Inbox、显示缓存优化重新列为缺失。
- HomeBootstrap 等待归档云拉取并不必然堵住显示 Tab 的首屏：`conversation.dart:1305` 独立启动首屏恢复；`1666` 直接调用 restoreProjection。`archivedConversationPersistToDisk=false` 时 controller `530` 的磁盘归档等待也不会执行。实时服务启动顺序由主审计另行评估。
- `android_perf_p0_contract_test.dart` 要求旧源码字符串 `if (_listHasCorrelatingDup(sorted))`。当前展示投影采用 authoritative window；该字符串消失不能单独证明退化。
- 3 个诊断测试通过；执行的是本地注入 SDK + 本地 SQLite/虚拟时间，不是线上压力测试。没有 Android/iOS profile/release 真机 frame timeline、内存快照、ANR、原生 SDK 长任务日志。发送图片由同组媒体审计负责。
- Graph first：先使用旧图导航，再用主代理新生成图复核核心符号。新索引位于 `D:/codex-task-cache/program-performance-audit-full-20260928`，indexedAt=`2026-09-27T17:57:41Z`。图正确定位 `_drainVisibleIncomingProgress`、`acknowledgeVisibleHistoryMessages`、`ConversationTabStore._fetch`、`ImMailboxRouter.dispatch`；Dart callback/extension 仍有不完整或错误解析，跨文件关键边已由当前源码和真实调用测试验证，未将空 processes 当成无人调用的证据。
