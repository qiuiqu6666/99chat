# 99chat 两轮审查合并与当前代码复核

日期：2026-09-28。用户要求：复核所贴的 17 项静态报告，并与上一轮启动、会话、聊天、媒体、通讯录及钱包排查合并；本轮不修业务代码。

## 结论

这份补充报告指出的多数机制在当前工作区仍存在，并且其中一些已从“静态推断”升级为真实组件的故障注入证据。**A16 的核心撤回控制流缺陷已经被当前未提交代码修复，应从待修清单移除；相关白屏/门控推测仍只能作为待验证场景。** A10 与上一轮首屏前初始化问题合并，不重复计数。

按原报告的 17 个编号归并：**15 项保留、1 项合并、1 项核心已修**。这是条目归并数，不是 15 个已证实的线上根因；部分条目包含多个缺陷或仍需真机测量的影响。

当前证据支持三个并行方向：

1. **界面和资源压力**：原尺寸图片解码、相册前置重编码、滚动重复数据库确认、大列表和备份的重复工作。
2. **业务状态失去进展或互相覆盖**：重复重连、旧会话校准改写新阶段、加载请求长期不结束、旧搜索/钱包结果覆盖当前状态、AI 停止后仍被视为生成中。
3. **连接稳定性**：网络字节块独立解码、主动取消被当作节点故障、错误响应被测速当成健康、业务 TCP 认证失败后的 force 入口被拦截。

这些机制可以叠加，但不能由源码或本地注入测试算出每项占线上投诉的比例。原生图片内存估算、虚拟时间和本地测试延时，都不等于受影响手机的实测指标。

## A01–A17 逐项结论

“成立”指当前代码中的行为/缺口得到确认；性能类条目仍单独保留耗时、帧率和发生率边界。复现测试断言当前问题存在，不代表产品验收通过。

| 编号 | 复核结果 | 合并后的准确表述 |
|---|---|---|
| A01 | 保留：两条路径均已复现 | TCP 与 AI SSE 的成功流路径按网络字节块单独 UTF-8 解码。真实 TCP 拆包丢失中文事件；真实 SSE 接口测试中 7 个字符内部切分点均失败。不是腾讯 IM SDK 本身的传输问题。 |
| A02 | 保留：已复现 | 公共 ApiClient 的取消错误被计为传输失败。3 次取消注入得到 3 次故障回调；是否实际切线还取决于成功清零、阈值和测速结果。 |
| A03 | 保留：已复现 | 真实 probeNode 将本地 HTTP 503 标为 normal；真实选择逻辑会优先选中比健康响应更快的 503。测速混淆了可达与可用。 |
| A04 | 保留：恢复缺口已复现 | `_authFailed` 的 return 位于 force 重置之前。真实服务换合成凭证后 force 未重新连接，stop/start 恢复成功；不能说只能杀进程。 |
| A05 | 保留：调用已复现，成本待测 | 缓存恢复会执行一次 connect，刷新签名成功后再 connect。已 ready 再 restore 也会重复；SDK 是否内部复用、实际连接成本尚未测量。 |
| A06 | 保留：并发已复现 | 定时重连检查 `_activeOperation` 却不登记自身。前一登录 pending 时，新的断线可触发第二个同代次登录调用。 |
| A07 | 保留：调度行为成立 | 等待聊天空闲有上限，超时后继续校准，即使聊天还活跃。额外工作确定，具体卡顿取决于账号规模和执行成本。 |
| A08 | 保留：状态覆盖已复现 | 旧校准任务完成/失败能改写新会话 scheduled 阶段，使新任务不再发起。确认的是控制阶段污染，不是已证明跨账号数据泄漏。 |
| A09 | 保留：故障条件已复现 | 注入一个不结束的 close 后，生命周期 resume 和写入许可一起等待。没有受影响 iPhone 的原生关库日志，不能称为已确认的线上 iOS 根因。 |
| A10 | 合并到前轮启动项 | 移动端 runApp 仍等多项前置初始化；安全存储失败/等待缺口已在上一轮验证。不能据此解释所有进入聊天后的白屏。 |
| A11 | 保留：额外上传已复现 | 101 条无变化的设备联系人连续两次 INCREMENTAL，均发送 100+1 条；旧快照主要用于删除项。是否可只发变化项必须核对后端完成语义。 |
| A12 | 保留：重复工作成立 | 已启用备份后逐项重写累计快照；超限视频在大小拒绝前可能已完成哈希。现有前台、空闲、网络、导航限制仍在，不能说随时无条件上传。 |
| A13 | 保留：两条状态缺口均已复现 | 实际页面收到内容后 stop，仍被历史 streaming 状态阻止再次发送；独立测试中旧上传失败覆盖了新回答。两条分支的运行证据见 AI 分报告。 |
| A14 | 保留：高频工作成立 | 每个 delta 更新页面状态并安排到底部滚动，缺少用户离底判断。Flutter 会合并部分 build，不能直接把 delta 数等同于绘制次数。 |
| A15 | 保留：隐藏刷新成立 | 钱包访问后保活，余额事件能触发离屏 Controller 刷新。是事件驱动的额外工作，不是已证明的无限轮询；必要资金/订单恢复不能停掉。 |
| A16 | 核心已修；其余待验证 | 当前 revokeMsg 在准备期间 scope 失效后已经 return，现有行为回归确认不调用 SDK。白屏、视口 gate 和长任务等待需分别验证。 |
| A17 | 独立保留 | 相册访问许可在未设置备份选择时可启用备份；当前默认 API/TCP 包含明文路径。需要独立处理授权目的和传输保护，未证明已泄漏，也不混入帧率根因。 |

