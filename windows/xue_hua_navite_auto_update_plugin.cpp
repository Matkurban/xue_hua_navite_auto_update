#include "xue_hua_navite_auto_update_plugin.h"

// Windows system headers
#include <windows.h>
#include <appmodel.h>
#include <bcrypt.h>
#include <shellapi.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cctype>
#include <cwctype>
#include <fstream>
#include <iomanip>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

#ifndef NT_SUCCESS
#define NT_SUCCESS(Status) (((NTSTATUS)(Status)) >= 0)
#endif

namespace xue_hua_navite_auto_update {

namespace {

// Converts a UTF-8 std::string to a UTF-16 std::wstring.
std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int count = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                  static_cast<int>(utf8.size()), nullptr, 0);
  if (count <= 0) return std::wstring();
  std::wstring wide(count, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      wide.data(), count);
  return wide;
}

// Converts a UTF-16 std::wstring to a UTF-8 std::string.
std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) return std::string();
  int count = WideCharToMultiByte(CP_UTF8, 0, wide.data(),
                                  static_cast<int>(wide.size()), nullptr, 0,
                                  nullptr, nullptr);
  if (count <= 0) return std::string();
  std::string utf8(count, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                      utf8.data(), count, nullptr, nullptr);
  return utf8;
}

std::string ToLowerAscii(std::string input) {
  std::transform(input.begin(), input.end(), input.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return input;
}

// Returns the absolute path of the current running .exe module.
std::wstring GetCurrentExecutablePath() {
  std::vector<wchar_t> buffer(MAX_PATH);
  while (true) {
    DWORD copied = GetModuleFileNameW(nullptr, buffer.data(),
                                      static_cast<DWORD>(buffer.size()));
    if (copied == 0) return L"";
    if (copied < buffer.size() - 1) {
      return std::wstring(buffer.data(), copied);
    }
    buffer.resize(buffer.size() * 2);
  }
}

// Returns the parent directory of a file path.
std::wstring GetParentDirectory(const std::wstring& path) {
  size_t pos = path.find_last_of(L"\\/");
  if (pos == std::wstring::npos) return L"";
  return path.substr(0, pos);
}

// Returns the filename portion of a path.
std::wstring GetFileNamePart(const std::wstring& path) {
  size_t pos = path.find_last_of(L"\\/");
  if (pos == std::wstring::npos) return path;
  return path.substr(pos + 1);
}

// Detects whether the current process is running inside a Windows MSIX / AppX
// Store package container where self-replacement is prohibited.
bool IsRunningInMsixContainer() {
  HMODULE kernel32 = GetModuleHandleW(L"kernel32.dll");
  if (!kernel32) return false;
  using GetCurrentPackageFullNameFn = LONG(WINAPI*)(UINT32*, PWSTR);
  auto fn = reinterpret_cast<GetCurrentPackageFullNameFn>(
      GetProcAddress(kernel32, "GetCurrentPackageFullName"));
  if (!fn) return false;
  UINT32 length = 0;
  LONG rc = fn(&length, nullptr);
  return rc != APPMODEL_ERROR_NO_PACKAGE;
}

// Tests whether the current non-elevated user token has write permission inside
// `directory_path` by creating and immediately deleting a temporary probe file.
bool CanWriteToDirectory(const std::wstring& directory_path) {
  if (directory_path.empty()) return false;
  DWORD pid = GetCurrentProcessId();
  DWORD tick = GetTickCount();
  std::wstring probe_path = directory_path + L"\\.xue_hua_write_probe_" +
                            std::to_wstring(pid) + L"_" +
                            std::to_wstring(tick) + L".tmp";
  HANDLE hFile = CreateFileW(
      probe_path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
      FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE, nullptr);
  if (hFile == INVALID_HANDLE_VALUE) {
    return false;
  }
  CloseHandle(hFile);
  return true;
}

// Escapes a string for safe embedding inside a PowerShell single-quoted literal.
std::wstring EscapePowerShellSingleQuoted(const std::wstring& input) {
  std::wstring out;
  out.reserve(input.size() + 8);
  for (wchar_t ch : input) {
    if (ch == L'\'') {
      out += L"''";
    } else {
      out.push_back(ch);
    }
  }
  return out;
}

}  // namespace

