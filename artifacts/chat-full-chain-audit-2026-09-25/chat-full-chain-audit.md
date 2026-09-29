**聊天对话页面全链路审计 · 2026-09-25**

本次检查针对当前工作树中的普通单聊、群聊对话页面，以 Chat → 本地定制 UIKit → 消息协调与持久化 → Tencent IM SDK / 业务 API 为主线，覆盖进入页面、首屏历史、分页与定位、发送与接收、已读与未读、附件、草稿、页面返回、离页、账号切换及异常恢复。

检查发现：3 个状态问题通过隔离实验复现；Web 构建实际失败；另有源码可确定的返回定位问题、会话已读队列持续重试问题，以及性能预算和架构契约漂移。现有 104 个测试文件共执行 780 项，770 项通过、10 项失败。10 项失败并不等于 10 个独立运行时缺陷，后文逐项分类。

本轮没有修改业务代码，没有提交 Git，没有向真实联系人发送消息。新增内容只有本目录中的报告、隔离实验与验证日志。工作区本来存在未提交改动，因此结论对应检查时的工作树，不能直接等同于 HEAD 的干净版本。

**一、结论与处理优先级**

P1 表示应优先修复的数据可靠性或构建问题；P2 表示明确的交互或恢复缺陷；P3 表示需量化或统一契约的问题。这些优先级与 GitNexus 的调用影响风险是不同概念。

| 编号 | 优先级 | 结论 | 证据强度 | 用户影响 |
|---|---|---|---|---|
| F1 | P1 | 上一条消息的成功回调会清掉发送后新输入的草稿 | 真实草稿控制器实验 + 页面调用链 | 新文字可能仍在输入框，但离页后不能恢复 |
| F2 | P1 | 已成功的消息会被迟到的失败结果降级为失败 | 真实 GlobalModel 实验 + 发送协调器源码 | 消息已送达仍显示失败，可能诱发用户重复发送 |
| F3 | P1，Web 范围 | 当前 Web 构建失败 | 实际 flutter build web + analyzer | Web 无法构建交付；不能据此判断移动端编译失败 |
| F4 | P2 | 从普通二级页面返回会强制跳到当前窗口底部 | 源码完整可达链路 | 阅读历史或搜索位置被打断 |
| F5 | P2 | 同会话并发首次打开可能压入两个聊天路由 | NavigatorObserver 隔离实验 | 返回次数异常、出现重复聊天实例 |
| F6 | P2 | 会话已读队列没有重试上限或永久错误终止策略 | SQLite 队列实验 + 定时器源码 | 永久失败也会继续周期请求 |
| F7 | P3 | 历史阅读数据窗口可达 3000 条，旧预算测试仍限制 320 | 策略常量 + 现有测试失败 | 性能预算失配；尚无真机卡顿或内存泄漏证据 |
| F8 | P3 | 局部写入和 SDK 读取绕过架构约定，源码字符串测试失配 | 架构契约测试 + 调用点核对 | 增加维护和回归判断成本 |

**二、F1：迟到的发送成功回调清掉新草稿**

触发时序：

1. 用户输入 A 并点击发送。
2. 输入组件立即清空输入框并回传空字符串；SDK 发送仍在进行。
3. 用户开始输入另一段尚未发送的 B。
4. A 的成功回调到达，页面无条件调用 _clearChatLocalDraftAfterSend。
5. 此方法对当前草稿调用 markSendCompleted，清掉 B 的内存状态、取消 B 的防抖保存，并设置禁止离页保存标记。
6. 页面离开时 _persistChatLocalDraft 提前返回；再次进入，B 不能从草稿恢复。

源头分别在 [发送成功回调](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:9474>)、[成功后清草稿](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:1446>)、[草稿控制器](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat_page/chat_draft_controller.dart:62>) 和 [离页保存门禁](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:1424>)。

当前保护解决了“发送前的旧防抖任务晚到，导致已发文字重新变成草稿”的问题，但没有区分“此次发送的草稿版本”和“发送后新编辑的版本”。已有 stateRevision / writeGeneration，却没有把提交时的版本作为成功清理的条件。

隔离实验对真实 ChatDraftController 执行“清空 → 新输入 → 旧发送完成”，期望保留 next unsent draft，实际得到 null，同时离页保存被抑制。这是控制器与页面接线层面的复现；没有进行真机输入和重新进入页面的人工操作。

建议：提交时捕获 owner、conversation、draft revision 和本次发送身份；成功回调只清理提交版本以及更早的待写入任务，不能清掉较新的编辑。数据库清理也应针对提交时的会话与版本，避免扩大到当前页面后来切换到的会话。

