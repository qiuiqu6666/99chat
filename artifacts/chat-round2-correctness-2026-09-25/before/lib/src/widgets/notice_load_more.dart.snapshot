import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';

/// Only user scrolling (or an explicit tap) requests the next batch.
/// Layout changes and loading a short first page never drain the remote list.
class NoticeLoadMore extends StatefulWidget {
  const NoticeLoadMore({
    super.key,
    required this.child,
    required this.hasMore,
    required this.loading,
    required this.onLoadMore,
    this.error = false,
  });

  final Widget child;
  final bool hasMore;
  final bool loading;
  final bool error;
  final Future<void> Function() onLoadMore;

  @override
  State<NoticeLoadMore> createState() => _NoticeLoadMoreState();

  Widget footer(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (!hasMore && !error) return const SizedBox(height: 16);
    final i18n = AppI18n.of(context);
    return Center(
        child: TextButton(
      onPressed: onLoadMore,
      child: Text(error
          ? i18n.t(
              zhHans: '加载失败，点击重试',
              zhHant: '載入失敗，點擊重試',
              en: 'Could not load. Tap to retry',
              ja: '再試行',
              ko: '다시 시도')
          : i18n.t(
              zhHans: '加载更多',
              zhHant: '載入更多',
              en: 'Load more',
              ja: 'さらに表示',
              ko: '더 보기')),
    ));
  }
}

class _NoticeLoadMoreState extends State<NoticeLoadMore> {
  bool _requesting = false;

  Future<void> _load() async {
    if (_requesting) return;
    _requesting = true;
    try {
      await widget.onLoadMore();
    } finally {
      // ScrollUpdate and Overscroll can arrive before the parent's loading
      // state rebuild. Keep the latch until that frame has finished.
      WidgetsBinding.instance.addPostFrameCallback((_) => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final userScroll = notification is ScrollUpdateNotification &&
                (notification.scrollDelta ?? 0) > 0 ||
            notification is OverscrollNotification &&
                notification.overscroll > 0;
        if (notification.depth == 0 &&
            userScroll &&
            notification.metrics.extentAfter < 160 &&
            widget.hasMore &&
            !widget.loading &&
            !widget.error) {
          unawaited(_load());
        }
        return false;
      },
      child: widget.child,
    );
  }
}
