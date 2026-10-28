import 'package:flutter/foundation.dart';

/// Standard installer package formats supported by `xue_hua_navite_auto_update`.
enum UpdatePackageType {
  /// macOS Apple Disk Image (`.dmg`) containing the `.app` bundle.
  dmg('dmg'),

  /// macOS Installer Package (`.pkg`).
  pkg('pkg'),

  /// Windows Inno Setup executable installer (`.exe`).
  exe('exe'),

  /// Linux self-contained AppImage executable (`.AppImage`).
  appImage('appImage'),

  /// Debian / Ubuntu / Deepin / Linux Mint package (`.deb`).
  deb('deb'),

  /// Fedora / RHEL / openSUSE RPM package (`.rpm`).
  rpm('rpm');

  const UpdatePackageType(this.wireValue);

  /// The serialized string identifier sent over the platform channel.
  final String wireValue;

  /// Parses an [UpdatePackageType] from its serialized [wireValue].
  static UpdatePackageType? fromWireValue(String? value) {
    if (value == null || value.isEmpty) return null;
    final normalized = value.trim().toLowerCase();
    for (final type in UpdatePackageType.values) {
      if (type.wireValue.toLowerCase() == normalized) {
        return type;
      }
    }
    return null;
  }

  /// Automatically infers the [UpdatePackageType] from a local [filePath] suffix.
  ///
  /// Throws an [ArgumentError] if the file extension is not one of
  /// `.dmg`, `.pkg`, `.exe`, `.AppImage`, `.deb`, or `.rpm`.
  static UpdatePackageType inferFromPath(String filePath) {
    final lower = filePath.trim().toLowerCase();
    if (lower.endsWith('.dmg')) return UpdatePackageType.dmg;
    if (lower.endsWith('.pkg')) return UpdatePackageType.pkg;
    if (lower.endsWith('.exe')) return UpdatePackageType.exe;
    if (lower.endsWith('.appimage')) return UpdatePackageType.appImage;
    if (lower.endsWith('.deb')) return UpdatePackageType.deb;
    if (lower.endsWith('.rpm')) return UpdatePackageType.rpm;
    throw ArgumentError.value(
      filePath,
      'filePath',
      'Cannot infer UpdatePackageType from file extension. '
          'Expected .dmg, .pkg, .exe, .AppImage, .deb, or .rpm.',
    );
  }
}

/// Reason why in-place auto-update is blocked in the current runtime environment.
enum UpdateBlockReason {
  /// The current environment supports automatic update and relaunch.
  none('none'),

  /// macOS: The application is running directly inside a read-only mounted disk
  /// image (`/Volumes/...`). The user must drag the app into `/Applications` first.
  runningOnReadOnlyVolume('runningOnReadOnlyVolume'),

  /// macOS: Gatekeeper App Translocation is active (`/AppTranslocation/...`),
  /// running the app from a randomized read-only path. The user must move the
  /// app to `/Applications` first.
  runningInAppTranslocation('runningInAppTranslocation'),

  /// The application is running inside a restricted store or container sandbox
  /// (Mac App Store Sandbox, Windows MSIX / Microsoft Store, Linux Snap or Flatpak)
  /// where self-replacement is prohibited by the OS.
  runningInSandboxOrStore('runningInSandboxOrStore'),

  /// Linux: Running as an AppImage update target, but the `$APPIMAGE` environment
  /// variable is not present or points to a non-writable mount.
  missingAppImageEnv('missingAppImageEnv'),

  /// The current operating system does not support desktop installer auto-update.
  unsupportedPlatform('unsupportedPlatform'),

  /// Unknown or unclassified environment restriction.
  unknown('unknown');

  const UpdateBlockReason(this.wireValue);

  /// The serialized string identifier sent over the platform channel.
  final String wireValue;

  /// Parses an [UpdateBlockReason] from its serialized [wireValue].
  static UpdateBlockReason fromWireValue(String? value) {
    if (value == null || value.isEmpty) return UpdateBlockReason.none;
    for (final reason in UpdateBlockReason.values) {
      if (reason.wireValue == value) {
        return reason;
      }
    }
    return UpdateBlockReason.unknown;
  }
}

/// Diagnostic and permission metadata returned by [XueHuaNaviteAutoUpdate.checkEnvironment].
@immutable
class UpdateEnvironmentInfo {
  /// Creates an [UpdateEnvironmentInfo] instance.
  const UpdateEnvironmentInfo({
    required this.platform,
    required this.executablePath,
    required this.bundlePath,
    required this.processId,
    required this.canAutoUpdate,
    required this.requiresElevation,
    this.blockReason = UpdateBlockReason.none,
    this.statusMessage = '',
  });

  /// Deserializes an [UpdateEnvironmentInfo] from a platform channel map.
  factory UpdateEnvironmentInfo.fromMap(Map<Object?, Object?> map) {
    return UpdateEnvironmentInfo(
      platform: (map['platform'] as String?) ?? defaultTargetPlatform.name,
      executablePath: (map['executablePath'] as String?) ?? '',
      bundlePath: (map['bundlePath'] as String?) ?? '',
      processId: (map['processId'] as num?)?.toInt() ?? 0,
      canAutoUpdate: (map['canAutoUpdate'] as bool?) ?? false,
      requiresElevation: (map['requiresElevation'] as bool?) ?? false,
      blockReason: UpdateBlockReason.fromWireValue(
        map['blockReason'] as String?,
      ),
      statusMessage: (map['statusMessage'] as String?) ?? '',
    );
  }

