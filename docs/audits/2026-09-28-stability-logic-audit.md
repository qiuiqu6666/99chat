# 99chat 前端稳定性与逻辑审查（持续审查）

审查日期：2026-09-28  
代码基线：`0e7aa83bc5b096a99ff8bb424842404a3c901cb7`，分支 `codex/w0-w7-stability-repair`  
审查方式：静态代码阅读、调用链核对、GitNexus 图分析、阅读相关回归用例；未修改业务代码。对 10 个现有测试文件执行定向回归，共 77 条通过；未运行整套测试，也未进行真机测试。

## 范围和限制

审查持续补充扩展。重点路径包括冷启动与会话恢复、会话列表首屏/账号切换、聊天历史和滚动、Android 系统相册图片/视频发送、朋友圈缓存、群成员同步、iOS/Android 推送及保活；并逐项对照此前跨模块审查的 A01–A17 基线，复核网络、关系同步、SQLite 生命周期、设备备份、AI、钱包和撤回路径。重点追踪了 SessionManager、会话分页存储、账号清理、UIKit 媒体发送队列、相册恢复日志、发件箱持久化和 APNs 注册/注销边界。

本仓库工作区仍有大量已修改或未跟踪状态项，且其他任务会并行修改同一目录。下列结论适用于各项复核时的工作树状态，不能直接等同于用户手机上 3.0.1+20 安装包的源码行为；合并前应对最终提交重新复核。仓库文件规模较大，本轮围绕高频入口和共享状态深查，并非逐行读完全部约 4,000 个文件。静态审查也不能替代 Android/iOS 真机、弱网、后台杀进程和大数据量性能录制。

## 当前已确认问题及复核状态

### 1. 会话列表原生读取超时后，后续首屏请求可能被旧请求挡住且不自动恢复

**严重度：P2；结论置信度：高（触发需要原生 SDK 请求长时间不返回）**

- `lib/src/services/conversation_local/conversation_tab_store.dart:2888-2910`：逻辑读取等待 8 秒后超时，并清除逻辑 in-flight 状态。
- 同文件 `:3198-3240`：原生 SDK 读取另有 `_physicalReads` 槽位；只有原生 Future 真正结束时才释放。`Future.timeout` 不会取消原生调用。
- 同文件 `:2779-2825`：切账号清空列表和逻辑请求标记，但有意保留 `_physicalReads`，防止重复调用原生 SDK。
- 同文件 `:2888-2892`：新账号第一次读取若撞上旧账号的物理槽位，只标记失败并立即返回，没有等待旧请求结束，也没有登记一个待补拉任务。
- 旧请求最终返回时，代次检查会正确丢弃旧账号结果；但槽位释放本身不触发新账号补拉。`ConversationSyncService._bootstrapSdkFirstScreen` 可能在短重试用完后仍然失败，列表要等用户刷新或后续生命周期/同步事件再次触发才恢复。

组合场景：旧账号会话列表请求遇到 SDK/平台通道卡顿，期间切换账号；8 秒后逻辑请求超时，清理状态保留物理槽；新账号首页启动读取撞槽而失败；即使旧请求稍后返回，新账号也没有因槽位释放自动补拉。用户会看到空白或不完整的会话列表，可能误以为会话丢失。

现有 `test/conversation_tab_read_deadline_test.dart:21-91` 覆盖了超时、跨 clear 保留槽位、旧结果隔离，以及“旧请求结束后显式再调用一次即可成功”。缺少“旧请求结束后自动唤醒新会话首屏读取”的断言，也没有覆盖原生 Future 长时间不返回。

建议：让新代次的首次读取可以等待同类型物理槽位释放，并在释放后只补拉一次；如果原生 Future 永远不结束，增加代次隔离的恢复策略，避免同一个全局槽永久阻塞。补一个旧账号读挂起 → clear/新账号首读 → 旧读释放 → 新账号自动成功的测试。

### 2. Android 相册恢复记录在发送持久化前就被标为完成

**严重度：P2；结论置信度：高（触发需要进程在短暂交接窗口内被系统终止）**

- `third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_more_panel.dart:1804-1814`：系统相册返回后，调用 `_dispatchSystemPickedMedia`，随后立即 `completePaths`。
- 同文件 `:831-842`：视频准备和发送以 `unawaited` 后台任务启动。
- 同文件 `:910-920`、`:1056-1062`：图片加入待发送列表后，也以 `unawaited` 后台任务发送；`_dispatchSystemPickedMedia` 返回不代表 worker 已完成发送准备或可靠保存。
- 同文件 `:6880-6884`、`:6918-6984`：图片发送还要经过后端附件路由、文件探测、压缩/暂存、SDK 消息创建等异步阶段。
- `lib/src/services/im/outgoing_send_coordinator.dart:337-361`、`:522-555`：可靠发件箱准备和接受发生在发送协调器中；UIKit 的 `_sendMessage` 到 `third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:5631` 才进入该持久化路径。
- `picker_recovery_coordinator.dart:289-300` 写入 `complete.json`；同文件 `:243-266` 会跳过已有完成标记的草稿。

组合场景：用户从 Android 系统相册选中大图或视频，界面已排入后台 worker，恢复协调器就把原文件标记为 `handed_off`；随后应用在标准 IM 发送路径的压缩、视频元数据处理、文件暂存或 Outbox 落盘前被低内存回收/用户强制关闭。重启后恢复列表看见完成标记而隐藏该草稿，Outbox 里也尚无可重试记录，用户刚选的媒体会消失。若媒体转到自托管附件路径，需再核实该附件服务何时持久化其任务；本条结论针对进入标准 IM Outbox 的路径。

现有 `test/picker_recovery_coordinator_test.dart:70-81` 只验证正常调用 `completePaths` 后草稿消失，`:83-99` 验证在交接前重启可恢复；没有覆盖“worker 已排队、Outbox 尚未接受时进程终止”。

建议：把“已交给内存 worker”和“已被可靠发件箱接受”分成不同状态。只有每个媒体项的 Outbox 持久化成功后才完成对应恢复记录；进程重启时，对未接受项保留重试入口。增加可在暂存/Outbox 前后模拟进程重启的测试。

### 3. 冷启动凭据读取超过 8 秒会把仍有效的会话送到登录页

**严重度：P2；结论置信度：中高（Android/iOS 安全存储慢时触发）**

- `lib/src/session/session_manager.dart:104-134`：`restore()` 只给调用方 8 秒等待预算；超时时只有 `_state.userId` 已存在时才改为 `offline`。owner 为空时直接返回，不改变初始 `unknown` 状态。
- 同文件 `:203-228`：先依次读取业务 token、用户 ID、写回业务会话；这些操作全部完成后才把状态设成 `restoring` 并写入 owner。
- `lib/utils/init_step.dart:273-285`：等待 `restore()` 返回后，如果状态既非 `ready` 也非 `offline`，就直接导航登录页。
- 全仓检索到的 `SessionManager.addListener` 用法没有登录路由恢复订阅；因此恢复 Future 后来成功时，不能据此认为登录页会自动回首页。

