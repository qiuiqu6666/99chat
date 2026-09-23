import 'favorite_list_page.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/models/favorite_message_models.dart';
import 'package:tencent_cloud_chat_demo/src/pages/favorites/widgets/favorite_media_preview.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_empty_state.dart';
import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/api/favorite_message_api.dart';
import 'package:tencent_cloud_chat_demo/utils/favorite_message_chat_sender.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_chat_controller.dart';

/// 聊天「更多」面板：选择收藏并发送到当前会话。
class FavoritePickerSheet extends StatefulWidget {
  const FavoritePickerSheet({
    super.key,
    required this.chatController,
    required this.convId,
    required this.convType,
  });

  final TIMUIKitChatController chatController;
  final String convId;
  final ConvType convType;

  static Future<void> show(
    BuildContext context, {
    required TIMUIKitChatController chatController,
    required String convId,
    required ConvType convType,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FavoritePickerSheet(
        chatController: chatController,
        convId: convId,
        convType: convType,
      ),
    );
  }

  @override
  State<FavoritePickerSheet> createState() => _FavoritePickerSheetState();
}

class _FavoritePickerSheetState extends State<FavoritePickerSheet> {
  List<FavoriteMessageItem> _items = [];
  bool _loading = true;
  bool _sending = false;
  String? _sendingId;
  FavoriteMessageType? _filter;
  bool _searching = false;
  String _query = '';

  String _label(String zh, String en) =>
      AppI18n.of(context).t(zhHans: zh, zhHant: zh, en: en, ja: en, ko: en);

