# 禁言成员昵称与头像修复：深入完整实施计划

> 状态：待实施。仅制定计划，未修改生产代码或测试。
> 任务：修复“管理群 → 禁言成员”显示 UID 和默认头像，而非有权查看的真实用户资料。
> 仓库：99chat；证据基线 HEAD：b6dcaaae0999d698f822222a393d59823d3ed55f，同时包含当前未提交源码。
> 图谱：2026-09-21T15:56:06.186Z，HEAD 相同，但未证明覆盖全部工作区改动；无 PDG 层；源码优先。
> Runner：node .gitnexus/run.cjs，版本 1.6.12。完整 build/dependency identity 未独立复核；stale analyzer provenance — source-weighted limitation，不以版本相同证明构建一致。本轮未刷新索引或构建分析器。
> 证据摘要：schema 2；global_dirty_digest=614c7750a99cf4d0c05c07e799183728f431547775dbb85368c09094c193f85f；20 个引用路径，完整摘要见 §11，仅排除本计划路径。
> 保存例外：Windows 不具备技能要求的安全 write-plan 条件；用户明确授权本次使用普通文件补丁。证据快照仍由官方 helper 生成，不声称持有安全 writer 收据。

## 1. 目标与范围

在服务端存在且当前账号有权查看资料的前提下，禁言名单在冷缓存、旧缓存、弱网恢复和重新进入页面后，自动显示正确昵称和头像，不再长期停在 UID 占位。

范围包括接口字段解析、逐字段资料补齐、缓存有效性、并发与账号隔离、权限变化、页面更新、测试、真机验证和回退。
不改变禁言/解除禁言接口的业务语义，不重构全部用户资料服务，不扫描全群，不更改聊天消息或历史加载逻辑。

**完成不等于“永远不出现默认头像”。** 用户未设置头像、资料已删除、无权查看、断网等情形允许明确降级；不得用他人头像或过期权限下的资料掩盖失败。

## 2. 当前行为与已确认缺口

以下行号相对 §11 固定的工作区字节，而非仅相对 HEAD。

- [verified] `lib/src/api/me_group_api.dart:70` 的 `MutedGroupMemberRecord` 只包含 userId、muteUntilSec、nameCard、imRole；`fromJson` 未接收昵称、头像。**这证明客户端会丢字段，不证明线上接口已经返回了这些字段。**
- [verified] 同文件 `fetchMutedMembers:1401` 请求群的 `/members/muted`，解析 members，异常返回 null。
- [verified] `tim_uikit_group_manage.dart:390` 先显示权威名单，再调用共享 `loadGroupMembersInfo`；未显式刷新，失败或空资料没有可见解释。
- [verified] `_mutedRecordToMemberInfo:429` 从当前有限的 groupMemberList 补昵称/头像，比较 UID 时仅 trim，没有统一采用 rawUserUid。
- [verified] `group_membership_sync_service.dart:1026` 只有“缓存不存在，或昵称与群名片都为空”才补查；头像为空不参与判断。昵称等于 UID 的旧占位也属于非空。
- [verified] 同服务收到 SDK 数据后，对已存在记录只填原本为空的 nickname/avatarUrl；非空旧值不会被刷新。这说明**只给当前调用加 refresh:true 仍不足以修复旧非空资料**。
- [verified] `muted_member_profiles.dart:7` 会合并仍在当前名单中的资料，保留角色和禁言时间；但没有来源/新旧判定，任何非空返回都可能优先。
- [verified] `tim_uikit_group_manage.dart:783` 展示名优先级为备注 → 群名片 → 昵称 → UID；头像使用 faceUrl。昵称正确但展示的是群名片不等于资料丢失。
- [verified] 现有 `test/muted_member_profiles_test.dart` 为合并逻辑测试和页面 Type 检查，未真正挂载页面验证完整异步链路。
- [inferred] 截图可由上述多个分支导致；目前没有这次管理页真实响应，不能断言异常设备必然命中了某一个分支，也不能认定截图中的默认头像一定是 URL 为空而非图片下载失败。

## 3. 相关架构与边界

### 权威来源

| 数据 | 权威来源 | 本次允许的修改 |
| --- | --- | --- |
| 谁被禁言、禁言时间、全员禁言 | 禁言业务接口及成功的禁言操作 | 仅对应业务结果可增删/修改 |
| 是否仍是群成员、群角色 | 原有业务成员/权限流程 | 资料查询不得据此推断或覆盖 |
| 业务昵称与头像 | 已确认契约的业务接口资料 | 优先使用当前请求结果 |
| 备注、群名片 | 对应用户/群字段来源 | 保持当前显示顺序，不用昵称覆盖 |
| SDK 资料 | 受权限约束的候补来源 | 只补缺或刷新它自己提供的旧字段，不能盖过新业务资料 |

[verified] `loadGroupMembersInfo` 同时服务群资料展示、入群来源、邀请选人、增量成员修正及 UIKit bridge。
[verified] `group_member_entry_refresh_test.dart:267` 明确验证默认缓存和 `refresh:true` 身份查询不同：后者得到空列表时应保持空，不得还原缓存成员。
[verified] `UserApi.tryFetchUserById:232` 有账号代次隔离和 30 秒缓存；`_fetchUserById:249` 将 404、其他 Dio 错误与异常都降为 null，无法区分权限拒绝与网络失败。
[verified] `GroupPrivacyGuard.blockedGroupProfileHint` 的现有客户端资料页策略对当前群管理者豁免，但这不是禁言接口或其他资料接口的后端授权凭证。
[verified] 本项目用本地 SDK override；`v2_tim_group_manager.dart:284` 将 Web 与原生查询分派到不同实现，真机结果不可由 Dart mock 证明。

**设计选择：新增禁言页专用 resolver，不改变共享 loadGroupMembersInfo 的默认或 refresh:true 语义。**
它可以借用规范化 UID、会话隔离及批量方式，但不能为了展示而改写共享成员身份结果。

## 4. GitNexus 调查与影响范围

