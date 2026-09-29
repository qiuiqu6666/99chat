import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/android_performance_profile.dart';

/// 会话同步写库节奏开关（Phase 1：缓解 SDK 连续拉页写库卡顿/发烫）。
/// 热窗优先：首屏 `loadUiWindow` 默认读取本地完整会话行，UI 通过虚拟列表按需水合。
/// **禁止**挂机 idle 为「对齐腾讯全集」无限翻页；其余会话触底/增量再拉。
/// UI 列表：硬顶默认关；滑动窗默认开（内存裁切，触顶/触底再从库补页）。
/// 返回卡顿靠「禁止整窗 ByIds」+ 滚动中延后 UI 通知。
/// 数值只准改本文件。
class ConversationPerfFlags {
  ConversationPerfFlags._();

  /// `true`：`reset`/`force` 只重置游标，前台限页 + 后台 drain；`false`：恢复旧「reset 可一口气拉全量」。
  static bool pacedSdkPersist = true;

  /// SDK 持有完整会话库。页面按需翻页，业务归档只维护自己的索引，
  /// 登录后不再为了另一份全账号镜像持续分页和写 SQLite。
  static const bool idleBackgroundDrainEnabled = false;

  /// 后台 drain 页预算。`<=0` 表示持续到 C2C/群游标都完成；每页仍让出
  /// 主线程，避免冷启动补全影响发送和当前聊天窗口。
  static const int idleDrainSessionPageBudget = 0;

  /// 单次登录会话内 idle drain cycle 上限。
  /// 防止 `idleDrainSessionPageBudget<=0` + haveMore=true 时无限续期，
  /// 导致每条新消息/恢复前台都触发一次完整 SDK 拉页。`<=0` 表示不封顶。
  static const int idleDrainMaxCyclesPerSession = 5;

  /// 回前台 coalesce 单帧最多 flush 条数，余量 post-frame 续刷。
  static const int resumeForegroundCoalesceBatchCap = 40;

  /// `true`：从聊天返回后的 soft reload 只 patch 刚离开会话，禁止整窗 `conversationsByIds`。
  static const bool postPopLightReloadEnabled = true;

  /// soft / merge-preserve 单次 `conversationsByIds` 条数帽。
  /// `<=0`：不按条数截断（生产路径应禁止整窗 ByIds，不依赖本帽）。
  static const int softReloadByIdsMax = 0;

  /// 前台最多连续拉/写页数（页大小见 sync 服务 `_defaultPageSize`）。
  static const int bootstrapForegroundPages = 2;

  /// 后台 drain 页与页之间让出主线程。
  static const Duration backgroundPageYield = Duration(milliseconds: 80);

  /// 后台 drain 每完成一页就刷新一次会话投影，确保续翻写库后当前进程可见。
  static const int backgroundUiRefreshEveryPages = 1;

  /// 前台限页结束后多久才允许开始 idle drain。
  static const Duration idleDrainStartDelay = Duration(seconds: 3);

  /// 空库 IM Snapshot 成功后，再推迟多久才开腾讯分页 idle drain（单次 Timer，不叠加 [idleDrainStartDelay]）。
  static const Duration snapshotDrainStartDelay = Duration(seconds: 8);

  /// 登录快照只负责优先补齐最近单聊；群列表和完整游标继续由 SDK 同步。
  static const int snapshotPriorityC2cLimit = 20;

  /// Snapshot 后端分路参数的契约下限；响应中的群和 preload 不提交到聊天窗。
  static const int snapshotRequestGroupFloor = 1;
  static const int snapshotRequestMessageFloor = 30;

  /// `false`：登录不走后端 IM Snapshot，首屏直接用本地会话库，再按需 SDK 分页同步。
  /// `true`：恢复「有库也 Snapshot 暖窗」方案 B。
  static const bool attemptImSnapshotOnLoginBootstrap = false;

  /// A 块（v15/v16 改造）：`bootstrapTypedFirstScreen` 的 `reset` 默认值。
  /// `false`：rebase-aware 路径，保留旧 cursor，幂等续拉，避免破坏未完成同步位点。
  /// `true`：恢复旧行为——重置 cursor 从 0 拉（仅在业务显式需要时打开）。
  /// 配合 A3 埋点 `cold_start_no_full_drain` 验证 cold_start 路径不再触发全量 drain。
  static const bool bootstrapTypedDefaultReset = false;

  /// E 块（v15/v16）：每会话拉取历史消息的上限（聊天页上拉历史）。
  /// 项目实际使用 `count: 20`（SDK 推荐值，v15 §12.19 业界共识），已通过 audit。
  /// 这里用常量封装以便未来调整——参见 `chat.dart` 中所有 `count: 20` 调用。
  /// 调整为：保留 20；如历史消息需要更大窗口，未来可调整。
  static const int offlinePullPerConvLimit = 20;

