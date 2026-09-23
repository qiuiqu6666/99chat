part of 'test_page.dart';

// Temporarily disabled; retain the reveal implementation for later use.
const _lotteryRevealAvailable = false;

class _ConfiguredLottery extends StatefulWidget {
  const _ConfiguredLottery(
      {super.key, required this.machineCode, this.previewOnly = false});
  final String machineCode;
  final bool previewOnly;
  @override
  State<_ConfiguredLottery> createState() => _ConfiguredLotteryState();
}

class _ConfiguredLotteryState extends State<_ConfiguredLottery> {
  late LotteryLiveSession _session;
  @override
  void initState() {
    super.initState();
    _session = lotteryLiveSession(widget.machineCode);
    _session.attach();
  }

  @override
  void dispose() {
    _session.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _session,
        builder: (context, _) {
          if (!_session.ready && _session.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!_session.ready) {
            return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_session.error ?? '暂无开奖数据'),
              TextButton(onPressed: _session.refresh, child: const Text('重试')),
            ]));
          }
          return _LotteryDashboard(
            previewOnly: widget.previewOnly,
            live: _session,
            mappings: _session.mappings,
            results:
                _session.draws.where((r) => r['status'] == 'drawn').map((r) {
              final a = Map<String, dynamic>.from(r['attributes'] as Map);
              return _MarkSixResult(
                time: _session.formatTime(r['drawAt'] as int),
                issue: r['issueLabel'] as String? ?? r['issue'] as String,
                fullIssue: r['issue'] as String,
                specialNumber: int.parse(a['special'] as String),
                zodiac: a['zodiac'] as String,
                fiveElement: a['fiveElement'] as String,
                attributes: a,
                waveColor: switch (a['wave']) {
                  '红' => _WaveColor.red,
                  '蓝' => _WaveColor.blue,
                  _ => _WaveColor.green,
                },
              );
            }).toList(),
          );
        },
      );
}

_WaveColor _mappedWave(LotteryNumberMappings? mappings, String number) {
  if (mappings == null) return _numberWave(number);
  return switch (mappings.colors[int.parse(number)]) {
    '红' => _WaveColor.red,
    '蓝' => _WaveColor.blue,
    _ => _WaveColor.green,
  };
}

class _DrawCardClock extends StatefulWidget {
  const _DrawCardClock({this.previewOnly = false, this.now});
  final bool previewOnly;
  final DateTime Function()? now;

  @override
  State<_DrawCardClock> createState() => _DrawCardClockState();
}

class _DrawCardClockState extends State<_DrawCardClock> {
  DateTime _now = DateTime.now();
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.now?.call() ?? _now;
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${current.year}-${two(current.month)}-${two(current.day)} '
        '${two(current.hour)}:${two(current.minute)}:${two(current.second)}';
    return Text('当前时间 $time',
        style: TextStyle(
            fontSize: 11,
            color: widget.previewOnly
                ? lotteryThemeColor(context, const Color(0xFF566173),
                    AppTokens.textSecondaryDark)
                : lotteryThemeColor(context, const Color(0xFF7D8797),
                    AppTokens.textSecondaryDark),
            fontWeight:
                widget.previewOnly ? FontWeight.w500 : FontWeight.normal));
  }
}

class _LotteryDashboard extends StatefulWidget {
  const _LotteryDashboard(
      {this.results = _results,
      this.mappings,
      this.previewOnly = false,
      this.live});
  final LotteryLiveSession? live;
  final bool previewOnly;
  final List<_MarkSixResult> results;
  final LotteryNumberMappings? mappings;

  @override
  State<_LotteryDashboard> createState() => _LotteryDashboardState();
}

class _LotteryDashboardState extends State<_LotteryDashboard> {
  List<_MarkSixResult> get _results => widget.results;
  static const _visiblePredictions = 100;
  int tab = 3;
  int window = 40;
  String attribute = '特码';
  bool combined = true;
  bool omissionDescending = false;
  bool dragonRanking = false;
  bool specialDragon = true;
  bool openedDragon = false;
  bool hotFirst = true;
  String _downloadUrl = '';
  bool _downloadUrlLoading = true;

  @override
  void initState() {
    super.initState();
    if (!widget.previewOnly) {
      unawaited(_loadDownloadUrl());
    }
  }

