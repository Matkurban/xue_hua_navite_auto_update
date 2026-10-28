# xue_hua_navite_auto_update example

Desktop workbench for [xue_hua_navite_auto_update](https://pub.dev/packages/xue_hua_navite_auto_update).

Use it to **manually verify** the plugin's `checkEnvironment` → optional `verifyPackageChecksum` → `installAndRelaunch` flow by picking a real installer with [xue_hua_file_operations](https://pub.dev/packages/xue_hua_file_operations).

## Run the workbench

From this `example/` directory:

```bash
flutter pub get
flutter run -d macos
# flutter run -d windows
# flutter run -d linux
```

For a real in-place update, install a packaged build (not `flutter run` from the repo) so `checkEnvironment()` reports `canAutoUpdate: true`. Debug `flutter run` on macOS often lives in a derived-data / build folder that is fine for picking files, but the cleanest test is:

1. Bump `version` in `example/pubspec.yaml` (for example `1.0.0+1` → `1.0.1+2`).
2. Package a **newer** installer with [fpack](https://github.com/Matkurban/fpack) (`fpack.yaml` in this directory).
3. Install / copy the **older** app into a writable location (`/Applications` on macOS, the Inno user-install dir on Windows, a writable `.AppImage` path, or the same `/opt/xue-hua-navite-auto-update-example` prefix used by `.deb` / `.rpm`).
4. Launch that older app, then pick the newer artifact.

## Manual test: pick a freshly built fpack artifact

### 1. Build an installer

From `example/`:

```bash
fpack doctor
fpack build dmg --no-sign --force          # macOS
fpack build exe --force                    # Windows (needs Inno Setup)
fpack build appimage deb rpm --force       # Linux (rpm can be *built* on Debian hosts)
```

Artifacts land under `example/dist/{version}/` (see `fpack.yaml`). `SHA256SUMS` is written next to them when checksums are enabled.

Typical names:

| Platform | Pick this file |
| :--- | :--- |
| macOS | `*.dmg` or `*.pkg` |
| Windows | Inno Setup `*.exe` |
| Linux | `*.AppImage`, `*.deb`, or `*.rpm` |

### 2. (Optional) copy the SHA-256

Open `SHA256SUMS` and paste the 64-character hex digest for the artifact into **Expected SHA-256 Hex Digest** *before* picking the file. Leave the field empty to skip `verifyPackageChecksum`.

### 3. Pick and update

1. Launch the **older** installed example app.
2. Confirm card 1 (`checkEnvironment`) shows `canAutoUpdate: true`. On macOS, if the app is still on a mounted `.dmg` or under `/AppTranslocation/`, drag it into `/Applications` and relaunch first.
3. Click **选择更新包 / Pick update package**.
4. Choose the newer fpack artifact. The dialog is filtered to platform installer extensions (`dmg`/`pkg`, `exe`, or `AppImage`/`deb`/`rpm`).
5. The workbench logs the chosen name/path, re-runs `checkEnvironment`, optionally verifies SHA-256, then calls `installAndRelaunch` with the progress-dialog strings and relaunch args from card 3.
6. After the native progress window finishes, the app should relaunch. Launch args such as `--updated-from=1.0.0` appear in the event log.

Canceling the picker (`null`) only writes a log line. `FileOperationsException` is logged with its `ErrorCode` and message.

You can still paste a path and use **Verify SHA-256** / **立即重启并安装更新** without picking a file.

## Linux formats (AppImage / deb / rpm)

All three Linux artifacts share `linux.package_name` and `linux.prefix` in `fpack.yaml`. Build them together, then test each format from a **packaged** install of the older version (not `flutter run`).

```bash
fpack build appimage deb rpm --force
```

| Format | How to install the older app | What `installAndRelaunch` needs |
| :--- | :--- | :--- |
| `.AppImage` | `chmod +x` the older AppImage and launch it from a writable directory | `$APPIMAGE` must be set (the AppImage runtime injects this). Without it the plugin reports `missingAppImageEnv`. No Polkit / root password. |
| `.deb` | `sudo apt install ./…-linux-….deb` on Debian/Ubuntu | Same prefix as the newer `.deb` (`/opt/xue-hua-navite-auto-update-example/xue_hua_navite_auto_update_example`). `pkexec apt-get install` shows a graphical Polkit prompt. |
| `.rpm` | `sudo dnf install ./…-linux-….rpm` (or `zypper` / `rpm -Uvh`) | Same prefix as the newer `.rpm`. `pkexec dnf` / `zypper` / `rpm -Uvh --replacepkgs` shows Polkit. |

**rpm verify vs build:** Debian/Ubuntu hosts can still *build* `.rpm` with fpack. Install-and-relaunch verification belongs on Fedora, RHEL, or openSUSE (a desktop session with Polkit). After `pkexec` finishes, the updater relaunches as the original non-root desktop user — do not start the GUI as root.

Headless e2e on Linux uses `--e2e-package=` with a `.AppImage`, `.deb`, or `.rpm` path (same flags as below).

## Headless e2e flags (unchanged)

```text
--e2e-package=/path/to/update.(dmg|pkg|exe|AppImage|deb|rpm) --e2e-sha=<hex>
```

When `--e2e-package=` is present, the workbench still writes JSON to the platform temp dir as `xue_hua_auto_update_e2e.json` and runs the same verify + `installAndRelaunch` path. The pick-file button is for humans; do not remove these flags. Pass a real `.deb` or `.rpm` on Linux the same way you pass an `.AppImage`.

## Host permissions

- **macOS**: App Sandbox stays **off** (`com.apple.security.app-sandbox` = `false`) so the updater can replace the running `.app`. Both `DebugProfile.entitlements` and `Release.entitlements` also include `com.apple.security.files.user-selected.read-write` so `NSOpenPanel` file picking works if sandbox is later re-enabled.
- **Windows / Linux**: no extra manifest or permission is required for the system file dialog.

Android / iOS are out of scope for this desktop example.