  /// E8 占位消息降级（v15/v16 audit 结论）：
  /// 当前 Flutter SDK 8.7 的 `V2TimMessage` 模型不暴露 `isPlaceMsg` 字段
  /// （v15 §12.19 提到的是 Android/iOS 原生 SDK 的能力）。撤回处理由 UIKit 内部
  /// 通过 `V2TIM_MSG_STATUS_LOCAL_REVOKED` 完成，无需项目层加 isPlaceMsg 降级。
  /// 后续升级 SDK（如 9.x）暴露 `isPlaceMsg` 时再加此功能。
  static const bool isPlaceMsgFallbackEnabled = false;

  // ====================================================================
  // FFB（v17 / iOS sqflite_darwin PRAGMA busy_timeout 救火）开关
  // ====================================================================

  /// FFB-1.1：iOS 启动早期 `openDatabase` 的 `onOpen` 回调里执行
  ///   `PRAGMA busy_timeout = 5000` 时偶发 "not an error" 抛出。
  /// 该 flag 为 `true` 时：捕获该异常并打 `conv_db_open_pragma_busy_timeout_failed`
  /// 但不 rethrow，让 DB open 继续；为 `false` 时：保持原异常上抛。
  /// 默认 `true`：线上已确认 DB 内 `PRAGMA busy_timeout` 已经设置成功，不需要再阻断。
  static const bool openDbPragmaIgnoreFailure = true;

  /// FFB-1.2：单次冷启动内 `_openDb` 失败次数上限。
  /// 超过该值 → 走内存分支（参考 web `_useMemoryOnly` 路径），并打
  /// `conv_db_open_give_up_memory_only{ count, durationMs }`。
  /// `<=0` 表示不限次数（保持"始终尝试"）。默认 `8`。
  static const int openDbMaxRetryInWindow = 8;

  /// FFB-1.2：失败计数器窗口时长（毫秒）。超过该时长后计数器归零，
  /// 让长跑应用有机会恢复 DB 直连。
  /// `<=0` 表示不归零（永久累积）。默认 `8000`。
  static const int openDbRetryWindowMs = 8000;

  /// FFB-4：失败埋点节流间隔（毫秒）。
  /// 第 1 次失败立刻打埋点；之后该间隔内不再打（避免 log 雪崩）。
  /// `errCategory` 切换（如 `pragma_busy_timeout_failed` → `corrupt`）会强制突破节流。
  /// `<=0` 表示每次失败都打。默认 `5000`。
  static const int openDbFailedThrottleMs = 5000;

  /// UI 列表总硬顶。`<=0` 表示无硬顶（不因长度拒收 append）。
  static const int uiWindowHardCap = 0;

  static bool get uiWindowHardCapEnabled => uiWindowHardCap > 0;

  /// 滑动窗口裁切。`false`：只追加不裁顶（无上限列表，用久了更卡）。
  /// 注意：即使为 `true`，[uiAppendOlderGrowsWindow] 开启时触底 append 仍只增不裁。
  static const bool uiSlidingWindowEnabled = true;

  static bool get uiSlidingWindowActive => uiSlidingWindowEnabled;

  /// 滑动窗 / patch 锚点裁切预算。`<=0` 表示不裁。
  /// 触底翻页在 [uiAppendOlderGrowsWindow] 下不受此限。
  static const int uiSlidingWindowBudget = 600;

  /// `true`：下滑加载更旧会话时先抬高该类型显示数量（可超过 [uiSlidingWindowBudget]）。
  /// 超过 [uiAppendOlderMaxPerType] 后只裁**当前翻页类型**，对侧类型保留，
  /// 避免滑群把单聊 tab 挤空（单聊往往更旧、排在列表后段）。
  static const bool uiAppendOlderGrowsWindow = true;

  /// 触底扩窗：每个会话类型（单聊/群）各自的软上限。
  /// `<=0` 表示该类型不设软顶。
  static const int uiAppendOlderMaxPerType = 600;

  /// 下滑续载的紧急上限（按类型）。
  /// `<=0` 表示不按长度裁切窗口。
  static const int uiAppendOlderEmergencyMaxPerType = 600;

  /// @Deprecated 兼容旧名；请用 [uiAppendOlderMaxPerType]。
  static const int uiAppendOlderMaxWindow = uiAppendOlderMaxPerType;

  /// 方案 C：上滑 prepend 的单页长度；两阶段回顶时先拉这么多。
  /// 软裁本身按视口连续切片，不再拆热头+旧尾。
  static const int uiAppendOlderHotHeadReserve = 40;

  /// 裁切时优先保留的置顶条数（仅 budget>0 且滑动开启时有意义）。
  /// 软裁路径会保留**全部**置顶；本值只约束 budget 锚点裁切。
  static const int uiSlidingWindowPinnedReserve = 16;

  /// 锚点裁切时「未读优先」条数上限。大账号群几乎全未读时若无上限，
  /// 会占满预算，触底 append 的更旧页进不了窗（noop），并挤掉已读单聊。
  /// `<=0`：关闭未读优先。
  static const int uiSlidingWindowUnreadReserve = 24;