- [graph] `impact(MutedGroupMemberRecord, upstream, depth=3)`：HIGH，174 个传播节点、16 个直接文件 IMPORTS。这是高风险警告，不以字段小或其他风险轴低而消除。采用可选字段、旧构造兼容，不改公共接口路径。
- [graph] `impact(loadGroupMembersInfo, upstream, depth=3)`：LOW，4 个节点，直接调用方 applyTargetedMemberCorrection。源码还发现 bridge 回调、禁言页、入群来源和邀请选人；图谱调用集合不完整。
- [graph] `impact(_loadRequestedMembers, upstream, depth=3)`：直接 loadGroupMembersInfo；后续为 applyTargetedMemberCorrection 等。
- [graph] `impact(_refreshMutedMembers, upstream, depth=3)`：LOW，直接 _bootstrapManagePage 与 tuiBuild，涉及管理页流程。
- [graph] `impact(mergeMutedMemberProfiles, upstream, depth=3)`：LOW，直接 _refreshMutedMembers。
- [graph] context/clusters/processes 已读取；相关区域为 Group_local、Api、Widgets、Separate_models；部分 query 返回不相关流程，不将它们用作行为证据。
- [graph] `detect_changes(scope=all)` 返回全工作区混合改动摘要（80 changed symbols、22 changed files、5 affected、medium）。它不是本计划专属审查，不能当作修复后提交门禁，尤其不能据少量 affected 宣称未跟踪文件无影响。
- 本轮所有影响判断以当前源码补核。实施前重新对实际被编辑的方法执行 impact；提交前重新 detect_changes，partial/truncated 结果不得当作通过。

## 5. 语句级控制流与并发约束

PDG 探针 `pdg_query(controls, _loadRequestedMembers)` 返回 “no PDG layer”。完整 runner provenance 未复核，因此本轮不升级索引；以下为 **source-derived 控制流说明，不是 PDG 边**。

1. [verified] _refreshMutedMembers 捕获会话与请求 generation，名单请求后检查，再 setState，再资料查询，再次检查。
2. [verified] _loadRequestedMembers 先按移除 tombstone 过滤，再读缓存，再挑 missing；SDK 每批最多 50 人，批次前后验证账号/会话。
3. [verified] 默认模式 SDK 全失败仍可能返回 code=0 的剩余缓存/空数组；refresh 模式才有 “Member lookup failed” 分支。现有 callback 的成功码不能代表“昵称头像均完整”。
4. [verified] SDK code=0 即退出当前群 ID 候选循环，哪怕只返回部分成员或资料为空；不能因为调用成功就标记全部对象解决。
5. [verified] _removeMutedMemberLocally 只移除行，没有推进名单请求 generation。当前资料合并不会复活行，但**更早发出的整份名单响应**仍须单独防护。
6. [inferred] 缓存读取、网络返回、权限变化、名单操作与页面销毁都必须作为失效边界；Future timeout 不会自动保证晚到结果不回写。
7. [verified] 保留成员身份、角色、入群元数据的测试已存在，新的展示查询不能破坏这些不变量。

## 6. 拟议修改

### 6.1 解析契约：先接住服务端资料

文件：`lib/src/api/me_group_api.dart`；现有符号：MutedGroupMemberRecord / fromJson。

- 增加向后兼容的可选 nickname、avatarUrl；字段别名以脱敏真实 fixture/后端契约为准，不能凭猜测接受任意 name 字段。
- 保留“字段未提供”和“明确空值”的区别；空头像可能表示用户没有头像，不能无限补查。
- 使用已有规范化习惯；不改变 userId、muteUntilSec、nameCard、imRole 的解析和既有构造调用。
- 头像 URL 如需转对象存储地址，先复用项目已验证的转换方式；不要拼接猜测域名，勿删除签名参数。
- 禁言响应若已含有效昵称和头像，页面首轮即可显示，不等待 SDK。

### 6.2 专用资料查询：隔离展示与成员身份

**拟新增文件**：`lib/src/services/group_local/muted_member_profile_resolver.dart`（新符号尚不存在，实施时确定类名）。

输入包含账号/会话快照、规范化群 ID、目标 UID、当前权威资料与所需字段。
输出逐用户、逐字段记录值、来源、结果状态；最少区分：
resolved / resolved-empty / partial / forbidden / not-found / transient-failure / stale-discarded。
这些是拟定状态，不是现有 SDK 错误码。

查询顺序：
1. 当前授权的禁言接口资料。
2. 同账号同群本地资料作为临时显示，不把“有名片”当成真实昵称已完整。
3. 对缺失或过期对象进行 SDK 定点补查，保留每人的结果，匹配返回 UID；批次最多沿用 50，首版串行批次，不扫描全群。
4. 若 SDK 无资料，展示明确降级。**默认不自动调用通用用户资料接口。** 只有确认权限与数据权威契约后，才能另行启用受限 fallback；不复用把所有异常变 null 的 API 来冒充 typed 成功。

缓存策略：
- 首版仅新增 resolver 的账号/群/会话范围内存缓存与 in-flight 合并；不迁移数据库、不直接写共享成员表。
- 本地磁盘旧资料仅预览；resolver 未验证过则后台复核，进程重启后重新验证，避免永久相信旧占位。
- 拟定成功缓存 TTL 60 秒；显式空资料同样短期缓存，防止合法无头像反复请求。
- 网络失败不记为成功；一次页面自动补查最多追加 1 次退避重试（约 1 秒并带抖动），之后只接受用户重试/下一次进入；429 遵守服务端等待要求，无无限 timer。
- 拟定单批超时 8 秒；超时的请求代次失效，晚到结果不得写缓存或 UI。
- 缓存/in-flight 设上限（建议 500 用户、16 批任务），移除过期/LRU 条目；超量按可见区排队，不能全量并发。
- 昵称等于 UID 仅作为“需复核一次”的启发，不永久判假；权威返回的同名昵称仍可合法显示。

### 6.3 页面与合并

现有文件：tim_uikit_group_manage.dart、muted_member_profiles.dart。
符号：_refreshMutedMembers、_mutedRecordToMemberInfo、_bootstrapManagePage、_removeMutedMemberLocally、mergeMutedMemberProfiles。

