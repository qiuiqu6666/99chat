# 99chat F01–F13 审计复核

日期：2026-09-28。对象：用户提供的《99chat 全 App 关键链路稳定性与性能审计》，以当前工作区为准，含此前未提交的聊天修复。HEAD：`0e7aa83bc5b096a99ff8bb424842404a3c901cb7`。

结论：报告在复核开始时的主要判断有依据；收尾时工作区出现并行网络修复，F01/F03 及 F02/F04 的已测子项现已通过针对性验证，不能继续一律列为未修。F05/F06/F07/F08/F09/F11/F12 的对应机制仍在；F10 收尾新增生命周期改动，另列待验收。各项证据等级不同，不能合称已复现线上故障。F13 应更新为“聊天诊断部分补齐，全局持久化及网络任务仍有缺口”。报告附带的“撤回作用域失效分支缺少退出”已过时，当前实现已有退出且回归通过。尚未证明这些问题共同解释用户的全部白屏、撤回、滚动或跳转症状。

本轮仅新增本目录复核材料与诊断探针，没有修改业务代码、原有测试或提交代码。GitNexus 导航使用当前工作区对应的 `99chat-unread-rebound` 索引（记录时间 2026-09-27T18:28:33.139Z，UTC）；所有判断回到当前源码验证，25 个主要文件的 SHA-256 见 [source-manifest.json](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/source-manifest.json>)。未运行全量回归、打包、真机或线上测试。

## 收尾时发现的并行改动：以此状态为准

收尾核验时，4 个网络源文件相对首次读取发生变化。这些业务修改并非本复核执行；已保存 [候选差异](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/candidate-network.diff>) 与 [候选源码清单](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/candidate-source-manifest.json>)（UTC 2026-09-27 19:02:30，即台北时间 2026-09-28 03:02:30）。下面的历史证据表记录修改前状态，不得把旧探针的缺陷断言当作候选修复的验收断言。

| 项目 | 最新快照状态 | 本次新增验证与余项 |
| --- | --- | --- |
| F01 | **取消误计数已修，针对性测试通过** | [取消与节点代次过滤](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/api/api_client.dart:235>)；3 次取消现在为 0 次健康失败、0 次健康成功。真实网关故障、完整自动切线仍需覆盖。 |
| F02 | **快速 503 误选已修；其余修复待专项验收** | [探测状态](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/api_node_service.dart:305>) 对 503 返回 abnormal，较慢 200 被选中。当前也增加请求节点代次/目标地址过滤与 [共享探测 Future](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/api_node_service.dart:241>)，但本轮未验证旧节点乱序结果和并发探测。200 且 Map 是当前健康判断，完整接口契约需另外确认。 |
| F03 | **本次字符跨块丢失已修，针对性测试通过** | [流式 UTF-8 解码](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/friend_realtime/friend_realtime_connection_io.dart:45>)；分块中文事件与后续控制帧都交付，异常数为 0。所有字节边界、过长帧和坏帧策略尚未完整验收。 |
| F04 | **新凭据恢复已修；认证/心跳限时新增，待专项验收** | [凭据代次](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/friend_realtime_service.dart:133>) 使 force 后连接数变 2、ready=true。新增 [阶段 deadline](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/friend_realtime_service.dart:329>)、pong 清理和前后台处理，但无认证应答、半开连接与频繁前后台仍需测试。 |
| F05 | **重试总边界仍未修** | 候选文件中 [过载重排](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/friend_realtime_service.dart:608>) 仍取消单次计时器并重排，无入队总期限/尝试上限。此前 9.2 秒/76 次探针是修改前运行结果；候选的新增心跳机制不等于修复过载预算。 |
| F06/F07/F08/F09/F11/F12 | **对应缺口/成本路径仍保留** | 通讯录新增捕获代次不回退的修复，但未改变 F06 单条增量的复制/扫描路径；其余保留后文证据等级。 |
| F10 | **收尾新增生命周期修复，待验收** | 新代码取消全局串行生命周期链，加入有限等待、degraded 状态和逐库关闭记录，保留原生关库屏障。本轮未对该新版本注入关库挂起/前后台故障，不再将旧串行链描述为当前未改实现，也不宣布恢复问题已解决。 |
| F13 与撤回旧项 | **聊天日志部分补齐；过期撤回缺少退出已修** | 保留后文说明。 |

候选针对性测试 **4/4 通过**：[网络 3 项日志](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/candidate-network.log>)、[认证 1 项日志](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/candidate-auth.log>)。使用与基线相同的 loopback/受控 adapter 故障条件，改为断言期望行为，不修改旧探针。两阶段共 10 项最终断言通过：5 项复现旧缺陷、1 项验证既有撤回修复、4 项验证新增网络修复；不是 10 项产品功能全量验收。后续改动应按清单 hash 判断这份结论是否仍适用。



收尾又读取到生命周期与目录变更，差异保存在本目录的 late-lifecycle-directory.diff，最新 F10 状态已更新为“待验收”。工作区仍有并行修改；测试结论仅适用于各次清单中的源码快照，后续版本需要重新验收。

