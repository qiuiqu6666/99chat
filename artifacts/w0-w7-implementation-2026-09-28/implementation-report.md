# 99chat W0–W7 实施与验证记录

范围：执行 `docs/plans/2026-09-28-gitnexus-plan-cross-module-stability-repair.md` 的 W0–W7；W8 不在本次范围。原计划未改写。代码实施与针对性回归已完成，平台、后端合同及发布验收仍有下述未完成项。

## 基线与归属

- Git 基线：`0e7aa83bc5b096a99ff8bb424842404a3c901cb7`。
- 工作分支：`codex/w0-w7-stability-repair`；未 stage、commit、发布安装包或部署。
- 用户反馈最多的 Android 包：`https://image.99chat.vip/app-release.apk`。只读检查得到包名 `chat.chat99.chatpro`、versionName `3.0.1`、versionCode `20`、minSdk 24、targetSdk 36。
- APK SHA256：`17AF7112DF7AE719BBECEF899720237012F1F597F4FC675AA0DC06B689D00ECA`；350,324,280 字节。版本号相同不能证明 APK 来自本工作区的同一 commit。
- 开始时已有大量未提交改动；实施前保存了 135 个相关路径的原始字节。执行期间用户明确要求其他任务继续并行修改，本轮保留其成果，不宣称整个当前 diff 均由本任务产生。最终清单记录验证时的文件哈希。
- 原始审计中用于证明缺陷的测试文件保持原样。新增正式测试断言修复后的行为；红测失败与编译/夹具失败分开记录。

## 实施范围

| 工作包 | 已落地的行为 | 验证/边界 |
| --- | --- | --- |
| W0 | 受控 Debug/Profile 诊断；构建版本/标识；登录并发、数据库关闭阶段、图片准备与恢复等阶段观测；缺陷转正式回归 | 未把单元测试计时当真机帧率、内存收益；Release 不开放该详细控制台诊断 |
| W1 | TCP/SSE 有状态 UTF-8；取消请求不触发节点失败；旧节点结果不污染新节点；健康探针验证公开响应合同；探测合并；实时认证/pong 有期限并区分前后台 | 没有凭空设置协议帧大小，也没有修改 W8 的节点加密合同 |
| W2 | 已就绪回前台只鉴权检查；SDK 初始化/登录/退出共享真实串行任务；新登录等待旧清理；签名刷新按代次/登录版本隔离；SessionStore 整操作跨实例串行 | UI 超时不释放仍在运行的 SDK 槽；保留踢下线、停用、过期及 IM06 初始化 |
| W3 | 关系、钱包、搜索与 AI 结果绑定账号、代次和具体请求；旧 success/error/finally 不覆盖新状态；钱包后台续页通知本地刷新；AI 终态统一、保留流式空白 | 新增账号切换、迟到请求、空服务端订单 ID、后台第二页等故障回归 |
| W4 | 先显示可恢复启动界面；未完成与失败分开提示；可选入口预热延后并门控显示；会话读取 8 秒界面期限，每种会话类型保留一个物理请求；精确 ID ACK 的 noChange 去重 | 不推进超时页游标，不把等待中当无账号；30 次微滚动重复 SQL ACK 从基线 39 次降至 0，测试未读仍为 1 |
| W5 | Android 按像素采样；图片准备/上传分开额度；预览双轴限制；iOS 原生串行导出；Android 恢复数据先暂存/journal 后确认清缓存；同账号原目的地确认恢复 | iOS 无 Mac 编译/真机证据；HEIC 默认输出合同保留 JPEG；共享插件不同调用不统一套聊天 2560 限制 |
| W6 | 搜索分片 3 页/150 条/250ms 下一页启动预算并可继续；AI delta 合并；交互期校准延期；通讯录游标与几何发布；钱包隐藏只记 dirty；超限视频哈希前跳过 | SDK 全量准入、联系人生产差量、新照片进度存储的启用门槛见下表 |
| W7 | 生命周期只保留最新状态；真实 close 只有一轮；ready/deferred/cancelled 有界界面等待；原生关闭失败不假成功；晚到 open 保留实际关闭保护；聊天 exact-token 完成与 UI 期限分离 | 不清库、不强行重开未知句柄、不因超时重发远端命令；自动重建仍需 iOS 原生/真机合同 |

## 保留的启用门槛