// static
void XueHuaNaviteAutoUpdatePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "xue_hua_navite_auto_update",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<XueHuaNaviteAutoUpdatePlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

XueHuaNaviteAutoUpdatePlugin::XueHuaNaviteAutoUpdatePlugin() {}

XueHuaNaviteAutoUpdatePlugin::~XueHuaNaviteAutoUpdatePlugin() {}

void XueHuaNaviteAutoUpdatePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();

  if (method == "checkEnvironment") {
    result->Success(flutter::EncodableValue(CheckEnvironment()));
    return;
  }

  if (method == "verifyPackageChecksum") {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!args) {
      result->Error("INVALID_ARGUMENTS", "Expected argument map.");
      return;
    }
    auto file_it = args->find(flutter::EncodableValue("filePath"));
    auto sha_it = args->find(flutter::EncodableValue("expectedSha256"));
    if (file_it == args->end() || sha_it == args->end() ||
        !std::holds_alternative<std::string>(file_it->second) ||
        !std::holds_alternative<std::string>(sha_it->second)) {
      result->Error("INVALID_ARGUMENTS",
                    "filePath and expectedSha256 are required.");
      return;
    }
    const std::string file_path_utf8 = std::get<std::string>(file_it->second);
    const std::string expected_sha = std::get<std::string>(sha_it->second);
    bool matched = VerifyFileSha256(Utf8ToWide(file_path_utf8), expected_sha);
    result->Success(flutter::EncodableValue(matched));
    return;
  }

  if (method == "installAndRelaunch") {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!args) {
      result->Error("INVALID_ARGUMENTS", "Expected argument map.");
      return;
    }
    HandleInstallAndRelaunch(*args, std::move(result));
    return;
  }

  result->NotImplemented();
}

flutter::EncodableMap XueHuaNaviteAutoUpdatePlugin::CheckEnvironment() const {
  std::wstring exe_path = GetCurrentExecutablePath();
  std::wstring install_dir = GetParentDirectory(exe_path);
  int64_t pid = static_cast<int64_t>(GetCurrentProcessId());

  if (IsRunningInMsixContainer()) {
    return flutter::EncodableMap{
        {flutter::EncodableValue("platform"),
         flutter::EncodableValue("windows")},
        {flutter::EncodableValue("executablePath"),
         flutter::EncodableValue(WideToUtf8(exe_path))},
        {flutter::EncodableValue("bundlePath"),
         flutter::EncodableValue(WideToUtf8(install_dir))},
        {flutter::EncodableValue("processId"), flutter::EncodableValue(pid)},
        {flutter::EncodableValue("canAutoUpdate"),
         flutter::EncodableValue(false)},
        {flutter::EncodableValue("requiresElevation"),
         flutter::EncodableValue(false)},
        {flutter::EncodableValue("blockReason"),
         flutter::EncodableValue("runningInSandboxOrStore")},
        {flutter::EncodableValue("statusMessage"),
         flutter::EncodableValue(
             "Application is running inside a Windows MSIX / Microsoft Store container. Use standard Win32 / Inno Setup distribution for self-updating.")},
    };
  }

  bool writable = CanWriteToDirectory(install_dir);
  bool requires_elevation = !writable;
  std::string status_msg =
      requires_elevation
          ? "Ready for Inno Setup auto-update. Windows UAC elevation will be requested if the installer targets Program Files."
          : "Ready for UAC-free Inno Setup auto-update in user-writable directory.";

  return flutter::EncodableMap{
      {flutter::EncodableValue("platform"), flutter::EncodableValue("windows")},
      {flutter::EncodableValue("executablePath"),
       flutter::EncodableValue(WideToUtf8(exe_path))},
      {flutter::EncodableValue("bundlePath"),
       flutter::EncodableValue(WideToUtf8(install_dir))},
      {flutter::EncodableValue("processId"), flutter::EncodableValue(pid)},
      {flutter::EncodableValue("canAutoUpdate"), flutter::EncodableValue(true)},
      {flutter::EncodableValue("requiresElevation"),
       flutter::EncodableValue(requires_elevation)},
      {flutter::EncodableValue("blockReason"),
       flutter::EncodableValue("none")},
      {flutter::EncodableValue("statusMessage"),
       flutter::EncodableValue(status_msg)},
  };
}

