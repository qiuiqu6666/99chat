# W0–W7 后端配合与接口清单

状态：2026-09-28 源码复核，尚未修改或部署后端。后端本地 HEAD 为 `54ffe5b728fb41f638f855a85f8830b28f024206`；相关同步目录干净，GitNexus 后端索引核对为 up-to-date。源码行为不等于线上部署实测。

客户端绑定 `99chat-unread-rebound`，本轮已重建导航索引；重建后其他并行任务又修改了三个群名片相关路径。本清单使用当前 `SyncApi` 等相关源码核实，未将客户端全工作区表述为静止的最新快照。

最明确的后端实改是联系人设备隔离/幂等提交，以及照片、视频的查重与上传恢复。启动界面、聊天列表/滚动、图片缩放、客户端会话并发、SQLite 生命周期修复本身不要求改造全部业务接口。

## 1. 联系人差量：启用 A11 前必须落实

以下为现有真实路由，没有 `/api/v1` 前缀。

| 接口 | 后端需要实现或补强的行为 |
| --- | --- |
| `GET /me/sync/status` | 同步基线按登录用户＋设备区分，不能让新设备继承另一台设备的全量时间或 revision；可通过可选字段发布新同步能力 |
| `POST /me/sync/contacts/sessions` | 将 session 绑定已认证用户、设备及其基线；验证请求模式和基线版本；缺基线/冲突时要求重新完整同步 |
| `POST /me/sync/contacts/batch` | 每个批次可安全重试：相同批次/相同内容不重复计数或产生副作用，相同标识不同内容明确冲突；联系人来源与修改范围绑定设备 |
| `POST /me/sync/contacts/complete` | 成功后重复请求返回同一持久回执；确认批次完整，再提交变更、明确删除及新设备 revision；并发完成只提交一次，失败不能推进基线 |

当前明确缺口：

- `deviceId` 已进入 session，但联系人唯一域是 `user_id + local_contact_id`，状态域是 `userId + syncType`。应增加设备来源映射和设备同步状态；删除只能删除该设备的来源关系，不能误删另一设备的数据。
- complete 完成后仍经 `requireRunningSession`，重试返回 409，无法应对“服务端已成功但响应丢失”。
- batch 直接写正式联系人表，重放会重复累计统计。complete 方法虽然有事务，整轮多批同步还没有原子提交边界。建议暂存批次后完整校验、原子提交；若采用逐批提交，必须明确较弱合同，客户端不能将失败轮次视为完整基线。

已经具备的行为要保留：batch 合并更新；只删除显式 `deletedLocalContactIds`；零批次与空删除列表可以完成。差量没有出现的联系人必须保留。无权限、采集失败不得伪装为“成功采集到空通讯录”。

建议字段（**拟新增，不是当前合同**）：能力 `contactsDeltaV2`；`baseRevision`、`batchId`、`payloadHash`、`snapshotComplete`、`committedRevision`。可根据现有 session 标识精简字段，语义不可省略。设备标识必须在用户身份下验证，不能只靠任意字符串决定可修改的数据域。

主要修改位置：

- [SyncController.java](<C:/Users/ASUS/Downloads/Telegram Desktop/99chat-server/src/main/java/com/chat99/server/sync/SyncController.java:22>)：状态、session、batch、complete 请求与回执。
- `SyncStatusService`：设备维度的同步状态与兼容旧版的能力/基线读取。
- [ContactSyncService.java](<C:/Users/ASUS/Downloads/Telegram Desktop/99chat-server/src/main/java/com/chat99/server/sync/ContactSyncService.java:68>)：设备范围、批次、删除与提交逻辑。
- [SyncSessionService.java](<C:/Users/ASUS/Downloads/Telegram Desktop/99chat-server/src/main/java/com/chat99/server/sync/SyncSessionService.java:37>)：已完成请求重放、并发完成。
- [UserContactItem.java](<C:/Users/ASUS/Downloads/Telegram Desktop/99chat-server/src/main/java/com/chat99/server/sync/UserContactItem.java:19>)、[UserSyncState.java](<C:/Users/ASUS/Downloads/Telegram Desktop/99chat-server/src/main/java/com/chat99/server/sync/UserSyncState.java:26>)：设备来源/基线，以及对应 Repository 查询和数据库迁移。

数据库设备来源改造后，联动检查现有 `GET /me/sync/contacts` 的读取投影，维持已约定的账号级展示/聚合语义，避免因为来源行变多而向旧客户端返回重复项；不默认把读接口也强制改成只返回单设备。

## 2. 照片和视频：修复现有恢复合同

视频也通过客户端 `/photos/*` 接口进入后端，再委托 `VideoSyncService`，不需要凭空新增 `/videos/*` 路由。

| 接口 | 后端需要实现或补强的行为 |
| --- | --- |
| `POST /me/sync/photos/check` | 内容 hash 不同不能仅因 `localAssetId` 相同判定已备份；本地 ID 作为设备内来源关联；覆盖照片和视频 |
| `POST /me/sync/photos/init-upload` | 处理 check 后其他请求已提交同 hash 的竞态；响应必须是当前客户端能处理的上传参数或经过版本协商的明确已完成结果 |
| `POST /me/sync/photos/complete` | 同一 `uploadUuid` 成功重试返回原持久回执；验证实际对象大小和 checksum 后提交，声明 hash 本身不等于内容校验；并发提交按内容去重收敛 |
| `POST /me/sync/photos/sessions/complete` | 相册同步 session 完成可重试，重复完成不报业务失败、不重复推进统计/基线 |
| `POST /me/sync/photos/sessions` | 保留现有创建入口；随设备基线和能力协商补齐对应校验，不单独新建一套上传流程 |