详细代码位置及测试见：[网络与撤回复核](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/cross-module-report-verification-2026-09-28/network/network-verification.md>)、[会话恢复复核](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/cross-module-report-verification-2026-09-28/session/session-verification.md>)、[关系/数据库/设备同步复核](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/cross-module-report-verification-2026-09-28/lifecycle-sync/lifecycle-sync-verification.md>)、[AI/钱包/传输复核](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/cross-module-report-verification-2026-09-28/ai-wallet/ai-wallet-verification.md>)。

## 最有价值的新增证据

### 重复恢复与并发重连是两种不同问题

真实 SessionManager 的计数验证：两次缓存 restore（第二次进入时已 ready）共调用 `connect=4、fetchMe=2、fetchCredential=2`。这是 A05 的重复工作证据，不证明四条真实连接。

A06 另用真实 SessionManager 的断线回调和重试定时器：第一次重连的 connect 被保持 pending，再次断线后推进虚拟时间，出现两个同时 pending 的登录调用。账号代次没有变化，因此现有跨账号保护不会挡住这两个同代次尝试。

关键位置：[SessionManager.restore](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/session/session_manager.dart:93>)、[签名刷新再次 connect](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/session/session_manager.dart:319>)、[未登记自身的重连](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/session/session_manager.dart:355>)。

### 旧校准任务能压掉新会话的校准

A08 验证了旧任务成功、旧任务失败两个完成顺序：新会话已 scheduled 后，旧任务把共享 phase 改为 completed 或 idle，新任务醒来后不再发起 fetch。部分内部数据写入有 owner 检查，不足以保护外层 phase、任务释放与错误回退。

### “网络连接着”不等于业务可用

A02 和 A03 的运行证据分别来自真实公共拦截器和真实探针/选择器，不是复制判断公式的小脚本。TCP A01 的实际 socket 拆包也确认：本来合法的中文事件在字节被分开后触发 FormatException，字符串层的换行缓存无法修复已经失败的解码。

### A16 的结论必须按当前工作区更新

[revokeMsg 当前失效分支](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:8228>) 已恢复准备状态并于 8245 行返回。现有 `chat_session_recovery_test.dart` 中“revoke stops before SDK if its view changes during durable preparation”回归通过。

这项修复来自审计前/期间已有的工作区修改，本轮没有再次改动它。原报告基于固定 main 提交，不能直接把其缺陷清单等同于当前脏工作区。

## 上一轮仍保留的补充发现

以下没有被新报告取代；A10 已在上面合并。完整证据仍在[上一轮报告](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/program-performance-audit-2026-09-28/audit.md>)。

| 用户场景 | 保留结论 | 本次合并说明 |
|---|---|---|
| Android 发图 | 常规压缩缺解码前采样预算，图片准备并发 2 | 两张 48MP 原始 ARGB 位图理论约 366 MiB；不是已测手机峰值/OOM。 |
| iOS 多图 | 系统 picker 返回前整批导出并重编码 | 发生在 Dart 压缩队列前，需量化“点击完成到收到文件列表”。 |
| 聊天滚动 | 无变化的已读确认撤销去重签名，重复提交旧尾段 | 本轮重新运行生产列表 + SQLite 诊断仍复现：30 次轻滚动、37 次重复事务、2,997 个旧 ID，未读仍为 1。前轮为 38–43 次，调度影响次数但不改变机制。 |
| 会话列表 | SDK 请求长期不完成会占住首屏/分页单飞 | 前轮虚拟 60 秒仍 loading；重试加入旧 Future。与 A06 形成两种不同缺口：有些入口并发，有些入口永远等待。 |
| 消息洪峰 | 内层队列有限，外层等待准入无总量上限 | 前轮上限 8、10,000 个事件仍保留 9,999 个待办。不能简单丢弃消息解决。 |
| 大通讯录 | 分批投影仍有重复从头扫描和逐人线性插入 | 与 A11 设备通讯录上传是不同链路，不能合为一个功能。 |
| 搜索 | 降级扫描缺总预算；旧本地结果可迟到写回 | 前轮真实搜索模型已验证退出清空后旧结果重新出现。 |
| 钱包/红包 | 全局 WalletStore 缓存缺账号/请求代次保护，筛选请求可被丢弃 | 与 A15 隐藏页面刷新不同。部分 WalletController 有身份隔离，不代表所有 WalletStore 消费者都受保护。 |
| 图片预览与恢复 | 无尺寸元数据的大图保护失效；Android 未接回 lost-data | 前者是解码风险，后者是系统回收宿主后的恢复缺口。 |
| 诊断 | 启动 Profile 阶段输出受 kDebugMode 条件挡住 | 当前又新增了聊天恢复诊断，不能笼统说整个程序没有日志。 |

