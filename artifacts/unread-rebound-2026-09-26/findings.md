# 新消息到来后旧未读数恢复：检查结果

检查日期：2026-09-26。当前工作区 HEAD 为 `c25b083f63e6d8c2687ef3625b2089af8a57f659`，版本 `3.0.1+18`。

后续用户确认：**iPhone 真机 3.0.1+18，单聊和群聊均异常；正常的是电脑上的安卓模拟器。**两者不是同一平台对照。新增离页顺序检查见 [iOS 补充检查](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/unread-rebound-2026-09-26/ios-followup.md>)：已复现客户端离页目标冲突；尚未取得 iPhone 的原生请求结果和回调顺序，不能将模拟测试当作真机根因已经确认。

已通过真实客户端列表/汇总代码加模拟 SDK 会话回调复现。业务代码未修改；本次新增诊断用例、执行日志和本报告。没有连接真实账号、调用线上清未读接口或验证用户手机上的安装包。

**结论**

本地已读保护只判断 SDK 快照的最后一条消息是否已经读过，并没有把 SDK 未读总数拆分成“已读残留”和“本次新到”。新消息一到，旧保护被解除，整个 SDK 累计未读数重新进入列表及底部汇总。因此，进入聊天后清零的旧数量可以在下一条新消息到来时再次出现。

单聊还存在一个稳定的残留来源：上报 SDK 的已读时间是最后一条已读消息时间 T 减一秒，SDK 端时间为 T 的旧消息未被这次清理覆盖。这一策略用于保护同秒未看到的新消息，但当前实现没有配套处理留下的旧未读。

**完整触发链**

| 阶段 | 现有行为 | 后果 |
| --- | --- | --- |
| 点击会话 | `conversation.dart:3302` 调用 `clearLocalForOpenFast` | 本地列表与汇总先清零 |
| 记录已读 | `conversation_unread_clear_service.dart:675` 记录消息 ID、原始时间和群序号 | 旧消息的相同快照可以被拦住 |
| 上报 SDK | `_watermarkFor:204` 使用 `conservativeTimestamp`，后者返回 T−1 | 单聊最后一秒的已读消息可能留在 SDK 未读数中 |
| SDK 调用成功 | `_runSdkClean:1369` 记录成功并确认 outbox；`read_outbox_store.dart:255` 删除相应记录 | 这里只证明所提交范围的请求成功，没有证明完整的本地读取范围已清理 |
| 新消息回调 | `_createConversationListener:759` → `applyPendingRealtimeProjection:804` | 先更新独立汇总，再给列表排队 |
| 已读保护判定 | `conversation_local_store.dart:2505`，新时间/群序号前进就执行 `_clearReadCleared` | 保留 SDK 原始未读数，同时删除旧已读保护 |
| 同秒单聊 | `conversation_local_store.dart:2509`，不同消息 ID 同秒到达时保留保护，但直接保留 SDK 数量 | 即使保护未删除，累计数量仍包含旧残留 |
| 显示 | 汇总 `_resolveSdkUnread:131` 和列表 `mergePatchRow:1689` 都使用共享守卫 | 会话行与底部角标会一起变成错误数量 |

主要源码：

- [单聊已读范围](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/conversation_read_policy.dart:3>)
- [进聊天清零和记录锚点](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_unread_clear_service.dart:656>)
- [新消息导致保护解除](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_local_store.dart:2501>)
- [SDK 请求成功后的处理](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_unread_clear_service.dart:1369>)
- [列表与汇总分发](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat_session/chat_session_controller.dart:804>)

