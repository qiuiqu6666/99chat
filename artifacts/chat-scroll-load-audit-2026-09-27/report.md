# 安卓版本 19 聊天页上下翻页排查

日期：2026-09-27。结论性质：录屏观察、当前源码追踪和可重复的故障注入测试；尚未取得问题手机的运行日志，不能把代码缺陷直接等同于录屏的唯一触发原因。

## 结论

确认了两处分页缺陷：**云端补拉失败后，本地短页会错误关闭较新消息分页；缓存页全部被业务过滤后，较早消息分页可以反复报告成功，却停在同一游标。** 两者取决于设备本地消息状态和请求结果，能够解释同一页面在不同设备上表现不同。

另外确认，本地数据库不可用时，上下分页都可能在发起 SDK 请求之前失败，且没有用户可见提示。恢复数据库后测试能够继续加载，因此本次没有证明数据库异常会永久锁死页面。

本轮没有修改业务源码、版本号或依赖，没有提交或打包。只新增本目录内的排查材料，并刷新 GitNexus 索引。

## 范围与版本

- 用户补充：安卓，版本号 19；未取得具体型号和安卓系统版本。
- 当前工作区版本为 `3.0.1+19`。基准提交 `c7e9caf4101c6571f60881f4212c9ff380273213`；工作区原本已有版本号和依赖锁文件修改，均保留。手机安装包与该提交是否完全一致仍未核验。
- `IMG_0108.MP4` 长约 10.13 秒。列表能够滚动，反复显示同一段消息，顶部多次出现加载圈；录屏没有网络响应和分页游标，不能证明服务端未返回消息，也不能证明新消息已经到达手机。
- [录屏抽帧](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-scroll-load-audit-2026-09-27/video-contact-sheet.jpg>)：每 0.5 秒一帧，按行从左到右排列。

## 1. 高优先级：本地短页被当成云端较新历史结束

触发条件：向较新方向补拉；云端请求失败或返回空；本地缓存仍有少量较新消息；没有比该本地页更高的有效“已知最新消息”提示，也没有其他待补消息标记兜底。

具体路径：

1. [较新方向本地兜底](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_history_pagination_load.dart:1018>)将 `localLatestResponse` 赋给 `response`，没有同步将 `selectedHistorySource` 改为 local。较早方向的对应兜底已有这一步。
2. [来源判断](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_history_pagination_load.dart:1093>)根据请求前后在线状态推算来源。在“连接状态仍在线，但这一笔云端请求失败”的情况下，本地结果被记录为 `actualSource=cloud / cloudProven=true`。
3. [安卓使用的原生适配器](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_sdk/lib/native_im/adapter/tim_message_manager.dart:1322>)按 `messageList.length < count` 合成 `isFinished`。这是返回条数判断，不能单独证明云端已经没有更多消息。
4. [结束状态计算](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_history_pagination_load.dart:1218>)对非空短页的保护只覆盖较早方向；[较新状态更新](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_history_pagination_load.dart:1932>)仍直接使用 `response.isFinished`。
5. [界面分页入口](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart:9167>)依赖这些标记。一旦全部被关闭，用户继续滑到较新端也不会再次补拉。

实际复现：初始显示 100、99，设置“较新消息缺失”，保持网络状态 online；云端请求抛错，本地返回 101～105，共 5 条，请求数量为 20。结果：

```text
请求：CLOUD_NEWER -> LOCAL_NEWER
结果来源被记录：actualSource=cloud, cloudProven=true
可见消息：105..99
haveMoreLatestData=false
memoryWindowMissingNewer=false
knownTipMissing=false
```

“本地短页不能证明云端结束”的断言失败。该缺陷对本地缓存少、云端偶发失败、最新消息提示落后的设备影响更明显。即便后续其他恢复机制可能重新打开状态，当前滚动入口已经被关闭。

修复方向：本地兜底必须保留真实来源；本地结束和原生短页不能作为云端较新历史结束依据；在远端缺口尚未核实时保留可重试状态。修复不能只增加滚动触发次数，否则入口状态仍会错误关闭。

## 2. 中高优先级：缓存页被过滤后不推进游标，反复假成功

触发条件：命中本地相邻历史页，整批消息被业务过滤，实际显示列表没有增长。当前真实生产回调会过滤非终态通话信令，不需要假设不存在的过滤逻辑。

路径：

- [读取缓存页](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_history_pagination_load.dart:17>)默认根据当前可见列表最老消息取边界，仅在扫描上限触发时保存继续扫描位置。
- [提交缓存页](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_history_pagination_load.dart:89>)调用业务过滤后，以 `commit != null` 判断加载成功，没有同时证明可见列表或较早方向游标推进。
- [生产回调](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:9671>)确实执行通话历史归一化；[过滤实现](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/utils/call_bubble_dedupe.dart:231>)会移除不应显示的通话信令。
- 下一次仍从原最老可见消息读取，继续命中同一缓存页，无法走到更早的可见消息或 SDK 兜底。