验收应覆盖：成功回调前输入 B、B 已经防抖落盘、连续发 A/C 后输入 B、失败后保留、等待回调时离页、切换会话或账号后旧回调到达。只有“发送成功后旧草稿消失”的测试不足以覆盖这个问题。

**三、F2：成功消息被迟到失败结果降级**

[applyOutgoingSendResult](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:3671>) 先调用 updateMessage；只要 code 非零，又调用 markOutgoingSendFailedByIdentity。前者在 [12215 行](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:12215>) 直接赋失败状态；后者在 [12447 行](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:12447>) 克隆已有消息后直接改成失败，没有保护已经确认的成功状态。

[发送协调器](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/outgoing_send_coordinator.dart:448>) 对 outcomeUnknown 有“若持久化拒绝覆盖，则检查服务端成功证据并规范化为成功”的逻辑；显式失败分支没有同等处理，仍可能把失败 callback 交给 UI。即使持久化层避免状态回退，UI 投影仍可回退，两个层面的状态可能不一致。

实验先插入具有本地 ID、正式 msgID、SEND_SUCC 状态的消息，再将晚到的 code=6012 结果交给真实 applyOutgoingSendResult。期望状态 2（成功），实际状态 3（失败）。实验使用本地假的元数据服务，没有真实发送；证明的是现有状态机不能抵御这种到达顺序，并不证明线上 SDK 每次都会产生此顺序。

建议：统一成功证据优先级，确保同一消息身份、同一发送尝试的已确认成功不能被较旧失败覆盖。显式失败和结果未知都应核对已采纳的成功证据。不要只在一个 UI 分支隐藏失败图标，因为 outbox、消息列表与重试入口必须一致。新的重试尝试需要自己的身份或尝试版本，不能用“永远忽略失败”代替状态规则。

验收应覆盖：实时回流成功先于 SDK 失败、历史补偿成功先于超时、失败先到成功后到、别名身份合并、用户取消、重新发送的独立尝试。重复消息目前属于下游风险，未在真实服务端复现。

**四、F3：Web 构建存在实际阻断**

执行 flutter build web --no-pub --debug 后失败，有两个明确问题：

| 问题 | 源码位置 | 结果 |
|---|---|---|
| 接口新增 completeRecoveryCopies 参数，Web override 未跟进 | [接口](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/im_ingress_store.dart:174>) / [Web 实现](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/im_ingress_store_platform_web.dart:313>) | invalid_override，实际构建也报错 |
| Web 依赖图引入原生 IM 类型，最终到达 dart:ffi | [conversation_rebase_policy.dart](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_rebase_policy.dart:2>) | JavaScript Web 编译不支持 dart:ffi |

后者是实际构建日志给出的依赖链之一，不能假设修掉这一个 import 就消除所有原生 SDK 依赖。需要逐条处理编译器报告的直接和传递依赖，采用公共模型或条件导入。

Web 并非只有“测试文件未覆盖”的抽象风险：两个 Web 策略测试可以通过，同时整个应用构建仍失败。应把 Web 真正构建加入校验。移动端 Flutter VM 的聊天页编译测试通过；本轮没有执行 Android APK 或 iOS archive，不能扩大这个结论。

证据：[应用 analyzer](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-full-chain-audit-2026-09-25/analyze-app.log>)、[Web 构建错误日志](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-full-chain-audit-2026-09-25/web-build-stderr.log>)。日志较大，后续类型错误大量由 dart:ffi 不可用连锁产生，不应逐条视为独立缺陷。

**五、F4：普通页面返回破坏历史阅读位置**

可达链路是：

didPopNext → _scheduleRouteReturnRecovery → _recoverAfterRouteBecameCurrent → _recoverChatHistoryAfterOverlayReturn → _performChatHistoryAfterOverlayReturn。

[RouteAware 返回入口](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:9712>) 已对媒体预览、媒体选择器、钱包覆盖页设置例外；但普通二级页面返回仍进入恢复逻辑。[有消息分支](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:7353>) 只要 scrollController 有 clients，就 jumpTo(minScrollExtent)。

问题在于注释声称处理“有缓存消息仍空白”，代码没有检查列表是否真的空白，也没有检查当前是否正在阅读历史或停在搜索锚点。因此，打开个人资料、普通设置等页面再返回，可能丢失原来的消息位置。若还在分页，会延迟 2 秒后进入同一恢复路径，并非保留阅读锚点。

这里跳到的是当前消息窗口的底部，不能等同于已经加载到真正最新消息。强行滚动与“回到最新”的窗口补齐、可见性证明、已读 ACK 事务也不同。

建议：普通路由返回只恢复活动状态并触发必要重绘；以明确的空白检测或缺失窗口条件启动修复。修复前后保留 message identity + 像素偏移，区分 live-follow、history-reading、search-jump 三种模式。媒体已有恢复逻辑应保留。

