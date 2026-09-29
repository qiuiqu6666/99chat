# 聊天页面稳定性修复记录

日期：2026-09-28。基线：`0e7aa83bc5b096a99ff8bb424842404a3c901cb7`。

本次已修改代码，重点消除一次局部失败后持续占用状态的路径。没有连接手机或真实腾讯云账号，不能据此宣称所有线上随机现象已被完全复现或消除。

## 已确认的问题与处理

| 路径 | 原有问题 | 修复后的行为 |
| --- | --- | --- |
| 会话初始化 | 别名消息窗口迁移的异步读取先于初始化完成；同一模型再次初始化可能交错。已初始化模型切换会话直接返回。 | 当前会话、分页代次及监听绑定在磁盘等待前完成；异步迁移有期限和会话校验；切换后旧结果不能接管新页面。 |
| 历史分页 | loading 标记设置后，清空 epoch 同步位于 try/finally 外；异常或永不返回会留下分页锁。 | 将前置读取纳入异常处理；关键异步步骤设 20 秒期限；finally 释放本次标记；旧代次不能释放新代次的锁。 |
| 分页优先级 | 同一会话的优先级仅用集合保存，旧请求结束可能清除新请求的优先级。 | 每个请求持有独立 token，只能释放自己的优先级。 |
| 首屏显示 | 初始化失败可能抛出未处理的异步异常；空窗或揭示门槛失败缺少恢复入口。 | 保留消息列表；12 秒仍不能显示时提供“重新加载”；已有内容可解除首屏隐藏；重试失败或 25 秒超时后按钮恢复可点。 |
| 撤回 | 菜单可携带旧对象或本地别名；准备写入失败没有统一恢复；会话失效后的补偿分支原先仍可能继续调用 SDK。 | 重新查找当前权威消息、采用 SDK msgID；准备失败可再次操作；失效会话补偿后立即结束；SDK 等待有期限。 |
| 撤回落盘 | SDK 已接受后，本地确认或回滚读取一次失败可能留下长期待处理投影。 | 仅重试幂等的本地确认/补偿，不自动重复发送撤回命令；SDK 超时后的迟到成功仍在原账号归属有效时修正状态。 |
| SDK 监听器 | 注册/移除一直 pending，会阻塞后续监听恢复与生命周期操作；旧监听回调缺少实例归属判断。 | 注册和移除设 10 秒期限；注销立即使旧回调失效；迟到注册只移除自己的旧实例；现有服务重试机制可重新注册。 |
| 滚动过渡层 | 若调用方未提供截止时间，也未调用 finish，保留画面及 AbsorbPointer 可持续拦截触摸。 | 默认最多保留 25 秒；结束等待 layout 最多 1 秒；到期释放遮挡并记录事件。 |
| 新消息/底部入口 | 未成功定位也会直接清零本地胶囊计数；UI 未等待的滚动操作可能向外抛错。 | 清零交由实际滚动与可见性确认；失败保留入口。保留原有“加载窗口→布局→定位→目标可见/底部确认”及有期限重试机制，增加点击/失败/结束日志。 |

## 主要代码

- `third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart`：会话初始化、首屏加载、撤回与补偿。
- `third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_history_pagination_load.dart`、`controllers/history_pagination_controller.dart`：分页期限、释放与代次隔离。
- `third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_bounded_history.dart`：准备写入授权期限及本地完成重试。
- `lib/src/services/im/tencent_advanced_message_adapter.dart`、`lib/src/services/conversation_local/conversation_sync_service.dart`：SDK 监听生命周期。
- `lib/src/services/conversation_history_sync_coordinator.dart`：请求独立的分页优先级 token。
- `third_party/tencent_cloud_chat_uikit/lib/ui/widgets/chat_history_window_transition.dart`、`chat_history_recovery_notice.dart`：过渡层释放、可重复重试入口。
- 消息列表、底部胶囊、消息菜单和聊天 Provider：恢复接线、日志及异常收敛。

## 关键链路日志

新增 `ChatRecoveryTrace`：输出 `[ChatRecovery]`，不受本工具类内的 debug 模式开关限制；包含 UTC 时间、conversation、operation 和 message 标识。内存保留最近 200 条。不得传入正文、附件链接、凭据或完整 SDK payload。

撤回正常链路：

