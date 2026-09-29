# 聊天滚动、回到底部与新消息提示：深入排查

检查日期：2026-09-28。检查对象是当前工作目录的实际代码，包含尚未提交的修改。此次没有修改生产代码。

## 结论

已复现三个逻辑或布局问题，以及一个返回失败时反馈不足的问题。这些问题分布在消息过滤、可见性确认、布局状态释放和历史阅读位置保护中，不能靠统一改一个滚动距离解决。

现有实现已经有可取的基础：新消息按身份去重；区分历史窗口底部和真正最新端；检查实际显示行；部分返回任务可被手势取消；按钮显隐有不同阈值。应保留这些保护，修正数据口径和状态生命周期，避免推倒后重新引入误清未读等问题。

## 已确认问题

### 1. 高优先级：隐藏系统消息让“新消息”提示清不掉

**触发**：正在阅读历史时收到一条原生设置管理员提示。这条消息按现有业务规则不展示。点击“1 条新消息”，再点一次。

**实际观测**：两次返回后均为 `offset=0, min=0, rawNewest=101, displayNewest=100, remaining=1, durable=true`。可见列表已经到底，但提示仍存在。

**原因**：入站计数接收所有非本人、具有 ID 的消息；显示过滤发生在后面。到底确认又要求显示的最新消息 ID 等于原始最新消息 ID，要求用户看到一条永远不会展示的消息。持久化待确认边界也保留了该消息。

关键位置：

- [应用展示过滤](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:10896>)
- [新消息身份登记](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:4200>)
- [原始最新与显示最新比较](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/tim_uikit_chat_history_message_list_tongue_container.dart:199>)
- [持久化最新边界确认](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_bounded_history.dart:1297>)

**修复方向**：同步层继续保留原始消息；“新消息”计数、显示最新边界、待确认账本统一使用业务可显示性。区分“永久隐藏”和“暂时未加载/未布局”，不能为了消除提示而直接清零。还要处理已有账本中的隐藏 ID。

**证据**：[管理员提示诊断用例](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/new-message-capsule-audit-2026-09-27/admin_tip_probe_test.dart>)。该诊断用例通过表示成功复现错误，不表示功能正确。

### 2. 高优先级：阅读历史期间的延迟高度变化会带走阅读位置

**触发**：使用生产消息列表，向历史方向拖动 650 像素并停稳；让当前已挂载的一条较新消息增高 120 像素。

**实际观测**：正在阅读的第 89 条消息顶部从 `486` 变成 `366`，位移 `-120`；滚动偏移一直为 `650`。期望误差不超过 1 像素的断言失败。

**原因与边界**：保持滚动偏移不等于保持正在看的消息。当前有专门用于消息插入和分页的锚点恢复，但没有覆盖所有稳定阅读期间的内容高度变化；插入锚点还会在有限帧数后清理。诊断用例控制单元格高度，证明实际列表不能保住此场景的阅读位置；它不意味着所有图片都会改变高度。

关键位置：[插入锚点保护与清理](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart:3883>)。

**修复方向**：阅读历史期间持续保存稳定消息 ID 和相对视口位置；分页、图片尺寸更新、消息内容更新统一按该锚点保持位置。在布局阶段补偿，避免先显示偏移再于下一帧跳回。对媒体尽量提前固定宽高比，但不能仅依赖占位尺寸。

### 3. 中高优先级：界面尺寸稳定后，“布局调整中”状态可能不释放

**触发**：生产列表视口从 `390×844` 改为 `390×620`，随后等待 120 帧。

**实际观测**：`isGeometryViewportTransitionActive` 仍为 `true`，期望已经释放的断言失败。

**原因**：代码等待两次“尺寸相同的滚动指标通知”才释放。但尺寸不再变化后，不一定会继续产生这类通知；稳定帧不等于滚动指标通知。

**直接影响**：跟随状态同步和部分可见新消息确认会被该状态阻挡。新的真实拖动有显式解除逻辑，因此不能扩大描述为“所有手势永久锁死”。

关键位置：