bool XueHuaNaviteAutoUpdatePlugin::VerifyFileSha256(
    const std::wstring& file_path, const std::string& expected_hex) {
  std::string clean_expected = ToLowerAscii(expected_hex);
  clean_expected.erase(
      std::remove_if(clean_expected.begin(), clean_expected.end(),
                     [](unsigned char c) { return std::isspace(c); }),
      clean_expected.end());
  if (clean_expected.size() != 64) {
    return false;
  }

  HANDLE hFile = CreateFileW(file_path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                             nullptr, OPEN_EXISTING,
                             FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
  if (hFile == INVALID_HANDLE_VALUE) {
    return false;
  }

  BCRYPT_ALG_HANDLE hAlg = nullptr;
  BCRYPT_HASH_HANDLE hHash = nullptr;
  bool success = false;

  do {
    if (!NT_SUCCESS(BCryptOpenAlgorithmProvider(
            &hAlg, BCRYPT_SHA256_ALGORITHM, nullptr, 0))) {
      break;
    }
    DWORD hash_obj_size = 0;
    DWORD cb_data = 0;
    if (!NT_SUCCESS(BCryptGetProperty(
            hAlg, BCRYPT_OBJECT_LENGTH,
            reinterpret_cast<PUCHAR>(&hash_obj_size), sizeof(DWORD), &cb_data,
            0))) {
      break;
    }
    std::vector<UCHAR> hash_obj(hash_obj_size);
    if (!NT_SUCCESS(BCryptCreateHash(hAlg, &hHash, hash_obj.data(),
                                     hash_obj_size, nullptr, 0, 0))) {
      break;
    }

    std::vector<UCHAR> buffer(64 * 1024);
    DWORD bytes_read = 0;
    bool read_ok = true;
    while (true) {
      if (!ReadFile(hFile, buffer.data(), static_cast<DWORD>(buffer.size()),
                    &bytes_read, nullptr)) {
        read_ok = false;
        break;
      }
      if (bytes_read == 0) break;
      if (!NT_SUCCESS(
              BCryptHashData(hHash, buffer.data(), bytes_read, 0))) {
        read_ok = false;
        break;
      }
    }
    if (!read_ok) break;

    UCHAR digest[32] = {0};
    if (!NT_SUCCESS(BCryptFinishHash(hHash, digest, sizeof(digest), 0))) {
      break;
    }

    std::ostringstream oss;
    oss << std::hex << std::setfill('0');
    for (size_t i = 0; i < 32; ++i) {
      oss << std::setw(2) << static_cast<int>(digest[i]);
    }
    success = (oss.str() == clean_expected);
  } while (false);

  if (hHash) BCryptDestroyHash(hHash);
  if (hAlg) BCryptCloseAlgorithmProvider(hAlg, 0);
  CloseHandle(hFile);
  return success;
}

void XueHuaNaviteAutoUpdatePlugin::HandleInstallAndRelaunch(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  auto pkg_it = args.find(flutter::EncodableValue("packagePath"));
  if (pkg_it == args.end() ||
      !std::holds_alternative<std::string>(pkg_it->second)) {
    result->Error("INVALID_ARGUMENTS", "packagePath is required.");
    return;
  }

  std::wstring package_path = Utf8ToWide(std::get<std::string>(pkg_it->second));
  DWORD attrs = GetFileAttributesW(package_path.c_str());
  if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_DIRECTORY)) {
    result->Error("PACKAGE_NOT_FOUND",
                  "Installer .exe does not exist at the specified packagePath.");
    return;
  }

  bool show_progress_dialog = true;
  auto show_it = args.find(flutter::EncodableValue("showProgressDialog"));
  if (show_it != args.end() &&
      std::holds_alternative<bool>(show_it->second)) {
    show_progress_dialog = std::get<bool>(show_it->second);
  }

  bool exit_current_app = true;
  auto exit_it = args.find(flutter::EncodableValue("exitCurrentApp"));
  if (exit_it != args.end() &&
      std::holds_alternative<bool>(exit_it->second)) {
    exit_current_app = std::get<bool>(exit_it->second);
  }

  std::vector<std::wstring> relaunch_args;
  auto args_it = args.find(flutter::EncodableValue("relaunchArgs"));
  if (args_it != args.end() &&
      std::holds_alternative<flutter::EncodableList>(args_it->second)) {
    const auto& list = std::get<flutter::EncodableList>(args_it->second);
    for (const auto& item : list) {
      if (std::holds_alternative<std::string>(item)) {
        relaunch_args.push_back(Utf8ToWide(std::get<std::string>(item)));
      }
    }
  }

  std::wstring target_exe = GetCurrentExecutablePath();
  std::wstring target_dir = GetParentDirectory(target_exe);
  std::wstring target_exe_name = GetFileNamePart(target_exe);
  DWORD current_pid = GetCurrentProcessId();

  // Build Inno Setup command-line arguments:
  // - showProgressDialog == true  -> /SILENT /SUPPRESSMSGBOXES /NORESTART /SP- /CLOSEAPPLICATIONS
  // - showProgressDialog == false -> /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /CLOSEAPPLICATIONS
  std::wstring inno_mode = show_progress_dialog ? L"/SILENT" : L"/VERYSILENT";

  wchar_t temp_dir_buf[MAX_PATH] = {0};
  DWORD temp_len = GetTempPathW(MAX_PATH, temp_dir_buf);
  std::wstring temp_dir =
      (temp_len > 0) ? std::wstring(temp_dir_buf, temp_len) : L"C:\\Windows\\Temp\\";

  std::wstring script_path =
      temp_dir + L"xue_hua_updater_guard_" + std::to_wstring(current_pid) +
      L"_" + std::to_wstring(GetTickCount()) + L".ps1";

  // Build forwarded relaunch arguments array for PowerShell
  std::wstringstream relaunch_args_ps;
  relaunch_args_ps << L"@(";
  for (size_t i = 0; i < relaunch_args.size(); ++i) {
    if (i > 0) relaunch_args_ps << L", ";
    relaunch_args_ps << L"'" << EscapePowerShellSingleQuoted(relaunch_args[i])
                     << L"'";
  }
  relaunch_args_ps << L")";

  // Write detached background guardian script:
  // 1. Waits for the main Flutter process (PID) to exit cleanly.
  // 2. Launches the Inno Setup installer (.exe) with /SILENT or /VERYSILENT and
  //    blocks until the installer finishes (WaitForSingleObject / -Wait).
  // 3. Checks whether the target application executable was already relaunched
  //    by Inno Setup's [Run] section.
  // 4. If NOT running (e.g., [Run] omitted or user cancelled UAC prompt),
  //    explicitly relaunches the original/updated executable so the user's app
  //    is 100% guaranteed to come back.
  std::wstringstream ps_content;
  ps_content
      << L"$ErrorActionPreference = 'SilentlyContinue'\r\n"
      << L"$mainPid = " << current_pid << L"\r\n"
      << L"$installerPath = '" << EscapePowerShellSingleQuoted(package_path) << L"'\r\n"
      << L"$targetExe = '" << EscapePowerShellSingleQuoted(target_exe) << L"'\r\n"
      << L"$targetDir = '" << EscapePowerShellSingleQuoted(target_dir) << L"'\r\n"
      << L"$relaunchArgs = " << relaunch_args_ps.str() << L"\r\n"
      << L"\r\n"
      << L"# 1. Wait for the main Flutter application process to exit\r\n"
      << L"for ($i = 0; $i -lt 300; $i++) {\r\n"
      << L"  $proc = Get-Process -Id $mainPid -ErrorAction SilentlyContinue\r\n"
      << L"  if ($null -eq $proc) { break }\r\n"
      << L"  Start-Sleep -Milliseconds 100\r\n"
      << L"}\r\n"
      << L"\r\n"
      << L"# 2. Launch Inno Setup installer and block until completion\r\n"
      << L"$innoArgs = @('" << inno_mode
      << L"', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/CLOSEAPPLICATIONS')\r\n"
      << L"try {\r\n"
      << L"  Start-Process -FilePath $installerPath -ArgumentList $innoArgs -Wait -WorkingDirectory $targetDir\r\n"
      << L"} catch {\r\n"
      << L"  # User may have cancelled UAC or installer failed; fall through to relaunch guard\r\n"
      << L"}\r\n"
      << L"\r\n"
      << L"Start-Sleep -Milliseconds 400\r\n"
      << L"\r\n"
      << L"# 3. Check if Inno Setup [Run] already started the target executable\r\n"
      << L"$alreadyRunning = $false\r\n"
      << L"$procName = [System.IO.Path]::GetFileNameWithoutExtension($targetExe)\r\n"
      << L"$candidates = Get-Process -Name $procName -ErrorAction SilentlyContinue\r\n"
      << L"foreach ($c in $candidates) {\r\n"
      << L"  if ($c.Id -ne $mainPid) {\r\n"
      << L"    $alreadyRunning = $true\r\n"
      << L"    break\r\n"
      << L"  }\r\n"
      << L"}\r\n"
      << L"\r\n"
      << L"# 4. Guarantee 100% relaunch via ShellExecute / Start-Process if not running\r\n"
      << L"if (-not $alreadyRunning -and (Test-Path -LiteralPath $targetExe)) {\r\n"
      << L"  if ($relaunchArgs.Count -gt 0) {\r\n"
      << L"    Start-Process -FilePath $targetExe -ArgumentList $relaunchArgs -WorkingDirectory $targetDir\r\n"
      << L"  } else {\r\n"
      << L"    Start-Process -FilePath $targetExe -WorkingDirectory $targetDir\r\n"
      << L"  }\r\n"
      << L"}\r\n"
      << L"\r\n"
      << L"Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue\r\n";

  // Write UTF-8 with BOM so Windows PowerShell 5.1 reads Unicode paths and CJK text accurately
  std::string utf8_script = WideToUtf8(ps_content.str());
  {
    std::ofstream ofs(script_path, std::ios::binary | std::ios::trunc);
    if (!ofs.is_open()) {
      result->Error("UPDATER_SCRIPT_WRITE_FAILED",
                    "Failed to write detached updater guard script in %TEMP%.");
      return;
    }
    const unsigned char bom[3] = {0xEF, 0xBB, 0xBF};
    ofs.write(reinterpret_cast<const char*>(bom), 3);
    ofs.write(utf8_script.data(), static_cast<std::streamsize>(utf8_script.size()));
    ofs.close();
  }

  std::wstring cmd_line =
      L"powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass "
      L"-WindowStyle Hidden -File \"" +
      script_path + L"\"";
  std::vector<wchar_t> mutable_cmd(cmd_line.begin(), cmd_line.end());
  mutable_cmd.push_back(L'\0');

  STARTUPINFOW si;
  ZeroMemory(&si, sizeof(si));
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESHOWWINDOW;
  si.wShowWindow = SW_HIDE;

  PROCESS_INFORMATION pi;
  ZeroMemory(&pi, sizeof(pi));

  BOOL created = CreateProcessW(
      nullptr, mutable_cmd.data(), nullptr, nullptr, FALSE,
      CREATE_NO_WINDOW | DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP, nullptr,
      target_dir.empty() ? nullptr : target_dir.c_str(), &si, &pi);

  if (!created) {
    DeleteFileW(script_path.c_str());
    result->Error("UPDATER_LAUNCH_FAILED",
                  "CreateProcessW failed to launch detached updater guard.");
    return;
  }

  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);

  result->Success();

  if (exit_current_app) {
    PostQuitMessage(0);
    ExitProcess(0);
  }
}

}  // namespace xue_hua_navite_auto_update
