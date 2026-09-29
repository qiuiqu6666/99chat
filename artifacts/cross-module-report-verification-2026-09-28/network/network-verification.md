# A01（TCP）、A02、A03、A04、A16 当前工作区核实

核实日期：2026-09-28。HEAD：`0e7aa83bc5b096a99ff8bb424842404a3c901cb7`。以当前工作区为准；聊天模型有其他任务的未提交修复。本次未修改产品代码或原有测试，只新增本目录诊断文件。当前文件 SHA256 见 `source-hashes.json`。遵循 graph first，GitNexus 用于导航，结论逐条回到当前源码及真实组件测试核对；图输出见 `graph-contexts.txt`、`graph-ensure-connected.txt`。

| 项目 | 结论 | 当前证据 |
| --- | --- | --- |
| A01 TCP 分块 UTF-8 | **confirmed** | 真实 loopback TCP 把中文多字节字符拆开，生产连接组件产生 2 次 FormatException，整条事件未交付 |
| A02 取消算节点故障 | **confirmed** | 真实 CancelToken 取消 3 个 ApiClient 请求，公共 onError 最终调用 transportFailure 3 次 |
| A03 503 探针正常 | **confirmed** | 真实 probeNode 请求本地 HTTP 服务：503→normal/14ms，200→normal/403ms；真实选择器选择 503 节点 |
| A04 auth_fail 后 force 恢复 | **confirmed** | 真实服务收到 auth_fail 后换合成凭证并 force，连接数仍 1、ready=false；stop/start 后连接数 2、ready=true |
| A16 失效撤回缺少退出 | **fixed**（仅该明确缺陷） | 当前 stale 分支已有 return；现有延迟落盘→切会话组件回归通过、SDK 未调用且写入 restore |

## A01 — TCP 逐块解码仍存在

- 当前位置：`lib/src/services/friend_realtime/friend_realtime_connection_io.dart:43-47`，尤其 **44**；字符串换行缓冲在 **51-63**，晚于字节解码。
- 触发：服务器发送原始中文/emoji 的 UTF-8 JSON，接收块从一个多字节字符中间断开。全部 ASCII 转义时不触发。
- 实测直接导入生产 `FriendRealtimeConnection`，本地服务器先发多字节字符的首字节，等待客户端实际错误回调后再发剩余字节，因此不依赖操作系统偶然分片。捕获 **2 个 FormatException**，原事件没有进入 `onLine`；随后完整 ASCII 控制帧正常交付，`onDisconnected` 仍为 **0**。
- 机制：监听器内部抛出的同步异常逸出至 Zone；`onError` 是流错误处理器，不能覆盖这次回调自身抛错。不能将结果夸大成必然进程崩溃；此次确认的是帧丢失、错误逸出且未进入断连恢复。
- 范围：应用自建业务 TCP；不等于腾讯 IM 原生消息通道损坏。AI SSE 由另一个审计子任务核实。
- 修复方向：对整条字节流使用有状态 UTF-8 解码器，然后按行解析；定义错误与过长帧的退出策略。不要以 `allowMalformed` 掩盖合法 UTF-8 分块问题。

## A02 — 主动取消仍污染节点健康计数

- 当前位置：`lib/src/api/api_client.dart:283-288` 无响应即 true，`224-225` 将其传给 `onTransportFailure`；`lib/src/services/api_node_service.dart:162-163` 接入节点计数，阈值在 **54**，计数/触发在 **176-186**，测速选择在 **189-201**，换节点后 TCP 强制恢复在 **210-226**。
- 实测使用生产 `ApiClient.dio`、真实 `CancelToken.cancel`，仅替换网络 adapter 为等待取消的受控 adapter；没有发往线上节点的网络请求。连续 3 次取消最终经生产公共错误拦截器产生 **3 次 transportFailure、0 次 success**。
- 注意取消的调用方 Future 可以早于错误拦截器完成；测试明确等待 3 次分类完成，避免把异步到达误判为计数漏失。
- 外部症状：有条件地触发无必要测速/切节点和自建 TCP 重连。不是任何 3 次取消都必然切线：节点服务须已 hydrate，计数期间不能被成功响应清零，且需存在可切候选。成功会清零，见 `api_node_service.dart:168-172`。
- 本次运行验证到了错误分类回调；完整自动切线以当前源码链确认，没有调用目录内线上节点进行端到端切线实验。
- 修复方向：先排除主动/过期取消再记真实传输失败，并将结果绑定原请求的节点与代次，防止旧结果污染新节点。

## A03 — 快速 503 仍成为正常最快候选

