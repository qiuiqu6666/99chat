# AI、隐藏钱包与默认明文传输复核

日期：2026-09-28。基于当前工作区，未修改产品源码或已有测试。针对用户提供的 17 项静态报告复核 A01 的 AI SSE 部分、A13、A14、A15、A17 的 HTTP/TCP 部分；其它部分由主报告合并。

先使用刷新后的 GitNexus 图定位 stream、_beginAssistantReply、WalletController、catalog、_connect、FriendRealtimeConnection，再核对现有源码。图存储为 `D:\codex-task-cache\program-performance-audit-full-20260928`，indexedAt 为 2026-09-27T17:57:41Z。保留 `graph-ai-reply.txt`、`graph-wallet.txt` 两份图证据。

## 结论矩阵

| 报告项 | 状态 | 当前证据 | 触发边界与准确表述 |
| --- | --- | --- | --- |
| A01 AI SSE 分块 UTF-8 | confirmed | 实际 AiAssistantApi 注入字节流：41 个单切分点中 7 个多字节内部边界失败、34 个通过 | 成功 SSE 响应中 UTF-8 字符横跨网络分块；ASCII 或恰好位于完整字符间的切分通过。并非所有中文请求必现 |
| A13-a 停止后 streaming 锁 | confirmed | 实际 AiAssistantPage：收到 delta 后停止，下一次发送未产生请求；首个 delta 前停止可重发的对照通过 | 至少收到一个 delta 且未收到 done 时停止。当前页保留的状态即可阻止重发；不声称重新进入页面必定恢复或必定继续锁定 |
| A13-b 旧上传错误覆盖新回答 | confirmed | 实际页面 + 实际 uploadFile：挂起旧 CSV 上传，停止并发起新回答，旧上传失败覆盖新 partial，replying 变 false | 旧上传缺 CancelToken，停止前未收到 delta 可再次发起；随后旧上传抛非 CANCELLED 的 AiAssistantException。并非所有旧流回调都缺隔离 |
| A14 delta 重建、强制滚动 | confirmed（行为） | 实际页面从旧消息 index 30 浏览位置，在下一 delta 后回到最新消息 index 0 | 未滚动跟随判定；页面级 setState、字符串累加、搜索重算由源码确认。没有测帧耗时，不能写成“每个 delta 对应一次独立重绘”或已测得掉帧率 |
| A15 隐藏钱包余额刷新 | confirmed | 实际 HomeTabStack 保留的 WalletController：隐藏后余额事件仍调用 getWallet；dispose 后不调用 | 已创建、尚未 dispose 且发生余额事件；未访问的钱包页不会因这个 controller 自动创建。是事件驱动刷新，非无条件永久轮询 |
| A17 默认 HTTP / TCP 明文 | confirmed（默认代码配置） | 实际 catalog / endpoint 解析测试：默认 API scheme=http；2/2 TCP 节点 useTls=false；HTTPS 对照为 true。调用源码确认 token 发送 | 无运行时安全覆盖、选中默认节点或任一内置 TCP 节点时。不是线上抓包、不是泄漏证据；Web release 同源及运行时/编译期覆盖需单独核验 |

本范围没有发现已修复项；原报告中若将以上问题扩写为所有请求必现、无限轮询、已证实泄漏或量化卡顿，这些扩写不受本次证据支持。

## A01：SSE 的网络字节被单块 UTF-8 解码

- `lib/src/api/ai_assistant_api.dart:436`：成功响应创建 SSE parser。
- `lib/src/api/ai_assistant_api.dart:441`：`parser.feed(utf8.decode(chunk), ...)`。每块独立解码，失去跨块的 UTF-8 续接状态。
- `lib/src/api/ai_assistant_api.dart:433`：非 SSE / 非 200 响应反而使用 `utf8.decoder.bind(payload.stream).join()`，该分支不会因同一种切分方式失去字符续接。
- `lib/src/api/ai_assistant_api.dart:461`：普通解码异常转成 `AiAssistantException('MAIN_UNAVAILABLE', ...)`，中断回答。

测试直接构造真实 AiAssistantApi，通过 Dio 注入 ResponseBody，把 `event: delta` 中的 `中文🙂` 在每一个可能的单字节边界拆成两块。41 个边界中 7 个内部续接字节边界均失败，其余 34 个均正常返回原文本。没有复制待测解码算法，也没有访问线上接口。

