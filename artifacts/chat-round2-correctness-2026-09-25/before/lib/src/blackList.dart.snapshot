// ignore_for_file: file_names

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/api/block_api.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/services/block_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_demo/src/user_profile.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_back_button.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_empty_state.dart';
import 'package:tencent_cloud_chat_demo/utils/profile_page_nav.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_demo/utils/user_api_error_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';

class BlackList extends StatefulWidget {
  const BlackList({Key? key}) : super(key: key);

  @override
  State<BlackList> createState() => _BlackListState();
}

class _BlackListState extends State<BlackList> {
  final List<BlockListItem> _items = <BlockListItem>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _nextStartIndex = 0;
  String? _error;
  String? _busyUserId;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _nextStartIndex = 0;
        _hasMore = false;
      });
    } else {
      if (_loadingMore || !_hasMore) {
        return;
      }
      setState(() => _loadingMore = true);
    }

    try {
      final page = await BlockApi.instance.list(
        startIndex: reset ? 0 : _nextStartIndex,
        limit: 50,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(page.items);
        } else {
          _items.addAll(page.items);
        }
        _hasMore = page.hasMore;
        _nextStartIndex = page.startIndex;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
      BlockLocalStore.instance.applyPage(page.items, replace: reset);
    } on DioError catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = UserApiErrorMessage.fromBlock(e);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = AppI18n.of(context).t(
          zhHans: '加载失败，请重试',
          zhHant: '載入失敗，請重試',
          en: 'Failed to load. Please try again.',
          ja: '読み込みに失敗しました。もう一度お試しください。',
          ko: '불러오기에 실패했습니다. 다시 시도해 주세요.',
        );
      });
    }
  }

  Future<void> _unblock(BlockListItem item) async {
    if (_busyUserId != null) {
      return;
    }
    final i18n = AppI18n.of(context);
    final confirmed = await AppDialog.confirm(
      title: i18n.t(
        zhHans: '移出黑名单',
        zhHant: '移出黑名單',
        en: 'Unblock',
        ja: 'ブロック解除',
        ko: '차단 해제',
      ),
      message: i18n.t(
        zhHans: '确定将 ${item.displayName} 移出黑名单？',
        zhHant: '確定將 ${item.displayName} 移出黑名單？',
        en: 'Unblock ${item.displayName}?',
        ja: '${item.displayName} のブロックを解除しますか？',
        ko: '${item.displayName}님을 차단 해제할까요?',
      ),
      confirmText: i18n.t(
        zhHans: '移出',
        zhHant: '移出',
        en: 'Unblock',
        ja: '解除',
        ko: '해제',
      ),
      cancelText: i18n.t(
        zhHans: '取消',
        zhHant: '取消',
        en: 'Cancel',
        ja: 'キャンセル',
        ko: '취소',
      ),
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _busyUserId = item.userId);
    try {
      await BlockLocalStore.instance.unblock(item.userId);
      if (!mounted) {
        return;
      }
      setState(() {
        _items.removeWhere((e) => e.userId == item.userId);
        _busyUserId = null;
      });
      ToastUtils.toast(i18n.t(
        zhHans: '已移出黑名单',
        zhHant: '已移出黑名單',
        en: 'Unblocked',
        ja: 'ブロック解除しました',
        ko: '차단 해제됨',
      ));
    } on DioError catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _busyUserId = null);
      ToastUtils.toast(UserApiErrorMessage.fromBlock(e));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _busyUserId = null);
      ToastUtils.toast(i18n.t(
        zhHans: '操作失败，请重试',
        zhHant: '操作失敗，請重試',
        en: 'Operation failed. Please try again.',
        ja: '操作に失敗しました。もう一度お試しください。',
        ko: '작업에 실패했습니다. 다시 시도해 주세요.',
      ));
    }
  }

  void _openProfile(BlockListItem item) {
    final isWideScreen =
        TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;
    if (isWideScreen) {
      ProfilePageNav.openUserProfile(
        context,
        userID: item.userId,
      );
      return;
    }
    Navigator.push(
      context,
      AppMaterialPageRoute(
        builder: (context) => UserProfile(userID: item.userId),
      ),
    );
  }

  Widget _buildList(Color cardColor, Color titleColor, Color subColor) {
    final i18n = AppI18n.of(context);
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 80) {
          _load(reset: false);
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _items.length + (_loadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _items.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final item = _items[index];
            final busy = _busyUserId == item.userId;
            return Dismissible(
              key: ValueKey('block-${item.userId}'),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) async {
                await _unblock(item);
                return false;
              },
              background: Container(
                color: AppColors.primaryRed,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: Text(
                  i18n.t(
                    zhHans: '移出',
                    zhHant: '移出',
                    en: 'Unblock',
                    ja: '解除',
                    ko: '해제',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              child: Material(
                color: cardColor,
                child: InkWell(
                  onTap: () => _openProfile(item),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: Avatar(
                            faceUrl: item.avatarUrl ?? '',
                            showName: item.displayName,
                            type: 1,
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              color: titleColor,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: busy ? null : () => _unblock(item),
                          child: busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  i18n.t(
                                    zhHans: '移出',
                                    zhHant: '移出',
                                    en: 'Unblock',
                                    ja: '解除',
                                    ko: '해제',
                                  ),
                                  style: TextStyle(
                                    color: subColor,
                                    fontSize: 14,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<DefaultThemeData>(context).theme;
    final i18n = AppI18n.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor =
        theme.conversationItemBgColor ?? AppColors.card(dark: isDark);
    final titleColor = theme.darkTextColor ?? AppColors.text(dark: isDark);
    final subColor = theme.weakTextColor ?? AppColors.subText(dark: isDark);
    final background =
        theme.weakBackgroundColor ?? AppColors.background(dark: isDark);

    Widget body;
    if (_loading) {
      body = const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (_error != null && _items.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: subColor),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => _load(reset: true),
                child: Text(i18n.t(
                  zhHans: '重试',
                  zhHant: '重試',
                  en: 'Retry',
                  ja: '再試行',
                  ko: '다시 시도',
                )),
              ),
            ],
          ),
        ),
      );
    } else if (_items.isEmpty) {
      body = AppEmptyState(
        message: i18n.t(
          zhHans: '暂无黑名单',
          zhHant: '暫無黑名單',
          en: 'No blocked users',
          ja: 'ブロック中のユーザーはいません',
          ko: '차단한 사용자가 없습니다',
        ),
      );
    } else {
      body = _buildList(cardColor, titleColor, subColor);
    }

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: Text(
          i18n.t(
            zhHans: '黑名单',
            zhHant: '黑名單',
            en: 'Blocklist',
            ja: 'ブロックリスト',
            ko: '차단 목록',
          ),
          style: TextStyle(
            color: theme.appbarTextColor ?? theme.darkTextColor ?? Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: theme.appbarBgColor ?? Colors.white,
        shadowColor: theme.weakDividerColor,
        iconTheme: IconThemeData(
          color: theme.primaryColor ?? const Color(0xFF1E90FF),
        ),
        leading: AppBackButton(
          color: theme.primaryColor ?? const Color(0xFF1E90FF),
        ),
      ),
      body: body,
    );
  }
}
