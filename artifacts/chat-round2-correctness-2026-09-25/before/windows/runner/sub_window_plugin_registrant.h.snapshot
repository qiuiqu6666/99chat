#ifndef RUNNER_SUB_WINDOW_PLUGIN_REGISTRANT_H_
#define RUNNER_SUB_WINDOW_PLUGIN_REGISTRANT_H_

#include <flutter/plugin_registry.h>

// Registers plugins for a desktop_multi_window child engine.
//
// Must stay in sync with windows/flutter/generated_plugin_registrant.cc,
// except:
// - DesktopMultiWindowPlugin (already registered internally)
// - BitsdojoWindowPlugin (process-level HWND singleton)
// - WebRTC / LiveKit / webview / drop / geolocator / local_auth (process
//   singletons; child live/media popouts use media_kit, not those plugins)
void RegisterSubWindowPlugins(flutter::PluginRegistry* registry);

#endif  // RUNNER_SUB_WINDOW_PLUGIN_REGISTRANT_H_
