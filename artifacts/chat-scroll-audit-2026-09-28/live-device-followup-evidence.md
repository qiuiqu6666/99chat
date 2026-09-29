# 真机聊天回底与持续来消息观察

记录日期：2026-09-28。来源是已连接 Android 物理机正在运行的调试版应用（3.0.1 / versionCode 20），不是自动化测试或模拟器日志。

只读读取 Flutter logcat 与应用已有 `files/chat_recovery/recent.log`。未点击、滑动、发送消息、修改设备或导出完整日志。此记录不含消息正文、用户 ID、会话 ID、消息 ID、设备序列号。

以下时间采用设备 logcat 的 UTC+7；持久诊断使用 UTC，已加 7 小时对齐。观察仅证明所列时段的行为，未建立用户截图与某次操作的精确时间对应关系。

## 点击回底：几何到底，最新行确认未完成

| 时间 | 观察 |
| --- | --- |
| 04:21:04.638 | 点击“回到底部”；未读 0，离最新边缘 2516px，rawCount=118，followingLatest=false。 |
| 04:21:04.641 | 开始 return；hasMissingNewer=false。此操作没有 newest SDK reload。 |
| 04:21:05.088 | distance=0，但 restore_blocked，reason=waiting_for_visible_confirmation。 |
| 04:21:05.127 | 持久诊断 return_finished：success=false，targetReached=false，current=true，rowMaterialized=false。 |
| 04:21:05.132–05.181 | 新到 2 条；isFollowing=false，willPin=false；list_insert_decision=hold/not_following；距离增加至 132px。 |
| 04:21:09.150 | 未读累计 7，distance=487.5px，仍未跟随最新。 |
| 04:21:11.795–12.099 | 再次点击，随后 return_finished success=true，rowMaterialized=true。 |

这段直接证明：几何边缘与最新行呈现/确认不同步时，回底会失败；随后消息按“仍在阅读历史”处理，将最新边缘继续推远。它不是一次 SDK reload 失败的证据。

另一次 04:23:44.158 点击时 loadingHistory=true；已有历史加载在 44.336 结束，44.824 return_finished 为 success=false、targetReached=false、current=true、rowMaterialized=true。该日志没有更细的失败 stage，不能仅凭它判定为加载超时或具体证明条件失败。

## 手动向最新滚动：分批加载反复延长剩余距离

04:25:20–29 没有 capsule 点击，returning=false；日志显示分页、center 分区和窗口裁剪交替发生。

| 时间 | 加载/状态 | 滚动结果 |
| --- | --- | --- |
| 04:25:20.313–20.343 | direction=latest，batch=20，isFinished=false，haveMoreLatestData=true，memoryWindowMissingNewer=true；buffered=46，rawCount=240。 | pixels 保持 0，minExtent 从 0 变成 -2300，distance 从 0 增至 2300px。 |
| 04:25:21.462–21.495 | 再加载 20 条；buffered=27，rawCount=260。 | minExtent 从 -2091 变成 -4618.8，distance 从 0 增至 2527.8px。 |
| 04:25:22.568 | 窗口裁剪至 220；buffered=8。 | centerActive 改变；随后 pin_refused=have_more_latest。 |
| 04:25:23.503–23.542 | 加载 8 条，isFinished=true，haveMoreLatestData=false，memoryWindowMissingNewer=false。 | minExtent 从 0 变成 -654，distance 从 0 增至 654px。 |
| 04:25:24.546–29.793 | 仍依次请求 latest，得到 1、1、2、2 条；各次 isFinished=true、missingNewer=false，buffered 持续为 1 或 2；其间再次裁剪至 220。 | 出现 loading_latest / durable_deferred 拒绝跟随，及 102–231px 的边缘变化。 |
| 04:25:29.954–29.955 | set_true；received=0，followingLatest=true。 | distance=0，settle_at_true_latest_end。 |

每批附近还出现 `reveal_anchor_clear reason=attempts_exhausted`，centerActive 反复切换。先补真实缺页、再追逐持续到达的小批次的行为，与“滑到下面又有新消息，难以到达最新”的反馈一致。日志尚不足以将问题归因于某一个方法；需结合分页、durable 确认及布局回归测试。

## SDK reload 的证据边界

捕获到 04:20:47、04:20:57、04:23:46 三次 newest reload 均 `ok=true`。其中 04:20:57 点击时未读 7，04:20:58.523 返回成功并清至 0。

因此，本次日志没有证明“SDK newest reload 失败”导致用户截图。源码中的“任意 durable pending 即重拉 SDK”是另一个可检验的行为风险：durable pending 不必然代表本地缺少消息；若网络失败或返回页未覆盖捕获水位，回底会在几何滚动前失败。应单独测试，不能当作已证实的真机根因。
