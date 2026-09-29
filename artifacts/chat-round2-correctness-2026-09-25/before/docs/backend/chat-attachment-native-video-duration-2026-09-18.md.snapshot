# 后端待办：自建大附件链路视频消息时长丢失（气泡显示 0:01）

- 日期：2026-09-18
- 影响范围：`/me/chat` 大附件链路（`kind = video`），服务端代发的原生 `TIMVideoFileElem`
- 严重程度：中（功能可用，但所有接收方与发送方本人看到的视频时长恒为 `0:01`）
- 客户端协议版本：`X-Chat-Attachment-Protocol-Version: 1`

---

## 1. 现象

超过分流阈值（`min(routingThresholdBytes, nativeMaxBytes.video)`，默认 100 MiB）的视频走自建大附件链路。发送成功后，聊天气泡左下角时长文字显示 `0:01`，实际视频时长为数十秒到数分钟。

客户端气泡渲染逻辑（`third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_video_card.dart`）：

- `videoElem.duration == null || <= 0` → 显示 `视频`
- `videoElem.duration == 1` → 显示 `0:01`

因此 `0:01` 说明服务端下发的 `TIMVideoFileElem.VideoSecond == 1`。

## 2. 根因

自建链路的视频消息由后端调用腾讯 IM REST 接口代发，客户端全程**没有把视频时长传给后端**，后端只能填占位值。

### 2.1 客户端当前发送给后端的字段

`POST /me/chat/uploads`（`lib/src/services/chat_attachment_transfer.dart:65-73`）：

```json
{
  "clientUploadKey": "<taskId>",
  "conversationType": "c2c | group",
  "peerUserId": "<id>",         // 或 "groupId"
  "kind": "video",
  "nativeMessageKind": "video",
  "originalName": "xxx.mp4",
  "mimeType": "video/mp4",
  "declaredSizeBytes": 123456789
}
```

`POST /me/chat/uploads/{uploadId}/complete`：body `{}`
`POST /me/chat/uploads/{uploadId}/thumbnail-complete`：body `{}`

`POST /me/chat/native-video-messages`（`lib/src/api/chat_attachment_api.dart:161-175`）：

```json
{
  "clientOperationId": "<taskId>",
  "attachmentId": "<id>",
  "referenceId": "<id>",
  "conversationType": "c2c | group",
  "peerUserId": "<id>"          // 或 "groupId"
}
```

以上任何一个请求都**没有** `durationMs`、`width`、`height`。

### 2.2 客户端本地其实持有时长

`ChatAttachmentTask.durationMs`（`lib/src/models/chat_attachment_task.dart`）在 `ChatAttachmentService.start()` 时已写入，仅用于本地上传中的临时气泡，未上传。

### 2.3 客户端探测也可能失败

客户端用 `VideoPlayerController` 限时 2 秒探测时长，大文件超时返回 0 → 传 `null`。所以后端**不能假定客户端一定会给时长**，需要有服务端兜底。

## 3. 目标

1. 服务端代发的 `TIMVideoFileElem.VideoSecond` 为真实时长（秒，向上取整，`>= 1`）。
2. 客户端未提供时长时，服务端自行从已上传文件中探测。
3. 同步补齐 `ThumbWidth` / `ThumbHeight` / `VideoFormat` / `VideoSize`，避免同类元数据缺失。
4. 保持协议版本 `1` 向后兼容：旧客户端不传新字段仍可正常发送。

## 4. 接口变更

### 4.1 `POST /me/chat/uploads` 新增可选字段

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `durationMs` | integer | 否 | 视频/音频时长，毫秒，`> 0` 才有效。客户端探测失败时不传或传 `null`。 |
| `width` | integer | 否 | 视频画面宽度像素，`> 0` 才有效。 |
| `height` | integer | 否 | 视频画面高度像素，`> 0` 才有效。 |

校验规则：

- 非正整数、非数字 → 视为未提供，不报错（客户端可能传 `null`）。
- `durationMs` 上限建议 `24 * 3600 * 1000`，超出视为未提供并记录告警日志。
- 字段与 `uploadId` 绑定持久化到附件元数据，`kind != video/audio` 时忽略 `durationMs`。

### 4.2 `POST /me/chat/native-video-messages` 新增可选字段

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `durationMs` | integer | 否 | 同上。用于客户端在上传初始化之后才拿到时长的场景（覆盖 `uploads` 阶段的值）。 |

取值优先级：`native-video-messages.durationMs` > `uploads.durationMs` > 服务端探测值 > 兜底值。

### 4.3 `GET /me/chat/attachments/{attachmentId}` 响应新增字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `durationMs` | integer \| null | 最终生效的时长（毫秒），来源见 4.4。 |
| `width` | integer \| null | 最终生效宽度。 |
| `height` | integer \| null | 最终生效高度。 |
| `mediaProbe` | object \| null | 可选调试信息：`{"source": "client" \| "server" \| "fallback", "probedAt": "<ISO8601>"}` |

客户端当前只读 `status`、`sizeBytes`、`attachmentId`，新增字段不会破坏兼容。

### 4.4 服务端探测（兜底）

在 `POST /uploads/{uploadId}/complete` 合并分片成功后（或在 `native-video-messages` 处理前），若 `durationMs` 未提供：

