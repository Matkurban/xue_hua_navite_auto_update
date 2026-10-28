#include "include/xue_hua_navite_auto_update/xue_hua_navite_auto_update_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "xue_hua_navite_auto_update_plugin.h"

void XueHuaNaviteAutoUpdatePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  xue_hua_navite_auto_update::XueHuaNaviteAutoUpdatePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
