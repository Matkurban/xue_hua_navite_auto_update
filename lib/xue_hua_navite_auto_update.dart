import 'src/models.dart';
import 'xue_hua_navite_auto_update_platform_interface.dart';

export 'src/models.dart';
export 'src/sha256.dart' show StreamingSha256;
export 'xue_hua_navite_auto_update_method_channel.dart'
    show MethodChannelXueHuaNaviteAutoUpdate;
export 'xue_hua_navite_auto_update_platform_interface.dart'
    show XueHuaNaviteAutoUpdatePlatform;

/// One-click desktop auto-update and self-relaunch controller for Flutter
/// across **macOS** (`.dmg`, `.pkg`), **Windows** (Inno Setup `.exe`), and
/// **Linux** (`.AppImage`, `.deb`, `.rpm`).
///
/// Features:
/// - **Standard Installer Reuse**: Consumes standard platform installer packages
///   directly without requiring a custom delta format.
/// - **Out-of-Process Native Progress UI**: Spawns a detached native progress
///   window (`NSPanel` on macOS, Inno Setup `/SILENT` window on Windows,
///   `zenity` / `kdialog` on Linux) before the Flutter app exits, eliminating
///   any desktop blank gap.
/// - **On-Demand Elevation & Rollback**: Automatically prompts for administrator
///   authorization (macOS Touch ID / password, Windows UAC, Linux Polkit `pkexec`)
///   when needed, and rolls back to the previous `.app` / binary and relaunches
///   it if authorization is cancelled or installation fails.
class XueHuaNaviteAutoUpdate {
  /// Creates a [XueHuaNaviteAutoUpdate] instance.
  const XueHuaNaviteAutoUpdate();

  /// Shared singleton instance of [XueHuaNaviteAutoUpdate].
  static const XueHuaNaviteAutoUpdate instance = XueHuaNaviteAutoUpdate();

  /// Inspects the current desktop runtime environment.
  ///
  /// Returns an [UpdateEnvironmentInfo] describing:
  /// - Current platform (`macos`, `windows`, `linux`)
  /// - Main executable path (`executablePath`) and outer bundle path (`bundlePath`)
  /// - Current process ID (`processId`)
  /// - Whether auto-update is supported (`canAutoUpdate`)
  /// - Whether administrator elevation will be prompted (`requiresElevation`)
  /// - Specific block reason (`blockReason`), such as running directly inside a
  ///   read-only mounted `.dmg` (`/Volumes/`) or Gatekeeper `/AppTranslocation/`.
  Future<UpdateEnvironmentInfo> checkEnvironment() {
    return XueHuaNaviteAutoUpdatePlatform.instance.checkEnvironment();
  }

  /// Streams and verifies the SHA-256 checksum of [filePath] against
  /// [expectedSha256].
  ///
  /// Uses native streaming SHA-256 calculation (Apple `CryptoKit` on macOS,
  /// Win32 `BCrypt` CNG on Windows, GLib `GChecksum` on Linux, with a pure-Dart
  /// streaming fallback) so multi-hundred-megabyte installers never block UI
  /// memory.
  Future<bool> verifyPackageChecksum({
    required String filePath,
    required String expectedSha256,
  }) {
    return XueHuaNaviteAutoUpdatePlatform.instance.verifyPackageChecksum(
      filePath: filePath,
      expectedSha256: expectedSha256,
    );
  }

  /// Launches the detached native out-of-process updater for [packagePath] and
  /// immediately exits the current Flutter application so the update can be
  /// applied and relaunched.
  ///
  /// Parameters:
  /// - [packagePath]: Absolute local path to the downloaded installer package.
  /// - [packageType]: Optional explicit package format. If omitted, automatically
  ///   inferred from [packagePath]'s extension (`.dmg`, `.pkg`, `.exe`,
  ///   `.AppImage`, `.deb`, `.rpm`).
  /// - [showProgressDialog]: Whether to display the standalone native update
  ///   progress window after the main app closes (defaults to `true`).
  /// - [strings]: Localized strings displayed inside the native progress window.
  /// - [relaunchArgs]: Command-line arguments forwarded to the newly launched
  ///   application instance after update completion.
  /// - [exitCurrentApp]: Whether the native plugin should terminate the current
  ///   process immediately after spawning the detached updater (defaults to `true`).
  Future<void> installAndRelaunch({
    required String packagePath,
    UpdatePackageType? packageType,
    bool showProgressDialog = true,
    UpdateProgressStrings strings = const UpdateProgressStrings(),
    List<String> relaunchArgs = const <String>[],
    bool exitCurrentApp = true,
  }) {
    final trimmedPath = packagePath.trim();
    if (trimmedPath.isEmpty) {
      throw ArgumentError.value(
        packagePath,
        'packagePath',
        'packagePath must not be empty.',
      );
    }
    final resolvedType =
        packageType ?? UpdatePackageType.inferFromPath(trimmedPath);
    return XueHuaNaviteAutoUpdatePlatform.instance.installAndRelaunch(
      packagePath: trimmedPath,
      packageType: resolvedType,
      showProgressDialog: showProgressDialog,
      strings: strings,
      relaunchArgs: relaunchArgs,
      exitCurrentApp: exitCurrentApp,
    );
  }
}