```text
revoke_clicked
  conv / op / msg / localID / status / admin / staleObject / generation / disposed
→ revoke_local_published（本地乐观发布，writerCommitted）
→ revoke_sdk_call
→ revoke_sdk_result（code / message）
→ revoke_finished（sdkAccepted）
```

消息列表收到乐观状态时另有 `revoke_message_list_updated → revoke_ui_frame`。本地乐观刷新可能发生在 SDK 返回前，不能仅凭刷新日志判断 SDK 已接受。`revoke_ui_frame` 代表该列表构建后的帧完成，并记录 revealed；不代表屏幕外的气泡一定已绘制。

异常分支包括 `revoke_prepare_failed`、`revoke_stale_cancelled`、`revoke_failed`（stage / sdkAccepted）、`revoke_sdk_late_result`、`revoke_preview_failed`、`mutation_completion_retry`、`mutation_projection_retry`。

其他关键事件：

- 会话：`visit_initialized`、`visit_alias_failed`、`hydrate_failed`。
- 分页：`history_failed`、`history_released`，记录阶段、代次有效性与剩余 loading 状态。
- 列表恢复：`window_not_visible`、`window_retry`、`window_retry_failed`。
- 遮挡释放：`viewport_transition_expired`。
- 返回底部：`return_clicked`、`return_failed`、`return_finished`，包含目标到达及消息实际装载证明。
- 监听器：`message_listener_attached`、`message_listener_attach_failed`。

## 验证结果

- 新增 17 项故障注入测试：全部通过；覆盖初始化交错、前置读取抛错/悬挂、旧会话迟到、生命周期回调悬挂、撤回准备失败/超时、SDK 超时后迟到成功、落盘重试、过渡层释放、恢复按钮再点击、监听注册/注销与迟到回调。
- 加上 3 项现有监听生命周期约定测试，最终针对性验证 **20/20 通过**：`final-fault-injection.log`。
- 30 个测试文件联合回归 **266 通过、6 失败**：`final-regression.log`。包含真实 SQLite 消息窗口、300 条到达跨窗口裁剪、持续拖动、未读计数与目标渲染证明。
- 剩余 6 项全部在修改前代码上单独复现：`baseline-existing-failures.log`，不是本次新增失败。分别涉及 return-latest 提前确认计数、窗口预算旧值、页面源码标记、胶囊源码断言、持久已读队列旧常量、媒体枚举数量。
- 已更新一项旧测试：会话初始化现在必须清除旧分页锁，不再断言保留该锁；另一项源码定位断言适配可等待的初始化签名。
- 同一批故障测试在原实现上出现 13 次失败；另有注销等待悬挂，测试进程 90 秒后终止并恢复代码：`baseline-fault-injection.log`。这是可复现的失败路径证据，不是真机所有随机症状的完整复现。
- 静态检查使用主应用的包解析配置：**0 error、93 warning、297 info**，退出码 2，不能标成全绿。UIKit 自身缓存的包配置缺少主应用入口，会产生额外路径错误；检查时临时对齐，之后已恢复生成配置，没有改依赖锁文件。
- `git diff --check` 通过。

## 影响与边界

编辑前已执行 GitNexus impact。共享初始化/消息模型属于 HIGH/CRITICAL 风险范围，已按共享链路安排回归。部分 Dart UI/扩展符号图查询为 UNKNOWN，另外核对了源码调用点，没有把空调用集当作安全证明。最终 `detect_changes(scope: all)` 返回 38 个变更符号、310 个受影响流程、risk=critical，未返回 partial/truncated；新增文件和静态图未解析的动态调用仍需依靠源码检查与运行测试。

保留工作区原有 `pubspec.lock` 变更；没有提交、推送或打包发布。

测试中 C 盘空间不足阻止了一次测试产物复制。后续测试临时目录转至 D 盘；本次两组废弃测试临时文件也保留移至 `D:/codex-task-cache/chat-session-recovery-20260928/`。自动审批拒绝删除，因此采用保留文件的移动方式。

上线前仍需 Android/iOS 真机验证：弱网/断网恢复、后台切前台、连续进退单聊/群聊、长时间滚动和媒体高度变化、SDK 实际错误码与长时间不回调。本次期限会解除 UI/操作占用，但不等于取消原生 SDK 或 SQLite 内部调用；迟到结果由归属校验或补偿处理。永久存储故障仍需平台恢复，不能通过跳过数据一致性校验来伪造成功。