  /// `true`：`upsertBatch` 入口短延迟合并 + 写串行，压碎片并发 txn。
  static const bool upsertWriteCoalesceEnabled = true;

  /// upsert 写合并窗口。
  static const Duration upsertWriteCoalesceDelay = Duration(milliseconds: 100);

  /// 列表滚动 / 进出聊天时拉长合并，错开手势帧。
  static const Duration upsertWriteCoalesceDelayBusy = Duration(
    milliseconds: 180,
  );

  /// 单个 SQLite 事务最多处理的会话数。只拆事务，不丢数据、不限制会话总数。
  static const int upsertTransactionChunkSize = 200;

  /// 连续流量下的最长等待，避免 quiet window 被不断重置而饥饿。
  static const Duration upsertWriteCoalesceMaxDelay = Duration(
    milliseconds: 250,
  );

  /// 忙碌态最长等待（滚动/聊天切换/post-pop）。
  static const Duration upsertWriteCoalesceMaxDelayBusy = Duration(
    milliseconds: 400,
  );

  /// ViewModel → 本地库 persist 去重窗口（闲时）。
  static const Duration persistDedupDelay = Duration(milliseconds: 60);

  /// 忙碌态 persist 去重窗口，减少「写库刚完又刷列表」。
  static const Duration persistDedupDelayBusy = Duration(milliseconds: 200);

  /// SDK `onConversationChanged` / `onNewConversation` 热路径 persist 去重（闲时）。
  static const Duration persistDedupDelayConversationListener = Duration(
    milliseconds: 32,
  );

  /// SDK 会话监听热路径 busy 去重。
  static const Duration persistDedupDelayConversationListenerBusy = Duration(
    milliseconds: 64,
  );

  /// 分页同步中预览 patch 最长排队；超时强制落地（仍不改 unread）。
  static const Duration pendingPreviewPatchMaxWait = Duration(
    milliseconds: 1200,
  );

  /// `true`：打 msg→callback→persist→ui 三段耗时探针（`[ConvPerfGate] realtime_latency`）。
  static const bool conversationRealtimeLatencyLogEnabled = false;

  /// `true`：无 `[` 的预览走纯 Text（滚动性能）；含内置表情 token 时仍走 ExtendedText。
  static const bool conversationListPlainPreviewText = true;

  /// 滚动中写库完成后：合并排队，停滑后再刷新列表 UI。
  /// 会话列表手感优先于毫秒级实时重排，避免高速滑动时被消息回调打断。
  static const bool deferUiNotifyWhileFeedScrolling = true;

  /// Chat 页打开时：推迟会话列表 Feed 的 `notifyListeners`（角标仍走 UnreadAggregate）。
  /// `false`：聊中也刷离屏 Feed（列表实时性优先）。
  static const bool deferUiNotifyWhileActiveChat = true;

  /// SDK-primary committed rows are durable in SQLite before they reach the
  /// TabStore. While Chat owns the foreground, keep non-visible rows in a
  /// coalesced projection buffer instead of repeatedly copying and sorting the
  /// full conversation window on the UI isolate.
  static const bool deferTabStoreProjectionWhileActiveChat = true;

  /// Chat 页内列表 UI notify 最长推迟；到期仍 flush 一次，防永不回列表饿死。
  static const Duration activeChatUiNotifyMaxDefer = Duration(
    milliseconds: 1200,
  );

  /// 冷启动期（bootstrap / idle_drain 未结束）节流 tabStore projection，
  /// 避免 im_ingress 风暴期反复 rebuild 会话列表。结束信号：
  /// `ConversationTabStore.notifyColdStartEnded()`。
  /// 启动期默认开；若关闭则与旧行为等价（每次 apply 都立即 rebuild）。
  static const bool deferTabStoreProjectionDuringColdStart = true;

  /// 冷启动期单次 flush 后，下一次 flush 的最小间隔（trailing debounce 窗口）。
  static const Duration coldStartUiNotifyTrailingDebounce =
      Duration(milliseconds: 100);

  /// 冷启动期连续节流上限：到期仍强制 flush 一次，防累积饿死。
  static const Duration coldStartUiNotifyMaxDefer =
      Duration(milliseconds: 1200);

  /// 冷启动窗口兜底关闭时长。正常由 post-home 同步完成时
  /// `ConversationTabStore.notifyColdStartEnded()` 关闭；本值只在那条链路断裂
  /// 时保护列表实时性——窗口不关会让 SDK push 一直 preserveOrder，
  /// 列表既不重排也不通知。
  static const Duration coldStartWindowFallbackDelay = Duration(seconds: 10);

  /// `true`：聊中 maxDefer 到期仍整表 `notifyListeners`（旧行为）。
  /// `false`：只保持 pending + 攒脏 ID，禁止聊中整表 flush。
  static const bool activeChatMaxDeferFullFlushEnabled = false;

  /// `true`：离开聊天不整表 reload，只 patch 刚离开会话；挂起的 Feed notify 仍会 flush。
  static const bool chatLeavePatchLeftOnlyEnabled = true;

