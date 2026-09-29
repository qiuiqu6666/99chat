# 聊天已读后底部 Tab 残留未读：链路检查与修复

检查日期：2026-09-25。已通过自动化测试复现并修复客户端状态一致性问题；尚未在反馈用户的手机上验证，也未发布安装包。

**结论**

本地已读、SDK 已读确认、SDK 会话快照和 Tab 汇总是异步进行的。旧快照在本地清零之后到达时，部分入口绕过已读锚点，重新采用旧的未读数。SDK-primary 模式下，本地会话镜像可能没有对应消息，后续落库调用还会覆盖刚记录的已读锚点。两者叠加，造成读完后角标再次出现。

截图中的“正在连接”与这种时序相符，但截图不能证明当时的网络错误码或 SDK 回执顺序。确定结论来自源码链路和可控时序测试。

**检查的完整链路**

| 阶段 | 代码入口 | 检查结果 |
| --- | --- | --- |
| 点击聊天 | conversation.dart → clearLocalForOpenFast | 同帧清本地未读，记录本次读取目标，异步持久化与上报 |
| 本地清零 | ChatSessionController.zeroUnreadLocallyMany → ConversationTabStore.zeroUnreadLocallyMany | 会话行和汇总都参与清零，单纯再次通知 UI 不能解决后来的旧数据回写 |
| 已读目标 | ConversationLocalStore.recordReadClearedAnchor | 原先可能被无消息快照的后续调用覆盖；现保留同一读取目标的消息 ID、时间和群序号 |
| SDK 上报 | ConversationReadOutboxStore → scheduleSdkUnreadClean → TencentConversationReadService.cleanUnread | 使用持久化的有限读取范围；重连时 recoverPendingReadOutbox 重试 |
| SDK 实时会话 | ConversationSyncService → ChatSessionController.applyPendingRealtimeProjection | 同时进入独立汇总与列表队列，原先并非所有路径都会检查已读锚点 |
| SDK 会话分页 | ConversationTabStore._loadOnce / restoreSdkConversationsByIds | 显式未读字段原先可绕过普通合并守卫；已补齐共享入口检查 |
| 独立未读校准 | ConversationUnreadAggregate._refreshFromSdk | 不依赖列表已加载窗口；原先保存未读数却丢弃消息身份，无法识别旧已读快照 |
| 底部显示 | ConversationScopeUnreadBadge → AppBadgeUnreadUtils.visibleUnreadForC2c / visibleUnreadForGroup | Tab 读取按类型汇总，不直接读取 sdkTotalUnreadCount；只清 SDK 总数无法修复此问题 |

**本次修复**

1. 汇总保留轻量的消息身份与顺序信息，实时输入和独立分页校准都按已读锚点处理。分页结果在发布时重新检查，防止等待期间发生的已读操作被覆盖。
2. 进聊天时直接从 SDK 会话快照捕获完整锚点。无快照的后续落库、相同 ID 的重复调用，保留原有锚点信息。
3. SDK-primary 列表入口同样检查已读锚点，带消息身份的显式未读字段仍需经过顺序判定。
4. 旧消息的迟到已读回执不能清除后来到达的新未读。同秒 C2C 消息用已读消息身份辅助判断；比较锚点不随旧快照倒退。
5. 明确区分原始 SDK 回调与列表已经处理好的本地变更，保留正常删除消息后的预览回退。只带数量、不带消息内容的 SDK 已读确认，也可清掉列表外会话的未读。

**未扩大 SDK 清未读范围**

现有 C2C 清理策略使用保守的秒级时间边界，群聊使用序号。SDK 确认和本地可见状态不一定同一时刻达到零。这次让本地显示尊重已确认的读取目标，没有改成无边界清空整段会话。不同消息即使同秒到达，仍保留其有效未读。

群聊 Tab 另外计入未静音的群通知；消息 Tab 不包含群通知。归档、免打扰、退出群和其他会话的未读仍沿用原有计数规则。

**验证证据**

- 新增 conversation_read_tab_consistency_test.dart，共 17 项回归：实时旧回放、独立校准、窗口外未读、分页中读取、空镜像锚点、群序号、同秒 C2C、新消息后迟到已读、真实角标组件、账号切换、删除预览回退和无消息内容的 SDK 确认。
- 修复前，首批 9 项中有 7 项失败：Tab 期望 2 实际 3、锚点消息 ID 变空、消息时间变 0、角标“1”再次出现。另两项迟到回执测试复现了新未读被错误清零。
- 主链路回归：13 个测试文件、175 项通过，日志 read-tab-final-tests.log。
- 最后的补充验证：一致性测试和 SDK 来源测试共 29 项通过，日志 read-tab-sdk-ack-tests.log；其中包括新增的无消息内容确认场景。两次执行有重复用例，不将执行次数相加冒充独立测试数。
- 新的汇总、守卫和回归文件静态分析无问题。检查全部相关文件时无错误；保留 3 个原有 warning 和 12 个原有格式提示，详见 read-tab-final-analysis.log。
- 修改文件的 git diff --check 通过。

**影响分析与范围**

绑定 GitNexus 仓库 99chat-ios-actions-precommit，路径为当前工作区。索引时间 2026-09-25T11:37:25Z，基线提交 02d627633d6fa5e96eedf24d09de2b8edf1c9a8d，与 HEAD 一致；未提交改动通过实际源码核对。

进聊天的两个清未读入口影响评级为 HIGH，已在修改前说明；合并入口为 MEDIUM，其余已解析方法为 LOW。图中未解析到调用者的入口通过文本和实际调用代码补查，没有把 UNKNOWN 当作低风险。图未提供这部分 Dart 链路的完整 process，报告链路以源码核对为准。

保留工作区其他任务的既有改动。没有提交、发布或修改用户线上数据。
