# 聊天统一调度：实施状态

基线：c5008765a84faf765b8f6b47bd7c878980ad71e7
分支：codex/unified-chat-runtime-core

## 当前交付范围

已将生产消息入站与恢复队列接入 RuntimeEffectScheduler，并统一持久 Inbox 的提交阶段顺序。AccountRuntimeSupervisor 仍为 shadow，RuntimeCommitCoordinator 和 RuntimeViewSession 尚未接管生产业务权威与页面状态；全量统一调度迁移仍未完成。详见第五批记录。

| 模块 | 已实现行为 |
| --- | --- |
| RuntimeDocument / RuntimeEnvelope | 深层不可变数据、账号与 SDK 代次、会话、清空代次、事件和操作标识、可选页面及版本依赖 |
| AccountRuntimeSupervisor / ConversationActor | 每会话 FIFO，短批次让出事件循环，重复事件去重，账号/清空/页面/修订准入，失败不提交 |
| RuntimeEffectScheduler | 限制并发、每通道 FIFO、通道轮转、显式等价请求合并、显式过载、保留已发出操作的迟到结果 |
| RuntimeViewSession | 每次页面访问独立状态、有限回最新目标、窗口与布局证明、读取确认仅覆盖证明与捕获集合的交集 |

基础层在 third_party/tencent_cloud_chat_uikit/lib/business_logic/runtime/，不依赖 Flutter、腾讯 SDK 或宿主业务服务。EffectScheduler 已通过生产 ImMailboxRouter 执行入站工作，shadow account runtime 仍只返回效果意图。

事件去重、清空请求和 actor 生命周期当前是内存实现。它们还没有持久恢复或淘汰策略，不能作为正式消息账本，也不应直接启用为长期运行的账号服务。不能通过把 shadow 政名为 live 完成上线。

## 已验证

新增 24 项行为测试：

- 嵌套 SDK 形状数据冻结，拒绝可变对象和回调。
- 同会话顺序、重复事件、不同会话公平调度。
- 清空先使旧事件失效；重复清空幂等；同 ID 不同代次拒绝；清空准备失败不移动屏障。
- 账号关闭、关闭后读取、页面重新打开和搜索替换后的旧结果拒绝。
- Reducer 失败不提交；生命周期屏障在发布前再次核验。
- 效果通道串行与跨通道并发、等价合并、异常释放、显式过载。
- 已 dispatch 的操作在关闭后仍保留实际响应，不自动重发。
- 两个页面状态独立；有限目标不随新消息延伸。
- 过期账号、清空、visit、operation、窗口、布局证明均拒绝。
- 窗口替换要求重新布局，目标缺失回到加载态。
- 相同因果顺序在不同批次大小下产生相同快照和效果意图。

加上原有 27 项 MessageReconciliationWriter 测试，共 51 项通过。重复清空的临时探针已确认“修复前失败、修复后通过”。

验证命令（在本工作树执行）：

~~~powershell
flutter test --no-pub test/chat_runtime_scheduler_test.dart test/chat_runtime_multi_view_test.dart test/chat_runtime_replay_test.dart test/message_reconciliation_writer_test.dart
dart analyze --fatal-infos --fatal-warnings third_party/tencent_cloud_chat_uikit/lib/business_logic/runtime test/chat_runtime_scheduler_test.dart test/chat_runtime_multi_view_test.dart test/chat_runtime_replay_test.dart
~~~

## 现有基线失败

改动业务代码前，在原工作区相同 HEAD 上两次运行 Writer 与 durable scroll 套件，均为 34 通过、13 失败。失败涉及逐行可见性、未读推进、裁剪连续性、媒体布局恢复以及手动滚到最新后计数未清零。本次没有修改这些原有断言，也没有声称修复这些生产链路。

原有 tool/im_gate.ps1 基线同时发现：

- 格式检查报告 15 个文件需要格式化（检查未写文件）。
- 分析器因本地状态目录配置崩溃。
- 引用了不存在的 test/conversation_pin_api_test.dart，导致测试阶段未执行。
- 静态扫描发现两个应用层 setMessageList 调用及旧分类计数不一致。

对应日志保存在原工作区 artifacts/chat-full-chain-2026-09-22/runtime-baseline-tests.log 和 runtime-baseline-im-gate.log。新工作树检查日志位于 .dart-appdata/。


## 持久提交层（第二批）

已增加 RuntimeCommitCoordinator 和 RuntimeCommitSchema，并以 3 行增量代码注册到 MessageCoreStore 的建表及旧库修复流程。未迁移或删除旧表，未启用第二个生产消息写入者。