  /// `true`：deactivate/dispose 对同一 leave 只交还一次。
  static const bool chatLeaveFlushDedupeEnabled = true;

  /// `true`：离页草稿时序打点。仅 `kDebugMode` 下 `debugPrint`；
  /// 禁止打印原文、原始 conversationId。
  static const bool draftLeaveTraceEnabled = true;

  /// `true`：进聊期间脏会话 ID 延后分批补齐（非整表 notify）。
  static const bool activeChatDirtyCatchUpEnabled = true;

  /// 离开聊天后脏补齐延迟（未在滑时）。
  static const Duration postChatLeaveCatchUpDelay = Duration(
    milliseconds: 1200,
  );

  /// 脏补齐每批会话数。
  static const int activeChatDirtyCatchUpBatchSize = 20;

  /// `true`：两边 Conversation 的 folder_unread 单飞。
  /// 实现须用「单 bit pending + 结束后 microtask 补一次」，
  /// 禁止 per-join `whenComplete→schedule`（会同步风暴冻 UI）。
  static const bool folderUnreadSingleFlightEnabled = true;

  /// `true`：每个 in-flight 世代最多打 1 条 `folder_unread_single_flight_join`。
  static const bool folderUnreadSingleFlightJoinLogOncePerFlight = true;

  /// `true`：离开聊天不立刻跑 folder_unread，跟 catch-up/停滑。
  static const bool folderUnreadDeferOnChatLeave = true;

  /// `true`：离开聊天不立刻续 incomplete HistoryWarm。
  static const bool historyWarmDeferResumeAfterChatLeave = true;

  /// 离开聊天后 HistoryWarm 抑制时长。
  static const Duration postChatLeaveWarmSuppress = Duration(seconds: 8);

  /// `true`：C2C 会话行 `onTapDown` 即开始 LOCAL-only 历史预热。
  /// 预热不打云，进聊路径仍负责云端首窗和完整性校验。
  static const bool pressWarmOnTapDownEnabled = true;

  /// `true`：群聊行允许按下目标会话时 LOCAL warm 这一条。
  /// 群聊不做批量 press，不走 CLOUD，只给用户明确按下/点击的目标让路。
  static const bool groupPressWarmOnTapDownEnabled = true;

  /// 首页会话列表不自动预热其它会话的历史消息。
  ///
  /// 会话列表首屏只需要会话摘要；批量读取消息历史会与 IM SDK 数据库、
  /// 会话 SQLite 和消息列表解析争抢资源。明确打开/按下某个聊天时的
  /// target/press warm 不受此开关影响。
  static const bool historyWarmAutomaticListEnabled = false;

  /// `true`：`conversationsByIds` 日志带 caller。
  static const bool conversationsByIdsCallerLogEnabled = false;

  /// `true`：Chat 打开时仍 apply 内存窗（角标 delta）；仅 defer Feed notify。
  /// `false`：Chat 打开时连 persist UI apply 一并挂起（更省，角标靠 scheduleRefresh）。
  static const bool persistUiApplyWhileActiveChat = true;

  /// `false`：滚动中写库后不 apply / 不排会触发 loadUiWindow 的 soft；停滑 flush。
  /// `true`：滑动中也立刻 apply（列表实时性优先，但会更容易打断滚动帧）。
  static const bool persistUiApplyWhileFeedScrolling = false;

  /// `false`：resume quiet 窗内写库后不立刻灌 UI（可 schedule 角标）。
  static const bool persistUiApplyInResumeQuiet = false;

  /// `true`：`loadUiWindow` 单飞，并发调用合并到同一 Future。
  static const bool loadUiWindowSingleFlight = true;

  /// `true`：`loadUiWindow` 进行中若再有请求，结束后再跑一轮脏读，
  /// 所有等待方拿到最终结果（压冷启连环 begin）。
  static const bool loadUiWindowCoalesceWhileBusy = true;

  /// `true`：`ensurePinnedPresentInWindow` 仅 missing 时 ByIds，
  /// 且等待 upsert 写队列空闲后再读，避免与写库互顶。
  static const bool ensurePinnedWaitsUpsertIdle = true;

  /// ensurePinned 等待 upsert 空闲的上限；超时仍读，防饿死。
  static const Duration ensurePinnedUpsertIdleMaxWait = Duration(
    milliseconds: 800,
  );

  /// `true`：近顶 prepend 两阶段（先 [uiAppendOlderHotHeadReserve]，再补满
  /// [uiAppendOlderMaxPerType]），减轻一次拉 240 的顿挫。
  static const bool restoreHotHeadTwoPhaseEnabled = true;

  /// `true`：触底/近顶翻页的 UI notify 走短窗合并，压 structure 风暴。
  static const bool appendUiNotifyCoalesceEnabled = true;

  /// append/prepend notify 合并窗口（与既有 48ms coalesce 对齐）。
  static const Duration appendUiNotifyCoalesceDelay = Duration(
    milliseconds: 48,
  );