此项依据源码确定执行条件；尚未在真实设备完整导航操作中录屏复现。验收需要在历史中段、搜索结果、分页进行中、键盘展开等状态分别进入资料页和设置页再返回。

**六、F5：并发首次打开同会话时，复用检查存在空隙**

[openOrReuseAppChat](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/navigation/app_chat_route.dart:254>) 在 await prepareOpenViewport 之前查 activeRoute；等待之后直接 push，没有再次检查，也没有按 Navigator + sessionKey 预占正在打开的路由。注册发生在路由子树挂载之后。

因此两个并发调用均可能查到“没有”，然后各压入一个新路由。隔离实验让本地预热走受支持的失败降级路径，通过 NavigatorObserver 观察：期望 1 次 push，实际 2 次。实验没有构建完整聊天子树；它验证的是公共导航 helper 的并发互斥缺口。

范围应区分：会话列表本身已有 _openingConversationID 门禁，能减少其自身触发；[用户资料页的发消息入口](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/user_profile.dart:2011>) 没有同样的等待期保护，其他导航来源也不能假设受会话列表门禁覆盖。搜索锚点打开刻意不复用路由，这是现有语义，不能作为同一个缺陷处理。

建议：普通会话打开建立按 Navigator + 会话键的 in-flight 预占，并在失败、pop 时正确释放；复用调用返回的 Future 仍应在目标路由真正退出时完成。仅在 push 前重查，如果注册仍要等到下一帧，也未必完全覆盖同帧并发。

验收：双击资料页“发消息”、会话入口与推送同时打开、预热成功/失败/超时、已有路由被其他页盖住、不同会话并行、带搜索锚点的专用路由。

**七、F6：会话已读重试可能无限持续**

[ConversationReadOutboxStore.markRetry](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/read_outbox_store.dart:357>) 递增 attemptCount，并以指数退避计算下一次时间；指数被限制到 6，也就是最大约 64 秒，但没有最大尝试次数或 dead-letter 状态。

[ConversationUnreadClearService](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_unread_clear_service.dart:1335>) 在缺少可用水位或 SDK 清理失败后继续 markRetry，再安排定时器。因此账号保持活动、同一记录持续失败时，可以长期循环。

真实 SQLite 队列实验连续调用 20 次 markRetry，记录仍存在，attemptCount=20，下一次重试在 64 秒以内。这个实验是对当前行为的断言，所以它通过；不是“系统可靠性已通过”。

要区分两个类：会话已读队列 ConversationReadOutboxStore 缺此策略；逐消息已读回执的 ReadReceiptOutboxStore 已有 10 次与 dead-letter 相关逻辑，不能笼统说所有已读队列都无限重试。

建议按失败原因处理：断网保留并等待连通性/前台恢复触发；明确的权限、会话失效、记录无效等永久错误进入可诊断终态；限制定时器重试并允许新水位或会话恢复重新激活。不能简单删除所有失败记录，否则会造成未读状态长期不一致。

**八、当前完整运行链路**

~~~mermaid
flowchart TD
  A[业务会话恢复与 IM 登录] --> B[账号身份与 generation]
  B --> C[会话列表 / 资料页 / 搜索 / 推送入口]
  C --> D[openOrReuseAppChat]
  D --> E[本地窗口分类与预热]
  E --> F[Chat 页面和定制 UIKit]
  F --> G[输入 / 草稿 / 附件]
  G --> H[发送协调器与 Outbox]
  H --> I[Tencent IM SDK]
  I --> J[实时监听与账号级同步]
  J --> K[消息归并与窗口投影]
  K --> F
  F --> L[历史本地读取 / 云端补齐 / 搜索定位]
  L --> K
  F --> M[可见性证明与已读水位]
  M --> N[本地未读 / 已读 Outbox / SDK 已读]
  G --> O[业务附件 API 与签名对象存储]
  O --> H
  F --> P[覆盖页 / 离页 / 恢复]
  P --> E
~~~

这张图描述客户端职责边界。腾讯云消息路由、真实服务端幂等和权限校验的内部实现不在本次已验证范围内；业务附件接口追踪到客户端请求与响应处理，未对生产环境执行上传或发送。

**8.1 登录前提与账号隔离**

[SessionManager](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/session/session_manager.dart:92>) 负责恢复业务会话、获取 IM 凭据、初始化和连接 IM，再进入 ready。成功后配置消息 writer 的账号作用域并安装账号级实时监听。业务 token 和 IM UserSig 有不同用途，业务 API 可用与 IM ready 不能互相替代。

sessionGeneration 用来阻止同一账号登出重登后，旧 Future 重新应用结果。连接断开可安排重连；被踢下线被视作终止事件；UserSig 过期进入凭据刷新。相关分支见 [会话状态与回调](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/session/session_manager.dart:40>)。