本轮对前轮九个核心源码文件进行了 SHA256 对比，均未变化；涉及聊天相关其他新修改，另补跑了上面的滚动诊断。对比记录见 `prior-core-source-comparison.json`。没有反复重跑无关且已通过的全部测试。

## 合并后的处理顺序

**先修确定的控制流/协议缺口**：A01、A02、A03、A04、A06、A08、A13，加上前轮钱包/搜索结果所有权问题。这些具备清晰的可控输入和行为验收，适合小范围修改。A16 核心从本批移除，保留其回归。

**同时针对用户四个主要场景处理资源与等待**：图片解码预算、滚动重复 ACK、会话加载恢复、首屏状态机（A10）。A05/A07 的调用与调度要分冷启动、短前后台、断线、交互期设计，不用增加固定延迟掩盖。

**对依赖外部条件的项先建立可观测性并做针对性场景验证**：A09 原生 close 活性、A11 后端增量契约、A12 相册规模、A14 长文本/用户离底、A15 离屏钱包事件合并。需要测量并不意味着已确认的无效循环/额外上传可以忽略。

**A17 单独高优先级处理**：确认正式安装包的实际 endpoint、HTTPS/TLS 与证书验证；区分读相册权限和上传备份的明确选择。不要为了本次审计测试而对真实用户开启备份或上传数据。本轮没有执行这些操作。

统一保留：账号隔离、消息连续性、精确已读、撤回/删除记录、订单幂等与必要鉴权。不能清空全部数据库、无限重试、放开全部交互门槛或直接重用尚未关闭的数据库句柄。

## 运行验证的边界

- 本轮测试使用真实项目组件配合可控 Future、虚拟时钟、本地 socket/HTTP 服务或接口替身；没有登录真实账号、发消息、支付或向线上制造负载。
- 本轮新增诊断 21 项、已有相关回归 22 项、前轮滚动复核 1 项，共 44 项断言通过。新增诊断用于捕获缺陷及控制条件，已有回归用于确认现有保护；详见 [验证汇总](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/cross-module-report-verification-2026-09-28/verification-summary.md>)。
- 不能把“诊断断言通过”等同于“缺陷已修复”。没有新真机 Profile、ANR、OOM、iOS 关库堆栈或线上发生率数据。
- 这不是全套测试通过声明：前轮 71 项已有测试中的 3 个源码字符串契约失败仍保留记录，本轮未修改它们。
- 安装包与提交映射仍未确认。上一轮连接环境中的 `3.0.1+20` 不是所有用户设备，也未证明包含当前未提交修改。

## 来源与图分析

用户原报告保存在本目录 `source-report.txt`；仓库 HEAD 仍为 `0e7aa83bc5b096a99ff8bb424842404a3c901cb7`。本报告以当前工作区为准，保留其他任务的未提交改动。本轮只新增报告、诊断测试和证据，不修改业务源码、不提交、不部署。

先用 GitNexus query/context 定位，再核对当前源码和测试。初始外置索引为上一轮新生成版本，旧 MCP 曾存在乱码/错误映射，因此使用 CLI。审计中再次刷新外置索引；最终元数据和文件指纹见本目录验证汇总。图中的静态调用覆盖不等于所有运行时调用，尤其 Dart 回调、跨语言和截断流程。

官方语义已重新核对：未完成/非法 UTF-8 序列在默认单次解码下会抛异常，应使用可跨块保存状态的流转换；参见 [Utf8Codec.decode](https://api.dart.dev/dart-convert/Utf8Codec/decode.html) 与 [Utf8Decoder](https://api.dart.dev/dart-convert/Utf8Decoder-class.html)。`Future.timeout` 结束等待但不取消原任务，参见 [Future.timeout](https://api.dart.dev/dart-async/Future/timeout.html)。性能结论仍需代表性实体设备的 Profile，参见 [Flutter 性能分析](https://docs.flutter.dev/perf/ui-performance)。这些框架资料只支持语义和验证方法，不替代项目实测。
