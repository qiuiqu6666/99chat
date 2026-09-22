# 聊天统一调度：实施状态

基线：c5008765a84faf765b8f6b47bd7c878980ad71e7
分支：codex/unified-chat-runtime-core

## 当前交付范围

已实现可测试的运行时基础层。当前只有 shadow 构造入口，尚未连接生产消息流、持久数据库或页面；现有 MessageReconciliationWriter 继续持有业务写入权。本次交付不等于完成统一调度迁移，也不代表现有聊天问题已经根治。

| 模块 | 已实现行为 |
| --- | --- |
| RuntimeDocument / RuntimeEnvelope | 深层不可变数据、账号与 SDK 代次、会话、清空代次、事件和操作标识、可选页面及版本依赖 |
| AccountRuntimeSupervisor / ConversationActor | 每会话 FIFO，短批次让出事件循环，重复事件去重，账号/清空/页面/修订准入，失败不提交 |
| RuntimeEffectScheduler | 限制并发、每通道 FIFO、通道轮转、显式等价请求合并、显式过载、保留已发出操作的迟到结果 |
| RuntimeViewSession | 每次页面访问独立状态、有限回最新目标、窗口与布局证明、读取确认仅覆盖证明与捕获集合的交集 |

基础层在 third_party/tencent_cloud_chat_uikit/lib/business_logic/runtime/，不依赖 Flutter、腾讯 SDK 或宿主业务服务。EffectScheduler 的执行端口目前仅由测试调用，shadow runtime 只返回效果意图。

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

## 后续迁移门槛

1. 完成基线与性能测量；修复现有门禁自身的问题。
2. 在 MessageCoreStore 内设计并实现原子提交、事件去重和效果意图持久化，验证中断恢复。将需要同事务生效的清空、变更、deferred 和读取权威迁入同一提交域，旧 HistoryWindowStore 降为可重建缓存。
3. 实时、历史、搜索、删除、撤回、清空按完整会话状态域接入；切换时撤销旧写入权，禁止分支双写。
4. 将页面的搜索/回最新/布局/滚动/可见性确认接入独立 ViewSession，逐项消除上述 13 项失败。
5. 发送、附件和恢复接入效果策略；保留 Outbox 身份和 unknown 状态，禁止无证据自动重发。
6. 接入资料、权限、草稿与后台恢复，删除分散的旧写入入口和计时器。
7. 执行完整行为、崩溃恢复、多页面与性能验收后，才能认定整体完成。

## 图分析范围

本工作树单独注册为 99chat-runtime，索引位于 D:\CodexRuntimeIndexes\unified-chat-runtime-20260922，避免原工作区并发改动和系统盘空间不足影响分析。

默认文件大小范围能够覆盖本次所有新增核心与测试。将范围扩到 2048 KB 后，压缩 Web SDK 解析超时；该次索引没有作为编辑依据。现有超大聊天文件的影响分析仍未闭合，默认索引不能用来批准其生产写入切换。后续必须明确处理 SDK 产物的索引策略并核验超大业务文件，不能把 UNKNOWN 或未解析调用视为没有影响。

索引的全局流程枚举存在截断；本次另行查询具体改动符号，并核对实际调用点。新模块目前只有新增测试引用，没有生产入口。