  Future<void> _loadDownloadUrl() async {
    try {
      final contact = await PlatformApi.instance.fetchContact();
      if (!mounted) return;
      setState(() {
        _downloadUrl = contact.downloadUrl.trim().isNotEmpty
            ? contact.downloadUrl.trim()
            : contact.website.trim();
        _downloadUrlLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _downloadUrlLoading = false);
    }
  }

  Future<void> _copyDownloadUrl() async {
    if (_downloadUrl.isEmpty) {
      unawaited(_loadDownloadUrl());
      return;
    }
    try {
      await ClipboardGuard.copy(_downloadUrl);
      if (mounted) ToastUtils.toast('下载链接已复制', context: context);
    } catch (_) {
      if (mounted) ToastUtils.toast('复制失败，请重试', context: context);
    }
  }

  static const attributes = [
    '特码',
    '生肖',
    '单双',
    '大小',
    '头数',
    '尾数',
    '合单双',
    '五行',
    '波色'
  ];

  String value(_MarkSixResult r, [String? field]) =>
      switch (field ?? attribute) {
        '生肖' => r.zodiac,
        '单双' => r.parity,
        '大小' => r.size,
        '头数' => r.head,
        '尾数' => r.tail,
        '合单双' => r.sumParity,
        '五行' => r.fiveElement,
        '波色' => r.waveColor.label,
        _ => r.numberText,
      };

  List<String> get categories => categoriesFor(attribute);

  List<String> categoriesFor(String field) => switch (field) {
        '生肖' => ['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'],
        '单双' || '合单双' => ['单', '双'],
        '大小' => ['大', '小'],
        '头数' => List.generate(5, (i) => '$i'),
        '尾数' => List.generate(10, (i) => '$i'),
        '五行' => ['金', '木', '水', '火', '土'],
        '波色' => ['红', '蓝', '绿'],
        _ => List.generate(49, (i) => '${i + 1}'.padLeft(2, '0')),
      };

  @override
  Widget build(BuildContext context) {
    if (widget.live != null) window = widget.live!.window;
    if (_results.isEmpty && widget.previewOnly) {
      return Center(child: _pendingLatestCard());
    }
    final sample = _results.take(window).toList();
    final counts = {
      for (final key in categories)
        key: sample.where((r) => value(r) == key).length
    };
    final omissions = {
      for (final key in categories)
        key: sample.indexWhere((r) => value(r) == key)
    };
    final ranked = [...categories]..sort((a, b) {
        final comparison = counts[b]!.compareTo(counts[a]!);
        return comparison == 0 ? a.compareTo(b) : comparison;
      });
    final latest = _results.isEmpty ? null : _results.first;
    final reveal = lotteryRevealState(widget.mappings?.machineCode ?? 'demo');
    final latestCard = latest == null
        ? _pendingLatestCard()
        : ListenableBuilder(
            listenable: reveal,
            builder: (context, _) => _latestCardPanel(Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            gradient: const LinearGradient(colors: [
                              Color(0xFF61A8FF),
                              Color(0xFF176EF2),
                            ]),
                          ),
                          child: const Icon(Icons.bolt_rounded,
                              color: Colors.white, size: 19),
                        ),
                        const SizedBox(width: 8),
                        const Text('最新开奖',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800)),
                        if (_lotteryRevealAvailable) const SizedBox(width: 6),
                        if (_lotteryRevealAvailable)
                          Semantics(
                            toggled: reveal.enabled,
                            child: TextButton(
                              key: const ValueKey('lottery-reveal-toggle'),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 28),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                foregroundColor: reveal.enabled
                                    ? const Color(0xFF1677FF)
                                    : lotteryThemeColor(
                                        context,
                                        const Color(0xFF667085),
                                        AppTokens.textSecondaryDark),
                              ),
                              onPressed: reveal.toggle,
                              child: Text(
                                  reveal.enabled
                                      ? (reveal.isHidden(
                                              latest.fullIssue ?? latest.issue)
                                          ? '眯牌·开'
                                          : '已揭晓')
                                      : '眯牌',
                                  style: const TextStyle(fontSize: 11)),
                            ),
                          ),
                        const Spacer(),
                        Text('第 ${latest.issue} 期',
                            style: const TextStyle(
                                color: _red,
                                fontSize: 15,
                                fontWeight: FontWeight.w800))
                      ]),
                      const SizedBox(height: 2),
                      Row(children: [
                        Expanded(
                            child: _DrawCardClock(
                                previewOnly: widget.previewOnly,
                                now: widget.live?.now)),
                        if (widget.live != null &&
                            widget.live!.draws.isNotEmpty)
                          Tooltip(
                            message:
                                '当前第 ${widget.live!.draws.first['issueLabel'] ?? widget.live!.draws.first['issue']} 期状态',
                            child: Container(
                              padding: widget.previewOnly
                                  ? EdgeInsets.zero
                                  : const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                              decoration: widget.previewOnly
                                  ? null
                                  : BoxDecoration(
                                      color:
                                          (widget.live!.draws.first['status'] ==
                                                      'open'
                                                  ? _blue
                                                  : _red)
                                              .withValues(alpha: .09),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                              child: _LotteryCardCountdown(
                                round: widget.live!.draws.first,
                                now: widget.live!.now,
                              ),
                            ),
                          ),
                      ]),
                      SizedBox(height: widget.previewOnly ? 8 : 6),
                      LotteryScratchCover(
                          key: ValueKey(
                              'scratch-${latest.fullIssue ?? latest.issue}'),
                          hidden: _lotteryRevealAvailable &&
                              reveal.isHidden(latest.fullIssue ?? latest.issue),
                          onRevealed: () =>
                              reveal.reveal(latest.fullIssue ?? latest.issue),
                          child: Row(children: [
                            Container(
                                width: widget.previewOnly ? 52 : 60,
                                height: widget.previewOnly ? 52 : 60,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                    image: DecorationImage(
                                        image: AssetImage(
                                            switch (latest.waveColor) {
                                          _WaveColor.red =>
                                            'assets/lhc/hong.png',
                                          _WaveColor.blue =>
                                            'assets/lhc/lan.png',
                                          _WaveColor.green =>
                                            'assets/lhc/lv.png',
                                        }),
                                        fit: BoxFit.contain)),
                                child: Text(latest.numberText,
                                    style: TextStyle(
                                        color: Colors.black,
                                        fontSize: widget.previewOnly ? 25 : 28,
                                        fontWeight: FontWeight.w800))),
                            SizedBox(width: widget.previewOnly ? 10 : 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(
                                      '特码 ${latest.numberText} · ${latest.zodiac}',
                                      style: TextStyle(
                                          fontSize:
                                              widget.previewOnly ? 16 : 17,
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 7),
                                  Wrap(spacing: 5, runSpacing: 5, children: [
                                    for (final t in [
                                      latest.parity,
                                      latest.size,
                                      '${latest.head}头',
                                      '${latest.tail}尾',
                                      '合${latest.sumParity}',
                                      latest.fiveElement,
                                      '${latest.waveColor.label}波'
                                    ])
                                      _tag(t)
                                  ]),
                                ])),
                          ])),
                    ])));
    if (widget.previewOnly) {
      return DefaultTextStyle.merge(
        style: TextStyle(
            color: lotteryThemeColor(
                context, const Color(0xFF141B26), AppTokens.textPrimaryDark)),
        child: latestCard,
      );
    }
    return DefaultTextStyle.merge(
      style: TextStyle(
          color: lotteryThemeColor(
              context, const Color(0xFF17243D), AppTokens.textPrimaryDark)),
      child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
          children: [
            latestCard,
            const SizedBox(height: 10),
            Container(
                key: const ValueKey('lottery-tab-bar'),
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                    color: lotteryThemeColor(context, const Color(0xFFF0F6FF),
                        AppTokens.surfaceAltDark),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                        color: lotteryThemeColor(context,
                            const Color(0xFFDEE9FB), AppTokens.borderDark))),
                child: Row(children: [
                  // Hide omission (1) and temperature (2) entries only.
                  // Their panels and data-loading logic remain available.
                  for (final i in [3, 0, 4, 5])
                    Expanded(
                        child: Padding(
                            padding: EdgeInsets.zero,
                            child: DecoratedBox(
                                key: ValueKey('lottery-tab-background-$i'),
                                decoration: BoxDecoration(
                                  gradient: tab == i
                                      ? const LinearGradient(colors: [
                                          Color(0xFF3A91FA),
                                          Color(0xFF1976F3),
                                        ])
                                      : null,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: FilledButton.tonal(
                                  style: FilledButton.styleFrom(
                                      minimumSize: const Size(0, 34),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 6),
                                      backgroundColor: Colors.transparent,
                                      elevation: 0,
                                      foregroundColor: tab == i
                                          ? Colors.white
                                          : lotteryThemeColor(
                                              context,
                                              const Color(0xFF526077),
                                              AppTokens.textSecondaryDark),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12))),
                                  onPressed: () {
                                    setState(() {
                                      tab = i;
                                    });
                                    if (i == 1 || i == 2) {
                                      widget.live
                                          ?.loadStatistics(_statisticsKey);
                                    }
                                  },
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (i == 5)
                                          Image.asset(
                                            'assets/lhc/declaration_megaphone.png',
                                            key: const ValueKey(
                                                'lottery-declaration-tab-icon'),
                                            width: 18,
                                            height: 18,
                                            color:
                                                tab == i ? Colors.white : null,
                                            colorBlendMode: BlendMode.srcIn,
                                          )
                                        else
                                          Icon(
                                            [
                                              Icons.auto_awesome_rounded,
                                              Icons.pending_actions_rounded,
                                              Icons
                                                  .local_fire_department_outlined,
                                              Icons.access_time_rounded,
                                              Icons.bar_chart_rounded,
                                            ][i],
                                            size: 16,
                                          ),
                                        const SizedBox(width: 6),
                                        Text(
                                          [
                                            '智能预测',
                                            '遗漏',
                                            '冷热',
                                            '开奖历史',
                                            '已开统计',
                                            '本群宣言'
                                          ][i],
                                          maxLines: 1,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ))))
                ])),
            const SizedBox(height: 8),
            if (tab == 5) ...[
              _panel(Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Image.asset('assets/lhc/declaration_megaphone.png',
                        key: const ValueKey('lottery-declaration-header-icon'),
                        width: 32,
                        height: 32),
                    const SizedBox(width: 8),
                    const Text('本群宣言',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text('真实 · 公平 · 安全 · 稳定',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 10,
                                color: lotteryThemeColor(
                                    context,
                                    const Color(0xFF8291A8),
                                    AppTokens.textSecondaryDark)))),
                  ]),
                  const SizedBox(height: 10),
                  Divider(
                      height: 1,
                      color: lotteryThemeColor(context, const Color(0xFFE5EEFC),
                          AppTokens.borderDark)),
                  const SizedBox(height: 10),
                  Container(
                    key: const ValueKey('lottery-declaration-quote'),
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(15, 14, 15, 22),
                    decoration: BoxDecoration(
                        color: lotteryThemeColor(context,
                            const Color(0xFFF2F8FF), AppTokens.surfaceAltDark),
                        borderRadius: BorderRadius.circular(12)),
                    child: Stack(children: [
                      Positioned(
                          right: 0,
                          bottom: -38,
                          child: IgnorePointer(
                              child: Text('”',
                                  style: TextStyle(
                                      color: lotteryThemeColor(
                                          context,
                                          const Color(0xFFDDEBFF),
                                          const Color(0xFF34506E)),
                                      fontSize: 86,
                                      fontWeight: FontWeight.w800)))),
                      const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '全天候直播开奖(用户实时亲眼所见)！\n'
                              '公平骰子！公开发包！无任何套路！\n'
                              '杜绝一切不透明开奖！\n'
                              '上下分不卡分！快速！红包不回收！\n'
                              '全部是真实用户在亲身参与点包！',
                              style: TextStyle(fontSize: 14, height: 1.55),
                            ),
                            SizedBox(height: 16),
                            Text('十一年口碑！诚信经营！安全稳定！',
                                style: TextStyle(fontSize: 14, height: 1.55)),
                          ]),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Material(
                    color: lotteryThemeColor(context, const Color(0xFFF2F8FF),
                        AppTokens.surfaceAltDark),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      key: const ValueKey('lottery-app-download-link'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: _downloadUrlLoading ? null : _copyDownloadUrl,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(children: [
                          const Icon(Icons.download_rounded,
                              color: _blue, size: 23),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('下载 App',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 3),
                                  Text(
                                    _downloadUrlLoading
                                        ? '正在获取下载链接…'
                                        : _downloadUrl.isEmpty
                                            ? '暂无下载链接，点击重试'
                                            : _downloadUrl,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: _downloadUrl.isEmpty
                                            ? lotteryThemeColor(
                                                context,
                                                const Color(0xFF8291A8),
                                                AppTokens.textSecondaryDark)
                                            : _blue),
                                  ),
                                ]),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.copy_rounded,
                              size: 18,
                              color: lotteryThemeColor(
                                  context,
                                  const Color(0xFF6B84A8),
                                  AppTokens.textSecondaryDark)),
                        ]),
                      ),
                    ),
                  ),
                ],
              )),
              const SizedBox(height: 22),
              Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 22,
                      height: 1,
                      color: lotteryThemeColor(context, const Color(0xFFB7C9E4),
                          AppTokens.borderDark)),
                  const SizedBox(width: 7),
                  Text('公平公开 · 真实可靠',
                      style: TextStyle(
                          fontSize: 10,
                          color: lotteryThemeColor(
                              context,
                              const Color(0xFF8B9BB2),
                              AppTokens.textSecondaryDark))),
                  const SizedBox(width: 7),
                  Container(
                      width: 22,
                      height: 1,
                      color: lotteryThemeColor(context, const Color(0xFFB7C9E4),
                          AppTokens.borderDark)),
                ]),
              ),
            ],
            if (tab == 4) ..._openedStatistics(),
            if (tab == 0)
              _panel(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          width: 3,
                          height: 19,
                          decoration: BoxDecoration(
                              color: _blue,
                              borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 9),
                      const Expanded(
                          child: Text('逐期预测',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800))),
                      const Icon(Icons.bar_chart_rounded,
                          size: 16, color: _blue),
                      const SizedBox(width: 4),
                      const Text('数据分析 · 智能推荐',
                          style: TextStyle(fontSize: 11, color: _blue)),
                    ]),
                    const SizedBox(height: 10),
                    ..._attributeControls(),
                    if (tab == 0)
                      InkWell(
                        borderRadius: BorderRadius.circular(11),
                        onTap: () => setState(() => combined = !combined),
                        child: Container(
                          key: const ValueKey('prediction-combined-panel'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: lotteryThemeColor(
                                context,
                                const Color(0xFFF2F7FF),
                                AppTokens.surfaceAltDark),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Row(children: [
                            const Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text('综合预测 · 全部属性',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700)),
                                  SizedBox(height: 2),
                                  Text('基于历史数据，AI智能分析仅供参考',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF74839B))),
                                ])),
                            Column(children: [
                              SizedBox(
                                width: 56,
                                height: 30,
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: GroupSettingsSwitch(
                                    activeColor: AppColors.primaryBlue,
                                    value: combined,
                                    onChanged: (enabled) =>
                                        setState(() => combined = enabled),
                                  ),
                                ),
                              ),
                              Text(combined ? '已开启' : '已关闭',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: lotteryThemeColor(
                                          context,
                                          const Color(0xFF74839B),
                                          AppTokens.textSecondaryDark))),
                            ]),
                          ]),
                        ),
                      ),
                    if (widget.live == null)
                      Text(
                          combined
                              ? '每期同时预测 9 项，分别核对开奖结果'
                              : attribute == '特码'
                                  ? '特码 · 每期预测 18 码，命中任一码即为中'
                                  : '$attribute · 每期以前 $window 期的最高频项作为预测',
                          style: TextStyle(
                              color: lotteryThemeColor(
                                  context,
                                  const Color(0xFF7D8797),
                                  AppTokens.textSecondaryDark),
                              fontSize: 12)),
                    const SizedBox(height: 12),
                    widget.live != null
                        ? _livePredictions()
                        : combined
                            ? _combinedHistory()
                            : _predictionHistory(),
                    const SizedBox(height: 12),
                    if (widget.live == null)
                      Text(
                          '演示回测，并非已发布预测。特码18码、生肖5肖、尾数4尾、头数3头、五行3个。仅使用该期之前的数据；并列按固定顺序选取，样本不足不判定。',
                          style: TextStyle(
                              color: lotteryThemeColor(
                                  context,
                                  const Color(0xFF7D8797),
                                  AppTokens.textSecondaryDark),
                              fontSize: 12)),
                    const SizedBox(height: 10),
                    Center(
                        child: Text('理性参考 · 快乐参与',
                            style: TextStyle(
                                color: lotteryThemeColor(
                                    context,
                                    const Color(0xFF74839B),
                                    AppTokens.textSecondaryDark),
                                fontSize: 11))),
                  ])),
            if ((tab == 1 || tab == 2) && widget.live != null)
              _serverStatisticsPanel()
            else if (tab == 1 && widget.live?.statisticsComplete == false)
              _panel(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader('当前遗漏'),
                    const Text('历史期次不连续，暂不计算遗漏和长龙。'),
                  ]))
            else if (tab == 1)
              _omissionPanel(omissions, sample.length),
            if (tab == 2 && widget.live == null)
              _temperaturePanel(counts, ranked, sample.length),
            if (tab == 3) ...[
              Container(
                height: 540,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: lotteryThemeColor(
                      context, Colors.white, AppTokens.surfaceDark),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                      color: lotteryThemeColor(context, const Color(0xFFDFE9F8),
                          AppTokens.borderDark)),
                ),
                child: _ResultTable(results: _results),
              ),
            ],
            const SizedBox(height: 24),
          ]),
    );
  }

  Widget _pendingLatestCard() {
    final live = widget.live;
    final round =
        live != null && live.draws.isNotEmpty ? live.draws.first : null;
    return _panel(Column(mainAxisSize: MainAxisSize.min, children: [
      if (round != null) ...[
        Text(
            '第 ${round['status'] == 'waiting_open' ? '0' : round['issueLabel'] ?? round['issue']} 期',
            style: const TextStyle(color: _red, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _LotteryCardCountdown(round: round, now: live!.now),
        const SizedBox(height: 8),
      ],
      Text(round == null ? '暂无已完成开奖' : '本期尚未开奖'),
      TextButton(onPressed: live?.refresh, child: const Text('刷新')),
    ]));
  }

  List<Widget> _openedStatistics() {
    final sample = _results.take(100).toList();
    int count(String field, String item) => sample
        .where((r) => field == '组合'
            ? '${r.size}${r.parity}' == item
            : value(r, field) == item)
        .length;
    Widget statisticCell((String, String, Color?) item) {
      final (field, rawValue, accent) = item;
      final label = field == '生肖'
          ? '特肖$rawValue'
          : field == '波色'
              ? '$rawValue波'
              : rawValue;
      return Expanded(
        child: Container(
          key: ValueKey('opened-cell-$field-$rawValue'),
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color:
                lotteryThemeColor(context, Colors.white, AppTokens.surfaceDark),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color: lotteryThemeColor(
                    context, const Color(0xFFE5EEFC), AppTokens.borderDark)),
          ),
          child: Row(children: [
            Expanded(
              flex: 4,
              child: Container(
                key: ValueKey('opened-label-$field-$rawValue'),
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: accent == null
                      ? null
                      : LinearGradient(colors: [
                          accent.withValues(alpha: .78),
                          accent,
                        ]),
                  color: accent == null
                      ? lotteryThemeColor(context, const Color(0xFFF1F6FD),
                          AppTokens.surfaceAltDark)
                      : null,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (accent != null) ...[
                      const Icon(Icons.bar_chart_rounded,
                          size: 13, color: Colors.white),
                      const SizedBox(width: 3),
                    ],
                    Text(label,
                        style: TextStyle(
                            color: accent == null
                                ? lotteryThemeColor(
                                    context,
                                    const Color(0xFF394A64),
                                    AppTokens.textPrimaryDark)
                                : Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: Container(
                key: ValueKey('opened-count-cell-$field-$rawValue'),
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: lotteryThemeColor(context, const Color(0xFFEBFAF5),
                      const Color(0xFF193B32)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${count(field, rawValue)}',
                    key: ValueKey('opened-$field-$rawValue'),
                    style: const TextStyle(
                        color: Color(0xFF159664),
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      );
    }

    Widget section(String title, List<(String, String, Color?)> items,
        {int columns = 2}) {
      final secondary = lotteryThemeColor(
          context, const Color(0xFF7D8797), AppTokens.textSecondaryDark);
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _panel(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 3,
                height: 19,
                decoration: BoxDecoration(
                    color: _blue, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 9),
            Text('$title（${sample.length}期）',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const Spacer(),
            const Icon(Icons.bar_chart_rounded, size: 16, color: _blue),
            const SizedBox(width: 4),
            Text('数据统计', style: TextStyle(fontSize: 11, color: secondary)),
          ]),
          const SizedBox(height: 10),
          Container(
            key: ValueKey('opened-statistics-$title'),
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 5),
            decoration: BoxDecoration(
              color: lotteryThemeColor(
                  context, const Color(0xFFF1F7FF), AppTokens.surfaceAltDark),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Column(children: [
              Row(children: [
                for (var i = 0; i < columns; i++)
                  Expanded(
                      child: Row(children: [
                    Expanded(
                        flex: 4,
                        child: Text('类型',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: secondary))),
                    const SizedBox(width: 8),
                    Expanded(
                        flex: 5,
                        child: Text('已开次数',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: secondary))),
                  ])),
              ]),
              const SizedBox(height: 4),
              for (var start = 0; start < items.length; start += columns)
                Row(children: [
                  for (var i = start; i < start + columns; i++)
                    i < items.length
                        ? statisticCell(items[i])
                        : const Expanded(child: SizedBox()),
                ]),
            ]),
          ),
        ])),
      );
    }

    return [
      if (sample.isEmpty)
        const Padding(padding: EdgeInsets.all(8), child: Text('暂无已开奖记录')),
      section('基本类型', [
        ('单双', '单', _blue),
        ('单双', '双', _red),
        ('大小', '大', _red),
        ('大小', '小', _blue)
      ]),
      section('组合类型', [
        ('组合', '小单', _blue),
        ('组合', '小双', _green),
        ('组合', '大单', Colors.orange),
        ('组合', '大双', _red)
      ]),
      section(
          '色波', [('波色', '红', _red), ('波色', '蓝', _blue), ('波色', '绿', _green)],
          columns: 3),
      section('生肖',
          [for (final zodiac in categoriesFor('生肖')) ('生肖', zodiac, null)]),
    ];
  }

  String get _statisticsKey => const [
        'special',
        'zodiac',
        'parity',
        'size',
        'head',
        'tail',
        'sumParity',
        'fiveElement',
        'wave'
      ][attributes.indexOf(attribute)];

  Widget _serverStatisticsPanel() {
    final live = widget.live!;
    final data = live.statistics[_statisticsKey];
    final rows = [...?data?.items];
    rows.sort((a, b) {
      int comparison;
      if (tab == 2) {
        comparison = (a['count'] as int).compareTo(b['count'] as int) *
            (hotFirst ? -1 : 1);
      } else if (omissionDescending) {
        comparison = ((b['omission']?['periods'] ?? -1) as int)
            .compareTo((a['omission']?['periods'] ?? -1) as int);
      } else {
        comparison = (a['order'] as int).compareTo(b['order'] as int);
      }
      return comparison == 0
          ? (a['value'] as String).compareTo(b['value'] as String)
          : comparison;
    });
    return _panel(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(tab == 1 ? '当前遗漏' : '冷热分布'),
      ..._attributeControls(),
      Wrap(spacing: 6, children: [
        for (final (label, selected, action) in tab == 1
            ? <(String, bool, VoidCallback)>[
                (
                  '默认顺序',
                  !omissionDescending && !dragonRanking,
                  () => setState(() {
                        omissionDescending = false;
                        dragonRanking = false;
                      })
                ),
                (
                  '遗漏最多',
                  omissionDescending && !dragonRanking,
                  () => setState(() {
                        omissionDescending = true;
                        dragonRanking = false;
                      })
                ),
                (
                  '长龙排行',
                  dragonRanking,
                  () => setState(() => dragonRanking = true)
                ),
              ]
            : <(String, bool, VoidCallback)>[
                ('热号优先', hotFirst, () => setState(() => hotFirst = true)),
                ('冷号优先', !hotFirst, () => setState(() => hotFirst = false)),
              ])
          ChoiceChip(
              label: Text(label),
              selected: selected,
              showCheckmark: false,
              onSelected: (_) => action()),
      ]),
      if (tab == 1 && dragonRanking) ...[
        if (live.statisticsComplete && _results.isNotEmpty)
          _dragonList()
        else
          const Text('暂无连续完整的开奖样本'),
      ] else ...[
        if (live.statisticsError != null)
          TextButton(
              onPressed: () => live.loadStatistics(_statisticsKey, force: true),
              child: Text(live.statisticsError!)),
        if (data == null)
          TextButton(
              onPressed: () => live.loadStatistics(_statisticsKey, force: true),
              child: Text(live.statisticsLoading ? '统计加载中…' : '点击加载统计'))
        else ...[
          Text(
              '实际统计 ${data.sampleCount} 期${data.basisIssue == null ? '' : ' · 截至 ${data.basisIssue}'}',
              style: TextStyle(
                  fontSize: 11,
                  color: lotteryThemeColor(context, const Color(0xFF7D8797),
                      AppTokens.textSecondaryDark))),
          if (!data.sampleComplete)
            const Text('统计样本存在缺期',
                style: TextStyle(fontSize: 11, color: Colors.orange)),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, constraints) {
            final columns = (constraints.maxWidth / 80).floor().clamp(1, 8);
            final width = (constraints.maxWidth - (columns - 1) * 6) / columns;
            return Wrap(spacing: 6, runSpacing: 6, children: [
              for (final row in rows)
                Container(
                    width: width,
                    padding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    decoration: BoxDecoration(
                        color: lotteryThemeColor(context,
                            const Color(0xFFF2F5FA), AppTokens.surfaceAltDark),
                        borderRadius: BorderRadius.circular(10)),
                    child: Column(children: [
                      if (attribute == '特码')
                        _NumberBall(row['value'],
                            wave: _mappedWave(widget.mappings, row['value']))
                      else
                        Text(row['value'],
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      if (data.sampleCount == 0)
                        const Text('暂无样本', style: TextStyle(fontSize: 11))
                      else if (tab == 1)
                        Text(
                            row['omission'] == null
                                ? '暂不可计算'
                                : '${row['omission']['isLowerBound'] == true ? '≥' : ''}${row['omission']['periods']}期',
                            style: const TextStyle(fontSize: 12))
                      else ...[
                        Text(
                            '${row['count']} 次 · ${const {
                              'hot': '热',
                              'cold': '冷',
                              'normal': '平',
                              'unopened': '未开',
                              'unknown': '暂无样本'
                            }[row['temperature']]}',
                            style: const TextStyle(fontSize: 11)),
                        const SizedBox(height: 5),
                        LinearProgressIndicator(
                            value: (row['ratio'] as num).toDouble()),
                        Text(
                            '${((row['ratio'] as num) * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ])),
            ]);
          }),
        ],
      ],
    ]));
  }

  Widget _temperaturePanel(
      Map<String, int> counts, List<String> ranked, int sampleCount) {
    final ordered = [...ranked];
    if (!hotFirst) {
      ordered.sort((a, b) {
        final comparison = counts[a]!.compareTo(counts[b]!);
        return comparison == 0 ? a.compareTo(b) : comparison;
      });
    }
    final maximum = counts[ranked.first]!;
    final minimum = counts[ranked.last]!;
    final tied = maximum == minimum;
    return _panel(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader('冷热分布'),
      const SizedBox(height: 8),
      ..._attributeControls(),
      Wrap(spacing: 6, children: [
        ChoiceChip(
            label: const Text('热号优先'),
            selected: hotFirst,
            showCheckmark: false,
            onSelected: (_) => setState(() => hotFirst = true)),
        ChoiceChip(
            label: const Text('冷号优先'),
            selected: !hotFirst,
            showCheckmark: false,
            onSelected: (_) => setState(() => hotFirst = false)),
      ]),
      const SizedBox(height: 8),
      Text('实际统计 $sampleCount 期 · 占比为出现次数 / 实际期数',
          style: TextStyle(
              fontSize: 11,
              color: lotteryThemeColor(context, const Color(0xFF7D8797),
                  AppTokens.textSecondaryDark))),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, constraints) {
        final columns = (constraints.maxWidth / 72).floor().clamp(1, 8);
        final width = (constraints.maxWidth - (columns - 1) * 6) / columns;
        return Wrap(spacing: 6, runSpacing: 6, children: [
          for (final key in ordered)
            Builder(builder: (_) {
              final count = counts[key]!;
              final ratio = sampleCount == 0 ? 0.0 : count / sampleCount;
              final hot = !tied && count == maximum;
              final cold = !tied && count == minimum;
              final color = hot
                  ? const Color(0xFFE56C4B)
                  : cold
                      ? const Color(0xFF4189CF)
                      : lotteryThemeColor(context, const Color(0xFF76869C),
                          AppTokens.textSecondaryDark);
              final label = count == 0
                  ? '未开'
                  : hot
                      ? '热'
                      : cold
                          ? '冷'
                          : '平';
              return Container(
                width: width,
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: .16))),
                child: Column(children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (attribute == '特码')
                          _NumberBall(key,
                              size: 30, wave: _mappedWave(widget.mappings, key))
                        else
                          Text(key,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                        Text(label,
                            style: TextStyle(fontSize: 9, color: color)),
                      ]),
                  const SizedBox(height: 7),
                  Text('$count 次',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: color)),
                  const SizedBox(height: 6),
                  ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 4,
                          color: color,
                          backgroundColor: lotteryThemeColor(
                              context,
                              const Color(0xFFE8EDF4),
                              AppTokens.surfaceAltDark))),
                  const SizedBox(height: 4),
                  Text('${(ratio * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                          fontSize: 10,
                          color: lotteryThemeColor(
                              context,
                              const Color(0xFF8895A8),
                              AppTokens.textSecondaryDark))),
                ]),
              );
            }),
        ]);
      }),
      const SizedBox(height: 12),
      Text('热 / 冷表示样本内最高 / 最低频次（含并列），其余为平；全部同频时不区分冷热。',
          style: TextStyle(
              fontSize: 11,
              color: lotteryThemeColor(context, const Color(0xFF7D8797),
                  AppTokens.textSecondaryDark))),
    ]));
  }

  Widget _omissionPanel(Map<String, int> omissions, int sampleCount) {
    int gap(String key) => omissions[key]! < 0 ? sampleCount : omissions[key]!;
    final ordered = [...categories];
    if (omissionDescending || dragonRanking) {
      ordered.sort((a, b) {
        final difference = gap(b).compareTo(gap(a));
        return difference == 0 ? a.compareTo(b) : difference;
      });
    }
    return _panel(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader('当前遗漏'),
      const SizedBox(height: 8),
      ..._attributeControls(),
      Wrap(spacing: 6, children: [
        ChoiceChip(
            label: const Text('默认顺序'),
            selected: !omissionDescending && !dragonRanking,
            showCheckmark: false,
            onSelected: (_) => setState(() {
                  omissionDescending = false;
                  dragonRanking = false;
                })),
        ChoiceChip(
            label: const Text('遗漏最多'),
            selected: omissionDescending && !dragonRanking,
            showCheckmark: false,
            onSelected: (_) => setState(() {
                  omissionDescending = true;
                  dragonRanking = false;
                })),
        ChoiceChip(
            label: const Text('长龙排行'),
            selected: dragonRanking,
            showCheckmark: false,
            onSelected: (_) => setState(() => dragonRanking = true)),
      ]),
      const SizedBox(height: 10),
      if (dragonRanking)
        _dragonList()
      else
        LayoutBuilder(builder: (context, constraints) {
          final columns = (constraints.maxWidth / 60).floor().clamp(1, 8);
          final width = (constraints.maxWidth - (columns - 1) * 6) / columns;
          return Wrap(spacing: 6, runSpacing: 6, children: [
            for (final key in ordered)
              Builder(builder: (_) {
                final missing = omissions[key]!;
                final fresh = missing == 0;
                final color = fresh
                    ? const Color(0xFF159664)
                    : missing < 0
                        ? const Color(0xFF7B6BD6)
                        : const Color(0xFFE09325);
                return Semantics(
                  label:
                      '$attribute $key，${fresh ? '本期开出' : '遗漏${missing < 0 ? '至少$sampleCount' : '$missing'}期'}',
                  child: Container(
                    width: width,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: .07),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: color.withValues(alpha: .16))),
                    child: Column(children: [
                      if (attribute == '特码')
                        _NumberBall(key,
                            wave: _mappedWave(widget.mappings, key))
                      else
                        Text(key,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 5),
                      Text(
                          fresh
                              ? '已开'
                              : '${missing < 0 ? '≥$sampleCount' : '$missing'}期',
                          style: TextStyle(
                              fontSize: 12,
                              color: color,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                );
              }),
          ]);
        }),
      const SizedBox(height: 12),
      Text('已开 = 本期出现（遗漏 0）；≥ 表示样本内未出现，仅能确定遗漏下限。',
          style: TextStyle(
              color: lotteryThemeColor(context, const Color(0xFF7D8797),
                  AppTokens.textSecondaryDark),
              fontSize: 11)),
    ]));
  }

  Widget _dragonList() {
    final sample = _results.take(window).toList();
    if (sample.isEmpty) return const Text('暂无开奖记录');
    final entries =
        <({String field, String key, bool open, int count, bool bounded})>[];
    for (final field in attributes) {
      for (final key in categoriesFor(field)) {
        final open = value(sample.first, field) == key;
        final count =
            sample.takeWhile((r) => (value(r, field) == key) == open).length;
        entries.add((
          field: field,
          key: key,
          open: open,
          count: count,
          bounded: count == sample.length
        ));
      }
    }
    entries.sort((a, b) {
      final comparison = b.count.compareTo(a.count);
      if (comparison != 0) return comparison;
      final fieldOrder =
          attributes.indexOf(a.field).compareTo(attributes.indexOf(b.field));
      return fieldOrder != 0 ? fieldOrder : a.key.compareTo(b.key);
    });
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 10),
      Wrap(spacing: 8, children: [
        ChoiceChip(
          label: const Text('特码长龙'),
          selected: specialDragon,
          showCheckmark: false,
          onSelected: (_) => setState(() => specialDragon = true),
        ),
        ChoiceChip(
          label: const Text('其他属性长龙'),
          selected: !specialDragon,
          showCheckmark: false,
          onSelected: (_) => setState(() => specialDragon = false),
        ),
      ]),
      Wrap(spacing: 8, children: [
        ChoiceChip(
          label: const Text('未开'),
          selected: !openedDragon,
          showCheckmark: false,
          onSelected: (_) => setState(() => openedDragon = false),
        ),
        ChoiceChip(
          label: const Text('已开'),
          selected: openedDragon,
          showCheckmark: false,
          onSelected: (_) => setState(() => openedDragon = true),
        ),
      ]),
      for (final special in [specialDragon]) ...[
        const SizedBox(height: 14),
        Text(special ? '特码长龙' : '其他属性长龙 · 综合排序',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        Builder(builder: (_) {
          final group = entries
              .where(
                  (e) => (e.field == '特码') == special && e.open == openedDragon)
              .toList();
          return Column(children: [
            for (final entry in group)
              Builder(builder: (_) {
                final rank =
                    group.indexWhere((e) => e.count == entry.count) + 1;
                final color = entry.open
                    ? const Color(0xFF159664)
                    : const Color(0xFFE09325);
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: lotteryThemeColor(
                                  context,
                                  const Color(0xFFEDF1F6),
                                  AppTokens.borderDark)))),
                  child: Row(children: [
                    Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: .09),
                            borderRadius: BorderRadius.circular(7)),
                        child: Text('$rank',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: color))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: entry.field == '特码'
                            ? Row(
                                key: ValueKey('dragon-special-${entry.key}'),
                                children: [
                                  const Text('特码',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 6),
                                  _NumberBall(entry.key,
                                      wave: _mappedWave(
                                          widget.mappings, entry.key)),
                                ],
                              )
                            : Text('${entry.field} ${entry.key}',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600))),
                    Text(
                        '${entry.bounded ? '至少 ' : ''}${entry.open ? '连续开 ' : ''}${entry.count} 期${entry.open ? '' : '未开'}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: color)),
                  ]),
                );
              }),
          ]);
        }),
      ],
    ]);
  }

  List<String>? _prediction(List<_MarkSixResult> preceding, [String? field]) {
    if (preceding.length < window) return null;
    final selected = field ?? attribute;
    final ordered = [...categoriesFor(selected)]..sort((a, b) {
        final countA = preceding.where((r) => value(r, selected) == a).length;
        final countB = preceding.where((r) => value(r, selected) == b).length;
        return countA == countB ? a.compareTo(b) : countB.compareTo(countA);
      });
    final count = switch (selected) {
      '特码' => 18,
      '生肖' => 5,
      '尾数' => 4,
      '头数' || '五行' => 3,
      _ => 1,
    };
    return ordered.take(count).toList();
  }

  Widget _combinedHistory() => Column(children: [
        _combinedIssue(null, _results.take(window).toList()),
        for (var i = 0; i < _results.length && i < _visiblePredictions - 1; i++)
          _combinedIssue(
              _results[i], _results.skip(i + 1).take(window).toList()),
      ]);

  Widget _combinedIssue(
      _MarkSixResult? result, List<_MarkSixResult> preceding) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          border: Border.all(
              color: lotteryThemeColor(
                  context, const Color(0xFFE4EAF3), AppTokens.borderDark)),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            result == null
                ? '下一期 · 待开奖'
                : '第 ${result.issue} 期 · 开奖 ${result.numberText} ${result.zodiac}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        for (final field in attributes)
          Builder(builder: (_) {
            final prediction = _prediction(preceding, field);
            final actual = result == null ? null : value(result, field);
            final hit = prediction != null &&
                actual != null &&
                prediction.contains(actual);
            final status = result == null
                ? '待开奖'
                : prediction == null
                    ? '样本不足'
                    : hit
                        ? '中'
                        : '未中';
            final color = actual == null || prediction == null
                ? lotteryThemeColor(context, const Color(0xFF7D8797),
                    AppTokens.textSecondaryDark)
                : hit
                    ? const Color(0xFF159664)
                    : const Color(0xFFE55363);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                    width: 44,
                    child: Text(field,
                        style: TextStyle(
                            fontSize: 12,
                            color: lotteryThemeColor(
                                context,
                                const Color(0xFF69768A),
                                AppTokens.textSecondaryDark)))),
                Expanded(
                    child: _copyablePrediction(
                        field,
                        prediction,
                        Text(prediction?.join('  ') ?? '—',
                            style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF1677FF),
                                fontWeight: FontWeight.w600)))),
                const SizedBox(width: 6),
                SizedBox(
                    width: 34,
                    child: Text(actual ?? '—',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12))),
                SizedBox(
                    width: 50,
                    child: Text(status,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 12,
                            color: color,
                            fontWeight: FontWeight.w700))),
              ]),
            );
          }),
      ]),
    );
  }

  Widget _predictionHistory() {
    final next = _prediction(_results.take(window).toList());
    return Column(children: [
      _predictionLine('期号', '预测', '开奖', '结果', header: true),
      _predictionLine('下一期', next?.join(' ') ?? '—', '—', '待开奖'),
      for (var index = 0;
          index < _results.length && index < _visiblePredictions - 1;
          index++)
        Builder(builder: (context) {
          final result = _results[index];
          final predicted =
              _prediction(_results.skip(index + 1).take(window).toList());
          final actual = value(result);
          return _predictionLine(
              result.issue,
              predicted?.join(' ') ?? '—',
              actual,
              predicted == null
                  ? '样本不足'
                  : predicted.contains(actual)
                      ? '中'
                      : '未中');
        }),
    ]);
  }

  Widget _predictionLine(
      String issue, String prediction, String actual, String status,
      {bool header = false}) {
    final color = status == '中'
        ? const Color(0xFF159664)
        : status == '未中'
            ? const Color(0xFFE55363)
            : lotteryThemeColor(
                context, const Color(0xFF7D8797), AppTokens.textSecondaryDark);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
      decoration: BoxDecoration(
        color: header
            ? lotteryThemeColor(
                context, const Color(0xFFF0F5FC), AppTokens.surfaceAltDark)
            : lotteryThemeColor(context, Colors.white, AppTokens.surfaceDark),
        border: Border(
            bottom: BorderSide(
                color: lotteryThemeColor(
                    context, const Color(0xFFEDF1F6), AppTokens.borderDark))),
      ),
      child: Row(children: [
        for (final (index, text) in [issue, prediction, actual].indexed)
          Expanded(
              flex: attribute == '特码' && index == 1 ? 4 : 1,
              child: _copyablePrediction(
                  attribute,
                  !header && index == 1 && prediction != '—'
                      ? prediction.split(' ')
                      : null,
                  !header &&
                          attribute == '特码' &&
                          index == 1 &&
                          prediction != '—'
                      ? Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 4,
                          runSpacing: 4,
                          children: prediction
                              .split(' ')
                              .map((number) => Container(
                                    width: 24,
                                    height: 24,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: number == actual
                                          ? const Color(0xFF159664)
                                          : lotteryThemeColor(
                                              context,
                                              const Color(0xFFEAF2FF),
                                              const Color(0xFF203B60)),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(number,
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: number == actual
                                                ? Colors.white
                                                : const Color(0xFF1677FF))),
                                  ))
                              .toList(),
                        )
                      : Text(text,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  header ? FontWeight.w700 : FontWeight.w500,
                              color: !header && text == prediction
                                  ? const Color(0xFF1677FF)
                                  : lotteryThemeColor(
                                      context,
                                      const Color(0xFF536780),
                                      AppTokens.textSecondaryDark))))),
        Expanded(
            child: Text(status,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    color: header
                        ? lotteryThemeColor(context, const Color(0xFF536780),
                            AppTokens.textSecondaryDark)
                        : color,
                    fontWeight: FontWeight.w700))),
      ]),
    );
  }

  Widget _copyablePrediction(
      String field, List<String>? numbers, Widget child) {
    if (numbers == null || numbers.isEmpty) return child;
    return Semantics(
      button: true,
      label: '复制$field预测',
      child: InkWell(
        onTap: () async {
          try {
            final text = switch (field) {
              '特码' || '五行' || '生肖' => numbers.join('.'),
              '头数' => numbers.map((number) => '$number头').join(),
              '尾数' => numbers.map((number) => '$number尾').join(),
              _ => numbers.join(' '),
            };
            await Clipboard.setData(ClipboardData(text: text));
            if (!mounted) return;
            ToastUtils.toast('$field预测已复制', context: context);
          } catch (_) {
            if (!mounted) return;
            ToastUtils.toast('复制失败，请重试', context: context);
          }
        },
        child: child,
      ),
    );
  }

  Future<void> _selectWindow() async {
    final selected = await AppDialog.actionSheet<int>(
      title: '统计范围',
      actionContentWidth: 180,
      actions: [
        for (final count in (widget.live?.config?['windowOptions'] as List? ??
                [6, 12, 20, 30, 40])
            .cast<int>())
          AppActionSheetItem<int>(
            text: '最近 $count 期',
            value: count,
            icon: Icons.check_rounded,
            iconColor:
                window == count ? AppColors.primaryBlue : Colors.transparent,
          ),
      ],
    );
    if (!mounted || selected == null) return;
    setState(() => window = selected);
    widget.live?.selectWindow(selected);
  }

  Widget _livePredictions() {
    final live = widget.live!;
    const predictionAttributes = [...attributes, '组合'];
    const keys = [
      'special',
      'zodiac',
      'parity',
      'size',
      'head',
      'tail',
      'sumParity',
      'fiveElement',
      'wave',
      'zuhe'
    ];
    const labels = {
      'pending': '待开奖',
      'hit': '中',
      'miss': '未中',
      'insufficient_sample': '样本不足',
      'not_published': '未发布',
      'void': '已取消'
    };
    if (live.predictions.isEmpty) return Text(live.loading ? '预测加载中…' : '暂无预测');
    const displayOrder = [
      'special',
      'zodiac',
      'parity',
      'size',
      'zuhe',
      'head',
      'tail',
      'sumParity',
      'fiveElement',
      'wave'
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (live.predictionMode == 'backtest') const Text('回测结果，并非开奖前已发布预测'),
      for (final row in live.predictions)
        Builder(builder: (context) {
          final issue = '${row['issue']}';
          final draw = live.draws.firstWhere(
              (item) => '${item['issue']}' == issue,
              orElse: () => <String, dynamic>{});
          final drawAt = draw['status'] == 'drawn' ? draw['drawAt'] : null;
          final predictionItems = (row['items'] as List? ?? [])
              .whereType<Map>()
              .where((item) =>
                  combined ||
                  item['attribute'] ==
                      keys[predictionAttributes.indexOf(attribute)])
              .toList()
            ..sort((a, b) {
              int rank(Map item) {
                final index = displayOrder.indexOf('${item['attribute']}');
                return index < 0 ? displayOrder.length : index;
              }

              return rank(a).compareTo(rank(b));
            });
          return Container(
            key: ValueKey('prediction-issue-$issue'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(11, 8, 11, 4),
            decoration: BoxDecoration(
              color: lotteryThemeColor(
                  context, Colors.white, AppTokens.surfaceDark),
              border: Border.all(
                  color: lotteryThemeColor(
                      context, const Color(0xFFD9E6FA), AppTokens.borderDark)),
              borderRadius: BorderRadius.circular(11),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('第 ${row['issueLabel'] ?? row['issue']} 期',
                    style: const TextStyle(
                        color: _blue,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                const Spacer(),
                const Icon(Icons.access_time_rounded,
                    size: 13, color: Color(0xFF74839B)),
                const SizedBox(width: 3),
                Flexible(
                    child: Text(
                        '开奖时间：${drawAt is int ? live.formatTime(drawAt) : '待公布'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10,
                            color: lotteryThemeColor(
                                context,
                                const Color(0xFF74839B),
                                AppTokens.textSecondaryDark)))),
              ]),
              const SizedBox(height: 3),
              for (final item in predictionItems)
                Builder(builder: (context) {
                  final key = '${item['attribute']}';
                  final index = keys.indexOf(key);
                  final field = index < 0 ? key : predictionAttributes[index];
                  final values = (item['values'] as List? ?? [])
                      .map((value) => '$value')
                      .toList();
                  final actual =
                      row['actual'] is Map ? row['actual'][key] : null;
                  final status = row['drawState'] == 'cancelled'
                      ? 'void'
                      : row['predictionState'] == 'insufficient_sample'
                          ? 'insufficient_sample'
                          : row['predictionState'] == 'not_published'
                              ? 'not_published'
                              : item['result'];
                  final (icon, iconColor) = switch (key) {
                    'special' => (Icons.circle_outlined, _red),
                    'zodiac' => (Icons.pets_rounded, const Color(0xFFFF783B)),
                    'parity' => (
                        Icons.contrast_rounded,
                        lotteryThemeColor(context, const Color(0xFF17243D),
                            AppTokens.textPrimaryDark)
                      ),
                    'size' => (Icons.swap_vert_rounded, _green),
                    'zuhe' => (Icons.link_rounded, _blue),
                    'head' => (Icons.looks_one_rounded, _blue),
                    'tail' => (Icons.onetwothree_rounded, _blue),
                    'sumParity' => (Icons.join_inner_rounded, _blue),
                    'fiveElement' => (Icons.eco_rounded, _green),
                    'wave' => (Icons.waves_rounded, _blue),
                    _ => (Icons.circle_outlined, _blue),
                  };
                  final resultColor = status == 'hit'
                      ? const Color(0xFF159664)
                      : status == 'miss'
                          ? _red
                          : lotteryThemeColor(context, const Color(0xFF74839B),
                              AppTokens.textSecondaryDark);
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                        border: Border(
                            top: BorderSide(
                                color: lotteryThemeColor(
                                    context,
                                    const Color(0xFFE9EFF8),
                                    AppTokens.borderDark)))),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                              width: 20,
                              child: Icon(icon, size: 17, color: iconColor)),
                          const SizedBox(width: 4),
                          SizedBox(
                              width: 48,
                              child: Text(field,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600))),
                          Expanded(
                              child: _copyablePrediction(
                                  field,
                                  values.isEmpty ? null : values,
                                  Text(values.isEmpty ? '—' : values.join(' '),
                                      style: const TextStyle(fontSize: 12)))),
                          if (actual != null) ...[
                            const SizedBox(width: 4),
                            Text('$actual',
                                style: const TextStyle(fontSize: 11)),
                          ],
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: resultColor.withValues(alpha: .09),
                                borderRadius: BorderRadius.circular(12)),
                            child: Text(labels[status] ?? '—',
                                style: TextStyle(
                                    fontSize: 11, color: resultColor)),
                          ),
                        ]),
                  );
                }),
            ]),
          );
        }),
      Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: live.predictionsLoadingMore
              ? const SizedBox(
                  key: ValueKey('prediction-page-loading'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : live.predictionsPageError != null
                  ? Column(
                      key: const ValueKey('prediction-page-error'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(live.predictionsPageError!),
                        TextButton(
                          key: const ValueKey('prediction-page-retry'),
                          onPressed: live.loadAllPredictions,
                          child: const Text('重试'),
                        ),
                      ],
                    )
                  : Text(
                      live.predictionsHasMore ? '正在加载预测…' : '已全部加载',
                      key: ValueKey(live.predictionsHasMore
                          ? 'prediction-page-more'
                          : 'prediction-page-end'),
                      style: TextStyle(
                        fontSize: 12,
                        color: lotteryThemeColor(
                            context,
                            const Color(0xFF74839B),
                            AppTokens.textSecondaryDark),
                      ),
                    ),
        ),
      ),
    ]);
  }

  List<Widget> _attributeControls() => [
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final name in [
                ...attributes,
                if (tab == 0 && widget.live != null) '组合',
              ])
                Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ChoiceChip(
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                        labelStyle: TextStyle(
                            fontSize: 12,
                            color: attribute == name
                                ? (tab == 0 ? Colors.white : _blue)
                                : lotteryThemeColor(
                                    context,
                                    const Color(0xFF69768A),
                                    AppTokens.textSecondaryDark)),
                        selectedColor: tab == 0
                            ? const Color(0xFF328BFA)
                            : lotteryThemeColor(
                                context,
                                const Color(0xFFE5EFFF),
                                const Color(0xFF203B60)),
                        backgroundColor: lotteryThemeColor(
                            context, Colors.white, AppTokens.surfaceDark),
                        side: BorderSide(
                            color: attribute == name
                                ? (tab == 0
                                    ? const Color(0xFF328BFA)
                                    : lotteryThemeColor(
                                        context,
                                        const Color(0xFFB9D3FF),
                                        const Color(0xFF203B60)))
                                : lotteryThemeColor(
                                    context,
                                    const Color(0xFFE3E9F1),
                                    AppTokens.borderDark)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9)),
                        label: Text(name),
                        selected: attribute == name,
                        onSelected: (_) => setState(() {
                              attribute = name;
                              if (tab == 0) combined = false;
                              if (tab == 1 || tab == 2) {
                                widget.live?.loadStatistics(_statisticsKey);
                              }
                            })))
            ])),
        const SizedBox(height: 6),
      ];

  Widget _sectionHeader(String title, {bool showRange = true}) =>
      Row(children: [
        Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800))),
        if (showRange)
          TextButton(
            onPressed: _selectWindow,
            style: TextButton.styleFrom(
                foregroundColor: lotteryThemeColor(context,
                    const Color(0xFF536780), AppTokens.textSecondaryDark),
                padding: const EdgeInsets.symmetric(horizontal: 6)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('最近 $window 期', style: const TextStyle(fontSize: 12)),
              const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
            ]),
          ),
      ]);

  Widget _latestCardPanel(Widget child) {
    if (widget.previewOnly) {
      return Container(
        key: const ValueKey('lottery-latest-card'),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: child,
      );
    }
    return Container(
      key: const ValueKey('lottery-latest-card'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            lotteryThemeColor(
                context, const Color(0xFFFAFCFF), AppTokens.surfaceDark),
            lotteryThemeColor(
                context, const Color(0xFFF0F6FF), AppTokens.surfaceDark),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: lotteryThemeColor(
              context, const Color(0xFFD8E6FC), AppTokens.borderDark),
        ),
        boxShadow: [
          BoxShadow(
            color: lotteryThemeColor(
                context, const Color(0x141A67C9), Colors.transparent),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: 6,
            bottom: 8,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: Theme.of(context).brightness == Brightness.dark
                      ? 0.14
                      : 0.20,
                  child: Image.asset(
                    'assets/lhc/latest_card_watermark.png',
                    key: const ValueKey('lottery-latest-watermark'),
                    width: 96,
                    height: 96,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _panel(Widget child) => widget.previewOnly
      ? Padding(padding: const EdgeInsets.all(10), child: child)
      : Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: lotteryThemeColor(
                  context, Colors.white, AppTokens.surfaceDark),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x050F274D),
                    blurRadius: 12,
                    offset: Offset(0, 3))
              ],
              border: Border.all(
                  color: lotteryThemeColor(context, const Color(0xFFE7EDF5),
                      AppTokens.surfaceAltDark))),
          child: child);
  Widget _tag(String text) {
    final accent = switch (text) {
      '单' || '小' || '蓝波' => _blue,
      '双' || '大' || '红波' => _red,
      '绿波' => _green,
      '金' => lotteryThemeColor(
          context, const Color(0xFF9A6700), const Color(0xFFFFC857)),
      '木' => lotteryThemeColor(
          context, const Color(0xFF008A4A), const Color(0xFF55D99A)),
      '水' => lotteryThemeColor(
          context, const Color(0xFF0066CC), const Color(0xFF76B6FF)),
      '火' => lotteryThemeColor(
          context, const Color(0xFFD72C48), const Color(0xFFFF788A)),
      '土' => lotteryThemeColor(
          context, const Color(0xFF8C5A36), const Color(0xFFD5A678)),
      _ => null,
    };
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
            color: accent?.withValues(alpha: .10) ??
                lotteryThemeColor(
                    context, const Color(0xFFF0F5FC), AppTokens.surfaceAltDark),
            borderRadius: BorderRadius.circular(6)),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                color: accent ??
                    lotteryThemeColor(context, const Color(0xFF536780),
                        AppTokens.textSecondaryDark),
                fontWeight:
                    accent != null ? FontWeight.w600 : FontWeight.normal)));
  }
}