- 转换名单时采用 API 资料优先、同账号本地资料候补，并统一 UID 比较。
- 逐字段合并：补头像不能误改昵称，补昵称不能改名片；新业务值不能被旧 SDK 值盖回。
- 保留备注 → 群名片 → 昵称的原有展示顺序；UID 作为末级标识。未完成时显示“资料加载中”，失败后提供轻量重试提示，避免看似正常却长期只有 UID。
- 不让资料补查阻塞禁言名单和解除禁言操作；局部更新对应行，稳定使用规范化 UID 的 key。
- 解除禁言成功推进名单操作版本；所有更早名单/资料结果失效。重新禁言使用新操作版本，不能被永久 tombstone 错挡。
- 真正成功的空名单可清空；请求失败不是空名单。审查 keepExistingOnEmpty 分支，改为由已知在途禁言操作和请求版本控制，不能永久保留已失效名单。
- 手机与桌面选人成功返回均走同一刷新入口；重复进入、重建不可产生重复补查。
- 独立检查图片加载失败：如果 URL 有值但下载/解码失败，要区分于资料字段缺失；使用现有头像组件，不在本任务重写图片缓存系统。

### 6.4 权限与会话

- 每轮读取、发请求、收结果、更新缓存和 UI 都检查 owner、session generation、group、request/operation revision。
- 无管理权限、群已退出/解散、当前账号已禁用时终止本轮；不尝试换群 ID/换资料接口绕过明确的拒绝。
- 会话变化后旧资料不能进入新账号缓存；旧请求即使返回同一个 UID 也必须丢弃。
- 管理员被降级后撤销管理操作和受限展示，不继续拿已缓存的管理权限作授权。
- 隐私开启不是直接归因；是否允许群管理者看该条资料以服务端契约与实际响应为准。
- 本任务只消费现有 ACCOUNT_DISABLED 统一处理，不重新实现退出登录。

### 6.5 可观测性

记录结构化 debug 事件：list_received、profile_cache_hit、profile_fetch_start/result、profile_retry、profile_stale_drop、avatar_load_failed。
包含请求关联 ID、来源、耗时、批大小、缺失字段计数、结果类别；不记录 JWT、完整响应、昵称、可复用头像签名 URL。
必要用户/群标识仅在受控调试中使用脱敏值。发布统计若项目无现成设施，先用本地验收日志，不引入新的外部采集。

## 7. 分阶段实施顺序与门槛

| 阶段 | 工作 | 阶段出口 |
| --- | --- | --- |
| P0 证据与契约 | 核对实际安装版本；采集授权测试账号的 muted 响应、SDK 返回、头像加载错误；冻结 fixture | 明确字段、授权、空值语义；否则客户端可做解析/降级，但不能宣称真实资料已根治 |
| P1 先建失败测试 | 增加解析、缺头像但有昵称、过期非空昵称、原页面集成失败用例 | 未修代码下关键用例失败，证明覆盖真实遗漏 |
| P2 接入字段 | 可选字段解析；_mutedRecordToMemberInfo 用新资料并规范 UID | 接口已有资料时无需 SDK 即能显示；旧接口仍兼容 |
| P3 专用 resolver | 实现逐字段状态、批量、超时、去重、短期缓存和隔离，注入 fake loader 便于测试 | 边界测试通过；共享身份查询完全不变 |
| P4 页面串联 | 合并来源、局部刷新、失败重试、操作版本、同入口刷新、权限失效 | 真实 Widget 异步流程通过；不复活解除禁言行 |
| P5 回归与真机 | 运行 §8；对真实接口及原异常设备验证，记录构建号/耗时/请求数 | 所有必测项通过；无新增权限或会话泄漏 |
| P6 发布与回退演练 | 小范围测试构建→确认后正式发布；验证可独立撤回 UI/resolver | 证据完整后才关闭问题 |

每步只改本任务文件；保留当前大量无关未提交修改。生产代码变更前必须重新 impact。
本轮不执行上述阶段，不自动提交、上传或更改后端。若执行中发现必须新增后端能力，应先报告契约缺口，不擅自扩展范围。

## 8. 测试与真机验收

### 自动化场景

| 类别 | 输入/动作 | 预期 |
| --- | --- | --- |
| 解析 | 旧响应仅 UID；新响应含资料；缺失/null/空串/别名 | 旧构造兼容，字段不丢，缺失与显式空分开 |
| 冷缓存 | 权威名单有资料或 SDK 有资料 | 自动更新行，不要求用户先打开完整成员列表 |
| 部分缓存 | 有昵称无头像、有名片无昵称、有头像无昵称 | 每个缺失字段都可补查，已有正确字段不被清空 |
| 旧缓存 | 非空旧昵称/旧头像、UID 占位；重启应用 | 一次复核可更新；不依赖“空字段才写” |
| 来源冲突 | API 新昵称 A、SDK 旧昵称 B | 保持 A；仍保留有效备注/群名片 |
| 合法空值 | 用户确实无头像；真实昵称等于 UID | 有限次数验证后正常降级，不循环请求 |
| ID | UID、@UID、c2c_UID，返回了其他 UID | 规范化匹配；错人返回丢弃 |
| 部分返回 | 50 人只返回 20、空 code=0、一个批次失败 | 已成功的独立显示；剩余保持未解决，不全标成功 |
| 边界规模 | 0、1、50、51、200 条，滚动/重复重建 | 去重、小批量、无全群拉取、无每帧网络请求 |
| 失败 | timeout、断网、5xx、429 | 保留授权可用资料，明确失败状态，有界退避可手动重试 |
| 权限 | 普通403、角色降级、隐私拒绝、退群 | 不换接口绕权；撤销受限资料与操作 |
| 账号禁用 | ACCOUNT_DISABLED | 使用已有退出流程；终止本轮补查 |
| 并发 | 旧响应比新响应晚、重试并行、快速切群 | 只采纳当前版本，不写回旧群 |
| 账号切换 | A→B、同账号退出重登、Future 晚返回 | A 的结果不得进入 B/新代次 |
| 操作并发 | 请求中解除禁言、解除后再禁言、解除失败 | 成功后不复活；新禁言可出现；失败不错误移除 |
| 生命周期 | 请求中退出页面、前后台恢复 | 无 setState after dispose；恢复仅一次必要刷新 |
| 头像资源 | 正确 URL、404、过期签名、解码失败 | 不误诊为昵称缺失；有区别的日志，不触发无限资料请求 |

### 测试文件

新增（拟定路径）：
- test/muted_member_record_test.dart：响应 fixture 与解析。
- test/muted_member_profile_resolver_test.dart：状态、缓存、网络和会话隔离。
- test/group_manage_muted_profiles_test.dart：真正挂载管理页，使用测试 HTTP/SDK loader；断言列表文字与传入头像 URL、异步更新和操作保护。不用 Type 检查代替 Widget 验证。

