#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
// windows.h must be included before any SDK header that uses EXTERN_C /
// DECLSPEC_IMPORT (e.g. shellapi.h). gtest does not guarantee a full
// windows.h include, so pull it in explicitly after gtest (gtest may
// include winsock2.h first).
#include <windows.h>

#include <string>
#include <vector>

#include "xue_hua_navite_auto_update_plugin.h"
#include "xue_hua_navite_auto_update_plugin_private.h"

namespace xue_hua_navite_auto_update {
namespace test {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

std::wstring TempDir() {
  wchar_t buffer[MAX_PATH] = {0};
  DWORD len = GetTempPathW(MAX_PATH, buffer);
  if (len == 0 || len >= MAX_PATH) {
    return L"C:\\Windows\\Temp\\";
  }
  return std::wstring(buffer, len);
}

std::wstring UniqueTempPath(const wchar_t* prefix, const wchar_t* ext) {
  return TempDir() + prefix + L"_" + std::to_wstring(GetCurrentProcessId()) +
         L"_" + std::to_wstring(GetTickCount()) + ext;
}

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

bool WriteUtf8BomFile(const std::wstring& path, const std::wstring& wide) {
  std::string utf8 = WideToUtf8(wide);
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ,
                            nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                            nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return false;
  }
  const unsigned char bom[3] = {0xEF, 0xBB, 0xBF};
  DWORD written = 0;
  BOOL ok = WriteFile(file, bom, 3, &written, nullptr);
  if (ok) {
    ok = WriteFile(file, utf8.data(), static_cast<DWORD>(utf8.size()),
                   &written, nullptr);
  }
  FlushFileBuffers(file);
  CloseHandle(file);
  return ok == TRUE;
}

std::wstring MarkerScript(const std::wstring& marker_path) {
  return L"$ErrorActionPreference = 'SilentlyContinue'\r\n"
         L"Start-Sleep -Milliseconds 400\r\n"
         L"Set-Content -LiteralPath '" +
         EscapePowerShellSingleQuoted(marker_path) +
         L"' -Value 'alive' -Encoding ASCII\r\n"
         L"Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force "
         L"-ErrorAction SilentlyContinue\r\n";
}

bool WaitForFile(const std::wstring& path, DWORD timeout_ms) {
  const DWORD start = GetTickCount();
  while (GetTickCount() - start < timeout_ms) {
    if (GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES) {
      return true;
    }
    Sleep(100);
  }
  return GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES;
}

std::wstring CurrentExecutablePath() {
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

bool RunHelperInJob(const std::wstring& script_path, DWORD job_limit_flags,
                    DWORD* exit_code) {
  HANDLE job = CreateJobObjectW(nullptr, nullptr);
  if (!job) {
    return false;
  }

  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;
  ZeroMemory(&limits, sizeof(limits));
  limits.BasicLimitInformation.LimitFlags = job_limit_flags;
  if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits,
                               sizeof(limits))) {
    CloseHandle(job);
    return false;
  }

  const std::wstring exe = CurrentExecutablePath();
  std::wstring cmd = L"\"" + exe + L"\" --launch-guard-and-exit \"" +
                     script_path + L"\"";
  std::vector<wchar_t> mutable_cmd(cmd.begin(), cmd.end());
  mutable_cmd.push_back(L'\0');

  STARTUPINFOW si;
  ZeroMemory(&si, sizeof(si));
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi;
  ZeroMemory(&pi, sizeof(pi));

  if (!CreateProcessW(exe.c_str(), mutable_cmd.data(), nullptr, nullptr, FALSE,
                      CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT, nullptr,
                      nullptr, &si, &pi)) {
    CloseHandle(job);
    return false;
  }

  if (!AssignProcessToJobObject(job, pi.hProcess)) {
    TerminateProcess(pi.hProcess, 1);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    CloseHandle(job);
    return false;
  }

  ResumeThread(pi.hThread);
  const DWORD wait = WaitForSingleObject(pi.hProcess, 20000);
  DWORD code = 1;
  if (wait == WAIT_OBJECT_0) {
    GetExitCodeProcess(pi.hProcess, &code);
  } else {
    TerminateProcess(pi.hProcess, 1);
  }
  if (exit_code) {
    *exit_code = code;
  }

  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  // Closing the job kills any remaining members (KILL_ON_JOB_CLOSE).
  CloseHandle(job);
  return wait == WAIT_OBJECT_0;
}

}  // namespace

