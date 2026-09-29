**A 包：首屏调用、等待关系与原始日志现状**

本包对应 2026-09-25 当前工作树。上一轮审计记录的 10 个关键文件 SHA-256 全部未变化。本包覆盖的 38 个相关文件也已在提取后重新核对原文件哈希。它是当前代码证据包，不是性能优化后的实现。

[完整方法与类型源码](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-evidence-ab-2026-09-25/A-source-complete.md>) · [所有摘录的位置与哈希](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-evidence-ab-2026-09-25/source-manifest.json>) · [await/定时器逐行索引](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-evidence-ab-2026-09-25/A-await-timer-inventory.csv>)

**先给可以确定的结论。**

1. 普通移动会话列表打开有 list、route、chat_init 三个 prepare 调用来源；这证明存在多次 prepare 入口，不能据此直接断言发生三次 SDK 读取。GlobalModel 的 hydrate、peek local phase、H0 和 reset 各有复用机制，需要实测实际读取次数。
2. 导航前默认最多等待本地 hydrate Future 100ms；缓存命中不会固定等满 100ms。该 timeout 不是整个点击处理函数的硬上限，也不取消已发出的 SDK/数据库工作。
3. prepare 的重连 reset 分支和 H0 修复分支不等待云端完成再 push；缺少可展示窗口时，首条正确消息仍可能依赖云端结果。页面壳首帧与首条消息可见必须分别计时。
4. app 层 history gate 包装直接返回原聊天组件。因此 900/1200/400/300ms 不能相加为“页面固定黑屏/不能交互时间”。
5. 当前主要打开日志在 Profile 下关闭，Pipeline 输出也关闭；未找到合格的真机 Profile 原始记录。
6. 现有 ChatOpenPerf 的起点不覆盖会话点击的全部前置同步工作；直接从资料/推送等入口打开时，未见公共入口建立新的 beginOpen。
7. 后置调度器的 background 任务在 interacting 状态仍被允许运行。这与“交互时暂停可延后任务”的目标存在策略差异，但不能仅凭此证明它已经造成卡顿。

**A1．调用链与直接调用方**

普通移动会话列表路径：

~~~text
_ConversationState._handleOnConvItemTaped
  ├─ 设置 _openingConversationID（列表自己的导航门禁）
  ├─ pause coverage repair / viewport warm
  ├─ ChatPipelineClock.start（时钟启动，输出开关关闭）
  ├─ await clearLocalForOpenFast
  ├─ ChatOpenPerfLog.beginOpen（比点击入口晚）
  ├─ unawaited prepareOpenViewport(source=list)
  └─ await openOrReuseAppChat
       ├─ activeRoute 查询
       ├─ await prepareOpenViewport(source=route)
       └─ Navigator.push → Future 等待页面退出
            └─ Chat.initState
                 ├─ page scope / viewport attach / identity
                 ├─ unawaited prepareOpenViewport(source=chat_init)
                 ├─ _startOpenHistoryGate
                 ├─ TIMUIKitChat localOnlyInitialOpen
                 │    └─ _loadData / join hydrate / 必要的 local fallback
                 ├─ _scheduleDeferredHistoryVerification（post-frame）
                 └─ _schedulePostOpenTasks（转场完成后）
~~~

最后的 await openOrReuseAppChat 是“打开到页面退出”的调用契约，不能把它的总耗时当作打开延迟。嵌入式聊天通过 onConversationChanged 切换，没有同样的 Navigator.push 路径。搜索锚点有专用路径，不能与普通最新窗口统计混在一起。

