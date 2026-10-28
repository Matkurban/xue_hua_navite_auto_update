#ifndef FLUTTER_PLUGIN_XUE_HUA_NAVITE_AUTO_UPDATE_PLUGIN_H_
#define FLUTTER_PLUGIN_XUE_HUA_NAVITE_AUTO_UPDATE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace xue_hua_navite_auto_update {

class XueHuaNaviteAutoUpdatePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  XueHuaNaviteAutoUpdatePlugin();

  virtual ~XueHuaNaviteAutoUpdatePlugin();

  // Disallow copy and assign.
  XueHuaNaviteAutoUpdatePlugin(const XueHuaNaviteAutoUpdatePlugin&) = delete;
  XueHuaNaviteAutoUpdatePlugin& operator=(const XueHuaNaviteAutoUpdatePlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace xue_hua_navite_auto_update

#endif  // FLUTTER_PLUGIN_XUE_HUA_NAVITE_AUTO_UPDATE_PLUGIN_H_
