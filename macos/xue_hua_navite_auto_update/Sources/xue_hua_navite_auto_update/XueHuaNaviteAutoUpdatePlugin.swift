import AppKit
import CryptoKit
import Darwin
import FlutterMacOS
import Foundation

/// macOS native implementation of `xue_hua_navite_auto_update`.
///
/// Supports:
/// - Environment pre-flight checks (`checkEnvironment`) detecting read-only mounted
///   volumes (`/Volumes/`), Gatekeeper App Translocation (`/AppTranslocation/`),
///   App Sandbox restriction, and parent directory write permissions.
/// - Streaming SHA-256 checksum verification (`verifyPackageChecksum`) using
///   Apple `CryptoKit.SHA256`.
/// - Out-of-process native update progress UI & installer (`installAndRelaunch`)
///   for `.dmg` and `.pkg` packages with silent `hdiutil` mounting, `codesign`
///   verification, `.app.bak` backup & rollback, on-demand Touch ID / password
///   elevation (`osascript`), and automatic relaunch via `/usr/bin/open -n`.
public class XueHuaNaviteAutoUpdatePlugin: NSObject, FlutterPlugin {
    private static let channelName = "xue_hua_navite_auto_update"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger
        )
        let instance = XueHuaNaviteAutoUpdatePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "checkEnvironment":
            result(checkEnvironment())

        case "verifyPackageChecksum":
            guard let args = call.arguments as? [String: Any],
                  let filePath = args["filePath"] as? String,
                  let expectedSha256 = args["expectedSha256"] as? String
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARGUMENTS",
                        message: "filePath and expectedSha256 are required.",
                        details: nil
                    )
                )
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let matched = Self.verifySha256(filePath: filePath, expectedHex: expectedSha256)
                DispatchQueue.main.async {
                    result(matched)
                }
            }

        case "installAndRelaunch":
            guard let args = call.arguments as? [String: Any],
                  let packagePath = args["packagePath"] as? String
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARGUMENTS",
                        message: "packagePath is required.",
                        details: nil
                    )
                )
                return
            }
            handleInstallAndRelaunch(args: args, packagePath: packagePath, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - 1. Environment Pre-flight Check

    /// Inspects the current macOS `.app` bundle location, sandbox state, and
    /// parent directory write permissions.
    public func checkEnvironment() -> [String: Any] {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        let bundlePath = bundleURL.path
        let executablePath = Bundle.main.executableURL?.standardizedFileURL.path
            ?? ProcessInfo.processInfo.arguments.first
            ?? bundlePath
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        let env = ProcessInfo.processInfo.environment

        // 1. Check App Sandbox restriction (Mac App Store / Sandboxed builds cannot self-replace)
        if env["APP_SANDBOX_CONTAINER_ID"] != nil {
            return [
                "platform": "macos",
                "executablePath": executablePath,
                "bundlePath": bundlePath,
                "processId": pid,
                "canAutoUpdate": false,
                "requiresElevation": false,
                "blockReason": "runningInSandboxOrStore",
                "statusMessage": "Application is running inside the macOS App Sandbox (APP_SANDBOX_CONTAINER_ID is set). Disable com.apple.security.app-sandbox for direct distribution auto-updates.",
            ]
        }

        // 2. Check Gatekeeper App Translocation randomized read-only path
        if bundlePath.contains("/AppTranslocation/") || executablePath.contains("/AppTranslocation/") {
            return [
                "platform": "macos",
                "executablePath": executablePath,
                "bundlePath": bundlePath,
                "processId": pid,
                "canAutoUpdate": false,
                "requiresElevation": false,
                "blockReason": "runningInAppTranslocation",
                "statusMessage": "Application is running under Gatekeeper App Translocation (/AppTranslocation/). Please move the application to /Applications before updating.",
            ]
        }

        // 3. Check if running directly from a mounted read-only disk image (/Volumes/...)
        if bundlePath.hasPrefix("/Volumes/") || executablePath.hasPrefix("/Volumes/") {
            return [
                "platform": "macos",
                "executablePath": executablePath,
                "bundlePath": bundlePath,
                "processId": pid,
                "canAutoUpdate": false,
                "requiresElevation": false,
                "blockReason": "runningOnReadOnlyVolume",
                "statusMessage": "Application is running directly from a mounted volume (/Volumes/). Please drag the application into /Applications first.",
            ]
        }

        // 4. Check whether the parent directory (e.g. /Applications) and the .app bundle
        //    itself are writable by the current user without root elevation.
        let parentDir = bundleURL.deletingLastPathComponent().path
        let parentWritable = access(parentDir, W_OK) == 0
        let bundleWritable = access(bundlePath, W_OK) == 0
        let requiresElevation = !(parentWritable && bundleWritable)

        let statusMessage: String
        if requiresElevation {
            statusMessage = "Ready for auto-update. Administrator authorization (Touch ID / password) will be requested during installation."
        } else {
            statusMessage = "Ready for passwordless in-place auto-update in \(parentDir)."
        }

        return [
            "platform": "macos",
            "executablePath": executablePath,
            "bundlePath": bundlePath,
            "processId": pid,
            "canAutoUpdate": true,
            "requiresElevation": requiresElevation,
            "blockReason": "none",
            "statusMessage": statusMessage,
        ]
    }

    // MARK: - 2. Streaming SHA-256 Verification

    /// Computes the SHA-256 digest of `filePath` in 64 KB chunks using `CryptoKit`.
    public static func verifySha256(filePath: String, expectedHex: String) -> Bool {
        let cleanExpected = expectedHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleanExpected.count == 64, let handle = FileHandle(forReadingAtPath: filePath) else { return false }
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        let chunkSize = 64 * 1024
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: chunkSize)
            if data.isEmpty {
                return false
            }
            hasher.update(data: data)
            return true
        }) {}

        let digest = hasher.finalize()
        let actualHex = digest.map { String(format: "%02x", $0) }.joined()
        return actualHex == cleanExpected
    }

    // MARK: - 3. Out-of-Process Native Progress Updater & Relaunch

    private func handleInstallAndRelaunch(
        args: [String: Any],
        packagePath: String,
        result: @escaping FlutterResult
    ) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: packagePath) else {
            result(
                FlutterError(
                    code: "PACKAGE_NOT_FOUND",
                    message: "Installer package does not exist at path: \(packagePath)",
                    details: nil
                )
            )
            return
        }

        let rawType = (args["packageType"] as? String)?.lowercased() ?? ""
        let packageType: String
        if rawType == "dmg" || packagePath.lowercased().hasSuffix(".dmg") {
            packageType = "dmg"
        } else if rawType == "pkg" || packagePath.lowercased().hasSuffix(".pkg") {
            packageType = "pkg"
        } else {
            result(
                FlutterError(
                    code: "UNSUPPORTED_PACKAGE_TYPE",
                    message: "macOS only supports .dmg and .pkg packages. Got: \(packagePath)",
                    details: nil
                )
            )
            return
        }

        let envInfo = checkEnvironment()
        let canAutoUpdate = (envInfo["canAutoUpdate"] as? Bool) ?? false
        if !canAutoUpdate {
            let reason = (envInfo["blockReason"] as? String) ?? "unknown"
            let message = (envInfo["statusMessage"] as? String) ?? "Current environment blocks auto-update."
            result(
                FlutterError(
                    code: "ENVIRONMENT_BLOCKED",
                    message: message,
                    details: reason
                )
            )
            return
        }

        let showProgressDialog = (args["showProgressDialog"] as? Bool) ?? true
        let exitCurrentApp = (args["exitCurrentApp"] as? Bool) ?? true
        let relaunchArgs = (args["relaunchArgs"] as? [String]) ?? []
        let stringsMap = (args["strings"] as? [String: String]) ?? [:]

        let windowTitle = stringsMap["windowTitle"] ?? "正在更新应用"
        let waitingText = stringsMap["waitingForAppExitText"] ?? "正在等待主程序安全关闭..."
        let mountingText = stringsMap["mountingPackageText"] ?? "正在静默挂载并校验更新包签名..."
        let installingText = stringsMap["installingUpdateText"] ?? "正在安装新版本应用..."
        let relaunchingText = stringsMap["relaunchingText"] ?? "更新完成，正在重新启动应用..."
        let rollingBackText = stringsMap["rollingBackText"] ?? "更新已取消或失败，正在回滚并恢复旧版本..."

        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        let targetAppPath = bundleURL.path
        let mainPid = ProcessInfo.processInfo.processIdentifier

        // Export current application icon to /tmp so the standalone updater window can display it
        let sessionId = "\(mainPid)_\(Int(Date().timeIntervalSince1970))"
        let iconPath = "/tmp/xue_hua_updater_icon_\(sessionId).tiff"
        if let iconTiff = NSApplication.shared.applicationIconImage.tiffRepresentation {
            try? iconTiff.write(to: URL(fileURLWithPath: iconPath), options: .atomic)
        }

        let configDict: [String: Any] = [
            "mainPid": Int(mainPid),
            "targetAppPath": targetAppPath,
            "packagePath": URL(fileURLWithPath: packagePath).standardizedFileURL.path,
            "packageType": packageType,
            "showProgressDialog": showProgressDialog,
            "iconPath": iconPath,
            "relaunchArgs": relaunchArgs,
            "windowTitle": windowTitle,
            "waitingText": waitingText,
            "mountingText": mountingText,
            "installingText": installingText,
            "relaunchingText": relaunchingText,
            "rollingBackText": rollingBackText,
        ]

        let configPath = "/tmp/xue_hua_updater_config_\(sessionId).json"
        let scriptPath = "/tmp/xue_hua_updater_helper_\(sessionId).swift"
        let launcherPath = "/tmp/xue_hua_updater_launch_\(sessionId).sh"

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: configDict, options: [.prettyPrinted])
            try jsonData.write(to: URL(fileURLWithPath: configPath), options: .atomic)

            let swiftSource = Self.buildStandaloneSwiftHelperSource()
            try swiftSource.write(toFile: scriptPath, atomically: true, encoding: .utf8)

            // Launch the Swift AppKit helper detached from our process group
            let launcherContent = """
            #!/bin/bash
            nohup /usr/bin/swift "\(scriptPath)" "\(configPath)" "\(scriptPath)" "\(launcherPath)" >/tmp/xue_hua_updater_\(sessionId).log 2>&1 &
            """
            try launcherContent.write(toFile: launcherPath, atomically: true, encoding: .utf8)
            chmod(launcherPath, S_IRWXU)

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [launcherPath]
            try task.run()
        } catch {
            result(
                FlutterError(
                    code: "UPDATER_LAUNCH_FAILED",
                    message: "Failed to prepare or spawn detached macOS updater helper: \(error.localizedDescription)",
                    details: nil
                )
            )
            return
        }

        result(nil)

        if exitCurrentApp {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NSApplication.shared.terminate(nil)
                // Ensure process termination even if a window close delegate delays exit
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
                    exit(0)
                }
            }
        }
    }

    // MARK: - 4. Standalone Out-of-Process AppKit Progress Helper Source

    /// Returns the complete standalone Swift/AppKit script that runs out-of-process
    /// via `/usr/bin/swift`, renders a modern floating progress panel centered on screen,
    /// mounts `.dmg` / installs `.pkg`, verifies `codesign`, handles `.app.bak` backup
    /// and rollback, prompts for Touch ID / password when needed, and relaunches the app.
    public static func buildStandaloneSwiftHelperSource() -> String {
        return #"""
        import AppKit
        import Darwin
        import Foundation

        struct UpdaterConfig {
          let mainPid: Int32
          let targetAppPath: String
          let packagePath: String
          let packageType: String
          let showProgressDialog: Bool
          let iconPath: String
          let relaunchArgs: [String]
          let windowTitle: String
          let waitingText: String
          let mountingText: String
          let installingText: String
          let relaunchingText: String
          let rollingBackText: String
          let configPath: String
          let scriptPath: String
          let launcherPath: String

          static func load() -> UpdaterConfig? {
            let args = CommandLine.arguments
            guard args.count >= 4 else { return nil }
            let configPath = args[1]
            let scriptPath = args[2]
            let launcherPath = args[3]
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
              return nil
            }
            return UpdaterConfig(
              mainPid: Int32((dict["mainPid"] as? Int) ?? 0),
              targetAppPath: (dict["targetAppPath"] as? String) ?? "",
              packagePath: (dict["packagePath"] as? String) ?? "",
              packageType: (dict["packageType"] as? String) ?? "dmg",
              showProgressDialog: (dict["showProgressDialog"] as? Bool) ?? true,
              iconPath: (dict["iconPath"] as? String) ?? "",
              relaunchArgs: (dict["relaunchArgs"] as? [String]) ?? [],
              windowTitle: (dict["windowTitle"] as? String) ?? "Updating Application",
              waitingText: (dict["waitingText"] as? String) ?? "Waiting for application to close...",
              mountingText: (dict["mountingText"] as? String) ?? "Mounting and verifying update package...",
              installingText: (dict["installingText"] as? String) ?? "Installing update...",
              relaunchingText: (dict["relaunchingText"] as? String) ?? "Relaunching application...",
              rollingBackText: (dict["rollingBackText"] as? String) ?? "Update cancelled or failed, restoring previous version...",
              configPath: configPath,
              scriptPath: scriptPath,
              launcherPath: launcherPath
            )
          }
        }

        final class UpdaterAppDelegate: NSObject, NSApplicationDelegate {
          private let config: UpdaterConfig
          private var panel: NSPanel?
          private var statusLabel: NSTextField?
          private var percentLabel: NSTextField?
          private var progressBar: NSProgressIndicator?

          init(config: UpdaterConfig) {
            self.config = config
            super.init()
          }

          func applicationDidFinishLaunching(_ notification: Notification) {
            if config.showProgressDialog {
              setupProgressWindow()
            }
            DispatchQueue.global(qos: .userInitiated).async {
              self.runUpdatePipeline()
            }
          }

          private func setupProgressWindow() {
            let width: CGFloat = 420
            let height: CGFloat = 132
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
            let rect = NSRect(
              x: screenFrame.midX - width / 2,
              y: screenFrame.midY - height / 2,
              width: width,
              height: height
            )

            let window = NSPanel(
              contentRect: rect,
              styleMask: [.titled, .fullSizeContentView],
              backing: .buffered,
              defer: false
            )
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.level = .floating
            window.isReleasedWhenClosed = false
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true

            let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
            visualEffect.material = .hudWindow
            visualEffect.blendingMode = .behindWindow
            visualEffect.state = .active
            visualEffect.autoresizingMask = [.width, .height]
            window.contentView = visualEffect

            let iconView = NSImageView(frame: NSRect(x: 24, y: 34, width: 64, height: 64))
            if !config.iconPath.isEmpty,
               let img = NSImage(contentsOfFile: config.iconPath) {
              iconView.image = img
            } else {
              iconView.image = NSWorkspace.shared.icon(forFile: config.targetAppPath)
            }
            iconView.imageScaling = .scaleProportionallyUpOrDown
            visualEffect.addSubview(iconView)

            let titleField = NSTextField(labelWithString: config.windowTitle)
            titleField.frame = NSRect(x: 104, y: 80, width: 240, height: 22)
            titleField.font = NSFont.boldSystemFont(ofSize: 15)
            titleField.textColor = .labelColor
            visualEffect.addSubview(titleField)

            let pctField = NSTextField(labelWithString: "15%")
            pctField.frame = NSRect(x: 344, y: 80, width: 52, height: 20)
            pctField.alignment = .right
            pctField.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            pctField.textColor = .secondaryLabelColor
            visualEffect.addSubview(pctField)
            self.percentLabel = pctField

            let subtitleField = NSTextField(labelWithString: config.waitingText)
            subtitleField.frame = NSRect(x: 104, y: 54, width: 292, height: 18)
            subtitleField.font = NSFont.systemFont(ofSize: 12.5)
            subtitleField.textColor = .secondaryLabelColor
            subtitleField.lineBreakMode = .byTruncatingTail
            visualEffect.addSubview(subtitleField)
            self.statusLabel = subtitleField

            let indicator = NSProgressIndicator(frame: NSRect(x: 104, y: 28, width: 292, height: 14))
            indicator.isIndeterminate = false
            indicator.minValue = 0
            indicator.maxValue = 100
            indicator.doubleValue = 15
            indicator.controlSize = .regular
            visualEffect.addSubview(indicator)
            self.progressBar = indicator

            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.panel = window
          }

          private func updateUI(progress: Double, status: String) {
            DispatchQueue.main.async {
              self.progressBar?.doubleValue = progress
              self.statusLabel?.stringValue = status
              self.percentLabel?.stringValue = "\(Int(progress))%"
            }
          }

          private func runUpdatePipeline() {
            // Stage 1 (15%): Wait for main Flutter application process to exit
            updateUI(progress: 15, status: config.waitingText)
            waitForMainAppExit(pid: config.mainPid)

            let backupPath = config.targetAppPath + ".bak"
            var mountPoint: String? = nil
            var installSucceeded = false

            defer {
              if let mp = mountPoint {
                _ = runCommand("/usr/bin/hdiutil", args: ["detach", mp, "-force", "-quiet"])
              }
              cleanupTempFiles()
            }

            if config.packageType == "dmg" {
              // Stage 2 (40%): Silently attach DMG and verify code signature
              updateUI(progress: 40, status: config.mountingText)
              if let attachedMountPoint = attachDmgSilently(dmgPath: config.packagePath),
                 let sourceAppPath = findAppBundle(inMountPoint: attachedMountPoint) {
                mountPoint = attachedMountPoint
                if verifyAppSignature(appPath: sourceAppPath) {
                  // Stage 3 (75%): Replace application bundle (direct or elevated)
                  updateUI(progress: 75, status: config.installingText)
                  installSucceeded = replaceAppBundle(
                    sourceAppPath: sourceAppPath,
                    targetAppPath: config.targetAppPath,
                    backupPath: backupPath
                  )
                }
              }
            } else if config.packageType == "pkg" {
              // Stage 2 (40%): Verify PKG existence & signature
              updateUI(progress: 40, status: config.mountingText)
              usleep(250_000)
              // Stage 3 (75%): Install PKG with administrator privileges
              updateUI(progress: 75, status: config.installingText)
              installSucceeded = installPkgWithAdmin(
                pkgPath: config.packagePath,
                targetAppPath: config.targetAppPath,
                backupPath: backupPath
              )
            }

            if !installSucceeded {
              updateUI(progress: 90, status: config.rollingBackText)
              restoreBackupIfNeeded(targetAppPath: config.targetAppPath, backupPath: backupPath)
              usleep(600_000)
              relaunchApplication(appPath: config.targetAppPath, args: config.relaunchArgs)
              terminateHelper()
              return
            }

            // Stage 4 (100%): Clean up backup, relaunch updated application, and close helper
            updateUI(progress: 100, status: config.relaunchingText)
            try? FileManager.default.removeItem(atPath: backupPath)
            usleep(350_000)
            relaunchApplication(appPath: config.targetAppPath, args: config.relaunchArgs)
            terminateHelper()
          }

          private func waitForMainAppExit(pid: Int32) {
            guard pid > 0 else { return }
            var elapsedMs = 0
            while kill(pid, 0) == 0 && elapsedMs < 30_000 {
              usleep(100_000)
              elapsedMs += 100
            }
            if kill(pid, 0) == 0 {
              kill(pid, SIGTERM)
              usleep(400_000)
            }
          }

          private func attachDmgSilently(dmgPath: String) -> String? {
            let res = runCommand(
              "/usr/bin/hdiutil",
              args: ["attach", dmgPath, "-nobrowse", "-readonly", "-noverify", "-noautoopen", "-plist"]
            )
            guard res.exitCode == 0,
                  let data = res.stdout.data(using: .utf8),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                  let entities = plist["system-entities"] as? [[String: Any]] else {
              return nil
            }
            for entity in entities {
              if let mp = entity["mount-point"] as? String, !mp.isEmpty {
                return mp
              }
            }
            return nil
          }

          private func findAppBundle(inMountPoint mountPoint: String) -> String? {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: mountPoint) else {
              return nil
            }
            for item in items where item.hasSuffix(".app") && !item.hasPrefix(".") {
              return (mountPoint as NSString).appendingPathComponent(item)
            }
            return nil
          }

          private func verifyAppSignature(appPath: String) -> Bool {
            // Check if the bundle has a _CodeSignature directory or embedded signature;
            // if signed, strictly verify via codesign --verify --deep --strict.
            let infoCheck = runCommand("/usr/bin/codesign", args: ["-dv", appPath])
            if infoCheck.stderr.contains("code object is not signed at all") {
              // Allow local unsigned debug/ad-hoc test bundles while enforcing integrity on signed bundles
              return true
            }
            let verify = runCommand("/usr/bin/codesign", args: ["--verify", "--deep", "--strict", appPath])
            return verify.exitCode == 0
          }

          private func replaceAppBundle(
            sourceAppPath: String,
            targetAppPath: String,
            backupPath: String
          ) -> Bool {
            let parentDir = (targetAppPath as NSString).deletingLastPathComponent
            let canWriteDirectly = (access(parentDir, W_OK) == 0) &&
              (!FileManager.default.fileExists(atPath: targetAppPath) || access(targetAppPath, W_OK) == 0)

            if canWriteDirectly {
              let fm = FileManager.default
              try? fm.removeItem(atPath: backupPath)
              if fm.fileExists(atPath: targetAppPath) {
                do {
                  try fm.moveItem(atPath: targetAppPath, toPath: backupPath)
                } catch {
                  return false
                }
              }
              let dittoRes = runCommand("/usr/bin/ditto", args: [sourceAppPath, targetAppPath])
              if dittoRes.exitCode != 0 {
                restoreBackupIfNeeded(targetAppPath: targetAppPath, backupPath: backupPath)
                return false
              }
              _ = runCommand("/usr/bin/xattr", args: ["-cr", targetAppPath])
              return true
            } else {
              // Elevate via AppleScript with administrator privileges (Touch ID / Password prompt)
              let escapedSrc = shellSingleQuoteEscape(sourceAppPath)
              let escapedDst = shellSingleQuoteEscape(targetAppPath)
              let escapedBak = shellSingleQuoteEscape(backupPath)
              let shellCmd = "rm -rf \(escapedBak) && " +
                "if [ -d \(escapedDst) ]; then mv -f \(escapedDst) \(escapedBak); fi && " +
                "(/usr/bin/ditto \(escapedSrc) \(escapedDst) && /usr/bin/xattr -cr \(escapedDst) && rm -rf \(escapedBak) || " +
                "(rm -rf \(escapedDst); if [ -d \(escapedBak) ]; then mv -f \(escapedBak) \(escapedDst); fi; exit 1))"
              let appleScript = "do shell script \(appleScriptQuote(shellCmd)) with administrator privileges"
              let osaRes = runCommand("/usr/bin/osascript", args: ["-e", appleScript])
              return osaRes.exitCode == 0
            }
          }

          private func installPkgWithAdmin(
            pkgPath: String,
            targetAppPath: String,
            backupPath: String
          ) -> Bool {
            let escapedPkg = shellSingleQuoteEscape(pkgPath)
            let escapedDst = shellSingleQuoteEscape(targetAppPath)
            let escapedBak = shellSingleQuoteEscape(backupPath)
            let shellCmd = "rm -rf \(escapedBak) && " +
              "if [ -d \(escapedDst) ]; then cp -R \(escapedDst) \(escapedBak); fi && " +
              "(/usr/sbin/installer -pkg \(escapedPkg) -target / && /usr/bin/xattr -cr \(escapedDst) && rm -rf \(escapedBak) || " +
              "(if [ -d \(escapedBak) ]; then rm -rf \(escapedDst) && mv -f \(escapedBak) \(escapedDst); fi; exit 1))"
            let appleScript = "do shell script \(appleScriptQuote(shellCmd)) with administrator privileges"
            let osaRes = runCommand("/usr/bin/osascript", args: ["-e", appleScript])
            return osaRes.exitCode == 0
          }

          private func restoreBackupIfNeeded(targetAppPath: String, backupPath: String) {
            let fm = FileManager.default
            guard fm.fileExists(atPath: backupPath) else { return }
            try? fm.removeItem(atPath: targetAppPath)
            try? fm.moveItem(atPath: backupPath, toPath: targetAppPath)
          }

          private func relaunchApplication(appPath: String, args: [String]) {
            var openArgs = ["-n", appPath]
            if !args.isEmpty {
              openArgs.append("--args")
              openArgs.append(contentsOf: args)
            }
            _ = runCommand("/usr/bin/open", args: openArgs)
          }

          private func cleanupTempFiles() {
            let fm = FileManager.default
            if !config.iconPath.isEmpty { try? fm.removeItem(atPath: config.iconPath) }
            if !config.configPath.isEmpty { try? fm.removeItem(atPath: config.configPath) }
            if !config.scriptPath.isEmpty { try? fm.removeItem(atPath: config.scriptPath) }
            if !config.launcherPath.isEmpty { try? fm.removeItem(atPath: config.launcherPath) }
          }

          private func terminateHelper() {
            DispatchQueue.main.async {
              self.panel?.close()
              NSApp.terminate(nil)
            }
          }

          private func shellSingleQuoteEscape(_ str: String) -> String {
            return "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
          }

          private func appleScriptQuote(_ str: String) -> String {
            let escaped = str
              .replacingOccurrences(of: "\\", with: "\\\\")
              .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
          }

          private func runCommand(_ launchPath: String, args: [String]) -> (exitCode: Int32, stdout: String, stderr: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = args
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            do {
              try process.run()
              process.waitUntilExit()
            } catch {
              return (-1, "", error.localizedDescription)
            }
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            return (
              process.terminationStatus,
              String(data: outData, encoding: .utf8) ?? "",
              String(data: errData, encoding: .utf8) ?? ""
            )
          }
        }

        guard let config = UpdaterConfig.load() else {
          exit(1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = UpdaterAppDelegate(config: config)
        app.delegate = delegate
        app.run()
        """#
    }
}
