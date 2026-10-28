#include "include/xue_hua_navite_auto_update/xue_hua_navite_auto_update_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#include <glib.h>
#include <glib/gstdio.h>
#include <gtk/gtk.h>
#include <limits.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <cstring>
#include <string>
#include <vector>

#include "xue_hua_navite_auto_update_plugin_private.h"

#define XUE_HUA_NAVITE_AUTO_UPDATE_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), xue_hua_navite_auto_update_plugin_get_type(), \
                              XueHuaNaviteAutoUpdatePlugin))

struct _XueHuaNaviteAutoUpdatePlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(XueHuaNaviteAutoUpdatePlugin,
              xue_hua_navite_auto_update_plugin,
              g_object_get_type())

namespace {

// Resolves the absolute path of the running Linux binary via `/proc/self/exe`.
std::string GetCurrentExecutablePathLinux() {
  char buf[PATH_MAX] = {0};
  ssize_t len = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
  if (len <= 0) {
    return "";
  }
  buf[len] = '\0';
  return std::string(buf);
}

// Escapes a string for safe inclusion inside a single-quoted POSIX shell token.
std::string ShellSingleQuoteEscape(const std::string& input) {
  std::string out = "'";
  for (char c : input) {
    if (c == '\'') {
      out += "'\\''";
    } else {
      out.push_back(c);
    }
  }
  out.push_back('\'');
  return out;
}

std::string LookupStringField(FlValue* map,
                              const char* key,
                              const char* fallback) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* val = fl_value_lookup_string(map, key);
  if (val != nullptr && fl_value_get_type(val) == FL_VALUE_TYPE_STRING) {
    return fl_value_get_string(val);
  }
  return fallback;
}

}  // namespace

FlMethodResponse* handle_check_environment() {
  std::string exe_path = GetCurrentExecutablePathLinux();
  const gchar* appimage_env = g_getenv("APPIMAGE");
  const gchar* snap_env = g_getenv("SNAP");
  const gchar* flatpak_env = g_getenv("FLATPAK_ID");
  gint64 pid = static_cast<gint64>(getpid());

  std::string bundle_path;
  if (appimage_env != nullptr && strlen(appimage_env) > 0) {
    bundle_path = appimage_env;
  } else {
    g_autofree gchar* dir = g_path_get_dirname(exe_path.c_str());
    bundle_path = (dir != nullptr) ? dir : "";
  }

  // 1. Detect Snap or Flatpak sandbox containers
  if ((snap_env != nullptr && strlen(snap_env) > 0) ||
      (flatpak_env != nullptr && strlen(flatpak_env) > 0) ||
      g_file_test("/.flatpak-info", G_FILE_TEST_EXISTS)) {
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "platform", fl_value_new_string("linux"));
    fl_value_set_string_take(map, "executablePath",
                             fl_value_new_string(exe_path.c_str()));
    fl_value_set_string_take(map, "bundlePath",
                             fl_value_new_string(bundle_path.c_str()));
    fl_value_set_string_take(map, "processId", fl_value_new_int(pid));
    fl_value_set_string_take(map, "canAutoUpdate", fl_value_new_bool(FALSE));
    fl_value_set_string_take(map, "requiresElevation",
                             fl_value_new_bool(FALSE));
    fl_value_set_string_take(map, "blockReason",
                             fl_value_new_string("runningInSandboxOrStore"));
    fl_value_set_string_take(
        map, "statusMessage",
        fl_value_new_string(
            "Application is running inside a Snap or Flatpak container. Use .AppImage, .deb, or .rpm distribution for in-place auto-update."));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(map));
  }

  // 2. Determine whether privilege elevation (Polkit pkexec) is required.
  //    - When running from an $APPIMAGE in a user-writable folder, no elevation is needed.
  //    - When installed via .deb / .rpm into /usr or /opt, Polkit pkexec elevation is required.
  bool requires_elevation = true;
  std::string status_message =
      "Ready for system package (.deb / .rpm) auto-update via Polkit (pkexec).";

  if (appimage_env != nullptr && strlen(appimage_env) > 0) {
    g_autofree gchar* appimage_dir = g_path_get_dirname(appimage_env);
    bool dir_writable =
        (appimage_dir != nullptr && g_access(appimage_dir, W_OK) == 0);
    bool file_writable = (g_access(appimage_env, W_OK) == 0);
    requires_elevation = !(dir_writable && file_writable);
    status_message =
        requires_elevation
            ? "Running as AppImage in a protected directory; privilege elevation will be required."
            : "Running as AppImage in a user-writable directory; passwordless in-place replacement is ready.";
  }

  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "platform", fl_value_new_string("linux"));
  fl_value_set_string_take(map, "executablePath",
                           fl_value_new_string(exe_path.c_str()));
  fl_value_set_string_take(map, "bundlePath",
                           fl_value_new_string(bundle_path.c_str()));
  fl_value_set_string_take(map, "processId", fl_value_new_int(pid));
  fl_value_set_string_take(map, "canAutoUpdate", fl_value_new_bool(TRUE));
  fl_value_set_string_take(map, "requiresElevation",
                           fl_value_new_bool(requires_elevation));
  fl_value_set_string_take(map, "blockReason", fl_value_new_string("none"));
  fl_value_set_string_take(map, "statusMessage",
                           fl_value_new_string(status_message.c_str()));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(map));
}