  // ====================================================================
  // v18：会话列表 row 高频 setState 闪烁（活跃群 SDK push 风暴）
  // ====================================================================

  /// v18：`ConversationTabStore` 通知 session projection listener 时
  /// 走 `_scheduleCoalescedNotify` 短窗合并，默认 48ms。
  /// 解决：活跃群（实测 1~2 Hz `onConversationChanged`）会让会话列表 row
  /// 每秒全表 rebuild 一次 → 视觉闪烁。
  /// 关闭后恢复旧行为，每次 SDK push 都立刻 `notifyListeners`。
  static const bool tabStoreNotifyCoalesceEnabled = true;

  /// v18：tab_store notify 合并窗口。48ms 与既有 `_scheduleCoalescedNotify`
  /// 对齐：可承受 20Hz 以下 SDK push 风暴，对用户感知延迟几乎无影响。
  static const Duration tabStoreNotifyCoalesceDelay = Duration(
    milliseconds: 48,
  );

  /// `false`：置顶/取消置顶立刻重排并 `notify`（实时优先）。
  /// `true`：先静默改 pin，再等待短暂重排窗口（防双闪旧行为）。
  static const bool pinDeferredReorderEnabled = false;

  /// `true`：置顶点击后先改本地 UI，再等腾讯 `pinConversation`；失败回滚。
  static const bool pinOptimisticUiEnabled = true;

  /// `true`：免打扰点击后先改本地 UI，再等 SDK；失败回滚。
  static const bool recvOptOptimisticUiEnabled = true;

  /// 本地刚改免打扰后，阻止 SDK/落库旧 `recvOpt` 盖回的保护窗。
  static const Duration recvOptLocalGrace = Duration(seconds: 2);

  /// 停滑后再跑 folder_unread 的 settle；`<=0`：停滑立刻跑。
  static const Duration folderUnreadSettleAfterScroll = Duration(
    milliseconds: 400,
  );

  /// `true`：PostHome / 群 syncFull 避开 resume quiet 窗，错开首屏读窗。
  static const bool postHomeWaitResumeQuiet = true;

  /// `true`：UIKit `onViewModelPageLoaded` 写库后走 paced/defer，不每页重灌。
  static const bool viewModelPageUiApplyDeferred = true;

  /// `true`：resume quiet 内禁止 forceFull reload / folder unread 扫库 / history warm。
  static const bool resumeQuietBlocksHeavyUiReload = true;

  /// 覆盖 [ResumeForegroundPolicy.conversationHoldDuration]；`<=0` 用政策默认。
  static const Duration resumeQuietDuration = Duration(seconds: 3);

  /// 一页 apply 之后再决定是否续翻的间隔，避免同一帧连续 merge 两页。
  static const Duration feedPageContinueDelay = Duration(milliseconds: 32);

  /// `true`：滚动中暂停 SDK 续翻页（每页拉取前检查；maxWait 后强制继续防饿死）。
  /// 触底 `sync_next_page` / `resume_after_scroll` 不受此开关阻塞（见 sync 服务）。
  static const bool sdkPageFetchPauseWhileScrolling = true;

  /// SDK 翻页避让滚动上限。
  static const Duration sdkPageScrollPauseMaxWait = Duration(
    milliseconds: 1500,
  );

  /// `true`：列表滚动中暂缓 ViewModel 分页写库，停滑再落盘（减主线程 SQLite 争用）。
  static const bool deferViewModelPersistWhileFeedScrolling = true;

  /// 停滑后落地 pending UI apply 的 settle 窗口，压掉 scroll_end 抖动连 flush。
  /// `<=0`：立即 flush。
  static const Duration uiApplyFlushSettleDelay = Duration(milliseconds: 400);

  /// 滑动中 UI `notifyListeners` 最长推迟；到期即使仍在滑也强制 flush。
  static const Duration feedScrollUiNotifyMaxDefer = Duration(
    milliseconds: 1200,
  );

  /// PostHome 下一 stage 开始前若列表在滚则等待。
  static const bool postHomePauseWhileFeedScrolling = true;

  /// PostHome 避让滚动的上限，超时后继续 stage（防队列饿死）。
  static const Duration postHomeScrollPauseMaxWait = Duration(
    milliseconds: 800,
  );

  /// 进聊天页时暂停好友/群/贴纸等重 stage，避免与首屏历史抢 IO。
  static const bool postHomePauseWhileChatOpen = true;

  /// 聊天页避让上限；超时后继续补全，防队列饿死。
  static const Duration postHomeChatPauseMaxWait = Duration(seconds: 6);

  /// 群 membership revision 合并窗口。
  static const Duration joinedGroupsRevisionCoalesce = Duration(
    milliseconds: 200,
  );

  /// 会话列表视口锚点上报节流（翻页探测不走此节流）。
  static const Duration feedViewportAnchorThrottle = Duration(
    milliseconds: 120,
  );

