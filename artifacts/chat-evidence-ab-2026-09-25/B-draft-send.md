**B 包：F1/F2 完整状态、写入路径与第一轮修改点**

本包依据当前工作树，相关方法/类型采用 Dart AST 边界提取，未按签名行截断。大文件只摘取相关方法；较小的服务和契约文件保留完整正文。

[完整源码正文](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-evidence-ab-2026-09-25/B-source-complete.md>) · [摘录清单与哈希](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-evidence-ab-2026-09-25/source-manifest.json>) · [本轮 47 项定向测试结果](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-evidence-ab-2026-09-25/focused-tests-summary.json>)

上一轮草稿与发送状态反例仍在 [audit_probes_test.dart](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-full-chain-audit-2026-09-25/audit_probes_test.dart>)。由于对应源文件未变化，本轮复用其 [最终实验输出](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-full-chain-audit-2026-09-25/probes-final.jsonl>)，没有把它们描述为已经修复。

**B1．F1 的真实存储模型**

| 层 | 当前状态 | 寿命与作用 |
|---|---|---|
| ChatDraftController | text、_writeGeneration、_stateRevision、_sendClearBarrier、250ms debounce | 页面控制器内存；新实例重新从零开始 |
| ChatDraftWriteQueue | 一个 Future tail | 当前页面串行写入；不跨页面、不持久化 |
| ConversationDraftService | _tails、_versions | singleton 内存，key=owner + session generation + canonical SDK conversation ID |
| SDK 会话草稿 | setConversationDraft / getConversation.draftText | 当前权威草稿内容；应用只传 conversationID/text，没有 expectedRevision 参数 |
| SQLite 会话镜像 | local_draft_text、local_draft_updated_at；PK(owner_user_id,conversation_id) | 兼容镜像与会话展示 |
| SQLite coordinator state | generation、tombstone、字段状态等持久化信息 | 会话 mutation 仲裁；不是页面提交快照的 draft revision |

关键源码：[草稿服务](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_draft_service.dart:15>)、[会话表](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_local_store.dart:1322>)、[coordinator state 表](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_local_store.dart:1387>)。

ConversationDraftService._versions 不是持续递增的持久版本：当最后一个 tail 完成时，会把该 key 的 _versions 一起删除；下次写入可能又从 1 开始。因此既不能将页面 revision 当跨页面版本，也不能直接将服务 _versions 当永久会话版本。

当前 loadDraftText 读取 SDK 会话；persist/clear 先写 SDK，成功后提交 SQLite mirror，再通知会话列表。改 SQLite schema 或只在镜像加 CAS，都不能单独防止旧任务清掉 SDK 权威草稿。

**B2．F1 完整调用链与竞态位置**

~~~text
输入 onSubmitted / _onEmojiSubmitted
  ├─ 调用 sendTextMessage 或 sendTextAtMessage（不等待发送完成）
  └─ 清空 controller + onChanged("")
         ↓
Chat._onChatDraftTextChanged
  → ChatDraftController.onChanged
  → debounce / 空值立即持久化
  → Chat._persistChatLocalDraftText
  → ChatDraftWriteQueue.enqueue
  → ConversationDraftService.persistDraft
  → _write（捕获“调用此时”的账号和版本）
  → SDK setConversationDraft
  → _commitDraft / commitCoordinatorPlan
  → ChatSessionController.applyCommittedProjection

稍后旧发送成功：
SeparateViewModel._sendMessage
  → lifeCycle.messageDidSend
  → Chat._clearChatLocalDraftAfterSend
  → 当前 _draft.markSendCompleted
  → 当前 ids 集合的 clearDraftForConversationIds
  → _write(null)
~~~

清理方法没有携带提交版本；ids 还组合了传入 lifecycleConversationId 和当前 _conversation 的 ID/群别名。资料包提供完整 initState，包含这个生命周期闭包，不只摘出几行 callback。

服务 _write 的“后来的请求胜出”规则不能识别请求的业务新旧。A 的成功清理晚于 B 保存进入服务，就被分配更大的 version，反而成为“最新写入”；这正是为什么只靠现有队列不能修 F1。

