# 跨模块报告复核：生命周期、关系校准、设备同步

日期：2026-09-28。范围：用户提供报告中的 A07、A08、A09、A11、A12，以及 A17 的相册默认授权部分。结论基于当前工作区源码及 8 个通过的受控复现测试；没有修改产品源码，没有调用真实后端或读取用户通讯录/相册。

仓库基线 HEAD：`0e7aa83bc5b096a99ff8bb424842404a3c901cb7`。工作区原有改动保留。先通过 GitNexus 定位符号与调用，再逐段核实当前源码。采用本轮刷新图 `D:\codex-task-cache\program-performance-audit-full-20260928`，indexedAt `2026-09-27T17:57:41Z`，76209 nodes / 174266 edges；CLI 传入 `--repo .`。图用于导航，结论以现有源码和实际组件执行为准。

## 结论矩阵

| 项目 | 结论 | 已核实的具体问题 | 证据强度与边界 |
| --- | --- | --- | --- |
| A07 | confirmed | 活跃聊天持续超过等待截止时间，关系校准仍会执行 | 实际调度组件及实际活跃聊天判定复现；测试缩短可注入的等待时间，生产值为 15 秒；未测手机卡顿幅度 |
| A08 | confirmed | 旧代请求成功或失败会覆盖新代调度阶段，使已排队的新代首份快照任务不再加载 | 两条完成顺序均实测；证明任务丢失与状态错误，不能直接推导跨账号数据泄露 |
| A09 | confirmed | iOS 关库 Future 持续未完成时，恢复队列及写门槛持续等待；开库等待超时不会解除这一状态 | 实际 Host → Store → Guard 链路故障注入；没有证明真实 iOS 插件或线上确实发生了无限关库 |
| A11 | confirmed | INCREMENTAL 模式仍采集并发送全部联系人；旧快照只参与删除判断 | 实际服务连续两轮同步：101 个未变化联系人每轮均发送 100+1；未验证服务端协议是否要求全量 |
| A12 | confirmed | 相册每个上传成功/跳过项都序列化并写回全部快照；超大视频先读文件计算哈希，之后才按大小跳过 | 全快照写回静态证据；真实 prepareOne 的超限元数据测试证实哈希顺序；未测真实大相册/大视频耗时 |
| A17（相册） | confirmed | 手机端取得 authorized/limited 相册访问后，未设置的备份开关被自动设为 true | 两种权限回调均实测；显式 false 保留；request 方法自身已不再启用，但实际回调/启动路径仍启用 |

上述项目没有足够依据标为 fixed。A17 的 `request()` 已收紧，只能说明该入口变化，不能代表整条实际授权链已经修复。A17 明文传输部分由其他复核报告处理。

## A07：15 秒后绕过活跃聊天门槛

当前源码：

- `lib/src/services/im_sdk_relationship_perf.dart:13`：生产 `uiIdleTimeout = Duration(seconds: 15)`。
- `lib/src/services/im_sdk_relationship_reconcile_service.dart:691`：`_waitUntilRunnable()` 只在截止时间之前循环检查；第 703–709 行循环耗尽后正常返回。
- 同文件 `:712`：实际 `_productionCanRun()` 检查 `ActiveChatRegistry`，聊天仍活跃时返回 false。
- 同文件 `:214`、`:219`、`:225`、`:227`：等待返回后进入 running 并执行好友/群加载，没有再次要求闲时。

触发条件是关系任务排队时用户已在聊天，且聊天持续到等待到期。持续操作不会阻止关系任务启动。好友加载后的排序、快照更新和群列表加载等工作会与聊天重叠；是否导致明显掉帧取决于数据规模与设备，需要真机测量。

复现使用实际 `ActiveChatRegistry`，没有替换 `canRunNow`。只将构造器已支持注入的等待值缩为 30ms；任务结束时聊天仍然活跃，两个 loader 各执行一次。测试证明时间门槛的控制流，不把 30ms 当作生产配置。

修复方向：将超时结果明确为“继续延后/取消本次”，或定义可以在聊天期间运行的受限工作预算；避免超时无条件放行完整校准。

## A08：代次变化后的旧请求覆盖新状态

当前源码：

- `lib/src/services/im_sdk_relationship_reconcile_service.dart:111`：`resetForSession()` 更新 `_sessionGeneration`、重置 phases 与 directory；没有使旧 `_request` 的完成分支失效。
- 同文件 `:194`：`_request()` 没有捕获并验证自己的 session generation；第 229–239 行在 await 返回/异常时直接写共享 phase。
- 同文件 `:214`–`:217`：排队中的新请求只要恢复时 phase 已不是 scheduled，就直接返回。
- `lib/src/services/im_sdk_relationship_directory.dart:210`：reset 清除快照和 capture，故旧任务完成并不意味着新代已得到快照。

