import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 桌面群直播观看小窗的全局尺寸与位置（不按群、不按场次）。
class GroupLiveWatchFloatPrefs {
  GroupLiveWatchFloatPrefs._();

  static final GroupLiveWatchFloatPrefs instance = GroupLiveWatchFloatPrefs._();

  static const String _leftKey = 'group_live_watch_float_v1:left';
  static const String _topKey = 'group_live_watch_float_v1:top';
  static const String _widthKey = 'group_live_watch_float_v1:width';

  Offset? _offsetCache;
  double? _widthCache;

  Offset? readOffsetSync() => _offsetCache;
  double? readWidthSync() => _widthCache;

  /// 在 runApp 前灌入内存，避免首帧按默认 320×180 绘制后再跳动。
  Future<void> preload() async {
    final prefs = await SharedPreferences.getInstance();
    final left = prefs.getDouble(_leftKey);
    final top = prefs.getDouble(_topKey);
    final width = prefs.getDouble(_widthKey);
    if (left == null ||
        top == null ||
        width == null ||
        !left.isFinite ||
        !top.isFinite ||
        !width.isFinite ||
        width <= 0) {
      _offsetCache = null;
      _widthCache = null;
      return;
    }
    _offsetCache = Offset(left, top);
    _widthCache = width;
  }

  Future<void> write({required Offset offset, required double width}) async {
    if (!offset.dx.isFinite ||
        !offset.dy.isFinite ||
        !width.isFinite ||
        width <= 0) {
      return;
    }
    _offsetCache = offset;
    _widthCache = width;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_leftKey, offset.dx);
    await prefs.setDouble(_topKey, offset.dy);
    await prefs.setDouble(_widthKey, width);
  }
}
