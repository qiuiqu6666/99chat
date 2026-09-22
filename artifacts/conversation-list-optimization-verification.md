# 会话列表三项优化验收记录

日期：2026-09-22。对照提交：`c5008765a84faf765b8f6b47bd7c878980ad71e7`。

## 本次实现

1. SDK 会话回调按会话合并，在固定 48 ms 窗口内集中生成行数据、排序、更新索引并通知。连续回调不会无限推迟发布。同步读取、已读、删除、置顶、滚动结束和聊天返回会先处理待发布更新；退出账号直接丢弃旧队列。分页与 ByIDs 恢复保留回调的先后关系，防止较旧结果覆盖新消息。
2. 摘要缓存保存不可变的消息内容指纹，覆盖文字、自定义消息、附件及撤回者信息。消息 ID、时间和状态不变、SDK 原地修改对象时，也能识别变化并更新行。
3. 删除两个已直接返回的旧水合入口及调用点，修正已不适用的 SQLite 主数据源注释。

本次代码范围：

- `lib/src/services/conversation_local/conversation_tab_store.dart`
- `lib/src/chat_session/chat_session_controller.dart`
- `lib/src/conversation.dart`
- `lib/src/services/conversation_local/conversation_row_view.dart`
- `lib/src/utils/conversation_preview_fingerprint.dart`
- `test/conversation_realtime_batch_test.dart`
- `test/conversation_preview_content_invalidation_test.dart`

## 验证结果

- 新增 16 项测试全部通过：13 项批处理与时序边界、3 项内容指纹与行失效。
- 突发场景测试中，100 次同会话 SDK 更新收敛为 1 次行投影、1 次完整排序、1 次结构通知；最终未读数与排序保持正确。
- 20 个相关测试文件合计 174 项通过、5 项失败。使用 `--no-pub --concurrency=1` 避免共享 SQLite 测试相互争用。
- 5 项失败已在独立临时目录中的原始提交复现，测试名称和错误一致：4 项旧结构索引测试预期保留 1000/2000 行，与已有 600 行窗口上限冲突；1 项业务投影测试缺少 `shared_preferences` 插件 mock。
- 对本次 7 个文件静态分析无错误，保留 28 项已有 warning/info。
- 本次 7 个代码和测试文件的 `git diff c500876 HEAD --check` 通过。

日志：

- [最终相关回归](conv-opt-regression-final.log)
- [原始提交失败对照](conv-opt-original-regression.log)
- [静态分析](conv-opt-analyze-final.log)
- [批处理修复前失败](conv-opt-batch-baseline.log)
- [摘要失效修复前失败](conv-opt-preview-baseline.log)
- [账号解绑边界修复前失败](conv-opt-unsubscribe-baseline.log)

## 验证边界

上述次数来自自动化测试中的工作量计数，尚未进行真机帧耗时、CPU 或功耗采样，不能据此宣称对应倍数的运行速度提升。其他任务修改的图片预览、设置页面文件不属于本次实现。最终检查期间，共享工作区产生提交 `6881b96`，已包含本次代码与测试；本任务未执行提交或推送命令。

## GitNexus 最终校验

- 为避开另一任务占用的共享索引，建立独立索引 `.gitnexus/conv-opt-verification`。CLI 1.6.12、runner receipt schema 4，`runnerIdentityStatus=current`，`incompleteReasons=[]`。
- 索引构建期间 HEAD 从 `c500876` 更新为 `6881b96`；[内容哈希核对](conv-opt-final-source-check.json)确认本次 7 个文件均与索引内内容完全一致。
- `detect-changes --scope all` 时代码已由另一任务提交，因此随后以 `c500876` 为基准执行 compare 检测。完整结构化结果见 [图谱变更报告](conv-opt-graph-final.json)：整个共享提交涉及 146 个文件、161 个符号，返回 161 个符号，未设置 `partial` 或 `truncated`。
- 图谱的全局执行流程枚举受预算限制，且部分 Dart 动态调用不可解析；本次报告中的 0 个受影响流程不代表没有调用影响，也不替代修改前对共享 Store 的 CRITICAL 风险判断。已结合实际调用点与上述回归测试验证首屏、分页、已读、置顶、滚动、聊天返回和账号清理路径。
- [索引版本记录](conv-opt-index-receipt.json)。关闭全文检索构建只影响关键词检索，最终检测使用符号与关系图。