TEST(XueHuaNaviteAutoUpdatePlugin, CheckEnvironmentReturnsValidWindowsMap) {
  XueHuaNaviteAutoUpdatePlugin plugin;
  EncodableMap env_map;
  plugin.HandleMethodCall(
      MethodCall("checkEnvironment", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          [&env_map](const EncodableValue* result) {
            env_map = std::get<EncodableMap>(*result);
          },
          nullptr, nullptr));

  auto platform_it = env_map.find(EncodableValue("platform"));
  ASSERT_NE(platform_it, env_map.end());
  EXPECT_EQ(std::get<std::string>(platform_it->second), "windows");

  auto pid_it = env_map.find(EncodableValue("processId"));
  ASSERT_NE(pid_it, env_map.end());
  EXPECT_GT(std::get<int64_t>(pid_it->second), 0);
}

TEST(XueHuaNaviteAutoUpdatePlugin, EscapePowerShellSingleQuotedDoublesQuotes) {
  EXPECT_EQ(EscapePowerShellSingleQuoted(L"plain"), L"plain");
  EXPECT_EQ(EscapePowerShellSingleQuoted(L"it's"), L"it''s");
  EXPECT_EQ(EscapePowerShellSingleQuoted(L"a'b'c"), L"a''b''c");
}

TEST(XueHuaNaviteAutoUpdatePlugin, ResolvePowerShellExecutableIsAbsolute) {
  const std::wstring path = ResolvePowerShellExecutable();
  ASSERT_FALSE(path.empty());
  EXPECT_NE(path.find(L'\\'), std::wstring::npos);
  EXPECT_NE(GetFileAttributesW(path.c_str()), INVALID_FILE_ATTRIBUTES);
  const size_t slash = path.find_last_of(L"\\/");
  const std::wstring name =
      (slash == std::wstring::npos) ? path : path.substr(slash + 1);
  EXPECT_EQ(_wcsicmp(name.c_str(), L"powershell.exe"), 0);
}

TEST(XueHuaNaviteAutoUpdatePlugin, LaunchDetachedGuardRunsScript) {
  const std::wstring marker = UniqueTempPath(L"xue_hua_guard_marker", L".txt");
  const std::wstring script = UniqueTempPath(L"xue_hua_guard_script", L".ps1");
  DeleteFileW(marker.c_str());
  ASSERT_TRUE(WriteUtf8BomFile(script, MarkerScript(marker)));
  ASSERT_TRUE(LaunchDetachedUpdaterGuard(script));
  EXPECT_TRUE(WaitForFile(marker, 8000));
  DeleteFileW(marker.c_str());
  DeleteFileW(script.c_str());
}

TEST(XueHuaNaviteAutoUpdatePlugin,
     LaunchDetachedGuardSurvivesKillOnJobCloseWithBreakaway) {
  const std::wstring marker = UniqueTempPath(L"xue_hua_job_ba_marker", L".txt");
  const std::wstring script = UniqueTempPath(L"xue_hua_job_ba_script", L".ps1");
  DeleteFileW(marker.c_str());
  ASSERT_TRUE(WriteUtf8BomFile(script, MarkerScript(marker)));

  DWORD exit_code = 1;
  const bool launched = RunHelperInJob(
      script,
      JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_BREAKAWAY_OK,
      &exit_code);
  if (!launched) {
    GTEST_SKIP() << "Unable to create or assign a Windows Job Object.";
  }
  EXPECT_EQ(exit_code, 0u);
  EXPECT_TRUE(WaitForFile(marker, 8000));
  DeleteFileW(marker.c_str());
  DeleteFileW(script.c_str());
}

TEST(XueHuaNaviteAutoUpdatePlugin,
     LaunchDetachedGuardSurvivesKillOnJobCloseWithoutBreakaway) {
  const std::wstring marker = UniqueTempPath(L"xue_hua_job_nb_marker", L".txt");
  const std::wstring script = UniqueTempPath(L"xue_hua_job_nb_script", L".ps1");
  DeleteFileW(marker.c_str());
  ASSERT_TRUE(WriteUtf8BomFile(script, MarkerScript(marker)));

  DWORD exit_code = 1;
  const bool launched = RunHelperInJob(
      script, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE, &exit_code);
  if (!launched) {
    GTEST_SKIP() << "Unable to create or assign a Windows Job Object.";
  }
  EXPECT_EQ(exit_code, 0u);
  EXPECT_TRUE(WaitForFile(marker, 8000));
  DeleteFileW(marker.c_str());
  DeleteFileW(script.c_str());
}

}  // namespace test
}  // namespace xue_hua_navite_auto_update

int wmain(int argc, wchar_t** argv) {
  if (argc >= 3 && wcscmp(argv[1], L"--launch-guard-and-exit") == 0) {
    return xue_hua_navite_auto_update::LaunchDetachedUpdaterGuard(argv[2]) ? 0
                                                                         : 1;
  }
  testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