扩展 test/muted_member_profiles_test.dart，并回归：
- test/group_member_on_demand_test.dart
- test/group_member_entry_refresh_test.dart
- test/group_member_store_face_url_test.dart
- test/group_privacy_guard_test.dart

[verified] Flutter 命令在本机可用，pubspec 已有 flutter_test 与 sqflite_common_ffi；上述现有测试文件已定位。新增文件尚不存在，命令必须在实施后运行：

```powershell
flutter test --no-pub test/muted_member_profiles_test.dart test/group_member_on_demand_test.dart test/group_member_entry_refresh_test.dart test/group_member_store_face_url_test.dart test/group_privacy_guard_test.dart
flutter test --no-pub test/muted_member_record_test.dart test/muted_member_profile_resolver_test.dart test/group_manage_muted_profiles_test.dart
flutter analyze --no-pub lib/src/api/me_group_api.dart lib/src/services/group_local/muted_member_profile_resolver.dart test/muted_member_record_test.dart test/muted_member_profile_resolver_test.dart test/group_manage_muted_profiles_test.dart
git diff --check
```

从根项目验证嵌套 UIKit 页面编译；不得把嵌套包缺少根包依赖导致的分析失败当作“检查通过”。现有告警单列，新增错误必须清零。本轮未执行新修复测试，不引用此前 ACCOUNT_DISABLED 的 44 项作为本问题通过证据。

### 真机矩阵与量化验收

至少包含原异常设备、一个其他 Android 设备、一个 iPhone；若桌面/Web 同样使用该管理页，补做对应入口冒烟。记录系统版本、构建号、角色、群隐私开关、缓存状态和网络环境。

使用有已知昵称与头像的测试成员（不要以默认头像用户作成功样本）：
1. 全新测试安装/冷账号缓存进入管理页；不先打开该成员资料页。
2. 保留旧缓存升级；远端改昵称头像后重新进入。
3. 群隐私开/关，群主/管理员/普通成员，运行中管理员降级。
4. 弱网/断网后恢复、反复进入20次、后台恢复、杀进程重启。
5. 补查过程中解除禁言、再次禁言、切换账号和群。
6. 有 URL 但图片加载失败的故障注入，与字段缺失分开记录。

验收目标（拟定，不是已测成绩）：正常网络下授权资料请求完成后的下一次可用渲染周期更新行；有API资料不等待SDK；无二次手势依赖；20次重入无跨账号资料、无重复行、无永久加载；每轮每个缺失UID最多初次+1次自动重试，常规UI重建请求数为0。网络总耗时单独记录，不承诺所有设备/网络固定秒数。

## 9. 风险、依赖覆盖与回退

### 直接依赖逐项处理

[graph] MutedGroupMemberRecord 的16个直接节点为文件级 IMPORTS，不等于每处都构造该类；保持 API 向后兼容，范围内编译/回归并检查没有误改导出：

1. lib/src/all_group_application_list.dart
2. lib/src/api/group_notice_api.dart
3. lib/src/chat.dart
4. lib/src/create_group.dart
5. lib/src/group_info_detail.dart
6. lib/src/group_profile.dart
7. lib/src/pages/join_group_application_page.dart
8. lib/src/services/group_local/group_create_service.dart
9. lib/src/services/group_local/group_member_incremental_sync_service.dart
10. lib/src/services/group_local/group_membership_sync_service.dart
11. lib/src/services/group_notice_incremental_sync_service.dart
12. lib/utils/group_admin_role_message.dart
13. lib/utils/group_leave_message.dart
14. lib/utils/group_member_join_meta_loader.dart
15. third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_group_profile_model.dart
16. third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitGroupProfile/widgets/tim_uikit_group_manage.dart

以上是图谱依赖名单，未宣称逐文件行为已源码验证，非新增改动清单。
其他直接依赖：_bootstrapManagePage / tuiBuild → _refreshMutedMembers；_refreshMutedMembers → mergeMutedMemberProfiles；loadGroupMembersInfo → _loadRequestedMembers；applyTargetedMemberCorrection → loadGroupMembersInfo。本方案不修改最后两项的共享语义。
源码补充依赖：GroupMemberJoinMetaLoader、GroupInviteMemberPageMeta、uikit_self_hosted_group_bridge / SelfHostedGroupBridge，相关风险由 §8 原有测试和根项目编译覆盖。

### 关键风险控制

- 最高业务风险是权限泄漏、串号和误恢复成员，而非暂时显示占位；这些任一出现即阻断发布。
- SDK资料可能不同步：业务资料优先；P0 无权威返回则报告后端缺口，不能只调整缓存掩盖。
- 共享成员表不作为新 resolver 的写入目标，避免异步读改写覆盖角色、禁言和入群来源；后续若必须持久化，需另做字段级原子更新/权限失效设计。
- 内存缓存短期有界，首次重入复核会增加少量定点请求，必须记录次数；不许改成每次 build 强刷。
- 暂不清图像全局缓存；若同 URL 换图导致旧图，先确认 avatarVersion/资源版本契约，另做定向失效，不全局清库。

### 回退

按 P2解析、P3resolver、P4页面三个独立可回退单元实施。试发失败可先撤回页面对新 resolver 的接入，保留向后兼容字段解析，恢复原占位展示但维持正确禁言操作。
只回退本任务提交/补丁，绝不 git reset --hard 或覆盖用户其他脏文件。首版无数据库迁移，因此不需要降级清库。
发布前演练旧响应与新响应都能被上一版/新版客户端处理。若新增开关需复用项目已有配置设施，不为本问题新建远程配置系统。
回退触发：任何串号/绕权/成员复活；持续请求风暴；禁言操作失败率增加；页面崩溃。回退不意味着问题已修复，需保留故障样本继续定位。

## 10. 预期变更文件