实际复现：可见消息 100、99；缓存相邻页含 98～79 共 20 条邀请信令，再下一页含普通消息 78。使用生产的 `CallBubbleDedupe.normalizeCallHistoryMessages` 和去重回调，连续请求三次，每次取 20 条：

```text
三次返回：[true, true, true]
可见消息始终：[m100, m99]
SDK 请求数：0
更早普通消息 m78：始终未出现
```

这会表现为“加载圈出现了，但历史一直停在同一段”。它是已复现的缺陷，但录屏中未看到被过滤的隐藏页，因此不能断言录屏就是这个触发条件。

修复方向：把已扫描的原始缓存边界和可见消息边界分开；整页被过滤时保留继续位置，且不要把无进展提交报告为可见加载成功。继续扫描必须有限额，并保留账号、会话、清空版本和撤回/删除约束。

## 3. 已复现的失败表现：数据库不可用时两个方向静默失败

[分页缓存读取](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_history_pagination_load.dart:418>)先于 SDK 请求。模拟 `SqfliteClosedForBackground` 后，较早和较新分页均结束，SDK 请求数为 0，消息列表不变。恢复数据库后再次请求，SDK 被调用，消息 98 成功出现，loading=false。

这证明了数据库不可用期间可以出现“双向无反应”，也排除了在该复现条件下永久遗留加载锁的猜测。尚无证据证明问题手机前台时真的处于这种数据库状态。

诊断不直观的原因：

- [历史失败提示策略](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/controllers/history_pagination_controller.dart:63>)固定返回 false，测试里 `historyLoadNotice=null`。
- [分页日志开关](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/utils/chat_history_trace.dart:15>)只在 debug 模式打开，普通 release 包不会输出这些逐步事件。
- SDK 读取已有 20 秒超时保护；本地数据库串行读写和业务回调的等待不属于这段 SDK 超时。不能泛化为“所有请求都没有超时”。

修复/核验方向：在保留消息删除、撤回和清空屏障的前提下提供恢复与重试；不要直接绕过本地权威记录。增加短期、脱敏的分页状态诊断，记录实际来源、游标、返回条数、可见增长和拒绝原因。

## 测试与证据

既有相关测试共 **88 项通过**：

- 69 项：Community 历史末尾恢复、旧消息手势排队、较新方向恢复、短列表触摸重试、过滤后的 SDK 翻页。
- 19 项：移动端滚动、快速拖动、清空版本和前后台恢复。
- 新增 3 项故障探针：**2 项失败，稳定暴露以上两处缺陷；1 项通过，确认数据库不可用与恢复的行为。** 探针失败是排查结果，业务代码尚未修复。

文件：

- [诊断探针](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-scroll-load-audit-2026-09-27/diagnostic_probes_test.dart>)
- [诊断日志](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-scroll-load-audit-2026-09-27/diagnostic-probes.log>)
- [69 项测试日志](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-scroll-load-audit-2026-09-27/baseline-tests.log>)
- [19 项移动端与恢复测试日志](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-scroll-load-audit-2026-09-27/mobile-and-lifecycle-tests.log>)

复测诊断探针：

```powershell
flutter test --no-pub artifacts/chat-scroll-load-audit-2026-09-27/diagnostic_probes_test.dart --reporter expanded
```

测试是 Flutter 受控环境，并非问题安卓手机上的原生 SDK 实测；设备网络和磁盘故障由测试注入，缓存、Writer、分页加载和生产过滤逻辑实际运行。

## GitNexus 检查说明

绑定当前路径对应的 `99chat-unread-rebound`。原索引落后一个提交，且默认 512KB 上限漏掉两个核心聊天文件。已按 1024KB 上限刷新至上述 HEAD，索引时间 `2026-09-27T07:38:02.563Z`，包含 76,134 节点、174,040 关系。

刷新后全文检索因 UTF-8 错误降级；图查询仍可用。通过 CLI context 核实 `_scheduleLoadLatest -> _loadLatest` 等调用，保存了图结果。`_commitHistoryWindowPage` 上游影响为 LOW、2 个符号；`loadChatRecord` 的图风险为 UNKNOWN，不能视为无影响，已用源码确认 `TUIChatSeparateViewModel` 经 runner 和分页控制器的绑定调用。业务方法未做修改，因此不涉及提交前变更门禁。

建议先修复来源与结束标记、缓存游标这两处已复现问题，再用问题安卓设备验证：弱网恢复、进入旧消息后向最新端滑动、缓存含隐藏消息、切后台后回前台。记录安装包对应的提交以及分页诊断，才能把本次代码结论与录屏现场一一对应。
