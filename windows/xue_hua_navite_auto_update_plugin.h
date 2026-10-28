#ifndef FLUTTER_PLUGIN_XUE_HUA_NAVITE_AUTO_UPDATE_PLUGIN_H_
#define FLUTTER_PLUGIN_XUE_HUA_NAVITE_AUTO_UPDATE_PLUGIN_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>
#include <string>
#include <vector>

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

  // Inspects the current Windows runtime environment.
  flutter::EncodableMap CheckEnvironment() const;

  // Streams and verifies the SHA-256 checksum of a file using Win32 BCrypt CNG.
  static bool VerifyFileSha256(const std::wstring& file_path,
                               const std::string& expected_hex);

 private:
  void HandleInstallAndRelaunch(
      const flutter::EncodableMap& args,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace xue_hua_navite_auto_update

#endif  // FLUTTER_PLUGIN_XUE_HUA_NAVITE_AUTO_UPDATE_PLUGIN_H_
