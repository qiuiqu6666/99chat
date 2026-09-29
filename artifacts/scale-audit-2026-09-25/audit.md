# 冷启动、页面进入与万人规模性能审计

日期：2026-09-25。范围：单账号大数据量 + 一万用户集中上线/访问。当前客户端工作区 HEAD：`02d627633d6fa5e96eedf24d09de2b8edf1c9a8d`，包含未提交修改。

**优先处理冷启动等待、在线状态失败重试、代理下级查询总并发。最可能出现明显掉帧和内存上涨的页面是 AI 助手长历史、朋友圈大量评论、管理端大列表。聊天收消息/翻历史仍是最高优先级真机压测区域。**

本轮完成代码盘点、重点调用链核验和本地模拟，没有改动产品代码，没有对线上接口施压。不能据此宣称已达到万人容量或已完成所有页面真机验收。

## 1. 证据范围与阅读方式

- 扫描应用和项目内 UIKit 共 **1,703 个 Dart 文件**，提取 **192 个页面/屏幕候选文件**与 **258 个直接使用路径字面量的 HTTP 调用位置**。
- 候选文件包含旧入口、调试页、公共页面容器；192 不等于 192 个正在使用的独立路由。动态拼接接口、SDK 方法和间接服务调用不包含在 258 这个计数内。
- [逐文件入口清单](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/scale-audit-2026-09-25/page-entry-inventory.csv>)记录入口钩子、加载候选、API/服务依赖、SDK 调用、规模风险语句及源码 SHA-256。**页面中的按钮操作也可能出现在候选列，不能当成全部在进页时请求。**
- [HTTP 调用清单](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/scale-audit-2026-09-25/http-endpoint-inventory.csv>)记录路径、方法、文件和行号，供接口负责人逐项补运行时请求记录。
- GitNexus 绑定本工作区注册名 `99chat-ios-actions-precommit`；索引时间 2026-09-25 11:37:25 UTC，索引提交与 HEAD 一致。Dart 查询多次未提供完整执行流程，且工作区有后续修改，因此结论均以当前源码补查。空调用者不作为“未使用”的证明。
- 本轮 **82 项本地检查通过**：78 项已有测试 + 4 项新增诊断。新增诊断是复现当前风险，**通过不代表这些风险已修复**。没有采集手机实际帧率、服务端吞吐、数据库执行计划或腾讯服务端配额数据。

## 2. 从冷启动开始的真实链路

| 阶段 | 当前动作及接口 | 已有保护 | 极端场景要点 |
|---|---|---|---|
| 原生进程到 Flutter 首帧前 | 节点恢复 → ApiClient 本地凭证 → 本地启动图 → 设置/业务入口缓存 → 推送监听安装 → runApp | 启动图网络刷新在后台；图片验证使用 compute；网络状态监听不阻塞首帧 | **首次安装会在节点恢复中等待网络测速**；多个本地存储读取也串在 runApp 前 |
| 启动页到首页 | InitStep.checkLogin → SessionManager.restore | 会话单飞、账号代次校验、鉴权失效清理 | **首页导航等待 restore 完成**，不是只等待本地会话行恢复 |
| 有 IM 凭证缓存 | 业务 GET /me → IM 初始化 → SDK login → ready；后台刷新 GET /im/user-sig | /me 有短缓存及单飞，UserSig 单飞 | /me 仍是进首页前置依赖；应用层没有整个 restore 的截止时间 |
| 无缓存或缓存连接失败 | /me 与 /im/user-sig 并行 → 保存凭证 → SDK 初始化/登录 | 失败分类，断线可进入 offline 后重连 | HTTP 默认连接/接收超时均为 30 秒；SDK Future 长时间不结束会拖住入口 |
| 首页首帧之后 | 本地归档、会话投影、消息监听、另一个会话 Tab 预热、联系人增量同步 | 先本地、分阶段、会话 SDK 不再空闲拉完整账号 | 后续同步仍可能与用户马上进入聊天重叠 |
| 首页后台补全 | 约 2 秒后归档/文件夹/置顶/头像/贴纸；8 秒后直播索引/群通知；30 秒后低优先级任务 | 本机空闲门控、单飞、账号代次校验 | 固定延迟只分散单机任务；万人同时启动仍可能形成同一时间段的请求峰值 |
| 切后台再回来 | Session/连接恢复、会话增量、历史修复、已读补交、设备/通知恢复 | 上轮已修历史任务生命周期隔离；部分恢复分阶段 | 大积压、SDK 慢回调、数据库写队列和用户翻页相遇时必须压测 |