  Future<void> _openManager() async {
    await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const FavoriteListPage()));
    if (mounted) await _load();
  }

  Widget _filterChip(FavoriteMessageType? type, String label, bool dark) {
    final count = type == null
        ? _items.length
        : _items.where((e) => e.type == type).length;
    final active = _filter == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('$label ($count)'),
        selected: active,
        showCheckmark: false,
        onSelected: (_) => setState(() => _filter = type),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        backgroundColor:
            dark ? const Color(0xFF292D35) : const Color(0xFFF2F4F7),
        selectedColor: dark ? const Color(0xFF20344D) : const Color(0xFFEBF3FF),
        labelStyle: TextStyle(
            color:
                active ? AppColors.primaryBlue : AppColors.subText(dark: dark),
            fontWeight: active ? FontWeight.w600 : FontWeight.w400),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await FavoriteMessageApi.instance.listAll();
      if (!mounted) return;
      setState(() {
        _items = items..sort((a, b) => b.favoritedAt.compareTo(a.favoritedAt));
        _loading = false;
      });
    } on DioError catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ToastUtils.toast(FavoriteMessageApi.errorMessage(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _openTextPreview(FavoriteMessageItem item) {
    final text = item.text?.trim() ?? '';
    if (text.isEmpty) {
      return;
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final i18n = AppI18n.of(ctx);
        final maxHeight = MediaQuery.sizeOf(ctx).height * 0.75;
        return Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: AppColors.card(dark: dark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line(dark: dark),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        i18n.t(
                          zhHans: '全文',
                          zhHant: '全文',
                          en: 'Full Text',
                          ja: '全文',
                          ko: '전체 텍스트',
                        ),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text(dark: dark),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(
                        Icons.close,
                        color: AppColors.subText(dark: dark),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 0.6, color: AppColors.line(dark: dark)),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: SelectableText(
                    text,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.55,
                      color: AppColors.text(dark: dark),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _sending
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _sendItem(item);
                            },
                      icon: const Icon(Icons.send_rounded, size: 20),
                      label: Text(i18n.t(
                        zhHans: '发送',
                        zhHant: '發送',
                        en: 'Send',
                        ja: '送信',
                        ko: '보내기',
                      )),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendItem(FavoriteMessageItem item) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _sendingId = item.id;
    });
    try {
      final ok = await FavoriteMessageChatSender.send(
        item: item,
        chatController: widget.chatController,
        convId: widget.convId,
        convType: widget.convType,
      );
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context);
        ToastUtils.toast(AppI18n.current.t(
          zhHans: '已发送',
          zhHant: '已發送',
          en: 'Sent',
          ja: '送信しました',
          ko: '전송됨',
        ));
      } else {
        ToastUtils.toast(AppI18n.current.t(
          zhHans: '发送失败',
          zhHant: '發送失敗',
          en: 'Failed to send',
          ja: '送信に失敗しました',
          ko: '전송 실패',
        ));
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _sendingId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final query = _query.trim().toLowerCase();
    final visible = _items
        .where((item) =>
            (_filter == null || item.type == _filter) &&
            (query.isEmpty ||
                '${item.listPreview} ${item.sourceSenderName ?? ''} ${item.sourceConvLabel ?? ''}'
                    .toLowerCase()
                    .contains(query)))
        .toList();
    final muted = AppColors.subText(dark: dark);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.78),
        decoration: BoxDecoration(
            color: AppColors.card(dark: dark),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24))),
        child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 12),
              Container(
                  width: 38,
                  height: 5,
                  decoration: BoxDecoration(
                      color: dark
                          ? const Color(0xFF555D6B)
                          : const Color(0xFFD1D7E1),
                      borderRadius: BorderRadius.circular(3))),
              Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 10, 8),
                  child: Row(children: [
                    Expanded(
                        child: Text(_label('收藏', 'Favorites'),
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: AppColors.text(dark: dark)))),
                    IconButton(
                        tooltip: MaterialLocalizations.of(context)
                            .closeButtonTooltip,
                        onPressed: () => Navigator.pop(context),
                        icon:
                            Icon(Icons.close_rounded, color: muted, size: 27)),
                  ])),
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 10),
                  child: Row(children: [
                    Expanded(
                        child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: [
                              _filterChip(null, _label('全部', 'All'), dark),
                              _filterChip(FavoriteMessageType.text,
                                  _label('文字', 'Text'), dark),
                              _filterChip(FavoriteMessageType.image,
                                  _label('图片', 'Images'), dark),
                              if (_items.any(
                                  (e) => e.type == FavoriteMessageType.video))
                                _filterChip(FavoriteMessageType.video,
                                    _label('视频', 'Videos'), dark),
                            ]))),
                    IconButton(
                        tooltip: _label('搜索收藏', 'Search favorites'),
                        onPressed: () => setState(() {
                              _searching = !_searching;
                              if (!_searching) _query = '';
                            }),
                        icon:
                            Icon(Icons.search_rounded, size: 26, color: muted)),
                    IconButton(
                        tooltip: _label('管理收藏', 'Manage favorites'),
                        onPressed: _sending ? null : _openManager,
                        icon: Icon(Icons.checklist_rounded,
                            size: 26, color: muted)),
                  ])),
              if (_searching)
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: TextField(
                        autofocus: true,
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                            hintText:
                                _label('搜索内容或来源', 'Search content or source'),
                            prefixIcon: const Icon(Icons.search),
                            isDense: true,
                            filled: true,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none)))),
              Flexible(
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : visible.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(28),
                              child: AppEmptyState(
                                  message: _items.isEmpty
                                      ? _label('暂无收藏', 'No favorites yet')
                                      : _label(
                                          '没有匹配的收藏', 'No matching favorites'),
                                  imageWidth: 100))
                          : ListView.separated(
                              shrinkWrap: true,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              itemCount: visible.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = visible[index];
                                return _FavoritePickerTile(
                                    item: item,
                                    dark: dark,
                                    sending: _sending && _sendingId == item.id,
                                    onTap: _sending
                                        ? null
                                        : () {
                                            if (item.type ==
                                                FavoriteMessageType.text) {
                                              _openTextPreview(item);
                                            } else {
                                              _sendItem(item);
                                            }
                                          },
                                    onSend:
                                        _sending ? null : () => _sendItem(item),
                                    onViewFullText:
                                        item.type == FavoriteMessageType.text
                                            ? () => _openTextPreview(item)
                                            : null);
                              })),
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                      '—  ${_label('已收藏', 'Saved')} ${_items.length} ${_label('条内容', 'items')}  —',
                      style: TextStyle(
                          fontSize: 13, color: muted.withValues(alpha: 0.72)))),
            ])),
      ),
    );
  }
}