- 会话快照、事件去重和效果意图在同一 SQLite 事务内提交；版本冲突、身份冲突或写入失败时整体回滚。
- 复用 MessageCore 的数据库写入队列与持久租约；事务提交前再次检查租约与账号代次。
- 清空代次与待执行效果取消一起提交；已发出的操作保留原身份与结果。
- 效果执行前必须先持久领取唯一 attempt；结果未知不能再次领取或自动重发。
- 新租约接管后，已领取但未确认的操作进入 unknown；未发送操作保留，需宿主显式复核后才能在新会话领取。
- 有限分页按 revision、operation 和 kind 游标恢复，不遗漏同一次提交中的多个效果。
- 已完成事件保留持久去重身份。快照和效果账本尚无归档策略，不应当作完整历史消息存储。

新增 16 项真实 SQLite 测试，覆盖重启、回执丢失、原子失败、租约/账号失效、并发版本竞争、重复领取、迟到结果、跨会话隔离、分页与旧库升级。清空回执丢失测试已验证修复前失败、修复后通过。

当前合并验证：90 项通过（40 项新运行时/持久测试，50 项原有 Writer、MessageCore、IM05、回执兼容测试）。全部新增 Dart 模块和测试严格分析无问题。日志在 .dart-appdata/runtime-combined-tests.log。

此层目前只由测试使用，shadow supervisor 仍不会调用数据库。清空/变更/deferred/读取权威迁移、持久 actor 接入、生产入口切换、页面接入和旧写入入口删除均未完成；第二批交付不等于完整第二阶段或整体根治。

## 后续迁移门槛

1. 完成基线与性能测量；修复现有门禁自身的问题。
2. 在 MessageCoreStore 内设计并实现原子提交、事件去重和效果意图持久化，验证中断恢复。将需要同事务生效的清空、变更、deferred 和读取权威迁入同一提交域，旧 HistoryWindowStore 降为可重建缓存。
3. 实时、历史、搜索、删除、撤回、清空按完整会话状态域接入；切换时撤销旧写入权，禁止分支双写。
4. 将页面的搜索/回最新/布局/滚动/可见性确认接入独立 ViewSession，逐项消除上述 13 项失败。
5. 发送、附件和恢复接入效果策略；保留 Outbox 身份和 unknown 状态，禁止无证据自动重发。
6. 接入资料、权限、草稿与后台恢复，删除分散的旧写入入口和计时器。
7. 执行完整行为、崩溃恢复、多页面与性能验收后，才能认定整体完成。

## 图分析范围

本工作树单独注册为 99chat-runtime，当前索引位于 D:\\CodexRuntimeIndexes\\unified-chat-runtime-verified-20260922，避免原工作区并发改动和 Windows 旧索引句柄影响分析。

本次将索引上限设为 1024 KB，并在 .gitnexusignore 中仅排除四份已确认的压缩 Web SDK 分发包。手写 Web 桥接代码保留。两个超大业务文件 tui_chat_global_model.dart 和 tim_uikit_chat_history_message_list.dart 已在图中定位到真实类与调用者，原有大小过滤缺口已补齐。后续刷新仍须设置 GITNEXUS_MAX_FILE_SIZE=1024，防止默认 512 KB 再次漏掉它们。

全局流程枚举仍存在截断，接口/动态调用也不能完全静态追踪。影响分析必须查询具体目标，并核对实际调用点；不能用全局流程中的缺席或 UNKNOWN 作为零影响证据。持久提交适配器仍仅由测试使用；调度器已接入生产入站和恢复。增量 schema 已接入 MessageCoreStore 的现有启动流程。

## 手动回底与回弹消息修复（第三批）

已修改生产列表、胶囊策略、可见已读计数发布和跟随恢复提交。原有八套件基线有 32 项失败，最终扩大到十套件后为 126 项通过、12 项既有失败，无新增失败；六个专项页面回归全部通过。详见 [修复与验证记录](chat_bottom_settlement_fix.md)。上述早期“13 项均未修复”为第一、二批时点记录，本批已修复其中部分场景。统一运行时生产入口迁移仍未完成。

## 剩余回底回归修复（第四批）

第三批留下的 12 项现已全部通过。将手动阅读的胶囊计数与持久未读统一到同一个帧后可见行采样器；显式回底采用带访问代次的有限 ID 快照，避免超出 120 条的 SQL 尾部查询遗漏已处理身份。修复回底期间迟到消息、失败后的重试提示、键盘已打开时点击输入框回底，并验证空闲跑道收敛与 300 条跨窗口裁剪。