入口证据：[main.dart:352](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/main.dart:352>)、[init_step.dart:269](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/utils/init_step.dart:269>)、[session_manager.dart:104](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/session/session_manager.dart:104>)、[home_bootstrap.dart:120](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/bootstrap/home_bootstrap.dart:120>)。

**不要沿用旧链路结论。** `LoginCoordinator.restoreColdStartSession` 中的 4 秒等待不在当前 `InitStep → SessionManager.restore` 的这条入口调用链上。已有部分 cold-start 测试只测试辅助策略，不能证明当前启动导航不会被拖住。

## 3. 已确认的优先风险

P0 表示建议在万人容量验收前先处理；P1 表示高优先级改造或专项验证；P2 表示纳入后续性能验收。这里不是线上故障率评级。

### P0-A：实际冷启动存在没有应用层截止时间的等待

- `InitStep` 等 `SessionManager.restore` 返回后才导航首页。
- 有缓存仍先等 `_auth.fetchMe()`，随后等 `_im.initialize()`、`_im.connect()`。AuthRepository 没有额外短超时，ImClient.connect 直接等待 SDK login。
- 12 秒启动看门狗只记录日志，不解除等待。HTTP 自身超时不等于整条恢复链路的截止时间，SDK 内部是否最终超时还取决于平台实现。
- **本地证据**：分别让鉴权 Future、IM login Future 保持未完成；虚拟推进 60 秒，restore 都仍未返回。鉴权场景 IM 初始化次数为 0；IM 场景停在 connectingIm。这个模拟证明应用层缺少截止时间，不是声称真实 HTTP 一定等待 60 秒。
- 建议：拆分业务会话验证、可显示本地数据、SDK 连接三个状态；给等待明确预算和可重试 UI，区分网络不可达与明确鉴权拒绝。保留账号隔离和拒绝失效账户的规则，避免用简单跳过鉴权换速度。

证据：[session_manager.dart:139](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/session/session_manager.dart:139>)、[im_client.dart:36](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/session/im_client.dart:36>)、[auth_repository.dart:22](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/session/auth_repository.dart:22>)、[app.dart:520](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/app.dart:520>)。诊断：[启动等待模拟结果](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/scale-audit-2026-09-25/startup-probe.log>)。

### P0-B：在线状态失败后固定约 400 毫秒重试，缺少退避

- `PresenceProvider._flush` 失败后把整批 ID 放回 pending，再按 400 毫秒调度。
- 没有此路径的指数退避、失败次数上限或 429 Retry-After 处理；TCP 不可用时会走 HTTP。
- **本地证据**：模拟 /presence/last-seen 快速返回 503，2.6 秒内发出 6 次请求；间隔 404、403、402、402、403 毫秒。
- 理想快速失败条件下，每客户端接近 2.5 次/秒；一万客户端同处该分支，约 **2.5 万次/秒尝试**。这是客户端行为推算，不是实测服务器吞吐。
- 建议：按错误类型退避并加随机抖动，尊重服务端重试时间；页面隐藏/账号变化时撤销无用待查项，恢复后优先查可见用户。

证据：[presence_provider.dart:829](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/provider/presence_provider.dart:829>)、[presence_provider.dart:733](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/provider/presence_provider.dart:733>)。诊断：[503 重试模拟结果](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/scale-audit-2026-09-25/local-checks.log>)。

### P1-A：代理下级“每批 8 个”没有限制跨分页资料查询总并发

