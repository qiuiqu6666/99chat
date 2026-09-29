# 两轮审查合并：验证记录

日期：2026-09-28。对应主报告：[merged-audit.md](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/cross-module-report-verification-2026-09-28/merged-audit.md>)。范围是复核并合并结论，没有修复、提交或部署业务代码。

## 本轮执行

**新增诊断 21 项 + 已有相关回归 22 项 + 上轮滚动复核 1 项 = 44 项断言通过。** 新增诊断多数断言当前缺陷存在，也包含正常控制条件；这不代表产品已修复或全套测试均通过。

| 范围 | 数量 | 对应证据文件（本目录内） |
| --- | ---: | --- |
| 真实 TCP 拆包、取消分类、HTTP 探针 | 3 | `network/network-component-probes.log` |
| TCP 认证失败后 force 与 stop/start 对照 | 1 | `network/tcp-auth-force-probe.log` |
| 会话重复恢复、并发重连 | 2 | `session/session-verification.log` |
| 关系校准截止时间、旧成功/失败覆盖新代 | 3 | `lifecycle-sync/execution-results.md`，为实际执行结果的人工记录 |
| iOS 生命周期关库依赖持续未完成 | 1 | `lifecycle-sync/execution-results.md`，为实际执行结果的人工记录 |
| 联系人上传、超限视频哈希、两种相册授权 | 4 | `lifecycle-sync/device-sync-repro.log` |
| AI 字节分片、两类状态竞争及控制条件、滚动、隐藏钱包、默认传输配置 | 7 | `ai-wallet/test-output.txt` |
| 已有会话/启动预算/生命周期回归 | 21 | `session/existing-session-tests.log` |
| 已有失效撤回退出回归 | 1 | `network/revoke-stale-scope.log` |
| 前轮聊天滚动与真实 SQLite 诊断重跑 | 1 | `prior-scroll-ack-recheck.log` |

执行环境为本机 Flutter/Dart，Flutter 入口 `E:\flutter\flutter\bin\flutter.bat`，测试使用 `flutter test --no-pub ... --reporter expanded`。各分报告保留具体命令及测试文件；认证恢复测试还以编译期参数指定本机临时 TCP 端口，并校验目标是 loopback。

复核只使用合成数据、可控 Future/时钟、本地 socket/HTTP 服务和平台/网络边界替身，没有登录真实账号、付款、读取用户相册或向生产服务上传测试数据。真实组件测试不等于真机性能测量；A12 使用合成超限大小元数据与小型文件流，不能当作 100MiB 实际视频压测。

## 前轮结果仍须保留

前轮现有性能/启动/生命周期相关测试为 **71 项：68 通过、3 失败**。三个失败是旧源码字符串契约与当前实现不匹配，见 [前轮完整报告](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/program-performance-audit-2026-09-28/audit.md>) 及其 baseline 日志。本轮未修改这些断言，也没有把 44 项通过写成全套回归通过。

前轮九个核心源码 SHA256 对比无变化，记录在 `prior-core-source-comparison.json`。聊天模型存在其他任务的新增修改，因此另重跑旧历史滚动诊断：100 条旧历史、1 条未进入阅读范围的新消息，30 次轻滚动得到 37 次重复确认事务、2,997 个旧 ID，未读仍为 1。调度使具体次数与前轮略有不同，重复工作的机制仍在。

## 源码与索引基准

- HEAD：`0e7aa83bc5b096a99ff8bb424842404a3c901cb7`；结论以带原有未提交修改的当前工作区为准，不把 HEAD 当作完整源码快照。
- 用户原始文本：`source-report.txt`；原始报告的 17 个编号保留，方便逐项追溯。
- 最终所引源码指纹：`reviewed-source-manifest.json`。这是报告收尾时的快照；不表示所有测试都在同一时刻运行。
- 网络子审查另保存了运行时附近的 `network/source-hashes.json`。
- 图定位首先使用上一轮外置索引 `D:\codex-task-cache\program-performance-audit-full-20260928`，时间 2026-09-27 17:57:41 UTC。
- 本轮收尾时刷新外置索引至 `D:\codex-task-cache\cross-module-verification-20260928`，时间 **2026-09-27 18:14:42 UTC（台北 2026-09-28 02:14:42）**，3,246 文件、76,272 节点、174,421 关系、654 流程。摘要见 `graph-metadata.json`，完整执行见 `graph-refresh.log`。
- 旧 MCP 曾出现错误路径/乱码映射，因此采用 CLI 图定位并逐条核实当前源码。图定位只辅助寻找调用链；空结果、动态回调及跨语言缺边不等于无影响。未编辑产品符号，未执行提交。

## 仍未取得的现场证据

本轮没有新增代表性 Android/iOS 真机 Profile、ANR/OOM 堆栈、iOS 原生关库挂起记录、发布包实际节点配置或线上问题发生率。安装包与本工作区的精确提交映射尚未确认。因此报告区分了“代码机制成立”“可控条件下复现”“已修分支”和“线上贡献待测”，没有给出未经测量的性能提升比例。