  /// 置顶行底色动画时长（原 180ms）。
  static const Duration conversationRowPinAnimDuration = Duration(
    milliseconds: 80,
  );

  /// `true`：会话行侧滑 ActionPane 懒构建。
  static const bool lazyConversationSlidableActions = true;

  /// `true`：用轻量字段指纹替代 `sha256(utf8.encode(整包 raw_json))`，
  /// 并允许在 unchanged 快路径上跳过 `jsonEncode`。
  /// `false`：恢复旧「先整包 encode 再比指纹」。
  static const bool useLightweightFingerprint = true;

  /// 首屏快照单聊条数（`conv_type=1`）。`0` 表示冷启动列表不设 40 条硬上限，
  /// 由 SDK 游标分页持续灌库，UI 侧按需虚拟化。
  static const int uiSnapshotC2cLimit = 0;

  /// 首屏快照群聊条数（`conv_type=2`）。`0` 表示不设 40 条硬上限。
  static const int uiSnapshotGroupLimit = 0;

  static bool get uiSnapshotEnabled =>
      uiSnapshotC2cLimit > 0 && uiSnapshotGroupLimit > 0;

  /// 下滑从库追加。
  static const int uiScrollPageSize = 40;

  /// 短列表自动填视口最多页数（仅 conversation 侧有界调用；禁止 itemBuilder 触发）。
  /// 与 SDK sync 解耦：本地 append 不受 isSyncing 挡住；填不满屏时连补直到可滚或无增长。
  static const int uiViewportFillMaxPages = 3;

  /// `false`：paced sync/drain 不得无限扩「冷」会话进 UI 窗（置顶/未读仍热准入；
  /// 未达 [uiSnapshotC2cLimit]/[uiSnapshotGroupLimit] 类型地板时仍可冷准入）。
  /// `true`：无硬顶时恢复旧「一律准入」（应急回滚）。与 [uiWindowHardCap] 解耦。
  static const bool sdkSyncAdmitColdConversations = false;

  /// show_name / id 关键字查询（单页）。
  static const int uiSearchLimit = 50;

  /// 全局搜索本地会话分页：每页条数 / 总上限 / 最多页数（防死循环）。
  static const int uiSearchPageSize = 50;
  static const int uiSearchMaxResults = 500;
  static const int uiSearchMaxPages = 30;

  /// 冷启动后延迟 history warm。
  /// syncTop 后台预热只取轻量窗口；聊天页首开仍用完整 40 条历史窗口。
  static const int historyWarmSyncTopFetchCount = 24;

  /// `false`：syncTop 后台预热只读本地历史，避免空闲时批量打 CLOUD 抢滚动帧。
  /// 按下预热 / 聊天页打开仍可走 LOCAL→CLOUD。
  static const bool historyWarmSyncTopCloudEnabled = false;

  /// 群聊用户上拉时的单页 SDK 请求上限。旧历史按需分页，不自动补齐全群。
  static const int groupHistorySdkPageSize = 20;

  /// 群聊当前内存热窗口建议上限。超过后由消息列表窗口策略裁剪远端旧页。
  static const int groupHistoryMemoryWindowLimit = 120;

  /// 单次群聊历史/空洞修复 SDK 请求的超时边界。
  static const Duration groupHistorySdkTimeout = Duration(seconds: 12);

  /// `true`：原生端批量读库行解码可走 `compute` Isolate（Web 忽略）。
  static const bool isolateRowDecodeEnabled = true;

  /// 单次 rows 达到该条数才走 Isolate；更小批量同步解码以免启动开销。
  static const int isolateRowDecodeMinRows = 24;

  /// 会话列表灌库 **只允许** `getConversationListByFilter` 两路游标
  ///（单聊/群聊分开；分页大小不再由首屏 40 条上限决定）。
  /// 禁止改回 `false`：混流 `getConversationList` 业务路径已退役。
  static const bool conversationTypedByFilterSyncEnabled = true;

  /// `true`：热启发现 `c2cHaveMore=false` 且本地单聊行数低于 [uiSnapshotC2cLimit]
  /// 时重开 C2C 游标并至少拉一页（修复混流/脏 meta 导致单聊永久不灌）。
  static const bool c2cCursorHealEnabled = true;

  /// 虚拟列表：每个类型最多常驻水合条数（含置顶）。
  static int get virtualHydrateMaxPerType =>
      AndroidPerformanceProfile.instance.virtualHydrateMaxPerType;

  /// 虚拟列表：视口锚点上下各预取的条数。
  static int get virtualHydrateRadius =>
      AndroidPerformanceProfile.instance.virtualHydrateRadius;

  /// 虚拟列表：中心落在水合窗内且距窗缘 ≥ 本值时跳过跟滚水合。
  /// 须小于 [virtualHydrateRadius]，保证甩近边缘前仍会扩窗。
  static int get virtualHydrateSkipMargin =>
      AndroidPerformanceProfile.instance.virtualHydrateSkipMargin;