| 文件 | 责任 | 备注 |
| --- | --- | --- |
| lib/src/api/me_group_api.dart | 可选资料字段解析 | 公共文件 HIGH，兼容优先 |
| third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitGroupProfile/widgets/tim_uikit_group_manage.dart | 接入、行状态、请求/操作版本 | 保留用户现有改动 |
| third_party/tencent_cloud_chat_uikit/lib/ui/utils/muted_member_profiles.dart | 来源感知逐字段合并 | 当前未跟踪文件，不可遗漏打包 |
| lib/src/services/group_local/muted_member_profile_resolver.dart | 新专用查询服务 | 拟新增，注入可测试依赖 |
| test/muted_member_profiles_test.dart | 扩展合并回归 | 当前已存在未跟踪 |
| test/muted_member_record_test.dart | 新解析测试 | 拟新增 |
| test/muted_member_profile_resolver_test.dart | 新服务测试 | 拟新增 |
| test/group_manage_muted_profiles_test.dart | 新页面集成测试 | 拟新增 |

不预计修改 group_membership_sync_service.dart、group_member_local_store.dart、UserApi 或数据库schema；如执行证据要求改变，先重新评估影响并更新计划，不静默扩大范围。

## 11. 可复用实施上下文

以下为机器可读 JSON（完整 schema-2 快照原样嵌入）。执行前重新快照；若引用文件变化，先重读对应范围，不仅更新 HEAD。Windows 安全 read-plan 的限制仍须明确处理，本次写入豁免不伪造读取收据。