gboolean verify_file_sha256_linux(const gchar* file_path,
                                  const gchar* expected_sha256) {
  if (file_path == nullptr || expected_sha256 == nullptr) {
    return FALSE;
  }

  g_autofree gchar* expected_trimmed = g_strstrip(g_strdup(expected_sha256));
  g_autofree gchar* expected_lower = g_ascii_strdown(expected_trimmed, -1);
  if (strlen(expected_lower) != 64) {
    return FALSE;
  }

  FILE* fp = g_fopen(file_path, "rb");
  if (fp == nullptr) {
    return FALSE;
  }

  GChecksum* checksum = g_checksum_new(G_CHECKSUM_SHA256);
  guchar buffer[64 * 1024];
  size_t bytes_read = 0;
  bool read_error = false;

  while ((bytes_read = fread(buffer, 1, sizeof(buffer), fp)) > 0) {
    g_checksum_update(checksum, buffer, static_cast<gssize>(bytes_read));
  }
  if (ferror(fp)) {
    read_error = true;
  }
  fclose(fp);

  if (read_error) {
    g_checksum_free(checksum);
    return FALSE;
  }

  const gchar* actual_hex = g_checksum_get_string(checksum);
  gboolean matched = (g_ascii_strcasecmp(actual_hex, expected_lower) == 0);
  g_checksum_free(checksum);
  return matched;
}

