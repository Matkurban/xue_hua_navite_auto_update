#ifndef FLUTTER_PLUGIN_XUE_HUA_NAVITE_AUTO_UPDATE_PLUGIN_PRIVATE_H_
#define FLUTTER_PLUGIN_XUE_HUA_NAVITE_AUTO_UPDATE_PLUGIN_PRIVATE_H_

#include <string>

namespace xue_hua_navite_auto_update {

// Escapes a string for safe embedding inside a PowerShell single-quoted literal.
std::wstring EscapePowerShellSingleQuoted(const std::wstring& input);

// Resolves an absolute path to Windows PowerShell 5.1 (powershell.exe).
std::wstring ResolvePowerShellExecutable();

// Starts a guardian PowerShell script so it survives the current process
// exiting, including when the Flutter host is inside a Windows Job Object.
bool LaunchDetachedUpdaterGuard(const std::wstring& script_path);

}  // namespace xue_hua_navite_auto_update

#endif  // FLUTTER_PLUGIN_XUE_HUA_NAVITE_AUTO_UPDATE_PLUGIN_PRIVATE_H_