组合场景：应用冷启动时 ApiClient 已持有有效 JWT，但 Android Keystore/安全存储插件首次唤醒较慢，或者安全存储读写被系统 IO、解锁流程拖到超过 8 秒；SessionManager 仍处于 `unknown`，超时回调没有 owner 可用来显示离线首页；InitStep 按“无有效会话”路径打开登录页。后台恢复即便最终成功，当前路由也可能保持登录页，用户会感到被意外登出。

现有 `test/scale_startup_budget_test.dart` 覆盖了慢 `/me` 和慢 IM 登录时快速释放 UI，但模拟凭据读取和 `saveBusinessSession` 都即时完成，未覆盖 owner 尚未装入状态时超时。

建议：从开始读取凭据起就用显式 `restoring` 状态表示“身份尚在判定”；超时后展示可恢复的等待/重试状态，或订阅恢复完成后路由，而不要把 `unknown` 解释成已登出。补慢 `readBusinessToken`、`readUserId` 和 `saveBusinessSession` 的启动测试。

### 4. 复核后排除：在线会话健康探测超时不会把 ready 状态改为离线

**状态：当前并行工作树改动已覆盖原先担心的分支；不计为现存缺陷。**

- `lib/src/session/session_manager.dart:104-134` 当前超时分支会在 `_state.isReady` 时直接返回，不会把 ready 改为 offline。
- 同文件 `:136-159` 的 `_validateReadySession` 会吞掉普通网络/存储异常，只对明确身份失效执行登出。
- 现有 `test/scale_startup_budget_test.dart` 验证的是冷启动 `/me` 和 SDK 登录慢；没有单独覆盖“原本 ready 时回前台校验慢”。当前状态保护使原先描述的误离线行为在这份工作树上不能复现，建议补回归测试，但不作为现存问题计数。

### 5. 朋友圈异步请求没有固定账号代次，切号后旧响应可能污染新账号缓存

**严重度：P2（账号隔离/隐私）；结论置信度：高（切换账号发生在朋友圈请求返回前）**

- `lib/src/services/moments/moments_store.dart:28-31`：`accountScope()` 每次都从当前 UIKit 登录用户动态取 owner，没有接收调用方捕获的 owner 或 `SessionIdentity`。
- 同文件 `:203-226`、`:231-258`：feed 和用户主页请求发起前不保存账号 owner；网络返回后才调用 `accountScope()` 给 `MomentsLocalStore.savePage` 选择缓存分区。API 请求本身使用全局 `ApiClient`。
- `lib/src/services/moments/moments_feed_controller.dart:24-52`：首屏返回后直接覆盖 `posts`；没有请求代次、账号身份或 dispose 后结果检查。`loadMore()` 也会把迟到的旧游标页面并入当前列表。
- 同文件 `MomentsStore.upsertPost` 以及点赞/评论/发布的异步流程，也是在服务器请求完成后才根据当前 `accountScope()` 写入本地；账号切换期间完成的旧操作可能把旧响应放进新账号的数据分区。
- `test/moments_local_store_test.dart:56-91` 证明同一时刻按 owner 分区能隔离，但没有覆盖“旧 owner 发请求、切号、旧响应回来”的异步竞态。

组合场景：账号 A 打开朋友圈，feed 或点赞/评论请求仍在网络中；账号清理使 `SessionIdentity` 代次失效，随后账号 B 登录；旧响应返回后，`MomentsStore` 用当前账号 B 的 owner 保存 A 的内容，若页面实例仍存活，Controller 也会直接显示迟到数据。朋友圈 feed 可能包含按 A 的关系和可见范围筛选出的内容，因此这是本机多账号隔离风险，不只是列表短暂闪动。

建议：朋友圈 API 和本地缓存方法在入口捕获 owner/generation，并把捕获值贯穿网络返回后的保存、缓存回退和 Controller 状态提交；代次已变化时丢弃旧结果。增加 A→请求挂起→切 B→释放 A 响应的 feed、点赞、发布测试，验证 B 的 DB 与页面都不出现 A 的结果。

### 6. Android 保活服务的 single-flight 状态永不释放，后续启动/重试都复用已完成 Future

**严重度：P2；结论置信度：高（`AndroidKeepAliveService.start()` 执行一次后）**

- `lib/src/services/android_keep_alive_service.dart:34-44`：`start()` 把 `task.whenComplete(...)` 的返回 Future 存进 `_runningTask`，但完成回调却用 `identical(_runningTask, task)` 比较原始 `task`。两者不是同一个 Future，因此 `_runningTask` 不会归零。
- 同文件 `:47-60`：`ensureRunning()` 发现系统服务已停止时会调用 `start()`；但只要 `_runningTask` 留着旧的已完成 Future，`start()` 立即返回该 Future，不会再次进入 `_start()`。
- 同文件 `:91-103` 的 `stop()` 只重置 `_started`，不清 `_runningTask`；所以用户关掉再打开通知、应用设置变更，或系统停止前台服务后的自动恢复也会被旧 Future 挡住。
- `lib/src/services/notification_settings_service.dart:287-295` 会在 Android 通知设置应用时先 `applyFromSettings()`，需要通知时又安排 `ensureRunning()`；`lib/config.dart:112-113` 默认启用该服务。仓库未找到覆盖“启动→停止→重启”或启动失败后重试的 AndroidKeepAliveService 测试。

复现顺序：启动前台服务一次；随后由系统停止服务或关闭再重新打开通知设置；`isRunning()` 会报告 false，但 `_start()` 不会再次被调用。若第一次系统启动调用失败，之后的自动重试同样被永久短路。结果是 Android 后台连接保活通知可能消失，进程受系统回收后 IM 消息到达和本地通知延迟，给用户表现为“后台收不到消息”或偶发离线。

建议：single-flight 字段保存的 Future 与完成回调必须比较同一个对象，并在完成及 `stop()` 时正确释放状态。补充 fake MethodChannel 覆盖首次成功、首次失败、系统停止后重启、关闭设置再开启四条路径。

### 7. Android 保活服务被主动停止后仍会安排闹钟重启

**严重度：P2；结论置信度：高（调用显式 `stop()` 后）**

- `android/app/src/main/kotlin/vip/ninechat/pro/keepalive/KeepAliveForegroundService.kt:25-41`：收到 stop action 后调用 `stopSelf()`；`:59-63` 的 `onDestroy()` 对所有销毁都无条件调用 `KeepAliveScheduler.scheduleRestart(...)`。
- `KeepAliveAlarmReceiver.kt:10-13` 收到该闹钟后无条件重新启动服务，没有检查用户设置、注销状态或主动停止标志。
- `AndroidKeepAlivePlugin.kt:23-28` 的 stop 处理会调用 `KeepAliveForegroundService.stop(...)` 并取消周期 watchdog，但没有取消已排入的 `AlarmManager` 重启任务；`KeepAliveScheduler` 也没有对应 cancel 方法。
- Dart 侧 `AndroidKeepAliveService.stop()` 用于通知关闭、配置禁用和登出；因此显式停止后 5 秒左右仍可能被原生闹钟重新启动。若服务当前并未运行，stop action 自己启动服务并随后销毁，也会走无条件安排重启的路径。