1. 用 ffprobe（或等价工具）读取对象存储中的文件：`ffprobe -v error -show_entries format=duration:stream=width,height,codec_name -of json <url>`。
2. 仅需读取文件头部/尾部的 moov box，建议使用 Range 读取或流式探测，不要整文件下载。
3. 探测超时建议 10 秒；失败则进入兜底值，不阻塞消息发送。
4. 探测结果写回附件元数据（`durationMs`、`width`、`height`、`videoFormat`）。

### 4.5 `TIMVideoFileElem` 填充规则

| REST 字段 | 取值 |
| --- | --- |
| `VideoSecond` | `ceil(durationMs / 1000)`；`durationMs` 缺失时用兜底值（见下） |
| `VideoSize` | 附件真实字节数（已有） |
| `VideoFormat` | 文件扩展名（`mp4`/`mov`/`mkv`），来自 `originalName` 或探测的容器类型 |
| `ThumbWidth` / `ThumbHeight` | 缩略图真实像素尺寸（从上传的缩略图读取） |
| `ThumbSize` / `ThumbFormat` | 缩略图真实大小与格式 |

**兜底值**：所有来源都拿不到时长时，`VideoSecond` 填 `0`，不要填 `1`。客户端对 `0` 显示 `视频`（中性文案），对 `1` 会显示 `0:01`（错误信息）。

> 若腾讯 REST 接口拒绝 `VideoSecond = 0`，请在此文档记录实测结果并改为：仍填 `1`，同时在 `CloudCustomData` 中写入 `{"chatAttachment":{"durationUnknown":true}}`，客户端据此显示 `视频`。此分支需要客户端配合，请先确认 REST 行为再决定。

## 5. 数据与存储

- 附件表新增列：`duration_ms BIGINT NULL`、`width INT NULL`、`height INT NULL`、`media_probe_source VARCHAR(16) NULL`、`media_probed_at TIMESTAMP NULL`。
- 已存在的历史附件不回填；如需修复历史消息，另开任务（涉及腾讯 IM 消息修改接口，成本高）。

## 6. 兼容性

- 旧客户端（不传新字段）：走 4.4 服务端探测 → 兜底，行为优于现状。
- 新客户端 + 旧后端：新增字段被忽略，行为与现状一致，不报错。后端需确认网关/参数校验层对未知字段是**忽略**而不是 400。
- 协议版本头保持 `1`，不新增版本号。

## 7. 待办清单

后端：

1. [ ] `POST /uploads` 接收并持久化 `durationMs` / `width` / `height`（可选字段，宽松校验）。
2. [ ] `POST /native-video-messages` 接收可选 `durationMs`，优先级高于 `uploads` 阶段的值。
3. [ ] `complete` 成功后对 `kind = video` 且无 `durationMs` 的附件执行服务端探测（ffprobe，Range/流式读取，10 秒超时）。
4. [ ] 代发 `TIMVideoFileElem` 时按 4.5 填充 `VideoSecond` / `VideoFormat` / `ThumbWidth` / `ThumbHeight` / `ThumbSize` / `ThumbFormat`。
5. [ ] 兜底值由 `1` 改为 `0`；实测腾讯 REST 对 `VideoSecond = 0` 的接受情况并记录在本文档。
6. [ ] `GET /attachments/{id}` 响应新增 `durationMs` / `width` / `height` / `mediaProbe`。
7. [ ] 附件表加列与迁移脚本。
8. [ ] 确认参数校验层对未知字段为忽略策略。
9. [ ] 监控：新增指标 `native_video_duration_source{client|server|fallback}` 计数，`fallback` 比例作为告警项。

客户端（另开任务，此处仅记录接口依赖）：

1. [x] `chat_attachment_transfer.dart` 的 `initUpload` body 附带 `durationMs` / `width` / `height`（取自 `ChatAttachmentTask`）。
2. [x] `chat_attachment_api.dart#sendNativeVideo` 附带 `durationMs`。
3. [ ] 时长探测策略调整（放宽 2 秒超时 / 与上传并行 / 系统选择器补相册元数据回退）。

## 8. 验收标准

1. 使用新客户端发送一段 2 分钟、大于分流阈值的 mp4：接收方与发送方气泡均显示 `2:00`（或按实际秒数向上取整）。
2. 使用旧客户端（或抓包移除 `durationMs`）发送同一文件：气泡显示真实时长（来自服务端探测）。
3. 人为让服务端探测失败（如上传损坏的 moov）：气泡显示 `视频`，不显示 `0:01`。
4. `GET /attachments/{id}` 返回的 `durationMs` 与 ffprobe 结果误差在 1 秒内。
5. `native_video_duration_source` 指标三种来源均有采样，`fallback` 比例在灰度期内低于 5%。

## 9. 相关代码位置（客户端）

| 位置 | 说明 |
| --- | --- |
| `lib/src/services/chat_attachment_transfer.dart:65-73` | `initUpload` 请求体（待补字段） |
| `lib/src/api/chat_attachment_api.dart:161-175` | `sendNativeVideo` 请求体（待补字段） |
| `lib/src/services/chat_attachment_service_io.dart:394-403` | 视频任务强制走 `sendNativeVideo` |
| `lib/src/services/chat_attachment_service_io.dart:779-781` | 视频禁止走客户端自定义消息 |
| `lib/src/models/chat_attachment_task.dart` | `durationMs` 本地持有位置 |
| `third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_video_card.dart:25-29` | 时长文字渲染规则 |
| `third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_more_panel.dart:1409-1428` | 客户端 2 秒时长探测 |