## 首次复核证据（已变更文件链接到修改前快照）

| 编号 | 复核结论 | 当前证据与边界 |
| --- | --- | --- |
| F01 主动取消被计为节点故障 | **已复现** | [ApiClient](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/baseline-source/lib/src/api/api_client.dart:283>) 在 response 为空时直接判故障。真实 CancelToken 取消 3 次，公共拦截器发出 3 次失败反馈、0 次成功反馈。实际切线还依赖节点已初始化、累计失败未被成功清零及有可选节点；本次没有访问线上节点做完整切线。 |
| F02 错误健康探测与旧节点反馈 | **核心缺陷已复现；附属竞争为源码确认** | [probeNode](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/baseline-source/lib/src/services/api_node_service.dart:264>) 将快速 503 和较慢 200 都归为 normal，真实选择器选择了 503。[健康反馈](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/baseline-source/lib/src/services/api_node_service.dart:162>) 不携带原请求节点/代次，旧结果可污染当前计数；[probeAll](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/baseline-source/lib/src/services/api_node_service.dart:230>) 在已有探测时立即返回。后两项未做并发故障注入。 |
| F03 TCP 分块 UTF-8 | **已复现** | [逐块解码](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/baseline-source/lib/src/services/friend_realtime/friend_realtime_connection_io.dart:43>) 在中文字符中间拆块时抛出 2 次 FormatException，该事件未交付；后续 ASCII 控制帧正常，断连回调为 0。确认丢帧与异常逸出，未证明进程崩溃。范围是自建业务 TCP。 |
| F04 TCP 认证与存活状态 | **force 恢复缺陷已复现；无 auth/pong 截止风险由源码确认** | [ensureConnected](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/baseline-source/lib/src/services/friend_realtime_service.dart:113>) 在 force 清理前被 authFailed 拦住。换合成新凭据后连接数仍为 1、ready=false；stop/start 后连接数变 2、ready=true。[心跳](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/baseline-source/lib/src/services/friend_realtime_service.dart:257>) 无 pong 新鲜度判定。未跑长期半开或不回 auth 的手机实验，不能称为只能杀进程恢复。 |
| F05 在线查询无限重排 | **已复现超过单次超时仍 pending；无总边界由源码确认** | [重排分支](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/baseline-source/lib/src/services/friend_realtime_service.dart:533>) 每次过载取消旧计时器并重排。同一请求在 9.2 秒内收到 76 次过载回复仍未结束，超过名义 8 秒超时；停止过载后原请求与下一请求均成功。[PresenceProvider](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/provider/presence_provider.dart:780>) 持续等待时无法到达释放 busy 的 finally。不能把有限时长探针表述为实测“永久”等待。 |
| F06 通讯录目录放大 | **性能成本路径成立，耗时未测** | [单条投影](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/friend_local/contacts_protocol_sync_service.dart:445>) 与 [全量复制](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/baseline-source/lib/src/services/im_sdk_relationship_directory.dart:451>)、[全量差异扫描](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/baseline-source/lib/src/services/im_sdk_relationship_directory.dart:658>) 形成 K 条事件 × N 个好友的复制/扫描。已有单飞、分页和让路；优化需按页聚合并保留删除、版本及排序语义。 |
| F07 旧通话令牌覆盖新会话 | **控制流缺口确认，未做真实媒体复现** | [令牌刷新/恢复](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/livekit_call_session.dart:1151>) 在 await 后写入当前凭据与定时器，没有核对原 callId/sessionGen/Room。重连函数在返回后才捕获当前代次，无法阻挡旧请求。旧恢复请求的失败分支也可能结束当前新通话。 |
| F08 结束回调阻止媒体释放 | **条件性控制流缺口确认** | [结束任务](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/livekit_call_session.dart:1352>) 先调用业务回调再 teardown；同步抛错会跳过后者，外围 finally 只清 finalizing。[既有 teardown](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/livekit_call_session.dart:1250>) 的每阶段 2 秒限制应保留。未证明当前生产回调实际抛错或设备已泄漏媒体资源。 |
| F09 首帧前等待链 | **条件性等待风险成立** | [移动端入口](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/main.dart:475>) 在 runApp 前等待 deferred bootstrap 与 Android 性能桥接；[性能桥接](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/android_performance_profile.dart:38>) 无等待截止。不是所有初始化都访问网络，也不等于聊天页白屏根因。应先提供安全启动状态，再分级恢复。 |
| F10 iOS 关库拖住恢复 | **条件性等待风险成立，未复现原生死锁** | [生命周期串行链](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/baseline-source/lib/src/services/sqflite_lifecycle_host.dart:75>) 及 [多库关闭](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/baseline-source/lib/src/services/sqflite_lifecycle_host.dart:127>) 会等待全部关闭。任一 close 一直不结束，resumed 与写入许可都可能等待。此前聊天 watchdog 不等于这一原生资源问题已解决；不能超时后盲目并行开第二个 writer。 |
| F11 历史编码占据事务 | **性能成本路径成立，排队耗时未测** | [事务内 compute](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/history_window_store.dart:480>) 在读取权威历史状态后等待编码；isolate 不会自动释放事务。不能直接挪出全部计算，否则可能破坏撤回/删除与历史晚到的一致性。已有任务优先级与异常恢复，不应误报为完全缺失。 |
| F12 隐藏钱包仍工作 | **成本路径成立，实际负载未测** | [保留已访问 Tab](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/navigation/home_tab_stack.dart:26>) 后，[余额事件](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/wallet/wallet_controller.dart:153>) 仅检查 dispose，直接 force load；其中会启动订单恢复。已有 busy/refreshAgain 合并和可见刷新节流，不能称为无限并发。应拆分隐藏页面刷新与必须执行的资金对账。 |
| F13 长期等待诊断不足 | **部分过时，仍需继续补齐** | [持久化指标](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/im/message_persist_coordinator.dart:393>) 仍主要在成功结束后产出；失败和未完成任务缺少同等证据。当前已有 [聊天持久诊断](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/chat_recovery_diagnostics.dart:17>)、有界缓冲/轮转、等待阶段记录，以及设置中的“聊天问题排查”导出入口。不能再笼统描述聊天链路没有 Release 现场日志，也不能认为它已覆盖 TCP、所有数据库或启动阶段。 |