修复方向：先对整个网络 Stream 使用有状态 UTF-8 转换器，再把字符串块送进 SSE parser；补分块中文、emoji、连续多分块和 malformed UTF-8 策略测试。错误分支已有可参考做法。

## A13-a：停止后按钮恢复，但业务状态仍阻止重发

- `lib/src/pages/ai_assistant/ai_assistant_page.dart:1661`：delta 处理令最后消息 `status: 'streaming'`（1673）。
- 同文件 `1757`：停止取消 token，将 `_replying` 设 false。
- 同文件 `1773`–`1784`：已有文本只补时间，1782 仍复制 `last.status`。
- 同文件 `350`：`_hasStreamingHistory()` 查整个本地消息列表中的 streaming。
- 同文件 `1791`：发送时 `_replying || _hasStreamingHistory()` 直接拒绝；1793 提示 CHAT_BUSY。

实际页面测试输出：停止后 input bar.replying=false、助手消息 status=streaming，输入第二条内容后请求总数仍为 1、输入框保留第二条内容。对照测试在首个 delta 前停止，thinking 被移除，可以发起第 2 个请求。

附加源码边界：`1718`–`1728` 正常流结束但无 done 时，只有最后消息是 thinking 才置失败；已经有 partial 的 streaming 状态也会残留。这个 EOF 变体本次未另做动态测试。历史加载 `271` 也会根据 streaming 历史设置 replying，因此不能保证重新进页一定解除锁。

修复方向：停止 / 无 done 的 EOF 建立明确 terminal 状态，并同步 `_replying`；发送门禁只依赖当前活动请求或确实需要恢复的服务端任务，而不是永久保留的历史标记。

## A13-b：已停止的上传失败仍能改写新回答

- `lib/src/pages/ai_assistant/ai_assistant_page.dart:1604`：调用 uploadFile；1604–1609 无 token 参数。
- `lib/src/api/ai_assistant_api.dart:300` / `332`：uploadFile API 不接收 CancelToken，实际上传 post 未绑定流 token。
- 页面 `1626`：上传成功后有活动 token 判定，说明不是所有上传完成路径都不隔离。
- 页面 `1729`–`1743`：AiAssistantException 仅在“非活动 token 且 error.cancelled”时退出，旧 token 的其它异常继续把 replying 设 false，再调用 `_failLastAssistant`。
- 页面 `1558`：`_failLastAssistant` 操作当前列表最后一个助手消息，没有旧请求的 message ID 约束。
- 页面 `1745`–`1748`：一般 catch 则对所有非活动 token 退出，问题集中在类型化异常分支。

独立的实际页面测试通过系统附件回调注入合法 CSV bytes，挂起实际 uploadFile 的 Dio 请求，断言请求 cancelToken=null；点击停止后发送新文字并收到 `new partial`，再令旧上传抛 DioError。实际 uploadFile 将其转换为 AiAssistantException，旧 catch 将新回答改成 failed，且 input bar.replying=false。两个 A13 子问题均有各自动态复现，不是只验证其中之一。

修复方向：所有异步异常入口首先验证请求归属；让上传与当前 turn 共用取消令牌；状态更新绑定 turn/message ID，避免“最后一条消息”成为跨请求共享写入目标。

## A14：输出期间读旧消息会被拉回

- `lib/src/pages/ai_assistant/ai_assistant_page.dart:1662`：每 delta 字符串拼接 assembled。
- 同文件 `1663`：页面级 setState + 替换最后消息。
- 同文件 `1458`–`1467`：替换消息后同步 keys，处于搜索时执行 `_applyMatches()`。
- 同文件 `1677` / `1450`–`1455`：每 delta 添加 post-frame callback，无当前位置/用户阅读意图判断，执行 `jumpTo(index: 0)`。

实际页面装载 60 条历史，产生回复后滚到旧消息 index 30；下一 delta 后最新助手消息重新成为可见构建项，证实强制回到底部的行为。列表本身使用惰性 ScrollablePositionedList（2112 起）；本次不把它误记为全量构建列表。Flutter 可以在一帧内合并多次 setState，但已经注册的多个 post-frame 回调仍可能重复执行。CPU 开销及掉帧比例仍需设备 profile。

修复方向：仅用户处于底部并选择跟随时滚动；流文本局部更新、按帧合并输出和滚动请求；搜索结果增量更新或合理节流。

## A15：可见性只限制页面入口刷新，未限制事件订阅

