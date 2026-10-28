## 1.0.1

* Shortened the package description to fit pub.dev search-snippet guidelines (60–180 characters).

## 1.0.0

* Initial release of `xue_hua_navite_auto_update` by Matkurban (3496354336@qq.com).
* **macOS (`Swift` + `SPM`)**:
  * Supports `.dmg` and `.pkg` standard installers.
  * Pre-flight environment check (`checkEnvironment`) for read-only `/Volumes/`, Gatekeeper `/AppTranslocation/`, App Sandbox, and `/Applications` write permissions.
  * Detached out-of-process native AppKit progress window (`NSPanel`/`NSWindow`) with 4-stage real-time progress bar, dark mode adaptation, silent DMG mounting (`hdiutil`), code signature verification (`codesign`), atomic backup & rollback (`.app.bak`), on-demand Touch ID / administrator authorization (`osascript`), and automatic relaunch (`open -n`).
* **Windows (`C++ Win32 API`)**:
  * Supports Inno Setup `.exe` installers with dynamic `/SILENT` (native progress window) and `/VERYSILENT` flags.
  * Detached background guardian script/process (`CREATE_NO_WINDOW | DETACHED_PROCESS`) ensuring 100% reliable application relaunch even if `[Run]` is omitted or UAC is cancelled.
  * Native streaming SHA-256 verification via Windows CNG (`BCrypt`).
* **Linux (`C++ GTK3 & Polkit`)**:
  * Supports `.AppImage`, `.deb`, and `.rpm` packages.
  * Out-of-process native progress dialog (`zenity` / `kdialog`) with Polkit (`pkexec`) graphical elevation for `.deb` / `.rpm` and non-root user relaunch.
  * Native streaming SHA-256 verification via GLib `GChecksum`.
