# 会话列表后续优化验证

日期：2026-09-22
分支：codex/conversation-list-followup-optimizations
实现前基准：677641e932137c99042f5b06de645e2502f6b7ba（包含工作期间另一任务提交的图片修复）。

## 已实现

| 优化 | 最终行为 |
| --- | --- |
| 未读通知与文件夹统计 | 原始未读数实际变化才发布版本；按会话到文件夹的反向索引更新统计。成员变化、归档、账号切换和增量记录过期触发完整校准。SDK 每行版本屏障继续阻止旧分页覆盖新回调。 |
| 摘要投影 | 只按被观察行的 ID 查询；单次计算复用消息指纹。下一次计算仍按值重新捕获，支持同一消息对象内容修改和撤回。 |
| 筛选列表缓存 | 内容更新只替换受影响的可见行；无关更新复用原列表，保留旧快照。结构变化、增量缺失或超过 64 轮保留窗口时回退完整刷新；群 ID 别名转换为展示行实际保留的 ID。 |
| 首屏加载策略 | 默认首次请求统一为 30 条；显式指定数量优先，后续分页仍为 50 条。保留可见 Tab 优先、请求合并、失败重试和账号隔离。 |

额外修正了本次验证发现的两处发布顺序：内容增量在会话 ID 确定后发布；账号清理完成后再通知未读监听器。过期账号的文件夹异步结果直接丢弃。

## 验证结果

- 最终 32 个测试文件，**268 项全部通过**，约 65 秒，使用单并发避免共享 SQLite 测试相互干扰。
- 本次 13 个 Dart 文件静态分析：**0 errors、3 warnings、24 info**。27 条均位于既有代码；分析器因这些既有诊断返回 1，不等同于零诊断通过。
- 最初先复现：5 项定向用例中 4 项失败（重复未读通知、静音通知范围、默认首屏数量、显式首屏数量），1 项旧分页屏障通过。
- 页面用例验证了未选中文件夹成员变化、归档扣减、不可变快照、无关变化复用列表及错过 70 轮内容更新后的兜底。
- 账号清理顺序用例在修复前读到旧值 4，修复后读到 0。
- 群 ID 别名用例在增量路径启用后曾读到旧值 1，统一 ID 后读到最新值 3。
- 计算量断言：100 次相同未读快照不发布文件夹变更；5,000 行辅助模型中仅查询变化的可见行；摘要只查询观察 ID；50 个文件夹的单成员变化只读取该成员并更新其所属文件夹。
- 尚未进行真机帧率、内存或长时间收消息压测；以上计算量断言不能换算为实际 FPS 提升比例。

修复了三类既有测试问题：超出生产 600 行窗口的测试先建立真实保留窗口再测索引；业务投影用例补齐偏好与服务初始化；启动调度源码断言匹配已有的 identity 参数。保留原业务断言，没有放宽生产窗口限制。

## 可复现命令

```powershell
flutter test --no-pub --concurrency=1 test/conversation_followup_regression_test.dart test/conversation_incremental_projection_test.dart test/conversation_realtime_batch_test.dart test/conversation_preview_content_invalidation_test.dart test/conversation_projection_coalescing_test.dart test/conversation_sdk_live_feed_test.dart test/conversation_sdk_viewport_paging_test.dart test/sdk_tab_unread_source_test.dart test/conversation_tab_store_test.dart test/conversation_tab_structure_index_test.dart test/conversation_sdk_window_contiguous_restore_test.dart test/conversation_feed_settle_jump_contract_test.dart test/conversation_preview_monotonic_projection_test.dart test/conversation_preview_history_sync_test.dart test/conversation_revoked_preview_cache_test.dart test/conversation_preview_chat_source_test.dart test/conversation_preview_fingerprint_test.dart test/chat_pop_started_list_flush_test.dart test/archive_main_list_sync_test.dart test/conversation_feed_hidden_work_test.dart test/conversation_local_clear_notification_test.dart test/chat_session_business_projection_test.dart test/conversation_sdk_bootstrap_singleflight_test.dart test/conversation_folder_loading_test.dart test/conversation_folder_exclusive_membership_test.dart test/conversation_folder_reorder_test.dart test/folder_unread_refresh_gate_test.dart test/conversation_feed_source_order_test.dart test/conversation_sdk_window_policy_test.dart test/conversation_unread_aggregate_test.dart test/conversation_unread_aggregate_idempotent_test.dart test/home_bootstrap_scheduler_test.dart
```

本地日志：
- artifacts/conv-followup-final-tests.log
- artifacts/conv-followup-final-analyze.log
- artifacts/conv-followup-reset-before.log
- artifacts/conv-followup-final-graph.log（最终图谱与变更检查凭证）

## 图谱检查边界

按项目要求在修改前运行 impact。列表缓存入口为 CRITICAL、部分摘要和文件夹入口为 HIGH，已保留完整刷新、旧分页版本屏障、请求合并和账号校验。属性 setter、测试入口和部分动态调用返回 UNKNOWN，已逐处核对实际调用，未将 UNKNOWN 当作无影响。

分析器为 GitNexus 1.6.12 / Node v20.19.3，runner receipt schema 4。最终检查要求 status=up-to-date、runnerIdentityStatus=current、incompleteReasons=[]，并在提交前执行 all 和 staged 的 detect_changes。凭证保存到上述日志。

全局执行流枚举存在预算上限，动态派发也有静态解析限制，不能把零条受影响流程解释为没有影响。FTS 因既有索引问题关闭，符号与调用图查询可用。C 盘空间不足及旧数据库读句柄占用时，分析切换到 D 盘独立缓存；未修改其他任务的业务代码。