  /// Same-APK A/B for conversation row cacheExtent + LRU keepAlive.
  /// `null` uses [conversationRowRetentionEnabled] default (`false`).
  static bool? debugConversationRowRetentionOverride;

  /// Production default stays off until the keptAlive-probe model is
  /// device-validated. Testers flip [debugConversationRowRetentionOverride].
  static bool get conversationRowRetentionEnabled =>
      debugConversationRowRetentionOverride ?? false;

  /// LRU of rows that have already left `cacheExtent`. Not a whole-list keep.
  static const int conversationRowRetentionLruLimit = 20;

  /// 会话列表 ListView 前后缓存区；独立于聊天消息，避免滚动时过量预构建/头像解码。
  /// Retention on: 480/720/960. Off: baseline 240/360/480.
  static double get conversationFeedCacheExtent {
    final profile = AndroidPerformanceProfile.instance;
    if (!conversationRowRetentionEnabled) {
      return profile.conversationFeedCacheExtent;
    }
    return AndroidPerformanceProfile
        .conversationFeedRetentionCacheExtentForTier(
      profile.tier,
    );
  }

  /// 虚拟列表：滚动监听两次水合请求的最小中心步进（条）。
  /// 停滑时仍会强制按最终中心补一次。
  static int get virtualHydrateCenterStep {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 14;
    }
    return 8;
  }

  /// 大账号（群数 ≥ [GroupLocalPerfFlags.largeAccountGroupThreshold]）中心步进。
  static int get virtualHydrateCenterStepLargeAccount {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 28;
    }
    return 24;
  }

  /// `true`：滚动中不发起虚拟水合，仅 scroll_end / force 补一次。
  /// `false`：iOS/Android 均恢复边滑边水合，减少骨架闪现；
  /// 代价是滚动中主线程会叠加 SQLite/SDK 解码，低端 Android 可能掉帧。
  static bool get virtualHydrateOnlyOnScrollSettle => false;

  /// 启动后禁止 viewport history warm 的时长（press 仍可）。
  static Duration get historyWarmSuppressAfterLaunch {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return const Duration(seconds: 35);
    }
    return const Duration(seconds: 20);
  }

  /// `true`：大账号关闭 viewport warm，仅 press 预热。
  static const bool historyWarmLargeAccountPressOnly = true;

  /// `true`：`conversationsByIds` / ensurePinned 打印 wait/query/total 分阶段日志。
  static const bool conversationsByIdsPhaseLogEnabled = false;

  /// `true`：归档列表走 prepare + JOIN/LIMIT 真分页；`false` 回退旧 `loadOlderAmongIds`。
  static const bool archiveTruePageEnabled = true;

  /// `true`：归档首屏不做全量 `conversationsByIds` missing probe。
  static const bool archiveDeferFullMissingProbe = true;

  /// 归档冷缺壳：单次 SDK `getConversation` 补齐上限。
  static const int archiveColdHydrateBatchSize = 8;

  /// `prepareArchiveIdSet` 写入 JOIN 候选的分块大小。
  static const int archivePrepareChunkSize = 400;

  /// `true`：prepare 分块之间 `await Future<void>.delayed(Duration.zero)` 让帧。
  static const bool archivePrepareYield = true;

  /// 单次打开归档页 `_archiveItems` 硬顶；达到后停载（退出重进可重置）。
  static const int archiveListEmergencyCap = 480;

  /// `true`：持久 `archive_id_index`（首版关，用会话表内 JOIN 候选表）。
  static const bool archiveIdIndexPersistent = false;

  /// `true`：归档 prepare / 取页打 `[ConvPerfGate] archive_page_*`。
  static const bool archivePagePhaseLogEnabled = false;

  /// `true`：主列表虚拟 count/page/hydrate 排除已归档（修主列表与归档双显）。
  static const bool virtualListExcludeArchivedEnabled = true;

  /// `true`：归档集变更时从 UI 水合窗 purge 已归档并刷新 totals。
  static const bool purgeUiOnArchiveChangeEnabled = true;

  /// `true`：folder_unread 单飞在开跑前同步占坑，禁止双 Tab 同时 run。
  static const bool folderUnreadAtomicClaimEnabled = true;

  /// `true`：归档页分页/已有列表时，归档 ID 变更不立刻整表 reload first。
  static const bool archivePageForbidReloadFirstWhilePaging = true;

  /// `true`：排除归档的 COUNT/PAGE 串行化，禁止 TEMP 表并发互踩打回全量总数。
  static const bool archiveExcludeQuerySerialized = true;

  /// `true`：归档/取消归档后同步主列表（purge + 恢复回灌 + totals）。
  static const bool archiveChangeMainListSyncEnabled = true;

  /// `true`：主列表归档同步单飞，合并连打。
  static const bool archiveChangeSyncSingleFlight = true;

  /// Phase3：自建 Conversation 表中 unread / lastMessage / orderKey / isPinned
  /// **对主列表 UI 仅为 mirror**（sdkPrimary 时 UI 读 TabStore/SDK）。
  /// 仍写入 SQLite，供角标聚合 / 离线兜底 / 分组 unread map；停写留给 Phase4
  ///（角标改挂 Store 之后）。
  static const bool conversationSqliteListFieldsMirrorOnly = true;

  /// `true`：ByFilter 单聊空时，从好友/置顶等候选按历史补建 C2C 会话壳。
  static const bool c2cHistoryBackfillEnabled = true;

  /// 单次最多探测的 C2C peer 数（防好友上千打爆）。
  static const int c2cHistoryBackfillMaxPeers = 30;

  /// 本地单聊行数 **低于** 本值时，即使已有壳也仍扫好友/置顶补壳。
  /// `<=0`：禁用「有壳仍扫好友」（回到旧行为：仅 localC2c==0 才扫）。
  /// 默认对齐 [uiSnapshotC2cLimit]，覆盖「SDK 只回几条、实际还有十几个有历史单聊」。
  static const int c2cHistoryBackfillFriendScanBelow = uiSnapshotC2cLimit;

  /// `true`：SDK 无会话壳时必须 history≥1 才补壳（好友≠有过会话）。
  static const bool c2cHistoryBackfillRequireHistory = true;

  /// `true`：好友列表纳入补壳候选。
  static const bool c2cHistoryBackfillIncludeFriends = true;

  /// `true`：置顶 C2C 纳入补壳候选。
  static const bool c2cHistoryBackfillIncludePinned = true;

  /// `true`：把 Snapshot 优先 C2C ID 并入候选（默认关）。
  static const bool c2cHistoryBackfillUseSnapshotIds = false;

  /// @Deprecated 假 spacer 页数；真虚拟列表用 itemCount=total，此值忽略。
  /// `<=0`：不插假高度。
  static const int virtualSpacerMaxPages = 0;

  /// `true`：本地类型耗尽且 haveMore 时触底必拉 SDK 一页（打 feed_bottom_sdk_page）。
  static const bool feedBottomSdkPageEnabled = true;

  /// 触底 SDK 拉页后仍无本地增量时的短压制，避免空转刷屏。
  static const Duration feedBottomSdkEmptySuppress = Duration(
    milliseconds: 800,
  );

  // ─────────────────────────────────────────────────────────────────────
  // P2 / E 块：Rebase + 离线重连体验优化（v15/v16 §12.19 / §11.1.3）
  // ─────────────────────────────────────────────────────────────────────

  /// E2：Rebase 阈值——C2C 会话本地 cursor 与 SDK 服务端 newestSeq 差距超过本值，
  /// 则触发「Rebase」：跳过中间积压消息，把 cursor 跳到 newestSeq-1 直接续拉。
  ///
  /// 不阻塞——业务目标「慢但不能漏」，但 5000 条以上 C2C 积压在低端机解码 5s+，
  /// 体感「卡死」。跳到最近位点后用户看到最新消息，老的会在 idle 时 backend-driven
  /// 异步补齐。
  ///
  /// 业界参考（钉钉 DTIM）：超大积压触发 Rebase 跳到最新位点。
  /// 与 _pendingConvRebaseTrigger（C2C）的 server-set value 配套使用。
  static const int rebaseC2cBacklogThreshold = 5000;

  /// E2：Rebase 阈值——群聊 backlog。比 C2C 大因为群消息密度更高且有多用户离线交错。
  static const int rebaseGroupBacklogThreshold = 10000;

  /// E2：触发 Rebase 后，cursor 跳到 newestSeq-N（N 即本值），给用户留 N 条最近消息。
  static const int rebaseKeepRecent = 100;

  /// E2：同一会话二次触发 Rebase 的最短间隔，防「Rebase 风暴」。
  static const Duration rebaseCooldown = Duration(seconds: 30);

  /// E2：Rebase 后给 UI 弹 banner 的开关。
  static const bool rebaseBannerEnabled = true;

  /// E2：Rebase banner 信息 TTL（用户看到后定时消失，可在聊天页手动触发查看旧消息）。
  static const Duration rebaseBannerTtl = Duration(seconds: 30);

  /// E2：离线状态可观测埋点开关。
  static const bool offlineStatsLogEnabled = false;

  /// E7/E9：seq 单调性 gap detection 开关。每 50 条 onRecvNewMessage 采样一次。
  static const bool seqGapDetectionEnabled = true;

  /// E9：gap detection 窗口大小（最近 N 条 seq 用于滑动检查）。
  static const int seqGapWindowSize = 64;

  /// E10：首屏位置审计开关（scrollToSpecificMessage / locateMessage 调用埋点）。
  static const bool firstScreenLocateAuditEnabled = false;
}

/// SDK 会话分页写库模式。
enum ConversationSdkDrainMode {
  /// 最多 [ConversationPerfFlags.bootstrapForegroundPages] 页，有剩余则调度后台 drain。
  foregroundLimited,

  /// 在有 haveMore 时继续拉写，页间 yield；可被前台请求插队。
  backgroundContinue,

  /// 只拉写一页。
  singlePage,
}
