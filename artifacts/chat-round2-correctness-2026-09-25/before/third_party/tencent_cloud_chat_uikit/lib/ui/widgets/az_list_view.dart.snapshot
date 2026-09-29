import 'package:azlistview_all_platforms/azlistview_all_platforms.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/directory_list_style.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme_view_model.dart';

class AZListViewContainer extends StatefulWidget {
  final List<ISuspensionBeanImpl>? memberList;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final Widget Function(BuildContext context, int index)? susItemBuilder;
  final bool isShowIndexBar;
  final bool subduedStyle;
  final double? cacheExtent;

  /// AzListView / ScrollablePositionedList 触底检测用（优先于 ScrollNotification）。
  final ItemPositionsListener? itemPositionsListener;
  final String Function(ISuspensionBeanImpl item)? itemIdentity;

  const AZListViewContainer(
      {Key? key,
      required this.memberList,
      required this.itemBuilder,
      this.isShowIndexBar = true,
      this.subduedStyle = false,
      this.cacheExtent,
      this.susItemBuilder,
      this.itemIdentity,
      this.itemPositionsListener})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _AZListViewContainerState();
}

class _AZListViewContainerState extends TIMUIKitState<AZListViewContainer> {
  List<ISuspensionBeanImpl>? _list;
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();
  int _updateGeneration = 0;

  addShowSuspension(List<ISuspensionBeanImpl> curList) {
    for (int i = 0; i < curList.length; i++) {
      if (i == 0 || curList[i].tagIndex != curList[i - 1].tagIndex) {
        curList[i].isShowSuspension = true;
      }
    }
    return curList;
  }

  void _hideSuspension(List<ISuspensionBeanImpl> curList) {
    for (final item in curList) {
      item.isShowSuspension = false;
    }
  }

  List<ISuspensionBeanImpl> _prepareList(List<ISuspensionBeanImpl> source) {
    final list = List<ISuspensionBeanImpl>.from(source);
    if (widget.isShowIndexBar) {
      return addShowSuspension(list);
    }
    _hideSuspension(list);
    return list;
  }