| 能力 | 当前状态 | 原因 |
| --- | --- | --- |
| SDK 实时消息全局有界准入/溢出压缩 | 未启用 | 尚无所有事件类别的原生重放或先持久化保证。已持久 Inbox 恢复支持非等待式有界准入，满载延期不标完成；不能把它称为所有实时回调已全局有界 |
| A11 联系人生产差量 | `deviceScopedDeltaEnabled=false` | 只读核对后端当前按用户+localContactId，尚缺设备隔离和 complete 幂等合同。保留兼容全量发送；本地 diff/采集失败分类已实现 |
| A12 按项照片进度 SQLite 存储 | `enabled=false` | 实现及迁移/生命周期测试已接入，但启用依赖 W8 明确同意迁移。本轮仅独立启用超 100MiB 视频哈希前跳过 |
| iOS 关闭异常后的自动重建 | 未增加 | 未确认真实句柄安全关闭时保持降级说明和保护，不绕过 guard |

恢复提示只展示当前账号的草稿，不自动发送。通用非聊天入口暂存后提示回原功能重新选择；不能假称所有业务表单都能完整重建。已认领但发送确认不明的记录不会自动重试，以避免重复发送。

## 验证记录

以下按工作组列出，既有测试有交叉，不把多次执行相加当作独立场景总数。新增回归均通过；全仓旧测试及静态检查并非全绿。

| 验证集 | 结果 | 证据 |
| --- | --- | --- |
| 核心网络、会话、启动、数据库合同 | 12 文件 **55/55**；后续入口重试、媒体/历史覆盖晚到 open 及原有入口/搜索复验 **20/20**。去重后 27 新增、44 既有通过 | 总证据目录 `root-final-tests.log`、`root-final-followup-tests.log` |
| 可独立提交的数据库测试夹具 | 从原始审计目录抽离支持类后，受影响测试 **8/8** 再通过 | `root-portable-fixtures-tests.log` |
| 聊天搜索、会话期限、ACK、持久 Inbox 准入 | **21 新增通过**；扩展集 121 通过、3 个已复现的基线失败 | `chat-final-regression-1.log`、`chat-baseline-ab.log` |
| W7 聊天 exact-token 收尾、撤回/删除等待 | **10 新增 + 34 既有 = 44 独立场景通过**；其中最终联合集 24/24 | `w7-chat/green-final.log`、`w7-chat/green-1.log` |
| 关系、钱包、通讯录、备份门控、凭证及入口账号隔离 | **32 新增 + 28 既有通过**；另 1 个 HEAD 基线失败 | 数据组 `final-counts.json`、`implementation-status.md`、`green-entry-service.log` |
| AI、图片准备、预览与选择器恢复 | **21 新增 + 98 既有 = 119/119**；最后账号重复通知修正后 AI 11/11 再通过 | 媒体组 `media-ai-final-green.txt`、`ai-final-boundary-green.txt` |
| Android 相册插件 | Java 编译通过，**4/4 原生缓存恢复测试通过** | 媒体组 `media-native-android-final.txt` |

数据回归包含真实 WalletApi → SQLite → controller 后台续页、2500 联系人页面恢复、1k/5k/10k 算法工作量与跨实例凭证序列。100MiB 视频场景使用合成大小证明未打开哈希流，不是设备吞吐测试。Android 原生测试使用可用 Java 17 环境的 SDK 24 Robolectric，不等于 SDK 36 或手机验收；iOS 仅源码/合同复核，未运行 Xcode 构建。

完整 `flutter analyze --no-pub` 已执行但未全绿：扫描得到 7896 条诊断（含 3656 error、1130 warning）。大量来自历史审计/备份 `.dart` 文件、嵌套第三方包各自分析环境不能解析应用反向引用；不能据此宣称所有 error 都无关。应用 `lib/` 在该次扫描为 0 error。两份原有正式测试夹具的 3 个 API 签名错误已最小兼容修正，未删除行为断言，对应测试已通过。

随后 `dart analyze lib test` 为 **0 error、975 条其余诊断**。最后改动的 10 个路径定向分析为 **0 error、0 warning、6 info**；媒体 16 路径为 0 error、1 个既有 warning、15 info。不能将这些范围的结果表述为全仓静态检查通过。证据：`flutter-analyze-final.log`、`app-active-analyze.log`、`final-followup-analyze.log` 及媒体组分析记录。

已确认的旧失败保留原断言并单列：`history_visible_deferred_progress_test.dart:350,415,468` 未读期望分别为 1/4/2，基线实际为 0/3/1；`home_tab_body_lifecycle_test.dart:340` 基线期望 7、实际 0；`sangong_my_config_test.dart:35` 的旧期望缺少既有 `imGroupLedgerId` 空值键（模型和测试均与 HEAD 一致）。这些结果不算本轮通过项。

基线对照只在 D 盘隔离镜像替换保存的基线文件，未回滚工作区。首页旧失败使用补全资源后的 `home-baseline-clean-ab.log` 为证。新网络回归在该镜像中 3 项实际变红；W7 最终新增测试选择 4 项对旧实现运行，均因行为断言失败。W7 `green-1.log` 证明 34 条既有回归通过，该批另有 10 个夹具失败，新增测试最终通过以 `green-final.log` 为准。另有会话退出并发、原生 close 错误、AI 账号/空白合同等修复前红测，均保留日志；编译或测试夹具失败不当作缺陷红测证明。

