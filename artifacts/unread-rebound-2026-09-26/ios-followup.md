# iPhone 3.0.1+18 未读恢复：补充检查

用户反馈：iPhone 真机的单聊、群聊都会出现；电脑安卓模拟器正常。未确认在真机停留较长时间是否仍能复现。

**本轮新增的确定发现：两个离页入口使用不同的已读目标，并且先执行的入口决定最终结果。**这个缺陷存在于共享客户端代码，不是已证实的 iOS 原生 SDK 缺陷。

| 入口 | 读取的目标 | 代码位置 |
| --- | --- | --- |
| 会话列表等待聊天返回后 | 会话列表的 lastMessage，通常为最新预览 | `conversation.dart:3460`、`:4462` |
| 聊天页面销毁 | 从聊天消息数组尾部倒序找第一个非空 ID | `chat.dart:9850`、`:10056` |

聊天消息实际为 newest-first（最新在数组头部），来源为 `tui_chat_global_model.dart:8217` 的排序约定与检查逻辑。因此第二个入口可能取到加载窗口中最旧的消息；它也没有读取真正的屏幕可见范围。

随后两个入口都进入 `finalizeConversationLeaveOnce`。同一次聊天采用 first-flight 去重：已有处理就等待；已经处理完就直接跳过。同一代次中，后到入口携带的不同目标不会重新合并。

当旧 ID 先进入时，`_finalizeConversationLeave:627` 只把该 ID 传给 `recordReadClearedAnchor`。原锚点与新传入的旧 ID 不同，本地会话最新消息也不匹配，在 SDK-primary 镜像不存在或只有最新预览时，时间与群序号退成 0。下一份 SDK 未读快照就可能被判定成新消息，清掉防护并恢复旧数量。

**执行结果**

新增 `leave_anchor_reproduction_test.dart`，直接调用真实 `finalizeConversationLeaveOnce`，按两种顺序同时发起两次离页处理。为隔离本地问题，关闭 SDK 网络调度，使用测试专用本地持久化替身；没有运行 iOS 原生库，没有复制 finalizer 的实现。

| 先到目标 | 后到目标 | 单聊结果 | 群聊结果 |
| --- | --- | --- | --- |
| 正确最新消息 seen | 旧历史消息 old-history | 正常，旧快照后仍为 0 | 正常，旧快照后仍为 0 |
| 旧历史消息 old-history | 正确最新消息 seen | 锚点时间变 0，行/Tab 恢复 5 | 锚点时间和群序号变 0，行/Tab 恢复 5 |

共 4 项：2 个正常顺序对照通过，2 个错误顺序缺陷断言失败。完整输出为 `leave-anchor-reproduction.log`。这一结果可以解释为什么回调/离页处理顺序不同会产生不同表现，但尚不能证明 iPhone 当次必定采用错误顺序。

**已核对的原生链路与边界**

- iOS Podfile.lock 锁定腾讯 SDK 8.9.7545；与本地 Flutter SDK 包 8.9.7545 对齐。podspec 自身的 8.0.0 是插件描述版本，不等于安装了腾讯 8.0 原生 SDK。
- 当前原生平台都经过 `TIMConversationManager.cleanConversationUnreadMessageCount`，iOS 装载其 framework，Android 装载 `.so`。未看到按 iOS 特意跳过清未读的应用分支。
- FFI 的清理时间和群序号参数均声明为 Uint64；未发现 Dart 绑定把两个参数颠倒或声明为 32 位的证据。仓库中的 iOS 桥接库是二进制，未验证其运行时行为。
- SDK 原生回调返回之前，清理 Future 会保持等待；当前链路没有单次请求超时。若回调不返回，后续同会话清理会加入等待。这是额外的可疑条件，尚无手机日志证明本次发生。
- 旧 UIkit 已读入口默认不会做全会话清理；主路径依赖保存的读取范围。单聊 T−1 的残留问题仍成立，但不能单独解释群聊也异常。
- Release 的 `main.dart:103` 丢弃 debugPrint，并吞掉 print；`ConversationUnreadTrace` 默认关闭。仅添加 IM_UNREAD_TRACE 编译开关到 Release 包仍不足以输出现有诊断行。

**真机下一步需要验证的最小证据**

同一次操作记录：版本和原生 SDK 版本 → 进入时旧未读数及消息 ID/时间/群序号 → 两个离页入口各自的目标和先后 → SDK 清理参数及返回码 → 后续 SDK 快照的消息身份和未读数 → 本地解析后的未读数。

最有区分度的事件是 `finalize_leave_start` / `finalize_leave_join` / `finalize_leave_skip`，以及 `sdk_clean_start` / `sdk_clean_done` / `sdk_clean_deferred` / `sdk_clean_frequency_block`。应使用能保留这些事件的诊断构建；当前 Windows 主机仅能看到 Android 模拟器，没有可操作的 iPhone 或 Xcode 真机运行环境。没有重新安装、退出登录或清理用户聊天数据。

修复范围应覆盖两个离页入口的一致目标、读取水位不倒退，以及旧 SDK 数量与新消息增量的合并。仅把数组末尾改成头部，仍无法证明最新消息已在屏幕显示，也不能独自解决上一篇报告中的累计值残留问题。

GitNexus 使用当前工作区索引 `99chat-unread-rebound`（2026-09-26T05:05:21.314Z，HEAD c25b083）。`_lastVisibleMessageIdForLeave` 影响分析 LOW，直接调用者为 dispose；`recordReadClearedAnchor` 为 LOW/lower-bound，17 个类型未解析调用点已用调用源码补查。SDK 分发代码被仓库索引排除规则排除，采用精确源码核对。业务代码未修改。
