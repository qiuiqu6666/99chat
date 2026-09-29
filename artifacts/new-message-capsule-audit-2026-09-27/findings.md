# 新消息按钮不返回 / 到底仍显示计数：检查结果

检查日期：2026-09-27。代码：main，0e7aa83bc5b096a99ff8bb424842404a3c901cb7，版本 3.0.1+20。
用户补充：点击后数字提示一直不变。以下为源码及可控测试确认的触发路径，尚未取得出问题设备的运行日志，因此不能断言手机上每次故障都由同一原因造成。

## 1. 已复现的逻辑缺陷：永久隐藏的业务消息阻止“已到最新”确认

实际产品规则会隐藏原生管理员设置/取消通知、废弃本地管理员通知、部分通话信号、空群提示。但新消息身份账本与“最新消息”判定没有统一使用这套展示规则。

链路：
1. `lib/src/chat.dart:9650` 的 newMessageWillMount 返回消息；`:10860` 的 _messageShouldMountInHistory 又在展示阶段过滤它。
2. `third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:4199` 的 _recordBufferedLiveIncoming 记录身份时不检查业务展示规则；`:14775` 的 getMessageList 展示时才应用 messageShouldMount。
3. `third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/tim_uikit_chat_history_message_list_tongue_container.dart:198` 的 _latestRowMaterialized 比较原始最新消息与显示最新消息的身份；两者不同即认为最新行尚未显示。
4. `third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_bounded_history.dart:1179` 的 historyWindowReturnCoversDeferred 要求可见消息覆盖未读边界；隐藏的最新消息永远不满足，且它并非权威删除，无法走“全部已删除”的例外路径。

完整生产消息列表 + 生产按钮 + 真实 SQLite 存储 + 可控 SDK 测试：原始最新序号 101 是原生设置管理员通知，正常业务过滤后显示最新序号为 100。点击两次后均为：

| 指标 | 点击第一次 | 点击第二次 |
|---|---:|---:|
| 滚动位置 / 底部位置 | 0 / 0 | 0 / 0 |
| 原始最新序号 | 101 | 101 |
| 显示最新序号 | 100 | 100 |
| 新消息身份账本剩余 | 1 | 1 |
| 持久化待确认状态 | true | true |
| “1 条新消息”按钮 | 仍可见可点击 | 仍可见可点击 |

这解释了“可见列表已经到底，数字仍保留，重复点击无效”。空群提示也独立复现。管理员通知测试调用真实 GroupTipsMessageHelper.isImNativeAdminRoleTip；没有靠伪造展示序号绕过生产判断。

证据：`admin_tip_probe_test.dart`、`admin-tip-probe.log`、`full_list_probe_test.dart`、`full-list-probe.log`。

## 2. 已复现的失败路径：最新页不可用或尚未追上，返回动作在滚动前退出

按钮不是直接滚到当前列表尾部。有较新消息缺口或持久化待确认消息时，它先重新获取最新窗口。

- `.../tim_uikit_chat_history_message_list_tongue_container.dart:468`：最多重试 3 次，两次重试间仅 80ms。
- 同文件 `:502`：三次未成功就重新显示提示并 return，后面的滚动动画不会执行。
- `.../tui_chat_separate_view_model.dart:1959`：即使 SDK 返回成功，若页面没有覆盖已收到的最新消息边界，仍返回失败。

两种情况均在生产按钮、生产加载逻辑、真实存储的测试中复现：

| 情况 | 点击前位置 | 点击后位置 | 剩余数字 | SDK 调用 |
|---|---:|---:|---:|---:|
| SDK 请求失败 | 1200 | 1200 | 1 | 3 |
| 已收到 101，但 SDK 成功页只到 100 | 1200 | 1200 | 1 | 3 |

后者说明不能只把现象归结为断网：消息到达与历史页更新的时差也可触发。保留未读和缺口是必要保护；问题是返回意图在三次尝试后结束，而界面没有清晰说明此次未能完成，因此表现像点击无反应。

证据：`capsule_probe_test.dart`、`probe-tests.log`、`stale_page_probe_test.dart`、`stale-page-probe.log`。

## 验证范围与限制

- 现有 6 个相关测试文件共 51 项：首轮 50 通过，1 项在批量消息写入等待阶段超时；索引刷新结束后单独重跑该项通过。该超时没有被归因于产品缺陷。
- 新增 5 项诊断用例均通过。它们断言的是上述异常现象确实存在，而非修复已完成。
- 完整列表的两个诊断使用实际 TIMUIKitHistoryMessageList、实际提示组件、实际模型与 SQLite，SDK 返回值可控；没有连接真实安卓设备或腾讯服务。
- 普通返回、最新行延迟布局、返回期间继续收消息、可见后确认等既有路径已有通过的测试。此次未证实“设备型号不兼容”或“Android 版本限制”。
- 仅新增诊断材料；业务源文件未修改。本次没有提交或推送。已有 pubspec.lock 的本地差异保留。

## 建议修复顺序

1. 统一业务可显示性与新消息计数、可见最新边界的口径。对永久业务隐藏消息单独处理其待确认状态，并兼容已经积累的旧账本；不得将动画暂未显示、消息尚未加载、延迟布局也当作永久隐藏。原始消息仍须保留用于同步游标和连续性。
2. 返回最新失败时保留正确的未读数和缺口，给出明确失败/重试反馈；检查网络/数据恢复后的返回意图恢复机制。不要简单强制清零或只滚到旧窗口底部。
3. 将本次探针转成正式回归：管理员通知在最新位置、可见消息与隐藏通知混合、重复点击、历史页暂时落后、请求失败恢复；保留既有晚到消息与真实可见性保护。

GitNexus：本地隔离存储索引已刷新到当前提交，流程与符号分析先行。部分 Dart 扩展/UI 回调未被图完整识别，已以源码和真实组件测试补证；MCP 默认存储仍报告旧提交，结论不依赖其空调用者结果。
