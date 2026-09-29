**聊天首轮修改证据包：A + B**

已按要求补齐当前工作树中的首屏调用/等待关系，以及 F1/F2 方法、调用方和状态结构。当前可以确定第一轮修改层次；仍没有足以决定窗口、缓存和并发数值的真机数据。

- [A：首屏链路、等待与日志缺口](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-evidence-ab-2026-09-25/A-first-screen.md>)
- [B：草稿与发送仲裁、具体修改点](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-evidence-ab-2026-09-25/B-draft-send.md>)
- [A 完整源码正文](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-evidence-ab-2026-09-25/A-source-complete.md>)
- [B 完整源码正文](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-evidence-ab-2026-09-25/B-source-complete.md>)
- [源码位置与哈希清单](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-evidence-ab-2026-09-25/source-manifest.json>)
- [逐行 await/定时器索引](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-evidence-ab-2026-09-25/A-await-timer-inventory.csv>)
- [原始日志检索清单](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-evidence-ab-2026-09-25/raw-log-inventory.json>)
- [本轮定向测试结果](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-evidence-ab-2026-09-25/focused-tests-summary.json>)
- [证据一致性检查](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-evidence-ab-2026-09-25/evidence-integrity.json>)

范围：38 个相关源码文件、126 份完整方法/类型/小文件摘录。大文件使用 Dart AST 精确边界，完整闭包保留；原文提取时不保留 UTF-8 BOM，原文件哈希仍按原始字节计算。每份摘录保留原路径和起止行号。

基线：分支 codex/gallery-chat-order，HEAD 26bcc02c68680725c1a91bf7548535c0645687a0，包含工作树原有未提交改动。[与上一轮 10 个关键文件的比较](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/artifacts/chat-evidence-ab-2026-09-25/previous-audit-comparison.json>)全部一致。本包提取后也再次校验了 38 个文件，未发生内容漂移。

本轮补跑 47 项定向测试全部通过。F1/F2 上轮反例仍未修复：它们证明的是更高层的异步时序缺口，不能被既有服务测试通过替代。

原始性能样本：缺失。在 artifacts/test_outputs 检索到的是测试输出或源码快照，没有可用于真实设备 Profile 对比的完整打开链路。本包没有生成估算 p50/p95，也没有把测试耗时当成产品性能。

第一轮修改点已经收敛：

1. F1：输入提交快照 → 页面草稿版本 → ConversationDraftService 条件写入，全程保留原账号和会话身份。
2. F2：现有 Im05Persistence 事务返回明确终态 verdict → coordinator → UI/重试统一消费，并携带发送尝试与投影版本。
3. 测量：复用现有打开账本，补统一入口、Profile 采集、排队/执行/投影分段与脱敏；暂不调整窗口、缓存或并发。

保持首屏消息正确连续、中间历史上拉加载、阅读历史不抢位置。此次交付为源码证据与可执行修改契约，没有修改业务实现或提交 Git。

