# 执行结果记录

日期：2026-09-28。Flutter：`E:\flutter\flutter\bin\flutter.bat`。每项命令使用 `test --no-pub <path> --reporter expanded`。

这是已观察执行结果的人工记录，非重新生成的原始终端日志。设备同步的原始重定向日志另存 `device-sync-repro.log`。

| 文件 | 实际通过数 | 最终结果 |
| --- | ---: | --- |
| relationship_lifecycle_repro_test.dart | 3 | All tests passed |
| sqflite_close_gate_repro_test.dart | 1 | All tests passed |
| device_sync_repro_test.dart | 4 | All tests passed |
| 总计 | 8 | 全部最终执行通过 |

用例名：

1. A07 production idle predicate is bypassed after deadline
2. A08 late old success suppresses the new session job
3. A08 late old error suppresses the new session job
4. A09 paused native close stalls resume and write gate until it actually completes
5. A17 authorized callback enables previously unset backup
6. A17 limited callback enables previously unset backup
7. A11 unchanged 101-contact directory is uploaded again in INCREMENTAL mode
8. A12 oversized video metadata does not stop prepareOne from hashing

SQLite 测试会输出 sqflite 更换 default factory 的提醒，这是故障注入的测试配置，并非产品运行错误。初次测试工具适配过程中存在编译/工厂配置错误（自定义 factory 需要实现 sqflite 内部 factory 接口；AssetEntity 的 file getter 与测试字段名冲突）；仅修正本目录测试代码后最终通过。没有据初始失败判定产品缺陷。

关系调度使用现有 forTest 构造器和真实 directory，A07 保留真实活跃聊天 predicate，仅缩短可配置截止时间。SQLite 使用真实 Host/Store/Guard、受控 Database.close。设备同步使用真实 DeviceSyncService/PhotoBackupConsent/PhotoSyncCollector，替换平台通道与 HTTP 响应。所有数据为合成数据，无外部上传。