账号保护也存在边界：_write 会捕获调用时的身份，保护的是写入开始后的换号；它不能知道调用方拿着旧发送快照，却在新账号环境里才调用 clear。提交时的身份必须一路传到清理请求。

**B3．F1 的第一轮修改契约**

一次发送只结算自己的提交快照，提交快照至少关联：

- owner + account/session generation。
- canonical conversation ID。
- 不复用的草稿编辑会话身份，以及该编辑会话内的 revision。
- submissionId；SDK local ID / operationId 尚未生成时，后续再绑定，不从文本内容猜身份。

现有 operationId 在 ImOutgoingSendCoordinator.send 中、SDK create 之后才生成；输入提交时拿不到它。因此不能假设在 onSubmitted 时已经有 Outbox operationId，也不能为修草稿顺手重做 ACK key。可以先使用 submissionId，再绑定到既有身份链。

建议在现有三个位置落实，而不是新建一套平行草稿系统：

| 修改位置 | 应承担的规则 |
|---|---|
| 输入提交 / 生命周期接线 | 提交前捕获快照；区分“此次提交导致的程序清空”与“用户后续编辑”；把结果关联回这次提交 |
| ChatDraftController / Chat 页面 | 完成回调只失效提交版本之前的工作；B 的 debounce、内存和离页保存不受影响；不从当前 _conversation 扩大清理范围 |
| ConversationDraftService 现有 per-key 队列 | 接受捕获的身份与 expected token；入队时和真正执行时校验；SDK 完成后复核，禁止旧结果覆盖 mirror/通知 |

关于跨页面和跨重启，当前证据支持这样处理：

- 跨页面：必须由会话/账号作用域的服务持有不复用的编辑身份，不能只比两个页面都从零开始的整数。
- 跨重启：当前草稿清理是内存队列与 callback，没有发现持久化的“清草稿任务”。普通 Future 不会跨进程存活，不能为了一个尚不存在的恢复任务盲目迁移数据库。
- 若以后引入可跨重启重放的草稿操作，应持久化独立版本并做条件写入；那应是单独的 schema/恢复契约工作，不能直接复用 timestamp 或内存 revision。

SDK setConversationDraft 没有 compare-and-set 参数，所以“执行前检查一次”仍不足：旧 SDK clear 已发出期间如果接受了新编辑，旧调用无法被应用层凭空撤销。必须保留 per-key 串行处理，使较新意图最终成为最后有效 SDK 写入；对于在途旧结果，复核后不发布过期 mirror/列表状态，必要时重新应用当前有效意图。验收必须观察最终 SDK 草稿和重新进入后的恢复，而非只看本次 controller.text。

本轮在这条实际失败回写路径中未发现 updateMessage 使用 setInputField 自动把失败文字写回输入框；该参数仍在传递但不能因此假设已有完整失败恢复。若新增失败恢复，必须遵守同样的提交版本条件。

**B4．F1 必要回归用例**

| 顺序 | 必须断言 |
|---|---|
| 发 A → 输入 B → A 成功，B 尚未 debounce | B 的内存、待保存任务与离页保存仍有效 |
| 发 A → B 已写入 SDK/mirror → A 成功 | SDK 与 SQLite 最终都是 B，旧清理被拒绝 |
| 发 A → 离页 → 重开并输入 B → A 回调 | 新页面 B 不受旧页面 revision 碰撞影响 |
| 发 A/C → 输入 B → 回调乱序 | 多个旧提交都不能清 B |
| 发 A → 手动清空 / 输入相同文本 A | 按 revision/identity 仲裁，不按字符串相同推断同一次编辑 |
| 发 A → 换会话/换号 → 回调 | 不清当前会话或当前账号 |
| 旧 SDK 写已发出 → 新编辑 → 旧 SDK 返回 | 旧结果不发布，最终保存当前有效意图 |
| SDK 草稿写失败 → 后续正常写 | 队列不被失败污染，不能虚报保存完成 |