确定性顺序：旧代两类请求开始 → reset 到新代 → 新代请求进入 scheduled 并等待 → 旧请求结束 → 旧成功把新 phase 写 completed，或旧失败把它写 idle → 新代恢复发现 phase 不是 scheduled 而退出。结果是新代未获取好友/群首份快照，但相应排队任务已经结束；用户可能看到缺失/陈旧关系资料，或依赖其他事件才恢复。

两个测试分别注入旧成功和旧失败，均验证好友/群 loader 调用次数停在 1，新代 directory 的两类 complete snapshot 均为 false。测试使用真实调度和 directory，仅对网络加载与等待顺序做可控替换。

限定：生产好友协议/identity 路径另有防护，本次不能由状态竞争推导“旧账号数据一定进入新账号”。证实的是调度状态的代次隔离不足和新任务丢失。

修复方向：为请求、flight、phase 及完成分支绑定同一代次/操作身份；旧代结果不能修改新代 phase，也不能让新代复用旧代 flight。需要保留成功、失败两种交错回归测试。

## A09：iOS 关库未完成会阻塞恢复和写入

当前源码：

- `lib/src/services/sqflite_lifecycle_host.dart:32`：只在 iOS 采用 pause 关库策略。
- 同文件 `:75`–`:95`：生命周期事件串行等待前一个事件。
- 同文件 `:105`–`:115`：pause 等关库完成，resume 也等关闭门槛，之后才恢复开库/写入。
- 同文件 `:127`–`:166`：设置禁止开库后，`Future.wait` 等待多 store 关闭；完成门槛只在 finally 中解除。
- `lib/src/services/friend_local/friend_local_store.dart:373`–`:377` → `lib/src/services/sqflite_lifecycle_guard.dart:42`–`:49`：最终 await `db.close()`，没有自身截止时间。
- `lib/src/services/sqflite_lifecycle_host.dart:63`–`:73`：`waitUntilWritesAllowed()` 没有等待上限。
- 同文件 `:38`–`:59`：开库等待有超时，但超时仅返回 canOpen 状态，不会完成关库/恢复队列。
- `lib/src/services/history_window_store.dart:1891`–`:1903`：该 store 的 close 还会等待原有 serial/opening 工作，也属于可能使总关库等待延长的入口。

故障注入使用真实 `SqfliteLifecycleHost`、`FriendLocalStore`、Guard，在平台边界提供一个 close 受 Completer 控制的 Database。pause 进入 close 后，resume 和写等待均未完成；开库等待 40ms 超时返回 false，canOpen/writes 仍 false。放行 close 后，三者才恢复。没有打开任何原生数据库。

这是已证明的“遇到持续未完成的依赖，应用级门槛没有恢复路径”，不等于已证实 iOS 原生关库一定会挂死，也不等于 UI 主线程被同步阻塞。原报告若将其描述为线上根因，需要补充关库耗时、pending store、原生回调与生命周期日志。

修复方向：记录每个 store 的关闭阶段、耗时和等待对象，设计受控的故障恢复及数据库句柄代次。不能简单超时后重开同一仍在关闭的句柄，否则可能增加并发关闭/写入问题。

## A11：联系人增量模式仍发送完整目录

当前源码：

- `lib/src/services/device_sync_service.dart:451`–`:475`：登录后的同步进入联系人任务。
- 同文件 `:523`–`:535`：根据服务端 `lastFullSyncAt` 选择 FULL/INCREMENTAL。
- 同文件 `:541`：两种模式都调用 `collectAll()`。
- 同文件 `:543`–`:556`：读旧 snapshot 后，直接将当前全部 contacts 按 100 条分批发送。
- 同文件 `:558`–`:571`：旧 snapshot 仅用于计算删除 ID，最后保存当前指纹；没有按指纹筛出变化联系人。
- `lib/src/services/contact_sync_collector.dart:33`–`:39`：从设备获取带 properties 的全部联系人并转换。

受控边界测试连续调用两次真实 `syncAfterLogin()`，服务端状态始终说明已有首次同步。本地目录两次相同且含 101 人；两次 session 均标 INCREMENTAL，实际发送批次长度为 `[100, 1, 100, 1]`，第二轮内容与第一轮一致，删除列表均为空。平台通讯录、权限和 HTTP 用测试替身，没有外部请求。

