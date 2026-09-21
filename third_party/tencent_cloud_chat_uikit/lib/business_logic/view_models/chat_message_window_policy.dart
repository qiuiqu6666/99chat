/// 活跃会话内存消息窗口策略（DB 无限，内存有限）。
///
/// 与 ImageCache / mediaRoot 生命周期解耦；关闭 [enabled] 可秒回滚旧行为。
class ChatMessageWindowPolicy {
  ChatMessageWindowPolicy._();

  /// 总开关。false 时 [ChatMessageWindow] / setMessageList 闸门不裁剪。
  /// 内存有界；持久化历史仍可通过阅读锚点双向分页加载。
  static bool enabled = true;

  /// trim 后目标长度：当前视口附近，而不是整段已翻历史。
  static const int targetSize = 220;

  /// 超过才 trim（允许 targetSize + 一小页瞬时）。
  static const int softMax = 280;

  /// Stop starting history pages before the next page can exceed [softMax].
  /// Idle trimming returns the shared Writer window to [targetSize].
  static const int paginationHighWater = targetSize + 40;

  /// 阅读历史时也不能无限堆积。超过后仍按阅读锚点裁剪页面 projection。
  static const int historyReadSoftMax = 300;

  /// 文档/断言参考；不强制填充。
  static const int softMin = 80;

  /// 与 [HistoryMessageDartConstant.getCount] 对齐。
  static const int loadBatch = 40;

  /// 锚点向更新侧（newest-first 数组头部方向）至少保留。
  static const int keepNewerSide = 40;

  /// 锚点向更旧侧（newest-first 数组尾部方向）至少保留。
  static const int keepOlderSide = 40;
}