- [布局锁释放条件](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart:14745>)
- [跟随状态同步被阻挡](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart:3467>)
- [可见新消息进度被阻挡](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart:5949>)
- [模型拒绝退出跟随](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:4285>)

**修复方向**：在布局帧中验证尺寸是否稳定，按会话和任务代次释放；允许新手势立即接管；离页、异常和取消时都有清理。不要依赖未来可能不再到来的通知。

第 2、3 项共用证据：[生产组件诊断测试](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-scroll-audit/scroll_anchor_probe_test.dart>)、[最终合并运行日志](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-scroll-audit/scroll_anchor_probe_final.log>)。最终日志两项均因真实行为断言失败，没有测试夹具找不到行的问题。

### 4. 中优先级：返回最新失败时，缺少明确的进行中与失败反馈

**触发**：已通过实时消息收到第 101 条，SDK 的最新页仍只返回到第 100 条。

**实际观测**：至少进行了 3 次请求；操作后仍停在偏移 `1200`，新消息计数仍是 `1`。保留未读是正确保护，但用户看到的是按钮消失、画面没动、随后提示重新出现。

返回过程中整个按钮被隐藏；有 25 秒总截止时间，尚未结束时重复调用直接返回。生产入口没有连接保留画面的过渡回调，也没有在这个按钮上提供进行中或失败状态。

关键位置：[返回任务与重试](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/tim_uikit_chat_history_message_list_tongue_container.dart:357>)、[进行中隐藏按钮](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/tim_uikit_chat_history_message_list_tongue_container.dart:1686>)、[生产入口接线](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart:14431>)。

**修复方向**：保留入口，显示“正在返回/加载”；明确失败后可重试；用户拖动可取消，不能误清未读。网络结果尚未覆盖已知最新消息时，应明确显示加载状态，并保留已经可浏览的内容。

**证据**：[最新页落后诊断用例](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/new-message-capsule-audit-2026-09-27/stale_page_probe_test.dart>)。该诊断用例通过同样表示错误场景得到复现。

## 主流产品如何处理

以下来自官方资料及公开源码，不能据此声称掌握微信或 WhatsApp 的内部实现；腾讯云组件也不等于微信客户端源码。

| 参照 | 能核实的处理方式 | 本项目应借鉴的重点 |
| --- | --- | --- |
| 腾讯云 IM | 底部时自动跟随；读历史时只提醒；加载旧消息后保留位置；点击回最新入口才定位。 | 依据用户阅读状态决定行为，不因消息数组变化就滚到底部。 |
| Telegram Desktop | 保存可见消息的位置标识及相对偏移；按钮综合判断距底距离、是否加载到最新、下方未读等。 | 位置锚点和新消息数量分开；“当前窗口到底”不代表“真实最新”。 |
| Signal Desktop | 根据更新类型分别保持顶部、保持底部距离、定位消息或未读分隔线；普通新增仅在原先位于底部时跟随。 | 将滚动决策集中，区分旧页、新页、实时消息和用户定位。 |
| Slack | 提供“打开停在最新但保留未读”等独立偏好。 | 定位和已读是两件事，不能在点击按钮瞬间全部清零。 |

一手来源：

