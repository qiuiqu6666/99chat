# A05 / A06 / A10 当前代码复核

日期：2026-09-28。用户要求复核并合并排查结论；未修改业务源码。

## A05：成立，重复调用已动态验证，网络成本未测

当前调用链：`lib/src/pages/app.dart:186-205` 回前台节流后调用 `LoginCoordinator.recoverOnForeground`；`lib/src/services/login_coordinator.dart:776` 无条件调用 SessionManager.restore；`lib/src/session/session_manager.dart:93-103` 只合并在途恢复，不跳过已经 ready 的会话。

缓存凭证分支 `session_manager.dart:158` 验证业务账号，`:182` 执行 `_im.connect`；成功后 `:201` 启动凭证刷新，`:308-319` 刷新成功且 ready 时再次 `_im.connect`。`lib/src/session/im_client.dart:39` 直接调用 SDK.login。

诊断用真实 SessionManager 与可计数的 I/O 替身：第一次缓存恢复后 connectCalls=2；已经 ready 再 restore 后总计 connectCalls=4、fetchMe=2、fetchCredential=2。

**保留边界**：没有声称每次系统生命周期回调都会通过 App 的 3 秒节流；没有声称腾讯 SDK 每次 login 调用都会建立一条新连接。确认的是客户端的重复初始化/鉴权/登录调用，实际网络耗时与帧率贡献尚未测量。

建议在合并报告中列为“性能放大项，调用已证实”。修复需区分冷启动、短暂前后台、断线和凭证到期，同时保留业务鉴权、踢下线和账号归属检查。

## A06：成立，两个重连登录并发已动态复现

`session_manager.dart:355-360` 的 `_reconnect` 只检查 `_activeOperation`，自己没有占用它；`:369-376` 定时器触发时先清 `_retryTimer`，然后启动 `_reconnect`。第二个断线事件可以安排下一个重试；同一个 sessionGeneration 无法排除同代次竞争任务。

诊断先建立正常会话，再让重连的 ImClient.connect 保持 pending：第一条断线在 2 秒后进入 connect；它尚未完成时再次触发断线，再推进 5 秒，得到 **两个同时 pending 的重连 connect**。随后释放两者以完整结束测试。

**保留边界**：这证明现有客户端会发出竞争尝试，并不是已证明服务端收到两次不同连接，也不是已测线上发生率。现有冷恢复的 single-flight 保护仍存在，缺口发生在定时重连自己未登记所有权。

建议归入最高优先级稳定性修复，统一登记恢复/重连任务所有者，按任务实例与连接代次提交/释放，验证旧错误不能覆盖新成功。

## A10：成立，与上一轮启动发现合并，不重复计数

`lib/main.dart:355-368` 在 runApp 前等待节点、读屏障、API与启动图；`:418-440` 等待本地设置、代理入口预热、游戏/浮窗偏好和通知处理；`:475-481` 原生分支等待 finishDeferredBootstrap 及 Android 性能档位后才 runApp。

上一轮 `startup_fault_repro_test.dart` 已对真实 ApiClient.bootstrap 验证安全存储异常会向外抛出、读取 pending 会持续等待。本轮核对这些源码 SHA256 与上一轮一致，未为相同机制重复计数或把多项本地读取分别断言成耗时瓶颈。

启动耗时需要分别测 native splash、Flutter 首帧和数据可用；该项解释启动停滞风险，不能直接解释进入聊天后的所有白屏。

## 验证

命令：`flutter test --no-pub artifacts/cross-module-report-verification-2026-09-28/session/session_verification_test.dart --reporter expanded`

结果：**2/2 诊断断言通过**，用于复现当前问题，不代表修复完成。输出见同目录 `session-verification.log`。全部使用假接口和虚拟时钟，没有访问线上服务或真实账号。

图优先定位使用当前工作区外置 GitNexus 索引；`_restoreInternal`、`_reconnect`、`recoverOnForeground` 结果保存在同目录 graph 文件。源文件核实为当前版本，SessionManager/app 的最后修改时间均在该索引之前。

语义注意：增加 `Future.timeout` 只结束外部等待，原任务仍可继续完成，所以不能将其当成取消 SDK 登录的方法。依据：[Dart Future.timeout](https://api.dart.dev/dart-async/Future/timeout.html)。