| 入口/方法 | 直接调用来源 | 作用 |
|---|---|---|
| prepareOpenViewport | 会话列表点击、公共路由、Chat.initState | 分类并锁定首窗；可能启动 hydrate/H0/reset |
| ensureLocalSnapshotForOpen | 按压预热、prepareForOpen、prepareOpenViewport、页面 prepare gate | 共享本地 hydrate；重连代次需要 reset 时进入另一分支 |
| runForOpen | _ensureLatestWindowResetForOpen 的 load 闭包 | 为已 attach 的打开窗口建立可信最新页 |
| runInPage | Chat 的重连恢复、reset 服务网络恢复 | 页面内修复，受用户阅读模式约束 |
| ChatHistoryPeekBootstrap.apply | 本地 hydrate、H0、后续 verification 等 | 受 allowCloudVerification 区分本地阶段与云阶段 |
| verifyAfterFirstFrame | 页面 deferred verification、相关恢复入口 | freshness/coverage 校验；会先协调已有 H0/reset |
| _loadData | UIKit 会话初始化 | 普通首次打开 local-only；搜索/未读专用入口另行处理 |

源码定位：[会话点击](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/conversation.dart:3242>)、[公共路由](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/navigation/app_chat_route.dart:254>)、[页面初始化](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:9200>)。所有正文均已收入 A-source-complete.md，不需要仅凭这些链接猜实现。

图谱先查询了 Coordinator、Peek、reset、hydrate、日志等符号，再以源码调用点补足。Dart 动态分发在图中存在空隙，缺少 callers 不表示无调用；graph 目录保留查询原始输出。

**A2．导航前 prepare 的四条分支**

| 条件 | 实际动作 | 导航是否等它完成 |
|---|---|---|
| 重连 recoveryEpoch 要求 reset，且非搜索 | 失效 viewport cache，必要时同步清旧窗，启动 reset hydrate，锁定当前空/临时结果 | 不等待 reset 的网络 Future；同步清理/投影仍在当前调用里 |
| viewport cache 有完整窗口，预览没有领先 | 重新从 GlobalModel project 并验证；可用则 lockInitial 返回 | 没有本地读取 await；仍有同步复制、分类和投影成本 |
| 内存不足或预览领先 | ensureOpenHydrate → local peek，最多按传入 timeout 等待 | route 默认 100ms；超时继续，不取消底层工作 |
| 本地结果仍需修复或预览领先 | 建立 repair ticket，unawaited H0 | 不等待 H0；首条正确内容何时出现取决于后续采纳/布局 |

[prepareOpenViewport](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/chat_open_viewport_coordinator.dart:356>) 的 cloudGrace 默认值为 200ms，但这条路径只记录参数并启动 H0，明确 awaitGrace=false；不能将它算作必经 200ms 等待。prepareTimeout=400ms 是兼容观测参数，prepareForOpen 不按它等待 SDK/网络。

localBudget=100ms 包的是共享 task.timeout，并不包住整个方法：前面的窗口复制、preview 检查、cache 分类，以及返回后的再次投影都有自己的 CPU 成本。这些成本尚无真机样本。

**A3．逐段 await 的实际含义**

下面列出首屏主路径上的等待族；CSV 中保留 286 个 await、detached 调用、预算和计时点的原行，包含相关方法的分支上下文。CSV 是定位索引，不能把一行 await 等同于一次独立 I/O，也不能把其中所有预算相加。