原有服务测试已经覆盖 alias 串行、旧保存不提交、SDK 错误不污染后续写、换号失效；它们没有覆盖“业务上旧的成功回调作为一个较新的 clear 入队”，因此通过这些测试并不能关闭 F1。

**B5．F2 消息身份与尝试字段**

[OutgoingIdentityContract](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/contracts/outgoing_identity_contract.dart>) 的完整类型、编码/解码和生成函数已收入源码包。

| 字段 | 产生与用途 | 不能据此推导什么 |
|---|---|---|
| 乐观 UI ID | sendTextMessage 在 createTextMessage 前插入占位消息 | 不是 SDK dispatch 身份 |
| SDK local id | createTextMessage 返回，乐观消息随后采用它 | 不是送达证据 |
| operationId | coordinator 正常 send 新建；prepared recovery 可保留原 ID | 不能用会话 ID 代替它 |
| clientCorrelationId | 随 operation 生成，放入 cloud custom data | 必须配合 owner/conversation/payload 校验 |
| payloadFingerprint | 消息规范化 payload 的指纹 | 不能单凭文本相同判断同一操作 |
| sendOperationGeneration | 当前 coordinator 实例内递增 | 非持久的跨重启尝试计数 |
| dispatchAttemptId | attempt:operationId:sendGeneration:nowMs，写入主表和恢复副本 | 当前结果 API 未要求调用方传回 expectedAttemptId |
| serverMsgId / sync msgID | 同步身份回调或成功结果补全 | “非空 ID”不能替代成功状态/服务端证据 |
| UI outgoing stable ID | 消息行与本地别名合并 | 需和当前操作/尝试的仲裁结果相连，不能单独覆盖终态 |

适配器在 SDK Future 完成前即可接收 onSyncMsgID；真正的 send success 则检查 result.code==0。另有失败占位对象将 msgID 设为本地 id 的代码，因此“只要有 msgID 就忽略失败”在当前封装内明确不成立。

用户重试路径会 recreateOutgoingMessage，生成新 SDK 消息，移除旧行再调用普通 _sendMessage；普通 coordinator send 再生成新的 operation/correlation。prepared recovery 才允许显式复用旧 operationId。两种行为不能混成同一次尝试。

**B6．F2 实际 Outbox 表与状态**

当前独立数据库为 message_core.db，建表源在 [MessageCoreStore._createSchema](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/message_core_store.dart:305>)。ConversationLocalStore 中还保留历史表/迁移代码，本包没有把旧表定义误当成唯一活动存储。

| 表 | 主键与重要字段 |
|---|---|
| message_outbox | operation_id 主键；owner_user_id、conversation_id、client_correlation_id、payload_hash、state、sdk_message_id、server_msg_id、dispatch_attempt_id、result_code、lease/fencing、retry、密文/媒体引用 |
| message_outbox_recovery_copy | PK(owner_user_id,operation_id)；correlation/conversation/payload identity、recovery_revision、state、dispatch_attempt_id、sdk_local_id、server_msg_id、result_code、checksum |
| idx_message_outbox_ready | owner_user_id、state、next_retry_at 的索引 |

发送主要转换：

~~~text
prepared + copyPrepared
  → dispatchIntent + dispatchIntent
  → sending
      ├─ SDK 成功 → acknowledged + resultRecorded
      │              → UI projection 完成 → completed + reconciled
      ├─ SDK 明确失败 → failedTerminal + resultRecorded
      └─ 超时/异常 → outcomeUnknown + outcomeUnknown
                       → history/provider 证据采纳
                       → acknowledged / completed
~~~

状态枚举还包含 manualRequired、pausedByLogout、abandonedByUser 等终态/恢复状态。不能为了统一失败显示，将它们都压成 failedTerminal。

**B7．F2 仲裁现状和实际缺口**

[Im05Persistence._recordOutboxSdkResult](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/im05_persistence.dart:1161>) 已在一个 transaction 内：

1. 核对 writer lease/fencing。
2. 读取主记录和恢复副本。
3. 检查两份 identity，以及两份 dispatchAttemptId 是否互相一致。
4. 只允许合适的 state 转换，更新恢复副本与主记录。
5. SQL update 同时匹配 owner、operationId、expected state。