- `lib/src/navigation/home_tab_stack.dart:28`–`41`：访问过的页保留在 IndexedStack，隐藏时只设置 HomeTabActivity / TickerMode 等。
- `lib/src/pages/wallet/wallet_screen.dart:156`：Provider 创建 WalletController。
- `lib/src/pages/wallet/wallet_screen.dart:227`–`239`：tab 入口刷新有活动状态和 10 秒门限。
- `lib/src/pages/wallet/wallet_controller.dart:25`：构造时监听余额事件；153–155 的事件回调仅检查 `_dead`，直接 load(force:true)。
- 同文件 `53`–`108`：load 没有 tab 可见性检查，最终调用 `_repo.getWallet()`；72–84、137–139 的 busy 合并限制同时并发，并不会使隐藏期间的事件全部失效。
- 同文件 `164`–`166`：只在 dispose 移除事件监听。
- `lib/src/pages/wallet/order/wallet_pending_recovery_service.dart:60`：pending recovery 本身有同身份 5 秒门限，不能把每次 load 描述为无条件全量恢复，也不能从这里推断无限轮询。

动态测试用真实 HomeTabStack、真实 WalletController 和真实余额事件，仅替换 repository / snapshot store 为内存计数桩。已访问钱包切换聊天后，钱包隐藏但仍在树中；一个余额事件产生一次 getWallet，dispose 后事件不再请求。未渲染完整 WalletScreen、未测后台电量或服务器负载。

修复方向：隐藏时余额事件只标记 dirty，恢复可见时合并刷新；需要全局同步的账务工作放在独立服务，不依赖隐藏 UI controller。

身份隔离说明：本 controller 的请求结果确实使用 SessionIdentity 检查，这只证明该路径的一部分防护；它不能证明 WalletStore 全局余额/支付方式缓存的所有异步请求都有隔离。不得据此抵消上一轮已复现的 WalletStore 旧请求覆盖问题。

## A17：默认明文传输是独立安全风险

- `lib/src/services/api_node_service.dart:57`–`72`：默认 cn 节点 API 为 HTTP；两个内置节点的 realtimeTcpBase 均为 HTTP scheme。
- `lib/config.dart:24` / `41`–`44`：native 默认 API 和 realtime 配置亦是这些明文地址。
- `lib/src/api/api_client.dart:48`–`79`：运行时覆盖优先，随后适用编译期覆盖；Web release 可同源。默认配置不等于每个安装包的实测配置。
- `lib/src/api/api_client.dart:164`–`171`：非公开 API 且有效 JWT 时带 Bearer Authorization；并非每个公开请求都带 token。
- `lib/src/services/friend_realtime/friend_realtime_endpoint.dart:36`–`37`：只有 https/tls/ssl 使用 TLS，HTTP scheme 为 false。
- `lib/src/services/friend_realtime_service.dart:188`–`190`：节点服务已 hydrate 时取当前选定节点，否则取 config；217–233 将 useTls 交给连接并发送 auth/token。
- `lib/src/services/friend_realtime/friend_realtime_connection_io.dart:30`–`41`：false 分支调用普通 Socket.connect；67–73 将 JSON 字节直接写入 socket。
- `android/app/src/main/AndroidManifest.xml:37`：应用允许 cleartext traffic。

测试导入实际 catalog / parser 验证默认 HTTP、两个 TCP endpoint 的 useTls=false，HTTPS 控制样例=true。没有线上抓包、没有读取或输出真实 JWT、没有发出任何生产流量。这足以确认默认路径缺传输层加密，不能证明数据已被窃取，也不能把它直接列为本次卡顿主因。本项“媒体同意”部分不在本子审计范围。

修复方向：部署并切换 HTTPS / TLS 节点，严格校验证书和 hostname；最终发布包验证运行时实际节点，不只调整字符串默认值。

## 可复核运行记录

运行文件：`ai_wallet_fault_injection_test.dart`（实际产品类 + 网络/平台/存储边界桩）。

命令：`E:\flutter\flutter\bin\flutter.bat test --no-pub artifacts/cross-module-report-verification-2026-09-28/ai-wallet/ai_wallet_fault_injection_test.dart --reporter expanded`

结果：`test-output.txt`，7 tests passed，进程退出码 0。这里测试通过表示断言捕获到当前缺陷或其控制条件，不表示产品已修复。这些是 Flutter VM / widget 逻辑复现，不是 Android/iOS 实机 FPS、内存或线上协议测量。
