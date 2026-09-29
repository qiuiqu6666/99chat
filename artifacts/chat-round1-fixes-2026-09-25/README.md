# 聊天全链路检查：第一轮修复与验证

日期：2026-09-25。工作基线：`codex/gallery-chat-order`，HEAD `26bcc02c68680725c1a91bf7548535c0645687a0`。

本轮已经落地 F1 草稿版本贯通、F2 发送结果仲裁贯通、Profile 首屏证据三项变更。没有调整窗口大小、缓存容量、并发预算或自动重发策略；没有新增数据库、发送协调器或持久化状态枚举。SDK 仍是草稿权威源，SQLite 仍是镜像。

**验收结论：第一轮定向回归通过；不能据此宣布全链路达到高稳定性，也没有得出真实性能改善的结论。** 后续发送接纳与强杀恢复、F4/F5/F6、跨端恢复和后端联调仍需独立验收。

## 交付物与修改边界

三个补丁已经应用在当前工作区；它们是供审阅或在相同基线上重放的增量，**不要再次应用到当前工作区**：

| 补丁 | 范围 |
| --- | --- |
| `01-f1-draft.patch` | 输入提交快照、生命周期钩子、页面版本、草稿服务与回归 |
| `02-f2-outbox.patch` | Outbox 裁决、协调器、消息行/预览回调/失败清理入口与回归 |
| `03-profile-trace.patch` | 入口、共享读取、底层 SDK 调用、日志与回归 |

`review-manifest.json` 记录每个文件的前后 SHA-256、所属补丁和原始快照。三个补丁的反向 `git apply --check` 均通过，`git diff --check` 通过。未提交 Git commit，未发布。保留了任务开始前的工作区改动；已捕获的其他基线文件没有出现额外变更。

上一轮材料仍保留在 `artifacts/chat-full-chain-audit-2026-09-25/chat-full-chain-audit.md` 和 `artifacts/chat-evidence-ab-2026-09-25/`，本报告不替代其中的未解决问题清单。

## F1：从输入框到 SDK、镜像的版本归属

新的调用顺序为：

```text
用户输入 → 服务立即登记编辑版本 → 页面防抖保存
点击发送 → 清空前捕获提交快照 → 调用原发送链路
         → 归属于该提交的输入清空 → 条件保存空草稿
发送结果 → 校验提交快照 → 校验当前服务令牌 → 页面队列
         → 服务队列出队校验 → SDK 写入 → 再校验 → 镜像/会话投影
```

关键变化：

1. `ChatDraftSubmission` 使用不复用的编辑会话对象、编辑 revision、提交内容及持久化令牌。相同文字的两次输入也是不同编辑；页面重建后的 revision 从零开始不会碰撞旧页面的令牌。
2. UIKit 的文本、回复和 @ 消息发送，在清空输入框之前捕获快照。新增可选的 `textWillSubmit`、`textDidClearAfterSubmit`、`textDidSubmit` 钩子。通用媒体发送完成不再清理当前文本草稿。
3. 页面在真正执行排队任务前检查服务令牌，避免旧任务先改页面文本再被 SDK 层拒绝。用户输入 B 后，A 的成功回调不能取消 B 的防抖、设置抑制离页保存标志或清除 B。
4. 服务令牌绑定账号、现有登录 generation、规范化 SDK 会话 ID 和编辑版本；SDK 调用前、调用返回后、镜像提交时均进行相应检查。同账号重新登录也受 generation 隔离。
5. 新页面接管尚未写入 SDK 的编辑时保留待保存内容，并在当前令牌下重新排队。异步加载不能覆盖更新后的编辑。
6. SDK 写入失败不会确认镜像；SDK 成功但镜像失败使用单独的异常/待修复标记，后续加载从 SDK 读取并修复镜像，不拿旧镜像反向覆盖 SDK。

**已验证的反例（10 项正式测试）**包括 A 成功迟到而 B 仍需防抖/离页保存、相同文本再次输入、旧页面/旧编辑、队列执行前版本变化、SDK 在途时新编辑、账号 generation 变化、SDK 与镜像部分成功，以及离页再进入恢复 B。

边界：这些编辑令牌是进程内能力，不是跨进程的草稿日志。本轮没有新增 SDK 应用租户选择；作用域沿用当前固定 SDK 实例与登录 generation。进程被杀时尚未持久化的唯一提交内容能否恢复，仍属于第二轮的发送接纳/崩溃一致性验收。

## F2：以持久化裁决驱动发送展示

新的数据流为：

```text
SDK 结果 / 实时自发消息 / 历史补偿
    → 现有 Im05Persistence 事务
    → decision + 当前主记录/恢复副本 + 持久化 revision
    → ImCoordinatedSendResult 的当前结果视图
    → 消息行、完成回调、会话预览触发、重试资格
```

`ImOutboxResultVerdict` 包含本次事件的裁决、当前主记录、恢复副本、事件尝试 ID、当前状态、`stateVersion`、`canRetry` 和原因。操作身份、账号/会话、SDK/server 消息身份随原有主记录交付。`stateVersion` 复用恢复副本的持久化 `recoveryRevision`，没有新增数据库字段。