```json
{
  "implementation_context": {
    "task_summary": "禁言成员真实昵称与头像完整修复；本文件为计划，不是已实施结果。",
    "acceptance_criteria": [
      "授权且服务端有资料时，冷缓存/旧缓存均能自动显示昵称和头像",
      "禁言名单、角色、成员身份权威不被资料查询覆盖",
      "账号/群切换、解除禁言、权限收回后的旧响应不得回写",
      "资料缺失、权限拒绝、网络失败有可区分结果和有界重试",
      "真实接口与原异常设备通过验收；不能仅依赖合并函数单测"
    ],
    "evidence_provenance": {
      "schema_version": 2,
      "head_commit": "b6dcaaae0999d698f822222a393d59823d3ed55f",
      "generated_plan_path": "docs/plans/2026-09-22-gitnexus-plan-muted-member-profile-recovery.md",
      "global_dirty_digest": {
        "algorithm": "sha256",
        "canonicalization": "gitnexus-evidence-provenance-v2 NUL-framed UTF-8 records",
        "value": "614c7750a99cf4d0c05c07e799183728f431547775dbb85368c09094c193f85f"
      },
      "cited_path_manifest": [
        {
          "path": "lib/src/api/me_group_api.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:a824176242ea1b6064b96d1c14abc88d750b67603221a9a6efd66b651c6e04d5",
          "index_digest": "sha256:a824176242ea1b6064b96d1c14abc88d750b67603221a9a6efd66b651c6e04d5",
          "worktree_digest": "sha256:2676489cc43faa80a70b64337fe5421448808465f83d280d0fa77da5695731db",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/api/user_api.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:591f7e8ddfe3fafe388455e284755290e61fd66cb6ab46401a22b9bcbb207fa7",
          "index_digest": "sha256:591f7e8ddfe3fafe388455e284755290e61fd66cb6ab46401a22b9bcbb207fa7",
          "worktree_digest": "sha256:591f7e8ddfe3fafe388455e284755290e61fd66cb6ab46401a22b9bcbb207fa7",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/platform/uikit_self_hosted_group_bridge.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:a0b8d628e759d50965412b095d64083f5d35f4bb6ce75cffc5a3815b0aa2dd8e",
          "index_digest": "sha256:a0b8d628e759d50965412b095d64083f5d35f4bb6ce75cffc5a3815b0aa2dd8e",
          "worktree_digest": "sha256:a0b8d628e759d50965412b095d64083f5d35f4bb6ce75cffc5a3815b0aa2dd8e",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/group_local/group_member_local_store.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:e4f7cd44bf2581d1d5f8a52ff64c9477c17c76c3cb6d75cce01008b3d89c4137",
          "index_digest": "sha256:e4f7cd44bf2581d1d5f8a52ff64c9477c17c76c3cb6d75cce01008b3d89c4137",
          "worktree_digest": "sha256:d413d96f24019f3f27f0b01999fd3b6e635bc59ff75306b6970891d79b748fd0",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/services/group_local/group_membership_sync_service.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:57f479787570f532c0a039bb3bbc13ecdd5645831dd2461c35246ab3eba0cd41",
          "index_digest": "sha256:57f479787570f532c0a039bb3bbc13ecdd5645831dd2461c35246ab3eba0cd41",
          "worktree_digest": "sha256:b4ea8c4c5846a6108af2551facda501bbc391a8b974a730f17b1cd3ca280c83f",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/src/utils/group_invite_member_page_meta.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:1920410a84b067574cdde786500b74d3389ddabb8ba9eac7c3ecea62c46de261",
          "index_digest": "sha256:1920410a84b067574cdde786500b74d3389ddabb8ba9eac7c3ecea62c46de261",
          "worktree_digest": "sha256:67c34c121576878bf3a79890de6f56defe8813db8ec0477e4035e2efc4f16710",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/utils/chat_id_format.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:132b3bc8ed80bcda846f9364e8e49cf92a8fe3f26e7f094484265b0d49a58949",
          "index_digest": "sha256:132b3bc8ed80bcda846f9364e8e49cf92a8fe3f26e7f094484265b0d49a58949",
          "worktree_digest": "sha256:132b3bc8ed80bcda846f9364e8e49cf92a8fe3f26e7f094484265b0d49a58949",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/utils/group_member_join_meta_loader.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:fcd7d52f554d219c10a916c7c8844c8ab0cdcd791540add01f41614ed791c001",
          "index_digest": "sha256:fcd7d52f554d219c10a916c7c8844c8ab0cdcd791540add01f41614ed791c001",
          "worktree_digest": "sha256:fcd7d52f554d219c10a916c7c8844c8ab0cdcd791540add01f41614ed791c001",
          "untracked_digest": "absent"
        },
        {
          "path": "lib/utils/group_privacy_guard.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:74d94358f7750c538ea0897ebefc96a525bc6a54196699d3a7a490733d4ebde2",
          "index_digest": "sha256:74d94358f7750c538ea0897ebefc96a525bc6a54196699d3a7a490733d4ebde2",
          "worktree_digest": "sha256:74d94358f7750c538ea0897ebefc96a525bc6a54196699d3a7a490733d4ebde2",
          "untracked_digest": "absent"
        },
        {
          "path": "pubspec.yaml",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "unstaged",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:e4b31fbea941eaeae804d4fa8cc578899aa61374f36bbd984b92645f61359a1b",
          "index_digest": "sha256:e4b31fbea941eaeae804d4fa8cc578899aa61374f36bbd984b92645f61359a1b",
          "worktree_digest": "sha256:b56b40a618b40c117e25ca88926648386580380aa862d940ead3a89d39318ccf",
          "untracked_digest": "absent"
        },
        {
          "path": "test/group_member_entry_refresh_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:649da9381bb462cf178772536c5fc60d23bf77d7a256b03840b4b3864cb0cb9b",
          "index_digest": "sha256:649da9381bb462cf178772536c5fc60d23bf77d7a256b03840b4b3864cb0cb9b",
          "worktree_digest": "sha256:649da9381bb462cf178772536c5fc60d23bf77d7a256b03840b4b3864cb0cb9b",
          "untracked_digest": "absent"
        },
        {
          "path": "test/group_member_on_demand_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:f580ac59320babadd0c463d1f1eae899beb0fb4f60909a4621e4adb2e71ac22f",
          "index_digest": "sha256:f580ac59320babadd0c463d1f1eae899beb0fb4f60909a4621e4adb2e71ac22f",
          "worktree_digest": "sha256:f580ac59320babadd0c463d1f1eae899beb0fb4f60909a4621e4adb2e71ac22f",
          "untracked_digest": "absent"
        },
        {
          "path": "test/group_member_store_face_url_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:61499daef2127791d0aa06e089067da3446a9b62f814c1c4b0b8b9b237e7c06a",
          "index_digest": "sha256:61499daef2127791d0aa06e089067da3446a9b62f814c1c4b0b8b9b237e7c06a",
          "worktree_digest": "sha256:ae8ea588f346fdaaa753f89eb59bc9bce17377578bed0e7fd1ccca895e8c8adb",
          "untracked_digest": "absent"
        },
        {
          "path": "test/group_privacy_guard_test.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:eb555116c948f6a06d8f94aade942656321de4cefc3866ad82f1854c92af0dfc",
          "index_digest": "sha256:eb555116c948f6a06d8f94aade942656321de4cefc3866ad82f1854c92af0dfc",
          "worktree_digest": "sha256:eb555116c948f6a06d8f94aade942656321de4cefc3866ad82f1854c92af0dfc",
          "untracked_digest": "absent"
        },
        {
          "path": "test/muted_member_profiles_test.dart",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:34fb6e3ddcc385e6dfb70a7e6bed3ad5271c279ee84c97781d386914aaef3ec4"
        },
        {
          "path": "third_party/tencent_cloud_chat_sdk/lib/manager/v2_tim_group_manager.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:9f6e1635e33d0bd572492c2a2c1f84e080a824941db91a22d7d948714fe56d8b",
          "index_digest": "sha256:9f6e1635e33d0bd572492c2a2c1f84e080a824941db91a22d7d948714fe56d8b",
          "worktree_digest": "sha256:9f6e1635e33d0bd572492c2a2c1f84e080a824941db91a22d7d948714fe56d8b",
          "untracked_digest": "absent"
        },
        {
          "path": "third_party/tencent_cloud_chat_uikit/lib/data_services/group/group_services_implement.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:7eb40e7da8119568007f43ce77e76a98a57a139db0d05c931aa3adca384e10f6",
          "index_digest": "sha256:7eb40e7da8119568007f43ce77e76a98a57a139db0d05c931aa3adca384e10f6",
          "worktree_digest": "sha256:7eb40e7da8119568007f43ce77e76a98a57a139db0d05c931aa3adca384e10f6",
          "untracked_digest": "absent"
        },
        {
          "path": "third_party/tencent_cloud_chat_uikit/lib/data_services/group/self_hosted_group_bridge.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "clean",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:e41ab9336f154995a71ced3ad0ea365d9dd030bb6f5be109a449f80fa01e99e7",
          "index_digest": "sha256:e41ab9336f154995a71ced3ad0ea365d9dd030bb6f5be109a449f80fa01e99e7",
          "worktree_digest": "sha256:e41ab9336f154995a71ced3ad0ea365d9dd030bb6f5be109a449f80fa01e99e7",
          "untracked_digest": "absent"
        },
        {
          "path": "third_party/tencent_cloud_chat_uikit/lib/ui/utils/muted_member_profiles.dart",
          "object_kind": {
            "head": "absent",
            "index": "absent",
            "worktree": "absent",
            "untracked": "regular"
          },
          "state": "untracked",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "absent",
          "index_digest": "absent",
          "worktree_digest": "absent",
          "untracked_digest": "sha256:91f3b01148a4737d24b9e656be77288a6a17763f579b3c8074c74033bd482854"
        },
        {
          "path": "third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitGroupProfile/widgets/tim_uikit_group_manage.dart",
          "object_kind": {
            "head": "regular",
            "index": "regular",
            "worktree": "regular",
            "untracked": "absent"
          },
          "state": "unstaged",
          "rename_from": null,
          "rename_to": null,
          "head_digest": "sha256:72d5ac43c00d135e5df340ffb3ce4b8c9a66d48b825191b021f1769da106fc54",
          "index_digest": "sha256:72d5ac43c00d135e5df340ffb3ce4b8c9a66d48b825191b021f1769da106fc54",
          "worktree_digest": "sha256:7a878bfa31ee87257892b881dbdc345d5198815543c126789e9632cbba59b700",
          "untracked_digest": "absent"
        }
      ]
    },
    "primary_symbols": [
      {
        "symbol": "MutedGroupMemberRecord.fromJson",
        "file": "lib/src/api/me_group_api.dart",
        "lines": "70-102",
        "role": "禁言记录解析；当前不保留昵称头像"
      },
      {
        "symbol": "_refreshMutedMembers",
        "file": "third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitGroupProfile/widgets/tim_uikit_group_manage.dart",
        "lines": "390-427",
        "role": "名单与资料两阶段刷新"
      },
      {
        "symbol": "_loadRequestedMembers",
        "file": "lib/src/services/group_local/group_membership_sync_service.dart",
        "lines": "1026-1157",
        "role": "共享查询；保留默认与 refresh 身份核验语义，作为兼容边界"
      },
      {
        "symbol": "mergeMutedMemberProfiles",
        "file": "third_party/tencent_cloud_chat_uikit/lib/ui/utils/muted_member_profiles.dart",
        "lines": "7-33",
        "role": "只合并仍存在行的展示字段；扩展来源优先级"
      },
      {
        "symbol": "_mutedRecordToMemberInfo",
        "file": "third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitGroupProfile/widgets/tim_uikit_group_manage.dart",
        "lines": "429-449",
        "role": "API资料优先与UID规范化"
      }
    ],
    "related_symbols": [
      {
        "symbol": "_bootstrapManagePage / tuiBuild",
        "relationship": "CALLS _refreshMutedMembers",
        "relevance": "首次进入、选人返回、平台入口一致性"
      },
      {
        "symbol": "_removeMutedMemberLocally",
        "relationship": "mutates current rows",
        "relevance": "解除禁言后阻止旧名单和旧资料恢复行"
      },
      {
        "symbol": "applyTargetedMemberCorrection",
        "relationship": "CALLS loadGroupMembersInfo",
        "relevance": "共享服务直接依赖；不改变"
      },
      {
        "symbol": "GroupInviteMemberPageMeta.existingMemberUserIds",
        "relationship": "CALLS loadGroupMembersInfo refresh:true",
        "relevance": "不得用历史资料伪装当前成员身份"
      },
      {
        "symbol": "GroupMemberJoinMetaLoader.loadVisible",
        "relationship": "CALLS loadGroupMembersInfo",
        "relevance": "入群来源资料保持兼容"
      },
      {
        "symbol": "SelfHostedGroupBridge.loadGroupMembersInfo",
        "relationship": "callback through uikit_self_hosted_group_bridge",
        "relevance": "图谱未完整覆盖的共享入口"
      },
      {
        "symbol": "UserApi.tryFetchUserById / _fetchUserById",
        "relationship": "potential fallback, not selected",
        "relevance": "失败统一 null；权限契约未确认，不用于自动换接口兜底"
      },
      {
        "symbol": "GroupPrivacyGuard.blockedGroupProfileHint",
        "relationship": "existing UI policy reference",
        "relevance": "客户端策略不是后端授权；不能跨接口绕权"
      }
    ],
    "execution_path": [
      "读取带权威禁言状态的名单",
      "字段解析并按规范化UID建立行",
      "读取同账号/同群展示缓存，立即展示可用资料",
      "仅对需要验证的资料定点补查",
      "按账号代次/群/请求版本/权限版本/当前名单验证结果",
      "逐字段按来源合并并更新页面；失败不改变禁言状态"
    ],
    "pdg_constraints": [],
    "pdg_note": "pdg_query controls _loadRequestedMembers 返回 no PDG layer；§5仅源码控制流，不伪造PDG边。",
    "architectural_patterns": [
      {
        "pattern": "账号与代次隔离、在途请求合并",
        "example_location": "lib/src/services/group_local/group_membership_sync_service.dart:loadGroupMembersInfo",
        "usage_guidance": "新专用 resolver 借鉴，不改变现有成员身份返回语义"
      },
      {
        "pattern": "只合并当前名单",
        "example_location": "third_party/tencent_cloud_chat_uikit/lib/ui/utils/muted_member_profiles.dart:mergeMutedMemberProfiles",
        "usage_guidance": "继续保留解除禁言保护与角色/禁言字段"
      },
      {
        "pattern": "定点UID查询，禁止扫描全群",
        "example_location": "test/group_member_on_demand_test.dart:606",
        "usage_guidance": "小批量只查缺失/到期对象，无分页0扫描"
      }
    ],
    "files_to_modify": [
      {
        "file": "lib/src/api/me_group_api.dart",
        "symbols": [
          "MutedGroupMemberRecord",
          "MutedGroupMemberRecord.fromJson"
        ],
        "intended_change": "可选昵称头像字段及字段存在性；仅支持已确认别名，不改权威禁言字段"
      },
      {
        "file": "third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitGroupProfile/widgets/tim_uikit_group_manage.dart",
        "symbols": [
          "_refreshMutedMembers",
          "_mutedRecordToMemberInfo",
          "_bootstrapManagePage",
          "_removeMutedMemberLocally"
        ],
        "intended_change": "专用资料查询接入、来源感知合并、失败可见、并发与操作版本保护"
      },
      {
        "file": "third_party/tencent_cloud_chat_uikit/lib/ui/utils/muted_member_profiles.dart",
        "symbols": [
          "mergeMutedMemberProfiles"
        ],
        "intended_change": "展示字段质量与来源优先级；API新资料不被SDK旧资料覆盖"
      },
      {
        "file": "lib/src/services/group_local/muted_member_profile_resolver.dart",
        "symbols": [
          "新增，名称待实施确认"
        ],
        "intended_change": "禁言页专用的有界查询、状态、短期缓存与会话隔离；不写群身份表"
      }
    ],
    "tests": [
      {
        "file": "test/muted_member_profiles_test.dart",
        "scenarios": [
          "逐字段补全",
          "新API值优先于旧SDK值",
          "UID别名",
          "解除禁言不复活",
          "空值不误清有效值"
        ]
      },
      {
        "file": "test/muted_member_record_test.dart",
        "scenarios": [
          "新增；新旧响应解析",
          "真实fixture字段兼容",
          "字段缺失与显式空区分"
        ]
      },
      {
        "file": "test/muted_member_profile_resolver_test.dart",
        "scenarios": [
          "新增；冷缓存/旧缓存/部分成功",
          "名片存在头像缺失仍补查",
          "权限拒绝不换接口",
          "超时/429有界退避",
          "账号及请求版本隔离",
          "50条边界与去重"
        ]
      },
      {
        "file": "test/group_manage_muted_profiles_test.dart",
        "scenarios": [
          "新增；真实管理页挂载，不仅检查Type",
          "接口→解析→resolver→列表文本与头像源",
          "反序响应/页面销毁/切群/账号切换",
          "解除禁言/重新禁言/操作失败",
          "权限降级"
        ]
      },
      {
        "file": "test/group_member_on_demand_test.dart",
        "scenarios": [
          "现有共享行为回归，默认缓存/无全群扫描/角色权威保持"
        ]
      },
      {
        "file": "test/group_member_entry_refresh_test.dart",
        "scenarios": [
          "refresh:true保留身份验证空结果及失败语义"
        ]
      },
      {
        "file": "test/group_member_store_face_url_test.dart",
        "scenarios": [
          "已有头像覆盖与晚到快照保护回归"
        ]
      },
      {
        "file": "test/group_privacy_guard_test.dart",
        "scenarios": [
          "隐私策略回归；不能替代新增服务端拒绝场景"
        ]
      }
    ],
    "verification_commands": [
      "flutter test --no-pub test/muted_member_profiles_test.dart test/group_member_on_demand_test.dart test/group_member_entry_refresh_test.dart test/group_member_store_face_url_test.dart test/group_privacy_guard_test.dart",
      "flutter test --no-pub test/muted_member_record_test.dart test/muted_member_profile_resolver_test.dart test/group_manage_muted_profiles_test.dart （新增文件完成后）",
      "flutter analyze --no-pub lib/src/api/me_group_api.dart lib/src/services/group_local/muted_member_profile_resolver.dart test/muted_member_record_test.dart test/muted_member_profile_resolver_test.dart test/group_manage_muted_profiles_test.dart （新增文件完成后）",
      "git diff --check",
      "node .gitnexus/run.cjs detect-changes --scope all --repo . （仅提交前；partial/truncated 不算通过）"
    ],
    "risks": [
      "图谱 MutedGroupMemberRecord HIGH：16个文件级IMPORTS；保持可选字段向后兼容",
      "图谱无PDG且部分调用缺失，不以LOW作为完备性证明",
      "后端没资料/无权限时客户端不能保证真实头像",
      "旧请求、权限变更、缓存跨账号泄漏",
      "新增resolver与共享查询重复请求；限定禁言页小批量、有界缓存"
    ],
    "assumptions": [
      "实施前记录异常设备实际安装版本，确认包含上次改动",
      "实施前用授权测试账号核对 /members/muted 的响应字段和资料可见性",
      "SDK昵称头像可能非业务权威，必须与已知测试用户资料对照",
      "先不增加数据库schema、不清空群成员库；缓存只作临时展示"
    ],
    "open_questions": [
      "禁言接口实际返回nickname/avatarUrl及字段清空语义是什么？",
      "隐私开启时群主/管理员的名单资料授权是否明确？",
      "SDK空资料是未设置、隐私过滤还是同步缺失？",
      "是否有头像版本/更新时间？没有则不能保证同URL换图立即失效。"
    ],
    "avoid": [
      "不要重复全仓探索；先复核本包引用的变动",
      "不把refresh:true改为失败时返回旧成员",
      "不全量拉群成员或调用搜人接口凑资料",
      "不新增未确认后端接口或绕过403",
      "不覆盖role/muteUntil/入群信息，不以资料响应增删禁言名单",
      "不清用户缓存/数据库作为修复步骤",
      "不改无关脏文件，不自动提交/推送",
      "图谱未完整或摘要变化时重新验证，而不是宣称无影响"
    ],
    "publication_exception": "用户2026-09-22明确允许本次普通文件补丁保存；Windows安全write-plan不可用。snapshot仍采用官方schema2 helper。后续执行若safe read-plan仍不支持Windows，需另行明确兼容读取方式，不能冒充安全读取收据。"
  }
}
```