组合场景：用户关闭通知或退出账号，Dart 端请求停止服务；原生服务 `onDestroy` 又排入 5 秒重启闹钟，AlarmReceiver 随后重启前台服务。表现为通知关闭后保活常驻通知回来、登出后服务仍运行和额外耗电；如果用户紧接着重新登录，服务是否重复启动取决于 Dart single-flight/原生服务状态，还会与上一条 `_runningTask` 未释放问题叠加。

建议：显式停止时记录停止原因并取消待触发的 AlarmManager PendingIntent；`onDestroy` 只对非主动销毁安排恢复。重启接收器还应检查持久化的“保活仍启用且当前账号有效”状态。增加“启动→登出停止→等待闹钟周期”“设置关闭→进程重建”“系统意外杀进程”的原生测试。

### 补充：iOS 退出账号时，进行中的 APNs 注册可能在删除之后重新写回

**严重度：P2；代码竞态确认度：高（触发需要令牌 POST 和登出 DELETE 并行且服务端完成顺序倒置）**

- `lib/src/services/ios_apns_push_service.dart:174-197`：令牌同步由 `_syncTask` 串行执行，但没有取消令牌；队列正在执行的 `_syncTokensOnce` 不会因登出自动结束。
- 同文件 `:213-231`：`clearLocalStateOnLogout()` 只清 `_pendingTokenSync` 和本地令牌状态，没有等待或取消 `_syncTask`。
- 同文件 `:440-526`：`_syncTokensOnce()` 只在开始 POST 前及收到响应后检查 credential generation，没有检查 `ApiClient.isLogoutInProgress`；POST 已发出后也无法撤回服务器副作用。
- `lib/src/services/account_session_service.dart:235-240, 280-287`：退出先把 `logoutInProgress` 置为 true，然后调用 `DELETE /me/push-token`；该同步器不感知此状态。`PushTokenApi` 直接经共用 Dio 发起 POST/DELETE，API 请求拦截器没有因 logout flag 拒绝新的 `/me/push-token` POST。
- `NotificationSettingsService.resetForLogout()` 在稍后的 `ListenerStore.beforeLogout()` 才清同步队列；清理代码也没有等待 active task。`test/ios_apns_token_sync_test.dart` 覆盖账号切换时旧响应不写本地成功凭据，但没有覆盖旧账号注册 POST 与登出 DELETE 并发、POST 最后提交的顺序。

组合场景：令牌到达或设置同步启动 POST 后用户立即退出；DELETE 先完成、旧 POST 后完成。客户端收到旧 POST 响应时，generation 可能已经变化，因此不会保存本地成功状态，但服务端写入已发生，无法由本地代次检查回滚。该设备可能继续收到旧账号通知；若随后登录另一个账号，通知路由和当前登录身份不一致还会放大混淆。

建议：在登出开始时先关闭旧身份的令牌同步入口，并等待或显式取消/栅栏化所有活动注册请求，再执行服务端 DELETE；新登录应在新身份建立后重新开放同步。服务端也应确保 DELETE 后的旧请求不能把已注销设备重新启用。补一个可控 Dio adapter 测试：POST 挂起→开始登出并完成 DELETE→释放 POST→断言最终服务端/客户端状态仍是未注册，并验证新登录可重新注册。

### 补充：登出时服务端令牌删除失败会被吞掉，且没有离线重试

**严重度：P2 条件风险；结论置信度：高（登出时网络不可用或 DELETE 超时）**

- `lib/src/services/push_registration_service.dart:69-104`：`deletePushTokenBeforeImLogout()` 调用服务端 DELETE 后捕获所有异常，只作 debug log，不返回失败状态，也不保存待删除标记。
- `lib/src/services/account_session_service.dart:280-287`：登出把该调用包在 `_safe()` 中；失败后仍继续退出 IM 和清除业务凭据。
- `NotificationSettingsService.resetForLogout()` 随后调用 `clearLocalPushStateOnLogout()`，会清本地 owner 上传凭证；没有发现后续重试 DELETE 的持久任务。
- 当前 `test/ios_apns_token_sync_test.dart` 覆盖注册失败重试，没有覆盖注销 DELETE 失败后恢复网络的补偿路径。

组合场景：用户在无网或切网时退出，DELETE 超时/失败；本地认为退出已完成，并清掉身份及令牌上传状态。恢复网络后客户端没有待处理删除任务，服务端可能继续保留旧账号与设备的推送关联；用户可能在登出后仍收到旧账号通知。是否最终被服务端过期清理取决于后端策略，本地代码没有保证。

建议：让 DELETE 返回可观察结果；失败时在本地按 owner/deviceId 留下有期限的登出删除任务，恢复有效网络和身份后使用旧账号授权安全重试，成功后再删除任务。需确保重试不会误删新账号刚建立的关联。测试登出 DELETE 失败→恢复网络→重试旧关联→新账号正常注册的顺序。

## 高风险条件项（需真机或依赖行为确认）

### 8. 切账号与发送超时叠加时，旧媒体任务会拖慢新账号并绕过并发上限

**严重度：P2；结论置信度：高（单次影响最长受 3 分钟派发超时约束）**

- `third_party/tencent_cloud_chat_uikit/lib/data_services/message/outgoing_message_send_queue.dart:21-28`：图片并发槽为 3、视频为 1、文件为 2；媒体槽是 queue 单例上的全局队列。
- 同文件 `:32-48`：媒体发送 Future 最长等待 3 分钟；超时不会取消底层原生/网络请求。
- 同文件 `:141-146`：`clearSession()` 只清会话串行尾部和批次映射，没有重建/释放图片、视频、文件的上传槽。
- `lib/src/services/account_session_service.dart:231-241` 在退出时调用该清理；新账号随后仍使用同一组媒体槽。
- `message_service_implement.dart:1019-1027` 在真正派发时会检查账号代次，所以排队的旧账号发送不会因此被错误地送到新账号；这里确认的是延迟风险，不是跨账号发送。

组合场景：旧账号同时有 3 个未完成图片上传，接着退出并登录新账号；新账号选图后，新任务排在旧全局槽后面。旧发送若一直等到 3 分钟超时，新账号图片也可能长时间不开始上传。视频槽只有 1 个，受单个卡住的视频发送影响更明显。更关键的是，Future 超时会释放 admission slot，但不能取消 SDK 原生 Future；新发送获准后，底层旧上传仍可能运行，所以 3/1/2 只约束队列等待的 Future，并不保证弱网/平台通道挂起时原生实际发送数始终不超限。若用户继续批量发送并反复遇到超时，未结束的原生调用可能与后续任务重叠，进一步挤占网络、内存和 SDK 资源。现有 `test/media_batch_parallel_send_test.dart` 验证账号代次隔离，`test/outgoing_message_send_queue_test.dart` 和同文件批次用例验证超时后队列推进；没有模拟多轮底层 Future 一直不结束并检查实际活动调用数。

建议：媒体队列按 session generation 分区，避免旧账号逻辑队列拖住新账号；同时单独跟踪超时但仍未 settle 的原生调用，限制连续未知发送的数量，直到回调完成或完成结果核对。增加账号切换和多轮未完成 Future 的压力用例，验证新会话延迟与真实并发数。

### 9. IM 登录 Future 若在原生桥接层不返回，退出/账号切换会一直等待

**严重度：P2 条件风险；结论置信度：中（依赖腾讯 SDK 是否内部保证最终回调）**

