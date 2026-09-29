# 好友关系同步实现（2026-09-23）

此实现已对照 99chat-server 仓库，替代先前未取得后端源码时的协议提案。后端已经具备 itemVersion、删除墓碑语义、快照接口和持久变更日志，本次复用这些机制；保留后端双向删除业务语义。

## 权威与写入入口

- 权威关系：后端 user_friend；权威增量：friend_contact_change。
- 客户端关系表：contacts.db 的 friends；内存目录、UIKit 和选人列表是该表的投影。
- ContactsProtocolSyncService 串行处理全量/增量。HTTP 修改成功、TCP 推送、SDK 回调、成友消息只触发同步，不直接创建/删除本地关系。
- 无版本 relation 查询只服务权限判断，不能创建好友行。关系缓存按账号隔离；失效前发出的请求不能重新填充缓存。
- 旧事件由 itemVersion、eventId 和删除墓碑过滤。完整快照移除不在服务器名单中的旧行；数量不完整时保留原表。
- contacts.db v7 清除旧同步进度并重新全量核对，修复历史乐观写入导致的数据错误。升级时保留旧好友表以供离线显示。
- 同步中再次收到变更会追加一轮。前台每 30 秒、TCP 重新认证、回到前台均追赶日志。网络故障时保留最后确认的状态，随后重试。

## 配套后端改动

必须先发布后端对 `/sync/contacts/changes` 的 afterRevision 支持，再发布客户端。非空 cursor 优先；完整分页后用 toRevision 继续追赶。后端空页不能通过 MAX(revision) 确认未交付的事件。

没有引入新的服务端表、mutationId 或推送 outbox。实时路径是提交后通知触发 HTTP 拉取；丢通知由持久变更日志补偿，不承诺离线时实时同步。

## 验证范围与待办

回归覆盖删除/重加后的乱序事件、重复 eventId、全量清除旧好友、快照完整性、并发触发补拉、切账号旧响应、关系缓存失效、Web 内存快照以及目录/搜索等现有行为。

后端仓库缺失 `scripts/bootstrap/server-0.0.1-SNAPSHOT.jar`：已提供接口层独立测试入口 `scripts/contacts-contract-tests/pom.xml`。完整服务编译、MySQL 事务与双端联调仍需补齐该产物；当前改动未部署、未提交或推送。