这已经是可复用的原子仲裁基础，不需要把所有会话发送塞到一个全局串行队列。

但它返回 bool，含义并不等于“调用方给的这个状态被采纳”：

| 原有状态与请求 | 当前返回 | 实际含义 |
|---|---|---|
| sending，符合身份的显式失败 | true | 失败被写入 |
| acknowledged，随后显式失败 | false | 成功态不允许退回失败 |
| completed + reconciled，随后显式失败 | true | 已经完成的幂等早返回；并没有把它改成失败 |
| outcomeUnknown，普通 dispatch callback 再来 | false | 保留 unknown，等待合规证据 |
| lease/身份/副本冲突 | false | 不允许当前调用影响记录 |

所以“把 unawaited 改成 await，然后 bool 为 true 就投影失败”仍然是错误修法。

当前 coordinator 的显式失败分支 unawaited recordOutboxSdkFailed，之后直接返回原始失败 callback；UI 的 applyOutgoingSendResult 再无条件降级。这解释了存储已保护成功但 UI 仍可能失败的分裂。

当前 _recordOutboxSdkResult 比较的是主表与恢复副本的 attempt 是否一致，不是“这次结果携带的 attempt 是否等于当前 attempt”。recordOutboxSdkFailed/Succeeded 的参数也没有 expectedAttemptId。虽然新手动重试通常会生成新的 operationId，结果契约仍应把尝试边界写清楚，而不是依赖隐含假设。

**B8．成功证据的入口边界**

- SDK 结果：adapter 根据 code==0 构造成功，不以 msgID 是否为空代替。
- 运行时 Inbox/provider 采纳：adoptOutboxProviderSucceeded 校验 operation、correlation、conversation、payload hash 及租约；只接受相应 sending/unknown 组合。
- 历史归并：completeHistoryReconciliation 提交后 unawaited adoptProviderHistory。因此 UI 历史投影和 Outbox 的确认存在时间差。
- 普通 SDK realtime namespace：_handleMessageIngress 在进入通用 Inbox adoptOutgoing 回调前就进入快速路径并返回。不能假设每个 realtime 事件都已经走过 durable success adoption；修 F2 必须核对快速路径的成功证据如何与现有 Outbox 结果仲裁接上。
- 关系禁止与无效目标：还有在 coordinator 之前直接调用 GlobalModel 的失败路径，不能只修 coordinator 后就认为所有写失败入口已收口。

本包补上 applyAppRealtimeMessage、_onReceiveNewMsg、历史提交、_handleMessageIngress 和 _providerOutgoingIdentity 的完整方法，用于核对上述顺序。这里没有要求所有实时事件绕一遍 Inbox，只要求同一发送操作的证据规则一致。

**B9．F2 第一轮修改契约**

优先扩展现有持久化仲裁返回值，不新建平行状态机。结果应明确表达：

- 对哪个 owner/conversation/operation/attempt 作出决定。
- 是否采纳此次事件；未采纳原因。
- 当前权威 state，以及可确认的成功/失败/unknown 证据。
- 当前状态版本或可拒绝旧投影的令牌。
- UI 是否可以更新、是否可以显示重试、是否可以完成 projection。

具体修改点：

| 层 | 修改要求 |
|---|---|
| Im05Persistence | 事务内判断后返回明确 verdict + 当前状态；继续使用条件更新与 lease；把调用结果的尝试身份纳入核对 |
| ImOutgoingSendCoordinator.send | 成功/失败/unknown 都消费仲裁结果；显式失败不能先放给 UI，再异步补持久化 |
| ImCoordinatedSendResult | 携带已仲裁身份与状态，不仅提供原始 SDK callback |
| GlobalModel / SeparateViewModel | 只投影仍属于当前操作/尝试的 verdict；旧失败不能覆盖后来成功；直接失败入口使用同一规则 |
| 实时与历史成功采纳 | 复用同一证据条件，避免 UI 与 durable 状态长期各判一次 |
| 重试与生命周期 | 重试入口消费同一终态；messageDidSend 不应再把未经仲裁的原始 code 当唯一依据 |