| 等待点 | 真正等待什么 | 是否位于首屏关键路径 | 超时/取消与测量缺口 |
|---|---|---|---|
| 会话点击 await clearLocalForOpenFast | 同步内存清零、通知和异步任务启动前缀，然后 Future 交接 | 位于 beginOpen 之前，属于点击到导航的前段 | 方法内部没有 await 持久化或 SDK 清未读；不能称为等待数据库落盘 |
| route await prepareOpenViewport | 分支分类；不足时 join/执行本地 hydrate | 导航前 | 本地等待默认 100ms，非全函数硬截止 |
| ensureLocalSnapshotForOpen await task.timeout | ensureOpenHydrate 的共享 Future | 取决于调用方：route / page gate / press warm | 默认 280ms；route 传 100ms；页面 gate 传 900ms；timeout 不取消 |
| hydrate microtask await load | peek.apply，或重连 reset | 延后到 microtask；可能提供首条可展示数据 | 队列等待与实际 load 耗时未拆分 |
| peek.apply 的 clearEpoch 查询和 join | 历史清理边界、同作用域已有 local/in-flight 任务 | local hydrate 的组成部分 | 必要身份边界；多次调用不等于多次数据库实读 |
| peek._applyImpl 的 coverage/clear fence | coverage 加载与清理边界复核 | 本地分支可命中 | 底层缓存/数据库耗时未单独测量 |
| loadLocalForChatEntry | SDK 本地较旧页读取；去重；清理边界过滤 | 本地首窗数据来源 | count=initialOpenFetchCount；不访问 cloud/归档联合链 |
| 本地历史 didGetHistoricalMessageList | 页面生命周期过滤/归一化 | 位于消息提交之前 | 需记录 rawCount、displayCount、处理耗时 |
| prepareFirstWindowMedia(awaitNetwork=false) | 选中本地媒体的有界 warm；网络 URL 解析转后台 | 可能延长数据提交前段 | 当前本地媒体预算 24ms；不能称“完全不等待媒体” |
| canCommitInitialWindow / clear fence 复核 | 账号、窗口和清理状态仍有效 | 采纳前必要判断 | 不得为了减少 await 删除这些条件 |
| UIKit local-only awaitOpenHydrateInFlight | 已存在 app hydrate | UIKit 后续加载流程，80ms 后若仍在运行就 defer | 不等于整个页面 80ms 白屏 |
| UIKit local fallback await loadChatRecord | 没有可用消息且无已提交/未完成 hydrate 时的 SDK 本地读取 | 在 fallback 场景决定首条内容 | 不进入普通 cloud fallback |
| 页面 _prepareOpenHistoryGate | 同一 local/reset hydrate，等待上限 900ms | 生命周期/后置任务准备依赖 | 外层组件没有用此 Future 阻断整个页面 |
| _runOpenHistoryGateWithTipsMerge | preparation 1200ms、群本地 tip 400ms、layout ready 300ms | 生命周期与列表几何协调 | 这些是上限/条件分支；不固定串行消耗最大值 |
| deferred verification | first-frame 后 0 或 700ms 延迟，协调 H0/reset，再验证 | 已有完整本地窗时是后置；空/薄窗可能决定首条消息 | 网络新鲜度与第一帧分开记录 |
| post-open runTasks | 转场完成/后备延迟，然后等待两个 history gates | 草稿加载、资料/群信息等后置任务 | 不应把这些完成时间当作消息首屏时间 |
| H0/最新 reset | cloud latest page、边界核对、过滤、必要媒体 warm、提交 | 不挡 push；特殊冷/重连场景可挡首条正确消息 | 云请求自身及队列仍需分段记录 |

媒体注释容易误读：当前 awaitNetwork=false 只保证网络 URL/远端解码任务不成为完整等待，但会等本地 warm，预算取 initialMediaBudget 与 initialLocalMediaBudget 较小者，当前后者为 24ms。

另一个易误读点：[页面包装](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4536>) 是直接 return chatWidget。history gate 的旧注释提到 AbsorbPointer，不能拿注释代替现有执行代码。

**A4．复用键和“重复请求”的证据边界**

| 机制 | 复用/失效条件 | 目前能证明什么 |
|---|---|---|
| GlobalModel.ensureOpenHydrate | 先查同会话 alias 的可发布 in-flight；完成缓存再比 requestSignature、initialLoaded | 多个 prepare 能 join；in-flight 分支并不重新比较新签名 |
| 普通 local signature | owner、account generation、preview msgID/seq/timestamp、clearEpoch | 完成结果不是无条件跨账号或跨清理代次复用 |
| reset signature | 再包含 recoveryEpoch，发布检查 openGeneration/abandoned/search | reset 与普通 local hydrate 的目标不同 |
| ChatHistoryPeekBootstrap | 各自 in-flight/local phase 与账号/清理边界 | 云和本地调用可能共享一部分结果；原文已附 |
| H0 repair | owner@generation、规范会话键、latest | openGeneration 用于 ticket 采纳，不在 H0 共享键内 |
| 后置 verification | owner@generation、会话键；遇已有 H0 先等，遇 reset owner 跳过 | 不是所有入口都独立发一遍 cloud |
| 最新 reset | 按会话维护 operation，并核对 open generation/identity | 新页面与旧任务的接管需要遵守原令牌 |