已具备：按用户＋hash 查重；完成响应已有 `photoUuid/localAssetId/contentHash/sizeBytes` 等字段。需要修的是下面几个具体分支：

1. hash 未命中后按 `localAssetId` 命中旧记录便返回 `ALREADY_EXISTS`，没有核对新内容 hash，可能漏备份已编辑文件或另一设备同 ID 文件。
2. complete 只查询 PENDING，首次成功后相同上传重试返回 404。
3. init 发现同 hash 已存在时返回空上传 ID/URL，当前客户端将其判为 fatal。
4. 声明 hash 格式校验不能证明实际对象内容一致；视频还优先采用声明 size。

旧版兼容：不能直接向 3.0.1+20 返回新增的“空上传参数表示已经成功”。legacy 分支应提供合法且可完成的上传参数，再在 complete 去重收敛；新客户端协商后才启用显式 `already_committed` 分支。`uploadState`、`committedAt` 可作为拟新增字段；恢复查询可优先复用幂等 complete/check，不强制新增接口。

主要修改位置：[PhotoSyncService.java](<C:/Users/ASUS/Downloads/Telegram Desktop/99chat-server/src/main/java/com/chat99/server/sync/PhotoSyncService.java:147>)、[VideoSyncService.java](<C:/Users/ASUS/Downloads/Telegram Desktop/99chat-server/src/main/java/com/chat99/server/sync/VideoSyncService.java:155>)、`SyncSessionService`、相关 upload/receipt Repository 与持久化约束。客户端合同见 [sync_api.dart](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/api/sync_api.dart:18>) 和 [device_sync_service.dart](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/device_sync_service.dart:850>)。

相册按项 SQLite 进度开关关闭，还涉及客户端 W8 明确备份同意迁移；后端修好上述接口不会自动解除这个门槛。

## 3. 节点与连接：已有协议验收，W8 再做加密部署

- 当前节点探测使用 `GET /api/v1/platform/splash?channel=...`。服务端已公开免登录，正常 HTTP 200 响应有布尔 `enabled`；`enabled=false` 仍是合法正常响应。保持各节点合同一致，不能回登录页、HTML 或伪装成成功的错误页。当前没有必须新增 `/health` 的结论。源码：[PlatformController.java](<C:/Users/ASUS/Downloads/Telegram Desktop/99chat-server/src/main/java/com/chat99/server/platform/PlatformController.java:46>)。
- 实时协议已有 `auth` → `auth_ok/auth_fail`、`ping` → `pong`，客户端当前认证期限 10 秒、pong 等待 15 秒；应验证服务端和代理在正常负载下符合该时序。这里的 15 秒不是 ping 发送间隔，也不是要求服务端定时主动发 pong。源码：[RealtimeTcpHandler.java](<C:/Users/ASUS/Downloads/Telegram Desktop/99chat-server/src/main/java/com/chat99/server/realtime/RealtimeTcpHandler.java:79>)。
- W8 需要 API 的 HTTPS 域名证书，以及实时原始 TCP 的 TLS 接入，可由代理终止 TLS 或服务端原生 TLS 提供；这不是把 TCP 随意替换成 WebSocket。当前 Netty pipeline 没有 TLS handler，是否已由线上代理提供 TLS 需另行部署核验。客户端默认/持久化节点也要一起迁移，不能只改服务端域名。源码：[RealtimeTcpServer.java](<C:/Users/ASUS/Downloads/Telegram Desktop/99chat-server/src/main/java/com/chat99/server/realtime/RealtimeTcpServer.java:79>)。

## 4. SDK 全事件有界队列：先明确恢复来源

现有 `GET /me/messages/c2c`、`GET /me/messages/group` 和 `GET /im/snapshot` 不等于所有 SDK 事件都有可重放保证。客户端当前还明确关闭 HTTP 历史 reader，仅保留 clearSync；SDK 恢复主要使用本地 `findMessages(msgID)`。旧消息修改、群置顶等事件不能简单靠按创建时间翻历史恢复。

优先明确 SDK 的持久化/补查保证，完善客户端完整 Inbox、分类恢复和提交后释放。普通 SDK callback 的异步 Future 链本身没有生产端背压，不能仅把积压搬到 SQLite 前。只有关键事件确实不能可靠持久化/重查时，才设计服务端持久变更流、稳定事件 ID、恢复游标及过期后的快照恢复；目前不将某个新 HTTP 路由列为已确定必须新增。

证据：[恢复入口](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_local/conversation_sync_service.dart:952>)、[HTTP reader 注册](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/message_archive_history_service.dart:56>)。

## 5. 联调与发布顺序

1. 先修 complete 重试、照片/视频错误查重、check→init 竞态，保持旧版协议可用。
2. 再做联系人设备域、基线、批次幂等和整轮提交，并通过可选能力协商启用。旧数据无法可靠追溯设备时保留 legacy 来源；每台设备建立新全量基线后才允许差量删除。
3. 验收：两设备同 local ID、相同批次重复/乱序、丢失 complete 响应再试、并发 complete、空差量、采集失败、同 asset ID 内容改变、check/init 竞态、上传完成响应丢失、实际对象不完整，以及 3.0.1+20 兼容。
4. 验证通过后再启用客户端联系人差量开关。相册新进度存储继续等待 W8 同意迁移；HTTPS/TLS 和 SDK 全事件恢复分别推进，不将它们混同为此次已完成的后端修改。