- 进页先 50 条，随后从第 1 页改用 200 条持续拉完；每页都 unawaited 启动 `_loadProfiles`。
- 单个 _loadProfiles 内并发为 8，但上一页资料请求尚未完成时，下一页又启动 8 个。代次校验在等待结果后，只能丢弃旧结果，不能取消已发请求。
- **本地证据**：注入 10,000 条下级，分页立即完成、资料请求保持未完成；未做任何滚动，产生 **51 次分页请求、408 个同时未完成的资料查询**。
- 此外，下一批提高全局 profileGeneration 后，旧批返回会被丢弃，资料补全还可能不完整。
- 建议：统一资料请求队列和全局并发上限；按可见行补资料，优先由列表接口返回展示字段；分页由滚动/明确搜索驱动，避免进页自动拉完。

证据：[agent_rebate_descendants_page.dart:131](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/agent_rebate_descendants_page.dart:131>)、[agent_rebate_descendants_page.dart:172](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/agent_rebate_descendants_page.dart:172>)、[agent_rebate_descendants_page.dart:237](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/agent_rebate_descendants_page.dart:237>)。诊断：[万人下级模拟结果](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/scale-audit-2026-09-25/descendants-probe.log>)。

### P1-B：AI 助手长历史的附件下载、内存和列表布局没有配套上限

- 历史首批 100 条，续页 50 条；每次续页都会遍历当前全部消息。
- 历史附件逐个 unawaited 下载；缓存只检查“已下载”，没有同文件正在下载的单飞集合，翻页重叠时可能再次发起下载。
- 原始文件字节保存在页面 Map 中；本页未见字节预算/LRU。
- 列表先生成全部消息 Widget；搜索时 `cacheExtent: double.infinity`，会扩大布局/保留范围。
- 风险：大量带图历史 + 连续翻页 + 搜索，会同时放大网络请求、内存、GC 和布局耗时。
- 建议：附件按视口排队、去重、限并发和字节预算；历史使用有边界的窗口和 builder；搜索跳转使用索引定位，避免无限缓存范围。

证据：[ai_assistant_page.dart:258](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/ai_assistant/ai_assistant_page.dart:258>)、[ai_assistant_page.dart:370](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/ai_assistant/ai_assistant_page.dart:370>)、[ai_assistant_page.dart:454](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/ai_assistant/ai_assistant_page.dart:454>)、[ai_assistant_page.dart:2141](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/ai_assistant/ai_assistant_page.dart:2141>)。

### P1-C：朋友圈评论详情存在平方级遍历和一次性全量布局

- 详情接口返回的 comments 全部在 Column 中构建；每个 comment 又调用 `post.comments.indexOf(item)`。
- 若实际返回 10,000 条不同评论，仅查下标约需 5,000 万次比较；同时布局全部评论。服务端是否限制评论数量，本仓库不能证明。
- Feed 本身已有 20 条分页及 Sliver builder，不能把详情问题泛化到整个朋友圈。
- 另外，进页 initState 调一次 header extras，_load 完成后又调一次；通知未读读取没有在该层合并，通常会重复请求。
- 建议：评论独立游标分页，SliverList/builder 按需构建；使用索引循环；合并 header 请求。

证据：[moments_detail_page.dart:709](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/moments/moments_detail_page.dart:709>)、[moments_api.dart:69](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/api/moments_api.dart:69>)、[moments_page.dart:110](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/moments/moments_page.dart:110>)、[moments_page.dart:205](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/moments/moments_page.dart:205>)、[moments_store.dart:355](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/moments/moments_store.dart:355>)。

### P1-D：手机通讯录好友首屏等待全部号码匹配

- 先读取全部本机联系人，号码按 500 个串行 POST /users/contacts/match，全部完成后才组装/排序并返回页面。
- 10,000 个去重号码至少 20 批，首屏业务内容等待约为各批耗时之和；异步等待本身不代表主线程冻结，但用户会看到长时间加载。
- 建议：先显示本机联系人，逐批补注册状态；缓存匹配结果和增量；大列表搜索避免每次输入重新全量排序。

