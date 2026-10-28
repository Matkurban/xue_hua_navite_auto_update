#include <flutter_linux/flutter_linux.h>
#include <gmock/gmock.h>
#include <gtest/gtest.h>

#include "include/xue_hua_navite_auto_update/xue_hua_navite_auto_update_plugin.h"
#include "xue_hua_navite_auto_update_plugin_private.h"

namespace xue_hua_navite_auto_update {
namespace test {

TEST(XueHuaNaviteAutoUpdatePlugin, CheckEnvironmentReturnsLinuxMap) {
  g_autoptr(FlMethodResponse) response = handle_check_environment();
  ASSERT_NE(response, nullptr);
  ASSERT_TRUE(FL_IS_METHOD_SUCCESS_RESPONSE(response));
  FlValue* result = fl_method_success_response_get_result(
      FL_METHOD_SUCCESS_RESPONSE(response));
  ASSERT_EQ(fl_value_get_type(result), FL_VALUE_TYPE_MAP);

  FlValue* platform_val = fl_value_lookup_string(result, "platform");
  ASSERT_NE(platform_val, nullptr);
  EXPECT_STREQ(fl_value_get_string(platform_val), "linux");
}

}  // namespace test
}  // namespace xue_hua_navite_auto_update