static FlMethodResponse* handle_install_and_relaunch(FlValue* args) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "INVALID_ARGUMENTS", "Expected argument map.", nullptr));
  }

  std::string package_path = LookupStringField(args, "packagePath", "");
  std::string package_type = LookupStringField(args, "packageType", "");
  if (package_path.empty() || !g_file_test(package_path.c_str(), G_FILE_TEST_IS_REGULAR)) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "PACKAGE_NOT_FOUND",
        "Update package file does not exist at packagePath.", nullptr));
  }

  // Normalize packageType if needed
  g_autofree gchar* lower_type = g_ascii_strdown(package_type.c_str(), -1);
  std::string normalized_type = lower_type != nullptr ? lower_type : "";
  if (normalized_type.empty()) {
    g_autofree gchar* lower_path = g_ascii_strdown(package_path.c_str(), -1);
    if (g_str_has_suffix(lower_path, ".appimage")) {
      normalized_type = "appimage";
    } else if (g_str_has_suffix(lower_path, ".deb")) {
      normalized_type = "deb";
    } else if (g_str_has_suffix(lower_path, ".rpm")) {
      normalized_type = "rpm";
    }
  }

  if (normalized_type != "appimage" && normalized_type != "deb" &&
      normalized_type != "rpm") {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "UNSUPPORTED_PACKAGE_TYPE",
        "Linux only supports .AppImage, .deb, and .rpm packages.", nullptr));
  }

  const gchar* appimage_env = g_getenv("APPIMAGE");
  if (normalized_type == "appimage" &&
      (appimage_env == nullptr || strlen(appimage_env) == 0)) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "MISSING_APPIMAGE_ENV",
        "Cannot perform AppImage in-place update because the $APPIMAGE environment variable is not set.",
        nullptr));
  }

  bool show_progress_dialog = true;
  FlValue* show_val = fl_value_lookup_string(args, "showProgressDialog");
  if (show_val != nullptr && fl_value_get_type(show_val) == FL_VALUE_TYPE_BOOL) {
    show_progress_dialog = fl_value_get_bool(show_val);
  }

  bool exit_current_app = true;
  FlValue* exit_val = fl_value_lookup_string(args, "exitCurrentApp");
  if (exit_val != nullptr && fl_value_get_type(exit_val) == FL_VALUE_TYPE_BOOL) {
    exit_current_app = fl_value_get_bool(exit_val);
  }

  FlValue* strings_map = fl_value_lookup_string(args, "strings");
  std::string window_title =
      LookupStringField(strings_map, "windowTitle", "正在更新应用");
  std::string waiting_text = LookupStringField(
      strings_map, "waitingForAppExitText", "正在等待主程序安全关闭...");
  std::string installing_text = LookupStringField(
      strings_map, "installingUpdateText", "正在安装新版本应用...");
  std::string relaunching_text = LookupStringField(
      strings_map, "relaunchingText", "更新完成，正在重新启动应用...");
  std::string rollback_text = LookupStringField(
      strings_map, "rollingBackText", "更新已取消或遇到异常，正在恢复旧版本...");

  // Build forwarded relaunch command-line arguments
  std::string relaunch_args_escaped;
  FlValue* relaunch_list = fl_value_lookup_string(args, "relaunchArgs");
  if (relaunch_list != nullptr &&
      fl_value_get_type(relaunch_list) == FL_VALUE_TYPE_LIST) {
    size_t count = fl_value_get_length(relaunch_list);
    for (size_t i = 0; i < count; ++i) {
      FlValue* item = fl_value_get_list_value(relaunch_list, i);
      if (item != nullptr && fl_value_get_type(item) == FL_VALUE_TYPE_STRING) {
        relaunch_args_escaped += " ";
        relaunch_args_escaped +=
            ShellSingleQuoteEscape(fl_value_get_string(item));
      }
    }
  }

  std::string exe_path = GetCurrentExecutablePathLinux();
  std::string target_launch_binary =
      (normalized_type == "appimage" && appimage_env != nullptr)
          ? std::string(appimage_env)
          : exe_path;

  pid_t main_pid = getpid();
  g_autofree gchar* script_path = g_strdup_printf(
      "%s/xue_hua_linux_updater_%d_%ld.sh", g_get_tmp_dir(),
      static_cast<int>(main_pid), static_cast<long>(g_get_real_time()));

  std::string script = "#!/usr/bin/env bash\n";
  script += "set +e\n";
  script += "MAIN_PID=" + std::to_string(main_pid) + "\n";
  script += "PKG_PATH=" + ShellSingleQuoteEscape(package_path) + "\n";
  script += "PKG_TYPE=" + ShellSingleQuoteEscape(normalized_type) + "\n";
  script += "TARGET_BIN=" + ShellSingleQuoteEscape(target_launch_binary) + "\n";
  script += "SHOW_PROGRESS=" + std::string(show_progress_dialog ? "1" : "0") + "\n";
  script += "TITLE_TEXT=" + ShellSingleQuoteEscape(window_title) + "\n";
  script += "WAITING_TEXT=" + ShellSingleQuoteEscape(waiting_text) + "\n";
  script += "INSTALLING_TEXT=" + ShellSingleQuoteEscape(installing_text) + "\n";
  script += "RELAUNCH_TEXT=" + ShellSingleQuoteEscape(relaunching_text) + "\n";
  script += "ROLLBACK_TEXT=" + ShellSingleQuoteEscape(rollback_text) + "\n";
  script += R"SH(