存储事务结束到 UI 投影仍有异步间隔，不能只有“先查一次成功、再更新 UI”。需要携带状态版本/尝试令牌，或让同一 operation 的投影仲裁在既有归并规则里拒绝旧结果。这样可以处理：失败事务先完成 → 成功证据随后提交 → 旧失败投影最后才到达。

必须保留 outcomeUnknown 的既有保护，不自动将迟到 SDK success/failure 当作恢复查询证据；也不扩大此前收窄的 ACK key 工作范围。

**B10．F2 必要回归用例**

| 顺序 | 必须同时断言 |
|---|---|
| provider 已 acknowledged → 旧失败 | 主表/副本保持成功，UI 成功，不能重试 |
| completed/reconciled → record failed 返回幂等结果 | 不能将 bool=true 误读为采纳失败 |
| 失败 verdict 先形成 → 成功证据提交 → 旧失败 UI 延迟 | 旧 UI verdict 被版本/身份拒绝 |
| 同 operation 的旧 attempt 回调 | 拒绝旧尝试，不影响当前尝试 |
| 手动重试新 operation、新 SDK id | 旧回调不更新新行、不触发新提交的草稿清理 |
| correlation/payload/owner 不匹配 | 不采纳“成功”，不做别名误合并 |
| 只有 sync msgID，SDK 随后失败 | 不把 ID 存在当送达 |
| outcomeUnknown 后迟到 success/failure | 保持既定 unknown 恢复规则 |
| 历史成功先投影、持久化采纳未完成 | 旧失败仍不能闪成重试态 |
| 快速 realtime / Inbox / 历史三条来源 | 对同一证据得到一致终态 |
| clear/revoke/cancel/logout 并发 | 不复活被删除消息、不污染新 owner |

**B11．现有测试与覆盖缺口**

本轮补跑 4 个测试文件，47 项全部通过：

- im08_outgoing_send_coordinator_test.dart。
- conversation_local_store_draft_test.dart。
- chat_open_perf_log_test.dart。
- conversation_settings_reliability_test.dart。

其中 Im08 文件虽然名字带 coordinator，正文主要是适配结果类型/持久化恢复契约，不能因此宣称已经覆盖“真实 coordinator → GlobalModel → 页面回调”的整个链路。草稿服务测试通过也不能替代提交快照的跨页面竞态测试。

上一轮 F1/F2 的组件反例仍应在修复时迁入正式 test/ 并增强：F1 要验证 SDK/mirror/离页重开，F2 要验证 Outbox、UI、重试入口三者一致，而不是仅测一个 status 常量。

本轮没有修改业务源码或正式测试集，47 项是新增验证证据，不是“修复完成”的声明。

**B12．影响评估与变更拆分**

| 符号 | impact 结果 | 解释 |
|---|---|---|
| applyOutgoingSendResult | 上轮 CRITICAL，3 个去重直接调用者、48 个三层影响项 | 两套发送模型及好友禁止同步共用；修复前需要保留此风险警告 |
| _recordOutboxSdkResult | LOW，2 个直接调用者，5 个影响项 | 公共成功/失败持久化入口，测试必须覆盖两边 |
| recordOutboxSdkFailed | LOW，2 个直接调用者，6 个影响项 | 除 send，还涉及卡住消息的失败恢复 |
| adoptOutboxProviderSucceeded | LOW，图中 1 个直接调用者 | 源码另有历史协调器调用；图低风险不代表所有动态调用均被解析 |
| persistDraft / clearDraftForConversationIds | UNKNOWN，图未解析 callers | 已通过源码确认 Chat 持久化/发送回调及测试调用，未按“无调用”处理 |

建议拆成三个可独立审阅的变更：F1 草稿提交快照；F2 发送结果仲裁；A 包已有埋点的 Profile 采集与阶段补齐。每个变更分别 impact、反例回归和提交前 detect_changes。窗口、缓存、并发、ACK key 与大文件拆分不混入这三项。