[账号清理](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/account_session_service.dart:215>) 先失效身份，再清理会话、已读调度、发送队列、覆盖层与监听等状态。普通登出可保留按 owner 隔离的磁盘数据，显式清盘是另一条策略。不能把“磁盘仍有数据”直接判定为账号泄漏；需要同时核对数据访问的 owner、generation、lease。

后续聊天页面的 gate 只能保护页面实例，账号级监听和持久化任务还需要自己的身份检查。当前架构确实同时使用这些层级，修复时不应为了简化删除其中一层。

**8.2 会话入口与路由**

主入口包括会话列表、联系人/资料页、群相关页面、搜索与推送。公共路由层根据单聊/群聊建立 sessionKey。普通打开可以复用同 Navigator 下的已有聊天路由；搜索或明确消息锚点需要保留专用导航语义。

已有路由复用时等待 existing.popped，而不是立即完成 Future。这样调用方不会在聊天仍可见时误认为已经退出并执行未读收尾。这个完成时机应在修 F5 时保留。

**8.3 首屏：先本地，再补齐**

[ChatOpenViewportCoordinator](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/chat_open_viewport_coordinator.dart:356>) 负责本地快速分类、缓存、空窗处理与后续工作调度。页面启用 localOnlyInitialOpen，首屏不应无条件等云端历史。

[ChatLatestWindowResetService](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/chat_latest_window_reset_service.dart:265>) 处理需要建立最新窗口的场景，包括 in-flight 复用/替换、网络可用性、云端返回的新鲜度和预览边缘校验。它会将确认结果提交给消息层，而不是把任意返回列表当成完整历史。

当前对“连续性”和“新鲜度”分开判断：数字 seq 有空洞不能自动证明丢消息，删除等情况可能留下数值缺口。这意味着不能为了让旧字符串测试通过，机械恢复所有旧的 seq-gap 行为。

首屏问题排查应依次确认：owner/IM scope → conversation key → 本地 coverage → 窗口 generation → raw list → display filtering → layout ready。只看接口返回数量，无法判定页面为何空白。

**8.4 历史、分页、搜索与阅读模式**

历史窗口包含可见页、窗口外的到达消息、变更覆盖层和连续性/覆盖信息。readyLocal、partial、gap、emptyLocal、verified 代表不同证据；本地空或短页不能一律推导出服务端没有更多消息。

older / newer 分页需要不同游标；搜索锚点和普通最新窗口不是同一种打开方式。分页完成时还需要检查会话、账号、窗口 generation 和 clearEpoch，避免旧请求把被清掉的历史恢复回来。

阅读历史时，新消息可以先进入 deferred 数据区并增长未读提示，避免强行把用户拖回底部。点击“回到最新”则通过单独的事务补齐窗口、布局和可见性确认。

[reloadNewestHistoryWindow](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:1855>) 的成功结果不是“消息已经看到”的证明。现有实现只提前处理可被权威删除证据确认的情况，其余水位交给真正可见后确认。这是后文一个旧测试失败需要单独解释的原因。

**8.5 文本与普通消息发送**

主路径如下：

输入组件提交 → SeparateViewModel.sendTextMessage → 插入乐观消息 → SDK createTextMessage → 绑定本地稳定身份 → _sendMessage → ImOutgoingSendCoordinator → SDK adapter → 结果归并 → 生命周期 messageDidSend → 更新草稿和会话预览。

入口见 [sendTextMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:7622>)；统一调度见 [ImOutgoingSendCoordinator.send](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/outgoing_send_coordinator.dart:103>)。

发送不是简单“Future 成功就 append”。本地 ID、SDK ID、服务端 msgID 和 operation/correlation identity 会逐步补全，期间的实时回流可能早于发送 Future 完成。F2 正是跨来源结果仲裁不完整的表现。

发送协调器取得当前账号/租约，准备可恢复 payload 和媒体副本，记录 prepared、dispatchIntent、sending，再调用 SDK。成功、明确失败和结果未知是不同结果，不能将超时等同于服务端没收到。

**8.6 崩溃恢复与幂等边界**

[OutgoingOutboxRecoveryService](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/outgoing_outbox_recovery_service.dart:24>) 对 prepared 等尚未发起的状态可继续发送；已进入 dispatchIntent/sending 的操作可能已经影响服务端，恢复时按结果未知处理并等待实时或历史证据，不宜盲重发。

持久化 outbox、SDK 消息库、可见列表是不同状态来源。检查“重复”应同时检查操作身份、服务端 msgID 与 UI 合并，检查“丢失”则应区分尚未 dispatch、服务器结果未知、已确认但未投影三个阶段。

现有的 outcomeUnknown 保护值得保留；修复 F2 应补齐成功证据仲裁，不能把所有失败或未知都变成自动重发。