FIFO_PATH="/tmp/xue_hua_zenity_fifo_${MAIN_PID}_$$"
ZENITY_PID=""

start_progress_ui() {
  if [ "$SHOW_PROGRESS" = "1" ] && command -v zenity >/dev/null 2>&1; then
    mkfifo "$FIFO_PATH"
    zenity --progress \
      --title="$TITLE_TEXT" \
      --text="$WAITING_TEXT" \
      --percentage=15 \
      --auto-close \
      --no-cancel \
      --width=420 < "$FIFO_PATH" >/dev/null 2>&1 &
    ZENITY_PID=$!
    exec 3>"$FIFO_PATH"
  fi
}

update_progress_ui() {
  local pct="$1"
  local msg="$2"
  if [ -n "$ZENITY_PID" ]; then
    echo "$pct" >&3 2>/dev/null
    echo "# $msg" >&3 2>/dev/null
  fi
}

close_progress_ui() {
  if [ -n "$ZENITY_PID" ]; then
    echo "100" >&3 2>/dev/null
    exec 3>&- 2>/dev/null
    kill "$ZENITY_PID" >/dev/null 2>&1 || true
    rm -f "$FIFO_PATH"
  fi
}

start_progress_ui
update_progress_ui 15 "$WAITING_TEXT"

# 1. Wait for main Flutter application process to exit
ELAPSED=0
while kill -0 "$MAIN_PID" 2>/dev/null && [ $ELAPSED -lt 300 ]; do
  sleep 0.1
  ELAPSED=$((ELAPSED + 1))
done

INSTALL_OK=0

# 2. Execute format-specific installation
if [ "$PKG_TYPE" = "appimage" ]; then
  update_progress_ui 50 "$INSTALLING_TEXT"
  chmod +x "$PKG_PATH"
  BAK_PATH="${TARGET_BIN}.bak"
  cp -f "$TARGET_BIN" "$BAK_PATH" 2>/dev/null || true
  if mv -f "$PKG_PATH" "$TARGET_BIN" && chmod +x "$TARGET_BIN"; then
    rm -f "$BAK_PATH"
    INSTALL_OK=1
  else
    update_progress_ui 85 "$ROLLBACK_TEXT"
    if [ -f "$BAK_PATH" ]; then
      mv -f "$BAK_PATH" "$TARGET_BIN"
      chmod +x "$TARGET_BIN"
    fi
  fi
elif [ "$PKG_TYPE" = "deb" ]; then
  update_progress_ui 55 "$INSTALLING_TEXT"
  if command -v apt-get >/dev/null 2>&1; then
    pkexec apt-get install -y --allow-downgrades "$PKG_PATH" && INSTALL_OK=1
  else
    pkexec dpkg -i "$PKG_PATH" && INSTALL_OK=1
  fi
elif [ "$PKG_TYPE" = "rpm" ]; then
  update_progress_ui 55 "$INSTALLING_TEXT"
  if command -v dnf >/dev/null 2>&1; then
    pkexec dnf install -y "$PKG_PATH" && INSTALL_OK=1
  elif command -v zypper >/dev/null 2>&1; then
    pkexec zypper --non-interactive install --allow-unsigned-rpm "$PKG_PATH" && INSTALL_OK=1
  else
    pkexec rpm -Uvh --replacepkgs "$PKG_PATH" && INSTALL_OK=1
  fi
fi

if [ "$INSTALL_OK" = "1" ]; then
  update_progress_ui 100 "$RELAUNCH_TEXT"
