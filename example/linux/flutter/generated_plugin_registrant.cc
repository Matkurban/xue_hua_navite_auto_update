//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <xue_hua_file_operations/xue_hua_file_operations_plugin.h>
#include <xue_hua_navite_auto_update/xue_hua_navite_auto_update_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) xue_hua_file_operations_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "XueHuaFileOperationsPlugin");
  xue_hua_file_operations_plugin_register_with_registrar(xue_hua_file_operations_registrar);
  g_autoptr(FlPluginRegistrar) xue_hua_navite_auto_update_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "XueHuaNaviteAutoUpdatePlugin");
  xue_hua_navite_auto_update_plugin_register_with_registrar(xue_hua_navite_auto_update_registrar);
}