**8.7 接收消息与实时同步**

[ConversationSyncService._handleMessageIngress](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_sync_service.dart:1081>) 是重要接收入口。普通 SDK realtime namespace 有直接处理分支，进入 [_handleSdkRealtimeMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_sync_service.dart:1182>) 后核对当前账号和清理代次，再调用 GlobalModel 的 app realtime 投影。

因此不能把现有系统描述成“所有 SDK 实时事件都先持久化 Inbox 后展示”。当前存在普通实时快速路径；其他运行时/恢复事件才使用 Inbox 的领取、处理、完成与重试路径。

是否投影到当前页面与 ActiveChatRegistry 有关；离页并不意味着账号级同步停止。通知和通话信令有独立的后续处理，不能拿“页面没有监听”推断“账号不收消息”。

该快速路径与恢复路径并存，后续需要明确崩溃恢复来源以及幂等责任。这里记录的是架构事实，本次未据此证明存在消息丢失。

**8.8 消息归并与 UI 投影**

MessageReconciliationWriter 负责消息结构归并，使用本地/SDK/服务端身份关联、删除 tombstone、账号/窗口 generation 等机制；GlobalModel 管理共享列表与投影，SeparateViewModel 管理当前会话行为。

删除、撤回、实时消息、历史补页、发送结果不能各自独立 append，否则容易出现重复、复活或顺序漂移。当前多数路径已有 writer 和 delta 机制，但还存在应用层 setMessageList 的明确例外，见 F8。

原始消息存在不保证可显示：还会经过 messageShouldMount、messageListShouldMount、系统消息/自定义消息过滤、时间/分组、窗口布局。因此排查空白应同时采集 raw count、display count、窗口身份和过滤原因。

**8.9 未读、回执与“真正看到”**

至少要区分三件事：

| 状态 | 用途 | 为什么不能互换 |
|---|---|---|
| 本地会话未读/列表徽标 | 会话列表展示和本地一致性 | 本地清零不证明 SDK 已处理 |
| 页面未读提示与可见水位 | 告诉用户还有未看的到达消息 | 抓到最新历史不证明最新行已显示 |
| SDK 会话已读和消息已读回执 | 与服务端及其他端同步 | 发出请求也可能失败或等待重试 |

[回到最新按钮事务](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/tim_uikit_chat_history_message_list_tongue_container.dart:348>) 先确定需要加载的窗口，捕获有限的返回水位，等最新行真正可见后确认。动作过程中后来到达的新消息不应被旧水位一并误清。

这个模型比“进页就全部标已读”更严格。当前失败的旧用例期待 reloadNewest 返回 true 后立即减少 deferred，和新的可见性确认时机冲突；不能直接认定生产代码漏清未读。F6 则是独立的重试终态问题。

**8.10 草稿与输入**

输入防抖保存间隔为 250ms；写队列串行执行，单次写失败不会阻断以后所有写。空输入会立即触发草稿清理；载入草稿通过 stateRevision 避免覆盖用户刚输入的文字。

页面 deactivate/dispose/切换和发送完成都可能触发草稿操作，必须有统一版本仲裁。F1 表明“防旧写回”和“保新输入”两个约束目前未同时满足。

已有输入法 composition、选区保留、键盘布局、发送节流相关测试通过，不能因此覆盖异步发送完成与新草稿的竞态。这类测试应以时间顺序和可恢复结果为断言。

**8.11 图片、视频、文件和附件 API**

[ChatAttachmentService](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/chat_attachment_service_io.dart:319>) 的主要阶段是：策略 → 本地 staging → 初始化上传 → 分片与签名地址 → complete → reference → ready → dispatching → 消息发送/确认。

业务请求由 [ChatAttachmentApi](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/api/chat_attachment_api.dart:9>) 发起；签名对象存储使用分离 transport，不携带业务 JWT、设备鉴权头或业务拦截器。下载另有长度/范围检查。附件流程使用 owner、取消标记和操作身份，防止离页/换号后旧任务继续应用到当前会话。

| 客户端请求 | 作用 |
|---|---|
| GET /me/chat/attachment-policy | 读取附件能力与大小等策略 |
| POST /me/chat/uploads | 初始化上传 |
| GET /me/chat/uploads/{id} | 获取上传状态与已完成分片 |
| POST /me/chat/uploads/{id}/part-urls | 申请分片签名地址，每次 1–32 个 |
| POST /me/chat/uploads/{id}/complete | 完成合并 |
| POST /me/chat/attachments/{id}/references | 为目标会话创建附件引用 |
| POST /me/chat/native-video-messages | 后端原生视频消息发送 |
| GET /me/chat/native-video-messages/{operationId} | 查询结果未知的视频发送 |
| POST /me/chat/attachments/{id}/access | 取得访问授权 |

