#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <memory>
#include <string>
#include <variant>

#include "xue_hua_navite_auto_update_plugin.h"

namespace xue_hua_navite_auto_update {
namespace test {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

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

}  // namespace test
}  // namespace xue_hua_navite_auto_update
