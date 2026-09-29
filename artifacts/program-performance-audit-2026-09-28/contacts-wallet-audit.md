# 通讯录、搜索、钱包与常用资料设置审计

日期：2026-09-28。只读审计产品代码，新增报告及复现文件，没有修改产品源码。

仓库：`C:/Users/ASUS/Downloads/Telegram Desktop/99999999`；GitNexus 名称 `99chat-unread-rebound`。先用 query/context 导航，最终用新索引 `D:/codex-task-cache/program-performance-audit-full-20260928` 的 CLI context 复核关键调用（indexedAt `2026-09-27T17:57:41Z`）。MCP 旧连接曾返回错乱 UID，未把这类返回作为缺陷证据。WalletStore.getWallet 的新图仍是 lower-bound，5 个接收类型无法解析的调用点，已用实际调用源码补齐。

下文行号均是当前工作区源码。严重度排序面向用户体验，不代表已获取线上发生率。4 个真实类的异步复现已经执行；通讯录帧耗时和搜索历史扫描的手机耗时尚未实测。

## 1. 大通讯录分批加载仍然是二次复杂度，并会继续争抢非当前页的主线程（P1，源码确认）

- 定位：`lib/src/widgets/contact_list_with_presence.dart:298-349`、`:414-485`；阈值 `lib/src/services/im_sdk_relationship_perf.dart:10-15`，调度等待 `lib/src/services/conversation_local/native_bootstrap_perf_flags.dart:10-15`。
- 触发：首次打开数千/上万好友的通讯录；批量联系人变动后补齐；补齐期间用户切换页签或开始滚动。
- 原因：首批 80、后续每批 250，但是每批 `for (id in ordered)` 都从头跳过已加载 ID。每个新增好友 `_appendFriendsToAz` 又从第 0 行线性扫描已有列表寻找插入点，并为每个批次复制完整行列表、好友列表，再触发 setState。同首字母且按目录顺序到达的普通好友，插入比较总量随 N² 增长：5,000 人约 1,249 万次，10,000 人约 4,999 万次，未含查表、复制、绘制。
- 额外延迟：Android 每批固定等待 96ms，10,000 人仅批间等待就约 3.84 秒，之后才全量投影完成；等待本身让出线程，但每个同步批次仍可造成卡顿。`while` 只检查 mounted 和 friends==null，不检查 `_workEnabled`/`_scrolling`，已启动的补齐不会因切页或滚动而停下。
- 图复核：initState、_onDirectoryChange、_applyDirectoryIncremental、_flushPendingDirectoryProjection 均可到达该 pump，pump 调用 _appendFriendsToAz。
- 修复方向：维护顺序游标，批量归并有序片段；需要不同可见排序时统一 sort 或 O(logN) 定位，避免逐人线性扫描；每批恢复前检查页面可见及滚动状态；用时间预算控制批次，并在 1k/5k/10k 真机 profile 验证帧耗时。

## 2. 搜索降级会顺序扫描大量历史，单次交互没有总工作预算（P1/P2，源码确认）

- 定位：`third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_search_view_model.dart:735-826`、`:1685-1724`、`:1858-1933`；媒体浏览同类逻辑 `:970-1035`。
- 触发：云搜索失败/无权限后回退历史；查询较少发言的人、很久之前的日期，或者在大量文字消息中查找不存在的文件名。
- 原因：文件关键词每次 50 条，一直循环到至少找到一个匹配或历史结束；成员/日期查询一直读到 30 条匹配或历史结束。没有单次请求页数、耗时或总消息数上限，`loading` 在整个循环完成后才归零。因此一次查找可能发起数百次串行历史读取。成员/日期路径还没有检查 `batch.last.msgID` 是否为空或与上页相同，如果底层重复返回整页且无匹配，无法自行终止。
- 边界：并非每次普通云搜索都会扫描全历史；这是降级路径。真实耗时依赖 SDK、历史量及设备，没有声称线上固定秒数。
- 修复方向：一轮只扫描有限页/有限毫秒，保留扫描游标并提供继续查找；每次 await 后检查查询代次；检测游标不前进，退出并提供可重试错误。文件/媒体及成员日期路径应共用这些约束。

## 3. 搜索页退出后旧本地结果仍能写回全局模型（P1/P2，已动态复现）

- 定位：同上搜索模型 `:1787-1851`、`:1883-1933`、`:1725-1727`；页面 `third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitSearch/tim_uikit_conversation_filter_msg_page.dart:88-115`。
- 触发：云查询失败后本地查找仍在等待，用户退出结果页，再去另一会话/另一筛选页。
- 原因：模型是共享 singleton；dispose 调用 clearConversationFilterResults，重置并增加 generation。云路径检查 generation，本地搜索与历史扫描却在 await 后直接写入共享 conversationFilterMessages、分页游标和 hasMore，finally 也无条件写 loading。上一页迟到的返回会污染新页面结果或中断新页面加载指示。
- 复现：`search_filter_repro_test.dart` 注入延迟的真实 MessageService 调用，让云查询失败、本地查询挂起；执行页面 dispose 使用的 clear 调用，然后完成旧请求，模型重新出现 `stale-old-page-message`。真实 TUISearchViewModel 测试通过，证实清空后仍会回写。
- 修复方向：将 generation/context key 传到 local/history 每层，所有提交及 finally 检查归属；最好每个搜索路由拥有独立控制器。新条件到来时应替换或排队，不应先清空结果再被旧 loading guard 拒绝。

