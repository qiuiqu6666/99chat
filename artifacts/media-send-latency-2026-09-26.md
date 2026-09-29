# 图片/视频气泡出现后发送慢：链路核查

更新：已收到现场日志并修复一处恢复扫描竞争；最新结论、修改和验证见文末“收到实测日志后的更新”。前半部分保留首次仅有代码检查时的记录。

## 结论边界

用户已确认单张普通图片也会出现。当前工作区能确认本地占位气泡在处理和上传前就插入，不能以气泡出现推断已经开始上传。没有拿到该用户的真机阶段日志、文件大小/格式、网络或版本，不能把某个代码风险写成该用户已经证实的根因，也不能宣称本次诊断改动已提升真实发送速度。

## 当前实际路径

1. 系统相册返回本地文件 → 插入图片/视频占位 → 至多等待约 32 ms 给 UI 一帧机会。
2. 图片：读取尺寸 → 判断是否压缩 → 压缩准备池 → 稳定文件保存 → SDK 创建图片消息。
3. 视频：稳定文件保存 → 并行读取时长/生成封面 → SDK 创建视频消息。读取时长时的播放器初始化设置了 2 秒超时，但这不等于整个元数据阶段有截止时间；封面生成底层 Future 无应用层等待上限。
4. 共用发送协调：取得本地消息写入租约 → 恢复文件引用/保存 → 加密发送记录 → Prepared、DispatchIntent、Sending 持久化 → 上传槽位 → 腾讯 SDK 上传并发送 → 本地结果提交 → UI 确认。
5. 大附件另有后端上传路线；普通小图的路径检查仅查询文件和已缓存的分流策略，不会为它先请求附件策略 HTTP。图片默认原生限制 28 MiB、视频 100 MiB，后端下发策略可能改变分流边界。

## 已证实的等待点与已排除的简单解释

| 点位 | 源码事实 | 能否认定为这次根因 |
| --- | --- | --- |
| 图片压缩 | 小于等于 1200 KiB 的 JPEG、GIF、已准备的图片跳过压缩；其他格式可能进入压缩。原生压缩调用没有应用层期限，准备并发为 2。 | 未证实；不能说每张普通图都在长时间压缩。 |
| 视频封面 | 与时长查询并行，但 Future.wait 仍需等封面完成。最多重试 3 次不等于每次有截止时间。 | 明确的长期等待风险；没有真机耗时证据。 |
| 本地发送准备 | 租约、媒体恢复引用、密钥读取/加密和多次事务都位于 SDK 调用前。 | 单张也经过，需实测区分磁盘/数据库等待。 |
| 全局上传槽位 | 图片 3、视频 1、文件 2，同类型跨会话共享。某次只发送一张也可能等前面的同类任务。SDK 派发超时 3 分钟；超时后保留结果待确认语义。 | 可能解释单张被前序任务拖慢，未证明该用户当时有积压。 |
| SDK/网络 | 原生 send Future 包含上传及消息确认；上传进度 100% 不等于对端可见或消息发送成功。 | 必须结合进度里程碑和回调时间判断。 |
| 重复大文件复制 | 当前 Outbox 已借用受管理的稳定媒体文件并保存引用；正常路径不是再次全量复制。 | 不应将旧实现的问题重复报告为当前根因。 |
| 后台相册上传竞争 | 当前 beginForegroundMediaWork 会取消后台相册上传并延后后续工作。 | 不能无证据归咎为当前必然抢带宽。 |

## 本轮落地：补齐诊断

- 在 SDK 创建消息、图片准备队列、发送租约、Outbox 文件/加密/各次提交、上传队列和上传结果提交处计时。
- 等待同一阶段 5 秒后记录一次 slow_stage；工作继续由原有流程持有，不取消原生调用、不转为失败、不发起重试。
- 记录首次非零上传进度与首次 100% 的时间，保留单调进度。只有 SDK/既有结果裁决负责发送状态。
- 普通 Release 不打开全局日志；保留最多 64 条无内容的近期诊断快照 `MediaSendPerf.recentEvents`。这些内存记录不会跨进程保存，目前没有新增用户导出入口。
- Debug/Profile 输出 `[MediaSendPerf]`；需要 Release 真机日志时，用 `--dart-define=MEDIA_SEND_DIAGNOSTICS=true` 构建诊断包，仅此类数字摘要绕过宿主 Release 日志静默。慢于 2 秒或非成功结果保留摘要，阶段卡住时不必等最终完成才有记录。
- 不记录聊天对象、消息内容、文件路径、文件名、账号、访问令牌或媒体 URL。`media_N` 仅为进程内诊断序号。日志输出失败不影响发送。

### 如何判读一次复现

