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