- 当前位置：`lib/src/services/api_node_service.dart:264-286`；**272** 接受任何 HTTP 状态，**284-286** 无条件返回 normal。错误分支收到 response 也 normal，见 **291-294**。选择器 **110-132** 仅检查 normal 和耗时；对照公共 API 的 **api_client.dart:287-288** 将 502/503/504 算故障。
- 实测直接调用生产 `probeNode`，真实 loopback `HttpServer` 先返回 503，再模拟较慢 HTTP 200。得到 **503=normal/14ms，200=normal/403ms**，真实 `pickFastestNormal` 选择映射为 `cn` 的 503 结果。
- 该测试证明状态分类及候选排序缺陷，不声称探针返回的任意 HTTP 200 内容已代表完整业务健康。502、504 未逐个运行，但与 503 走相同的无条件接受分支。
- 原报告同时建议合并并发 probeAll：当前 **230-232** 确实在 `_probing` 为 true 时立即返回而非等待同一个 Future；`_failoverAfterFailures:191-195` 随后可能读取旧的 `_probeById`。该次级并发风险仅做源码确认，未额外访问线上节点注入。
- 修复方向：区分可达性与服务可用性，对健康状态和轻量响应契约做判定；共享进行中的探测 Future。

## A04 — force 无法越过 authFailed，stop/start 可恢复

- 当前位置：`lib/src/services/friend_realtime_service.dart:113-131`；**118-120** 提前退出，之后 **125-126** 的 force 清除不可达。认证失败处理 **312-324** 设置标志、取消任务并关闭连接；`stop:154-170` 中 **157** 清除标志。
- 实测启动生产 `FriendRealtimeService`，仅以 `--dart-define=REALTIME_TCP_BASE=http://127.0.0.1:<临时端口>` 将 TCP 引向本地测试服务器。服务器对第一次认证返回 `auth_fail`，替换合成 token 后调用 `ensureConnected(force:true)`：**connections=1、authFrames=1、ready=false**。随后 `stop/start`：**connections=2、authFrames=2、ready=true**，真实收到 `auth_ok`。
- token 为测试用合成值，验证恢复控制流，不涉及生产登录凭证。测试在连接前强制校验目标为 loopback，并确保 ApiNodeService 未 hydrate，避免配置被节点目录覆盖。
- 原报告明确说 stop 会恢复，该限定正确。不能写成“只能杀进程”；调用方若已有 stop/start 补偿则能绕过此缺陷。并非所有登录恢复都已证明失败。
- 原报告的阶段超时风险仍有源码依据：**221** 是连接建立 3 秒超时；认证发送 **230-245** 后没有独立 auth_ok 截止时间；`_startPing:257-263` 只定期发送，`pong:325-326` 仅返回。本次没有长时间无 auth_ok/无 pong/真实移动网络半断实验，不能由此给线上挂起时长或发生率。
- 修复方向：按凭证代次允许确定的新凭证恢复，保留对相同无效凭证的终止策略；为认证和心跳建立阶段期限与连接代次校验。

## A16 — 当前已修复具体 stale revoke 控制流，广义视口症状仍待验证

- 当前位置：`third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:8165` 的 `revokeMsg`；异步准备 **8211-8218** 传入 `commandIsCurrent` 与 20 秒期限；失效判断 **8228**，恢复原 scope **8231-8236**，finally 完成投影 **8237-8240**，**8245 return null**，因此不会继续到 **8255** 的本地提交或后续 SDK 撤回。
- 跑了现有真实组件回归 `test/chat_session_recovery_test.dart:306`：`revoke stops before SDK if its view changes during durable preparation`。测试延迟 repository 写入，中途切换 conversationID，放行后确认 `sdk.revoked` 为空、最后一条 mutation 为原会话 restore。**1/1 通过**，见 `revoke-stale-scope.log`。
- 这项修复来自本次审计前已有/并行任务的未提交工作，本审计没有实现它。
- 该结果只把“失效撤回缺少退出”标为 **fixed**。原 A16 标题中的白屏、透明/禁触摸 gate、图片返回/键盘/分页组合和串行任务阻塞没有由这条测试全面覆盖，应保留为 **未证实的场景排查**，不能将整组视口风险标成全已修复或已复现。

## 复现与限制

新增的 `network_component_probes_test.dart` 共 3 个测试，`tcp_auth_force_probe_test.dart` 共 1 个测试，加现有撤回回归 1 个，最终 **5/5 通过**。这里网络测试的通过意味着成功复现当前缺陷，不代表产品已修好。

命令入口：

```powershell
flutter test --no-pub artifacts/cross-module-report-verification-2026-09-28/network/network_component_probes_test.dart --reporter expanded
flutter test --no-pub --dart-define=REALTIME_TCP_BASE=http://127.0.0.1:49325 artifacts/cross-module-report-verification-2026-09-28/network/tcp_auth_force_probe_test.dart --reporter expanded
flutter test --no-pub test/chat_session_recovery_test.dart --plain-name 'revoke stops before SDK if its view changes during durable preparation' --reporter expanded
```

TCP 端口使用本机空闲端口，报告命令中的端口仅示例。日志分别见 `network-component-probes.log`、`tcp-auth-force-probe.log`、`revoke-stale-scope.log`。测试为桌面 Dart/Flutter 真实组件和本地网络故障注入，不是 Android/iOS 真机帧率或线上现场。未验证真实手机后台挂起、TLS、全部 UTF-8 切分组合、认证无应答、丢 pong、节点完整切换及 A16 全部视口组合。没有据此推导线上比例、P95 或 ANR 数值。