证据：[contact_friends_lookup_service.dart:53](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/contact_friends_lookup_service.dart:53>)、[contact_friends_lookup_service.dart:157](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/contact_friends_lookup_service.dart:157>)、[contact_friends_page.dart:48](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/contact_friends_page.dart:48>)。

### P1-E：部分成员/管理页面仍自动读完整列表

- 选择直播主播：每页 100 人，打开即循环到底，每页通知重建；10,000 人约 100 个 SDK 分页请求。已有串行、超时、重复游标保护和 dispose 停止，但没有按滚动需求控制总量。
- 共同群：每页 20 条，进入后继续拉完；搜索时对所有已加载名称重新计算拼音，构建 A–Z 排序。10,000 个共同群的极端输入约 500 页，不代表普通账号会达到此数量。
- 三公全部用户：每页 50；输入一个少于 12 个匹配项的搜索词会继续自动翻页。数据随后生成 rows，并放进 SettingsGroup 的 Column，已加载行会集中构建和布局。
- 建议：服务端/本地索引搜索 + 滚动续页；资料保持轻量；管理大表避免用普通设置项容器承载。

证据：[group_live_member_loader.dart:68](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/group_live/group_live_member_loader.dart:68>)、[group_live_member_picker_page.dart:38](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/group_live/group_live_member_picker_page.dart:38>)、[common_group_chats_page.dart:127](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/common_group_chats_page.dart:127>)、[sangong_all_users_page.dart:107](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/group_game/sangong_all_users_page.dart:107>)、[settings_widgets.dart:145](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/settings/settings_widgets.dart:145>)。

### P1-F：钱包流水补全可能反复请求同一段历史

- 默认 getLedgerAll 每页 100，最多 20 页；后台分页仅以 scope 单飞，没有页面可见性/用户交互预算。
- 页预算耗尽但仍有更多记录时，不标 complete，也未在此流程保存下一页位置；下一次同 scope 再从首页和后续页补拉，可能重复已请求的区间。
- 因此 10,000 条账单不能只靠把 maxPages 增大解决；需要明确续页、范围和持久游标。
- 流水“全部”入口即使有本地快照仍 awaitFirstPage；弱网首屏可能先等刷新失败再回落缓存。
- 已有好处：余额页有本地快照、6 秒 UI 等待上限、账号隔离；流水详情补资料按可见项排队。余额页 Future.timeout 并不自动取消底层 HTTP，连续重试仍应检查实际在途量。
- 建议：按时间范围/游标展示流水，后台补全有预算且能恢复断点；本地快照先展示；保留账务权威和幂等约束。

证据：[wallet_api.dart:651](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/api/wallet_api.dart:651>)、[wallet_api.dart:860](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/api/wallet_api.dart:860>)、[wallet_api.dart:991](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/api/wallet_api.dart:991>)、[wallet_controller.dart:103](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/wallet/wallet_controller.dart:103>)。

### P1-G：首次安装在 Flutter 首帧前等待节点测速

- main await hydrate；没有保存节点时 hydrate await probeAll。
- probeNode 访问 /api/v1/platform/splash，连接/接收超时各 6 秒，没有把总预算与首帧分开。
- 仅首次安装/相关偏好缺失路径触发；不能说每次重开都测速。
- 建议：首帧先使用已有/默认节点，测速在可呈现加载状态后执行；限制整体预算并避免多人同时测速打业务重接口。

证据：[main.dart:352](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/main.dart:352>)、[api_node_service.dart:164](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/api_node_service.dart:164>)、[api_node_service.dart:305](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/api_node_service.dart:305>)。

### P2：需继续用实际耗时验证的区域