## 12. 假设、待确认问题与明确延后项

### 必须确认

- [assumed] 异常设备已安装包含前次修复的构建；用构建号/提交标识确认，而非只比较页面外观。
- [assumed] 禁言业务接口可提供目标用户的昵称头像。P0需脱敏实际响应或后端契约；若没有，确认后端是否能在现有响应增加向后兼容字段。
- [assumed] 群主/管理员在隐私开启时有权显示名单基础资料。以服务端允许/拒绝结果确认，不能用客户端角色缓存代替。
- [assumed] SDK所提供资料可补业务昵称头像。需与已知用户交叉验证；若非同一资料源，应以业务端补全为主。
- [assumed] 60秒TTL、8秒单批超时、一次自动重试适合当前产品负载；通过真机请求计数和体验验证后调整。
- [inferred] 本轮源码缺口足以解释症状，但缺少复现请求证据，不能把所有空头像都归因于缓存。
- 图谱 HEAD 与当前 HEAD 相同不等于工作区或构建完全一致；无 PDG，runner 完整构建身份未核实，未刷新。必要时执行阶段验证后运行 node .gitnexus/run.cjs analyze --index-only --pdg。
- Windows安全writer不可用已获本次普通补丁豁免；证据snapshot成功。后续读取/执行方式不能冒充技能安全收据。