- `imagePreparation` 慢且没有 `compress` 开始记录/完成耗时：结合同时间其他媒体记录检查压缩槽位；`compress` 的 slow_stage 指向原生编码等待。
- `sdkCreateImage` / `sdkCreateVideo` 慢：SDK 创建消息的阶段，尚未调用上传发送。
- `sendLease` / `outbox*` 慢：本地发送前准备或发送后的本地结果记录。
- `uploadQueueAndSend` 慢、上传派发尚无记录：结合最终 `uploadQueueWaitMs` 判断排队；`sdkUploadAndSend` 慢表明已进入 SDK。
- `uploadFirstProgressMs` 晚或进度停滞：SDK 上传路径；上传到 100% 后 SDK 很晚返回则是等待发送确认。进度回调缺失本身不能证明网络完全没有发送数据。
- SDK 已返回而 `outboxResult` 慢：发送完成后的本地结果提交可能延后 UI 确认。
- 各计时可能嵌套，不应简单相加成总耗时。

## 影响分析及验证

仓库绑定当前目录 `99999999`，本轮 GitNexus 注册名为 `99chat-friend-accept`，索引时间 2026-09-25 15:05:55 UTC，HEAD 为 `02d6276`。修改前先查图谱、再核对实时源码。

- MediaSendPerf 类 impact：CRITICAL，直接 5、三层 296；sendImageMessage：CRITICAL，直接 7/共 20；sendVideoMessage：CRITICAL，直接 6/共 21。已在编辑前向用户提示共用入口风险。
- send 协调方法和 SDK 服务实现的同名入口解析为 UNKNOWN；没有将空调用集合视为安全。实际调用经 TUIChatSeparateViewModel、TencentMessageAdapter/TUIKitMessageServicePort 与相应回归测试核对。
- 监听器工厂 impact LOW，直接 1/共 2。图谱没有列出流程不意味着这些入口没有业务影响。
- 61 项相关测试通过：诊断 7、媒体工作队列 5、发送/草稿、结果裁决、跨路由和跨账号媒体、乐观气泡契约及系统相册视频保存共 49。首次验证发现诊断泛型使一个非空结果被推为 nullable，已修正，并重跑受影响测试通过。
- 主工程 outgoing_send_coordinator 与诊断测试静态分析：无 error/warning，4 条既有风格 info。直接分析 vendored UIKit 包时，独立包上下文无法解析宿主包导入，不能将该次分析宣称为通过；相关修改已通过主工程测试的编译与执行。
- diff 空白检查通过。工作区同时存在其他任务的表情消息等修改，已保留；本轮不将它们计入成果。未提交、未发布、未进行真机网络或 SDK 上传性能测试。

下一步需要在问题设备上用诊断包复现单张图片和视频各一次，取得阶段数据后再选择优化点。当前工作属于链路核查和补齐观测，未以减少事务、降低图片质量、提高并发或跳过发送状态裁决来猜测修复。

## 收到实测日志后的更新：恢复扫描与正常发送竞争

本节更新前述“尚无现场日志”的结论。现场样本来自用户提供的 Android 日志，仅有一张图片的完整发送记录，不是稳定网络的性能基线。

- 原图 2,342,735 字节，发送文件 1,218,631 字节。
- 压缩 92ms、图片准备 93ms、上传排队 0ms、SDK 上传与发送 1182ms、媒体总链路 1522ms。
- SDK send 占总链路约 78%，但没有进度里程碑，不能判断这是上传启动、传输还是上传后的确认耗时。
- 发送期间出现 `recovered_logged_in reason=sdk_connect_timeout`，随后 `OUTBOX_RECOVERY scanned=1 advanced=1`。
- SDK 返回 `status=2 code=0`，本地协调器紧接着返回 `code=-2 / delivery pending reconciliation / outcomeUnknown=true`。

### 已复现的代码缺陷

重连，以及 Prepared 提交一秒后的恢复唤醒，都能在原发送 Future 尚未结束时扫描 Outbox。旧扫描对所有 dispatchIntent/sending 行调用 `recordOutcomeUnknown`，没有区分正在本进程发送的消息和上次进程中断留下的消息。

发送回执随后到达 `_recordOutboxSdkResult` 时，原有裁决规则拒绝让普通迟到回执直接推进 outcomeUnknown，给出 `state_requires_recovery_evidence`。协调器再按持久化状态输出 -2。这说明持久化耗时虽短，恢复与发送的状态竞争仍会延长用户看到的“发送中”。无需修改压缩、上传并发或 ACK 规则来修复这一缺陷。