  /// Current host platform identifier (`macos`, `windows`, or `linux`).
  final String platform;

  /// Absolute path to the running main executable binary.
  final String executablePath;

  /// Absolute path to the outer application bundle or installation directory.
  ///
  /// - On **macOS**: The `.app` bundle path (e.g. `/Applications/MyApp.app`).
  /// - On **Windows**: The installation directory containing the `.exe`.
  /// - On **Linux**: The `$APPIMAGE` file path if running from an AppImage,
  ///   or the executable's parent directory for `.deb` / `.rpm` installs.
  final String bundlePath;

  /// Operating system process ID (`PID`) of the currently running Flutter app.
  final int processId;

  /// Whether the current installation supports automatic update and relaunch.
  final bool canAutoUpdate;

  /// Whether replacing the current installation requires administrator / root
  /// privilege elevation (macOS Touch ID / password, Windows UAC, or Linux Polkit `pkexec`).
  final bool requiresElevation;

  /// Specific reason why [canAutoUpdate] is `false`, or [UpdateBlockReason.none]
  /// when updates are supported.
  final UpdateBlockReason blockReason;

  /// Human-readable diagnostic description of the current update environment.
  final String statusMessage;

  /// Serializes this instance to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'platform': platform,
      'executablePath': executablePath,
      'bundlePath': bundlePath,
      'processId': processId,
      'canAutoUpdate': canAutoUpdate,
      'requiresElevation': requiresElevation,
      'blockReason': blockReason.wireValue,
      'statusMessage': statusMessage,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UpdateEnvironmentInfo &&
        other.platform == platform &&
        other.executablePath == executablePath &&
        other.bundlePath == bundlePath &&
        other.processId == processId &&
        other.canAutoUpdate == canAutoUpdate &&
        other.requiresElevation == requiresElevation &&
        other.blockReason == blockReason &&
        other.statusMessage == statusMessage;
  }

  @override
  int get hashCode => Object.hash(
    platform,
    executablePath,
    bundlePath,
    processId,
    canAutoUpdate,
    requiresElevation,
    blockReason,
    statusMessage,
  );

  @override
  String toString() {
    return 'UpdateEnvironmentInfo('
        'platform: $platform, '
        'executablePath: $executablePath, '
        'bundlePath: $bundlePath, '
        'processId: $processId, '
        'canAutoUpdate: $canAutoUpdate, '
        'requiresElevation: $requiresElevation, '
        'blockReason: ${blockReason.name}, '
        'statusMessage: $statusMessage)';
  }
}

/// Localized text strings displayed inside the out-of-process native update progress UI.
@immutable
class UpdateProgressStrings {
  /// Creates an [UpdateProgressStrings] configuration with English defaults.
  const UpdateProgressStrings({
    this.windowTitle = 'Application Update',
    this.waitingForAppExitText = 'Waiting for application to close...',
    this.mountingPackageText = 'Verifying and mounting update package...',
    this.installingUpdateText = 'Installing new version...',
    this.relaunchingText = 'Relaunching application...',
    this.rollingBackText =
        'Update cancelled or failed, restoring previous version...',
  });

  /// Convenience factory for Simplified Chinese (`zh-CN`) native progress UI strings.
  const factory UpdateProgressStrings.zhCN({
    String windowTitle,
    String waitingForAppExitText,
    String mountingPackageText,
    String installingUpdateText,
    String relaunchingText,
    String rollingBackText,
  }) = _ZhCnUpdateProgressStrings;

  /// Title of the native out-of-process progress window.
  final String windowTitle;

  /// Stage 1 status text shown while waiting for the main Flutter process to exit (15%).
  final String waitingForAppExitText;

  /// Stage 2 status text shown while mounting the disk image and verifying signatures (40%).
  final String mountingPackageText;

  /// Stage 3 status text shown while copying files or requesting administrator privileges (75%).
  final String installingUpdateText;

  /// Stage 4 status text shown while cleaning up and relaunching the updated application (100%).
  final String relaunchingText;

  /// Fallback status text shown if installation fails or authorization is cancelled and `.bak` is restored.
  final String rollingBackText;

  /// Serializes this configuration to a map for platform channel transport.
  Map<String, String> toMap() {
    return <String, String>{
      'windowTitle': windowTitle,
      'waitingForAppExitText': waitingForAppExitText,
      'mountingPackageText': mountingPackageText,
      'installingUpdateText': installingUpdateText,
      'relaunchingText': relaunchingText,
      'rollingBackText': rollingBackText,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UpdateProgressStrings &&
        other.windowTitle == windowTitle &&
        other.waitingForAppExitText == waitingForAppExitText &&
        other.mountingPackageText == mountingPackageText &&
        other.installingUpdateText == installingUpdateText &&
        other.relaunchingText == relaunchingText &&
        other.rollingBackText == rollingBackText;
  }

  @override
  int get hashCode => Object.hash(
    windowTitle,
    waitingForAppExitText,
    mountingPackageText,
    installingUpdateText,
    relaunchingText,
    rollingBackText,
  );
}

class _ZhCnUpdateProgressStrings extends UpdateProgressStrings {
  const _ZhCnUpdateProgressStrings({
    super.windowTitle = '正在更新应用',
    super.waitingForAppExitText = '正在等待主程序安全关闭...',
    super.mountingPackageText = '正在静默挂载并校验更新包签名...',
    super.installingUpdateText = '正在安装新版本应用...',
    super.relaunchingText = '更新完成，正在重新启动应用...',
    super.rollingBackText = '更新已取消或遇到异常，正在回滚并恢复旧版本...',
  });
}