else
  update_progress_ui 95 "$ROLLBACK_TEXT"
fi

sleep 0.3
close_progress_ui

# 3. Relaunch application as the current non-root desktop user
)SH";

  script += "nohup \"$TARGET_BIN\"" + relaunch_args_escaped +
            " >/dev/null 2>&1 &\n";
  script += "rm -f -- \"$0\"\n";

  GError* file_err = nullptr;
  if (!g_file_set_contents(script_path, script.c_str(),
                           static_cast<gssize>(script.size()), &file_err)) {
    std::string msg = file_err != nullptr ? file_err->message
                                          : "Failed to write updater script.";
    if (file_err != nullptr) g_error_free(file_err);
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "UPDATER_SCRIPT_WRITE_FAILED", msg.c_str(), nullptr));
  }
  g_chmod(script_path, 0700);

  gchar* argv[] = {const_cast<gchar*>("/bin/bash"), script_path, nullptr};
  GError* spawn_err = nullptr;
  gboolean spawned = g_spawn_async(
      nullptr, argv, nullptr,
      static_cast<GSpawnFlags>(G_SPAWN_SEARCH_PATH |
                               G_SPAWN_STDOUT_TO_DEV_NULL |
                               G_SPAWN_STDERR_TO_DEV_NULL),
      nullptr, nullptr, nullptr, &spawn_err);

  if (!spawned) {
    g_unlink(script_path);
    std::string msg = spawn_err != nullptr
                          ? spawn_err->message
                          : "Failed to spawn detached Linux updater process.";
    if (spawn_err != nullptr) g_error_free(spawn_err);
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "UPDATER_LAUNCH_FAILED", msg.c_str(), nullptr));
  }

  if (exit_current_app) {
    g_timeout_add(
        150,
        +[](gpointer) -> gboolean {
          exit(0);
          return G_SOURCE_REMOVE;
        },
        nullptr);
  }

  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

// Called when a method call is received from Flutter.
static void xue_hua_navite_auto_update_plugin_handle_method_call(
    XueHuaNaviteAutoUpdatePlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (strcmp(method, "checkEnvironment") == 0) {
    response = handle_check_environment();
  } else if (strcmp(method, "verifyPackageChecksum") == 0) {
    std::string file_path = LookupStringField(args, "filePath", "");
    std::string expected_sha256 = LookupStringField(args, "expectedSha256", "");
    if (file_path.empty() || expected_sha256.empty()) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "INVALID_ARGUMENTS", "filePath and expectedSha256 are required.",
          nullptr));
    } else {
      gboolean matched = verify_file_sha256_linux(file_path.c_str(),
                                                  expected_sha256.c_str());
      g_autoptr(FlValue) res_val = fl_value_new_bool(matched);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(res_val));
    }
  } else if (strcmp(method, "installAndRelaunch") == 0) {
    response = handle_install_and_relaunch(args);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void xue_hua_navite_auto_update_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(xue_hua_navite_auto_update_plugin_parent_class)->dispose(object);
}

static void xue_hua_navite_auto_update_plugin_class_init(
    XueHuaNaviteAutoUpdatePluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = xue_hua_navite_auto_update_plugin_dispose;
}

static void xue_hua_navite_auto_update_plugin_init(
    XueHuaNaviteAutoUpdatePlugin* self) {}

static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  XueHuaNaviteAutoUpdatePlugin* plugin =
      XUE_HUA_NAVITE_AUTO_UPDATE_PLUGIN(user_data);
  xue_hua_navite_auto_update_plugin_handle_method_call(plugin, method_call);
}

void xue_hua_navite_auto_update_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  XueHuaNaviteAutoUpdatePlugin* plugin = XUE_HUA_NAVITE_AUTO_UPDATE_PLUGIN(
      g_object_new(xue_hua_navite_auto_update_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "xue_hua_navite_auto_update",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}
