#include <flutter_linux/flutter_linux.h>

#include "include/xue_hua_navite_auto_update/xue_hua_navite_auto_update_plugin.h"

// Exposes plugin internals for unit testing on Linux.

// Handles the checkEnvironment method call.
FlMethodResponse* handle_check_environment();

// Verifies the SHA-256 checksum of `file_path` against `expected_sha256`.
gboolean verify_file_sha256_linux(const gchar* file_path,
                                  const gchar* expected_sha256);