| 情况 | 现在的处理 |
| --- | --- |
| acknowledged/completed 后迟到失败 | 返回 superseded 与当前成功状态；不把幂等布尔值当成采纳失败 |
| 失败裁决已形成，投影前 provider 成功提交 | 活跃结果视图按持久化版本更新，下游读取成功结果 |
| 旧尝试失败 | 拒绝该事件；当前操作的真实状态和重试资格不被旧事件改写 |
| 同一操作的旧尝试获得精确 provider 成功证据 | 可以确认该操作成功，不以当前 attempt 不同为由丢弃 |
| outcomeUnknown 后普通迟到回调 | 保持待核对；只有符合当前契约的精确 provider 证据进入成功补偿 |
| SDK 成功、本地结果事务失败 | 保留成功证据，标记本地状态待修复，不显示失败并鼓励重发 |
| SDK 失败但本地事务失败 | 保持待核对，不将未经提交的失败开放为重试 |
| 已删除/撤回后迟到成功 | 可补全发送记录，但消息行和完成预览回调均拒绝复活正文 |
| 同步分配了 msgID，但尚无成功状态 | msgID 非空不被当成成功证明，真实失败仍可展示 |
| 发送前发现操作已经完成 | 拒绝重复 dispatch，同时向下游交付已确认结果 |
| 卡住消息的超时清理 | 对已存在的 Outbox 操作只读取裁决，计时器不制造 SDK 失败 |

精确 provider 证据必须匹配 owner、operation、correlation、会话和 payload 身份；生产入口还要求自发消息、发送者与 owner 一致以及非空服务端消息 ID。文本相同或时间相近不用于确认发送成功。

两个结果记录在同一事务中更新。任一 CAS 失败抛错触发回滚，避免只提交其中一份。实时快速路径没有被改成必须先写 Inbox；provider 补偿沿用现有协调器，在快速投影后异步核对。

结果视图按存储实例、owner、operation 隔离，并以弱引用保留活跃消费者；它不是第二套持久化状态机。重启后从原有主记录与恢复副本重新读取状态。发送前和 UI 完成发布前均检查当前账号代次。

**已验证的 15 项正式测试**包含 acknowledged/completed 迟到失败、裁决形成后的新成功、旧尝试、未知结果、放弃后成功、精确身份冲突、SDK 与持久化部分成功、消息行成功保护、删除/撤回与预览回调保护，以及真实 SQLite 故障注入与关闭重开。

SQLite 测试使用触发器让主记录成功更新失败，断言主记录、恢复副本、revision 一起回滚；解除故障后提交成功，再关闭重开数据库检查版本和 attempt 保留。这证明的是应用事务与重开行为，不能替代断电、磁盘满、迁移或真实 SDK 故障演练。

兼容边界：没有定位到 Outbox 的旧消息仍保留原有 UI 兜底；本轮没有声称所有历史版本遗留消息已迁移到统一发送契约。跨实例、跨进程长期状态追平仍依赖现有恢复路径，不能由进程内结果视图单独保证。

## Profile：能解释等待，不先调参数

启用方式：

```powershell
flutter run --profile -d <真实设备ID> --dart-define=CHAT_OPEN_PROFILE=true --dart-define=CHAT_OPEN_PERF_CONSOLE=true
```

Profile 产生 `[ChatOpenPerf]` 记录及 Dart Timeline 事件/异步阶段。Release 不启用。需要减少控制台干扰时设置 `CHAT_OPEN_PERF_CONSOLE=false`，用 DevTools Timeline 采集；最终性能对比应记录该开关，保持 A/B 一致。

| 记录 | 应怎样解释 |
| --- | --- |
| `session_begin`、`route_requested`、`route_reused`、`route_push` | 区分本次入口和路由复用；列表传递同一 trace，通用路由入口默认 source=route |
| `span_start` / `span_end` | `queueWaitUs` 是登记至开始，`executionUs` 是开始至结束，`totalUs` 为两者之和 |
| `hydrate_producer` | 一个共享 hydrate 的实际生产任务；调用方超时不结束此任务的计时 |
| `local_snapshot_wait` | 一次快照请求的等待，可能复用其他请求，不能当作一次 SDK 调用 |
| `history_loader_reused` | 复用 loader Future，没有新增该请求的 SDK 读取 |
| `sdk_local_call` / `sdk_cloud_call` | PeekLoader 内每次实际调用 MessageService 的记录；分页、云读取和诊断读取分别计数 |
| `source=coverage_diagnostic` | 现有云读取后的额外本地诊断读取，不能与前台必需读取混算 |
| `local_history_filter`、`local_read_result` | 去重/清空边界过滤的耗时与过滤前后数量 |
| 原有 prepare/commit/ignore/generation/window 记录 | 判断窗口归属、提交或丢弃理由，不能仅按 prepare 数量推断读取次数 |
| 原有 `messages_first_visible` | Flutter 层消息可见里程碑；不是 GPU 完成或屏幕实际发光时间 |