  static Widget getSusItem(BuildContext context, String tag,
      {double susHeight = 40,
      bool isDesktopScreen = false,
      bool subduedStyle = false}) {
    final theme = Provider.of<TUIThemeViewModel>(context).theme;
    return Container(
      height: subduedStyle ? susHeight : (isDesktopScreen ? 28 : susHeight),
      width: MediaQuery.of(context).size.width,
      padding: EdgeInsets.only(left: isDesktopScreen ? 20.0 : 16.0),
      color: subduedStyle
          ? (theme.weakBackgroundColor ?? Theme.of(context).colorScheme.surface)
          : Colors.transparent,
      alignment: Alignment.centerLeft,
      child: Text(
        tag,
        softWrap: true,
        style: TextStyle(
          fontSize: subduedStyle ? 12 : (isDesktopScreen ? 11.0 : 14.0),
          fontWeight: isDesktopScreen ? FontWeight.w600 : FontWeight.w400,
          letterSpacing: isDesktopScreen ? 0.4 : 0,
          color: subduedStyle
              ? (theme.weakTextColor ?? Colors.grey).withValues(alpha: 0.8)
              : theme.weakTextColor,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _list = _prepareList(widget.memberList!);
  }

  @override
  void didUpdateWidget(covariant AZListViewContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.memberList, widget.memberList) ||
        oldWidget.isShowIndexBar != widget.isShowIndexBar) {
      final identify = oldWidget.itemIdentity;
      final oldList = _list;
      String? anchor;
      var oldIndex = -1;
      var alignment = 0.0;
      if (identify != null && oldList != null) {
        final positions = (oldWidget.itemPositionsListener ?? _positions)
            .itemPositions
            .value
            .where((p) =>
                p.itemLeadingEdge >= 0 &&
                p.itemLeadingEdge < 1 &&
                p.index < oldList.length)
            .toList()
          ..sort((a, b) => a.index.compareTo(b.index));
        if (positions.isNotEmpty && positions.first.index > 0) {
          final first = positions.first;
          anchor = identify(oldList[first.index]);
          oldIndex = first.index;
          alignment = first.itemLeadingEdge;
        }
      }
      _list = _prepareList(widget.memberList!);
      final generation = ++_updateGeneration;
      final nextIdentity = widget.itemIdentity;
      if (anchor != null && nextIdentity != null) {
        final index = _list!.indexWhere((item) => nextIdentity(item) == anchor);
        if (index >= 0 && index != oldIndex) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                generation != _updateGeneration ||
                !_scrollController.isAttached) {
              return;
            }
            _scrollController.jumpTo(index: index, alignment: alignment);
          });
        }
      }
    }
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final isDesktopScreen =
        TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;
    return ChangeNotifierProvider.value(
        value: serviceLocator<TUIThemeViewModel>(),
        child: Consumer<TUIThemeViewModel>(
            builder: (context, tuiTheme, child) => Theme(
                  data: Theme.of(context).copyWith(
                    scrollbarTheme: ScrollbarThemeData(
                      thickness: WidgetStateProperty.all(
                        isDesktopScreen ? 6.0 : null,
                      ),
                      radius: const Radius.circular(4),
                      crossAxisMargin: isDesktopScreen ? 2 : 0,
                    ),
                  ),
                  child: AzListView(
                      cacheExtent: widget.cacheExtent,
                      physics: isDesktopScreen
                          ? const ClampingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            )
                          : const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                      data: _list!,
                      itemCount: _list!.length,
                      itemBuilder: widget.itemBuilder,
                      itemScrollController: _scrollController,
                      itemPositionsListener:
                          widget.itemPositionsListener ?? _positions,
                      // 无字母索引时去掉悬浮头占位，避免假高度干扰触底判断。
                      susItemHeight: widget.isShowIndexBar
                          ? (widget.subduedStyle
                              ? DirectoryListStyle.sectionHeight(context)
                              : kSusItemHeight)
                          : 0,
                      indexBarItemHeight: widget.subduedStyle
                          ? (MediaQuery.textScalerOf(context).scale(11) * 1.25 +
                                  2)
                              .clamp(16.0, double.infinity)
                          : kIndexBarItemHeight,
                      indexBarOptions: widget.subduedStyle
                          ? IndexBarOptions(
                              hapticFeedback: true,
                              textStyle: TextStyle(
                                  fontSize: 11,
                                  color: (tuiTheme.theme.weakTextColor ??
                                          Colors.grey)
                                      .withValues(alpha: 0.8)),
                              selectTextStyle: const TextStyle(
                                  fontSize: 11, color: Colors.white),
                              downTextStyle: const TextStyle(
                                  fontSize: 11, color: Colors.white),
                              selectItemDecoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: tuiTheme.theme.primaryColor ??
                                      Colors.blue),
                              downItemDecoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: tuiTheme.theme.primaryColor ??
                                      Colors.blue),
                            )
                          : IndexBarOptions(
                              hapticFeedback: true,
                              selectTextStyle: const TextStyle(color: Colors.white),
                              selectItemDecoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: tuiTheme.theme.primaryColor ?? Colors.blue,
                              ),
                            ),
                      indexBarData: (!isDesktopScreen && widget.isShowIndexBar)
                          ? SuspensionUtil.getTagIndexList(_list!)
                              .where((element) => element != "@")
                              .toList()
                          : [],
                      susItemBuilder: (BuildContext context, int index) {
                        if (!widget.isShowIndexBar) {
                          return const SizedBox.shrink();
                        }
                        if (widget.susItemBuilder != null) {
                          return widget.susItemBuilder!(context, index);
                        }
                        ISuspensionBeanImpl model = _list![index];
                        if (model.getSuspensionTag() == "@") {
                          return Container();
                        }
                        return getSusItem(
                          context,
                          model.getSuspensionTag(),
                          isDesktopScreen: isDesktopScreen,
                          subduedStyle: widget.subduedStyle,
                          susHeight: widget.subduedStyle
                              ? DirectoryListStyle.sectionHeight(context)
                              : kSusItemHeight,
                        );
                      }),
                )));
  }
}

class ISuspensionBeanImpl<T> extends ISuspensionBean {
  String tagIndex;
  T memberInfo;

  ISuspensionBeanImpl({required this.tagIndex, required this.memberInfo});

  @override
  String getSuspensionTag() => tagIndex;
}