因此当前只确认“三个 prepare 入口”，未确认“一次打开三次查 SDK”。应记录 prepareCount、actualHydrateCount、hydrateJoinCount、SDK 实读次数、commit 次数及丢弃原因，用同一个 openTraceId 关联。

对于后台工作是否排在用户前面，当前代码已有队列和用户分页协调；缺少排队时间记录，不能给出“把并发从 2 改 4”的依据。

**A5．定时器、预算与触发来源**

这些是源码配置，不是测得的耗时，也不是建议的新参数。

| 位置 | 当前值 | 来源与作用 |
|---|---|---|
| prepare localBudget | 100ms | route/list prepare 的本地 Future 等待上限 |
| ensureLocalSnapshot 默认 | 280ms | 按压/兼容调用；调用方可覆盖 |
| 页面 prepare gate | 900ms | 页面挂载后 join hydrate |
| UIKit plain local open | 80ms | 短暂 join，未结束则 defer |
| preparation/tip/layout gate | 1200/400/300ms | 生命周期准备、群本地 tip、布局信号 |
| 媒体首窗 local/URL/总体预算 | 24/140/220ms | 本地 warm 与后台 URL/媒体工作；默认不等待网络完成 |
| 页面首次 verification | 完整且预览未领先时 700ms，否则 0 | post-frame 后启动 |
| H0/verification SDK deadline | 12 秒 | 服务层 timeout，不能当作点击固定延迟 |
| verification 重试 | 0/1/5 秒；后续 15/60/300 秒 | 失败重试，不是普通首次必经等待 |
| reset 重试 | 0/800ms/2s，之后 5/15/60s | 最新页校验失败；网络状态变化可唤醒 |
| reset 用户操作等待 | 500ms poll；特定 defer 120ms | 尊重页面阅读/交互状态 |
| post-open route fallback | 1000ms | 未使用进行中的 route animation 完成回调时走后备调度 |
| post-open 延迟 | local 0、history 80、metadata/idle 380、mute 450、business 650、group feature 900ms | 转场/gate 之后错峰；p2Delay=220 定义存在，不代表此调用链用了它 |
| post-open 并发/超时 | 默认 2；8 秒 watchdog | watchdog 只诊断，不取消底层任务，不提前释放占用槽 |
| ChatOpenPerf settle summary | 2 秒 | 统计观察窗，不是打开完成态 |

ChatPostOpenScheduler._allows 当前对 background 返回 active 或 interacting。因此“正在交互时一定暂停后台任务”不能作为现有前提。是否调整它应另立行为契约，并在补齐观测后验证，不应顺手把 realtime/发送确认/账号恢复一起停掉。

**A6．现有测量能力与缺失字段**

[ChatOpenPerfLog](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/chat_open_perf_log.dart:13>) 当前 enabled=kDebugMode、enabledInProfile=false、consoleOutputEnabled=false；release 禁用。debugSink 用于测试捕获，并非已存在的生产采集出口。

[ChatPipelineClock](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/chat_pipeline_clock.dart:9>) 的 enabled=false。它内部会启动 Stopwatch，但没有可见的链路输出。

PerfTimeline 会发出聊天页打开和首帧等 instantSync 点，但没有自动形成排队/执行/投影的成对 span；这些点也不能直接表示首条消息对用户可见。

