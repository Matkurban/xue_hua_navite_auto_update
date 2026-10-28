---
name: xue-hua-navite-auto-update
description: >-
  Use when the user is working with xue_hua_navite_auto_update APIs
  (XueHuaNaviteAutoUpdate, UpdateEnvironmentInfo, UpdateProgressStrings,
  UpdatePackageType, UpdateBlockReason) to implement Flutter desktop (macOS,
  Windows, Linux) one-click auto-update and self-relaunch using standard
  installer packages (.dmg, .pkg, Inno Setup .exe, .AppImage, .deb, .rpm),
  out-of-process native progress dialogs, streaming SHA-256 verification,
  on-demand privilege elevation (Touch ID, UAC, Polkit pkexec), and automatic
  rollback.
---

# xue-hua-navite-auto-update

Provide idiomatic integration patterns, pre-flight environment checks, installer packaging configurations, and best practices for the `xue_hua_navite_auto_update` Flutter desktop plugin across macOS, Windows, and Linux.

## When to Use

- Checking whether the running desktop application can self-update (`XueHuaNaviteAutoUpdate.instance.checkEnvironment()`, `UpdateEnvironmentInfo`, `UpdateBlockReason`)
- Detecting macOS read-only mounted `.dmg` (`/Volumes/`) or Gatekeeper `/AppTranslocation/` execution and guiding users to move the app into `/Applications`
- Verifying downloaded installer packages with streaming SHA-256 checksums (`verifyPackageChecksum`, `StreamingSha256`)
- Triggering one-click out-of-process update installation and automatic app relaunch (`installAndRelaunch`) with localized progress strings (`UpdateProgressStrings`, `UpdateProgressStrings.zhCN()`)
- Configuring macOS `.dmg` / `.pkg` signing, Windows Inno Setup `.iss` (`PrivilegesRequired`, `/SILENT` vs `/VERYSILENT`, `CloseApplications`), or Linux `.AppImage` / `.deb` / `.rpm` Polkit (`pkexec`) packaging

## Guidelines

1. **Always run `checkEnvironment()` before starting an update flow**:
   - Inspect `env.canAutoUpdate` and `env.blockReason`.
   - If `env.blockReason` is `UpdateBlockReason.runningOnReadOnlyVolume` or `UpdateBlockReason.runningInAppTranslocation` on macOS, prompt the user to drag the `.app` into `/Applications` before updating.
   - If `env.blockReason` is `UpdateBlockReason.runningInSandboxOrStore` (Mac App Store Sandbox, Windows MSIX, Linux Snap/Flatpak), disable in-app self-update and direct users to the store channel.
2. **Always verify package integrity before invoking `installAndRelaunch()`**:
   - Call `await XueHuaNaviteAutoUpdate.instance.verifyPackageChecksum(filePath: path, expectedSha256: sha256)` to stream-hash the downloaded installer on a background thread without loading large `.dmg` / `.exe` files into memory.
3. **Use `showProgressDialog: true` (default) for seamless out-of-process UX**:
   - When the user clicks "Restart & Update", the main Flutter app exits immediately while a detached native helper process displays a centered native progress window (macOS `NSPanel`, Windows Inno Setup `/SILENT` progress dialog, Linux `zenity` progress bar).
4. **Localize the native progress dialog via `UpdateProgressStrings`**:
   - Use `const UpdateProgressStrings.zhCN()` for Simplified Chinese or pass custom localized strings to `UpdateProgressStrings(...)`.
5. **macOS Entitlements Requirement**:
   - Direct-distribution macOS apps using `xue_hua_navite_auto_update` MUST set `<key>com.apple.security.app-sandbox</key><false/>` in `Release.entitlements` and use Hardened Runtime + Developer ID signing + Apple Notarization.

## Examples

### Complete Pre-flight Check, SHA-256 Verification, and Update Relaunch

```dart
import 'package:flutter/material.dart';
import 'package:xue_hua_navite_auto_update/xue_hua_navite_auto_update.dart';

Future<void> performDesktopUpdate({
  required BuildContext context,
  required String downloadedPackagePath,
  required String expectedSha256,
}) async {
  final updater = XueHuaNaviteAutoUpdate.instance;

  // 1. Pre-flight environment check
  final env = await updater.checkEnvironment();
  if (!env.canAutoUpdate) {
    if (env.blockReason == UpdateBlockReason.runningOnReadOnlyVolume ||
        env.blockReason == UpdateBlockReason.runningInAppTranslocation) {
      // Guide macOS user to move the app from the mounted DMG to /Applications
      debugPrint('Please move the application to /Applications first.');
    }
    return;
  }

  // 2. Streaming SHA-256 checksum verification
  final isValid = await updater.verifyPackageChecksum(
    filePath: downloadedPackagePath,
    expectedSha256: expectedSha256,
  );
  if (!isValid) {
    throw StateError('Installer SHA-256 checksum mismatch!');
  }

  // 3. Spawn detached native progress UI, install update, and relaunch
  await updater.installAndRelaunch(
    packagePath: downloadedPackagePath,
    showProgressDialog: true,
    strings: const UpdateProgressStrings.zhCN(
      windowTitle: '正在更新应用',
      waitingForAppExitText: '正在等待主程序安全关闭...',
      mountingPackageText: '正在静默挂载并校验更新包签名...',
      installingUpdateText: '正在安装新版本应用...',
      relaunchingText: '更新完成，正在重新启动应用...',
    ),
    relaunchArgs: const <String>['--updated'],
  );
}
```

## Platform Gotchas

- **macOS (`.dmg` / `.pkg`)**:
  - Silently attaches `.dmg` via `hdiutil attach -nobrowse -readonly -noverify -noautoopen -plist` so Finder never pops up a volume window.
  - Verifies `.app` code signatures via `codesign --verify --deep --strict`.
  - Backs up the existing `.app` to `.app.bak` before copying with `/usr/bin/ditto` and clearing quarantine attributes via `xattr -cr`. If copying fails or the user cancels the Touch ID / password prompt (`osascript`), `.app.bak` is automatically restored and relaunched.
- **Windows (Inno Setup `.exe`)**:
  - Passes `/SILENT /SUPPRESSMSGBOXES /NORESTART /SP- /CLOSEAPPLICATIONS` when `showProgressDialog: true`, displaying Inno Setup's native progress bar window without wizard pages.
  - Runs a detached background guardian script (`CREATE_NO_WINDOW | DETACHED_PROCESS`) that waits for the installer to finish and guarantees 100% app relaunch even if `[Run]` is omitted in `.iss` or the user cancels the UAC prompt.
- **Linux (`.AppImage` / `.deb` / `.rpm`)**:
  - `.AppImage` updates replace `$APPIMAGE` atomically with `.bak` rollback and require no root password.
  - `.deb` (`pkexec apt-get install -y --allow-downgrades`) and `.rpm` (`pkexec dnf install -y` / `zypper` / `rpm -Uvh --replacepkgs`) prompt for graphical Polkit authentication and always relaunch the app under the original non-root desktop user.