原生视频在 dispatch 前保存状态；若结果未知，用 operationId 查询状态，定时约 15 秒，不直接反复 POST。attachmentId、referenceId、operationId 必须一致，避免误采纳其他任务的结果。

该附件增强服务主要面向 Android/iOS；Web 有 stub，桌面可能走 SDK/其他退化路径，不能把移动端附件测试结论推广到全部平台。附件上传、原生预览、传输隔离、批次顺序、媒体身份与取消的相关测试已执行，通过本轮所选用例。

本轮没有真实上传大文件、断网续传或验证后端幂等表、对象存储权限配置。这些是端到端联调的剩余边界。

**8.12 权限、群状态与特殊消息**

发送链路还受单聊权限、好友/拉黑状态、群成员资格/禁言、官方账号等业务门禁影响。已知禁止和权限检查中是不同状态；延迟的检查结果需遵守页面与账号身份，避免换会话后禁用错误输入框。

钱包卡片、直播、通话、表情及自定义消息依赖额外业务服务。主聊天列表负责显示和交互承载，但它不是这些业务交易的唯一事实来源。相关卡片恢复不能简单通过重发聊天消息代替业务查询。

本轮执行了 C2C 权限/拒绝、失败重发、直播页面保留、业务会话过期等相关测试；钱包支付实际扣款、通话真实接通、直播真实推拉流没有在线验证。不能据这次审计宣布这些完整子系统已全部通过。

**8.13 离页、覆盖页和返回**

离页需要失效页面 scope，保存有效草稿，收尾当前会话预览/未读，释放活动页面注册，并让账号级同步继续运行。页面关闭不应清空属于账号的持久化恢复队列。

媒体预览、媒体选择器、钱包页都有自身的遮罩/恢复状态。普通二级路由返回是另一类事件，应保留原来的历史锚点；F4 将它接到了过于激进的空白修复路径。

长任务的回调至少要回答：是否仍为同一账号、同一会话、同一页面实例、同一历史窗口/清理代次。某处 mounted 为 true，只说明 State 还没销毁，不能代替这些身份条件。

**九、性能与结构性风险**

[ChatMessageWindowPolicy](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/chat_message_window_policy.dart:12>) 定义普通 target=220、softMax=280、historyReadSoftMax=3000、loadBatch=40。历史阅读另有最多约 120 条的内存 deferred 缓冲策略。

3000 条数据不等于同时构建 3000 个 Flutter Widget，也不是内存泄漏证据。但它增加排序、去重、覆盖合并、映射、列表通知时的数据处理上限；携带媒体元信息时实际占用还需设备测量。现有“120–300 级预算”测试仍要求不超过 320，与实现明显分歧。

建议用 Android/iOS profile 实测：连续读数千条后的 RSS、GC、帧耗时、分页和新消息叠加时的卡顿；同时验证窗口裁剪不会破坏搜索和阅读锚点。直接把 3000 改回 280 可能修测试却破坏阅读体验。

当前 chat.dart、GlobalModel、SeparateViewModel、历史列表四个文件合计约 5.2 万行。职责跨层交错是后续回归的维护风险，但文件行数本身不是性能指标。优先建立发送身份、草稿版本、窗口模式和路由生命周期的明确边界，再考虑结构整理。

应用 analyzer 中还有若干跨 await 使用 BuildContext 的提示，属于值得逐处分辨的生命周期风险；本轮没有把这些提示全部计成已证实的崩溃。

**十、现有测试的 10 项失败逐一解释**