- `lib/src/session/session_manager.dart:162-200`：`_connectIm` 串行等待 `_imLoginTail`，再直接 await initialize/connect；应用层未设 SDK 登录超时。
- 同文件 `:572-622`：`signOut()` 等待 `previousLogin` 完成后才调用 disconnect、dispose 和清本地会话。
- `lib/src/services/account_session_service.dart:231-236`：账号清理同步等待 `signOut()`，不会以超时方式越过该 Future。

组合场景：弱网、SDK 原生回调丢失或平台通道异常导致 connect Future 长时间不完成；恢复 UI 的 8 秒超时虽能释放启动等待，但登录尾任务仍挂起；随后用户退出或切换账号，清理流程卡在 `await previousLogin`，无法进入 disconnect/清凭据步骤。

静态代码只能确认应用层没有额外截止时间，无法确认当前腾讯 SDK 版本是否一定会内部超时。因此需在目标 Android 3.0.1+20 和当前构建上分别用断网/切网/恢复前后台验证。若 SDK 不保证最终回调，应把登录、退出做成带代次的可超时 teardown，并保留晚到回调隔离。

### 10. 被踢下线时，正在进行的相册对象上传没有被会话边界取消

**严重度：P2 条件风险；结论置信度：高（自动过期/被踢路径在相册 PUT 期间触发）**

- `lib/src/services/account_session_service.dart:218`：账号清理一开始就递增 session generation，使旧异步任务失效；普通登出默认 `purgeOwnerDisk: false`，只有明确清盘才会调用 `DeviceSyncService.clearForOwner`。
- `lib/src/services/device_sync_service.dart:766-773`：相册对象 PUT 使用 `_albumUploadCancellation`；该令牌会在用户触摸首页、应用转后台、用户启用/停用备份时取消，但 session generation 变化本身没有通知该服务取消令牌。`clearForOwner` 的取消只在破坏性清盘路径调用。
- `lib/src/services/photo_sync_transfer.dart:48-64`：对象 PUT 等待结束后才再次检查 session guard；若 generation 已改变，就不会继续调用 `/photos/complete`。

组合场景：前台闲置备份正在向对象存储上传大视频时，服务端会话过期或被踢导致程序自动执行账号清理。该流程使旧任务失效，但没有触发对象 PUT 的取消；上传可继续到请求结束（Dio send deadline 最长 180 秒），随后因 guard 失败而不提交完成回执。用户登录新账号时，这段旧媒体流仍会占网络，可能拖慢新会话的消息/媒体请求；后端是否及时回收未完成对象取决于对象存储和服务端清理策略。用户主动点登出通常会先由首页触摸监听取消上传，因此主要风险在自动会话失效或没有首页指针事件的清理入口。

建议：把活动媒体任务取消接入统一 session invalidation 生命周期，而非仅靠 UI 触摸/前后台回调；测试在 PUT 中触发 kicked-offline，验证对象请求被取消、不会进入完成接口，且新账号网络任务不等待旧上传。

### 11. 通话连接阶段会吞掉振铃超时，连接慢后可能永不收口

**严重度：P2 条件风险；结论置信度：高（LiveKit `Room.connect` 延迟超过呼叫 timeout）**

- `lib/src/services/livekit_call_session.dart:917-921`：`_connectAndPublish` 把 phase 改为 `connecting` 后开始媒体建连；`:1039` 直接等待 `room.connect()`，应用层没有为首次建连设置截止时间。
- 同文件 `:1344-1359`：原呼叫 timer 仅处理 `ringingOut` 和 `ringingIn`；到期时若 phase 是 `connecting`，回调不做任何事。
- 同文件 `:1088-1104`：建连完成后，callee 直接变 `connected` 并取消 timer；caller 则回到 `ringingOut`，但若 timer 已在 `connecting` 阶段空转结束，没有重新建立剩余振铃截止时间。
- 同文件 `:59-65` 的 `shouldReconcileStaleRinging` 也只把 `ringingIn` / `ringingOut` 当作可收口状态；后台恢复不会替 `connecting` 阶段补做超时处理。

组合场景：弱网、iOS CallKit 音频会话交接慢或 LiveKit signaling/平台通道卡住，使拨出或接听阶段停在 `connecting` 超过服务端给定的 60 秒振铃时限。timer 到点时因 phase 不匹配而失效；若迟到建连后 caller 回到 `ringingOut`，本地已没有剩余 timer，通话可能持续显示呼叫中，直到外部信令偶然收口。若建连 Future 一直不返回，则 UI 可能一直停在连接中；应用侧没有独立的连接 deadline。

建议：分别管理建连截止时间与振铃截止时间；建连超时要 finalize 并隔离晚到的 Room 回调，拨出方建连完成后按原 deadline 只等待剩余振铃时长。增加 outgoing/incoming 在 connecting 时跨过 ring deadline、建连晚到和后台恢复的测试。

### 12. 群成员实时序号缺口不会触发补拉，丢失事件可能留在本地缓存

**严重度：P2 条件风险；代码行为置信度：高（成员流事件确实丢失且后续没有覆盖同一成员状态时）**

- `lib/src/services/group_local/group_member_local_store.dart:695`：群成员同步游标新建时 `member_seq` 初始化为 `0`；完整成员快照的写入路径也使用 `0`，没有把服务器当前成员流序号作为基线保存。
- `lib/src/services/group_local/group_member_incremental_sync_service.dart:83-94`：当前策略会应用所有 `seq > cursor` 的事件；因此首次观测到较大序号不会阻止后续事件，但也不会判断并修复中间缺口。
- 同文件 `:98-118` 与 `group_member_realtime_cursor_policy.dart:9-15`：游标只在 `seq == cursor + 1` 时前进。仓库内对 `writeCursor` 的调用只有 `noteRealtimeSeq`；已有 `/me/groups/{id}/members/changes` 增量 API 和 `GroupProtocolSyncService.syncGroupMembers` 目前没有生产调用方。
- `lib/src/services/group_local/group_sync_service.dart:131-189`：收到成员增加/删除/退出事件后会检查和记录该游标，并按事件携带的用户 ID 做定向校正；事件缺失的用户没有从这次定向校正中恢复。
- `test/group_member_realtime_cursor_test.dart` 只测纯序号策略，没有覆盖乱序/缺口、重放或丢失成员事件后的服务级修复链。

组合场景：用户升级后本地游标为 0，而服务端成员流已经运行过一段时间；收到 `seq=101` 后该事件会应用，但游标因只接受 `cursor + 1` 仍为 0，后续序号也不会推进游标。更关键的是，如果 `seq=100` 对应的成员删除或变更漏到客户端，收到 `seq=101` 及后续事件时只会处理各自携带的成员信息，代码没有因游标缺口触发该群的成员快照或增量补拉。缺失成员状态可能一直留在缓存，直到该群页面的其他按需刷新覆盖它。重复事件也可能再次进入 `applyGroupChanged`；其下游副作用是否完全幂等需结合具体 action 验证。具体表现取决于服务端 seq 的作用域/连续性，以及群页面刷新是否及时发生。