每次打开使用唯一 trace；异步任务和嵌套阶段保留创建时的 trace。不同会话没有合适账本时使用 detached 上下文，不借用另一会话。内容、token、签名、URL、错误正文等敏感字段不写入新增性能日志，标识符使用摘要。

计数范围明确限定在已接入的首屏/PeekLoader 链路；这些日志不能冒充 SDK 内部数据库、网络重试或全 App 所有读取的总账。通用路由的 source 默认只表示 route，可由调用者提供更具体的入口名称。

新增 8 项日志测试，特别验证了“两个请求共享一次底层调用”和“一个请求分页调用三次”。当前没有采集真实移动设备 Profile 的 P50/P95/P99、FrameTiming 或冷暖缓存对比。设备清单见 `devices.json`，其中 Android 目标为 `emulator-5554`、android-x64、无硬件渲染，不能据此作为代表性真机性能样本。

## 验证结果与仍然失败的旧断言

| 验证 | 结果 | 原始证据 |
| --- | --- | --- |
| 修改前原 F1/F2 探针 | 两个反例均失败，确认基线缺陷 | `baseline-regressions.jsonl` |
| 最终定向综合测试 | 118 通过，0 失败 | `round1-focused-final.jsonl` |
| 启用 Profile 编译开关的日志测试 | 15 通过，0 失败；执行环境仍是 flutter test | `profile-flag-tests.jsonl` |
| 额外旧回归集合 | 33 通过，2 失败 | `legacy-suite-final.jsonl` |
| 核心改动与新测试静态分析 | 0 error、0 warning，2 个既有 info | `final-core-analyze.log` |
| 页面静态分析 | 无编译错误，仍有既有 warning/info；未批量清理 | `profile-initial-analyze.log` |
| 工作区差异及补丁校验 | 通过 | `diff-check.log`、三个 patch |

F1 原探针调用旧的无参数 `markSendCompleted()`；生产异步路径现在必须传提交快照。正式回归已改为模拟捕获快照、发送清空、输入 B、A 完成和再进入，而非把旧探针的无参数调用改成假成功。F2 原 UI 降级反例也进入正式测试。

剩余两个旧失败没有隐藏或跳过：

1. `chat_reliability_regression_test.dart` 的 `durable read queues use bounded retry and dead-letter retention`：要求 read outbox 含 `maxRetryAttempts = 10`，修改前 HEAD 就不满足，且本轮未改该文件。它仍对应第二轮 F6，不能用本轮通过结果覆盖。
2. `chat_page_controllers_test.dart` 的 `extracted enums record and media states expose expected values`：期望 6 个 RecordInputState，实际 11 个；枚举源文件与修改前 HEAD 相同。属于旧断言与现有枚举不一致，未顺便改业务枚举。

输入法测试曾因本轮格式化换行导致精确字符串失配，已将该断言改为忽略空白并通过。路由 widget 测试已清理本次新增日志计时器，仍验证复用 Future 只在真实 pop 后完成。

`validation-summary.json` 汇总测试名称、失败证据及基线比对；测试数量不把多个重跑相加当作独立用例。

## 下一轮验收入口

本轮维持原定顺序：先处理 F4/F5/F6 与“发送已持久化接纳”边界，再执行杀进程、断网、凭据过期、磁盘故障、同账号重登、跨端及升级恢复演练。后端幂等、附件续传、迁移中断、断电持久性、离线撤回/删除追平仍待单独验证。Web 的既有 F3 构建边界也没有被移动端测试覆盖。

性能参数调整应等真实 Profile 样本：记录设备/系统/App 版本、入口、冷暖状态、缓存规模、窗口版本、实际读取次数、阶段排队/执行耗时、首条可见时间及长尾分布。并行阶段不能相加成首屏阻塞时间，超时预算也不能当作已实测耗时。

## 图谱检查的结果与能力边界

修改前执行了 GitNexus impact，HIGH/CRITICAL 范围已在操作时说明，涉及发送结果投影、生命周期钩子、日志上下文和共享历史读取。UNKNOWN 结果通过源代码与调用点核对，没有把空调用集当成未使用。

最终图谱包含 78,976 nodes、181,464 edges、656 个已枚举 flows。`detect_changes(scope: all)` 的结构化结果为 **51 个改动文件、211 个变化符号、2 个已识别受影响流程，汇总 risk=medium**；211 个符号全部返回，没有 partial/truncated 标记。该范围包含工作区原有业务改动，并非本轮 23 个文件的独立风险等级；不能用这个汇总覆盖各方法修改前的 HIGH/CRITICAL 警告。

图谱生成日志同时明确报告流程候选与分支的枚举上限、Dart 动态调用和跨语言字段解析缺口。因此“仅返回 2 个受影响流程”不等于聊天链路没有影响，最终依据还包括源代码复核和行为测试。

此外，最后刷新时 `Typedef.typedef_fts` 全文索引构建失败，执行一次 `analyze --repair-fts` 后仍未恢复。图存储与结构化变化分析可用，关键词/BM25 搜索处于降级状态。本轮没有依赖该降级搜索得出无影响结论，也没有为修工具而反复重建应用代码。证据见 `index-final-refresh-3.log`、`index-fts-repair.log`、`graph/detect-changes-structured.json`。