- [腾讯云 MessageList Store 官方示例](https://intl.cloud.tencent.com/zh/document/product/1047/72086)
- [Telegram 保存与恢复阅读位置](https://github.com/telegramdesktop/tdesktop/blob/d81a5ac270fdcb5315b49f813614caa71f85697f/Telegram/SourceFiles/history/view/history_view_list_widget.cpp#L1382-L1415)
- [Telegram 返回底部按钮判断](https://github.com/telegramdesktop/tdesktop/blob/d81a5ac270fdcb5315b49f813614caa71f85697f/Telegram/SourceFiles/history/view/history_view_chat_section.cpp#L3679-L3730)
- [Signal 滚动决策](https://github.com/signalapp/Signal-Desktop/blob/abe80d32445e53b047b42d10c5b751c4fbfbbfc0/ts/util/timelineUtil.std.ts#L157-L208)
- [Signal 实际可见性与已读推进](https://github.com/signalapp/Signal-Desktop/blob/abe80d32445e53b047b42d10c5b751c4fbfbbfc0/ts/components/conversation/Timeline.dom.tsx#L368-L458)
- [Slack 阅读位置与已读偏好](https://slack.com/help/articles/360043037853-Manage-your-Mark-as-read-preference)

## 建议统一的行为规则

这部分是结合证据提出的本项目方案，不是对任一家产品内部结构的断言。

| 状态/动作 | 应有行为 |
| --- | --- |
| 跟随最新 | 新消息进入后保持最新端，布局变化也保持贴底。 |
| 主动读历史 | 用户控制滚动；到达的新消息只增加尚未看见的可展示消息数。 |
| 加载旧消息 | 保持当前阅读消息及其位置，不能被新页顶走。 |
| 点击回最新 | 一个可取消的返回任务；加载、定位、渲染确认分阶段完成。 |
| 返回途中再次拖动 | 立即交还手势控制，旧动画和异步回调不能再次抢位置。 |
| 键盘/面板/消息尺寸改变 | 只临时保护布局；跟随模式保底，阅读模式保锚点；稳定后必定释放。 |
| 清除新消息数 | 基于实际已显示/已读身份确认；不依据点击事件、单纯偏移为零或历史加载完成。 |
| 临时窗口底部 | 仍缺新页时显示回最新入口，不伪装成真实底部。 |

修复顺序建议：先统一可展示消息口径并处理遗留隐藏 ID；再修布局状态释放；随后补齐历史阅读中的持续锚点；最后统一返回任务的反馈、取消和重试。现有距离阈值最后再根据真机体验调整。

## 验证情况与验收矩阵

本次普通回归测试共 42 项通过：

- `return_to_latest_rendered_proof_test.dart`、`chat_quick_drag_scroll_regression_test.dart`、`back_to_bottom_capsule_policy_test.dart`、`true_latest_end_capsule_test.dart` 合计 29 项。
- `chat_unread_presentation_state_test.dart` 4 项。
- `durable_incoming_capsule_regression_test.dart` 9 项。

另外 4 个针对性诊断场景：隐藏消息与落后最新页两个用例成功复现错误；新增的视口锁释放、延迟高度保锚点两个用例按正确行为断言，均失败。既有测试全绿不能说明这些交叉场景正确。

发现两个具体测试盲点：`chat_keyboard_viewport_message_visibility_test.dart:160` 只验证源码含有“两次通知”判断，并不检验稳定后是否真的解除保护；`history_reading_viewport_anchor_test.dart:125` 由测试主动持有锚点，验证了锚点算法，却没有验证生产页面会不会过早丢掉锚点。后续应增加真正驱动生产组件的行为测试，不能只增加源码字符串断言。

后续修复必须覆盖：

1. 快速上下拖动，同时连续收消息、重复推送和更新发送状态。
2. 分页加载与实时消息同时完成，用户继续拖动。
3. 点击回最新后立即反向拖动、连续点击、慢网与失败重试。
4. 图片/表情/长文本等消息在较晚时刻改变尺寸。
5. 键盘和表情面板反复切换、窗口旋转、预览返回。
6. 隐藏系统消息与普通消息混合、已有隐藏待确认 ID、撤回或删除。
7. 切换会话/账号后，旧请求或旧滚动动画完成。

测试使用真实 Flutter 消息列表、提示组件及部分真实 SQLite 路径，但消息网络和行尺寸可控；没有进行真实设备上的帧率、iOS 键盘动画和长时间大群压力验证。以上证据不声称已经覆盖用户遇到的所有现象。

GitNexus 绑定当前目录对应的 `99chat-unread-rebound`，注册索引提交与 HEAD 均为 `0e7aa83bc5b096a99ff8bb424842404a3c901cb7`，索引时间 `2026-09-27T20:29:36.339Z`。关键词索引未启用，采用符号上下文后核对当前源码；未提交变更以实际文件和运行结果为准。