| 建议字段/能力 | 当前情况 |
|---|---|
| 一次打开 traceId | ChatOpenPerf 的 chatOpenTraceId 存在，基于时间和会话 hash |
| 所有入口统一起点 | 缺失：当前 beginOpen 仅找到会话列表调用；直接入口可能没有自身 ledger |
| 从真实点击时刻计时 | 不完整：beginOpen 在 clearLocalForOpenFast 后；Pipeline 有更早点但关闭 |
| spanId / parentSpanId | 未形成通用完整体系 |
| ownerHash / conversationHash | ChatOpenPerf 有 ID 脱敏；其他日志并非统一采用同一脱敏出口 |
| pageInstanceId | 缺少统一显式字段；已有 scope/openGeneration 不应擅自等同 |
| windowGeneration / clearEpoch | 部分调用提供，非所有事件统一具备 |
| operationId / attemptId | 发送数据结构有，未统一接入打开账本 |
| queuedAt/start/end | 缺少贯穿本地读、SDK、writer、布局的完整配对 |
| rawCount / displayCount / source / hit | 部分已有；需要统一关联和定义 |
| 首条消息可见 | post-frame + reveal/placeholder/非空检查；不等于 GPU presentation，也不等同于已读可见性证明 |
| 每次实读次数 | 有 owner/join/read/commit 计数，但当前缺真机同 trace 样本 |
| UI/raster frame 和设备刷新率 | 本包没有设备关联原始记录 |

特别注意：markMessagesFirstVisible 的当前直接调用检查 mounted、会话一致、reveal 与占位状态，并没有在该函数内完成“应用前台、route 正在最上层、长消息实际交集”的全套判定。因此它可作为首屏绘制里程碑候选，不能直接拿来决定有限已读水位。

**A7．原始日志检索结果**

在 artifacts/** 与 test_outputs/** 中扫描 628 个日志/JSON/文本候选文件，排除本资料包自身；另检查了工作区常见日志与 trace 文件名。

找到 4 个包含 Pipeline/ChatOpenPerf 标记的历史文件，均为测试输出或源码快照；没有发现可确认设备、运行模式、冷热场景、构建版本和完整一次操作的 Profile trace。仓库另有 mini_trace fixture，属于测试样例，不是设备基线。

[原始日志清单与判定](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-evidence-ab-2026-09-25/raw-log-inventory.json>)保留了路径、文件大小、标记次数和类型判断。可复用的旧测试日志仍在原目录，不复制其中可能包含业务标识的内容作为性能样本。

当前可报告的真实性能数据：缺失。没有 p50/p95，没有每次打开实际 SDK 请求数，没有已验证的前台排队耗时，也没有可据此调整缓存/并发的数字。

**A8．第一轮性能修改点**

先在现有日志设施上补观测，不增加业务协调器：

1. 以真正入口点击/导航请求为统一开始点；显式传递 open trace context，覆盖列表、资料、推送和嵌入切换，避免借用另一个会话的当前 ledger。
2. 提供可控的 Profile 采集出口；复用现有脱敏原则，补稳定 owner/conversation hash，不输出正文、token、UserSig 或签名地址。不能只把旧 Pipeline 开关打开，因为它直接写原始会话键。
3. 在现有队列 admission、任务开始、完成和结果投影处形成成对记录，分开 queueWait / execution / UI application，不把 deltaMs 当成单独操作耗时。
4. 对本地 hydrate 的 SDK 读取、clear/coverage 查询、过滤、local media warm、writer commit、reveal/layout 各记录耗时与数据规模；cloud freshness 另计。
5. 记录共享读取的 producerId 与 waiterId，避免三个 prepare 各算一次“真实读取”。
6. 保存原始 Timeline 和场景元数据，先采样再决定是否减少重复工作或改变预算。

保持现有产品语义：首屏正确且连续，中间历史由用户上拉获取，阅读历史时不抢位置；不更改 3000/280/40 等窗口参数，不扩大首屏补历史范围。

本包未启用新埋点或改业务代码。真正性能基线仍需 Profile 真机运行。后续所需最小外部信息为设备/刷新率、交付平台、同一测试账号的数据规模及原始 Timeline；当前代码与本地测试已经可以在工作区直接取用，不需要重新提交整仓。

