//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <xue_hua_file_operations/xue_hua_file_operations_plugin_c_api.h>
#include <xue_hua_navite_auto_update/xue_hua_navite_auto_update_plugin_c_api.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  XueHuaFileOperationsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("XueHuaFileOperationsPluginCApi"));
  XueHuaNaviteAutoUpdatePluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("XueHuaNaviteAutoUpdatePluginCApi"));
}