## 4. 钱包内存缓存缺少账号、代次与响应顺序保护，余额可回跳（P1，已动态复现核心竞态）

- 定位：`lib/src/pages/wallet/wallet_store.dart:16-36`、`:38-93`、`:271-279`、`:320-332`。
- 触发：红包领取强制刷新重叠；兑换清缓存时旧请求仍在途；同进程切换账号后很快打开转账/红包/提币。
- 原因：余额、支付方式、卡片为全局缓存，getWallet/getPayMethods 的缓存和在途任务没有 account/generation；force 可启动重叠请求，任意旧响应都能覆盖新值，whenComplete 无条件清掉共享 future。clear 只给群成员缓存增加 generation，对余额/支付方式/卡片只置空，旧响应仍能重新填回。全库 WalletStore 引用核实 clear 的产品调用只有闪兑成功 `wallet_exchange_screen.dart:309`，未见退出/切号注册。
- 可见调用：转账 `transfer_controller.dart:51-65` 与红包 `red_packet_controller.dart:54-68` 先读取 cachedPayMethods 然后调用 20 秒 TTL 缓存；提币使用 getWallet；红包领取 `red_packet_claim_action.dart:101` 使用 force=true。
- 复现：真实 WalletStore 清空后完成旧请求，cachedWallet 重新出现旧余额，下一仓库请求次数为 0；两个 force 请求先完成新值再完成旧值，缓存最终回到旧值。钱包主界面 WalletController 自身已有 identity guard，不能据此认为 WalletStore 的其他消费者也受保护。
- 修复方向：所有 wallet cache 和 future 绑定 owner+generation；账户改变、clear、强制刷新都使旧任务失效；提交与 whenComplete 比对任务实例/版本；缓存读取验证账号，订单卡也需账号作用域及容量上限。

## 5. 钱包流水加载时切换筛选，新筛选被吞掉（P2，已动态复现）

- 定位：`lib/src/pages/wallet/record/wallet_record_controller.dart:24-32`、`:64-68`；`wallet_record_screen.dart:211-218`、`:234-242`。
- 触发：首次记录加载较慢时打开筛选，或快速连续切换“全部/红包/转账”。筛选按钮在 loading 时仍可点。
- 原因：setFilter 先更新 filter 再调用 load；load 发现 loading 直接 return，没有 pending 参数或 generation。旧请求完成后按旧筛选写 list，而 filter 已是新值，后续相同选项因为 filter==v 也不能触发重试。
- 复现：真实 WalletRecordController 加载 all 时 setFilter(redPacket)，完成旧请求后 fake repo 的请求记录始终只有 `[all]`，controller.filter 却为 redPacket。
- 修复方向：为筛选参数建立查询 key，旧结果只交给匹配 key；允许替换任务或在当前任务 finally 补发最后一次选项，保留旧内容并显示局部刷新状态。

## 附加次要项：钱包历史后台同步未连接页面更新（P2，源码确认，尚未独立动态复现）

`lib/src/api/wallet_api.dart:772-790` 把首批之后的历史放入后台任务，`:815-824` 返回当时的一次性 List；后台仅向 WalletLedgerLocalStore upsert。该 store 是普通类（`lib/src/services/wallet_ledger_local_store.dart:15`），没有提交事件。WalletRecordController 只赋值一次返回结果，wallet_record_screen 的 ListView (`:344-355`) 没有 loadMore。首次无缓存的页面通常只看见 100 条；后台记录已写到本地也不会自动出现在当前列表，选旧日期可能出现暂无记录，重新进入才变多。日期/币种还在客户端过滤当前 List。建议改为真正分页或由本地查询窗口订阅提交事件，限制每次读取/渲染的窗口。

## 验证、覆盖及局限

- 新增并执行 `contacts_wallet_repro_test.dart`（3 个钱包竞态复现）和 `search_filter_repro_test.dart`（1 个搜索生命周期复现），合计 4/4 通过。它们断言的是当前缺陷，不是代表质量合格的回归测试。
- 完整命令和输出保存在 `contacts-wallet-repro.log`；命令为 `flutter test --no-pub artifacts/program-performance-audit-2026-09-28/contacts_wallet_repro_test.dart artifacts/program-performance-audit-2026-09-28/search_filter_repro_test.dart --reporter expanded`。
- 阅读覆盖：通讯录入口、目录投影、在线状态可见区节流；好友/群搜索；群资料及成员分页/管理入口；钱包首页、支付方式、红包/转账缓存、流水；用户资料加载、设置存储空间。
- 群成员当前已有 50 条分页、identity/generation 检查和列表请求合并；GroupMemberStore 已有限容，不将旧“无限全量群成员缓存”假设列为缺陷。用户资料入口主要并行启动，未发现足够证据证明其串行初始化是主因。
- 存储空间页有次要重复扫描/统计问题：`storage_page.dart:129-144` mediaRoot 属于 chatRoot，随后又扫描完整 chatRoot 为 cacheBytes，`:277` 两者相加重复计数；遍历每个文件 length 都串行 await (`:202-215`)，页面退出没有停止标记。由于使用异步 I/O，未把它描述为已证明的主线程卡死。
- 未使用真实用户账号、未打线上负载，未测低端 Android/iOS 的 p95/p99 帧耗时、内存或真实网络吞吐；无法由源码确定哪些问题占反馈比例最高。建议首轮修复上述可重复竞态，同时对大通讯录与历史扫描加计时/页数/帧耗时观测后做真机回放。