建议：首次启用时从权威成员快照或服务端状态取得可验证的 seq 基线；发现 `seq > cursor + 1` 时安排该群的补拉并在补拉成功后提交游标。对无 seq 的旧推送继续保留幂等处理。增加“已有群安装升级首事件 seq 很大”“漏一个删除事件后收到后续事件”“重复和乱序事件并发到达”的服务级测试。

### 13. 聊天历史读取超时会释放逻辑队列，但原生请求继续运行

**严重度：P2 条件风险；代码行为置信度：高（腾讯原生历史读取 Future 超过 20 秒仍未 settle，且用户继续触发重试时）**

- `third_party/tencent_cloud_chat_uikit/lib/data_services/message/message_service_implement.dart:240-333`：会话历史 lane 在 20 秒等待超时后，将旧 flight 标成 `superseded`、从逻辑队列移除并唤醒等待者；注释明确说明原生 Future 无法取消。
- `third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_history_pagination_load.dart:412-414`、`:1069-1094`：分页调用另有 20 秒步骤超时，异常后会执行 retryable 路径并在 `finally` 释放分页 key 和 `previousPaginationInFlight`。
- `MessageServiceImpl` 只保留当前逻辑 flight 映射；超时旧 Future 仍可能未完成，但不再计入当前 lane。连续重试会继续发起新读取；按账号代次变化后的请求 lane 也是新 key，因此不等待旧账号尚未结束的底层 SDK 操作。
- 现有历史测试大量覆盖 cursor、窗口代次和 late response 丢弃，但本轮没有找到“重复原生 Future 永不返回时，真实活动原生读取仍受限”的压力用例。

组合场景：低端 Android/iOS 设备切网、原生 SDK 线程池或平台通道繁忙，某次向上翻页超过 20 秒未返回；分页代码会允许下次重试。若用户持续滚动、快速重进聊天，或此时又切账号，旧原生读取仍可能和新读取同时占用 SDK/网络资源。迟到结果会受代次和 flight 检查保护，不会直接污染当前消息列表；风险主要是原生调用堆积后引发更慢的聊天历史、更多超时，甚至平台通道不稳定。是否能累积到用户可感知程度，需要目标设备复现。

建议：把逻辑超时与物理原生调用状态分开计数；对仍未完成的旧调用设置可观测的并发上限和退避策略，必要时在 SDK 层确认是否支持取消。通过可控的永不完成 Fake SDK 连续触发多次翻页和切账号，断言未完成原生调用数不会无限增长且新会话仍能恢复。

### 14. 相册备份的本地版本戳可能绕过内容哈希检查，导致同 ID 的新内容不上传

**严重度：P2 条件风险；代码行为置信度：高（平台资产 ID 被复用且可见元数据保持一致时）**

- `lib/src/services/device_sync_service.dart:753-756`：本地快照版本只由 `modifiedDateTime`、资产类型、宽高和时长组成；`snapshot[asset.id] == version` 时直接跳过，不会调用 `PhotoSyncCollector.prepareOne()`，也不会请求后端 `checkPhoto`。
- `prepareOne()` 生成的内容 hash 是上传后压缩图像或视频原文件的字节 hash；这能满足服务端合同，但只有进入上传路径才会计算。
- 用户提供的服务端合同明确规定：相同本地素材 ID 只有在内容 hash 与媒体类型都匹配时才算已备份。客户端的快照命中条件没有纳入 hash，因此并不能证明服务端内容仍是这一份。
- 当前 `test/photo_sync_contract_test.dart` 覆盖上传合同与回执，没有覆盖“同 asset ID、相同元数据版本、不同文件内容”时绕过 `checkPhoto` 的情况。

组合场景：平台资产 ID 被重用，或媒体内容在时间戳粒度内被替换，但修改时间、类型、尺寸和视频时长保持相同；本地快照命中后客户端跳过该项，服务端永远看不到新 hash，也就无法要求重新上传。云端会继续保留旧内容，设备侧显示备份完成但内容不一致。该场景依赖平台 ID/时间戳复用，需在 Android/iOS 相册中实测。

建议：用可验证的内容指纹作为跳过依据，或先对轻量稳定指纹做验证再决定是否需要读取完整文件；若坚持使用元数据快照，资产 ID 变更、修改时间精度和替换场景必须在目标系统验证，并对不确定条目回查服务端 hash。增加同 ID 同戳不同字节的合同测试。

### 15. 设备同步用全局布尔锁，账号切换时新账号的一次同步请求会被直接丢弃

**严重度：P2 条件风险；代码行为置信度：高（旧账号同步仍在等待时完成切换和新登录）**

- `lib/src/services/device_sync_service.dart:467-483`、`:491-515`：联系人和照片同步各用一个实例级 `_contactsSyncing` / `_photosSyncing` 布尔值；只要已有账号的任务没结束，新账号的调用立即返回，没有排队新身份或保存待运行任务。
- 同文件 `:483`、`:513-515`：旧任务结束时只清布尔值；它只按旧身份执行完成逻辑，不能保证再次调度当时已登录的新身份。
- `AccountSessionService` 普通退出/切号不会调用 `DeviceSyncService.clearForOwner()`；该方法只出现在显式清盘路径。账号代次会阻止旧响应提交，但不会立刻清掉全局同步锁或启动新账号的待执行任务。
- `DeviceSyncService._runPostLoginSync()` 对新登录只执行一次 `syncAfterLogin()`；如果该次撞上旧任务，`_syncContactsSafe()` 会返回，后续不自动重试。照片同步即使有空闲定时器，也可能在旧任务仍持锁时被同样丢弃。

组合场景：账号 A 的联系人状态请求遇到弱网等待，用户切到账号 B；B 的登录后同步撞上 `_contactsSyncing == true` 后立即返回。A 的响应晚到时会因身份失效而丢弃，`finally` 只释放布尔值，不会补跑 B。B 可能持续显示旧联系人投影或错过联系人增删，直到权限变化、重新登录或其他入口再次触发同步。照片同步也可能因 A 的对象上传/扫描仍占锁而延迟 B 的同步。

建议：把 single-flight 改为按账号身份分区，或在 busy 时记住最新待执行的 `SessionIdentity`，旧任务释放后只补跑当前身份；登出时主动取消可取消的旧工作。增加 A 同步挂起→切 B→B 首次同步→释放 A 的测试，断言 B 的同步一定执行且 A 的旧结果不落库。

## 性能关注点（需要 profile 证据后才能定性）

- 会话列表在 `lib/src/widgets/conversation_feed/conversation_feed_body.dart:776-881` 每次相关重建都会物化可见会话、生成 ID 列表并计算顺序签名；结构变化时再构建行和索引映射。虽然 UI 使用懒构建列表，父层准备工作仍随会话数线性增长。超大联系人/会话账号、频繁内容 revision 和低端 Android 叠加时可能造成掉帧，需用 release profile 测 500/2,000/5,000 会话规模的重建耗时与帧时间。
- 照片备份进度表目前由 `lib/src/services/photo_backup_progress_store.dart:13` 以 `enabled = false` 关闭；因此 `lib/src/services/device_sync_service.dart:781-789` 在每个成功/永久跳过项后都会把不断扩大的完整 `snapshot` 重新 JSON 编码并写入 SharedPreferences。N 项全新相册扫描存在约 1+2+…+N 的累计快照处理量。`photo_sync_collector.dart:201-220` 已先检查视频大小再哈希，旧审查中“超大视频先完整哈希”的问题已修复；本项仍需用大相册测量其序列化和持久化成本。
- 当前聊天历史入口采用受控分页/窗口和视口状态协调；本轮没有确认“当前入口必然导致滚动卡死/位置跳变”的单一静态缺陷。要复现用户反馈，应录制超长聊天记录下的快速上滑、加载旧页、连续来新消息、键盘升降、图片预览返回和账号切换组合，不应拿未使用的旧 ChatV2 路径作为结论。

