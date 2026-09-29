import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/utils/sticker_panel_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/provider/user_sticker_provider.dart';
import 'package:tencent_cloud_chat_demo/utils/sticker_constants.dart';
import 'package:tencent_cloud_chat_demo/utils/sticker_panel_packages.dart';
import 'package:tencent_cloud_chat_demo/utils/sticker_send_helper.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/sticker/sticker_my_collection_grid.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/sticker/sticker_panel_theme.dart';
import 'package:tencent_cloud_chat_demo/src/pages/sticker/sticker_pack_preview_page.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/sticker/sticker_panel_long_press_preview.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/sticker/wechat_sticker_bottom_bar.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';

/// 微信风格表情面板：顶部包切换 + 主区域网格（收藏与我的上传同一 Tab）。
class StickerChatPanel {
  StickerChatPanel._();

  static const double defaultHeight = 248;
  static const double bottomBarHeight = 40;

  static Widget build({
    required BuildContext context,
    required StickerPanelConfig stickerPanelConfig,
    required void Function() sendTextMessage,
    required void Function(int index, String data) sendFaceMessage,
    required void Function() deleteText,
    required void Function(int unicode) addText,
    required void Function(String singleEmojiName) addCustomEmojiText,
    List<CustomEmojiFaceData> defaultCustomEmojiStickerList = const [],
    double? height,
    double? width,
  }) {
    return _WeChatStickerPanel(
      stickerPanelConfig: stickerPanelConfig,
      sendFaceMessage: sendFaceMessage,
      deleteText: deleteText,
      addText: addText,
      addCustomEmojiText: addCustomEmojiText,
      height: height ?? defaultHeight,
      width: width,
    );
  }
}

class _WeChatStickerPanel extends StatefulWidget {
  const _WeChatStickerPanel({
    required this.stickerPanelConfig,
    required this.sendFaceMessage,
    required this.deleteText,
    required this.addText,
    required this.addCustomEmojiText,
    required this.height,
    this.width,
  });

  final StickerPanelConfig stickerPanelConfig;
  final void Function(int index, String data) sendFaceMessage;
  final void Function() deleteText;
  final void Function(int unicode) addText;
  final void Function(String singleEmojiName) addCustomEmojiText;
  final double height;
  final double? width;

  @override
  State<_WeChatStickerPanel> createState() => _WeChatStickerPanelState();
}

class _WeChatStickerPanelState extends State<_WeChatStickerPanel> {
  String? _selectedPackName;
  bool _selectionChanged = false;
  List<CustomStickerPackage> _allPackages = [];

  int get _selectedPackIndex => StickerPanelTabStore.indexFor(
        _allPackages.map((pack) => pack.name).toList(),
        _selectedPackName,
      );

  Future<void> _restoreSelectedTab() async {
    await StickerPanelTabStore.instance.load();
    if (!mounted || _selectionChanged) return;
    setState(() {
      _selectedPackName = StickerPanelTabStore.instance.selectedName;
    });
  }

  @override
  void initState() {
    super.initState();
    UserStickerProvider.shared.addListener(_onProviderChanged);
    _allPackages = _loadPackages();
    _selectedPackName = StickerPanelTabStore.instance.selectedName;
    unawaited(_restoreSelectedTab());
    if (!UserStickerProvider.shared.loaded) {
      UserStickerProvider.shared.refresh(force: true);
    }
  }