class _FavoritePickerTile extends StatelessWidget {
  const _FavoritePickerTile({
    required this.item,
    required this.dark,
    required this.onTap,
    this.onSend,
    this.onViewFullText,
    this.sending = false,
  });

  final FavoriteMessageItem item;
  final bool dark;
  final VoidCallback? onTap;
  final VoidCallback? onSend;
  final VoidCallback? onViewFullText;
  final bool sending;

  @override
  Widget build(BuildContext context) {
    final isText = item.type == FavoriteMessageType.text;
    final muted = AppColors.subText(dark: dark);
    final i18n = AppI18n.of(context);
    final sendLabel =
        i18n.t(zhHans: '发送', zhHant: '發送', en: 'Send', ja: '送信', ko: '보내기');
    return Material(
      color: dark ? const Color(0xFF252A33) : const Color(0xFFF6F8FB),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (isText)
                Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: dark
                            ? const Color(0xFF20344D)
                            : const Color(0xFFECF2FF),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.title_rounded,
                        color: Color(0xFF568EFF), size: 27))
              else
                ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                        width: 76,
                        height: 68,
                        child: Stack(fit: StackFit.expand, children: [
                          FavoriteMediaPreview(
                              pathOrUrl: item.displayThumbPathOrUrl,
                              dark: dark,
                              fit: BoxFit.cover),
                          if (item.type == FavoriteMessageType.video)
                            const Center(
                                child: Icon(Icons.play_circle_fill,
                                    color: Colors.white, size: 28)),
                        ]))),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(item.listPreview,
                        maxLines: isText ? 4 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15,
                            height: 1.4,
                            color: AppColors.text(dark: dark))),
                    const SizedBox(height: 7),
                    Text(_sourceLine(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: muted)),
                    const SizedBox(height: 5),
                    Text(
                        DateFormat('yyyy-MM-dd HH:mm')
                            .format(item.favoritedAt.toLocal()),
                        style: TextStyle(fontSize: 12, color: muted)),
                  ])),
              const SizedBox(width: 4),
              Column(children: [
                PopupMenuButton<String>(
                    enabled: onSend != null,
                    icon: Icon(Icons.more_horiz, color: muted),
                    padding: EdgeInsets.zero,
                    onSelected: (action) {
                      if (action == 'send') {
                        onSend?.call();
                      } else {
                        onViewFullText?.call();
                      }
                    },
                    itemBuilder: (_) => [
                          if (onViewFullText != null)
                            PopupMenuItem(
                                value: 'view',
                                child: Text(i18n.t(
                                    zhHans: '查看全文',
                                    zhHant: '查看全文',
                                    en: 'View full text',
                                    ja: '全文を見る',
                                    ko: '전체 보기'))),
                          PopupMenuItem(value: 'send', child: Text(sendLabel)),
                        ]),
                const SizedBox(height: 8),
                SizedBox(
                    width: 32,
                    height: 32,
                    child: sending
                        ? const Padding(
                            padding: EdgeInsets.all(7),
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: sendLabel,
                            style: IconButton.styleFrom(
                                backgroundColor: dark
                                    ? const Color(0xFF323D50)
                                    : const Color(0xFFE9EFFA)),
                            onPressed: onSend,
                            icon: Icon(Icons.chevron_right_rounded,
                                color: muted, size: 26))),
              ]),
            ]),
          )),
    );
  }

  String _sourceLine(BuildContext context) {
    final i18n = AppI18n.of(context);
    final sender = item.sourceSenderName?.trim() ?? '';
    final conv = item.sourceConvLabel?.trim() ?? '';
    final parts = <String>[];
    if (sender.isNotEmpty) parts.add(sender);
    if (conv.isNotEmpty && conv != sender) parts.add(conv);
    final source = parts.isEmpty
        ? i18n.t(
            zhHans: '手动添加',
            zhHant: '手動新增',
            en: 'Manual',
            ja: '手動追加',
            ko: '직접 추가',
          )
        : parts.join(' · ');
    return '${i18n.t(
      zhHans: '来源',
      zhHant: '來源',
      en: 'Source',
      ja: 'ソース',
      ko: '출처',
    )}：$source';
  }
}