## A01–A17 跨模块基线复核

| 基线 | 当前工作树复核结果 |
|---|---|
| A01 TCP / AI SSE 分块 UTF-8 | **已修复**：TCP 使用 `utf8.decoder` 流式变换；AI SSE 使用绑定到字节流的流式 decoder。 |
| A02 主动取消误计节点故障 | **已修复**：公共拦截器和 `_isNodeTransportFailure` 都排除 cancel。 |
| A03 网关错误被测速当作健康 | **已修复**：探测仅在 HTTP 200 且 payload 符合健康结构时记为 normal。 |
| A04 TCP auth_fail 后无法恢复 | **已修复主要路径**：凭证代次变化才清除拒绝状态；认证应答与心跳都有截止时间。 |
| A05 回前台重复验证/登录 | **部分修复**：ready 会话不再直接重做 SDK login；每次满足恢复节流的回前台仍会调用 `fetchMe`，但当前 `_state.isReady` 超时保护不会把普通慢探测改成 offline。还需真机验证频繁回前台时 `/me` 调用量和首屏等待。 |
| A06 SessionManager 重连不 single-flight | **已修复**：重连会登记为 `_activeOperation` 并按任务所有权释放。 |
| A07 关系校准等待 15 秒后强行运行 | **已修复**：期限到达后返回不可运行并延迟重试，不再默认放行。 |
| A08 旧关系校准改写新会话阶段 | **已修复主要路径**：请求捕获 `_sessionEpoch` 和 request token，阶段提交/释放前检查所有权。 |
| A09 iOS 关库阻塞后写门无法恢复 | **条件风险仍在**：生命周期回调最多等待 2 秒并报 degraded，但不会取消/替代挂起的 native close；close 永不结束时 `_closeInFlight` 和写门可一直保持关闭。没有设备证据证明用户已遇到。 |
| A10 `runApp` 被非首屏初始化挡住 | **已修复主要问题**：`runApp(RecoverableStartup(...))` 在主要 bootstrap 任务前执行，许多可选服务移到首帧后。必需身份/本地状态仍会决定何时开放登录或消息页面。 |
| A11 联系人增量仍上传完整集合 | **按当前明确约束保留**：`ContactSyncPlan.deviceScopedDeltaEnabled` 当前为 false；服务端合同要求差量开关继续关闭。不要把 legacy 全量请求误判为意外开启新协议。 |
| A12 相册快照与大视频哈希成本 | **部分修复**：超限视频改为先查大小后哈希；大相册仍逐项重写完整快照，见性能关注点。 |
| A13 AI stop 残留 streaming / 旧错误污染新回复 | **已修复主要路径**：显式 stopped 状态、reply turn token 和 session identity 检查覆盖旧异步结果。 |
| A14 AI 每个 delta 重建页面并强制到底部 | **已修复主要路径**：delta 由当前回复的 `ValueNotifier` 发布并以 frame/50ms 合并；滚动只在用户仍跟随底部时安排。 |
| A15 钱包离开 Tab 后仍刷新 | **已修复**：不活跃 Controller 收到余额变化只标 dirty，重新激活时再加载。 |
| A16 撤回失效后仍提交/视口卡死 | **撤回控制流已修复主要缺口**：命令捕获会话与聊天代次，mutation scope 失效时做补偿清理并 return。视口 gate 与白屏现象仍需真机日志确认。 |
| A17 相册权限自动开启备份 / 明文传输 | **当前工作树仍未解决，且应独立优先**：首次照片权限存在时 `enableIfUnset` 会把备份默认设为 true；新安装 API 默认节点为 HTTP，TCP 节点也使用 HTTP scheme。详情见下节。 |

### A17. 照片访问授权会隐式开启云备份，默认网络配置缺少传输加密

**优先级：独立高优先级；代码事实置信度：高；正式安装包是否与当前目录一致仍需核对**

- `lib/src/services/api_node_service.dart:58-75`：新安装默认 `cn`；其 API 和实时 TCP 地址均为 `http://`。`hydrate()` 在没有有效保存选择时使用该默认值，见同文件 `:142-169`。
- `lib/src/api/api_client.dart:174-183`：非公开 API 请求会把业务 JWT 放入 `Authorization: Bearer ...` 请求头；若实际目标是上述 HTTP 节点，请求和凭证没有 TLS 传输保护。
- 同文件 `api_node_service.dart:66-71`：另一个节点的 API 是 HTTPS，但其 realtime TCP 地址仍是 HTTP scheme；`friend_realtime_connection_io.dart:29-45` 默认 `useTls = false`，由 `FriendRealtimeService` 将节点 scheme 传给连接层。实时认证帧含业务 token。
- `android/app/src/main/AndroidManifest.xml:38` 全局设置 `usesCleartextTraffic="true"`，因此 Android 不会替这些 HTTP 目的地挡下明文请求。iOS 的 `ios/Runner/Info.plist:35-57` 例外域名和节点目录也不一致，正式 iOS 路径应单独验证。
- `lib/src/services/photo_backup_consent.dart:39-55`：`enableIfUnset` 在尚无用户设置时写入 `true`；`device_sync_service.dart:324-345` 在发现照片权限已允许时调用该方法，之后会安排相册备份。

组合场景：新安装或没有保存过节点选择的用户登录后授予相册访问权限，但没有单独表达“把个人照片上传到云端”的意愿；照片备份开关被静默启用，空闲扫描之后开始备份。与此同时，默认节点配置把认证 API 和实时认证流量发到明文传输地址。代码本身证明了默认配置和授权流程，但不能单凭静态审查证明某次线上请求已被截获，也不能证明当前发布包未通过外部配置替换 endpoint。

建议：相册备份必须默认关闭，照片权限与云备份目的授权分离；业务 API 和实时认证流都使用验证证书的 TLS，故障切线不得降级到 HTTP。优先对照 3.0.1+20 实际 APK 的编译 endpoint、节点覆盖配置和网络抓包验收。

## 建议的复现矩阵