重复采集、转换和网络发送是确定的；大通讯录用户的字节数与实际耗时尚未测。此处不能断言后端协议允许只发差量，修复前应对齐协议，再使用已有指纹过滤 unchanged，并保留删除语义。

## A12：相册快照全量重写及超限视频先哈希

当前源码：

- `lib/src/services/device_sync_service.dart:674`–`:678`：读取完整 JSON snapshot。
- 同文件 `:734`–`:737`：每个 uploaded/skipped 结果立即更新 snapshot，并对整个 map `jsonEncode` 后写回 preferences。对 N 个新增项目，累计序列化的项数为 1+…+N；若已有 M 项，则为 O(MN+N²) 项处理量。
- 同文件 `:711`、`:722`：先 `prepareOne()`，再 `_uploadOnePhoto()`。
- `lib/src/services/photo_sync_collector.dart:198`–`:205`：视频拿到 file length 后，仅拒绝空文件，接着 `fileContentHash()`。
- `lib/src/services/sync_fingerprint.dart:16`–`:19`：哈希读取整个文件流。
- `lib/src/services/device_sync_service.dart:59`、`:777`–`:783`：100MiB 视频阈值到上传方法才检查，超限直接 skipped。

真实 `PhotoSyncCollector.prepareOne` 的测试中，受控 File 报告 size 为 104857601，并提供小型可核验内容流；结果仍打开流一次并得到内容 SHA256，证明超限元数据不能阻止 prepare 阶段哈希。这不是创建/读取实际 100MiB 文件的压测，不能据此报告真实 CPU、内存或掉帧数字。

现有保护必须保留在结论里：第 221–249 行有前台、登录身份、键盘、活跃聊天、前台工作、闲置 3 分钟、网络等条件，逐项处理也有重复检查；第 748 行有 800ms 间隔。因此不能说相册备份“总在聊天时连续全速运行”。这些保护不消除全快照写回复杂度和先哈希后拒绝的多余工作。

修复方向：在 prepare 的文件长度判断后、哈希前拒绝超限视频；批量/节流持久化 snapshot，或使用可按项更新的存储，同时定义中断后的进度恢复语义。

## A17（相册）：授权回调仍会启用未设置的备份

当前源码：

- `lib/src/services/photo_backup_consent.dart:41`–`:56`：`enableIfUnset()` 在没有持久化键时写 true；已有 false 会保留。
- `lib/src/services/device_sync_service.dart:29`–`:40`：安装相册授权回调。
- 同文件 `:327`–`:337`：手机端取得相册权限后调用 `enableIfUnset()`，随后调度扫描/备份。
- 同文件 `:316`–`:325`：启动/首次同步发现已经有相册权限也会启用未设置的备份。
- `lib/src/platform/permission_guard.dart:495`–`:513`：授权状态采用 `hasAccess`，覆盖 authorized 和 limited。
- 同文件 `:515`–`:525`、`:527`–`:552`、`:559`–`:574`：授权完成和启动检查都会通知这一回调。
- `lib/src/services/photo_backup_consent.dart:58`–`:80`：`request()` 自身已改为只查询 existing enabled，不再主动 enable；这与仍存在的回调启用路径并存。

两项测试分别提供 authorized 与 limited 状态，在真实 Android 目标平台分支安装并调用实际 `PermissionGuard.onPhotosAccessGranted`。未设置的备份键两种情况下均变 true；之后显式设 false，再次调用回调，false 被保留。测试没有实际上传相册，仅证明自动启用与调度入口；实际上传仍受 A12 所述门槛约束。

修复方向：操作系统相册权限与后台备份同意分别存储，只有清晰的用户备份操作才能把后者设为 true；同步审查已有权限的启动路径，而不只修改 `request()`。

## 验证记录与局限

本目录提供 3 个可复现测试文件，共 **8 项通过**：

- `relationship_lifecycle_repro_test.dart`：3 项（A07、A08 旧成功、A08 旧失败）。
- `sqflite_close_gate_repro_test.dart`：1 项（A09）。
- `device_sync_repro_test.dart`：4 项（A17 authorized、A17 limited、A11、A12）。

命令均为本地 `flutter test --no-pub <文件> --reporter expanded`。设备同步原始输出见 `device-sync-repro.log`；其余通过情况与故障注入边界见 `execution-results.md`。这些是对缺陷现状的断言，测试通过表示现状被复现，不表示缺陷已修复。未执行真机帧率、实际照片容量、生产服务端协议或线上发生率验证。