| 测试位置 | 失败点 | 分类与处理 |
|---|---|---|
| [chat_page_scope_test.dart:92](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/test/chat_page_scope_test.dart:92>) | 历史阅读预算预期 ≤320，实际 3000 | 性能策略与旧预算分歧，需产品/性能证据统一 |
| [chat_lifecycle_generation_contract_test.dart:15](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/test/chat_lifecycle_generation_contract_test.dart:15>) | 缺少源码字面量 call-history-refresh | 源码字符串契约漂移，不能独立证明生命周期漏保护 |
| [同文件:144](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/test/chat_lifecycle_generation_contract_test.dart:144>) | 缺少直接 markMessageAsRead(force: true) 字面量 | 已读职责/时机变化，应改验可见性与水位行为 |
| [chat_reliability_regression_test.dart:99](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/test/chat_reliability_regression_test.dart:99>) | 会话已读队列缺 maxRetryAttempts=10 | F6 对应真实重试策略差异，不能仅改测试掩盖 |
| [history_window_pagination_integration_test.dart:863](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/test/history_window_pagination_integration_test.dart:863>) | 回到最新返回成功后 deferred 预期 1，实际 2 | ACK 后移到可见性证明，旧断言需按新语义核对 |
| [chat_architecture_closure_contract_test.dart:18](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/test/chat_architecture_closure_contract_test.dart:18>) | 应用层仍有 setMessageList 写入 | 最新窗口 reset 与 viewport cache 是实际例外，需收口或登记有边界的例外 |
| [im06_history_production_wiring_test.dart:57](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/test/im06_history_production_wiring_test.dart:57>) | 允许名单外存在原始 SDK 历史/搜索调用 | 有 5 个文件；需逐个明确取消、账号和 clearEpoch 责任 |
| [chat_open_non_blocking_history_contract_test.dart:193](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/test/chat_open_non_blocking_history_contract_test.dart:193>) | 缺少 localWindowIsEmpty 字面量 | 首屏策略变化，字符串断言失配 |
| [message_reconciliation_production_wiring_test.dart:100](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/test/message_reconciliation_production_wiring_test.dart:100>) | 缺少 trackSeqGaps: isGroup 字面量 | 应核对实际缺口修复行为，不能机械恢复旧参数 |
| [同文件:146](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/test/message_reconciliation_production_wiring_test.dart:146>) | 缺少 isActiveChatNearBottom(convId) 字面量 | 门禁调用形式变化，需用真正的视口行为验证 |

两处直接投影写入位于 [最新窗口 reset](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/chat_latest_window_reset_service.dart:801>) 和 [打开窗口缓存](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/chat_viewport/open_viewport_cache.dart:173>)。

五个 SDK 历史/搜索例外位于：[聊天媒体预取](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:8004>)、[单聊设置搜索](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/c2c_chat_settings_page.dart:227>)、[群设置搜索](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/group_chat_settings_side_card.dart:217>)、[coverage 修复调度器](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/chat_coverage_repair_scheduler.dart:107>)、[SeparateViewModel](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:2217>)。

这些调用的目的和保护条件不完全相同，不能仅凭“绕过适配器”就断言都存在数据错乱。实际问题是当前架构要求与生产例外没有保持可验证的一致性。

**十一、执行的验证与证据**

| 项目 | 范围 | 结果 |
|---|---|---|
| 现有测试第一批 | 58 文件，458 项 | 453 通过，5 失败，约 128.4 秒 |
| 现有测试第二批 | 46 文件，322 项 | 317 通过，5 失败，约 40.4 秒 |
| 现有测试合计 | 104 文件，780 项 | 770 通过，10 失败，无跳过 |
| 新增隔离实验 | 4 项 | 3 项反例断言失败，1 项行为观察通过 |
| 应用定向 analyzer | Chat、页面子模块、路由、窗口协调和 IM 服务 | 1 error、4 warning、49 info |
| Web debug 构建 | 实际整个 Web 应用编译 | 失败，约 100.7 秒 |
| 原生真机构建/联调 | Android/iOS、生产 SDK 和后端 | 未执行 |

3 个失败的隔离实验是用于证明缺陷的“期望正确行为”断言，保留在 artifacts 目录中，没有纳入正常 test/ 测试集。不要把它们与现有 10 个失败用例重复计数。

环境：Flutter 3.41.6，Dart 3.11.4；使用 --no-pub 避免本轮重新解析依赖。原生 VM 的聊天页 compile test 已包含在现有测试选择内。

定向 analyzer 最初把应用文件与 UIKit 包文件混在不同包上下文分析，产生了大量跨包导入噪声。正式结论采用重新执行的应用上下文结果 analyze-app.log，没有将初次 474 条输出计为 474 个真实问题。

主要证据：

- [验证汇总 JSON](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-full-chain-audit-2026-09-25/verification-summary.json>)
- [第一批测试文件清单](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-full-chain-audit-2026-09-25/test-selection.txt>)、[第二批测试文件清单](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-full-chain-audit-2026-09-25/test-selection-2.txt>)
- [第一批原始结果](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-full-chain-audit-2026-09-25/tests.jsonl>)、[第二批原始结果](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-full-chain-audit-2026-09-25/tests-2.jsonl>)
- [隔离实验源码](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-full-chain-audit-2026-09-25/audit_probes_test.dart>)、[最终隔离实验输出](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-full-chain-audit-2026-09-25/probes-final.jsonl>)
- [analyzer 正式输出](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-full-chain-audit-2026-09-25/analyze-app.log>)、[Web 构建错误](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-full-chain-audit-2026-09-25/web-build-stderr.log>)

可重跑隔离实验：flutter test --no-pub artifacts/chat-full-chain-audit-2026-09-25/audit_probes_test.dart --reporter expanded。当前代码下预计仍有 3 项失败，用于体现尚未修复的行为。

**十二、图谱依据、影响范围与审计边界**

