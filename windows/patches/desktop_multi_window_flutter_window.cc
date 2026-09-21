// Patched copy of desktop_multi_window 0.2.1 windows/flutter_window.cc.
// Closing a subwindow must not destroy the child Flutter engine: tearing it
// down and creating a second one crashes this process (plugin WndProc /
// use-after-free in WM_DESTROY). Hide instead; the Dart singleton reuses it.
// WM_CLOSE and WM_SYSCOMMAND/SC_CLOSE are intercepted before
// HandleTopLevelWindowProc so Flutter does not tear down the view
// (title-bar X then reopen would paint black).

#include "flutter_window.h"

#include "flutter_windows.h"

#include "tchar.h"

#include <iostream>
#include <utility>

#include "include/desktop_multi_window/desktop_multi_window_plugin.h"
#include "multi_window_plugin_internal.h"

namespace {

WindowCreatedCallback _g_window_created_callback = nullptr;

TCHAR kFlutterWindowClassName[] = _T("FlutterMultiWindow");

int32_t class_registered_ = 0;

void RegisterWindowClass(WNDPROC wnd_proc) {
  if (class_registered_ == 0) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kFlutterWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, IDI_APPLICATION);
    window_class.hbrBackground = (HBRUSH) (COLOR_WINDOW + 1);
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = wnd_proc;
    RegisterClass(&window_class);
  }
  class_registered_++;
}

void UnregisterWindowClass() {
  class_registered_--;
  if (class_registered_ != 0) {
    return;
  }
  UnregisterClass(kFlutterWindowClassName, nullptr);
}

inline int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

void ResizeFlutterChild(HWND parent, HWND child) {
  if (!parent || !child) {
    return;
  }
  RECT rect;
  GetClientRect(parent, &rect);
  if (rect.right <= rect.left || rect.bottom <= rect.top) {
    return;
  }
  MoveWindow(child, rect.left, rect.top, rect.right - rect.left,
             rect.bottom - rect.top, TRUE);
}

bool IsWindowCloseMessage(UINT message, WPARAM wparam) {
  if (message == WM_CLOSE) {
    return true;
  }
  // Title-bar X sends WM_SYSCOMMAND/SC_CLOSE before WM_CLOSE. Flutter's
  // embedding tears down the view if it sees this first.
  return message == WM_SYSCOMMAND && (wparam & 0xFFF0) == SC_CLOSE;
}

void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling *>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
    FreeLibrary(user32_module);
  }
}

}

FlutterWindow::FlutterWindow(
    int64_t id,
    std::string args,
    const std::shared_ptr<FlutterWindowCallback> &callback
) : callback_(callback), id_(id), window_handle_(nullptr), scale_factor_(1) {
  RegisterWindowClass(FlutterWindow::WndProc);

  const POINT target_point = {static_cast<LONG>(10),
                              static_cast<LONG>(10)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  scale_factor_ = dpi / 96.0;

  HWND window_handle = CreateWindow(
      kFlutterWindowClassName, L"", WS_OVERLAPPEDWINDOW,
      Scale(target_point.x, scale_factor_), Scale(target_point.y, scale_factor_),
      Scale(1280, scale_factor_), Scale(720, scale_factor_),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  RECT frame;
  GetClientRect(window_handle, &frame);
  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments({"multi_window", std::to_string(id), std::move(args)});
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    std::cerr << "Failed to setup FlutterViewController." << std::endl;
  }
  auto view_handle = flutter_controller_->view()->GetNativeWindow();
  SetParent(view_handle, window_handle);
  MoveWindow(view_handle, 0, 0, frame.right - frame.left, frame.bottom - frame.top, true);

  InternalMultiWindowPluginRegisterWithRegistrar(
      flutter_controller_->engine()->GetRegistrarForPlugin("DesktopMultiWindowPlugin"));
  window_channel_ = WindowChannel::RegisterWithRegistrar(
      flutter_controller_->engine()->GetRegistrarForPlugin("DesktopMultiWindowPlugin"), id_);

  if (_g_window_created_callback) {
    _g_window_created_callback(flutter_controller_.get());
  }

  ShowWindow(window_handle, SW_HIDE);

}

FlutterWindow *FlutterWindow::GetThisFromHandle(HWND window) noexcept {
  return reinterpret_cast<FlutterWindow *>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

LRESULT CALLBACK FlutterWindow::WndProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT *>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<FlutterWindow *>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (FlutterWindow *that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  // Title-bar X / Alt+F4 must not reach Flutter first. The embedding treats
  // close as tearing down this view; hide+show then paints a black client.
  if (IsWindowCloseMessage(message, wparam)) {
    if (auto callback = callback_.lock()) {
      callback->OnWindowClose(id_);
    }
    ShowWindow(hwnd, SW_HIDE);
    return 0;
  }

  std::optional<LRESULT> flutter_result;
  if (flutter_controller_) {
    flutter_result = flutter_controller_->HandleTopLevelWindowProc(
        hwnd, message, wparam, lparam);
  }

  auto child_content_ = flutter_controller_ && flutter_controller_->view()
      ? flutter_controller_->view()->GetNativeWindow()
      : nullptr;

  if (message == WM_SHOWWINDOW && wparam == TRUE && window_handle_) {
    ResizeFlutterChild(window_handle_, child_content_);
    InvalidateRect(hwnd, nullptr, TRUE);
    if (child_content_ != nullptr) {
      InvalidateRect(child_content_, nullptr, TRUE);
    }
  }

  if (flutter_result) {
    return *flutter_result;
  }

  switch (message) {
    case WM_FONTCHANGE: {
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
    }
    case WM_DESTROY: {
      if (destroyed_) {
        return 0;
      }
      destroyed_ = true;
      window_handle_ = nullptr;
      window_channel_ = nullptr;
      flutter_controller_ = nullptr;
      if (auto callback = callback_.lock()) {
        callback->OnWindowDestroy(id_);
      }
      return 0;
    }
    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT *>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      ResizeFlutterChild(window_handle_, child_content_);
      return 0;
    }

    case WM_ACTIVATE: {
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;
    }
    default: break;
  }

  return DefWindowProc(window_handle_ ? window_handle_ : hwnd, message, wparam, lparam);
}

void FlutterWindow::Destroy() {
  if (destroyed_) {
    return;
  }
  HWND handle = window_handle_;
  window_handle_ = nullptr;
  window_channel_ = nullptr;
  flutter_controller_ = nullptr;
  if (handle) {
    DestroyWindow(handle);
  }
}

FlutterWindow::~FlutterWindow() {
  if (window_handle_) {
    std::cout << "window_handle leak." << std::endl;
  }
  UnregisterWindowClass();
}

void DesktopMultiWindowSetWindowCreatedCallback(WindowCreatedCallback callback) {
  _g_window_created_callback = callback;
}
