## 1.0.1

* **Windows**: Fix `installAndRelaunch` so the detached Inno Setup guardian actually stays alive after the Flutter process exits.
  * The previous `CreateProcessW` call launched `powershell.exe` via `PATH` with `CREATE_NO_WINDOW | DETACHED_PROCESS`. `CREATE_NO_WINDOW` is ignored when combined with `DETACHED_PROCESS`, and PowerShell's ConsoleHost often exits immediately without running `-File` — matching the leftover `%TEMP%\xue_hua_updater_guard_*.ps1` and the installer never starting.
  * If the app is inside a Windows Job Object with `KILL_ON_JOB_CLOSE` (common for desktop hosts), the child was also reaped by `ExitProcess`.
  * The guard is now started from the absolute Windows PowerShell path with `CREATE_BREAKAWAY_FROM_JOB | CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP`, falling back to WMI `Win32_Process.Create` (born outside the job) and `ShellExecuteEx`. The script writes a short `%TEMP%\xue_hua_updater_guard.log` line when it starts.
  * MSVC `UNICODE` build: `#undef GetObject` before including `wbemidl.h` (and around the `IWbemServices::GetObject` call) so wingdi's `GetObject` → `GetObjectW` rename cannot break the plugin DLL. The gtest runner no longer includes `shellapi.h` before `windows.h` (that produced `C2086 'int EXTERN_C'`).

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
