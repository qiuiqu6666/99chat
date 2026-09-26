import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/create_group.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';

/// Introduction to broadcast channels. The CTA continues into Community creation.
class ChannelIntroPage extends StatelessWidget {
  const ChannelIntroPage({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: const Color(0x800A1526),
        builder: (_) => FractionallySizedBox(
          heightFactor: .9,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: const ChannelIntroPage(),
          ),
        ),
      );

  static const _blue = Color(0xFF207DF0);
  static const _ink = Color(0xFF101A29);
  static const _muted = Color(0xFF64748B);

  String _t(BuildContext context, String zh, String en) =>
      AppI18n.of(context).t(
        zhHans: zh,
        zhHant: zh,
        en: en,
        ja: en,
        ko: en,
      );

  void _startCreating(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.pop();
    showCreateChannelSheet(navigator.context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FCFF),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF6FAFF), Colors.white],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Navigation belongs to the sheet, not its scrolling artwork.
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('channel-intro-back'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon:
                        const Icon(Icons.arrow_back_ios_new_rounded, size: 21),
                    label: Text(_t(context, '返回', 'Back')),
                    style: TextButton.styleFrom(
                      foregroundColor: _blue,
                      minimumSize: const Size(88, 48),
                      visualDensity: VisualDensity.standard,
                      tapTargetSize: MaterialTapTargetSize.padded,
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: LayoutBuilder(builder: (context, constraints) {
                      final compact = constraints.maxHeight < 640;
                      final width = constraints.maxWidth;
                      final artworkSize =
                          (width - 24).clamp(0.0, 390.0).toDouble();
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: compact ? 12 : 18),
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                    text: _t(context, '什么是', 'What is a ')),
                                TextSpan(
                                  text: _t(context, '频道？', 'channel?'),
                                  style: const TextStyle(color: _blue),
                                ),
                              ]),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _ink,
                                fontSize: width < 370 ? 35 : 40,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _t(context, '频道是一个一对多的工具，可以将你的信息\n广播给无限的受众',
                                  'A channel broadcasts your content\nto an unlimited audience'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 15,
                                height: 1.45,
                              ),
                            ),
                            SizedBox(height: compact ? 4 : 8),
                            SizedBox(
                              height: artworkSize * (compact ? .80 : .88),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: const BoxDecoration(
                                        gradient: RadialGradient(
                                          colors: [
                                            Color(0xFFD3E9FF),
                                            Color(0xFFEAF5FF),
                                            Color(0x00FFFFFF),
                                          ],
                                          stops: [0, .60, 1],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Image.asset(
                                    'assets/img/channel_intro.png',
                                    fit: BoxFit.contain,
                                    width: artworkSize,
                                    height: artworkSize,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: compact ? 6 : 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _feature(
                                    context,
                                    Icons.image_rounded,
                                    const Color(0xFF3A94F7),
                                    const Color(0xFFE3F1FF),
                                    '图文内容',
                                    '分享精彩瞬间',
                                    'Posts',
                                    'Share moments'),
                                _feature(
                                    context,
                                    Icons.play_arrow_rounded,
                                    const Color(0xFF9855EA),
                                    const Color(0xFFF1E8FF),
                                    '视频发布',
                                    '支持高清播放',
                                    'Videos',
                                    'Play in HD'),
                                _feature(
                                    context,
                                    Icons.people_alt_rounded,
                                    const Color(0xFFF5AA1F),
                                    const Color(0xFFFFF4E0),
                                    '无限订阅',
                                    '没有人数上限',
                                    'Subscribers',
                                    'No limit'),
                                _feature(
                                    context,
                                    Icons.bar_chart_rounded,
                                    const Color(0xFF20BFA3),
                                    const Color(0xFFE0F9F3),
                                    '数据统计',
                                    '了解内容表现',
                                    'Insights',
                                    'Track reach'),
                              ],
                            ),
                            SizedBox(height: compact ? 16 : 20),
                            SizedBox(
                              height: 52,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [
                                    Color(0xFF359AF4),
                                    Color(0xFF1775ED),
                                  ]),
                                  borderRadius: BorderRadius.circular(15),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x22207DF0),
                                      blurRadius: 14,
                                      offset: Offset(0, 7),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    key: const ValueKey('channel-intro-create'),
                                    borderRadius: BorderRadius.circular(15),
                                    onTap: () => _startCreating(context),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            _t(context, '创建频道',
                                                'Create Channel'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.arrow_forward_rounded,
                                            color: Colors.white, size: 25),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _feature(
      BuildContext context,
      IconData icon,
      Color iconColor,
      Color background,
      String zhTitle,
      String zhSubtitle,
      String enTitle,
      String enSubtitle) {
    return Expanded(
      child: Column(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: iconColor, size: 26),
        ),
        const SizedBox(height: 6),
        Text(_t(context, zhTitle, enTitle),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: _ink, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(_t(context, zhSubtitle, enSubtitle),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 10)),
      ]),
    );
  }
}