腾讯官方 Flutter 文档说明，单聊按指定时间戳及其之前清理；传 0 则清理整个会话。因此，代码传 T−1 时，时间为 T 的消息不在清理范围内。[腾讯官方说明](https://intl.cloud.tencent.com/zh/document/product/1047/48318)

**可复现示例**

1. 会话里有 5 条未读，最后消息为 M1、时间 T。
2. 打开聊天，本地显示 0，读取锚点记录为 M1/T。
3. 假设 5 条消息都在 T 秒，按 T−1 清理后，SDK 仍计为 5；或者 SDK 已读请求尚未完成，5 条都仍计入。
4. 返回列表，收到一条 M2。SDK 发来 `lastMessage=M2, unreadCount=6`。
5. 当前代码输出：会话行 6，底部汇总 6。应只显示新到的 1 条。

若原来的消息跨多个时间点且 SDK 清理成功，一般只会带回最后一秒内的残留；不能推断每次都会恢复全部历史未读。群聊使用群序号，没有单聊 T−1 的固定残留，但已读请求尚未确认时仍存在相同的累计值回写窗口。

自己发送的消息有单独分支，可以暂时保持 0；该分支仍没有拆分旧计数与后来新计数。本次测试验证了“迟到的自发消息会话快照 → 对方新消息回调”这一投影顺序，没有把它当作真实手机完整的输入、发送、退页测试。

另外核对了聊天内部的旧已读上报入口：`tui_chat_global_model.dart:10403` 的 `markMessageAsRead` 调用 `TencentConversationReadService.markRead` 时没有传 `explicitFullConversationClear=true`；后者在 `tencent_conversation_read_service.dart:34` 返回 `read_watermark_unavailable`，不会调用无边界清未读接口。因此不能假定聊天内部还有另一条隐式全清路径会消除上述残留。离页调度还有最近成功 3 秒内跳过的分支，快速返回也不意味着立即完成另一轮 SDK 清理。

**测试证据**

新诊断文件为 `reproduction_test.dart`。7 项中 2 项对照通过、5 项缺陷场景按预期失败：

| 场景 | 正确值 | 当前结果 |
| --- | --- | --- |
| 只有已读旧快照回放 | 行 0 / Tab 0 | 通过 |
| SDK 已正确清掉旧数，新消息回调为 1 | 行 1 / Tab 1 | 通过 |
| 单聊跨秒新消息，SDK 带入残留 | 行 1 / Tab 1 | 行 6 / Tab 6 |
| 单聊同秒不同消息 ID，SDK 带入残留 | 行 1 / Tab 1 | 行 6 / Tab 6 |
| 迟到的自发消息快照之后收到对方消息 | 行 1 / Tab 1 | 行 6 / Tab 6 |
| 群聊已读确认未完成时收到更大序号 | 行 1 / Tab 1 | 行 6 / Tab 6 |
| 独立 SDK 分页校准返回混合累计值 | Tab 1 | Tab 6 |

执行：`flutter test --no-pub --reporter expanded artifacts/unread-rebound-2026-09-26/reproduction_test.dart`。该文件放在诊断目录中，失败断言用于保留当前缺陷证据，不是已完成修复的回归结果。

诊断文件静态分析没有 error，报告 8 个 `invalid_use_of_visible_for_testing_member` warning：原因是文件特意保存在 `artifacts/` 而非 `test/`，分析器不将其视为测试目录，因而提示测试专用入口的使用。实际 Flutter 测试已成功编译并运行；上述 5 项失败均为数量断言失败。

另执行以下既有测试，共 54 项全部通过：

- `conversation_read_tab_consistency_test.dart`
- `conversation_unread_quick_return_test.dart`
- `conversation_unread_guard_test.dart`
- `conversation_unread_after_leave_test.dart`
- `round2_route_read_boundaries_test.dart`

已有测试中，新消息快照大多直接设置为 `unreadCount=1`，并且明确断言更新消息/群序号会移除 barrier。它们验证了旧快照不回灌、正常新消息可见，但未验证 SDK 累计值仍混有旧消息的情况。因此这些测试全部通过，不能排除本次问题。

**修复应满足的条件**

需要分别维护“用户确实读到了哪里”和“SDK 已确认清到了哪里”。后续消息到来不能被当成已读同步完成的证据；已读保护应保留足够信息，支持按消息身份/顺序区分旧残留和新未读。列表、持久化、SDK 分页及独立汇总必须使用相同的解析结果。

单聊同秒消息需要配套的读取边界处理。直接扩大 SDK 清理范围可能读掉同秒未看到的消息；固定减去进入会话时的旧数量也会在 SDK 已部分清理或其他设备已读时少算。因此应把上述失败用例与多设备降低计数、重复/乱序回调、账号切换和重启恢复一起作为修复验收条件。

**索引与检查边界**

已新建并完成当前工作区 GitNexus 索引 `99chat-unread-rebound`；时间 `2026-09-26T05:05:21.314Z`，索引提交与 HEAD 一致。索引存储在 `D:/codex-task-cache/99chat-unread-rebound-20260926`，未覆盖项目旧索引。

图追踪确认：`_handleOnConvItemTaped → clearLocalForOpenFast → _watermarkFor → conservativeTimestamp`。影响分析中，`conservativeTimestamp` 解析到 2 个直接调用者、深度 3 内 16 个受影响符号，评级 LOW；`resolveSdkUnreadAgainstReadBarrier` 解析到 `_mergeConversationUnread` 等 7 个符号，评级 LOW，但明确标记 lower-bound，另有 7 个接收者类型未解析的调用点。已用源码补查共享守卫、同步服务和本地合并入口。未把空 process 列表当作无影响证明；大文件中的旧 UIkit 已读入口另经源码核对。

历史追踪显示 T−1 策略来自 `c315f7e`；新消息前进时删除保护的逻辑在更早历史中已有，`cccb87d` 调整了群序号和同秒处理。现有证据支持这些机制叠加形成问题，不足以断言用户具体从哪一版开始遇到。

完整证据保存在本目录的 `reproduction.log`、`existing-tests.log` 和 `graph-evidence.json`。此次没有修改业务逻辑或提交代码。
