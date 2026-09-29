import 'dart:ffi';
import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/painting.dart';

const int _swpNoMove = 0x0002;
const int _swpNoActivate = 0x0010;
const int _dwmTransitionsForcedDisabled = 3;
const int _gwChild = 5;

final class _WinRect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

void applyWindowWidthKeepingOrigin(double width, double height) {
  if (!Platform.isWindows) {
    _fallback(width, height);
    return;
  }
  final hwnd = appWindow.handle;
  if (hwnd == null || hwnd == 0) {
    _fallback(width, height);
    return;
  }
  try {
    final user32 = DynamicLibrary.open('user32.dll');
    final dwmapi = DynamicLibrary.open('dwmapi.dll');
    final setWindowPos = user32.lookupFunction<
        Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
        int Function(int, int, int, int, int, int, int)>('SetWindowPos');
    final getWindow = user32.lookupFunction<IntPtr Function(IntPtr, Uint32),
        int Function(int, int)>('GetWindow');
    final getClientRect = user32.lookupFunction<
        Int32 Function(IntPtr, Pointer<_WinRect>),
        int Function(int, Pointer<_WinRect>)>('GetClientRect');
    final dwmSet = dwmapi.lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<Int32>, Uint32),
        int Function(int, int, Pointer<Int32>, int)>('DwmSetWindowAttribute');

    final flag = calloc<Int32>()..value = 1;
    dwmSet(hwnd, _dwmTransitionsForcedDisabled, flag, 4);

    final current = appWindow.rect;
    appWindow.rect = Rect.fromLTWH(
      current.left,
      current.top,
      width,
      height,
    );

    // bitsdojo 只在部分 WM_SIZE 路径里调 adjustChildWindowSize。
    // 外层加宽后必须把 Flutter 子窗铺满客户区，否则右边就是未绘制的黑块。
    final client = calloc<_WinRect>();
    getClientRect(hwnd, client);
    final childW = client.ref.right - client.ref.left;
    final childH = client.ref.bottom - client.ref.top;
    calloc.free(client);
    final child = getWindow(hwnd, _gwChild);
    if (child != 0 && childW > 0 && childH > 0) {
      setWindowPos(
        child,
        0,
        0,
        0,
        childW + 1,
        childH + 1,
        _swpNoMove | _swpNoActivate,
      );
      setWindowPos(
        child,
        0,
        0,
        0,
        childW,
        childH,
        _swpNoMove | _swpNoActivate,
      );
    }

    flag.value = 0;
    dwmSet(hwnd, _dwmTransitionsForcedDisabled, flag, 4);
    calloc.free(flag);
  } catch (_) {
    _fallback(width, height);
  }
}

void _fallback(double width, double height) {
  try {
    appWindow.alignment = null;
  } catch (_) {}
  try {
    final current = appWindow.rect;
    appWindow.rect = Rect.fromLTWH(current.left, current.top, width, height);
  } catch (_) {}
}