  @override
  void dispose() {
    UserStickerProvider.shared.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _allPackages = _loadPackages();
    });
  }

  List<CustomStickerPackage> _loadPackages() {
    final provider = UserStickerProvider.shared;
    return buildWeChatStickerPanelPackages(
      widget.stickerPanelConfig,
      favorites: provider.favorites,
      extraServerPacks: provider.serverPacks
          .where(
            (p) =>
                p.stickers.isNotEmpty &&
                !StickerConstants.serverFavoritesPackIds.contains(p.packId),
          )
          .toList(),
    );
  }

  void _openPackPreview(int index) {
    if (index < 0 || index >= _allPackages.length) {
      return;
    }
    final pack = _allPackages[index];
    StickerPackPreviewPage.open(
      context,
      pack: pack,
      sendFaceMessage: _wrapSendFace,
      deleteText: widget.deleteText,
      addText: widget.addText,
      addCustomEmojiText: widget.addCustomEmojiText,
    );
  }

  void _wrapSendFace(int index, String data) {
    final trimmed = data.trim();
    if (trimmed.startsWith('stk_')) {
      final item = UserStickerProvider.shared.findStickerById(trimmed);
      if (item != null) {
        StickerSendHelper.sendViaPanelCallback(
          widget.sendFaceMessage,
          stickerId: trimmed,
          thumbUrl: item.thumbUrl,
          originUrl: item.originUrl,
          mediaType: item.mediaType,
        );
        return;
      }
    }
    if (StickerSendHelper.isDynamicStickerData(data)) {
      final stickerId = data.startsWith(StickerConstants.stickerDataScheme)
          ? data.substring(StickerConstants.stickerDataScheme.length)
          : null;
      if (stickerId != null) {
        final item = UserStickerProvider.shared.findStickerById(stickerId);
        if (item != null) {
          StickerSendHelper.sendViaPanelCallback(
            widget.sendFaceMessage,
            stickerId: stickerId,
            thumbUrl: item.thumbUrl,
            originUrl: item.originUrl,
            mediaType: item.mediaType,
          );
          return;
        }
      }
    }
    widget.sendFaceMessage(index, data);
  }

  @override
  Widget build(BuildContext context) {
    final panelTheme = StickerPanelTheme.of(context);

    if (_allPackages.isEmpty) {
      return SizedBox(
        height: widget.height,
        width: widget.width ?? double.infinity,
        child: ColoredBox(
          color: panelTheme.panelBackground,
          child: Center(
            child: Text(
              AppI18n.of(context).t(
                zhHans: '暂无表情',
                zhHant: '暫無表情',
                en: 'No stickers yet',
                ja: 'スタンプがありません',
                ko: '스티커가 없습니다',
              ),
              style: TextStyle(
                color: panelTheme.emptyHintTextColor,
                fontSize: 14,
              ),
            ),
          ),
        ),
      );
    }

    final currentPack = _allPackages[_selectedPackIndex];
    final isMyCollectionTab =
        currentPack.name == StickerConstants.virtualPackFavorites;
    // 背景铺满底部安全区，内容与删除键上移，避免被 Home 指示条遮挡。
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return ColoredBox(
      color: panelTheme.panelBackground,
      child: SizedBox(
        height: widget.height,
        width: widget.width ?? double.infinity,
        child: Column(
          children: [
            WeChatStickerBottomBar(
              packages: _allPackages,
              selectedIndex: _selectedPackIndex,
              onSelected: (index) {
                final name = _allPackages[index].name;
                setState(() {
                  _selectionChanged = true;
                  _selectedPackName = name;
                });
                unawaited(StickerPanelTabStore.instance.select(name));
              },
              onPackPreview: _openPackPreview,
              height: StickerChatPanel.bottomBarHeight,
              panelTheme: panelTheme,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final gridHeight = constraints.maxHeight;
                  return isMyCollectionTab
                      ? StickerMyCollectionGrid(
                          key: const ValueKey(
                            StickerConstants.virtualPackFavorites,
                          ),
                          pack: currentPack,
                          height: gridHeight,
                          width: widget.width,
                          sendFaceMsg: _wrapSendFace,
                          panelTheme: panelTheme,
                          showDeleteButton: false,
                          bottomPadding: bottomInset,
                        )
                      : StickerPanel(
                          key: ValueKey(currentPack.name),
                          isWideScreen: false,
                          height: gridHeight,
                          width: widget.width ?? double.infinity,
                          panelPadding:
                              EdgeInsets.fromLTRB(0, 12, 0, bottomInset),
                          showBottomContainer: false,
                          sendTextMsg: null,
                          sendFaceMsg: _wrapSendFace,
                          deleteText: widget.deleteText,
                          addText: widget.addText,
                          addCustomEmojiText: widget.addCustomEmojiText,
                          customStickerPackageList: [currentPack],
                          backgroundColor: panelTheme.panelBackground,
                          bottomColor: panelTheme.bottomBarBackground,
                          lightPrimaryColor: panelTheme.selectedTabColor,
                          showDeleteButton: true,
                          crossAxisCount:
                              StickerConstants.panelCrossAxisCountForPack(
                            currentPack.name,
                          ),
                          onLongTap: (context, layerLink, packIdx, sticker) {
                            StickerPanelLongPressPreview.show(
                              context: context,
                              layerLink: layerLink,
                              sticker: sticker,
                            );
                          },
                          onLongPressEnd: StickerPanelLongPressPreview.hide,
                        );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