原十套件 138 项及新增纳入的两个账本套件合计 165 项通过。额外万条压测的正文缓存断言仍失败，已用修改前 be41443 原业务代码复现同样失败；详见 [完整证据与范围](chat_bottom_settlement_fix.md)。生产入口迁入统一运行时的整体任务仍未完成。

## 生产入站接入与压测契约修复（第五批，2026-09-23）

已将生产 ImMailboxRouter 改为 RuntimeEffectScheduler 的适配层，删除 _ImMailbox 和 _QueuedEvent 两套旧队列实现。SDK 实时入站、持久 Inbox 入站及恢复现在按账号和规范会话 ID 共用 FIFO；消息命名空间与 urgent/history 标签不再拆出并行写入者，也不再让同会话后来的事件越过先到事件。不同会话轮转共享工作池。

超时仅结束调用者的等待，实际执行仍占用会话和工作槽，直到原 Future 完成。drain 等待实际完成与尚在准入的事件。调度队列容量耗尽时，适配层按调用顺序等待容量，不把已提交的 SDK 消息转入有限重试缓存。运行时队列与并发有上限；不等待 dispatch 的生产者仍可能保留大量待准入 Future/SDK 对象，此项不能宣传成整个进程内存已有硬上限。

RuntimeIngressProcessor 已接入 ConversationSyncService._handleMessageIngress 的持久 Inbox 路径：元数据处理、刷盘、metadataCommitted 检查点、发送身份采纳、消息列表发布、projectionPublished、Outbox 完成、Inbox 完成依序执行。账号、SDK 代次与租约所有权在各阶段间检查；心跳更新对象但不变更 owner/token 时继续有效。失败保留最后一个持久检查点，真实 SQLite 重开测试覆盖恢复不重复发布。SDK 实时快速路径仍以 SDK 历史恢复为依据；本批没有为它复制持久正文。

万条集成测试的持久正文预期已修正为现有契约的 0。依据不是当前失败值，而是原有 HistoryWindowStore 万条测试与 appendDeferred 实现均明确只保存身份和计数。仍保留内存热正文 120 条、原始窗口 600 条、10000 条计数与迟到消息水位检查，并新增关闭/重开数据库后身份计数不丢失的验证。

验证记录（D:/CodexRuntimeTests/unified-chat-runtime-20260922/）：

- 原生产队列新增 5 项行为复现：迁移前全部失败（ingress-order-before.log），迁移后全部通过。
- 增加容量为 1 的 1000 条投递验证、万条即时完成让出 UI、关闭后真实排空、阶段失败与恢复，共 24 项新增行为测试。
- 18 套运行时、IM、Outbox、SQLite、SDK 和生命周期合并验证：175 项通过（runtime-production-combined.log）。
- 两套完整历史存储/真实入站验证：56 项通过，包含两个万条场景（body-contract-complete.log）。
- 原 12 套回底/未读页面回归再次验证：165 项通过（runtime-bottom-regressions.log）。
- 合计 396 项通过。重写/新增调度模块及测试严格分析无问题；同步服务分析无 error/warning，有 9 项既有大括号风格提示。

### 整体迁移仍需完成

本批使运行时调度器真正接入了生产入站和恢复，但没有宣称完成全量迁移：

| 范围 | 当前状态 |
| --- | --- |
| 生产入站/恢复队列 | 已由统一运行时执行，旧队列实现已删除 |
| 持久 Inbox 提交阶段 | 已统一执行顺序；仍使用既有业务存储和检查点 |
| AccountRuntimeSupervisor / RuntimeCommitCoordinator | actor 仍为 shadow；新持久提交适配器仍未接管生产业务权威 |
| 清空、变更、deferred、读取权威同事务 | 未迁入同一 MessageCore 提交域 |
| 每页面 RuntimeViewSession | 未替换现有页面状态所有者；现有回底修复保持通过 |
| 发送、附件、资料、权限、草稿和后台效果 | 未全量迁入新效果意图/恢复策略 |
| 新旧版本兼容范围 | 已确认新旧版本须在同一设备共用本地数据库目录并同时写同一账号；待提供旧版版本/提交及是否允许兼容协议补丁 |

元数据业务内部仍有自己的预览发布逻辑；阶段执行器保证的是 _publishMessageIngressProjection 在检查点后执行，不能把它描述为全部 UI 状态已与数据库原子提交。

兼容约束：不能直接迁走权威表并撤销旧写入权。未修改的旧版不认识新运行时的租约和提交入口。全量切换必须先验证旧版写入协议，不能把单独更新新版描述为已经约束全部旧写入者。
