# 聊天上下翻页修复与验证

2026-09-27。分支：`codex/chat-scroll-load-recovery`。修复提交：`9c7b5d7232a5e93cd23f3eaca8934bae5c834c73`，基准：`c7e9caf4101c6571f60881f4212c9ff380273213`。

## 完成的修复

1. **云端补拉失败后仍可继续加载新消息。** 采用本地回退结果时，明确记录其本地来源。本地短页、空页及本地结束标记不再关闭云端补拉，也不再错误清除“较新消息缺失”状态。云端恢复后能够从已接受的消息继续拉取；真正的云端结束结果仍可正常结束加载。
2. **缓存整页被过滤后不会反复卡在同一页。** 接受缓存页后保留原始扫描位置，即使通话信令等记录全部被业务过滤，下一次翻页仍能继续。只有实际新增可见消息才返回列表增长，避免错误触发滚动补偿。缓存读完后的网络失败也保留重试入口；提交失败的页不会提前推进位置。

修改仅涉及一个生产文件 `tui_chat_history_pagination_load.dart` 和一个新增测试文件 `history_scroll_pagination_recovery_test.dart`。保留了账号/会话有效性、清空历史版本、删除、撤回、分页数量上限等既有检查。原有 `pubspec.yaml`、`pubspec.lock` 修改未纳入提交。

## 验证结果

| 验证 | 结果 | 原始记录 |
| --- | --- | --- |
| 新增 9 项回归用例，在修复前源码运行 | 2 通过、7 失败，证明用例能检出缺陷 | [修复前回归](pre-fix-regression.log) |
| 同一组用例在修复后运行 | 9 项全部通过 | [修复后回归](fix-regression.log) |
| 最后一轮相关测试：新用例、较早/较新分页、短列表手势、被过滤的 SDK 页、移动端滚动、快速拖动、清空历史重试 | **97 项全部通过** | [最终测试](final-targeted-tests.log) |
| 扩展到缓存存储及完整分页集成测试 | 初次 152 通过、2 失败，后续核对见下文 | [扩展测试](fix-existing-tests.log) |
| 一万条延迟消息记录压力测试单独复跑 | **通过，81 秒** | [独立压力测试](store-stress-isolated.log) |
| 同一独立包解析环境下比较修复前后静态诊断 | 均为 6 条相同的既有非空断言警告，无新增诊断 | [修复前](pre-fix-analysis.log)、[修复后](fixed-isolated-analysis.log) |

新增用例覆盖：云端报错/返回空时的本地短页、本地空页、显式本地读取、云端恢复、真实云端结束、较早/较新方向整页过滤、缓存未命中后的网络重试，以及业务过滤回调失败后的重试。

修复前验证使用独立复制的 UIKit 包，并通过 `--packages` 指向隔离的依赖配置，没有回滚工作区。复制的旧加载器与基准提交字节一致；修复后分析快照与工作区字节一致。

## 仍需明确的限制

- 扩展测试中的 `return latest success=true controls watermark ack and snapshot session renewal` 仍然失败：预期待处理记录数为 1，实际为 2。**使用基准提交的加载器时也出现相同失败**，未把它记为本次修复通过。[基准失败记录](pre-fix-existing-failure.log)、[修复后复跑](existing-failure-recheck.log)。该测试覆盖返回最新位置时的水位确认，未在本次两处分页修复中扩大修改。
- 扩展测试的一万条记录用例首次超时，之后在没有索引重建竞争的情况下单独复跑通过。未修改超时阈值或弱化断言。
- 直接分析工作区的 vendored `part` 文件曾报告两处 `ConversationHistorySyncCoordinator` 解析错误及已有警告，见 [原始分析记录](fix-analysis.log)。上表的静态对比使用相同的独立包解析配置，不能据此宣称全仓静态检查通过。
- 未取得故障手机的运行日志，也未打包、安装或进行安卓实机验证。代码中的两处可复现缺陷已修复，但不能确认它们是录屏现象的唯一原因。

## 代码影响检查

- 修改前 `_tryLoadHistoryWindowPage` 影响 1 个上游符号、`_commitHistoryWindowPage` 影响 2 个，均为 LOW。`loadChatRecord` 的回调绑定未被图解析，返回 UNKNOWN；另行核对了 `runner.loadChatRecord` 的绑定和界面调用，未将 UNKNOWN 当成无影响。
- 提交前完整重建索引，状态 `up-to-date`，内容一致，runner 身份为 `current`，`incompleteReasons=[]`。
- `detect-changes --scope all` 和 `--scope staged` 均完成，没有 partial/truncated 警告；暂存区为预期的 2 个文件、6 个映射符号，风险 low。生产改动映射到加载器类和缓存提交方法，另对三个实际修改方法逐项检查了差异。[全部变更检查](commit-all-changes.log)、[暂存检查](commit-staged-changes.log)。
- GitNexus 1.6.12，Node 20.19.3，runner receipt schema 4；完整身份记录保存在 [提交前索引状态](commit-index-status.log)。代码索引原缓存达到 16 GiB 上限后，使用独立目录完整重建；工具的流程枚举本身存在预算限制，没有将“未列出流程”等同于“没有调用”。
- 提交后再次刷新并核验：索引提交与当前 `9c7b5d7232a5e93cd23f3eaca8934bae5c834c73` 一致，`up-to-date`、内容 `current`、runner `current`、`incompleteReasons=[]`。[最终状态](post-commit-status.log)。最终 `scope=all` 仅剩原有两个依赖/版本文件修改，没有对应代码符号；与基准比较仍为上述 6 个映射符号、low，无 partial/truncated 警告。[最终工作区检查](post-commit-all-changes.log)、[基准比较](post-commit-compare.log)。
