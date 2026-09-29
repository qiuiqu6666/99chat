# 99chat 稳定性与性能完整修复实施方案

> 状态：方案待实施，不代表已修复。日期：2026-09-28。
> 范围：两轮审查全部保留问题；Android 优先，同时覆盖 iOS。已有 A16 撤回失效退出修复保留，不重复实现。
> HEAD 0e7aa83bc5b096a99ff8bb424842404a3c901cb7；schema 2 dirty digest 0ed69bb536c9a772cab8fded0f0e43a942ac307a7e52a4c50930439090f15be3；cited manifest 120 条。仅排除本计划路径。
> GitNexus PDG 索引刷新于 2026-09-27 18:28:33 UTC；计划以带原有修改的工作区为准。代码基线、工作区指纹与图限制见 §4、§11。`[verified]` 为当前源码/已有执行证据；`[graph]` 为图关系；`[inferred]` 为拟采用的设计和影响推断；`[assumed]` 为待确认条件。

## 1. 目标

让启动、会话列表、聊天滚动和发送图片在弱网、大账号、低内存及前后台切换时保持可操作，消除已复现的错误状态、重复工作和无界积压。验收同时覆盖消息连续性、精确已读、账号隔离、撤回恢复及资金/订单状态正确性。

交付采用小批次提交和独立回退，每批同时包含实现、行为回归与必要指标。本轮只制定方案；安装包上线和服务端变更属于后续执行阶段。

## 2. 当前行为与范围映射

[verified] 两轮依据：`artifacts/program-performance-audit-2026-09-28/audit.md` 与 `artifacts/cross-module-report-verification-2026-09-28/merged-audit.md`。补充报告 17 个编号中：15 项保留，A10 与前轮启动项合并，A16 核心已修。上一轮的媒体、滚动、队列、搜索和钱包问题也全部保留在方案中。

| 工作包 | 覆盖问题 | 交付重点 |
| --- | --- | --- |
| W0 基线与诊断 | Profile 日志缺口、版本映射、既有失败断言 | 能在同一安装包/同一数据规模上复测，保留可信基线 |
| W1 网络与协议 | A01、A02、A03、A04 | 正确分片解码、健康判定和受控重连 |
| W2 会话恢复 | A05、A06 | 同代次登录单飞，区分恢复、校验与凭证刷新 |
| W3 请求归属与状态正确性 | A08、A13、前轮钱包/筛选/搜索迟到结果 | 旧任务不能覆盖新账号、新条件或新回答 |
| W4 启动与聊天常用路径 | A10、会话列表挂起、滚动重复 ACK、A16 回归 | 先有可恢复界面、读取有期限、无效确认不重复落盘 |
| W5 媒体内存与恢复 | Android 预采样、iOS 选图导出、无元数据预览、lost-data | 在原生解码前限预算，选择结果可恢复且目标正确 |
| W6 持续负载与隐藏工作 | A07、A11、A12、A14、A15、大通讯录投影、消息积压、搜索扫描预算 | 工作量有界、交互优先、必要恢复不丢失 |
| W7 iOS 数据库恢复 | A09 | 关闭阶段可定位，等待有可见结果，句柄安全隔离 |
| W8 备份同意与加密传输 | A17 | 显式备份同意、既有设置迁移、正式节点 HTTPS/TLS |
| W9 集成验收与分批发布 | 所有工作包 | 真机、故障注入、长会话、灰度与回退 |

## 3. 相关架构与必须保留的边界

[verified] 业务 JWT 与腾讯 IM 登录是两套状态；`SessionManager`、`LoginCoordinator`、原生 SDK 及自建业务 TCP 各自有恢复入口。UI 等待超时不等于底层登录或数据库操作取消。

[verified] 聊天经过 SDK 回调、调度/持久化、列表投影、阅读范围确认多层；单独限制内层队列不能保证外层待办有界。媒体同时经过系统 picker、原生解码、Dart 准备队列、发送槽与预览缓存。

[inferred] 保留以下不变量：

- 节点恢复先于首次 API 请求；读屏障恢复先于 SDK 回放；身份未确定时不进入可发送状态。
- 每个异步提交同时验证账号身份、会话代次和操作实例；同账号退出再登录也视为新代次。
- 已读只确认实际阅读范围；消息、撤回/删除记录和支付命令不能为了降负载而丢弃。
- UI 可超时降级，原生写操作只有实际完成或经已验证的取消/重置后才能释放其执行槽。
- 任何性能改动都不能以清空历史数据库、扩大无界缓存或忽略证书校验为代价。

## 4. GitNexus 影响分析

[graph] 本轮 8 个代表性共享入口执行 upstream/depth=3 影响分析（CLI `node .gitnexus/run.cjs impact <符号> --file <源文件> --repo . --direction upstream --depth 3`）。风险不以共享轴低分抵消。

| 目标 | 返回风险 | d1 数量 | 处理 |
| --- | --- | ---: | --- |
| SessionManager | CRITICAL | 16 | 会话、启动、profile、通话、直播、AI、搜索的登录/身份状态兼容；不扩展这些页面业务 |
| ApiNodeService | MEDIUM | 3 | 首请求节点、手动选线、自建 TCP 连接归属与健康 UI |
| prepareImageForChatSend | HIGH | 1 | sendImageMessage 的账号/目标、乐观行、稳定暂存、取消和重试保持 |
| AiAssistantApi.stream | UNKNOWN | 0 | 图 UNKNOWN；源码已确认 _beginAssistantReply 及真实 API 注入测试，不能视为无人调用 |
| ConversationTabStore._fetch | LOW | 2 | _loadOnce 纳入读取期限；GroupLiveIndexSyncService 同名字段误边已源码排除，不改直播查询 |
| ImMailboxRouter.dispatch | HIGH | 4 | adapter 接线及 durable recovery 分别处理；两个测试保留顺序和无损断言 |
| SqfliteLifecycleHost | CRITICAL | 3 | 前后台、全局模型与聊天投影消费保持；导入边不代表完整调用覆盖 |
| DeviceSyncService | CRITICAL | 13 | 启动/认证不阻塞、导航与媒体优先、活动计数配对、owner purge、设置同意迁移保持 |

[graph] SessionManager 的返回 d3 列表分页截断，本文只将完整 d1 名单用于逐项兼容，不能把 327 个计数当成已人工核实的完整运行时调用集合。其他图可能有 IMPORTS 或动态调用缺边。流程构建还报告候选/分支裁剪，654 个流程并非全程序覆盖。

<details>
<summary>全部 d1 名单与兼容安排</summary>

**SessionManager**：会话、启动、profile、通话、直播、AI、搜索的登录/身份状态兼容；不扩展这些页面业务。

- `lib/main.dart`：`main.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/bootstrap/home_bootstrap.dart`：`home_bootstrap.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/my_profile_detail.dart`：`my_profile_detail.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/pages/ai_assistant/ai_assistant_page.dart`：`ai_assistant_page.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/pages/app.dart`：`app.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/pages/group_live/group_live_authorize_page.dart`：`group_live_authorize_page.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/pages/group_live/group_live_room_page.dart`：`group_live_room_page.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/pages/group_live/group_live_routing.dart`：`group_live_routing.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/pages/home_page.dart`：`home_page.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/profile.dart`：`profile.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/services/account_session_service.dart`：`account_session_service.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/services/auth_session_service.dart`：`auth_session_service.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/services/call_launcher.dart`：`call_launcher.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/services/login_coordinator.dart`：`login_coordinator.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/utils/init_step.dart`：`init_step.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_search_view_model.dart`：`tui_search_view_model.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。

**ApiNodeService**：首请求节点、手动选线、自建 TCP 连接归属与健康 UI。

- `lib/main.dart`：`main.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/pages/settings/node_switch_page.dart`：`node_switch_page.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/services/friend_realtime_service.dart`：`friend_realtime_service.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。

**prepareImageForChatSend**：sendImageMessage 的账号/目标、乐观行、稳定暂存、取消和重试保持。

- `third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart`：`sendImageMessage`（CALLS，confidence=0.85）；按上述兼容安排验收。

**AiAssistantApi.stream**：图 UNKNOWN；源码已确认 _beginAssistantReply 及真实 API 注入测试，不能视为无人调用。

- 图未解析直接调用者；实际源码消费者按对应工作包覆盖。

**ConversationTabStore._fetch**：_loadOnce 纳入读取期限；GroupLiveIndexSyncService 同名字段误边已源码排除，不改直播查询。

- `lib/src/services/conversation_local/conversation_tab_store.dart`：`_loadOnce`（CALLS，confidence=0.85）；按上述兼容安排验收。
- `lib/src/services/group_live/group_live_index_sync_service.dart`：`_fetchIndexOnce`（CALLS，confidence=0.5）；按上述兼容安排验收。

**ImMailboxRouter.dispatch**：adapter 接线及 durable recovery 分别处理；两个测试保留顺序和无损断言。

- `test/chat_runtime_ingress_order_test.dart`：`main`（CALLS，confidence=0.85）；按上述兼容安排验收。
- `test/im_contracts_test.dart`：`main`（CALLS，confidence=0.85）；按上述兼容安排验收。
- `lib/src/services/conversation_local/conversation_sync_service.dart`：`_createMessageAdapter`（CALLS，confidence=0.85）；按上述兼容安排验收。
- `lib/src/services/im/im_recovery_worker.dart`：`run`（CALLS，confidence=0.85）；按上述兼容安排验收。

**SqfliteLifecycleHost**：前后台、全局模型与聊天投影消费保持；导入边不代表完整调用覆盖。

