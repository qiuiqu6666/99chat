# 同步合同前端接入（2026-09-28）

## 范围与状态

已按用户提供的上线合同接入 Flutter 客户端。联系人差量生产开关 `ContactSyncPlan.deviceScopedDeltaEnabled` 仍为 `false`；照片进度开关 `PhotoBackupProgressStore.enabled` 仍为 `false`。没有修改其他任务的工作、提交代码、打包或发布安装包。

合同来源：用户附件 `b0348f92-7a04-4451-aec3-ba8242509fbe/已粘贴的文本.txt`，SHA-256：`69E7B102296BE43B946C093339BA209B1D913520D8A9443B771D4E0138461D68`。后端称上线代码尚未提交，不能将后端 HEAD 当作这份合同的部署证明。

## 接入内容

- 状态查询带 `deviceId`，解析设备联系人基线、`contactsDeltaV2` 和视频状态。联系人字段改为合同要求的 Unix 秒 `updatedAt`。
- 新增联系人事务执行器：固定批次内容、UUID 批次标识及规范 JSON 的 SHA-256；临时故障原样重放；所有批次逐项确认后才提交完成请求；只有有效完成回执才能更新本地基线。
- 基线按账号和设备隔离保存，退出账号时清除。修订冲突或要求全量时重新查询状态，并最多建立一次新的 FULL 会话，禁止只把旧差量套上新版本号。批次冲突和缺失确认停止提交。
- 生产开关关闭时继续原有联系人请求，不发送 V2 批次字段；后端能力声明不会自动开启差量。
- 照片和视频共用上传执行器，初始化显式声明 `acceptAlreadyCommitted=true`。已有内容回执校验内容 hash、大小及返回的媒体类型，允许合同中的空上传参数；已有内容不再上传。
- 完成响应丢失时重试同一 `uploadUuid`，不重复 PUT。对象不存在或内容不匹配时，最多重新初始化和上传一次；失败不记成功。旧版初始化响应仍兼容。
- `DEVICE_NOT_BOUND` 停止当前身份的后续同步。请求前后检查账号有效性；媒体上传还检查取消状态和服务侧运行条件。中断的相册扫描、尚未清空的选图队列不提交整轮完成。

## 文件

生产：`lib/src/api/sync_api.dart`、`sync_contract_support.dart`；`lib/src/services/device_sync_service.dart`、`contact_sync_transaction.dart`、`contact_sync_baseline_store.dart`、`photo_sync_transfer.dart`。`contact_sync_plan.dart` 只更新开关说明。

测试：`test/sync_contract_api_test.dart`、`contact_sync_contract_test.dart`、`photo_sync_contract_test.dart`、`sync_contract_service_test.dart`、`support/sync_contract_harness.dart`。

## 验证

- 变更前 API 回归确认两个实际问题：状态请求没有设备参数、联系人时间字段不符合合同。
- 最终针对性回归 **40 项通过**：以上新合同测试以及 `stability_device_sync_test.dart`、`stability_data_capabilities_test.dart`、`device_sync_lifecycle_guard_contract_test.dart`。
- 扩展运行选图测试时，合计 41 项通过、1 项失败；失败用例 `permission alone does not enable album backup` 缺少权限插件方法模拟，抛出 `MissingPluginException`。本轮没有修改该测试或权限模块，也不宣称全项目测试通过。
- 改动生产文件和合同测试的定向静态分析没有错误或警告，有 16 条花括号风格提示；新增真实服务测试静态分析无问题。相关已跟踪文件 `git diff --check` 通过。
- GitNexus 修改前检查发现 `DeviceSyncService` 为 CRITICAL（13 个直接调用方），上传初始化模型为 HIGH，已在编辑前提示并覆盖现有同步服务回归。图谱不能代替动态调用、插件和平台验证。
- 最终重新建图成功，状态为 `up-to-date`。`detect_changes(scope: all)` 返回 104 个已跟踪变更文件、520 个符号、8 条流程，风险 HIGH，结果未标记 partial/truncated。这是包含其他并行任务的整个工作区结果，涉及网络探测、鉴权和连接流程，不能解释为本轮新增 104 个文件或整个工作区可直接发布。未跟踪新增文件不计入 Git diff，另由本轮文件清单与测试覆盖。

## 尚未验证

未对线上接口写入测试联系人或媒体，未进行安卓/iOS 真机验收。后端重复完成、设备隔离、并发去重和旧客户端兼容的端到端验收仍需完成；联系人差量开关因此保持关闭。此报告仅说明同步合同接入，不表示整个 W0–W7 或全部性能问题已经验收。

本轮日志、编辑前快照和图谱证据保存在 `D:/codex-task-cache/99chat-sync-contract-20260928/`；同目录的 `tested-files.json` 用于限定本轮验证文件版本，避免把并行任务的变化混入结论。