## 应修正的旧结论

[revokeMsg 过期作用域分支](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:8228>) 当前会恢复原作用域记录、完成投影清理，并在 8245 行 return，无法继续到后续撤回 SDK 调用。本轮重新运行“本地记录写入延迟时切会话”的真实组件回归，通过且 SDK 未被调用。因此删除报告中“该分支缺少退出，仍需修复”的断言；不将单项通过扩展成所有撤回现场问题都已解决。

原报告“当前环境没有 Flutter/Dart”“所有回归未执行”仅描述报告作者当时环境。本次已用可用 Flutter 运行以下 6 项；不能继续作为当前复核状态。

## 第一阶段实测证据（新增候选验证见前文）

| 验证 | 数量 | 结果 / 日志 |
| --- | --- | --- |
| F03 分块中文、F01 CancelToken、F02 快速 503 | 3 | 3 项成功复现缺陷。[network-probes.log](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/network-probes.log>) |
| F04 新凭据 force / stop-start 对照 | 1 | force 不恢复，stop/start 恢复。[auth-force.log](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/auth-force.log>) |
| F05 持续过载与解除过载对照 | 1 | 超过单次预算仍等待，过载解除后恢复。[presence-overload-verified.log](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/presence-overload-verified.log>) |
| 已有撤回过期作用域回归 | 1 | 修复仍有效。[revoke-stale-scope.log](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/revoke-stale-scope.log>) |

以上最终 6 项测试通过中，前 5 项的断言用于记录当前缺陷，**通过不代表修复完成**。网络使用 loopback 服务器或替换为受控 Dio adapter；日志中的默认业务 URL 只是请求元数据，取消探针没有向该地址发网。凭据为合成测试值。

新增 F05 探针的前两次调试运行在首次查询到达服务器前超时，不能用作过载证据。最终探针等待认证后的初始 ping 阶段稳定 200ms，隔离后再验证重试预算；未据此前两次失败新增产品缺陷结论。原始调试日志保留为 presence-overload.log 与 presence-overload-final.log。新探针尚未进入 GitNexus 索引，impact 返回 UNKNOWN；通过文本检索确认没有业务代码引用，只按显式测试路径执行，没有以空图结果宣称业务变更安全。

复现入口：先设置 Flutter 的可写 TEMP/TMP；网络测试使用 `flutter test --no-pub --concurrency=1 --reporter=expanded`。F04/F05 额外传入 `--dart-define=REALTIME_TCP_BASE=http://127.0.0.1:<空闲端口>`，测试会断言 loopback 与节点服务未 hydrate。F05 文件是 [presence_overload_probe_test.dart](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/audit-f01-f13-recheck-2026-09-28/presence_overload_probe_test.dart>)。其他探针沿用 cross-module-report-verification-2026-09-28/network 下的两份测试；其 A 编号不是本报告 F 编号。

## 实施顺序与验收边界

1. 优先处理仍未修的 F05/F07/F08，补齐 F02/F04 的并发与失活回归；F01/F03 保留新增修复并扩大边界验证。撤回过期作用域退出无需重复修。
2. F04/F09/F10 与剩余 F13 随后治理；诊断随每项修复一起补。需要截止时间，也需要任务身份、资源所有权和旧结果隔离，不能只清 busy。
3. F06/F11/F12 先取得 CPU、分配、队列等待和帧时间基线，再缩短路径；保留账号隔离、消息权威事实和必要资金对账。

现有待实施计划见 [跨模块稳定性修复计划](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/docs/plans/2026-09-28-gitnexus-plan-cross-module-stability-repair.md>)，本次复核不把计划存在视为已实现。下一轮验收仍需真实 Android/iOS 的弱网、前后台、长会话和大通讯录混合场景，并对应到实际发布包。没有线上发生率、P95、ANR 或“全部卡顿已经解决”的结论。