## 完成标准对照

| 原计划验收项 | 本轮结果 |
| --- | --- |
| W1–W8 硬行为回归 | W0–W7 已实施并验证本轮新增场景；W8 按用户范围未实施，旧失败见上文 |
| 无跨账号回写、错误已读、丢消息或重复命令 | 已覆盖对应竞态与故障回归；不以有限测试保证所有真实运行路径，普通 SDK 全局准入仍受重放合同限制 |
| 四个主场景达到 W0 真机预算 | 未验收；缺 Android 同数据 profile 前后对照及 iOS 真机数据 |
| 后端及 iOS 门槛落实 | 代码保留关闭开关和降级保护；后端设备/幂等合同、iOS 构建与真机验收未完成 |
| 灰度及回退验证完成 | 未进行发布、灰度或安装包级回退演练 |

## 证据位置与复验

- 本轮总证据：`D:/codex-task-cache/99chat-w0-w7-implementation-20260928/`。
- 数据组：`D:/codex-task-cache/99chat-w0-w7-data-logs/`。
- 媒体/AI 组：`D:/codex-task-cache/99chat-w0-w7-implementation/`；其中 `media-ai-final-handoff.md` 列明完整 Flutter/Android 复验命令。
- `source-manifest.json` 记录本轮涉及的 211 个源码、测试、依赖路径的最终 SHA256；共享路径不表示本任务独占归属。第一轮聊天的 bounded history 旧 receipt 已被后续 W7 receipt 覆盖，其余最新工作组 receipt 与最终文件一致。
- GitNexus 编辑前影响分析：首轮 `root-impacts/`，第二轮 `root-wave2-impacts/`，以及各工作组的影响清单。HIGH/CRITICAL 已在编辑前报告；UNKNOWN 结合实际消费者与框架入口核对，未按“无人使用”处理。
- 最终索引与检查已完成：`status=up-to-date`、runner schema 4 / `current`、`incompleteReasons=[]`；资源返回的 commit 与 runner receipt 和状态文件一致。GitNexus 1.6.12、Node v20.19.3；索引 commit 为本记录基线，源工作区包含本轮未提交改动。完整身份见 `graph-status.json`。
- 紧接新索引执行 `detect_changes(scope=all)`：**88 个已跟踪改动文件、428 个符号、8 条受影响执行流，risk=high，partial=false、truncated=false**。8 条流程均经节点探测/实时连接到 token、ready 或 HTTP 配置，符合本轮高影响修改范围。完整符号及流程见 `graph-changes.json`；26 个不在本任务来源清单中的符号路径已在 `verification-results.json` 分别标记为既有或其他任务并行改动，不据此扩大本轮修改范围。
- 该版本 `detect_changes(all)` 以 `git diff HEAD` 为输入，不包括未跟踪文件；本轮清单中的 155 个未跟踪路径另以文件清单、新索引和定向测试核对，不能把 88 文件数视为全部交付文件数。FTS Windows 文件异常后使用图索引；分析器流程枚举、跨语言和候选上限仍有覆盖边界，未列出的执行流不等于不存在。
- 最终 `git diff --check` 通过。211 个清单路径在交付校验时 **0 漂移**。并行任务仍可继续变更其他代码，结果只绑定记录中的时点和 SHA256，不宣称工作区已整体冻结。结构化结果见 `verification-results.json`，全局工作区证据见总证据目录 `final-provenance.json`。
- Windows 的 C 盘空间不足，测试临时目录和原生测试 Maven 缓存放在 D 盘；原 `build/test_cache` 整体保留并移到总证据目录 `flutter-test-cache/`，原位置为 Windows junction，后续测试已通过。没有清理用户文件，也未改全局 Pub Cache。新依赖补丁保存在仓库 `third_party/` 并由 lockfile 绑定。

本轮未做原计划建议的分批自动提交：开始时已有未提交内容，用户要求其他任务持续在同一目录工作，整文件提交会混入其他任务成果。当前仅保留工作区改动、来源清单及验证证据；未 stage/commit。正式计划 SHA256 仍为 `43493599907ef2d759deee209e9e3d941b6dbb8c01752e721d2707b6e8d6443a`。

仍需 Android 3.0.1+20 同数据集的 profile 对照和 iOS 真机验收：启动、会话可交互、长聊天滚动、1/2/9 张大图/长图、后台相册宿主回收、反复锁屏/回前台。当前没有这些实机结果，未生成或宣称可直接发布的完整安装包。