### 延后且不属于本次

全应用统一资料缓存重构；所有群成员库 schema 迁移；全局头像下载器/缓存重写；修改添加好友隐私策略；后台新增批量用户接口；修复无关聊天历史、直播、投诉、六合彩页面。若后端契约缺失阻碍目标，单独请求授权并明确交付依赖。

## 13. 完成定义

- [ ] P0 已有真实授权响应和安装版本证据，原问题能被新测试复现。
- [ ] 旧/新禁言响应兼容，昵称头像按字段补齐且来源正确。
- [ ] 冷缓存、非空旧缓存、重启、弱网恢复都不长期无解释地停留 UID。
- [ ] 禁言、角色、身份、名片和备注业务语义不被资料查询破坏。
- [ ] 会话/群/权限/请求操作版本隔离通过，解除禁言不复活。
- [ ] 失败、合法空、拒绝与部分成功能区分；无无限重试和全群扫描。
- [ ] Widget完整链路、resolver、解析与共享回归全部通过；新增静态错误为0。
- [ ] 原异常设备和规定真机矩阵通过，保留构建号与脱敏日志；未测平台明确列出。
- [ ] 回退演练完成，无清库/破坏用户数据步骤。
- [ ] 如需提交，impact及完整detect_changes门禁通过；无关脏文件未混入。
- [ ] 不能仅以“单元测试通过”或“截图看起来正常”宣布彻底解决。

---
本计划使用 gitnexus-plan 深入版；已按用户授权在 Windows 采用普通文件补丁保存。技能兼容性反馈：安全计划 writer/read-plan 目前限制 Windows，snapshot 可正常使用。