| 入口 | 叠加条件 | 重点观察 |
|---|---|---|
| 冷启动 | Android 安全存储延迟 0/4/9/15 秒；有效 JWT | 是否误到登录页；恢复后路由是否自动修正 |
| 会话列表 | 原生首屏读延迟 9/20/永久挂起；超时中切账号 | 新账号首屏是否自动补拉；空列表是否需要手动刷新 |
| 媒体发送 | 选 9 个大图/多个长视频；Outbox 前强制结束进程 | 重启后每个媒体项是否仍可恢复，是否重复发送 |
| 媒体队列 | 旧账号 3 个图片发送挂起，连续经历 3 分钟超时并继续发图，再切新账号 | 新账号首发延迟；超时底层 Future 未结束时的实际 SDK 并发数与资源占用 |
| IM 登录清理 | connect 阶段断网/杀回调，再立即退出或切账号 | 清理是否在可接受时限内完成，旧回调是否污染新会话 |
| 通话建连 | CallKit 音频交接/LiveKit connect 延迟超过 60 秒，建连后恢复前台 | connecting 是否超时收口；caller 是否仍有振铃截止时间 |
| 自动账号失效 | 相册 100 MB 视频 PUT 中触发 token 过期/被踢并立即登录新账号 | 旧 PUT 是否被取消；新账号消息与媒体请求是否仍受带宽竞争 |
| 在线恢复 | 保持 IM ready，再让 `/me` 或安全存储超过 8 秒 | SessionState 是否继续保持 ready；是否仅对明确鉴权失效执行登出或重登 |
| 聊天滚动 | 超长历史、低端 Android、后台回前台、键盘/预览切换 | 90/120Hz 帧丢失、视口跳动、分页重复或漏消息 |
| 相册备份授权 | 新账号已有系统相册权限、未碰备份开关、Wi-Fi 且空闲 | 是否静默上传；大相册每项快照序列化/写盘成本 |
| 发布网络配置 | 清除节点偏好后冷启动 Android/iOS | 实际 API/TCP scheme、JWT 是否只经 TLS；iOS ATS 失败是否影响登录 |

## 本轮自动化验证

- 10 个定向测试文件共 77 条测试全部通过，覆盖会话恢复、会话列表 SDK 读取截止时间、系统相册恢复、照片上传合同、设备同步基础语义、iOS APNs 注册队列、群成员游标策略和 LiveKit 会话恢复。
- `flutter analyze --no-pub lib` 没有 error 级诊断；共报告 857 条 lint/info/warning，因此 Flutter 命令仍以非零状态退出。没有对比干净基线，不能把这些提示都算作本轮新增或旧问题。全仓 `flutter analyze --no-pub` 会继续扫描 `artifacts/` 中的基线拷贝/探针和独立第三方测试，报告 8,208 条混合诊断，其中大量是这些副本的无效相对导入，不能代表应用源码编译状态。
- 没有运行完整测试套件或 Android/iOS 真机测试；弱网、后台终止、长列表和原生 SDK 永不返回仍需要目标设备验证。

本轮没有修改业务源代码。定向测试验证了现有覆盖路径，但无法证明前述未覆盖竞态已解决。若进入修复阶段，应先以最终合并后的工作树重新做调用图影响检查，再为未解决的会话、会话列表、媒体交接、相册授权/网络传输风险补足自动化回归与目标设备压力复现。

### 16. 联系人状态查询失败会直接退回全量兼容同步

**严重度：P3 条件性性能/稳定性风险；代码路径置信度：高（状态查询失败，但后续写接口仍可用，且设备通讯录已授权）**

- `lib/src/services/device_sync_service.dart:534-541`：`fetchStatus()` 除 `DEVICE_NOT_BOUND` 和新协议开关开启外，其他异常一律转成 `status = null`；当前 `ContactSyncPlan.deviceScopedDeltaEnabled` 为 `false`，所以网络超时、5xx 或不支持状态路由等错误都会继续走旧兼容流程。
- 同文件 `:544-546` 将空状态视为没有任何同步基线并选择 `FULL`；`:568-585` 收集并分批上传当前全部联系人，再提交 session。旧路径每批最多 100 条，联系人多时会产生连续请求。
- 当前 `test/sync_contract_service_test.dart` 验证的是状态请求成功返回能力信息后仍走旧合同；没有覆盖 `/status` 发生瞬时错误、而 sessions/batch 随后成功的情况。

组合场景：弱网下状态读取超时，但网络很快恢复、后续 POST 可达；或者状态路由短时故障但旧写接口仍在线。一次登录后的同步就会从未知状态退回全量上传全部联系人，增加首屏期间的流量和服务器写负载。若会话或 batch 也不可用，这些后续请求会失败并由外层记录；代码没有在状态失败处先退避或等待重试。现有流程通常只在登录后或通讯录权限新授予时触发，不应描述成持续后台无限重试。

建议：把“能力/基线明确不存在”与“状态未知（网络、5xx、鉴权以外错误）”区分；仅前者使用 FULL 兼容同步，后者保留待重试状态并避免立即发起整本通讯录上传。若为兼容旧服务端必须回退，应为回退加单次会话预算和可观测原因。

## 本轮继续复核及验证

- 另行检查联系人协议事务、朋友圈存储、钱包全局状态、聊天搜索请求和媒体工作队列。钱包 `WalletStore` 当前使用 owner/session epoch 拦截过期结果；搜索模型也按请求代次隔离，并限制单次历史回扫页数。它们的旧请求串写问题在当前工作树已有代码保护，不计为现存缺陷。
- `MomentsStore` 的账号归属仍在网络返回后动态读取，`MomentsFeedController` 也没有请求代次门槛；账号切换与旧 feed/互动响应交错时仍可能污染新账号缓存/页面，对应第 5 项仍成立。
- 本轮顺序运行了 13 个定向测试文件，均通过（约 92 条断言，含若干参数化用例）：联系人合同与真实 DeviceSync 服务、朋友圈本地缓存、钱包归属、搜索请求范围、媒体队列/系统选择器恢复、iOS APNs 队列、群成员游标及可恢复启动。通过表示这些回归断言成立，不代表相关未覆盖竞态已修复。
- 本轮仍未运行 1,051 个应用测试文件的完整套件，也未连接 Android/iOS 真机或正式服务；并行工作区仍持续变化，结论必须在最终合并树复查。

### 17. iOS 图片压缩先解码原图，跨平台队列按已采样尺寸低估内存

**严重度：P2 条件性稳定性风险；代码路径置信度：高（大尺寸图片触发时）；实际峰值与闪退影响需设备测量**

- `third_party/tencent_cloud_chat_uikit/lib/ui/utils/chat_media_send_utils.dart:826-845` 根据计算后的 `sampleSize` 估算解码工作内存，并在 `:914-927` 把该权重交给共享图片解码队列；但 `inSampleSize` 只在 Android 传 `admission.sampleSize`，iOS 固定传 `1`。
- 当前锁定的 `flutter_image_compress_common 1.1.1` iOS 实现先用 `UIImage imageWithData:` 建立源图，再由 `scaleWithMinWidth:` 绘制缩放。该原生实现没有像 Android `BitmapFactory` 那样按传入的 `inSampleSize` 解码；缩放发生在源图对象创建之后。Android 的路径则会把 sample size 交给 `BitmapFactory.Options`。
- `OutgoingMediaWorkQueue.imageDecode` 的并发上限是 2、权重上限是 96 MiB；单项估算超过上限会被权重夹到上限后单独运行，而不是拒绝或降级。于是 iOS 高像素图片（例如 48MP）虽然按缩放后的采样尺寸计入队列，实际仍可能先解出完整源图，并同时创建缩放/编码缓冲区；队列权重并不再代表 iOS 的真实峰值内存。
- `third_party/image_picker_ios/.../FLTImagePickerPlugin.m:484-531` 还把多选原生导出设为串行，并在全部保存完成后才把路径列表回给 Dart。JPEG/PNG/GIF 常规分支主要是逐个复制编码文件，不应误称为逐个重编码；但这会把多选批次的原生等待全部放在 Dart 首次处理/发送之前。它可能放大用户感知到的“选了图后卡住”，尤其在慢速相册存储和多选组合下。
- `test/media_decode_safety_test.dart` 和 `third_party/tencent_cloud_chat_uikit/test/gallery_adjacent_decode_budget_test.dart` 共 9 条定向测试通过，但覆盖的是 Dart 采样估算、队列和相邻缩略图安全规则；没有断言 iOS 原生分配量或多选首项等待时间。

