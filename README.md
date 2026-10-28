# xue_hua_navite_auto_update

**English** | [简体中文](README_ZH.md)

[![Pub Version](https://img.shields.io/badge/pub-v1.0.1-blue)](https://github.com/Matkurban/xue_hua_navite_auto_update)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-blueviolet)](https://github.com/Matkurban/xue_hua_navite_auto_update)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](LICENSE)

`xue_hua_navite_auto_update` is a production-grade **one-click auto-update and self-relaunch plugin** for Flutter desktop applications across **macOS**, **Windows**, and **Linux**.

Designed to deliver the same seamless update experience as **VS Code, Sparkle, and Lark/Feishu Desktop**:
1. **Reuses Standard Platform Installers**: Directly accepts standard installer packages already produced by your CI/CD pipeline (`.dmg` / `.pkg` on macOS, Inno Setup `.exe` on Windows, `.AppImage` / `.deb` / `.rpm` on Linux) without requiring custom binary delta formats.
2. **Seamless Out-of-Process Native Progress UI**: As soon as the user clicks "Restart & Update", the main Flutter app exits cleanly while a **detached native updater process** displays a centered, modern OS progress window (showing real-time progress and localized status text such as *"Waiting for application to close..."*, *"Mounting and verifying update package..."*, *"Installing new version..."*, *"Relaunching application..."*), eliminating any blank desktop gap after app exit.
3. **On-Demand Privilege Elevation & Automatic Rollback**: Automatically triggers native OS elevation prompts (macOS Touch ID / password, Windows UAC, Linux Polkit `pkexec`) only when required by directory permissions. Once installed, the progress window closes and launches the updated app. If the user cancels authorization or verification fails, the updater **automatically rolls back to `.bak` and relaunches the previous version**, ensuring the application never disappears.

---

## Table of Contents

1. [Architecture Flow & Platform Support Matrix](#1-architecture-flow--platform-support-matrix)
2. [Installation & Requirements](#2-installation--requirements)
3. [Dart API Reference](#3-dart-api-reference)
4. [Complete Flutter Integration Example](#4-complete-flutter-integration-example)
5. [Platform Packaging & Signing Guides (Copy-Paste Templates)](#5-platform-packaging--signing-guides-copy-paste-templates)
   - [5.1 Windows Inno Setup (`.iss`) Template](#51-windows-inno-setup-iss-template)
   - [5.2 macOS (`.dmg` / `.pkg`) Packaging, Signing & Notarization](#52-macos-dmg--pkg-packaging-signing--notarization)
   - [5.3 Linux (`.AppImage` / `.deb` / `.rpm`) Packaging Guide](#53-linux-appimage--deb--rpm-packaging-guide)
6. [Limitations & Edge Cases](#6-limitations--edge-cases)
7. [AI Coding Agent Skills](#7-ai-coding-agent-skills)
8. [Author & License](#8-author--license)

---

## 1. Architecture Flow & Platform Support Matrix

### 1.1 Out-of-Process Update & Self-Relaunch Sequence

```text
┌───────────────────────────┐          ┌──────────────────────────────────────────┐
│   Main Flutter Process    │          │    Detached Native Updater Process       │
└─────────────┬─────────────┘          └─────────────────────┬────────────────────┘
              │                                              │
  1. checkEnvironment()                                      │
     Check read-only volume / AppTranslocation / ACLs        │
              │                                              │
  2. verifyPackageChecksum()                                 │
     Stream & verify SHA-256 digest                          │
              │                                              │
  3. installAndRelaunch() ───────── Spawn detached helper ──▶│
              │                                              │ [Stage 1 - 15%]
  4. Main app exits cleanly (exit 0)                         │ Show centered native progress window
              ✕                                              │ Poll kill(mainPid, 0) / Get-Process until exit
                                                             │
                                                             │ [Stage 2 - 40%]
                                                             │ • macOS: Silent hdiutil attach + codesign verify
                                                             │ • Windows: Prepare Inno Setup /SILENT flags
                                                             │ • Linux: Prepare AppImage / DEB / RPM installer
                                                             │
                                                             │ [Stage 3 - 75%]
                                                             │ • Writable dir: Backup .bak -> atomic copy
                                                             │ • Protected dir: Prompt Touch ID / UAC / Polkit
                                                             │   ├─ On cancel/error: Restore .bak backup
                                                             │   └─ On success: Clear quarantine (xattr -cr) & remove .bak
                                                             │
                                       ┌─────────────────────┤ [Stage 4 - 100%]
                                       ▼                     │ Detach DMG & close progress window
┌─────────────────────────────────────────┐                  │ Relaunch app as standard desktop user
│  Updated (or Rolled-back) App Launches  │◀─────────────────┘ (Forwarding relaunchArgs)
└─────────────────────────────────────────┘
```

### 1.2 Platform Support Matrix

| Platform | Supported Formats | Out-of-Process Progress UI | Privilege Elevation (On-Demand) | Rollback & Relaunch Guarantee |
| :--- | :--- | :--- | :--- | :--- |
| **macOS** (`12.0+`, Swift + SPM) | `.dmg`<br>`.pkg` | Detached `/usr/bin/swift` AppKit HUD window (`NSPanel` + `NSVisualEffectView` + `NSProgressIndicator`, dark-mode adaptive) | **Passwordless** if `/Applications` is writable by the current user; otherwise prompts **Touch ID / Admin Password** via `osascript` (`with administrator privileges`) | Backs up `.app` to `.app.bak`; restores `.app.bak` and relaunches via `/usr/bin/open -n` if `codesign` fails, copy fails, or password prompt is cancelled |
| **Windows** (`Win10/11`, C++ Win32) | Inno Setup `.exe` | Passes `/SILENT /SUPPRESSMSGBOXES /NORESTART /SP- /CLOSEAPPLICATIONS` when `showProgressDialog: true` (shows **Inno Setup's native progress bar window** while skipping wizard pages) | - `PrivilegesRequired=lowest` (`AppData\Local\Programs`): **Zero UAC prompts**<br>- `PrivilegesRequired=admin` (`Program Files`): **Single UAC prompt** | Detached hidden guardian process (absolute `powershell.exe` path, `CREATE_NO_WINDOW \| CREATE_BREAKAWAY_FROM_JOB`, WMI fallback) waits for the installer to exit and explicitly relaunches the `.exe` if `[Run]` did not start it or UAC was cancelled |
| **Linux** (`GTK3`, C++ & Polkit) | `.AppImage`<br>`.deb`<br>`.rpm` | Centered native `zenity --progress --auto-close --no-cancel` dialog showing real-time stage percentages | - `.AppImage`: **Passwordless** atomic replacement of `$APPIMAGE`<br>- `.deb`: `pkexec apt-get install -y --allow-downgrades`<br>- `.rpm`: `pkexec dnf install -y` / `zypper` / `rpm -Uvh` (**Polkit graphical dialog**) | `.AppImage` backs up `.bak` and restores on failure; `.deb`/`.rpm` always drops back to the **non-root desktop user** and relaunches via `nohup` |

---

## 2. Installation & Requirements

### 2.1 SDK Constraints

- **Dart SDK**: `>=3.13.0 <4.0.0`
- **Flutter SDK**: `>=3.47.0`
- **Platforms**: macOS (`>= 12.0`), Windows (`Windows 10 / 11`), Linux (`Debian / Ubuntu / Deepin / Mint / Fedora / RHEL / openSUSE`)

### 2.2 Add Dependency in `pubspec.yaml`

```yaml
dependencies:
  xue_hua_navite_auto_update: ^1.0.0
```

Or depend directly on the GitHub repository:

```yaml
dependencies:
  xue_hua_navite_auto_update:
    git:
      url: https://github.com/Matkurban/xue_hua_navite_auto_update.git
      ref: main
```

---

## 3. Dart API Reference

```dart
import 'package:xue_hua_navite_auto_update/xue_hua_navite_auto_update.dart';
```

### 3.1 `checkEnvironment()` — Pre-flight Environment Inspection

```dart
Future<UpdateEnvironmentInfo> checkEnvironment()
```

Returns an `UpdateEnvironmentInfo` object containing:
- `platform` (`String`): Host platform identifier (`macos`, `windows`, `linux`).
- `executablePath` (`String`): Absolute path to the running binary.
- `bundlePath` (`String`): Outer `.app` bundle path on macOS, installation directory on Windows, or `$APPIMAGE` / binary directory on Linux.
- `processId` (`int`): Current process ID (`PID`).
- `canAutoUpdate` (`bool`): Whether in-place auto-update is supported in the current location.
- `requiresElevation` (`bool`): Whether administrator authentication (Touch ID / UAC / Polkit) will be requested during installation.
- `blockReason` (`UpdateBlockReason`): Specific reason when `canAutoUpdate == false`:
  - `UpdateBlockReason.none`: Ready for auto-update.
  - `UpdateBlockReason.runningOnReadOnlyVolume`: Running directly inside a mounted read-only `.dmg` volume (`/Volumes/...`).
  - `UpdateBlockReason.runningInAppTranslocation`: Running inside Gatekeeper App Translocation (`/AppTranslocation/...`).
  - `UpdateBlockReason.runningInSandboxOrStore`: Running inside Mac App Store Sandbox, Windows MSIX, or Linux Snap/Flatpak.
  - `UpdateBlockReason.missingAppImageEnv`: Missing `$APPIMAGE` environment variable for an AppImage update.
- `statusMessage` (`String`): Human-readable diagnostic message.

### 3.2 `verifyPackageChecksum()` — Streaming SHA-256 Verification

```dart
Future<bool> verifyPackageChecksum({
  required String filePath,
  required String expectedSha256,
})
```

Streams `filePath` in 64 KB chunks using native OS cryptography (`CryptoKit` on macOS, Win32 `BCrypt` on Windows, GLib `GChecksum` on Linux, with a pure-Dart streaming fallback) and compares the digest against `expectedSha256`.

### 3.3 `installAndRelaunch()` — Detached Native Progress UI, Install & Relaunch

```dart
Future<void> installAndRelaunch({
  required String packagePath,
  UpdatePackageType? packageType,
  bool showProgressDialog = true,
  UpdateProgressStrings strings = const UpdateProgressStrings(),
  List<String> relaunchArgs = const <String>[],
  bool exitCurrentApp = true,
})
```

- `packagePath`: Absolute local path to the downloaded installer package.
- `packageType`: Optional explicit format (`dmg`, `pkg`, `exe`, `appImage`, `deb`, `rpm`). Automatically inferred from `packagePath` extension when omitted.
- `showProgressDialog`: Whether to display the standalone native update progress window after the main app exits (defaults to `true`).
- `strings`: Localized strings for the native progress window (`const UpdateProgressStrings()` for English or `const UpdateProgressStrings.zhCN()` for Simplified Chinese).
- `relaunchArgs`: Command-line arguments forwarded to the newly launched application instance.

---

## 4. Complete Flutter Integration Example

```dart
import 'package:flutter/material.dart';
import 'package:xue_hua_navite_auto_update/xue_hua_navite_auto_update.dart';

class DesktopUpdateManager {
  static final XueHuaNaviteAutoUpdate _updater =
      XueHuaNaviteAutoUpdate.instance;

  static Future<void> checkAndInstallUpdate({
    required BuildContext context,
    required String downloadedInstallerPath,
    required String expectedSha256,
    bool isZhCN = false,
  }) async {
    // 1. Pre-flight environment check
    final env = await _updater.checkEnvironment();
    if (!env.canAutoUpdate) {
      if (!context.mounted) return;
      if (env.blockReason == UpdateBlockReason.runningOnReadOnlyVolume ||
          env.blockReason == UpdateBlockReason.runningInAppTranslocation) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Move Application to /Applications'),
            content: Text(
              'The app is currently running from a read-only volume or translocated path:\n'
              '${env.bundlePath}\n\n'
              'Please drag the application into your /Applications folder and relaunch it to enable automatic updates.',
            ),
            actions: <Widget>[
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // 2. Verify installer SHA-256 checksum
    final checksumOk = await _updater.verifyPackageChecksum(
      filePath: downloadedInstallerPath,
      expectedSha256: expectedSha256,
    );
    if (!checksumOk) {
      throw StateError('SHA-256 verification failed for $downloadedInstallerPath');
    }

    // 3. Configure localized progress UI strings
    final strings = isZhCN
        ? const UpdateProgressStrings.zhCN()
        : const UpdateProgressStrings(
            windowTitle: 'Updating Application',
            waitingForAppExitText: 'Waiting for application to close...',
            mountingPackageText: 'Mounting and verifying update package...',
            installingUpdateText: 'Installing new version...',
            relaunchingText: 'Update complete, relaunching application...',
          );

    // 4. Launch detached progress UI, install update, and relaunch
    await _updater.installAndRelaunch(
      packagePath: downloadedInstallerPath,
      showProgressDialog: true,
      strings: strings,
      relaunchArgs: const <String>['--updated'],
    );
  }
}
```

---

## 5. Platform Packaging & Signing Guides (Copy-Paste Templates)

### 5.1 Windows Inno Setup (`.iss`) Template

- **`PrivilegesRequired=lowest` (Recommended, like VS Code User Installer)**: Installs into `C:\Users\<User>\AppData\Local\Programs\MyApp`. Updates display the native Inno Setup `/SILENT` progress window and complete **without any UAC prompt**.
- **`PrivilegesRequired=admin`**: Installs into `C:\Program Files\MyApp`. Updates prompt for Windows UAC once before displaying the `/SILENT` progress window.

```iss
#define MyAppName "XueHuaDesktop"
#define MyAppVersion "2.0.0"
#define MyAppPublisher "Matkurban"
#define MyAppExeName "xue_hua_desktop.exe"
; IMPORTANT: Keep AppId identical across all versions so Inno Setup overwrites the existing installation directory!
#define MyAppId "{{8F9A2B3C-4D5E-6F70-8A9B-0C1D2E3F4A5B}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=XueHuaDesktop_Setup_{#MyAppVersion}
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=force
RestartApplications=no

[Files]
Source: "build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
```

### 5.2 macOS (`.dmg` / `.pkg`) Packaging, Signing & Notarization

1. **Disable App Sandbox in `macos/Runner/Release.entitlements`**:
   Direct-distribution apps must set `<key>com.apple.security.app-sandbox</key><false/>` and sign with **Hardened Runtime + Developer ID Application + Apple Notarization**.
2. **Atomic Synchronization of Embedded Extensions (`ShareExtension.appex`)**:
   Because `.dmg` updates replace the entire `.app` bundle atomically via `/usr/bin/ditto` and clear quarantine attributes via `xattr -cr`, any embedded extensions inside `Contents/PlugIns/` (such as `ShareExtension.appex`) are updated atomically alongside the main app.
3. **Packaging Commands**:
   ```bash
   flutter build macos --release
   codesign --force --deep --options runtime --timestamp \
     --entitlements macos/Runner/Release.entitlements \
     --sign "Developer ID Application: Your Name (TEAM_ID)" \
     build/macos/Build/Products/Release/MyApp.app

   mkdir -p build/dmg_staging
   cp -R build/macos/Build/Products/Release/MyApp.app build/dmg_staging/
   ln -s /Applications build/dmg_staging/Applications
   hdiutil create -volname "MyApp" -srcfolder build/dmg_staging -ov -format UDZO dist/MyApp_2.0.0.dmg
   ```

### 5.3 Linux (`.AppImage` / `.deb` / `.rpm`) Packaging Guide

- **`.AppImage`**: Replaces the file pointed to by `$APPIMAGE` atomically without root elevation and backs up `$APPIMAGE.bak` for rollback.
- **`.deb` / `.rpm`**: Keep the installed binary path (e.g., `/opt/myapp/myapp`) consistent across versions. The detached updater invokes `pkexec` to display the desktop Polkit authorization dialog and then relaunches the binary under the original non-root desktop user.

---

## 6. Limitations & Edge Cases

- **App Store & Container Sandboxes**: Mac App Store (`APP_SANDBOX_CONTAINER_ID`), Microsoft Store (`MSIX`), and Linux `Snap` / `Flatpak` prohibit self-replacement (`checkEnvironment()` returns `canAutoUpdate: false`, `blockReason: UpdateBlockReason.runningInSandboxOrStore`).
- **Running Directly from a Mounted `.dmg`**: Detected via `UpdateBlockReason.runningOnReadOnlyVolume` (`/Volumes/`) or `UpdateBlockReason.runningInAppTranslocation` (`/AppTranslocation/`). Prompt the user to drag the app into `/Applications`.
- **Authorization Cancelled by User**: Automatically restores `.app.bak` / `.bak` and relaunches the existing application binary so the app never vanishes.

---

## 7. AI Coding Agent Skills

This package ships with a built-in AI Agent Skill at `skills/xue-hua-navite-auto-update/SKILL.md` following the [Dart Package Skills specification](https://dart.dev/tools/pub/package-skills). Install it into your project with:

```bash
dart run skills@ get
```

---

## 8. Author & License

- **Author**: Matkurban ([3496354336@qq.com](mailto:3496354336@qq.com))
- **Repository**: [https://github.com/Matkurban/xue_hua_navite_auto_update](https://github.com/Matkurban/xue_hua_navite_auto_update)
- **License**: BSD 3-Clause License (see [LICENSE](LICENSE))