| 区域 | 已确认实现 | 重点量测 |
|---|---|---|
| 通讯录主 Tab | 首批 80，后续每批 250，48/96ms 让出；A–Z 投影逐批生成 | 已启动的 pump 循环只检查 mounted，隐藏/开始滚动后是否仍补完整目录；每批从有序 ID 起点扫描的成本 |
| 我的群/A–Z 搜索 | 从本地全量读取轻量骨架 limit:null，随后生成索引项 | 万群下单次查询、转换和拼音回填耗时；快速输入旧请求是否占据数据库队列 |
| 设置→存储 | 异步递归枚举目录并逐文件读长度 | 十万缓存文件的总等待、取消后是否继续 IO；不要把异步 IO 等待直接称为掉帧 |
| 收藏 | 默认最多 500 条，100/页，在 listAll 完成后显示 | 5 次请求的首屏等待、输入时全量过滤/排序；大于 500 条内容的可达性另做功能验收 |
| 隐藏页面 | 首页有按需创建、TickerMode 和 HomeTabActivity | TickerMode 只停动画，业务 Timer/Future/订阅是否各自停止；push 新页面但旧页面仍 mounted 的场景 |

证据：[contact_list_with_presence.dart:298](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/widgets/contact_list_with_presence.dart:298>)、[my_group_list_controller.dart:265](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/group_local/my_group_list_controller.dart:265>)、[storage_page.dart:202](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/settings/storage_page.dart:202>)、[favorite_message_api.dart:91](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/api/favorite_message_api.dart:91>)、[home_page.dart:1369](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/pages/home_page.dart:1369>)。

## 4. 各区域进入流程与接口检查表

下表区分进入/继续加载和主动操作。精确方法与候选位置见逐文件清单；API 路径均是客户端声明，域名前缀以对应客户端配置为准。“待测”不等于已发现故障。