组合场景：iOS 用户选择多张 48MP 原图，原生选择器先串行导出整个选择集合，然后 Dart 侧逐项压缩。原生压缩器对当前图片分配全尺寸解码和缩放中间图，尽管队列依据采样尺寸进行权重调度；在内存较紧、后台应用刚恢复或聊天图片预览也占用解码资源时，可能产生明显停顿、系统内存压力或进程被系统终止。静态代码不能证明具体机型会达到多少峰值，也不能单独证明这是已上报闪退的原因。

建议：为 iOS 改用能在解码阶段创建缩略图的 ImageIO 流程，或至少用未采样源像素数计算其队列权重并对超预算输入分段/降级；多选导出若要并发，需以 iOS 真机内存峰值评估后再调整并发度。验收记录每张源图的等待、压缩耗时、峰值内存、系统 jetsam/退出原因，并测 12MP/48MP、1/9 张选择、聊天滚动或预览同时运行的组合。

### 18. 聊天退出/切号后，迟到的媒体预取可能把旧账号消息写入新账号的本地分区

**严重度：P2 条件性账号缓存隔离风险；异步写入路径置信度：高；用户可见后果取决于消息键重合和后续读取**

- 当前活动路径在 `lib/src/chat.dart:4609-4647` 调用 `resolveOnlineUrlsForMessages()`；其单条请求 `lib/utils/chat_image_message_prefetch.dart:744-767` 在 SDK 返回后无条件更新消息对象，并通过 `upsertFromMessage(message)` 落库。请求等待期间没有捕获账号 `SessionIdentity` 或启动时 `ownerUserId`，外层页面在稍后检查 `canRun()` 不能撤销这次内部写入。
- 同一文件 `:148-178` 的缩略图下载队列以及 `:707-724` 的 URL 请求合并表都只按 `msgID` 去重，没有按 owner/session generation 分区；另 `:283` 下载结束后仍调用 owner 未显式指定的 `upsertFromMessage(source)`。
- `:382-401` 的 `_enrichOpenPrefetchInBackground()` 也有同样的动态 owner 风险。不过全仓文本搜索与 GitNexus 图都没有找到 `prepareBeforeChatOpen()` 的当前调用点，因此这条只作为未连接 helper 的潜在风险，不计入当前活跃路径结论。
- `lib/src/services/message_media_metadata_store.dart:229-257` 会在写入时从当前登录态动态推导 owner。存储表虽然按 `(owner_user_id, message_key)` 隔离，但迟到的 A 账号消息若在切到 B 后完成，其 URL/缩略图元数据就会进入 B 的 owner 分区。`ChatPageScope` 仅用于部分图像解码/页面生命周期判断；URL 查询与这些写入路径没有用 token 作废保护。
- `test/chat_image_message_prefetch_test.dart`、`test/chat_image_prefetch_lifecycle_test.dart`、`test/conversation_peek_async_media_test.dart` 和 `test/message_media_metadata_store_test.dart` 覆盖了队列上限、图片缓存释放、预览请求新旧代次与元数据写入，但没有覆盖“账号 A 的 URL 查询挂起→切至 B→A 查询返回→写入 owner”的组合。

组合场景：A 打开包含远程图片的聊天，图片 URL 查询或缩略图下载尚未结束时退出并切到 B；后台请求继续运行，回调把 A 的媒体地址写到 `MessageMediaMetadataStore` 当前解析到的 B 分区。下载/URL 去重表还可能把 B 的同 ID 消息挂到 A 开始的旧任务。最直接的确定影响是本地 B 分区混入 A 的记录；若消息键和会话键后来重合或被复用，B 的历史消息可能 hydration 到错误的 URL/本地路径。当前没有证据表明不同账号常规消息 ID 会重合，所以把错误显示视为条件后果，不把它陈述成必然发生。

建议：在每次预取/URL 查询启动时捕获 `SessionIdentity` 与 owner，回调写消息对象、落库、通知全局模型之前校验代次仍有效；metadata store 的写入接口要求显式 owner，避免异步返回后重新读取当前账号。添加 A 请求挂起→切 B→释放 A 的测试，并同时断言 A 结果不更新 B 的记录、不触发当前页面投影。

### 本轮新增定向验证

- 运行 `chat_image_message_prefetch_test.dart`、`chat_image_message_prefetch_oversize_test.dart`、`chat_image_prefetch_lifecycle_test.dart`、`conversation_peek_async_media_test.dart`、`message_media_metadata_store_test.dart`：全部通过，共 15 项测试。现有测试通过只证明已有断言成立；它们没有覆盖第 18 项的跨账号迟到写入场景。
- 补充运行 `chat_page_scope_test.dart`：5 项通过。它验证页面投影 token 的失效行为，但没有覆盖后台预取直接写入账号分区的路径，因此第 18 项仍未被现有测试否定。
- 同一风险也存在于缩略图下载完成后的 `chat_image_message_prefetch.dart:283`：运行任务只在开始/返回处检查前后台，不携带账号身份，下载结束后仍会调用按当前 owner 写入的 `upsertFromMessage()`。
- 另检查到 `_loadPeekForConversation()` 的 `_peekInFlight` 只按 conversation key 去重，但它仅由当前没有调用方的 `prepareBeforeChatOpen()` 使用；因此本报告没有把该 Future 合并风险列为当前运行时缺陷。若之后重新接入该入口，应把账号 owner 与 generation 纳入 key。

### 本轮补充：长历史滚动的条件性 CPU 热点（待 profile）

- `third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart:6165-6278`：每次滚动通知会合并到 post-frame 读取进度采样；若用户正在读旧历史且仍有新消息未读，边界发生变化后会遍历阅读边界后面的消息段，分别标记实时未读与填充待确认消息。页面消息窗口可在持续阅读时增长到 `ChatMessageWindowPolicy.historyReadSoftMax = 3000`。列表主体是 `CustomScrollView + SliverList`，常态窗口上限 280、缓存距离 800px，所以没有发现“每帧构建全部历史行”的缺陷。
- 变化后的边界若沿着长窗口逐步移动，重复扫描后缀会形成条件性 CPU 负担；最相关的组合是低端 Android、长时间翻旧记录、期间持续收到新消息。扫描是否超过设备帧预算尚无数据，暂列 profile 项而非已证实卡顿原因。
- 定向运行 `test/history_durable_scroll_to_latest_test.dart`：23 项长历史/分页/新消息滚动回归通过，历时约 95 秒。用例验证锚点和行为正确性，不采集 60/90/120Hz 真机帧耗时。