回归测试用真实协调器、恢复扫描、内存持久化和受控 SDK Future 复现：修复前图片/视频 × 单聊/群聊四个场景均被扫描改成 outcomeUnknown；修复后均保持 sending，并在同一 SDK 回调后确认成功，只发送一次。现场日志没有记录原始 adjudication reason，因此该竞争是与现场顺序吻合且可复现的原因，不能用这一样本排除其他原因。

### 实施

- 新增 `OutgoingSendActivity`：按账号、账号代次、消息域代次、operationId 记录当前发送所有权；使用独立 token，重复尝试退出不会移除仍活跃的发送。
- 在 Prepared 可被扫描之前登记，直到 SDK 回执完成本地裁决才释放；成功、失败、提前返回、异常均由 finally 清理。
- 恢复扫描跳过当前仍活跃的 operation，并输出 `activeSkipped`。这个内存标记不会跨进程保留，真正中断的发送仍进入核对，禁止自动重发。
- 不改 Outbox 表结构、事务、身份匹配、旧回执裁决、重试授权或成功证明标准。补充成功却未被接受时的 `IM_SEND_ADJUDICATION`，输出枚举状态和原因，便于区分 fencing、身份冲突等剩余情况。

### 上传进度诊断修补

本地 SDK 源码显示，原生上传进度由 `message_msg_id` 重建消息；临时 Dart `id` 可能缺失，而发送完成回调才补回临时 id。旧诊断仅关联临时 id。因此在已有 `onSyncMsgID` 回调中绑定原生消息 ID 到同一 trace，保留全部业务回调原行为；没有修改 SDK 本体或 ACK 别名逻辑。

新增时间点以媒体 trace 起点为统一原点（`timingOrigin=media_start`）：

| 字段 | 意义 |
| --- | --- |
| sdkEnterMs | 调用原生 send 前 |
| uploadFirstCallbackMs | 首次进度回调，包含 0% |
| uploadFirstProgressMs | 首次非零进度回调 |
| upload100Ms | 首次报告 100% |
| sdkReturnMs | 原生 send Future 成功或异常结束 |
| upload100ToSdkReturnMs | 100% 到 Future 结束的间隔 |
| uploadProgressCallbackCount | 关联到的进度回调数，缺失明确记 0 |
| imConnectionStateAtSend / imConnectionStateAtReturn | 发送前后应用持有的 IM 连接状态枚举 |
| imHandshakePendingAtSend | 是否仍处于握手展示期，避免把 UI 最短展示时间误判为网络恢复 |

旧 `uploadCompleteProgressMs` 仍为 SDK 进入到 100% 的时长，供旧诊断读取；新时间点均为绝对相对 trace 的时间。没有 100% 回调就不生成该里程碑，也不把缺失当作 0ms 上传。首次进度是“首个被观察到的回调”，不等于真实首字节时间；100% 同样不证明消息送达。

Debug/Profile 和开启 `MEDIA_SEND_DIAGNOSTICS=true` 的 Release 诊断包会输出快速成功的完整记录，确保稳定连接下的三次快发送也有可比数据。普通 Release 仍使用原有慢/异常摘要策略与 64 条内存上限。

### 验证与边界

- 本轮共 96 项不同测试通过，覆盖：活跃发送与恢复竞争 9、诊断计时 9、连接诊断 1、既有连接恢复 13，以及发送重试/草稿、持久化裁决、结果界面、媒体路由与账号生命周期、相册保存、工作队列等 64 项。
- 综合首次结果 95 通过、1 项连接测试在退出时残留数据库队列的零延迟 timer。保留业务断言，补充测试 `pumpAndSettle` 收尾后，连接测试 13 项全部通过；记录见 `media-send-regression-2026-09-26.log` 和 `media-send-connection-regression-2026-09-26.log`。
- 主工程改动与新增测试静态分析无 error/warning，15 条既有 info；日志见 `media-send-analysis-2026-09-26.log`。改动空白检查通过。UIKit 通过主工程测试编译。
- 修改前图谱：恢复类 HIGH（直接 3 / 共 116）；连接状态类 CRITICAL（20 / 211）；诊断类 CRITICAL（5 / 296），已提示用户。恢复方法 LOW；协调器 send 为 UNKNOWN，已核对 TUI 实际调用、适配器和测试。没有因为空流程结果而当作无影响。
- 没有进行真机或真实腾讯网络测速，未打包发布。1.18 秒内部耗时仍待实测，不声称此次修改减少了网络上传时间。

下一轮建议：使用本次代码构建诊断包，等连接及启动同步稳定后静置 10 秒，在同一单聊发送同一张图片三次，间隔 10 秒；保留每条 `[MediaSendPerf]`。另做一次冷启动恢复期间发送，对比 `activeSkipped`、成功裁决与 SDK 时间线。