| 页面区域（含子页面） | 进入或加载时的数据来源 | 首要检查 / 优先级 |
|---|---|---|
| 启动页、登录、注册、忘记密码、扫码登录确认 | 本地 session；/me、/im/user-sig；AuthApi 对应登录/短信/二维码接口由操作触发 | 恢复等待 P0；二维码轮询可见性、验证码冷却不是网络轮询 |
| 消息 Tab、群聊 Tab、分组、归档 | SDK getConversationListByFilter；本地行；/me/conversation-folders、/me/archived-conversations、置顶同步 | 万会话增量/滚动/未读重算；SDK 窗口每类型 600；已禁用 idle 全账号 drain |
| 单聊、群聊、搜索跳入聊天 | 本地消息窗口、SDK 历史；群资料/禁言/成员校验；业务功能延迟补充 | 离线 10,000 消息 + 正在上翻 + 返回/重进；历史、已读、持久化不同队列的等待分解 |
| 聊天设置、用户资料、头像、共同群 | SDK conversation/user/group info；UserApi、CommonGroupChatsService | 资料单飞、可见成员批量；共同群全拉 P1 |
| 群详情、群管理、加退群、创建群/频道、邀请/移除/投诉选人 | SDK 群资料/成员分页；MeGroupApi、GroupMemberApi、GroupJoinApi/GroupPrivacyApi、创建限制 | 万人大群首屏只需有限成员；搜索与选择不能隐式全拉 |
| 通讯录 Tab、转发好友、名片选人、朋友圈可见范围选人 | ImSdkRelationshipDirectory + 本地好友；ContactsProtocolSyncService；可见用户 presence | 快速切页后台 pump、批量状态失败 P0；不得逐行查资料 |
| 手机通讯录好友 | 本机通讯录权限/读取；POST /users/contacts/match | 全批匹配后才显示 P1 |
| 搜索、搜索加好友/群、群内历史/媒体文件 | SDK searchLocal/searchCloud；本地索引；UserApi.search | 关键词防抖、旧代次取消、分页边界、SDK scope；媒体页缩略图而非全原图 |
| 好友申请、群审批、群通知、消息通知中心 | FriendRequestApi、GroupJoinApi、群通知游标；朋友圈通知；支付助手 SDK 会话 | 增量游标过期、列表分页、进入/返回重复刷新；未读按来源对齐 |
| 我的、个人信息、昵称/签名、头像编辑 | 本地资料、GET /me；编辑成功再 PATCH/上传 | 保留 /me 单飞；选图解码/压缩、返回不全量刷页面 |
| 收藏列表、收藏详情、编辑、聊天收藏选择 | GET /me/favorites（最多 500）、详情；编辑上传由操作触发 | 首屏等 5 页、过滤排序 P2；不要把“500 上限”当作万人数据完整支持 |
| 朋友圈列表、个人朋友圈、发布、视频、消息通知 | /moments/feed、/moments/users/{id}、/moments/notifications、/moments/settings；发布/点赞/评论由操作触发 | 列表已有 20 条分页；长期累积窗口、图片解码、重复 header 请求 |
| 朋友圈详情评论 | GET /moments/{id} 返回 post + comments | 全量 Column + indexOf P1 |
| AI 助手、历史搜索、文件预览、卡片 | /ai-assistant/api/v1/chat/history、files/{id}；聊天流及上传由操作触发 | 附件总并发、原始字节缓存、无限 cacheExtent P1 |
| 钱包首页、币种资产、收款 | /wallet/me、币种/地址相关读取，本地快照 | 余额刷新合并、隐藏 Tab 事件、6 秒 UI 超时后的在途 HTTP |
| 钱包流水、资产记录、详情、待处理订单 | /wallet/ledger、订单详情、本地流水；待处理恢复 | 20 页补全重复、全缓存排序、详情补查上限 P1 |
| 转账、红包、兑换、提现、支付密码/生物验证 | 进入读取余额/支付配置/成员；确认才发金融写请求 | 热点红包/查单、幂等、未完成订单恢复；分页选人已有 100 条限制 |
| 代理当前/历史/下级列表/下级详情 | /me/agent/*、/me/rebate/*；部分三公服务 /api/v1/me/*；用户资料 | 跨批资料并发 408 的复现 P1；报表范围、导出单独限流 |
| 三公管理、全部用户、成员、层级/日报、规则/个人配置 | /api/v1/admin/reports/*、my-config、session 等；GroupGameApi | 搜索自动拉完整用户表、SettingsGroup 全量布局 P1 |
| 群直播授权、选择主播、推流信息、播放页 | /group-live/api/v1/groups/{id}/live/current；SDK 成员；授权/开停播由操作触发 | 万人成员自动 100 页 P1；播放器/解码器退出释放；直播轮询按状态 |
| 通话页、通话记录、悬浮窗 | CallLifecycle/LiveKit 状态与 token；GET /calls/recent | 媒体轨道/纹理释放、通话返回聊天、每秒计时只重建必要区域 |
| 生活缴费、水电燃气、手机充值、订单详情 | /life-payments/home、services、providers；mobile repository；查询/订单由操作触发 | 城市/机构大表过滤；查询轮询次数/取消；第三方慢接口隔离 |
| 表情管理、包预览、单图、上传、聊天表情面板 | /me/sticker-packs、/me/stickers/favorites、/stickers/batch；上传由操作触发 | 大量动图解码、隐藏动画、预取上限；压缩放后台 |
| 设置、通知、声音、主题、字号、背景、皮肤 | 多为本地设置/资源；账号/隐私页读取对应 UserApi/SettingsApi | 静态设置页低风险；图片背景/声音资源释放、避免整 App 高频通知 |
| 账号安全、密码/手机修改、登录设备/桌面会话、注销 | AuthApi、DeviceApi；提交动作分别发写请求 | 设备列表分页、旧请求隔离；验证码计时不触发全表重建 |
| 朋友圈/好友隐私列表、黑名单 | MomentsSettings、UserApi/BlockApi、好友目录 | 万人选人全量构建与过滤、增量更新 |
| 存储、节点切换 | 本地文件扫描；节点测速 /api/v1/platform/splash | 文件数与 IO；测点预算、故障时重复测速 |
| 帮助、关于、客服、意见反馈、投诉、协议/隐私 WebView、二维码/扫描 | 平台配置/静态内容；FeedbackApi/ComplaintApi 由提交触发；相机/WebView | 普通静态页低风险；媒体/相机/WebView 生命周期和低端机内存 |
| 桌面分栏、弹窗、多窗口及 UIKit 媒体/成员页 | 复用上述控制器、SDK/媒体组件 | 两个视图订阅同数据的请求去重；嵌入视图切换不一定 dispose |

## 5. 万人同时在线：先把客户端请求放大量化

以下为**条件满足时的平均请求量推算**，不包含响应大小、服务端缓存命中、数据库开销，也不是服务器容量结论。页面使用率、TCP 是否正常、客户端相位不同，必须带入实际比例；不能把每项都按 100% 使用直接相加。

| 场景 | 客户端现有节奏 | 一万客户端的推算 |
|---|---|---|
| presence 接口快速失败 | 约每 0.4s 重试 | 接近 25,000 次/s 尝试 |
| 联系人前台 catch-up | 30s，至少一页增量查询 | 约 333 次/s；游标过期的 snapshot 多页额外计算 |
| TCP 不可用时 HTTP 心跳 | 30s | 约 333 次/s；TCP 正常时此 HTTP 心跳会停 |
| 群 Tab 直播索引可见 | 45s，支持 ETag | 约 222 次/s；304 省响应体，仍有请求处理成本 |
| 群聊直播状态 | 有直播/预约 12s；无活动 60s | 约 833 或 167 次/s |
| 聊天推送焦点续租 | 60s | 约 167 次/s，另加进入/退出操作 |
| 钱包流水冷缓存补 20 页 | 每账号最多 20 次/轮 | 10,000 次同条件访问可产生约 200,000 次读请求，非每秒数 |
| 万人群选择主播 | 100 人/页连续读 | 约 100 个 SDK 请求/次打开；由实际打开人数相乘 |
| 代理下级列表 | 10,000 行模拟 51 页 + 未完成资料 408 | 先修单客户端并发，再按有权限用户访问率建模；不能假定所有在线用户都会访问管理页 |

确定性重连也要查：FriendRealtimeService 使用 1、2、4…60 秒退避，但没有随机抖动；HomeRealtime 使用固定 1、2、5、10、30 秒；SessionManager 也独立调度恢复。每个服务内部单飞并不自动限制全 App 的网络总并发。

证据：[friend_realtime_service.dart:614](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/friend_realtime_service.dart:614>)、[home_realtime_connection_state_machine.dart:49](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/home_realtime_connection_state_machine.dart:49>)、[contacts_protocol_sync_service.dart:72](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/friend_local/contacts_protocol_sync_service.dart:72>)、[presence_provider.dart:897](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/provider/presence_provider.dart:897>)、[group_live_index_sync_service.dart:28](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/group_live/group_live_index_sync_service.dart:28>)、[chat.dart:3886](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:3886>)。

服务端需要对应核验：鉴权/UserSig 生成、联系人 snapshot 与 changes 的索引/缓存、presence 批查询、热点群资料和成员分页、直播索引缓存、报表分页与按用户补资料、流水范围查询、红包/订单热点幂等。当前仓库没有提供这些服务端实现和生产监控，不能对其慢 SQL、机器规格、连接池容量作已证实判断。

## 6. 必须执行的客户端极端场景

| 用例 | 数据及操作 | 必须同时记录 |
|---|---|---|
| 干净安装 | 无偏好/无缓存，网络黑洞、DNS 慢、测速端点慢 | 进程到首帧、节点测速等待、是否可重试 |
| 大账号冷启动 | 10,000 好友、10,000 会话；分别有/无本地缓存 | 首帧、首页可交互、首屏会话可见、SDK ready、全部请求时间线 |
| 退出后重开 | 积压 10,000 条消息；进首页立即开聊、立即返回 | 消息到回调/落库/可见耗时；已读锚点、会话行与 Tab 数量一致 |
| 历史翻页 | 单群 100,000 条历史，上翻 100 页，同时接收新消息 | 帧 build/raster、锚点漂移、重复页、SDK/本地窗口长度 |
| 万人群功能页 | 成员、@人、邀请、移除、主播/红包收件人选择 | 首屏请求数、峰值在途数、成员对象数、连续搜索响应 |
| 网络波动 | 慢响应、快速 503、429、断网再恢复；连续 20 次前后台 | 重试节奏、是否尊重 Retry-After、旧请求与新会话代次、重复连接 |
| 多媒体 | 100/1,000 条带图历史、大图/GIF/视频，键盘与滚动叠加 | 字节缓存、解码尺寸、纹理/播放器数、RSS、GC 和最差帧 |
| 长时间运行 | 连续使用 30/60 分钟，20 次进入退出高风险页面 | 内存是否持续增长、订阅/计时器/队列是否归零 |
| 专项长列表 | AI 10,000 消息、评论 10,000 条、流水 10,000 条、代理 10,000 行 | 首屏与全量耗时分开；最大并发；非可见项是否仍布局/下载 |
| 存储压力 | 大缓存目录、低剩余空间，正在落库时切页/打开存储 | DB queue wait、transaction、prepare CPU、目录扫描时间 |

测量必须使用实际发布配置对应的 **profile/release 真机**，至少覆盖低内存 Android 和用户反馈所用 iOS 档位；debug 桌面单元测试结果不能换算成手机 FPS。

验收建议（是拟定目标，需按基线确认）：

- 60Hz 设备按约 16.7ms/帧观察 build/raster；120Hz 对应约 8.3ms。统计 p50/p95/p99、超预算比例及 >100ms 长帧，不能只看平均 FPS。
- 分开记录“首帧出现”“本地内容可用”“网络同步完成”，网络断开不能让整个界面无期限不可操作。
- 每页面定义可见范围、对象/字节缓存上限、HTTP/SDK 在途上限；隐藏后停止无用补拉。重复进出后资源数量应回落到可解释的稳定范围。
- 历史恢复不得吞新消息、清掉未见消息、回滚已读；性能改造继续复用上一轮未读/快速返回/生命周期回归用例。
- 已有 StartupPerfLog、ChatOpenPerfLog、ChatMainThreadPerf 的 build/raster 探针，以及持久化队列指标可以复用；本轮未产生真机帧数据。

## 7. 服务端压测方案与推进顺序

不要把“10,000 在线连接”“10,000 登录/分钟”“10,000 同时打开群”“同一万人群广播”当成同一种压力。

1. **先修请求放大**：presence 退避；下级资料全局限并发；AI 附件去重/预算。否则压测测到的是客户端自我放大。
2. **解决启动等待**：恢复阶段有预算、状态与重试入口；首次节点测速不占住首帧。用真实 SessionManager 入口测试，补上旧策略测试覆盖不到的情况。
3. **改高风险列表**：评论、管理表、成员选择、手机通讯录、流水，逐项落实首屏/分页/搜索/可见性。
4. **在测试环境逐级加压**：100 → 1,000 → 5,000 → 10,000 活跃连接，分别做 60 秒集中登录、平稳混合访问、网络故障恢复、热点群读取。每档需稳定观察，不直接把线上用户作为负载。
5. **按业务建模消息和支付热点**：例如同一万人群每秒 10 条消息对应约 100,000 次接收投递需求，这是消息分发量，不是 HTTP QPS；红包/转账使用测试账户和测试账本核验幂等与锁竞争。
6. **记录判据**：请求 p95/p99、错误率、重试比、在途连接、CPU/内存、DB 等待/慢查询、队列积压、SDK 限频码、媒体 CDN 带宽，并保留客户端帧时间关联 ID。没有这些证据不能判定“万人标准已达标”。

本轮产物仅为审计报告、静态清单和本地诊断用例。没有修改产品实现、提交代码或发布安装包。上述优先风险仍待修复及真机/服务端验证。

