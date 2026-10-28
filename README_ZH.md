# xue_hua_navite_auto_update

[English](README.md) | **简体中文**

[![Pub Version](https://img.shields.io/badge/pub-v1.0.1-blue)](https://github.com/Matkurban/xue_hua_navite_auto_update)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-blueviolet)](https://github.com/Matkurban/xue_hua_navite_auto_update)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](LICENSE)

`xue_hua_navite_auto_update` 是一款面向 Flutter 桌面端（**macOS** / **Windows** / **Linux**）的生产级**一键自动更新与自重启插件**。

它的核心交互体验直接对标 **VS Code / Sparkle / 飞书桌面版**：
1. **100% 复用各平台标准分发安装包**：无需维护专用的二进制差分格式，直接传入已下载的各平台标准安装包（macOS 为 `.dmg` / `.pkg`，Windows 为 Inno Setup `.exe`，Linux 为 `.AppImage` / `.deb` / `.rpm`）。
2. **无缝衔接独立原生更新进度弹窗（Out-of-Process Progress UI）**：当用户点击“立即重启更新”后，Flutter 主程序立即关闭退出；与此同时，插件拉起的**独立原生更新进程（Detached Updater）**会在屏幕中央弹出一个轻量、现代的系统原生更新进度弹窗（实时展示进度条与当前阶段文案，如“正在等待主程序安全关闭...”、“正在静默挂载并校验更新包签名...”、“正在安装新版本应用...”、“更新完成，正在重新启动应用...”），彻底杜绝主程序退出后的桌面空白期导致用户误以为软件闪退。
3. **按需提权与异常自动回滚**：安装过程中若目标目录需要管理员权限，自动唤起系统原生授权框（macOS Touch ID / 密码框、Windows UAC、Linux Polkit `pkexec`）；安装完成后进度弹窗自动关闭并拉起新版本主程序；若用户在密码框点击“取消”或安装校验失败，则**自动还原 `.bak` 备份并重新拉起原应用**，绝不让用户的应用消失。

---

## 目录

1. [交互流程图解与平台支持矩阵](#1-交互流程图解与平台支持矩阵)
2. [快速安装与环境要求](#2-快速安装与环境要求)
3. [Dart API 详解](#3-dart-api-详解)
4. [完整 Flutter 接入代码示例](#4-完整-flutter-接入代码示例)
5. [各平台打包规范与配置指南（可直接复制模板）](#5-各平台打包规范与配置指南可直接复制模板)
   - [5.1 Windows Inno Setup (`.iss`) 配置模板](#51-windows-inno-setup-iss-配置模板)
   - [5.2 macOS (`.dmg` / `.pkg`) 打包与签名公证指南](#52-macos-dmg--pkg-打包与签名公证指南)
   - [5.3 Linux (`.AppImage` / `.deb` / `.rpm`) 打包指南](#53-linux-appimage--deb--rpm-打包指南)
6. [使用限制与边界情况说明（Limitations）](#6-使用限制与边界情况说明limitations)
7. [AI Coding Agent Skills 支持](#7-ai-coding-agent-skills-支持)
8. [作者与开源协议](#8-作者与开源协议)

---

## 1. 交互流程图解与平台支持矩阵

### 1.1 核心更新与自重启时序图

```text
┌───────────────────────────┐          ┌──────────────────────────────────────────┐
│    Flutter 主应用进程     │          │     独立原生更新守护进程 (Out-of-Process) │
└─────────────┬─────────────┘          └─────────────────────┬────────────────────┘
              │                                              │
  1. checkEnvironment()                                      │
     检测只读卷 / AppTranslocation / 写权限                   │
              │                                              │
  2. verifyPackageChecksum()                                 │
     流式计算并校验安装包 SHA-256                             │
              │                                              │
  3. installAndRelaunch() ───────── 拉起脱离进程组的守护进程 ──▶│
              │                                              │ [阶段 1 - 15%]
  4. 主程序立即安全退出 (exit 0)                             │ 弹出屏幕中央原生进度窗
              ✕                                              │ 循环检测主进程 PID 完全退出
                                                             │
                                                             │ [阶段 2 - 40%]
                                                             │ • macOS: hdiutil 静默挂载 DMG + codesign 签名校验
                                                             │ • Windows: 准备 Inno Setup /SILENT 参数
                                                             │ • Linux: 校验 AppImage / DEB / RPM 包
                                                             │
                                                             │ [阶段 3 - 75%]
                                                             │ • 免密目录: 备份 .bak -> 原地覆盖写入
                                                             │ • 需提权目录: 唤起 Touch ID / UAC / Polkit 授权框
                                                             │   ├─ 若授权取消或失败: 自动还原 .bak 备份
                                                             │   └─ 若安装成功: 清除隔离属性 (xattr -cr) 并清理 .bak
                                                             │
                                       ┌─────────────────────┤ [阶段 4 - 100%]
                                       ▼                     │ 清理临时挂载卷 & 关闭进度弹窗
┌─────────────────────────────────────────┐                  │ 以普通桌面用户身份重新拉起主程序
│   新版本（或回滚后的原版本）主程序启动   │◀─────────────────┘ (透传 relaunchArgs 参数)
└─────────────────────────────────────────┘
```

### 1.2 平台支持矩阵表

| 平台                                | 支持安装包格式                  | 独立原生更新进度弹窗实现                                                                                                                                             | 提权机制（按需触发）                                                                                                                                                                                     | 异常/取消授权回滚与重启保障                                                                                                                                                                        |
|:------------------------------------|:--------------------------------|:---------------------------------------------------------------------------------------------------------------------------------------------------------------------|:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **macOS** (`12.0+`, Swift + SPM)    | `.dmg`<br>`.pkg`                | 独立脱离进程 `/usr/bin/swift` AppKit 原生毛玻璃悬浮窗 (`NSPanel` + `NSVisualEffectView` + `NSProgressIndicator`，自适应暗黑模式)                                     | `/Applications` 当前用户可写时**免密直装**；不可写或 `.pkg` 时通过 `osascript` (`with administrator privileges`) 唤起系统 **Touch ID / 密码框**                                                          | 替换前备份 `.app.bak`；`codesign` 校验不通过、拷贝失败或用户取消密码框时自动还原 `.app.bak` 并调用 `open -n` 重启原应用                                                                            |
| **Windows** (`Win10/11`, C++ Win32) | Inno Setup `.exe`               | `showProgressDialog: true` 时传入 `/SILENT /SUPPRESSMSGBOXES /NORESTART /SP- /CLOSEAPPLICATIONS`，直接展示 **Inno Setup 原生安装进度条小窗口**（自动跳过所有向导页） | - `PrivilegesRequired=lowest`（安装在 `AppData\Local\Programs`）：**全程免 UAC 弹窗**<br>- `PrivilegesRequired=admin`（安装在 `Program Files`）：**弹一次系统 UAC 确认框**                               | `%TEMP%` 无黑框守护进程（绝对路径 `powershell.exe`，`CREATE_NO_WINDOW \| CREATE_BREAKAWAY_FROM_JOB`，WMI 回退）阻塞等待安装器结束；若 `.iss` 未配置 `[Run]` 或用户取消 UAC，守护进程主动调用 `Start-Process`/`ShellExecuteW` 100% 重新拉起主程序 |
| **Linux** (`GTK3`, C++ & Polkit)    | `.AppImage`<br>`.deb`<br>`.rpm` | 优先调用系统 `zenity --progress --auto-close --no-cancel` 在屏幕中央展示实时更新文案与进度条                                                                         | - `.AppImage`：**免密**原子替换 `$APPIMAGE`<br>- `.deb`：`pkexec apt-get install -y --allow-downgrades`<br>- `.rpm`：`pkexec dnf install -y` / `zypper` / `rpm -Uvh`（唤起系统 **Polkit 图形化授权框**） | `.AppImage` 备份 `.bak` 并在失败时回滚；`.deb`/`.rpm` 安装或取消后自动**切回当前普通桌面用户身份**（严禁以 `root` 启动 GUI）通过 `nohup` 重新拉起主程序                                            |

---

## 2. 快速安装与环境要求

### 2.1 版本约束

- **Dart SDK**: `>=3.13.0 <4.0.0`
- **Flutter SDK**: `>=3.47.0`
- **支持平台**: macOS (`>= 12.0`)、Windows (`Windows 10 / 11`)、Linux (`Debian / Ubuntu / Deepin / Mint / Fedora / RHEL / openSUSE`)

### 2.2 在 `pubspec.yaml` 中添加依赖

```yaml
dependencies:
  xue_hua_navite_auto_update: ^1.0.0
```

或者通过 Git 仓库依赖：

```yaml
dependencies:
  xue_hua_navite_auto_update:
    git:
      url: https://github.com/Matkurban/xue_hua_navite_auto_update.git
      ref: main
```

---

## 3. Dart API 详解

包导入路径：
```dart
import 'package:xue_hua_navite_auto_update/xue_hua_navite_auto_update.dart';
```

### 3.1 `checkEnvironment()` — 运行环境预检

```dart
Future<UpdateEnvironmentInfo> checkEnvironment()
```

返回 `UpdateEnvironmentInfo` 对象，包含以下核心字段：
- `platform` (`String`): 当前操作系统标识（`macos`、`windows`、`linux`）。
- `executablePath` (`String`): 当前运行的主程序二进制绝对路径。
- `bundlePath` (`String`): 外层应用 Bundle 或安装目录路径（macOS 为 `/Applications/MyApp.app`，Windows 为 `.exe` 所在目录，Linux 下 AppImage 为 `$APPIMAGE` 路径）。
- `processId` (`int`): 当前主进程 PID。
- `canAutoUpdate` (`bool`): 当前环境是否允许原地自动更新。
- `requiresElevation` (`bool`): 更新时是否需要弹出系统管理员授权框（Touch ID / UAC / Polkit）。
- `blockReason` (`UpdateBlockReason`): 当 `canAutoUpdate == false` 时的具体原因枚举：
  - `UpdateBlockReason.none`: 支持自动更新。
  - `UpdateBlockReason.runningOnReadOnlyVolume`: macOS 应用直接运行在只读挂载卷（`/Volumes/...`）内。
  - `UpdateBlockReason.runningInAppTranslocation`: macOS 触发了 Gatekeeper 随机沙箱路径（`/AppTranslocation/...`）。
  - `UpdateBlockReason.runningInSandboxOrStore`: 运行在应用商店或容器沙箱内（Mac App Store Sandbox、Windows MSIX、Linux Snap / Flatpak）。
  - `UpdateBlockReason.missingAppImageEnv`: Linux 下尝试以 AppImage 方式更新但未检测到 `$APPIMAGE` 环境变量。
- `statusMessage` (`String`): 人类可读的诊断说明信息。

### 3.2 `verifyPackageChecksum()` — 流式 SHA-256 完整性校验

```dart
Future<bool> verifyPackageChecksum({
  required String filePath,
  required String expectedSha256,
})
```

- 采用原生流式分块（64 KB Chunks）计算文件的 SHA-256 哈希值（macOS 使用 `CryptoKit.SHA256`、Windows 使用 Win32 `BCrypt` CNG、Linux 使用 GLib `GChecksum`、并提供纯 Dart 流式兜底），即使校验数百 MB 的 `.dmg` / `.exe` 安装包也不会占用主线程内存。

### 3.3 `installAndRelaunch()` — 启动独立原生进度窗、安装更新并自重启

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

- `packagePath`: 已下载到本地的安装包绝对路径。
- `packageType`: 可选，指定安装包类型（`dmg`、`pkg`、`exe`、`appImage`、`deb`、`rpm`）。若不传则自动根据文件后缀推断。
- `showProgressDialog`: 关闭主软件后是否展示独立原生更新进度弹窗（默认 `true`）。
- `strings`: 自定义原生进度弹窗的多语言文案（支持 `const UpdateProgressStrings()` 英文默认与 `const UpdateProgressStrings.zhCN()` 简体中文预设）。
- `relaunchArgs`: 重启新版本主程序时透传的命令行参数列表（例如 `['--updated-from=1.0.0']`）。

---

## 4. 完整 Flutter 接入代码示例

```dart
import 'package:flutter/material.dart';
import 'package:xue_hua_navite_auto_update/xue_hua_navite_auto_update.dart';

class DesktopUpdateManager {
  static final XueHuaNaviteAutoUpdate _updater =
      XueHuaNaviteAutoUpdate.instance;

  /// 执行完整的桌面端更新预检、SHA-256 校验与一键自重启更新
  static Future<void> checkAndInstallUpdate({
    required BuildContext context,
    required String downloadedInstallerPath,
    required String expectedSha256,
    bool isZhCN = true,
  }) async {
    // 1. 环境预检：检查是否处于只读 DMG 卷、AppTranslocation 或商店沙箱
    final env = await _updater.checkEnvironment();
    if (!env.canAutoUpdate) {
      if (!context.mounted) return;
      if (env.blockReason == UpdateBlockReason.runningOnReadOnlyVolume ||
          env.blockReason == UpdateBlockReason.runningInAppTranslocation) {
        await _showMoveToApplicationsDialog(context, env);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('当前分发渠道不支持应用内自更新：${env.statusMessage}')),
        );
      }
      return;
    }

    // 2. 流式校验安装包 SHA-256 签名，防止下载损坏或被篡改
    final checksumOk = await _updater.verifyPackageChecksum(
      filePath: downloadedInstallerPath,
      expectedSha256: expectedSha256,
    );
    if (!checksumOk) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('安装包 SHA-256 校验失败，请重新下载更新包！')),
      );
      return;
    }

    // 3. 配置独立原生进度弹窗文案（支持中文 / 英文）
    final progressStrings = isZhCN
        ? const UpdateProgressStrings.zhCN(
            windowTitle: '正在更新雪花客户端',
            waitingForAppExitText: '正在等待主程序安全关闭...',
            mountingPackageText: '正在静默挂载并校验更新包签名...',
            installingUpdateText: '正在安装新版本，请稍候...',
            relaunchingText: '更新完成，正在重新启动应用...',
            rollingBackText: '更新已取消或遇到异常，正在恢复旧版本...',
          )
        : const UpdateProgressStrings(
            windowTitle: 'Updating Application',
            waitingForAppExitText: 'Waiting for application to close...',
            mountingPackageText: 'Mounting and verifying update package...',
            installingUpdateText: 'Installing new version...',
            relaunchingText: 'Update complete, relaunching application...',
            rollingBackText: 'Update cancelled or failed, restoring backup...',
          );

    // 4. 启动脱离主进程的原生进度窗并立即关闭当前应用完成替换与自重启
    await _updater.installAndRelaunch(
      packagePath: downloadedInstallerPath,
      showProgressDialog: true,
      strings: progressStrings,
      relaunchArgs: const <String>['--updated-success'],
    );
  }

  /// 当 macOS 用户直接在只读 .dmg 挂载卷内双击运行应用时的引导弹窗
  static Future<void> _showMoveToApplicationsDialog(
    BuildContext context,
    UpdateEnvironmentInfo env,
  ) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('请先将应用移至“应用程序”文件夹'),
        content: Text(
          '检测到您当前正在只读磁盘映像或临时沙箱路径中直接运行本软件：\n'
          '${env.bundlePath}\n\n'
          'macOS 不允许在只读挂载卷内直接原地更新。请先在 Finder 中将应用图标拖入“应用程序 (/Applications)”文件夹，再从“应用程序”中打开即可一键更新。',
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }
}
```

---

## 5. 各平台打包规范与配置指南（可直接复制模板）

### 5.1 Windows Inno Setup (`.iss`) 配置模板

在 Windows 平台下，`xue_hua_navite_auto_update` 专门针对 **Inno Setup** 打包的 `.exe` 安装器进行了深度适配：
- 当 `showProgressDialog: true`（默认）时，插件向安装器传入 **`/SILENT /SUPPRESSMSGBOXES /NORESTART /SP- /CLOSEAPPLICATIONS`**。Inno Setup 会弹出一个轻量的**原生安装进度条窗口**，但自动跳过所有安装向导页面、许可协议和完成确认框。
- 当 `showProgressDialog: false` 时，插件传入 `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /CLOSEAPPLICATIONS`，全程无界面静默安装。

#### 模式对比：`PrivilegesRequired=lowest` vs `PrivilegesRequired=admin`

| 配置项                  | 方案 A：`PrivilegesRequired=lowest`（强烈推荐，对标 VS Code User Installer / 飞书）    | 方案 B：`PrivilegesRequired=admin`（传统系统级安装）             |
|:------------------------|:---------------------------------------------------------------------------------------|:-----------------------------------------------------------------|
| **默认安装路径**        | `{autopf}\MyApp` 自动解析为当前用户目录 `C:\Users\<User>\AppData\Local\Programs\MyApp` | `{autopf}\MyApp` 解析为系统目录 `C:\Program Files\MyApp`         |
| **更新时是否弹 UAC 框** | **0 次弹窗（全程免 UAC）**，点击更新后直接显示原生进度条并自动重启                     | **弹 1 次系统 UAC 管理员确认框**，确认后显示原生进度条并自动重启 |
| **适用场景**            | 追求极致丝滑自动更新体验的现代桌面客户端                                               | 企业强制要求安装在 `C:\Program Files` 全系统共享目录的软件       |

#### 可直接复制的 Inno Setup (`.iss`) 生产模板

```iss
; ============================================================================
; XueHua Desktop Inno Setup Production Script (.iss)
; 完美适配 xue_hua_navite_auto_update 插件 (/SILENT 原生进度条 + 100% 守护重启)
; ============================================================================

#define MyAppName "XueHuaDesktop"
#define MyAppVersion "2.0.0"
#define MyAppPublisher "Matkurban"
#define MyAppExeName "xue_hua_desktop.exe"
; 【关键注意 1】：AppId 在所有历史版本与新版本之间必须保持绝对一致！
; 只有 AppId 一致，Inno Setup 才能自动识别原安装目录并执行原位覆盖升级。
#define MyAppId "{{8F9A2B3C-4D5E-6F70-8A9B-0C1D2E3F4A5B}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
; {autopf} 在 lowest 模式下指向 AppData\Local\Programs，在 admin 模式下指向 Program Files
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=XueHuaDesktop_Setup_{#MyAppVersion}
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern

; 【关键注意 2】：选择权限模式
; - 设为 lowest：安装在用户目录，更新时【免 UAC 弹窗】，体验最丝滑（推荐）
; - 设为 admin ：安装在 Program Files，更新时弹出一次系统 UAC 授权框
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

; 【关键注意 3】：自动关闭残留进程锁
; 尽管插件会先等待主程序退出，开启 CloseApplications=force 可防止后台子进程锁死 DLL
CloseApplications=force
RestartApplications=no

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Run]
; 【关键注意 4】：
; 即使此处不写 postinstall，或者因 /SILENT 参数未触发 [Run]，
; xue_hua_navite_auto_update 的后台守护进程也会在安装器退出后自动检测并 100% 拉起主程序！
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
```

---

### 5.2 macOS (`.dmg` / `.pkg`) 打包与签名公证指南

#### 1. `Release.entitlements` 硬性要求（关闭 App Sandbox）

macOS 的 App Sandbox（Mac App Store 沙箱）在内核层禁止应用修改 `/Applications` 下的自身 Bundle 或拉起脱离沙箱的更新脚本。因此，采用网站/独立安装包直接分发（Direct Distribution）时，**必须在 `macos/Runner/Release.entitlements` 中将 `com.apple.security.app-sandbox` 设为 `false`**，并采用 **Hardened Runtime + Developer ID Application 签名 + Apple Notarization（公证）**：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- 直接分发自更新应用必须关闭 App Sandbox -->
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <!-- Flutter JIT / Metal 渲染所需权限 -->
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

#### 2. 包含 `ShareExtension.appex` 等插件扩展时的原子同步更新优势

许多复杂的 macOS 桌面应用会在 `MyApp.app/Contents/PlugIns/` 目录下内嵌系统扩展（例如 `ShareExtension.appex`、Finder Sync Extension 或 QuickLook 插件）。
- `xue_hua_navite_auto_update` 在处理 `.dmg` 更新时，采用**整包原子替换策略**：先将旧版 `/Applications/MyApp.app` 整体移动备份为 `MyApp.app.bak`，随后调用系统底层 `/usr/bin/ditto "<mounted_dmg>/MyApp.app" "/Applications/MyApp.app"` 完整拷贝整个 `.app` Bundle 树，并执行 `xattr -cr` 清除隔离属性。
- 这种整包替换机制保证了主程序可执行文件、`Frameworks/` 动态库以及 `Contents/PlugIns/ShareExtension.appex` 扩展插件**100% 原子同步升级**，绝不会出现主程序与内置 App Extension 版本号不一致或签名断裂的问题。

#### 3. `.dmg` 与 `.pkg` 标准打包命令示例

**构建并签名 `.app`：**
```bash
# 1. 构建 Flutter macOS Release 包
flutter build macos --release

# 2. 使用 Developer ID Application 证书对整个 .app 进行深度硬化签名 (Hardened Runtime)
codesign --force --deep --options runtime --timestamp \
  --entitlements macos/Runner/Release.entitlements \
  --sign "Developer ID Application: Your Company Name (TEAM_ID)" \
  build/macos/Build/Products/Release/MyApp.app

# 3. 验证签名完整性（插件更新时同样会调用此命令校验）
codesign --verify --deep --strict --verbose=2 \
  build/macos/Build/Products/Release/MyApp.app
```

**方式一：打包为 `.dmg` 磁盘映像（推荐）：**
```bash
# 创建临时打包目录并放入 .app 与 /Applications 快捷方式
mkdir -p build/dmg_staging
cp -R build/macos/Build/Products/Release/MyApp.app build/dmg_staging/
ln -s /Applications build/dmg_staging/Applications

# 使用 hdiutil 生成压缩的只读 UDZO 格式 .dmg
hdiutil create -volname "MyApp Installer" \
  -srcfolder build/dmg_staging \
  -ov -format UDZO \
  dist/MyApp_2.0.0.dmg

# 对 .dmg 进行签名与 Apple 公证 (Notarization)
codesign --force --sign "Developer ID Application: Your Company Name (TEAM_ID)" dist/MyApp_2.0.0.dmg
xcrun notarytool submit dist/MyApp_2.0.0.dmg --keychain-profile "AC_PASSWORD" --wait
xcrun stapler staple dist/MyApp_2.0.0.dmg
```

**方式二：打包为 `.pkg` 安装包：**
```bash
pkgbuild --component build/macos/Build/Products/Release/MyApp.app \
  --install-location /Applications \
  --sign "Developer ID Installer: Your Company Name (TEAM_ID)" \
  dist/MyApp_2.0.0.pkg
```

---

### 5.3 Linux (`.AppImage` / `.deb` / `.rpm`) 打包指南

1. **`.AppImage` 打包要求**：
   - 运行 `.AppImage` 时，AppImage Runtime 会自动注入 `$APPIMAGE` 环境变量指向当前 `.AppImage` 磁盘文件路径。
   - 插件在更新 `.AppImage` 时**无需任何 root 密码**，直接备份 `$APPIMAGE.bak`，将新 `.AppImage` 赋予可执行权限 (`chmod +x`) 并原子覆盖原路径，随后直接重新拉起 `$APPIMAGE`。
2. **`.deb` / `.rpm` 固定安装路径要求**：
   - 打包 `.deb`（Debian/Ubuntu/Deepin/Mint）或 `.rpm`（Fedora/RHEL/openSUSE）时，新版本安装包的**主程序二进制安装路径**（例如 `/opt/myapp/myapp` 或 `/usr/lib/myapp/myapp`）必须与旧版本保持一致。
   - 插件在执行 `pkexec apt-get install -y --allow-downgrades "<deb>"` 或 `pkexec dnf install -y "<rpm>"` 完成后，会切换回原普通桌面用户身份并重新执行原二进制路径。
3. **Polkit 桌面代理与 `zenity` 进度弹窗环境**：
   - 主流 Linux 桌面环境（GNOME、KDE Plasma、XFCE、Deepin DDE、Cinnamon）均内置图形化 Polkit Agent，调用 `pkexec` 时会自动弹出系统原生密码授权框。
   - 独立进度弹窗优先调用系统 `zenity`（GNOME/Ubuntu/Debian/Deepin 默认预装）。若目标精简系统未安装 `zenity`，更新流程会自动降级为后台静默更新并正常弹出 Polkit 授权框与重启应用。

---

## 6. 使用限制与边界情况说明（Limitations）

1. **不支持应用商店强沙箱渠道**：
   - **Mac App Store**（开启了 `com.apple.security.app-sandbox`）、**Microsoft Store (`MSIX` / `AppX`)**、**Linux Snap / Flatpak** 均由操作系统商店接管生命周期并锁定应用目录只读。在这些渠道下调用 `checkEnvironment()` 会返回 `canAutoUpdate: false` 且 `blockReason: UpdateBlockReason.runningInSandboxOrStore`，请引导用户前往对应应用商店升级。
2. **macOS 用户直接在只读 `.dmg` 内双击运行应用**：
   - 许多 macOS 用户下载 `.dmg` 后未将图标拖入 `/Applications`，而是直接在挂载的 `/Volumes/MyApp` 只读卷内双击启动，或触发了 Gatekeeper 的 `/AppTranslocation/` 随机路径。
   - 此时 `checkEnvironment()` 会精准返回 `UpdateBlockReason.runningOnReadOnlyVolume` 或 `UpdateBlockReason.runningInAppTranslocation`。请参考上方第 4 节代码示例，在 UI 层弹窗提示用户先将应用拖入 `/Applications` 文件夹。
3. **用户在系统密码授权框点击“取消”后的回滚保障**：
   - **macOS**：若 `/Applications` 需要管理员权限或安装 `.pkg` 时用户在系统密码/Touch ID 弹窗点击了“取消”，独立更新进程会立即检测到非零退出码，自动将 `.app.bak` 还原回原路径，并在进度条提示后**重新启动旧版本应用**。
   - **Windows**：若 `.iss` 配置了 `PrivilegesRequired=admin` 且用户在 UAC 弹窗点击了“否”，后台守护进程捕获到安装器退出且目标新进程未启动后，会立即调用 `Start-Process` 重新拉起原有的 `.exe` 主程序。
   - **Linux**：若用户在 Polkit 密码框点击取消，`pkexec` 返回非零状态码，后台更新脚本关闭进度条并直接以普通用户身份重新拉起未修改的原主程序。

---

## 7. AI Coding Agent Skills 支持

本插件遵循 [Dart Package Skills 规范](https://dart.dev/tools/pub/package-skills)，在包根目录内置了标准 AI Agent 技能文件：`skills/xue-hua-navite-auto-update/SKILL.md`。

在使用 Cursor、Gemini、Claude Code、GitHub Copilot 等 AI 编程助手的项目中添加本插件后，可通过以下命令一键安装本插件专属的 AI 编码指南：

```bash
dart run skills@ get
```

---

## 8. 作者与开源协议

- **作者 (Author)**: Matkurban
- **联系邮箱 (Email)**: [3496354336@qq.com](mailto:3496354336@qq.com)
- **代码仓库 (Repository)**: [https://github.com/Matkurban/xue_hua_navite_auto_update](https://github.com/Matkurban/xue_hua_navite_auto_update)
- **开源协议 (License)**: （详见 [LICENSE](LICENSE)）