- `lib/src/pages/app.dart`：`app.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart`：`tui_chat_separate_view_model.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart`：`tui_chat_global_model.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。

**DeviceSyncService**：启动/认证不阻塞、导航与媒体优先、活动计数配对、owner purge、设置同意迁移保持。

- `lib/main.dart`：`main.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/bootstrap/home_bootstrap.dart`：`home_bootstrap.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/chat.dart`：`chat.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/conversation.dart`：`conversation.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/pages/app.dart`：`app.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/pages/home_page.dart`：`home_page.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/pages/settings/photo_backup_settings_cell.dart`：`photo_backup_settings_cell.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/platform/route_handler.dart`：`route_handler.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/services/auth_bootstrap_service.dart`：`auth_bootstrap_service.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/services/home_post_im_sync_service.dart`：`home_post_im_sync_service.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `lib/src/services/local_account_data_purge.dart`：`local_account_data_purge.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart`：`tui_chat_separate_view_model.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。
- `third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_more_panel.dart`：`tim_uikit_more_panel.dart`（IMPORTS，confidence=1）；按上述兼容安排验收。

</details>

## 5. 语句级约束与证据限制

[graph] 本轮使用已确认 current 的 GitNexus 1.6.12 runner，执行一次 `analyze --index-only --pdg`，生成独立外置索引。MCP 保留旧缓存并继续报告无 PDG，因此改用显式外置目录的 CLI。`impact _reconnect --mode pdg --direction downstream` 得到 4 个相关语句块，包含 `session_manager.dart:359` 的当前账号/登出条件与 `:360` 的 `_establish` 调用。`:357` 的精确行锚没有块，不能把图结果当作这条 guard 的完整控制证明。

[verified] 源码约束：`restore` 当前只对 UI 等待设置 8 秒期限并保留真实在途操作；定时 `_reconnect` 未登记自己的操作；签名刷新在 ready 状态再次调用 SDK 登录。拟改时必须保留迟到鉴权失效处理和 IM06 scope 配置。

[verified] `probeAll` 正在探测时直接返回，调用方可能继续读取旧结果；`probeNode` 接受任何 HTTP 状态为 normal。请求取消排除、探测共享 Future 与节点代次归属应作为同一个工作包实施，避免只修一个分支。

[inferred] 并发完成、共享字段和跨平台回调的全部关系不由 PDG 保证；上述顺序以当前源码及真实组件故障注入为主要约束。没有 taint 结果也不证明明文传输安全。

## 6. 具体修改设计

以下为拟实施设计，均标记为 `[inferred]`；对应现状已由源码或组件验证，新增类型/接口在描述中明确标为“拟新增”。

### W0：固定基线并补齐诊断

- 在 `lib/src/services/startup_perf_log.dart` 的 `consoleLoggingEnabled` 与现有埋点上开放受控 Profile 输出；复用已有聊天恢复诊断，不增加逐消息完整日志。
- 记录安装包版本、commit/工作区构建标识、设备内存档位、账号数据规模；阶段计时覆盖冷启动、首次列表可见、列表数据可用、相册完成到文件返回、准备/上传完成。
- 记录聚合指标：并发登录数、请求等待时长、队列在途/待办/最老年龄、无变化 ACK、数据库 close 阶段、图片原尺寸/采样尺寸。日志不含 token、聊天正文或联系人内容。
- 将审计中“断言缺陷存在”的 fixture 作为复制来源，为修复增加断言正确行为的正式测试，保留审计原文件。前轮 3 个源码字符串断言单独核对并以等价行为覆盖后更新，不能删断言来制造全绿。

### W1：修复网络协议与节点判定

范围：`api_client.dart`、`api_node_service.dart`、`friend_realtime_service.dart`、`friend_realtime_connection_io.dart`；AI SSE 部分同步修改 `ai_assistant_api.dart`。

- TCP/SSE 先对完整字节流使用有状态 UTF-8 转换，再分行/分事件。保留合法中文/emoji 跨多块；损坏字节、EOF 不完整帧应成为受控协议错误。帧长度上限须依据协议确认，不以替换乱码掩盖错误。
- `ApiClient._isNodeTransportFailure` 首先排除取消；给请求记录实际节点及节点代次，成功/失败只影响原请求对应的当前节点，旧节点返回不能污染新节点。
- `ApiNodeService.probeNode` 区分不可达、可达但不可用、健康；502/503/504 不进入健康候选。探针响应合同须与服务端确认，401/403 不能单凭“收到了响应”自动成为可用节点。`probeAll` 合并并等待同一个在途 Future，再原子提交同代次结果。
- `FriendRealtimeService.ensureConnected` 按新凭证/连接代次清除旧认证失败；同一无效凭证不无限重试。为认证等待及 pong 存活增加明确阶段期限，生命周期暂停期间区分系统冻结与服务器无响应，迟到旧连接事件不得改写新连接。
- 验收：全部合法 UTF-8 切分保持一致；连续取消不增加故障计数；快速 503 不赢过健康节点；旧节点迟到结果无效；更换有效凭证可恢复；同凭证认证失败不形成重连风暴。

### W2：统一恢复任务的所有权

范围：`lib/src/session/session_manager.dart` 的 `restore`、`_reconnect`、凭证刷新与现有登录入口；配合 `login_coordinator.dart` 和 `app.dart` 的恢复调用。

- 为 restore/reconnect/必要的重新认证统一登记当前 operation，finally 只释放自己的实例；相同账号代次同一时刻最多一个 SDK 登录。
- 按恢复原因区分冷启动、短暂回前台、真实断线、凭证将到期和账号变化（原因字段为拟新增）。已连接且身份有效的短前后台只做有期限的健康/鉴权检查，不重新初始化并双重登录。
- 签名刷新成功先更新缓存；是否必须重新登录由当前 SDK 连接状态、凭证到期语义与 SDK 已验证能力决定，不能每次刷新无条件再登录。保留踢下线、账号停用、JWT 过期与 IM06 初始化。
- UI 期限和底层任务生命周期分开：底层 SDK 未取消时不因 timeout 清空槽并启动竞争登录。异常情况下允许本地只读/可重试说明；确需重置时走经验证的串行退出/重建路径。
- 验收：两次快速 foreground 不额外重复 connect；多次断线时最大并发登录=1；旧失败不覆盖新成功；旧账号晚到的 401/完成事件不能登出新账号；真正当前账号失效仍正确退出。

### W3：请求结果归属与终态

- 关系校准：`ImSdkRelationshipReconcileService.resetForSession/_request` 给 phase、flight、成功/失败/finally 同时绑定 epoch+任务实例；旧任务只能结束自己。`ImSdkRelationshipDirectory` 的 capture token 不跨 reset 重用，旧 drop/apply 不能消费新 capture。新代 scheduled 时旧成功或旧失败晚到，仍必须完成新代首份好友/群快照。
- 钱包缓存：`WalletStore` 的余额、支付方式、订单卡及别名同时绑定 owner/sessionGeneration/storeEpoch。clear/换账号立即失效；每资源请求序号只允许最新提交，finally 只清自己的 Future；直接 update 也推进资源版本，避免旧 fetch 盖回。不得向新账号调用方返回旧账号的结果或 fallback。订单缓存和 alias 加有界淘汰，拟定初始上限 128 个 canonical order，实施时验证使用规模；不变更金额精度、20 秒余额 TTL、6 秒请求期限和订单幂等。
- 钱包筛选：`WalletRecordController.setFilter/load` 忙碌时保留一个最新条件，旧 success/error/finally 不提交到新条件；同一时刻一个执行、一个最新待办，快速 all→red→transfer 最终必须展示 transfer。`WalletController` 的直接缓存更新传入已有捕获身份。
- AI：`AiAssistantApi.uploadFile` 拟增可选取消令牌并传入当前 turn；`_beginAssistantReply` 的所有 success/catch/finally 首先验证活动请求和具体消息身份，不再按列表最后一条写回。停止、done、错误、无 done 的 EOF 和退出统一进入明确终态；停止后保留已生成文字但不能残留永久 streaming。历史 streaming 没有本地活动任务时显示可恢复中断状态；HTTP 取消不等于服务端取消生成，保留真实 CHAT_BUSY 的回退语义。验收覆盖 stop-after-delta 后重发、旧 CSV 上传成功/失败晚到、旧 finally、EOF、退出、切账号；新回答不受旧请求影响。
- 搜索：`searchConversationWithFilter` 先生成包含账号/会话/条件的请求归属，再决定 join；cloud/local/history 每个 await 后及结果/cursor/hasMore/降级标志/finally 提交前检查。不同条件不能先清空后被旧 loading 拦住；旧请求的错误不能禁用新查询。保留云→本地→历史顺序，本批不整体替换 singleton。
- 钱包历史附加项（前轮 P2 源码结论，尚无独立动态复现）：`WalletApi` 后台续页落盘后按账号/查询 scope 发提交版本事件，当前 `WalletRecordController` 合并本地缓存重读，不重新触发远端同步；隐藏记 dirty、退出取消订阅。验收首个空缓存、第一页 100 条和延迟第二页，不重进页面即可更新，旧 scope 不污染新筛选，通知不增加网络请求或重复行。

### W4：启动、会话列表与聊天滚动

- `lib/main.dart`：先渲染轻量、可恢复的启动状态界面；身份确认、节点选择、读屏障仍作为进入消息功能的依赖。安全存储读取失败与尚未完成各自显示明确状态和重试，不能误当作无账号。可选游戏/浮窗/代理/通知预热按需或首帧后执行；依赖它们的入口以未就绪状态占位，避免错误默认状态闪现。Web 字体与现有启动分支保兼容。
- `ApiClient.bootstrap/loadToken`：本地系统依赖有外部等待期限与受控失败；token 迁移写入串行且有代次检查。重试不与上一次未完成的写入竞争。
- 会话列表：`ConversationTabStore._load/_loadOnce/_fetch` 为每次读取绑定请求序号、账号/会话代次和分页游标。页面等待 Future 与实际 SDK 请求分开：超时结束 loading、保留已有行和重试入口，不推进 cursor/primed。物理在途额度直到真正完成才释放；建议初始页面预算 8 秒，同 runtime/type 最多 2 个只读请求以容纳一次受限重试，但须先验证 SDK 并发读取合同；不支持则保持 1 个，通过统一恢复协调器完成 runtime 重建后再读。连续重试只保留最新意图，不新增无界请求。旧返回不得覆盖新行、游标或 loading。
- 已读确认：`_scheduleVisibleIncomingProgress/_drainVisibleIncomingProgress` 与 `acknowledgeVisibleHistoryMessages` 使用明确结果（拟新增 changed/noChange/stale/retryableFailure），保留既有 bool 接口包装或逐调用者迁移。changed/noChange 均完成去重；仅真正可重试失败保留重试。阅读证明限定账号、会话、访问/清空/窗口代次和精确 ID，集合大小受当前窗口约束；不能仅用内存未读集合过滤掉持久层 deferred 候选。先修重复提交，再优化仅扫描已挂载且几何有效的阅读边缘及新越过区间。
- 验收：挂起会话读取超过页面预算后不再无反馈转圈；连续 100 次重试不超过物理额度；新读取成功后旧响应不能覆盖。旧历史 30 次小幅滚动时同 proof 内每个 ID 最多交付一次，未进入阅读范围的新消息仍未读=1；真实新增阅读、写失败重试、遮挡返回、trim、换会话、清空全部保留正确语义。保留 A16 的失效退出与迟到补偿回归，不顺带改写撤回流程。

### W5：图片解码、相册导出与恢复

1. Android：在 `prepareImageForChatSend` 调用 native 压缩前，按已验证编码尺寸及现有目标计算保守采样。当前正常长边 2560、长图高度上限 8192、保留宽度 1280、JPEG 质量 88；这些默认不随本批降低。8000×6000 照片通常采样 2 才保持目标所需清晰度，不能一律采样 4。小文件 JPEG 的免压缩判断也需检查像素量；未知尺寸不直接放行任意整图解码。
2. 准备队列增加像素/估算工作内存准入：先限制单项 native decode，再决定两项可并行或大图串行。上传槽与准备槽独立，accepted 工作不依赖页面仍在显示或必须有渲染帧；finally 释放预算。保留 GIF、EXIF/旋转、HEIC、透明度既有行为和稳定文件重试。
3. iOS：当前瓶颈发生在 Dart 收到文件列表之前。优先对锁定的 image_picker_ios 做可维护的本地最小补丁（拟新增本地插件目录并固定依赖），保留平台接口与 picker 体验；不改全局 Pub Cache。限制原生导出并发、使用独立自动释放范围；能获取编码文件时在有效访问期内复制到应用拥有的临时路径。必须转换时先用 ImageIO 按目标下采样，再编码，避免完整 NSData→UIImage 后才缩小。只加 Dart 队列或 maxWidth 不能算本项完成。暂保留整批返回合同，渐进式通道事件不是本批必需重构。
4. 预览：`wrapPreviewDecode` 与 resolution policy 对无 message 元数据走有双边上限的 fit 解码，禁止扭曲和放大小图；当前 Flutter 支持 ResizeImagePolicy.fit。处理 normal FileImage 和已编辑文件的提前返回，保留经验证的分块/tiled 路径。允许独立于消息的媒体尺寸输入，朋友圈/收藏/AI/头像受同一保护；后续缩放提升清晰度仍有像素/长边预算，不能永久把长截图缩成不可读小图。
5. Android lost-data：拟新增单一 picker 恢复协调器；发起前持久化操作 ID、账号/代次、来源和目的会话/草稿，不保存 token。认证及插件就绪后单消费者读取恢复数据，先可靠暂存再幂等认领。已有已接受的发送任务恢复原任务；尚未确认发送的恢复原目的地草稿，不能自动发送到当前另一个会话。丢 journal/换账号/缺路径均有受控提示且不猜目的地。
6. 验收：1/2/9 张 12MP/48MP、低字节高像素、旋转、HEIC/GIF、透明 PNG、窄长截图、坏文件；iPhone 本地与 iCloud 分别测“点完成→Dart 文件列表”和后续准备。外部相册期间回收 Android 宿主再返回，验证同账号原目的地只恢复一次、跨账号不发送。相邻预热、编辑后预览、宽屏/Web 与附件重试均不回退。

原生兼容门槛：image_picker_ios 的补丁影响全部调用入口，必须保留每次调用自己的 maxWidth/maxHeight/quality/requestFullMetadata 合同，不能全局套用聊天 2560 预算。原文件导出后分别验证小 JPEG 免压缩、GIF、HEIC 的方向和元数据路径，不能假定后续一定重新编码。恢复协调器覆盖 ChatGalleryPickUtils、SystemMediaPicker 等共享同一插件缓存的入口，journal 含 entry type 并按原入口恢复；实施时枚举剩余直接调用者，避免全局读取缓存后吞掉或误绑定 AI/头像等非聊天结果。

### W6：负载治理与交互期调度

- 消息总预算（最后启用）：`ImMailboxRouter.dispatch` 与 adapter 的待准入、SDK pending、失败区及已排队对象统一计数。SDK 回调不能 await 反压，不能把旧 Future 链换成另一个无界 Map。保留现有 worker 数作为初始值；普通有 ID 的入站消息只有证明 SDK 历史可补拉后才可压缩为有限会话 dirty/游标，dirty 自身也须有上限，必要时折叠账号级恢复标记。撤回/删除/custom/出站相关事件必须先可靠落盘，再移交有界恢复指针；现有有限失败缓存会淘汰，不能冒充无损溢出。恢复 worker 遇满载延期且不标完成，同会话真实 handler 未结束时仍占槽。最早 append 阶段也纳入预算证明。10,000 条突发夹控制事件恢复后最终内容、顺序、未读与无压力基线一致；任一类别的重放/持久保证未证明，则该类别不能开启新压缩。
- 搜索扫描：W3 后，将成员/日期/文件及媒体三条降级扫描改成有限可继续工作片。拟定初值每次最多 3 页/150 条，250ms 只约束是否开始下一页，不能取消已发生 SDK await。预算耗尽保留游标并提示继续，不等同无更多历史；空页、重复游标、游标循环分别处理，离屏停止启动下一页。第 4 页才出现的结果在下次继续可找到且不重复。
- AI 输出：W3 终态正确后再合并 delta，局部更新活动回复，每帧最多一次发布/滚动；前台最长等待拟定 50ms 并提供无渲染帧的定时兜底，终态立即 flush。按用户是否在底部跟随控制滚动，阅读旧消息/搜索/拖动时不拉回；旧 turn 的已排回调不得滚动新页面。100 个同帧 delta 合并但最终文字完全一致，长历史与 markdown 保持可读。
- A07：`_waitUntilRunnable` 返回 runnable/deferred/stale，15 秒等待结束不再自动放行活跃聊天中的全量校准。W3 代次正确后，当前代每类任务只保留一个 deferred，闲时/前台信号唤醒；单一有界后备 timer，reset/dispose 取消，不用每条事件建 timer。
- 大通讯录：`ContactListWithPresence` 每轮只捕获一次有版本的 ordered IDs，用 cursor 消费；userId→行元数据索引避免线性查找。小片计算与发布分离：先 80 条可见，后续按 80→160→320 等几何增长发布，避免每固定小批都复制全部旧列表。保留星标、备注、分组/#、筛选、顶部/计数行与可见锚；隐藏/滚动暂停新片，版本变更使旧 buffer 失效。以 1k/5k/10k 访问/比较/copy 数验证复杂度，不能只看到 yield 就算优化。
- A11：联系人采集先区分完整成功、无权限与失败；只有完整成功才能计算删除。后端合同确认后，FULL/无本地基线发全量，INCREMENTAL 只发新增/指纹变化及明确 deletedIds；保持每批 100 条，complete 成功且身份有效才原子推进基线。无变化时按合同零 item，不能假设可省略 complete。后端必须证明 merge/replace、缺席项、empty delta、批次重试、设备/账号边界及 complete 原子性；未证明前只做本地 diff/错误分类，继续兼容发送，不开启生产差量。
- A12：`PhotoSyncCollector.prepareOne` 在 length 已知后、hash stream 打开前拒绝超限视频，区分永久跳过和暂时不可用；上传层保留防御检查。进度拟改为 owner+asset 的按项存储，批量/按项写入，旧 JSON 分批迁移完才切换；不能每项重编码全快照。若新增 SQLite 表必须先接 W7 生命周期、账号清理和 W8 同意边界。保持前台/闲置 3 分钟/网络/键盘/聊天/媒体优先/800ms 间隔；验证上传回执到持久化之间重启的服务端内容 hash 去重，不能承诺网络 exactly-once。
- A15：钱包隐藏期间的余额事件只记 dirty；恢复可见合并一次刷新，dirty 不被原 10 秒入口节流吞掉。隐藏期间已在途请求允许必要的同身份缓存提交，但不排下一轮页面请求；路由遮挡也视为不可见。账务确认/未决订单恢复留在必要服务中，不能随页面隐藏停掉。验收隐藏 100 个事件产生 0 个 UI getWallet，返回一次刷新，dispose 后为 0。

### W7：iOS 数据库生命周期

范围为 `SqfliteLifecycleHost/Guard` 及聊天 `_readHistoryRollbackFacts` 的结果消费。本项拆两阶段交付。

1. 先交付可诊断、有界的等待：关闭轮次记录 owner/epoch、各 store 的起止及待完成 Future；只允许一轮真实 close。调用方有预算与取消，拟增 ready/deferred/cancelled 结果，watchdog 可标 degraded 并结束 UI 等待，但不解除真实 close fence、不重新打开同一路径/句柄。生命周期队列保留最新 desired state，不能因旧 pause 永不结束而无限堆积新事件。
2. 晚到 close 真正完成后，仅当前 epoch 且 desired foreground 才恢复一次 guard/重新水合；background 继续禁写。close 抛错不自动等于安全关闭。聊天命令遇 deferred 保留事实与有限补偿，不把远端已成功操作显示成失败或重新发送，也不做 500ms 无限循环。
3. 自动重开/重建必须取得当前 sqflite/iOS 原生约定与真机证据；证据不足时维持安全关闭态并提供明确恢复说明，不宣称自动恢复全部完成。不得清库恢复或绕过 guard。
4. 验收：永久 pending 的 close 超过预算后调用方得到 deferred、没有第二句柄/第二 close；50 次 pause/resume 只跟随最新状态；账号切换取消旧等待；晚到完成只恢复当前前台一次；正常后台关闭原保护保持。

### W8：备份同意与正式节点加密

- `PhotoBackupConsent` 拟新增 v2 目的同意状态（disabled/enabled/pendingConfirmation）与明确选择来源，和 OS 相册授权分别存储。删除启动/authorized/limited 回调的自动 enable 路径，主动发图不触发整库备份。
- 迁移：缺键和旧 false 保持关闭；旧 true 无法证明来自明确选择时进入待确认并停止新的整库上传，在设置页重新确认；保留已备份云数据和本地文件。明确启用但 OS 权限不足时展示未就绪，不扫描上传；关闭立即阻止新任务并取消可取消的在途传输。身份切换后旧授权回调不能改新账号状态。
- 验收 fresh/legacy false/legacy true × authorized/limited/denied，只有目的同意与 OS 权限同时满足才进入原有闲时调度；用户主动发送照片/视频不受影响。

- `lib/config.dart`、`ApiNodeService.catalog`、`ApiClient.resolveBaseUrl`、实时 endpoint/connection：先确认并部署有正确域名证书的 HTTPS/TLS 服务，再迁移默认与持久化已选节点；运行时覆盖、编译期覆盖及旧缓存配置都需检查。
- 正式包禁止敏感 API/TCP 降级到明文；证书错误明确失败，不设置全信任回调。先盘点其他 HTTP 资源和兼容需求，再收紧 Android 网络配置，避免把历史媒体全部断掉。
- 验收正式构建的实际连接配置与重定向链，而不是只检查默认字符串。TLS 服务未就绪时，本子项不能宣告完成，但不阻塞其他客户端缺陷修复。回退只切至已验证的安全节点，不能恢复明文作为永久兜底。

## 7. 实施顺序、依赖与并行方式

| 波次 | 工作 | 进入条件 | 完成后可独立交付 |
| --- | --- | --- | --- |
| 0 | W0；固定源码基线与现有 A16 修复 | 保存当前未提交成果及构建映射 | 诊断和行为基线 |
| 1 | W1、W2；W3 的状态正确性；W8 备份同意 | 每个拟改符号先 impact，确定文件归属 | 协议/恢复/归属小修复；同意设置迁移 |
| 2 | W4 与 W5 并行 | 同会话/账号归属回归先就绪 | 四个高频场景改善 |
| 3 | W6；W7 的观测与受控恢复 | 队列重放分类、数据库关闭语义明确 | 大账号和长会话治理；iOS 恢复保护 |
| 并行依赖线 | W8 TLS；A11 后端差量合同 | 服务端和证书/协议确认 | 独立联调与兼容发布 |
| 4 | W9 全链路验收与逐步放量 | 所有目标批次通过行为与平台检查 | 完整修复版本 |

大文件 `tui_chat_separate_view_model.dart` 由同一集成人维护；图片、已读、数据库门槛、A16 回归的提交顺序固定，禁止多个任务同时覆写。`api_client.dart` 先合并 W1 的节点归属，再接 W4 的启动状态；AI 页面先 W3 终态/请求归属，再 W6 输出节流；设备同步先 W8 同意边界，再 W6 快照优化。

每个工作包拆为可验证的小提交；不做跨模块大重写。依赖尚未满足的子项保持“未完成”，不能用其他批次通过代替。工期在 W0 基线、iOS 构建环境和服务端合同确认后估算，不虚构确定天数。

## 8. 验收策略

已有可执行验证入口均从仓库或前轮执行中确认。本轮规划没有重跑测试；不把前轮 44 项诊断/回归通过当作本次修复完成。

| 工作包 | 正式已有回归及诊断来源 | 修复后新增/改变的验收 |
| --- | --- | --- |
| W1/W2 | test/api_node_service_test.dart、test/friend_realtime_endpoint_test.dart、test/session_manager_test.dart；审计 network 与 session fixtures | 取消不计错、503 不健康、UTF-8 全切分、认证换凭证恢复、最大并发登录 1、旧完成不污染 |
| W3 | test/search_account_owner_test.dart、test/conversation_filter_search_test.dart；审计 wallet/search/AI/relationship fixtures | 旧成功/失败/finally 三种交错、新条件覆盖旧意图、停止回答终态 |
| W4 | test/conversation_tab_store_test.dart、test/history_visible_deferred_progress_test.dart、test/chat_visible_incoming_regression_test.dart、test/chat_session_recovery_test.dart | 挂起/迟到读取、精确 ACK 去重、A16 不调用旧 scope SDK |
| W5 | test/chat_image_send_target_size_test.dart、test/outgoing_media_work_queue_test.dart、test/chat_system_picker_failure_test.dart、test/chat_system_picker_video_staging_test.dart、test/gallery_send_without_frames_test.dart、third_party/tencent_cloud_chat_uikit/test/image_preview_resolution_utils_test.dart | native 预采样/预算、选图顺序/错误、无元数据实际 decode、lost-data 幂等恢复 |
| W6 | test/chat_runtime_ingress_order_test.dart、test/im_contracts_test.dart、test/scale_ai_layout_test.dart；设备同步诊断 | 有限总保留量且最终无损、3 页停止/继续、离底不跳、隐藏钱包不请求 |
| W7/W8 | 生命周期及设备同步诊断、现有 mobile_lifecycle_recovery_contract_test.dart、friend_realtime_endpoint_test.dart | close 未完成时受控降级、真实完成才开库、明确同意迁移、实际 TLS 配置 |

正式新增测试建议独立落在 test/ 下：node_failover_recovery_test.dart、ai_assistant_turn_lifecycle_test.dart、picker_lost_data_recovery_test.dart、chat_read_ack_idempotency_test.dart（以上为拟新增名称，实施前检查是否已有同职责文件）。测试真实组件与边界替身组合，审计原始断言保留为历史证据。

验证命令按工作包运行，例如：

```powershell
& 'E:/flutter/flutter/bin/flutter.bat' test --no-pub test/api_node_service_test.dart test/friend_realtime_endpoint_test.dart test/session_manager_test.dart
& 'E:/flutter/flutter/bin/flutter.bat' test --no-pub test/conversation_tab_store_test.dart test/history_visible_deferred_progress_test.dart test/chat_visible_incoming_regression_test.dart test/chat_session_recovery_test.dart
& 'E:/flutter/flutter/bin/flutter.bat' test --no-pub test/chat_image_send_target_size_test.dart test/outgoing_media_work_queue_test.dart test/chat_system_picker_failure_test.dart test/chat_system_picker_video_staging_test.dart test/gallery_send_without_frames_test.dart
& 'E:/flutter/flutter/bin/flutter.bat' test --no-pub test/chat_runtime_ingress_order_test.dart test/im_contracts_test.dart test/scale_ai_layout_test.dart
& 'E:/flutter/flutter/bin/flutter.bat' analyze --no-pub
```

新增测试创建后加入所属包。iOS 原生补丁必须在 Mac 确认实际 workspace/scheme 后构建并真机验证；本机 Windows 不宣称已有可运行 iOS 构建命令。每批通过后仅在新改动或失败需要时扩大回归，最终集成再统一全套检查。

真机矩阵（拟定验收协议，非已有测量）：Android 低内存机与主流机各一台，iOS 旧机与主流机各一台；60/120Hz 按设备实际刷新率记录帧预算。小账号和大账号分别覆盖冷启动、短前后台、弱网断连、离线消息洪峰、长历史、连续选图。

- 每个包记录首个可交互帧、会话可用时间、UI/raster 帧耗时 P50/P95、超帧预算比例、PSS/native heap 峰值、选图返回/准备/上传耗时、错误与恢复次数。
- 同设备同构建模式同数据和素材进行前后对照，冷启动建议至少 30 次，媒体场景至少 20 轮，滚动与恢复各重复固定脚本；至少完成一轮 60 分钟混合长会话。次数为拟定验证方案，执行时保留原始结果。
- 硬行为门槛先固定：无跨账号回写、无消息丢失/重复发送、无错误已读、无双登录、无无限无反馈等待、无未同意备份；不得新增崩溃/ANR/OOM。
- 性能预算在 W0 根据目标机型和基线写入验收记录再冻结；至少要求针对缺陷的工作量上界成立、目标场景指标改善且其他主场景无超出基线波动的回退。若不能达到预算，相关性能项保持未完成，不用桌面测试耗时替代真机结果。

## 9. 风险、发布与回退

[graph] SessionManager 为 CRITICAL；共享数据库生命周期、DeviceSyncService 同为 CRITICAL；图片准备与 ImMailboxRouter.dispatch 为 HIGH。实施前显式报告风险并逐个拟改符号重新 impact；本方案的代表性分析不能代替所有编辑前检查。AiAssistantApi.stream 是 UNKNOWN 而不是低风险。

[inferred] 三个最容易引入回归的错误做法必须禁止：timeout 后把尚未结束的原生任务当作已取消；将可重放消息和不可重放控制事件混为一类丢弃；只改缓存/队列的局部而遗漏前置原生分配或外围待办。

首批尽量不做破坏性数据库迁移；确需新增日志/同意记录采用可向后读取的版本字段，明确回滚版本如何处理新数据。不能通过回滚重新启用已撤回的备份同意。

建议发布顺序：内部合成账号验证 → 小范围真实设备 → 有分批渠道时按小比例逐步扩大。具体比例由现有发布渠道能力确认，不能假设已有远程开关。观察至少一个真实使用周期，并按 W0 的匿名聚合指标判定。

任一新增跨账号写入、消息缺失/重复、错误已读、资金状态错误直接停止该批；崩溃/ANR/OOM 或关键 P95 持续超出冻结预算停止扩大。回退对应独立提交/客户端版本或已存在且经验证的功能开关；保留待发消息、恢复游标、订单幂等键与备份同意，不回滚用户数据。尚未上线时先修正，不做生产试错。

## 10. 预期修改文件

以下是已定位的现有修改域；图中直接依赖不等于全部要修改。每个方法真正编辑前仍执行 impact。拟新增协调器/进度存储/原生插件均单独列出，不假称已经存在。

| 文件 | 现有符号/职责 | 目的 |
| --- | --- | --- |
| `lib/src/services/startup_perf_log.dart` | `consoleLoggingEnabled`、`mark` | W0 Profile 聚合观测 |
| `lib/src/api/api_client.dart` | `_isNodeTransportFailure`、`bootstrap`、`loadToken` | W1 请求节点归属；W4 启动受控等待 |
| `lib/src/services/api_node_service.dart` | `probeNode`、`probeAll`、`noteRequestFailure`、`catalog` | W1 健康合同/共享探测；W8 安全节点 |
| `lib/src/services/friend_realtime_service.dart` | `ensureConnected`、`_connect`、`_startPing` | W1 凭证与连接阶段期限 |
| `lib/src/services/friend_realtime/friend_realtime_connection_io.dart` | `connect` | W1 流式字节解码 |
| `lib/src/session/session_manager.dart` | `restore`、`_reconnect`、`_refreshCredentialInternal` | W2 所有权和刷新语义 |
| `lib/src/services/login_coordinator.dart` | `recoverOnForeground` | W2 有原因的恢复 |
| `lib/src/pages/app.dart` | `_scheduleResumeCheck`、`_checkIfConnected` | W2 恢复调用；W4/W5 生命周期接入 |
| `lib/main.dart` | `main`、`finishDeferredBootstrap` | W4 首帧状态与依赖拆分 |
| `lib/src/services/conversation_local/conversation_tab_store.dart` | `_load`、`_loadOnce`、`_fetch` | W4 UI期限和物理在途额度 |
| `third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart` | `_scheduleVisibleIncomingProgress`、`_drainVisibleIncomingProgress` | W4 精确阅读证明与去重 |
| `third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_bounded_history.dart` | `acknowledgeVisibleHistoryMessages` | W4 明确结果语义 |
| `third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_search_view_model.dart` | `searchConversationWithFilter`、`_searchConversationFilterViaLocalMessages`、`_searchConversationFilterViaHistoryScan`、`loadMediaAndFileForConversation`、`loadConversationAssets` | W3 请求归属；W6 有界可续扫描 |
| `third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitSearch/tim_uikit_conversation_filter_msg_page.dart` | 文件级职责，见对应工作包 | W6 预算耗尽/继续查找展示；实施前补窄读 build 分支 |
| `third_party/tencent_cloud_chat_uikit/lib/ui/utils/chat_media_send_utils.dart` | `prepareImageForChatSend`、`resolveChatImageSendTargetSize` | W5 Android 原生解码前采样 |
| `third_party/tencent_cloud_chat_uikit/lib/data_services/message/outgoing_media_work_queue.dart` | `OutgoingMediaWorkQueue` | W5 工作内存准入 |
| `third_party/tencent_cloud_chat_uikit/lib/ui/utils/chat_gallery_pick_utils.dart` | `ChatGalleryPickUtils` | W5 picker 合同/恢复标识 |
| `lib/src/services/system_media_picker.dart` | `SystemMediaPicker` | W5 单消费者恢复入口协调 |
| `third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_more_panel.dart` | `_sendImageMessage` | W5 发起前持久化目标 |
| `third_party/tencent_cloud_chat_uikit/lib/ui/widgets/image_screen.dart` | `ImageScreen` | W5 未知尺寸及编辑文件分支 |
| `third_party/tencent_cloud_chat_uikit/lib/ui/utils/chat_message_preview_image_resolver.dart` | `wrapPreviewDecode` | W5 FileImage/共享预览保护 |
| `third_party/tencent_cloud_chat_uikit/lib/ui/utils/image_preview_resolution_utils.dart` | `imagePreviewDecodeTarget`、`imagePreviewDecodedProvider` | W5 fit 和分级预算 |
| `lib/src/api/ai_assistant_api.dart` | `stream`、`uploadFile` | W1 SSE；W3 上传取消 |
| `lib/src/pages/ai_assistant/ai_assistant_page.dart` | `_beginAssistantReply`、`_stopAssistantReply` | W3 turn终态；W6 合并输出/跟随意图 |
| `lib/src/services/im_sdk_relationship_reconcile_service.dart` | `resetForSession`、`_request`、`_waitUntilRunnable` | W3 epoch；W6 deferred |
| `lib/src/services/im_sdk_relationship_directory.dart` | `reset`、`beginFriendCapture`、`beginGroupCapture` | W3 capture不重用 |
| `lib/src/pages/wallet/wallet_store.dart` | `getWallet`、`getPayMethods`、`getOrderCard`、`clear`、`updateWallet` | W3 缓存所有权/资源版本 |
| `lib/src/pages/wallet/record/wallet_record_controller.dart` | `load`、`setFilter` | W3 最新筛选；后台提交本地刷新 |
| `lib/src/api/wallet_api.dart` | 文件级职责，见对应工作包 | W3 历史后台持久化提交通知（仅本地更新，不扩大网络请求） |
| `lib/src/pages/wallet/wallet_controller.dart` | `load`、`_onBalanceChanged` | W3 身份参数；W6 active/dirty |
| `lib/src/pages/wallet/wallet_screen.dart` | `_WalletTabLifecycleState` | W6 可见性/遮挡 |
| `lib/src/widgets/contact_list_with_presence.dart` | `_pumpDirectoryProjection`、`_appendFriendsToAz`、`_composeContactEntries` | W6 分片计算和几何发布 |
| `lib/src/services/im/im_mailbox.dart` | `ImMailboxRouter.dispatch` | W6 总准入预算 |
| `lib/src/services/im/tencent_advanced_message_adapter.dart` | `_deliverSdkRealtime`、`_attemptSubmit`、`_retainFailedIngress` | W6 分类移交而非丢弃 |
| `lib/src/services/im/im_recovery_worker.dart` | `run` | W6 有界恢复与完成语义 |
| `lib/src/services/conversation_local/conversation_sync_service.dart` | `_createMessageAdapter` | W6 入口接线与聚合统计 |
| `lib/src/services/sqflite_lifecycle_host.dart` | `handle`、`_closeDatabases`、`waitUntilWritesAllowed` | W7 真实关闭与外部期限分离 |
| `lib/src/services/sqflite_lifecycle_guard.dart` | `closeDatabase`、`resume` | W7 句柄安全 |
| `third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart` | `sendImageMessage`、`_readHistoryRollbackFacts` | W5 保持媒体幂等；W7 消费deferred；revokeMsg仅保护不重写 |
| `lib/src/services/device_sync_service.dart` | `_syncContacts`、`_syncAuthorizedAlbum`、`handlePhotosAccessGranted` | W6 差量/按项进度；W8 不自动授权 |
| `lib/src/services/contact_sync_collector.dart` | `collectAll` | W6 完整采集与失败分离 |
| `lib/src/services/photo_sync_collector.dart` | `prepareOne` | W6 超限先拒绝 |
| `lib/src/services/photo_backup_consent.dart` | `enabled`、`setEnabled`、`enableIfUnset` | W8 v2同意与迁移 |
| `lib/src/pages/settings/photo_backup_settings_cell.dart` | `_change` | W8 明确选择/待确认 |
| `lib/config.dart` | 文件级职责，见对应工作包 | W8 默认端点；与持久节点及运行时覆盖联合验收 |
| `pubspec.yaml` | 文件级职责，见对应工作包 | W5 本地原生插件固定（选定此路径后） |
| `pubspec.lock` | 文件级职责，见对应工作包 | W5 锁定精确依赖，禁止顺带大升级 |

拟新增：picker恢复协调器、启动可恢复状态组件、账户相册进度存储、必要的结果类型和正式行为测试；iOS 原生插件选择最小本地补丁时新增本地固定包。确切文件/接口在相关 impact 和平台合同确认后建立，不创建万能全局调度器。

## 11. 可复用实施上下文

保存说明：规范 helper 已成功生成 schema-2 源码指纹；其 write-plan 因不支持 Windows 而拒绝写入。用户随后明确授权普通 Markdown 保存，本文件按该授权创建，不冒称 helper 写入成功。正文与上下文均已完成核对；该保存例外不取消实施前源码漂移、影响分析和测试要求。

<details>
<summary>实现上下文与完整源码指纹（JSON，供后续执行核对）</summary>

```json
{
  "implementation_context": {
    "task_summary": "覆盖两轮审查的完整稳定性/性能修复；本文件为计划，不是已实现结果",
    "acceptance_criteria": [
      "W1–W8硬行为回归通过",
      "无跨账号回写/错误已读/丢消息或重复命令",
      "四个主场景达到W0冻结的真机预算",
      "后端及iOS门槛落实",
      "灰度及回退验证完成"
    ],
    "evidence_provenance": {
      "schema_version": 2,
      "head_commit": "0e7aa83bc5b096a99ff8bb424842404a3c901cb7",
      "generated_plan_path": "docs/plans/2026-09-28-gitnexus-plan-cross-module-stability-repair.md",
      "global_dirty_digest": {
        "algorithm": "sha256",
        "canonicalization": "gitnexus-evidence-provenance-v2 NUL-framed UTF-8 records",
        "value": "0ed69bb536c9a772cab8fded0f0e43a942ac307a7e52a4c50930439090f15be3"
      },
      "cited_path_manifest": [
        {
          "path": "AGENTS.md",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:f3db1dec2e7d7757b7f53d37d91ac58d29e4fadf400f93dd9c274fb91b84c7ac",
          "index_digest": "sha256:f3db1dec2e7d7757b7f53d37d91ac58d29e4fadf400f93dd9c274fb91b84c7ac",
          "worktree_digest": "sha256:f3db1dec2e7d7757b7f53d37d91ac58d29e4fadf400f93dd9c274fb91b84c7ac",
          "untracked_digest": "absent"
        },
        {
          "path": "artifacts/cross-module-report-verification-2026-09-28/ai-wallet/ai-wallet-verification.md",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:c3c3d2780168c6c92a1862bdc83b1a307890bd45dc906b70480dfbaf64d29cde"
        },
        {
          "path": "artifacts/cross-module-report-verification-2026-09-28/ai-wallet/ai_wallet_fault_injection_test.dart",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:9fc9e71d223be02b68d81695428c4b51fdfea26e8db6d03bb2bb19a014bf5a0e"
        },
        {
          "path": "artifacts/cross-module-report-verification-2026-09-28/lifecycle-sync/device_sync_repro_test.dart",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:a8c491bd0df4ffcbc14454891c47d04dbaa705acbccfe0e9beac687e980fb409"
        },
        {
          "path": "artifacts/cross-module-report-verification-2026-09-28/lifecycle-sync/lifecycle-sync-verification.md",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:5e55da9629e750f6373d47919763542b1bab86b34fa7dc82294f6cae64f433df"
        },
        {
          "path": "artifacts/cross-module-report-verification-2026-09-28/lifecycle-sync/relationship_lifecycle_repro_test.dart",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:7acad2016a43f8f69abfdee340fffffff92543ac76c151b8cc6503ec2ba3c2c2"
        },
        {
          "path": "artifacts/cross-module-report-verification-2026-09-28/lifecycle-sync/sqflite_close_gate_repro_test.dart",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:d10d4879fa51ad0faa9f3474efeda6fa5fe3ec2b70a1686e5be4fe87f89e901b"
        },
        {
          "path": "artifacts/cross-module-report-verification-2026-09-28/merged-audit.md",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:d97fa4526a582f70ebccd0cfd1177035eea29864f7eea6d9cf609b3e9a7c3506"
        },
        {
          "path": "artifacts/cross-module-report-verification-2026-09-28/network/network-verification.md",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:96b92d317812069d96938885ba93152495a355e5016909de81c7e13506284e57"
        },
        {
          "path": "artifacts/cross-module-report-verification-2026-09-28/session/session-verification.md",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:95d04a3872aa4e8746249ddaa6e15d504b92a7214c817a0cd6281130193aefbb"
        },
        {
          "path": "artifacts/cross-module-report-verification-2026-09-28/session/session_verification_test.dart",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:33e0a75116a344ca1ce0f3e82de1f496c1ed84e2c3e4689a36a963af5bd937eb"
        },
        {
          "path": "artifacts/cross-module-report-verification-2026-09-28/verification-summary.md",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:2ea821b1ff020a85393e240940bfdb58795f4b0c3440f2272a6119cee5b6b59c"
        },
        {
          "path": "artifacts/program-performance-audit-2026-09-28/audit.md",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:abb44398710e17616d4abdd5f14aef24123af7286fe06fea537a6a8158949762"
        },
        {
          "path": "artifacts/program-performance-audit-2026-09-28/chat-audit.md",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:8e481285c60970e8d1353938bd86bbc79b86ac3dcedb6ee23c2bf6bc1c035bdc"
        },
        {
          "path": "artifacts/program-performance-audit-2026-09-28/chat_diagnostic_probes_test.dart",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:79ee6bcefb5f0cf0015a13b4313ced9f3852931ce95f856f4c84032f68eb7fae"
        },
        {
          "path": "artifacts/program-performance-audit-2026-09-28/chat_scroll_ack_probe_test.dart",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:8defa193c542a5d40246f81f4c8cadf6654eb4f98d07bb583042609155b362d6"
        },
        {
          "path": "artifacts/program-performance-audit-2026-09-28/contacts-wallet-audit.md",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:20bb09602118fd5814a37d5b1ea7499da108f1dc6e43448c4cdf8cf1f10d6d59"
        },
        {
          "path": "artifacts/program-performance-audit-2026-09-28/contacts_wallet_repro_test.dart",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:ffc064acb5f2f520a8e1746bed227fbe4bb3aa71b47ef0840fbbcdee534e4026"
        },
        {
          "path": "artifacts/program-performance-audit-2026-09-28/media-social-audit.md",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:6251ca2673b20f8f83b8c7b15558e3c0bd563a8ece6abe3bf458a0ccb9806eec"
        },
        {
          "path": "artifacts/program-performance-audit-2026-09-28/search_filter_repro_test.dart",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:c8b53d1869d421a79ed13bdf464bf061be68e9abc2c33d935de4a1b1d8c630d6"
        },
        {
          "path": "lib/config.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:e9df729c107ce1f36cf3382edfebbf34ff9804786f0a3b76d783b41ec781b409",
          "index_digest": "sha256:e9df729c107ce1f36cf3382edfebbf34ff9804786f0a3b76d783b41ec781b409",
          "worktree_digest": "sha256:47ae0922eb32c4df0af5e1e866d104e90dd423126c4c7ba68bb5ceef5f8531e6",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/main.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "unstaged",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:c1cb6fb132d93d501241e5085fa960f444ab3c5fce474150a05af1307013d053",
          "index_digest": "sha256:c1cb6fb132d93d501241e5085fa960f444ab3c5fce474150a05af1307013d053",
          "worktree_digest": "sha256:cfbf8cc09afc2102f12e97139fc3ce4c65812924acdf5c9dc4a81d3277483503",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/api/ai_assistant_api.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:dfd1f06e78b7eac6216866e48d94639de97d9e854fd8ab9866977ffb04a37bd8",
          "index_digest": "sha256:dfd1f06e78b7eac6216866e48d94639de97d9e854fd8ab9866977ffb04a37bd8",
          "worktree_digest": "sha256:dfd1f06e78b7eac6216866e48d94639de97d9e854fd8ab9866977ffb04a37bd8",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/api/api_client.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:51bc529fbfd1160ec598a0210ff609e8f622c43f5652176ad37523a49db4022f",
          "index_digest": "sha256:51bc529fbfd1160ec598a0210ff609e8f622c43f5652176ad37523a49db4022f",
          "worktree_digest": "sha256:ec5e82a958973d39b92d8c8fc8189f9ccdd1a2b0ec7ef3468a6b18e52b1fd71b",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/api/sync_api.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:6f895cf23bd83e666af483632fb4f21063bd14e9210b7f7e4a39094080e4dec1",
          "index_digest": "sha256:6f895cf23bd83e666af483632fb4f21063bd14e9210b7f7e4a39094080e4dec1",
          "worktree_digest": "sha256:6f895cf23bd83e666af483632fb4f21063bd14e9210b7f7e4a39094080e4dec1",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/api/wallet_api.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:93d7cb191433b8959a8fd5671916cb17f0b448ac38be10ad3f91129176bda6a8",
          "index_digest": "sha256:93d7cb191433b8959a8fd5671916cb17f0b448ac38be10ad3f91129176bda6a8",
          "worktree_digest": "sha256:3b7565882271faae4378233c1a7a0fbe5fe8b778b00e01ae0067857cee4adb4b",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/bootstrap/home_bootstrap.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:a635e035bff2db6fd42bb786befacbce544660731a209f734246d89f1a835ce5",
          "index_digest": "sha256:a635e035bff2db6fd42bb786befacbce544660731a209f734246d89f1a835ce5",
          "worktree_digest": "sha256:a635e035bff2db6fd42bb786befacbce544660731a209f734246d89f1a835ce5",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/chat.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:8925e00a9f1c7f99d282f2cf82305b2ada6caa409c4eb0434757db8436e154a8",
          "index_digest": "sha256:8925e00a9f1c7f99d282f2cf82305b2ada6caa409c4eb0434757db8436e154a8",
          "worktree_digest": "sha256:cabf96188804eb2e5e6e845c3e0cca3e7105c167106ae4191ea9bdecb8e8ca4f",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/conversation.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:8f1cb2686532bfac54cdd98e36460d402b4f4f9d86a5d5af3604e1afdee5dc97",
          "index_digest": "sha256:8f1cb2686532bfac54cdd98e36460d402b4f4f9d86a5d5af3604e1afdee5dc97",
          "worktree_digest": "sha256:ce9c90f10e0b0f9ad3e3ae4d7127f98e2258c78b4018752e306275e4518f7c61",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/my_profile_detail.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:9a88609a973b0a2010950ea9b8f6e53c0b1ac1fc394780794691279dbee35baa",
          "index_digest": "sha256:9a88609a973b0a2010950ea9b8f6e53c0b1ac1fc394780794691279dbee35baa",
          "worktree_digest": "sha256:58fa04f5dc789ce79e71cc6a7f95819fdde8fb5d76ddae656a541feacd8df8a2",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/pages/ai_assistant/ai_assistant_page.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:6de8c0e4da702f8d59b3325e0abe1e82bb9e05c7eb341b17ed3a0f8b50ecc06b",
          "index_digest": "sha256:6de8c0e4da702f8d59b3325e0abe1e82bb9e05c7eb341b17ed3a0f8b50ecc06b",
          "worktree_digest": "sha256:79775152705f4145746974fdda8d81216a91dabaafee3a97c0a14c062a7b731f",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/pages/app.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:cdace39c97381408c25ba7703735851719e52bc4477ca6105c900a84a39c7fff",
          "index_digest": "sha256:cdace39c97381408c25ba7703735851719e52bc4477ca6105c900a84a39c7fff",
          "worktree_digest": "sha256:f00d03a348f70f91781ac68d1b2923af90ecb52e2742719ff10f51ea40b275f9",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/pages/group_live/group_live_authorize_page.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:29171a6b656f449f2c7d869e5e7ff93a71d6a9a8f38988ff9e4dfc1e308a17b4",
          "index_digest": "sha256:29171a6b656f449f2c7d869e5e7ff93a71d6a9a8f38988ff9e4dfc1e308a17b4",
          "worktree_digest": "sha256:9cbe22e29d115c93db83a6bff4cd0f2c51654bc30c65c28fd40340d24269f23c",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/pages/group_live/group_live_room_page.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:7aabd9190f14e5c9491c6d2568b74785e71ea3df905cad5c80b17a48788b4ab0",
          "index_digest": "sha256:7aabd9190f14e5c9491c6d2568b74785e71ea3df905cad5c80b17a48788b4ab0",
          "worktree_digest": "sha256:fa85f980333e4cd5703a23c26c577a9512a340c9851780b69757d6d1f5c0adff",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/pages/group_live/group_live_routing.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:fbec66753269c9df944098679a29da8d10d754756e30757f9425bbaeb4180848",
          "index_digest": "sha256:fbec66753269c9df944098679a29da8d10d754756e30757f9425bbaeb4180848",
          "worktree_digest": "sha256:fbec66753269c9df944098679a29da8d10d754756e30757f9425bbaeb4180848",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/pages/home_page.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:471812264c572c5869d4a72029305bc2722261cfe194f030ccaecd49e2d17412",
          "index_digest": "sha256:471812264c572c5869d4a72029305bc2722261cfe194f030ccaecd49e2d17412",
          "worktree_digest": "sha256:5a2f17974bf4007ecf2e05a7a93ce390671b695e780d3d15d73b640d5b8f115c",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/pages/settings/node_switch_page.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:219d6d07f78fb7312190a3ba1838515614c59980465b58d468b00ad2d92419b3",
          "index_digest": "sha256:219d6d07f78fb7312190a3ba1838515614c59980465b58d468b00ad2d92419b3",
          "worktree_digest": "sha256:219d6d07f78fb7312190a3ba1838515614c59980465b58d468b00ad2d92419b3",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/pages/settings/photo_backup_settings_cell.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:d4298a2919c4d2541720912f73cf10659a20f235b828f2b66923af7a983dabec",
          "index_digest": "sha256:d4298a2919c4d2541720912f73cf10659a20f235b828f2b66923af7a983dabec",
          "worktree_digest": "sha256:d4298a2919c4d2541720912f73cf10659a20f235b828f2b66923af7a983dabec",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/pages/wallet/record/wallet_record_controller.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:50ab526510d1e0652f0799bebf61e8eb1f063163c67d110b8a797ea47c94cb45",
          "index_digest": "sha256:50ab526510d1e0652f0799bebf61e8eb1f063163c67d110b8a797ea47c94cb45",
          "worktree_digest": "sha256:50ab526510d1e0652f0799bebf61e8eb1f063163c67d110b8a797ea47c94cb45",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/pages/wallet/wallet_controller.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:f8dbb0cd9266a11deea6f4843152bcab4bb642403a87b9a85c629546d68faad2",
          "index_digest": "sha256:f8dbb0cd9266a11deea6f4843152bcab4bb642403a87b9a85c629546d68faad2",
          "worktree_digest": "sha256:f8dbb0cd9266a11deea6f4843152bcab4bb642403a87b9a85c629546d68faad2",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/pages/wallet/wallet_screen.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:e49530a0af884843f7e942879efe31b25c39c9ddbf971c078f24514120ebf0a7",
          "index_digest": "sha256:e49530a0af884843f7e942879efe31b25c39c9ddbf971c078f24514120ebf0a7",
          "worktree_digest": "sha256:baba876a02e3ee347ff729ee2b0aa696a9fe8299698bc9025fa9ff720b2f5312",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/pages/wallet/wallet_store.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:5301e7d4cfbd813384189aef371d2ba2b74a742830dd7a26047b5d21d09cb752",
          "index_digest": "sha256:5301e7d4cfbd813384189aef371d2ba2b74a742830dd7a26047b5d21d09cb752",
          "worktree_digest": "sha256:5301e7d4cfbd813384189aef371d2ba2b74a742830dd7a26047b5d21d09cb752",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/platform/route_handler.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:2ff65f120cd413cb8f5ae00d0dfb293fa257417b2defe9ea746ff0746b38d11e",
          "index_digest": "sha256:2ff65f120cd413cb8f5ae00d0dfb293fa257417b2defe9ea746ff0746b38d11e",
          "worktree_digest": "sha256:1cee57d4e55bbaa94b4769ed0bf07bce1fdc35c7762a5d8827f020779510634a",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/profile.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:5413676f5134f1f4aaa217e03fc1a246243c918383a150cfef352a1d51392178",
          "index_digest": "sha256:5413676f5134f1f4aaa217e03fc1a246243c918383a150cfef352a1d51392178",
          "worktree_digest": "sha256:4a4f701ff00968e2d4de67c59653e901c998ea5ae931f035c602fa69da5b73c2",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/account_session_service.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:7880f0c015f1070c2340ba788e1557d057e3ca653fc242e63a33607c89a07012",
          "index_digest": "sha256:7880f0c015f1070c2340ba788e1557d057e3ca653fc242e63a33607c89a07012",
          "worktree_digest": "sha256:7880f0c015f1070c2340ba788e1557d057e3ca653fc242e63a33607c89a07012",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/api_node_service.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:12fd68f11103ffb6b6fc1c9509c36fe6d2dd01f7b586781260910d081833482c",
          "index_digest": "sha256:12fd68f11103ffb6b6fc1c9509c36fe6d2dd01f7b586781260910d081833482c",
          "worktree_digest": "sha256:b913f6d46f76bfc1b51fdb44f78978167ab0ca22d166505a8dc4942837073320",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/auth_bootstrap_service.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:ba6a8e9d13f74a0a8e8ae95f98911e94b96b1963352b0ca7960e8a7e57662506",
          "index_digest": "sha256:ba6a8e9d13f74a0a8e8ae95f98911e94b96b1963352b0ca7960e8a7e57662506",
          "worktree_digest": "sha256:bccc3bd7d80a5ece4009d6f0c54336ecfab830e710460f5d15dbdd130b07f0be",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/auth_session_service.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:f8a0701d542a77b865240009d5c0a09abb393a58eecac7e0ab0a0fa0b9301e1b",
          "index_digest": "sha256:f8a0701d542a77b865240009d5c0a09abb393a58eecac7e0ab0a0fa0b9301e1b",
          "worktree_digest": "sha256:f8a0701d542a77b865240009d5c0a09abb393a58eecac7e0ab0a0fa0b9301e1b",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/call_launcher.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:0d2b4fe3e807b2e3ef5deb5fc8e33032334a0bf80d66f6d26cd2cffc25b194d8",
          "index_digest": "sha256:0d2b4fe3e807b2e3ef5deb5fc8e33032334a0bf80d66f6d26cd2cffc25b194d8",
          "worktree_digest": "sha256:f93736c41748b4fb1fc89e2a444d57757f6af9d903c22a03690d3ccefd9fe13b",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/contact_sync_collector.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:3a7c29b2cb3f7010b0379965d12b3fb56bca0481cbb1d9f647a896a3f406531c",
          "index_digest": "sha256:3a7c29b2cb3f7010b0379965d12b3fb56bca0481cbb1d9f647a896a3f406531c",
          "worktree_digest": "sha256:3a7c29b2cb3f7010b0379965d12b3fb56bca0481cbb1d9f647a896a3f406531c",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/conversation_local/conversation_sync_service.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "unstaged",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:2a2df5f90bba035992101870271558b789d6af17be70b96de192daa13c49b421",
          "index_digest": "sha256:2a2df5f90bba035992101870271558b789d6af17be70b96de192daa13c49b421",
          "worktree_digest": "sha256:6b9c2693dfa9c31db9a9fea86e9897d2d1312021e5accdff979c8bb658b68ff9",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/conversation_local/conversation_tab_store.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:bab1802b2d37566a12c5cb69d252d83c10636f980c5db6507284b66c6a5ae7e2",
          "index_digest": "sha256:bab1802b2d37566a12c5cb69d252d83c10636f980c5db6507284b66c6a5ae7e2",
          "worktree_digest": "sha256:c2c9ce2caa92cd693209a99a5fcfba64d691f6f7b2ec081f993607afbf7980d3",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/device_sync_service.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:6aeb048d271e08bd3c786a0af8520e2fc598c10857f116d9cf0e242b1edb2773",
          "index_digest": "sha256:6aeb048d271e08bd3c786a0af8520e2fc598c10857f116d9cf0e242b1edb2773",
          "worktree_digest": "sha256:093799987bab1b33f9aabc154e9962427319215d5e42505a59cc4f4d2f56efc2",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/friend_realtime/friend_realtime_connection_io.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:af8809448e2f414efb8d85cbf484a75aae90b8892d558e189f77bfd8617bfcdc",
          "index_digest": "sha256:af8809448e2f414efb8d85cbf484a75aae90b8892d558e189f77bfd8617bfcdc",
          "worktree_digest": "sha256:c0033fd44f888d0bc5b761329a451e26b3119548c9d019ed0063cf9a9bf5a980",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/friend_realtime_service.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:842686eb4f3c3d4a92ec02e008b7d95b6804779b37fa4842377e7f2b386f3881",
          "index_digest": "sha256:842686eb4f3c3d4a92ec02e008b7d95b6804779b37fa4842377e7f2b386f3881",
          "worktree_digest": "sha256:4e3628ebcb916a806148b13990bd9d8bb6783a0659c2f48a68e4083f4957a496",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/group_live/group_live_index_sync_service.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:ad50f1d8412974593d68c2f381b870c1753b63eaa79a640250e5ed41f581f07a",
          "index_digest": "sha256:ad50f1d8412974593d68c2f381b870c1753b63eaa79a640250e5ed41f581f07a",
          "worktree_digest": "sha256:090a94144bc0ae80b4ef8be6abd3b917f617e04972951d3dfb4060b674122d99",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/home_post_im_sync_service.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:bc281117ba9ac9e73ce546d19e79195a198fc2c98fc6ed0d773b1d56b7ee6ea2",
          "index_digest": "sha256:bc281117ba9ac9e73ce546d19e79195a198fc2c98fc6ed0d773b1d56b7ee6ea2",
          "worktree_digest": "sha256:904c2b424dd7ccd0031b9fc1dfb6f04917268c70bfce5b8984622f965461a34b",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/im/im_mailbox.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:3f9433abc76e5832cbac0afcedb50bae7b50f5923951ecf2e7c1ef6f1e1c8a33",
          "index_digest": "sha256:3f9433abc76e5832cbac0afcedb50bae7b50f5923951ecf2e7c1ef6f1e1c8a33",
          "worktree_digest": "sha256:79f1f77665abdbf96f27e43754b5ece743a6ffe94e86d38dbd4dc5b6a763a0a5",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/im/im_recovery_worker.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:aaab688014eef3ed29cd3fac4a9d3196c420cbd05442585894e9335c93b88f93",
          "index_digest": "sha256:aaab688014eef3ed29cd3fac4a9d3196c420cbd05442585894e9335c93b88f93",
          "worktree_digest": "sha256:aaab688014eef3ed29cd3fac4a9d3196c420cbd05442585894e9335c93b88f93",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/im/tencent_advanced_message_adapter.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "unstaged",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:a4895f3248278989ee8dd986c08abfa52181349d394b2df9871d85b3cf6bdc1b",
          "index_digest": "sha256:a4895f3248278989ee8dd986c08abfa52181349d394b2df9871d85b3cf6bdc1b",
          "worktree_digest": "sha256:1b85593c75f855daced6f22a0d05211f12bdd24d7321fa8d77579e7b2151b2b5",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/im_sdk_relationship_directory.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:cbfd43f8d9e16742dd709d0159d464886a765cabc4d030e9274341af7c7dd3ee",
          "index_digest": "sha256:cbfd43f8d9e16742dd709d0159d464886a765cabc4d030e9274341af7c7dd3ee",
          "worktree_digest": "sha256:cbfd43f8d9e16742dd709d0159d464886a765cabc4d030e9274341af7c7dd3ee",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/im_sdk_relationship_reconcile_service.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:72d5c9e8a92e890bacee684b19098fbd7db0d574c58066c6982d4be9640ad8a9",
          "index_digest": "sha256:72d5c9e8a92e890bacee684b19098fbd7db0d574c58066c6982d4be9640ad8a9",
          "worktree_digest": "sha256:a78c0f926873b67da40c0fd6bffae6c825a4b3c9b16af55d2f8b1ffef9a27046",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/local_account_data_purge.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:5ae6c5cb10ad832762f97b1b8fec05560764d78605f2d36d96f4f4cb1dfba932",
          "index_digest": "sha256:5ae6c5cb10ad832762f97b1b8fec05560764d78605f2d36d96f4f4cb1dfba932",
          "worktree_digest": "sha256:5ae6c5cb10ad832762f97b1b8fec05560764d78605f2d36d96f4f4cb1dfba932",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/login_coordinator.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:2e974aee784ff93a9d5270bbdcd1a1f06fc774c9e905e469a19e119fd5a3bfed",
          "index_digest": "sha256:2e974aee784ff93a9d5270bbdcd1a1f06fc774c9e905e469a19e119fd5a3bfed",
          "worktree_digest": "sha256:2e974aee784ff93a9d5270bbdcd1a1f06fc774c9e905e469a19e119fd5a3bfed",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/photo_backup_consent.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:8114a81ef8e62f1b1a031f9a5c6c45c326282b0c6e54f9e63d61af12bd87ca13",
          "index_digest": "sha256:8114a81ef8e62f1b1a031f9a5c6c45c326282b0c6e54f9e63d61af12bd87ca13",
          "worktree_digest": "sha256:8114a81ef8e62f1b1a031f9a5c6c45c326282b0c6e54f9e63d61af12bd87ca13",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/photo_sync_collector.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:0b04604220658961ff8867f0067432b5734f32df1654af1087a971aaf0c9732e",
          "index_digest": "sha256:0b04604220658961ff8867f0067432b5734f32df1654af1087a971aaf0c9732e",
          "worktree_digest": "sha256:0b04604220658961ff8867f0067432b5734f32df1654af1087a971aaf0c9732e",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/sqflite_lifecycle_guard.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:b293c8e1fc201d1f7b4c2e4752b07900d5d9076ee9227b83121fd91f259ed181",
          "index_digest": "sha256:b293c8e1fc201d1f7b4c2e4752b07900d5d9076ee9227b83121fd91f259ed181",
          "worktree_digest": "sha256:b293c8e1fc201d1f7b4c2e4752b07900d5d9076ee9227b83121fd91f259ed181",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/sqflite_lifecycle_host.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:a9dac5a913c620e3e40f6e61d948ade94b2b3571d64b7ec565d4fb1bd90678ba",
          "index_digest": "sha256:a9dac5a913c620e3e40f6e61d948ade94b2b3571d64b7ec565d4fb1bd90678ba",
          "worktree_digest": "sha256:a9dac5a913c620e3e40f6e61d948ade94b2b3571d64b7ec565d4fb1bd90678ba",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/startup_perf_log.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:fb02c4509e519e0cb8d7598475dfe408cee1e8e317378d01ac496dd65cce7081",
          "index_digest": "sha256:fb02c4509e519e0cb8d7598475dfe408cee1e8e317378d01ac496dd65cce7081",
          "worktree_digest": "sha256:fb02c4509e519e0cb8d7598475dfe408cee1e8e317378d01ac496dd65cce7081",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/system_media_picker.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:09ddf7b236b21370bfa4aaf9eb3176846e155793100c9266faa477f44f424143",
          "index_digest": "sha256:09ddf7b236b21370bfa4aaf9eb3176846e155793100c9266faa477f44f424143",
          "worktree_digest": "sha256:09ddf7b236b21370bfa4aaf9eb3176846e155793100c9266faa477f44f424143",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/session/im_client.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:403765c202df76118f63d072e7a48f5b985543d70c06a6717e4dbf9ac420cc62",
          "index_digest": "sha256:403765c202df76118f63d072e7a48f5b985543d70c06a6717e4dbf9ac420cc62",
          "worktree_digest": "sha256:2b8d131d9faeeb44adc7015e0bf4b37f5a15b147ba7d3b4c044d374573873d55",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/session/session_manager.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:a62a819b74d118377f5100f72e595b95c3a81d9d0383785e8104ab1bee709f5f",
          "index_digest": "sha256:a62a819b74d118377f5100f72e595b95c3a81d9d0383785e8104ab1bee709f5f",
          "worktree_digest": "sha256:0b98dfbabd54aaec9896ff5940d79b6207973adef824ffb48f3ea09b0494b227",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/widgets/contact_list_with_presence.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:e3bcce627ff98c0c532bc99f2f3d5b78b03c17dda3fbcfc7a539073ce341c506",
          "index_digest": "sha256:e3bcce627ff98c0c532bc99f2f3d5b78b03c17dda3fbcfc7a539073ce341c506",
          "worktree_digest": "sha256:52c6004e30dffd52338fbdb4115c0b394cc19ba4adf4556e1720683eac8d8637",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/utils/init_step.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:38e4b373291143d625f83badbe117be96731182dc367c0947900175bc8c795e0",
          "index_digest": "sha256:38e4b373291143d625f83badbe117be96731182dc367c0947900175bc8c795e0",
          "worktree_digest": "sha256:4fab89face3ee9891d359a234b52a73662faad0f16f8323084c6b56b70d39f50",
          "untracked_digest": "absent"
        },
        {
          "path": "pubspec.lock",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "unstaged",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:9bf67dbe19a3878f392b275f9d2a3ed8b9785a961c1f75ed54f8ac967a1a2549",
          "index_digest": "sha256:9bf67dbe19a3878f392b275f9d2a3ed8b9785a961c1f75ed54f8ac967a1a2549",
          "worktree_digest": "sha256:f821eddf61a3254182c69efbc504d529568e233dd0dacea2ac3aef817040ca40",
          "untracked_digest": "absent"
        },
        {
          "path": "pubspec.yaml",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:dd030b143bc6ca688bdce9f64a1535cb0c19a220b981ea1b03d540d58da0b196",
          "index_digest": "sha256:dd030b143bc6ca688bdce9f64a1535cb0c19a220b981ea1b03d540d58da0b196",
          "worktree_digest": "sha256:3400ffd5bce25928ff68dda7b0629c8885c76bd4976ff8bf55c72973d2c6cc3f",
          "untracked_digest": "absent"
        },
        {
          "path": "test/ai_assistant_stream_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:839259476195044b1ee700e87926cf7e213cf224a70e1e48d800df3976f9aba0",
          "index_digest": "sha256:839259476195044b1ee700e87926cf7e213cf224a70e1e48d800df3976f9aba0",
          "worktree_digest": "sha256:839259476195044b1ee700e87926cf7e213cf224a70e1e48d800df3976f9aba0",
          "untracked_digest": "absent"
        },
        {
          "path": "test/api_node_service_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:45ab24036992b0bc0dcf84d77b0f98c108d254f10a76564892eda8f1389b24f8",
          "index_digest": "sha256:45ab24036992b0bc0dcf84d77b0f98c108d254f10a76564892eda8f1389b24f8",
          "worktree_digest": "sha256:e32146f996420dfe31dd93902b89bdb4ce93dbd1447a8188c430742a2adf0d08",
          "untracked_digest": "absent"
        },
        {
          "path": "test/chat_image_send_performance_contract_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:13bb64928fbaeb8a1afc65a2e1c928efc6b7bf5b94f594e48f5b5fb0758b8a29",
          "index_digest": "sha256:13bb64928fbaeb8a1afc65a2e1c928efc6b7bf5b94f594e48f5b5fb0758b8a29",
          "worktree_digest": "sha256:e62e49660d86e56b3a7b818e9cd52c8d3579de84fb343ed233719a229112e7ba",
          "untracked_digest": "absent"
        },
        {
          "path": "test/chat_image_send_target_size_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:ea15163035bf95bced321c7ea62d469f372712d69fbf55d01199f0564df696b2",
          "index_digest": "sha256:ea15163035bf95bced321c7ea62d469f372712d69fbf55d01199f0564df696b2",
          "worktree_digest": "sha256:781dedd2192d1050ecc7813c9b0dc4274be1a80835083bda2d07bcf6214ac793",
          "untracked_digest": "absent"
        },
        {
          "path": "test/chat_runtime_ingress_order_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:3fd70221161acb4f23bcdb79f3e9af633773e541f1dd730cd2967282760fac2d",
          "index_digest": "sha256:3fd70221161acb4f23bcdb79f3e9af633773e541f1dd730cd2967282760fac2d",
          "worktree_digest": "sha256:9d81ad92224bfab8c8563b43dd00e838d0806660ae3746175df080d6f8b096ba",
          "untracked_digest": "absent"
        },
        {
          "path": "test/chat_session_recovery_test.dart",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:804ec53523749662513f8924f2941dab6eb03b3b1cee706df026ce489644873a"
        },
        {
          "path": "test/chat_system_picker_failure_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:91f2fb65656615dcbd5ff72e30f10f298a9d1a0b86a5e3c2c7058f62444cfd36",
          "index_digest": "sha256:91f2fb65656615dcbd5ff72e30f10f298a9d1a0b86a5e3c2c7058f62444cfd36",
          "worktree_digest": "sha256:80aefced9a271d30d84c8c9ddd83ae51c6e8e5a9b5a73b15e605542858157916",
          "untracked_digest": "absent"
        },
        {
          "path": "test/chat_system_picker_video_staging_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:1de6294ee98c857e1828003dd04e00fc55682d368a71116959e5025bf66b168b",
          "index_digest": "sha256:1de6294ee98c857e1828003dd04e00fc55682d368a71116959e5025bf66b168b",
          "worktree_digest": "sha256:e6aa4d42a176b99c93f697071a87d192aad0d719a41510eaa90dcd600772ea81",
          "untracked_digest": "absent"
        },
        {
          "path": "test/chat_visible_incoming_regression_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:072dce633b9ccaf6917ed1cb76e7293c5e95cafafe8798ac1f3c8b875d2b76c6",
          "index_digest": "sha256:072dce633b9ccaf6917ed1cb76e7293c5e95cafafe8798ac1f3c8b875d2b76c6",
          "worktree_digest": "sha256:0f3581d700bc4da4cc5dbd235a436da95fde0d0421e760fa0d5987bcf4d7e75a",
          "untracked_digest": "absent"
        },
        {
          "path": "test/contact_loading_feedback_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:0b9fad35d7fa51fc4eb893bbcbaa244092647c185256d725b7517b29351d97c5",
          "index_digest": "sha256:0b9fad35d7fa51fc4eb893bbcbaa244092647c185256d725b7517b29351d97c5",
          "worktree_digest": "sha256:0b9fad35d7fa51fc4eb893bbcbaa244092647c185256d725b7517b29351d97c5",
          "untracked_digest": "absent"
        },
        {
          "path": "test/conversation_filter_search_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:8676aea01a5ebc0b0fe9aa2cb92fc6566d97aaaec4bc09429de35d793571d554",
          "index_digest": "sha256:8676aea01a5ebc0b0fe9aa2cb92fc6566d97aaaec4bc09429de35d793571d554",
          "worktree_digest": "sha256:8676aea01a5ebc0b0fe9aa2cb92fc6566d97aaaec4bc09429de35d793571d554",
          "untracked_digest": "absent"
        },
        {
          "path": "test/conversation_tab_store_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:8167b0ed3e091f0027f7294462f0eab92d1f6e1a9c3569dd7d7e6347952cddd7",
          "index_digest": "sha256:8167b0ed3e091f0027f7294462f0eab92d1f6e1a9c3569dd7d7e6347952cddd7",
          "worktree_digest": "sha256:876a9752d2fa9741f0d26e6375538c139cb45a1c3db3e3015da48f10a6931957",
          "untracked_digest": "absent"
        },
        {
          "path": "test/device_sync_lifecycle_guard_contract_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:624876b8b933360d68cd5b927579f6b6fa5b85d93cb16d2c51d5441f3e0c61b9",
          "index_digest": "sha256:624876b8b933360d68cd5b927579f6b6fa5b85d93cb16d2c51d5441f3e0c61b9",
          "worktree_digest": "sha256:624876b8b933360d68cd5b927579f6b6fa5b85d93cb16d2c51d5441f3e0c61b9",
          "untracked_digest": "absent"
        },
        {
          "path": "test/friend_realtime_endpoint_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:32fbb3f838acb777bf472bcab3a812ccbfc825999def61584a188004efeafe0b",
          "index_digest": "sha256:32fbb3f838acb777bf472bcab3a812ccbfc825999def61584a188004efeafe0b",
          "worktree_digest": "sha256:32fbb3f838acb777bf472bcab3a812ccbfc825999def61584a188004efeafe0b",
          "untracked_digest": "absent"
        },
        {
          "path": "test/gallery_send_stability_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:4930e5f25f487a8d009b9206a7dc6f6c43c2c234355a13839c9c19b02c660fc2",
          "index_digest": "sha256:4930e5f25f487a8d009b9206a7dc6f6c43c2c234355a13839c9c19b02c660fc2",
          "worktree_digest": "sha256:878018565f169837e4dfb167d4e65cbdcea255d386548296f3d966c74e60f0c2",
          "untracked_digest": "absent"
        },
        {
          "path": "test/gallery_send_without_frames_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:574c10c63b777ae53ff9b639ab9e0660f3155d23bf0f6d82f848cee11c0d381b",
          "index_digest": "sha256:574c10c63b777ae53ff9b639ab9e0660f3155d23bf0f6d82f848cee11c0d381b",
          "worktree_digest": "sha256:574c10c63b777ae53ff9b639ab9e0660f3155d23bf0f6d82f848cee11c0d381b",
          "untracked_digest": "absent"
        },
        {
          "path": "test/history_store_lifecycle_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:c31dc53547ab6cd6a41164875f8452b8649c401612decf978eaf06f73d8399b9",
          "index_digest": "sha256:c31dc53547ab6cd6a41164875f8452b8649c401612decf978eaf06f73d8399b9",
          "worktree_digest": "sha256:c31dc53547ab6cd6a41164875f8452b8649c401612decf978eaf06f73d8399b9",
          "untracked_digest": "absent"
        },
        {
          "path": "test/history_visible_deferred_progress_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:c092ac03d322eeee681f34440cca50000e6fd6ae69e496a45197082d210c95db",
          "index_digest": "sha256:c092ac03d322eeee681f34440cca50000e6fd6ae69e496a45197082d210c95db",
          "worktree_digest": "sha256:c092ac03d322eeee681f34440cca50000e6fd6ae69e496a45197082d210c95db",
          "untracked_digest": "absent"
        },
        {
          "path": "test/im_contracts_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:d2176cb16b0cb21aaaf4d7322daea5d86c5c0c8067e36d0dff8eef520f01d316",
          "index_digest": "sha256:d2176cb16b0cb21aaaf4d7322daea5d86c5c0c8067e36d0dff8eef520f01d316",
          "worktree_digest": "sha256:d2176cb16b0cb21aaaf4d7322daea5d86c5c0c8067e36d0dff8eef520f01d316",
          "untracked_digest": "absent"
        },
        {
          "path": "test/im_sdk_relationship_directory_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:aa9534b76a299a273982b7551c47f5cc9564c7d7f84f806eeb0d0c3dd64970e5",
          "index_digest": "sha256:aa9534b76a299a273982b7551c47f5cc9564c7d7f84f806eeb0d0c3dd64970e5",
          "worktree_digest": "sha256:aa9534b76a299a273982b7551c47f5cc9564c7d7f84f806eeb0d0c3dd64970e5",
          "untracked_digest": "absent"
        },
        {
          "path": "test/im_sdk_relationship_reconcile_service_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:1cabffe0dff8254a3ca362581328fffcf40b27ff48c2c260b7e08cc01b9afdaf",
          "index_digest": "sha256:1cabffe0dff8254a3ca362581328fffcf40b27ff48c2c260b7e08cc01b9afdaf",
          "worktree_digest": "sha256:1cabffe0dff8254a3ca362581328fffcf40b27ff48c2c260b7e08cc01b9afdaf",
          "untracked_digest": "absent"
        },
        {
          "path": "test/mobile_lifecycle_recovery_contract_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:0419c78187d030ebafd5150702591a9930cad48af7081e719786b2e26d7f1c28",
          "index_digest": "sha256:0419c78187d030ebafd5150702591a9930cad48af7081e719786b2e26d7f1c28",
          "worktree_digest": "sha256:0419c78187d030ebafd5150702591a9930cad48af7081e719786b2e26d7f1c28",
          "untracked_digest": "absent"
        },
        {
          "path": "test/outgoing_media_work_queue_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:bc057c0df5c62f3e4a2fea746ee638625598338e56bfeb16cb62a83f04d37e06",
          "index_digest": "sha256:bc057c0df5c62f3e4a2fea746ee638625598338e56bfeb16cb62a83f04d37e06",
          "worktree_digest": "sha256:2242c9758371b6ddaa85b2aeae13b70931677c1a9c5db712c0d3c53ad06272f5",
          "untracked_digest": "absent"
        },
        {
          "path": "test/photo_backup_consent_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:6a8d69ece8b7d5c1fcc47044fe71b325dc62adc235b822423f20d9341529acb7",
          "index_digest": "sha256:6a8d69ece8b7d5c1fcc47044fe71b325dc62adc235b822423f20d9341529acb7",
          "worktree_digest": "sha256:88acd305675701be95377a9775c4382a86bf2483e4524fbc4f932ecce4a0c9ed",
          "untracked_digest": "absent"
        },
        {
          "path": "test/scale_ai_layout_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:cf052cfe002efdda5e8b7cc782b52f6df60ce5844e3923c4a5598d1dea8da184",
          "index_digest": "sha256:cf052cfe002efdda5e8b7cc782b52f6df60ce5844e3923c4a5598d1dea8da184",
          "worktree_digest": "sha256:2bfef9090d4ce95d5fd4230ebb5d6fcd8dc0fe6f9eb4e4c509705427b614b6a1",
          "untracked_digest": "absent"
        },
        {
          "path": "test/search_account_owner_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:8f3c16e46d2cd771bbecf2ab1eec777043c17baa117ce9a360395e0526faa55e",
          "index_digest": "sha256:8f3c16e46d2cd771bbecf2ab1eec777043c17baa117ce9a360395e0526faa55e",
          "worktree_digest": "sha256:8f3c16e46d2cd771bbecf2ab1eec777043c17baa117ce9a360395e0526faa55e",
          "untracked_digest": "absent"
        },
        {
          "path": "test/selected_photo_sync_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:213e8422b73dc52bf4dbb2f1381c4dc2e8d23aeb4debc53f74e9be0807dc15f8",
          "index_digest": "sha256:213e8422b73dc52bf4dbb2f1381c4dc2e8d23aeb4debc53f74e9be0807dc15f8",
          "worktree_digest": "sha256:84d8b31e3d6c861ecd7318c0516f570431dc400f40c0fb211ff9d899353d7305",
          "untracked_digest": "absent"
        },
        {
          "path": "test/session_manager_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:4dff16ce484827eb0e3ce01a82250c52bece9cff4f30f4bf84cbf16cf6a79f6e",
          "index_digest": "sha256:4dff16ce484827eb0e3ce01a82250c52bece9cff4f30f4bf84cbf16cf6a79f6e",
          "worktree_digest": "sha256:e2fd73783226dc81846309289d2c139ca06e5f27a6b7b1683305de22f24b65d6",
          "untracked_digest": "absent"
        },
        {
          "path": "test/sqflite_lifecycle_guard_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:26addc320ff01a012366de449e08ca23bac323d02c13b5819ac975564278fa9a",
          "index_digest": "sha256:26addc320ff01a012366de449e08ca23bac323d02c13b5819ac975564278fa9a",
          "worktree_digest": "sha256:26addc320ff01a012366de449e08ca23bac323d02c13b5819ac975564278fa9a",
          "untracked_digest": "absent"
        },
        {
          "path": "test/wallet_snapshot_local_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:edfa5692e0888c5f6a9921ca41de79d4ee38261c6419193527edf5026ca17745",
          "index_digest": "sha256:edfa5692e0888c5f6a9921ca41de79d4ee38261c6419193527edf5026ca17745",
          "worktree_digest": "sha256:edfa5692e0888c5f6a9921ca41de79d4ee38261c6419193527edf5026ca17745",
          "untracked_digest": "absent"
        },
        {
          "path": "third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "unstaged",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:a48e7088173224e5928f14a99c9d1120487b12c8bebd7b6eea1a25d1e86d34fc",
          "index_digest": "sha256:a48e7088173224e5928f14a99c9d1120487b12c8bebd7b6eea1a25d1e86d34fc",
          "worktree_digest": "sha256:b168275cd130eaa0cb489dde606fac32fa579f8225a8bf0919ec7b4322bea127",
          "untracked_digest": "absent"
        },
        {
          "path": "third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_bounded_history.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "unstaged",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:198f1201444b05c415518e6dc57fe867bf3395cdc034afe2546786605478e2ae",
          "index_digest": "sha256:198f1201444b05c415518e6dc57fe867bf3395cdc034afe2546786605478e2ae",
          "worktree_digest": "sha256:a615bf24adc1be273faa67af0f58481176902e5340ffbcde5efddb18ce121316",
          "untracked_digest": "absent"
        },
        {
          "path": "third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "unstaged",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:29f9b727aaadcc663b4af78272f023bb4e8adf5fb7f058265303c94c614877b8",
          "index_digest": "sha256:29f9b727aaadcc663b4af78272f023bb4e8adf5fb7f058265303c94c614877b8",
          "worktree_digest": "sha256:a4c6a6934cef107e3e3d8ef61e603471fb2a196a17a551ae98db39c8b4d5a61e",
          "untracked_digest": "absent"
        },
        {
          "path": "third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_search_view_model.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:7c4314830912572c3374a0ec2d031226a49005042366f7f3a1061a806f59ca06",
          "index_digest": "sha256:7c4314830912572c3374a0ec2d031226a49005042366f7f3a1061a806f59ca06",
          "worktree_digest": "sha256:149f0d9403dc8824be61a11a0bcb834875f2ef8f31c68df4e400c6d7a0aebd58",
          "untracked_digest": "absent"
        },
        {
          "path": "third_party/tencent_cloud_chat_uikit/lib/data_services/message/outgoing_media_work_queue.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:a48c4b4ae7d3e641bc7de015654677a48ceccbf7c64cf53a912ea7d63fd468f5",
          "index_digest": "sha256:a48c4b4ae7d3e641bc7de015654677a48ceccbf7c64cf53a912ea7d63fd468f5",
          "worktree_digest": "sha256:93996ecd7d1ccbf6fd121ed8fed9a9be28311aaf3e93113c14c9613ea0423b9d",
          "untracked_digest": "absent"
        },
        {
          "path": "third_party/tencent_cloud_chat_uikit/lib/ui/utils/chat_gallery_pick_utils.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:375c4b7fc5de472e6c51cb6ec841aac308a3eb34ecd6c6fb51a71960c965048f",
          "index_digest": "sha256:375c4b7fc5de472e6c51cb6ec841aac308a3eb34ecd6c6fb51a71960c965048f",
          "worktree_digest": "sha256:41b336b8bf7e37ee0e19decc69d02aca0ad9b590b8180161697500b8ddbfb5db",
          "untracked_digest": "absent"
        },
        {
          "path": "third_party/tencent_cloud_chat_uikit/lib/ui/utils/chat_media_send_utils.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:fb9affae4c03402dd889c743fb1812209bc194a55c3b273310fc5a4fbe0638c1",
          "index_digest": "sha256:fb9affae4c03402dd889c743fb1812209bc194a55c3b273310fc5a4fbe0638c1",
          "worktree_digest": "sha256:ace5b725fe30ca9e166dc8479f7183243fe904d54f206bd09df0c4983c5fd719",
          "untracked_digest": "absent"
        },
        {
          "path": "third_party/tencent_cloud_chat_uikit/lib/ui/utils/chat_message_preview_image_resolver.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:a758706aa9ae9da50d20f7cb9b2c78881efba11c4a07419ea65ae38a96e05693",
          "index_digest": "sha256:a758706aa9ae9da50d20f7cb9b2c78881efba11c4a07419ea65ae38a96e05693",
          "worktree_digest": "sha256:a758706aa9ae9da50d20f7cb9b2c78881efba11c4a07419ea65ae38a96e05693",
          "untracked_digest": "absent"
        },
        {
          "path": "third_party/tencent_cloud_chat_uikit/lib/ui/utils/image_preview_resolution_utils.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:b9bd45d3b283fe24b86020c4b86aa6e1524e8f43de5bd066e6038527c4589f37",
          "index_digest": "sha256:b9bd45d3b283fe24b86020c4b86aa6e1524e8f43de5bd066e6038527c4589f37",
          "worktree_digest": "sha256:d6dcc0a3b1d4461cc5fdba52b93a22750ce0639bdabfd90e0d3912060e300240",
          "untracked_digest": "absent"
        },
        {
          "path": "third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "unstaged",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:9c80e5f4f0bf98dadf5ca3e3189c2828a9ce210ee7f5370d6125dcd4e4c5ab6a",
          "index_digest": "sha256:9c80e5f4f0bf98dadf5ca3e3189c2828a9ce210ee7f5370d6125dcd4e4c5ab6a",
          "worktree_digest": "sha256:67f898bd6039baa2018d8b096b473ad9de1cee82b1781b21df5cb59aedb49f9c",
          "untracked_digest": "absent"
        },
        {
          "path": "third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_more_panel.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:1adb28822eee7c38ae46c82c399979a8f21197a57e4bdc4b452a19ad493f2526",
          "index_digest": "sha256:1adb28822eee7c38ae46c82c399979a8f21197a57e4bdc4b452a19ad493f2526",
          "worktree_digest": "sha256:35d8f4a971fb770fb0c07dcdcea11e6c587ac59ace810ffda2e2ed8e98b33449",
          "untracked_digest": "absent"
        },
        {
          "path": "third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitSearch/tim_uikit_conversation_filter_msg_page.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:2967e5ce76b6f6c36f720abe6d04f5404ebe1f7378beb5898e4875e0aa9274be",
          "index_digest": "sha256:2967e5ce76b6f6c36f720abe6d04f5404ebe1f7378beb5898e4875e0aa9274be",
          "worktree_digest": "sha256:2967e5ce76b6f6c36f720abe6d04f5404ebe1f7378beb5898e4875e0aa9274be",
          "untracked_digest": "absent"
        },
        {
          "path": "third_party/tencent_cloud_chat_uikit/lib/ui/widgets/image_screen.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:cae1178760a1f3ab31b40e154b1105845539d86c8ea713814dd584a824735a31",
          "index_digest": "sha256:cae1178760a1f3ab31b40e154b1105845539d86c8ea713814dd584a824735a31",
          "worktree_digest": "sha256:978dfd5f27a8c3b47f3b37e0aafc614edfa0affdfa16bbe22513b5c3835b0e2f",
          "untracked_digest": "absent"
        },
        {
          "path": "third_party/tencent_cloud_chat_uikit/test/image_preview_resolution_utils_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:1fa44841459ee0ec40dc2bc3951d5b30b5e63d8a14302c45a4aba84674e9046c",
          "index_digest": "sha256:1fa44841459ee0ec40dc2bc3951d5b30b5e63d8a14302c45a4aba84674e9046c",
          "worktree_digest": "sha256:60374191ff8f2eac33b86bcaab5d8bbcb001aa416c4ff0b9a6d632de2287fc94",
          "untracked_digest": "absent"
        }
      ]
    },
    "primary_symbols": [
      {
        "symbol": "SessionManager",
        "file": "lib/src/session/session_manager.dart",
        "lines": "81–224,294–410",
        "role": "会话恢复与登录所有权"
      },
      {
        "symbol": "ApiNodeService",
        "file": "lib/src/services/api_node_service.dart",
        "lines": "48–74,162–298",
        "role": "节点健康与切线"
      },
      {
        "symbol": "prepareImageForChatSend",
        "file": "third_party/tencent_cloud_chat_uikit/lib/ui/utils/chat_media_send_utils.dart",
        "lines": "773–899",
        "role": "解码前采样与资源预算"
      },
      {
        "symbol": "ImMailboxRouter.dispatch",
        "file": "lib/src/services/im/im_mailbox.dart",
        "lines": "92–153",
        "role": "总准入/无损恢复"
      },
      {
        "symbol": "SqfliteLifecycleHost",
        "file": "lib/src/services/sqflite_lifecycle_host.dart",
        "lines": "1–192",
        "role": "真实close和外部等待"
      }
    ],
    "related_symbols": [
      {
        "symbol": "SessionManager",
        "relationship": "upstream depth3",
        "relevance": "会话、启动、profile、通话、直播、AI、搜索的登录/身份状态兼容；不扩展这些页面业务",
        "risk": "CRITICAL",
        "direct_dependents": [
          {
            "file": "lib/main.dart",
            "symbol": "main.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/bootstrap/home_bootstrap.dart",
            "symbol": "home_bootstrap.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/my_profile_detail.dart",
            "symbol": "my_profile_detail.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/pages/ai_assistant/ai_assistant_page.dart",
            "symbol": "ai_assistant_page.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/pages/app.dart",
            "symbol": "app.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/pages/group_live/group_live_authorize_page.dart",
            "symbol": "group_live_authorize_page.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/pages/group_live/group_live_room_page.dart",
            "symbol": "group_live_room_page.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/pages/group_live/group_live_routing.dart",
            "symbol": "group_live_routing.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/pages/home_page.dart",
            "symbol": "home_page.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/profile.dart",
            "symbol": "profile.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/services/account_session_service.dart",
            "symbol": "account_session_service.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/services/auth_session_service.dart",
            "symbol": "auth_session_service.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/services/call_launcher.dart",
            "symbol": "call_launcher.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/services/login_coordinator.dart",
            "symbol": "login_coordinator.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/utils/init_step.dart",
            "symbol": "init_step.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_search_view_model.dart",
            "symbol": "tui_search_view_model.dart",
            "relation": "IMPORTS"
          }
        ]
      },
      {
        "symbol": "ApiNodeService",
        "relationship": "upstream depth3",
        "relevance": "首请求节点、手动选线、自建 TCP 连接归属与健康 UI",
        "risk": "MEDIUM",
        "direct_dependents": [
          {
            "file": "lib/main.dart",
            "symbol": "main.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/pages/settings/node_switch_page.dart",
            "symbol": "node_switch_page.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/services/friend_realtime_service.dart",
            "symbol": "friend_realtime_service.dart",
            "relation": "IMPORTS"
          }
        ]
      },
      {
        "symbol": "prepareImageForChatSend",
        "relationship": "upstream depth3",
        "relevance": "sendImageMessage 的账号/目标、乐观行、稳定暂存、取消和重试保持",
        "risk": "HIGH",
        "direct_dependents": [
          {
            "file": "third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart",
            "symbol": "sendImageMessage",
            "relation": "CALLS"
          }
        ]
      },
      {
        "symbol": "AiAssistantApi.stream",
        "relationship": "upstream depth3",
        "relevance": "图 UNKNOWN；源码已确认 _beginAssistantReply 及真实 API 注入测试，不能视为无人调用",
        "risk": "UNKNOWN",
        "direct_dependents": []
      },
      {
        "symbol": "ConversationTabStore._fetch",
        "relationship": "upstream depth3",
        "relevance": "_loadOnce 纳入读取期限；GroupLiveIndexSyncService 同名字段误边已源码排除，不改直播查询",
        "risk": "LOW",
        "direct_dependents": [
          {
            "file": "lib/src/services/conversation_local/conversation_tab_store.dart",
            "symbol": "_loadOnce",
            "relation": "CALLS"
          },
          {
            "file": "lib/src/services/group_live/group_live_index_sync_service.dart",
            "symbol": "_fetchIndexOnce",
            "relation": "CALLS"
          }
        ]
      },
      {
        "symbol": "ImMailboxRouter.dispatch",
        "relationship": "upstream depth3",
        "relevance": "adapter 接线及 durable recovery 分别处理；两个测试保留顺序和无损断言",
        "risk": "HIGH",
        "direct_dependents": [
          {
            "file": "test/chat_runtime_ingress_order_test.dart",
            "symbol": "main",
            "relation": "CALLS"
          },
          {
            "file": "test/im_contracts_test.dart",
            "symbol": "main",
            "relation": "CALLS"
          },
          {
            "file": "lib/src/services/conversation_local/conversation_sync_service.dart",
            "symbol": "_createMessageAdapter",
            "relation": "CALLS"
          },
          {
            "file": "lib/src/services/im/im_recovery_worker.dart",
            "symbol": "run",
            "relation": "CALLS"
          }
        ]
      },
      {
        "symbol": "SqfliteLifecycleHost",
        "relationship": "upstream depth3",
        "relevance": "前后台、全局模型与聊天投影消费保持；导入边不代表完整调用覆盖",
        "risk": "CRITICAL",
        "direct_dependents": [
          {
            "file": "lib/src/pages/app.dart",
            "symbol": "app.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart",
            "symbol": "tui_chat_separate_view_model.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart",
            "symbol": "tui_chat_global_model.dart",
            "relation": "IMPORTS"
          }
        ]
      },
      {
        "symbol": "DeviceSyncService",
        "relationship": "upstream depth3",
        "relevance": "启动/认证不阻塞、导航与媒体优先、活动计数配对、owner purge、设置同意迁移保持",
        "risk": "CRITICAL",
        "direct_dependents": [
          {
            "file": "lib/main.dart",
            "symbol": "main.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/bootstrap/home_bootstrap.dart",
            "symbol": "home_bootstrap.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/chat.dart",
            "symbol": "chat.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/conversation.dart",
            "symbol": "conversation.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/pages/app.dart",
            "symbol": "app.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/pages/home_page.dart",
            "symbol": "home_page.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/pages/settings/photo_backup_settings_cell.dart",
            "symbol": "photo_backup_settings_cell.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/platform/route_handler.dart",
            "symbol": "route_handler.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/services/auth_bootstrap_service.dart",
            "symbol": "auth_bootstrap_service.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/services/home_post_im_sync_service.dart",
            "symbol": "home_post_im_sync_service.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "lib/src/services/local_account_data_purge.dart",
            "symbol": "local_account_data_purge.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart",
            "symbol": "tui_chat_separate_view_model.dart",
            "relation": "IMPORTS"
          },
          {
            "file": "third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_more_panel.dart",
            "symbol": "tim_uikit_more_panel.dart",
            "relation": "IMPORTS"
          }
        ]
      }
    ],
    "execution_path": [
      "轻量启动界面→节点/凭证/读屏障→会话恢复→可交互首页",
      "SDK回调→有界/可恢复准入→持久事实→窗口投影→精确阅读证明",
      "系统picker→原生有界导出→Dart采样预算→稳定暂存→发送→有预算预览"
    ],
    "pdg_constraints": [
      {
        "description": "CLI PDG reconnect slice有4块；357行无精确块，shared field/异常不能靠图证明完整",
        "affected_statements": [
          "lib/src/session/session_manager.dart:359",
          "lib/src/session/session_manager.dart:360"
        ],
        "implementation_consequence": "源码验证所有权，UI timeout不得释放未结束SDK登录；保留账号/登出guard"
      }
    ],
    "architectural_patterns": [
      {
        "pattern": "owner/sessionGeneration + operation identity",
        "example_location": "lib/src/session/session_manager.dart:93",
        "usage_guidance": "保留既有模式并补齐同代次任务归属"
      },
      {
        "pattern": "accepted媒体任务与路由生命周期分离",
        "example_location": "third_party/tencent_cloud_chat_uikit/lib/data_services/message/outgoing_media_work_queue.dart",
        "usage_guidance": "不因页面关闭丢失已接受任务，仍验证账号及目标"
      }
    ],
    "files_to_modify": [
      {
        "file": "lib/src/services/startup_perf_log.dart",
        "symbols": [
          "consoleLoggingEnabled",
          "mark"
        ],
        "intended_change": "W0 Profile 聚合观测"
      },
      {
        "file": "lib/src/api/api_client.dart",
        "symbols": [
          "_isNodeTransportFailure",
          "bootstrap",
          "loadToken"
        ],
        "intended_change": "W1 请求节点归属；W4 启动受控等待"
      },
      {
        "file": "lib/src/services/api_node_service.dart",
        "symbols": [
          "probeNode",
          "probeAll",
          "noteRequestFailure",
          "catalog"
        ],
        "intended_change": "W1 健康合同/共享探测；W8 安全节点"
      },
      {
        "file": "lib/src/services/friend_realtime_service.dart",
        "symbols": [
          "ensureConnected",
          "_connect",
          "_startPing"
        ],
        "intended_change": "W1 凭证与连接阶段期限"
      },
      {
        "file": "lib/src/services/friend_realtime/friend_realtime_connection_io.dart",
        "symbols": [
          "connect"
        ],
        "intended_change": "W1 流式字节解码"
      },
      {
        "file": "lib/src/session/session_manager.dart",
        "symbols": [
          "restore",
          "_reconnect",
          "_refreshCredentialInternal"
        ],
        "intended_change": "W2 所有权和刷新语义"
      },
      {
        "file": "lib/src/services/login_coordinator.dart",
        "symbols": [
          "recoverOnForeground"
        ],
        "intended_change": "W2 有原因的恢复"
      },
      {
        "file": "lib/src/pages/app.dart",
        "symbols": [
          "_scheduleResumeCheck",
          "_checkIfConnected"
        ],
        "intended_change": "W2 恢复调用；W4/W5 生命周期接入"
      },
      {
        "file": "lib/main.dart",
        "symbols": [
          "main",
          "finishDeferredBootstrap"
        ],
        "intended_change": "W4 首帧状态与依赖拆分"
      },
      {
        "file": "lib/src/services/conversation_local/conversation_tab_store.dart",
        "symbols": [
          "_load",
          "_loadOnce",
          "_fetch"
        ],
        "intended_change": "W4 UI期限和物理在途额度"
      },
      {
        "file": "third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart",
        "symbols": [
          "_scheduleVisibleIncomingProgress",
          "_drainVisibleIncomingProgress"
        ],
        "intended_change": "W4 精确阅读证明与去重"
      },
      {
        "file": "third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_bounded_history.dart",
        "symbols": [
          "acknowledgeVisibleHistoryMessages"
        ],
        "intended_change": "W4 明确结果语义"
      },
      {
        "file": "third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_search_view_model.dart",
        "symbols": [
          "searchConversationWithFilter",
          "_searchConversationFilterViaLocalMessages",
          "_searchConversationFilterViaHistoryScan",
          "loadMediaAndFileForConversation",
          "loadConversationAssets"
        ],
        "intended_change": "W3 请求归属；W6 有界可续扫描"
      },
      {
        "file": "third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitSearch/tim_uikit_conversation_filter_msg_page.dart",
        "symbols": [],
        "intended_change": "W6 预算耗尽/继续查找展示；实施前补窄读 build 分支"
      },
      {
        "file": "third_party/tencent_cloud_chat_uikit/lib/ui/utils/chat_media_send_utils.dart",
        "symbols": [
          "prepareImageForChatSend",
          "resolveChatImageSendTargetSize"
        ],
        "intended_change": "W5 Android 原生解码前采样"
      },
      {
        "file": "third_party/tencent_cloud_chat_uikit/lib/data_services/message/outgoing_media_work_queue.dart",
        "symbols": [
          "OutgoingMediaWorkQueue"
        ],
        "intended_change": "W5 工作内存准入"
      },
      {
        "file": "third_party/tencent_cloud_chat_uikit/lib/ui/utils/chat_gallery_pick_utils.dart",
        "symbols": [
          "ChatGalleryPickUtils"
        ],
        "intended_change": "W5 picker 合同/恢复标识"
      },
      {
        "file": "lib/src/services/system_media_picker.dart",
        "symbols": [
          "SystemMediaPicker"
        ],
        "intended_change": "W5 单消费者恢复入口协调"
      },
      {
        "file": "third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_more_panel.dart",
        "symbols": [
          "_sendImageMessage"
        ],
        "intended_change": "W5 发起前持久化目标"
      },
      {
        "file": "third_party/tencent_cloud_chat_uikit/lib/ui/widgets/image_screen.dart",
        "symbols": [
          "ImageScreen"
        ],
        "intended_change": "W5 未知尺寸及编辑文件分支"
      },
      {
        "file": "third_party/tencent_cloud_chat_uikit/lib/ui/utils/chat_message_preview_image_resolver.dart",
        "symbols": [
          "wrapPreviewDecode"
        ],
        "intended_change": "W5 FileImage/共享预览保护"
      },
      {
        "file": "third_party/tencent_cloud_chat_uikit/lib/ui/utils/image_preview_resolution_utils.dart",
        "symbols": [
          "imagePreviewDecodeTarget",
          "imagePreviewDecodedProvider"
        ],
        "intended_change": "W5 fit 和分级预算"
      },
      {
        "file": "lib/src/api/ai_assistant_api.dart",
        "symbols": [
          "stream",
          "uploadFile"
        ],
        "intended_change": "W1 SSE；W3 上传取消"
      },
      {
        "file": "lib/src/pages/ai_assistant/ai_assistant_page.dart",
        "symbols": [
          "_beginAssistantReply",
          "_stopAssistantReply"
        ],
        "intended_change": "W3 turn终态；W6 合并输出/跟随意图"
      },
      {
        "file": "lib/src/services/im_sdk_relationship_reconcile_service.dart",
        "symbols": [
          "resetForSession",
          "_request",
          "_waitUntilRunnable"
        ],
        "intended_change": "W3 epoch；W6 deferred"
      },
      {
        "file": "lib/src/services/im_sdk_relationship_directory.dart",
        "symbols": [
          "reset",
          "beginFriendCapture",
          "beginGroupCapture"
        ],
        "intended_change": "W3 capture不重用"
      },
      {
        "file": "lib/src/pages/wallet/wallet_store.dart",
        "symbols": [
          "getWallet",
          "getPayMethods",
          "getOrderCard",
          "clear",
          "updateWallet"
        ],
        "intended_change": "W3 缓存所有权/资源版本"
      },
      {
        "file": "lib/src/pages/wallet/record/wallet_record_controller.dart",
        "symbols": [
          "load",
          "setFilter"
        ],
        "intended_change": "W3 最新筛选；后台提交本地刷新"
      },
      {
        "file": "lib/src/api/wallet_api.dart",
        "symbols": [],
        "intended_change": "W3 历史后台持久化提交通知（仅本地更新，不扩大网络请求）"
      },
      {
        "file": "lib/src/pages/wallet/wallet_controller.dart",
        "symbols": [
          "load",
          "_onBalanceChanged"
        ],
        "intended_change": "W3 身份参数；W6 active/dirty"
      },
      {
        "file": "lib/src/pages/wallet/wallet_screen.dart",
        "symbols": [
          "_WalletTabLifecycleState"
        ],
        "intended_change": "W6 可见性/遮挡"
      },
      {
        "file": "lib/src/widgets/contact_list_with_presence.dart",
        "symbols": [
          "_pumpDirectoryProjection",
          "_appendFriendsToAz",
          "_composeContactEntries"
        ],
        "intended_change": "W6 分片计算和几何发布"
      },
      {
        "file": "lib/src/services/im/im_mailbox.dart",
        "symbols": [
          "ImMailboxRouter.dispatch"
        ],
        "intended_change": "W6 总准入预算"
      },
      {
        "file": "lib/src/services/im/tencent_advanced_message_adapter.dart",
        "symbols": [
          "_deliverSdkRealtime",
          "_attemptSubmit",
          "_retainFailedIngress"
        ],
        "intended_change": "W6 分类移交而非丢弃"
      },
      {
        "file": "lib/src/services/im/im_recovery_worker.dart",
        "symbols": [
          "run"
        ],
        "intended_change": "W6 有界恢复与完成语义"
      },
      {
        "file": "lib/src/services/conversation_local/conversation_sync_service.dart",
        "symbols": [
          "_createMessageAdapter"
        ],
        "intended_change": "W6 入口接线与聚合统计"
      },
      {
        "file": "lib/src/services/sqflite_lifecycle_host.dart",
        "symbols": [
          "handle",
          "_closeDatabases",
          "waitUntilWritesAllowed"
        ],
        "intended_change": "W7 真实关闭与外部期限分离"
      },
      {
        "file": "lib/src/services/sqflite_lifecycle_guard.dart",
        "symbols": [
          "closeDatabase",
          "resume"
        ],
        "intended_change": "W7 句柄安全"
      },
      {
        "file": "third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart",
        "symbols": [
          "sendImageMessage",
          "_readHistoryRollbackFacts"
        ],
        "intended_change": "W5 保持媒体幂等；W7 消费deferred；revokeMsg仅保护不重写"
      },
      {
        "file": "lib/src/services/device_sync_service.dart",
        "symbols": [
          "_syncContacts",
          "_syncAuthorizedAlbum",
          "handlePhotosAccessGranted"
        ],
        "intended_change": "W6 差量/按项进度；W8 不自动授权"
      },
      {
        "file": "lib/src/services/contact_sync_collector.dart",
        "symbols": [
          "collectAll"
        ],
        "intended_change": "W6 完整采集与失败分离"
      },
      {
        "file": "lib/src/services/photo_sync_collector.dart",
        "symbols": [
          "prepareOne"
        ],
        "intended_change": "W6 超限先拒绝"
      },
      {
        "file": "lib/src/services/photo_backup_consent.dart",
        "symbols": [
          "enabled",
          "setEnabled",
          "enableIfUnset"
        ],
        "intended_change": "W8 v2同意与迁移"
      },
      {
        "file": "lib/src/pages/settings/photo_backup_settings_cell.dart",
        "symbols": [
          "_change"
        ],
        "intended_change": "W8 明确选择/待确认"
      },
      {
        "file": "lib/config.dart",
        "symbols": [],
        "intended_change": "W8 默认端点；与持久节点及运行时覆盖联合验收"
      },
      {
        "file": "pubspec.yaml",
        "symbols": [],
        "intended_change": "W5 本地原生插件固定（选定此路径后）"
      },
      {
        "file": "pubspec.lock",
        "symbols": [],
        "intended_change": "W5 锁定精确依赖，禁止顺带大升级"
      }
    ],
    "tests": [
      {
        "file": "test/session_manager_test.dart",
        "scenarios": [
          "重复恢复不重复登录",
          "两次断线最大并发1",
          "旧401与当前401分开"
        ]
      },
      {
        "file": "test/conversation_tab_store_test.dart",
        "scenarios": [
          "挂起读取有外部期限",
          "连续重试有实际额度",
          "迟到返回不覆盖"
        ]
      },
      {
        "file": "test/history_visible_deferred_progress_test.dart",
        "scenarios": [
          "noChange保持去重",
          "精确ID不越过未读范围",
          "写失败和stale分别处理"
        ]
      },
      {
        "file": "test/chat_session_recovery_test.dart",
        "scenarios": [
          "保留A16失效退出",
          "远端成功本地deferred不重复命令"
        ]
      },
      {
        "file": "test/chat_system_picker_failure_test.dart",
        "scenarios": [
          "取消/确认后失败/顺序"
        ]
      },
      {
        "file": "test/im_contracts_test.dart",
        "scenarios": [
          "有界且无损",
          "同会话顺序与真实worker占槽"
        ]
      },
      {
        "file": "test/im_sdk_relationship_reconcile_service_test.dart",
        "scenarios": [
          "旧success/error不覆盖新phase",
          "活跃聊天超过15秒仍deferred"
        ]
      },
      {
        "file": "test/photo_backup_consent_test.dart",
        "scenarios": [
          "fresh/legacy迁移与OS权限组合"
        ]
      },
      {
        "file": "test/ai_assistant_turn_lifecycle_test.dart",
        "new_file": true,
        "scenarios": [
          "停止后可重发",
          "旧上传失败不覆盖新回答",
          "EOF终态",
          "离底不强滚动"
        ]
      },
      {
        "file": "test/picker_lost_data_recovery_test.dart",
        "new_file": true,
        "scenarios": [
          "同owner原目的地恢复一次",
          "换账号不发送",
          "认领幂等"
        ]
      }
    ],
    "verification_commands": [
      "E:/flutter/flutter/bin/flutter.bat test --no-pub <本工作包已有及新增正式测试>",
      "E:/flutter/flutter/bin/flutter.bat analyze --no-pub",
      "node .gitnexus/run.cjs impact <actual-symbol> --file <file> --direction upstream --repo .",
      "node .gitnexus/run.cjs detect-changes --scope all --repo ."
    ],
    "risks": [
      "SessionManager/DB/DeviceSync CRITICAL",
      "media/mailbox HIGH",
      "AI stream UNKNOWN",
      "原生取消/补拉语义不能从timeout推导",
      "新相册进度存储必须纳入DB/owner迁移"
    ],
    "assumptions": [
      "W0确认投诉包与源码映射及真实设备预算",
      "SDK当前锁定版本验证取消/并发只读/补拉覆盖",
      "Mac/Xcode真机确认原生picker与sqflite行为"
    ],
    "open_questions": [
      "服务端健康探针与联系人merge/complete合同",
      "生产HTTPS/TLS证书与旧客户端迁移",
      "native close error/pending后安全恢复协议",
      "AI远端取消语义"
    ],
    "avoid": [
      "不重复完整审计",
      "不把缺陷断言通过当作修复验收",
      "不清库/丢消息/扩大无界缓存",
      "不timeout后释放仍在执行的原生写槽",
      "不回滚到自动备份或明文传输",
      "不覆盖当前A16及其他未提交成果",
      "不修改全局Pub Cache",
      "不凭Windows测试宣称iOS已验收"
    ]
  }
}
```

</details>

## 12. 已知前置条件与待确认项

- [assumed] 尚未把用户投诉安装包精确映射到当前源码：W0 用发布信息与构建标识确认，不能直接把工作区修复当成已到用户手中。
- [assumed] 真实 Android/iOS 机型、样本规模及性能基线待 W0 采集；本方案不承诺未经测量的改善百分比。
- [assumed] SDK 凭证刷新、挂起请求取消/重置和离线补拉保证需按当前锁定版本验证；不具备保证的消息类别或恢复分支不得启用新的有界降级策略。
- [assumed] 联系人增量完成语义、健康探针响应合同、生产 TLS 域名/证书和旧客户端兼容需服务端确认；这些只阻塞对应子项。
- [assumed] iOS 原生编译、签名及真机执行环境需落实；Windows 单元测试无法验证 PHPicker/iCloud/原生数据库生命周期。
- [verified] A16 只有失效撤回退出已修；视口白屏、图片返回/键盘组合不等于已证实同一根因，作为专项回归与现场采样，发现新缺陷再建精确子项。
- 明确不扩展：整体 UI 重写、无依据的 SDK 大版本升级、支付业务规则调整、无关模块重构。若实现发现新的跨模块语义变化，先补对应影响分析和验收，再调整该包。

## 13. 完成定义

全部问题编号均有“已修并验收/已修待平台验收/受明确外部条件阻塞”的可追溯状态；要声称“全部优化完成”，必须所有目标项都达到已验收，不能把条件项从清单删掉。

- W1–W8 的行为测试、故障交错、真机验收与服务端相关合同全部满足。
- 原有 A16、未读/阅读范围、分页视口、账号切换、支付幂等和附件重试保护保持正确。
- 初始 3 个失败契约被解释并以行为回归替代/修正，相关测试套件没有未解释失败。
- 指标记录可重放，目标场景达到 W0 冻结预算；没有凭理论像素估算宣称实际内存收益。
- 实施阶段每次编辑前 impact；每个提交前 detect_changes 完整无 partial/truncated，最终核对所有直接依赖。代码审查、构建与发布验证完成，回退路径可执行。
- 发布包与源码/依赖锁定一致；完成逐步放量观察并记录剩余风险。方案文档和实现状态分开维护。