检查基于分支 codex/gallery-chat-order，HEAD 26bcc02c68680725c1a91bf7548535c0645687a0，以及当时工作区已有的未提交改动。

AGENTS 中的仓库显示名与实际注册索引不一致；实际使用 99chat-ios-actions-precommit。原索引过期，且默认文件大小限制会漏掉大型 GlobalModel。本轮将最大文件大小提高到 2048KB，在独立存储路径完成重建后，用指定存储路径的 CLI 查询，避免 MCP 进程缓存旧库位置。

新索引统计：3285 文件、75433 图节点、170633 关系、656 个识别到的执行流程。索引时间 2026-09-24 18:00:49 UTC，即台北时间 2026-09-25 02:00:49。图节点包含文件等实体，不应把 75433 全部叫作函数数量。

图谱仍报告部分入口/被调方裁剪、21 次预算截断与 1 次深度上限；Dart 动态接收者也存在解析空隙。因此“某查询没有 process”或“0 caller”不是无影响证据。关键链路先 query/context，再用源码和实验补足。

| 改动热点 | GitNexus impact | 已识别范围 | 对后续修复的意义 |
|---|---|---|---|
| applyOutgoingSendResult | CRITICAL | 3 个直接调用者，涉及 9 个模块；无流程成员不代表无调用 | 发送主路径与拒绝同步共用，需跨来源顺序测试 |
| openOrReuseAppChat | CRITICAL | 13 个直接调用者，3 层内 54 个影响项，20 模块、3 流程 | 资料、搜索、群列表、推送等入口都需回归 |
| markRetry | UNKNOWN | 图谱未解析调用者，源码确认由已读清理服务调用 | 未视作安全或无用符号 |
| _clearChatLocalDraftAfterSend | LOW | 图谱识别 1 直接调用者、1 流程、1 模块 | 仍需用生命周期实验覆盖闭包/异步时序 |

CRITICAL 是修复这些枢纽的预先风险警告，不代表当前缺陷都是全站严重事故。本轮只做审计，没有对这些函数实施修改。若继续修复，应重新针对当时工作树做 impact；提交前按仓库要求完成 detect_changes，不能把本次只读结论当作提交门禁已经通过。

影响证据：[发送结果](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-full-chain-audit-2026-09-25/impact-applyOutgoingSendResult.json>)、[路由](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-full-chain-audit-2026-09-25/impact-openOrReuseAppChat.json>)、[重试](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-full-chain-audit-2026-09-25/impact-markRetry.json>)、[草稿](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-full-chain-audit-2026-09-25/impact-draft-clear.json>)、[索引重建日志](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-full-chain-audit-2026-09-25/index-full.log>)。

**十三、建议修复顺序与验收矩阵**

先修 F1 和 F2，建立可靠的草稿版本与发送终态规则；若 Web 是当前交付平台，同时修 F3。然后修 F4/F5 的导航与位置保留，再统一 F6 重试终态。最后处理性能预算、架构例外与测试重写。不要先大规模拆分大文件，再去找数据竞态；这样会扩大影响面并降低修复可验证性。

| 场景组 | 必测操作 | 验收条件 |
|---|---|---|
| 草稿 | 发 A 后输入 B，回调前后离页 | B 可恢复，A 不复活，另一会话不受影响 |
| 发送结果 | 成功/失败/超时/实时回流乱序 | 正式成功不被旧失败覆盖，不生成重复可见消息 |
| 首次导航 | 同会话并发、预热失败、推送竞争 | 普通同会话只建立一个路由，Future 退出语义正确 |
| 历史返回 | 历史中段/搜索定位进入二级页再返回 | 保持消息锚点与偏移，无无条件贴底 |
| 已读 | 回到最新过程中新增消息、SDK 永久失败 | 只 ACK 已看到的有限水位，失败有可诊断终态 |
| 生命周期 | 登出重登同账号、A 切 B、旧回调晚到 | 旧 owner/generation 不改变当前页面与数据库 |
| 清空/删除 | 清空历史时云请求未结束、撤回并发 | tombstone/clearEpoch 阻止旧消息复活 |
| 附件 | 上传中退出、结果未知、批量顺序、暂停恢复 | operationId 一致，无盲重发，顺序与取消正确 |
| 平台 | VM、Web 构建、Android/iOS 真机 | 公共接口一致，条件依赖正确，真机布局稳定 |
| 性能 | 数千条历史、快速拖动、来新消息、键盘与媒体返回 | 帧耗时、RSS、GC 有量化预算且不丢锚点 |

本报告已完成当前仓库可执行的源码、图谱、组件/集成测试和 Web 编译检查。真实双端收发、弱网、杀进程恢复、iOS/Android 媒体权限以及后端幂等/鉴权仍需要设备和服务端联调证据，不能用本轮单元测试结果替代。

