import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xue_hua_navite_auto_update/xue_hua_navite_auto_update.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AutoUpdateExampleApp(launchArgs: args));
}

class AutoUpdateExampleApp extends StatelessWidget {
  const AutoUpdateExampleApp({super.key, required this.launchArgs});

  final List<String> launchArgs;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'xue_hua_navite_auto_update Workbench',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: AutoUpdateWorkbenchPage(launchArgs: launchArgs),
    );
  }
}

class AutoUpdateWorkbenchPage extends StatefulWidget {
  const AutoUpdateWorkbenchPage({super.key, required this.launchArgs});

  final List<String> launchArgs;

  @override
  State<AutoUpdateWorkbenchPage> createState() =>
      _AutoUpdateWorkbenchPageState();
}

class _AutoUpdateWorkbenchPageState extends State<AutoUpdateWorkbenchPage> {
  final XueHuaNaviteAutoUpdate _updater = XueHuaNaviteAutoUpdate.instance;

  UpdateEnvironmentInfo? _envInfo;
  bool _loadingEnv = false;

  late final TextEditingController _packagePathController;
  late final TextEditingController _expectedSha256Controller;
  late final TextEditingController _relaunchArgsController;

  late final TextEditingController _windowTitleController;
  late final TextEditingController _waitingTextController;
  late final TextEditingController _mountingTextController;
  late final TextEditingController _installingTextController;
  late final TextEditingController _relaunchingTextController;
  late final TextEditingController _rollingBackTextController;

  UpdatePackageType? _explicitPackageType;
  bool _showProgressDialog = true;
  bool _exitCurrentApp = true;
  bool _useChinesePreset = true;

  String? _computedSha256;
  bool? _checksumMatched;
  bool _verifyingChecksum = false;
  final List<String> _logs = <String>[];

  @override
  void initState() {
    super.initState();
    _packagePathController = TextEditingController(
      text: _defaultSamplePackagePath(),
    );
    _expectedSha256Controller = TextEditingController();
    _relaunchArgsController = TextEditingController(
      text: '--updated-from=1.0.0 --channel=stable',
    );

    const zhPreset = UpdateProgressStrings.zhCN();
    _windowTitleController = TextEditingController(text: zhPreset.windowTitle);
    _waitingTextController = TextEditingController(
      text: zhPreset.waitingForAppExitText,
    );
    _mountingTextController = TextEditingController(
      text: zhPreset.mountingPackageText,
    );
    _installingTextController = TextEditingController(
      text: zhPreset.installingUpdateText,
    );
    _relaunchingTextController = TextEditingController(
      text: zhPreset.relaunchingText,
    );
    _rollingBackTextController = TextEditingController(
      text: zhPreset.rollingBackText,
    );

    if (widget.launchArgs.isNotEmpty) {
      _appendLog('Launched with relaunchArgs: ${widget.launchArgs.join(" ")}');
    }
    _refreshEnvironment();
  }

  @override
  void dispose() {
    _packagePathController.dispose();
    _expectedSha256Controller.dispose();
    _relaunchArgsController.dispose();
    _windowTitleController.dispose();
    _waitingTextController.dispose();
    _mountingTextController.dispose();
    _installingTextController.dispose();
    _relaunchingTextController.dispose();
    _rollingBackTextController.dispose();
    super.dispose();
  }

  String _defaultSamplePackagePath() {
    if (Platform.isMacOS) {
      return '/tmp/XueHuaApp_Update_2.0.0.dmg';
    } else if (Platform.isWindows) {
      return r'C:\Temp\XueHuaApp_Setup_2.0.0.exe';
    } else {
      return '/tmp/XueHuaApp_2.0.0_x86_64.AppImage';
    }
  }

  void _appendLog(String message) {
    final now = DateTime.now().toIso8601String().substring(11, 19);
    setState(() {
      _logs.insert(0, '[$now] $message');
    });
  }

  void _applyLocalePreset(bool zhCN) {
    final preset = zhCN
        ? const UpdateProgressStrings.zhCN()
        : const UpdateProgressStrings();
    setState(() {
      _useChinesePreset = zhCN;
      _windowTitleController.text = preset.windowTitle;
      _waitingTextController.text = preset.waitingForAppExitText;
      _mountingTextController.text = preset.mountingPackageText;
      _installingTextController.text = preset.installingUpdateText;
      _relaunchingTextController.text = preset.relaunchingText;
      _rollingBackTextController.text = preset.rollingBackText;
    });
    _appendLog(
      'Switched progress dialog strings preset to ${zhCN ? "Simplified Chinese (zh-CN)" : "English (en-US)"}.',
    );
  }

  Future<void> _refreshEnvironment() async {
    setState(() {
      _loadingEnv = true;
    });
    try {
      final info = await _updater.checkEnvironment();
      if (!mounted) return;
      setState(() {
        _envInfo = info;
      });
      _appendLog(
        'checkEnvironment() -> canAutoUpdate=${info.canAutoUpdate}, '
        'requiresElevation=${info.requiresElevation}, '
        'blockReason=${info.blockReason.name}',
      );
    } on PlatformException catch (e) {
      _appendLog('checkEnvironment() failed: [${e.code}] ${e.message}');
    } finally {
      if (mounted) {
        setState(() {
          _loadingEnv = false;
        });
      }
    }
  }

  Future<void> _generateMockInstallerFile() async {
    try {
      final tempDir = Directory.systemTemp;
      final ext = Platform.isMacOS
          ? '.dmg'
          : (Platform.isWindows ? '.exe' : '.AppImage');
      final file = File('${tempDir.path}/xue_hua_mock_installer_2.0.0$ext');
      final payload =
          'XueHuaMockInstaller v2.0.0 generated at ${DateTime.now().toIso8601String()}';
      await file.writeAsString(payload, flush: true);
      final sha = await StreamingSha256.computeFileSha256(file.path);

      if (!mounted) return;
      setState(() {
        _packagePathController.text = file.path;
        _expectedSha256Controller.text = sha;
        _computedSha256 = sha;
        _checksumMatched = null;
      });
      _appendLog(
        'Generated test package file at ${file.path} (SHA-256: $sha).',
      );
    } catch (e) {
      _appendLog('Failed to generate test package file: $e');
    }
  }

  Future<void> _verifyChecksum() async {
    final filePath = _packagePathController.text.trim();
    final expected = _expectedSha256Controller.text.trim();
    if (filePath.isEmpty) {
      _appendLog('Please enter a package file path first.');
      return;
    }

    setState(() {
      _verifyingChecksum = true;
    });

    try {
      final file = File(filePath);
      if (await file.exists()) {
        final actual = await StreamingSha256.computeFileSha256(filePath);
        _computedSha256 = actual;
        if (expected.isEmpty) {
          _expectedSha256Controller.text = actual;
        }
      }

      final matched = await _updater.verifyPackageChecksum(
        filePath: filePath,
        expectedSha256: _expectedSha256Controller.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _checksumMatched = matched;
      });
      _appendLog(
        'verifyPackageChecksum() -> ${matched ? "MATCHED (Valid)" : "MISMATCH (Invalid)"}',
      );
    } catch (e) {
      _appendLog('verifyPackageChecksum() error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _verifyingChecksum = false;
        });
      }
    }
  }

  Future<void> _triggerInstallAndRelaunch() async {
    final env = _envInfo;
    if (env != null && !env.canAutoUpdate) {
      await _showBlockedEnvironmentDialog(env);
      return;
    }

    final packagePath = _packagePathController.text.trim();
    if (packagePath.isEmpty) {
      _appendLog('packagePath cannot be empty.');
      return;
    }

    final expectedSha = _expectedSha256Controller.text.trim();
    if (expectedSha.isNotEmpty) {
      final valid = await _updater.verifyPackageChecksum(
        filePath: packagePath,
        expectedSha256: expectedSha,
      );
      if (!valid) {
        _appendLog(
          'Aborted installAndRelaunch: SHA-256 verification failed for $packagePath.',
        );
        return;
      }
    }

    final strings = UpdateProgressStrings(
      windowTitle: _windowTitleController.text.trim(),
      waitingForAppExitText: _waitingTextController.text.trim(),
      mountingPackageText: _mountingTextController.text.trim(),
      installingUpdateText: _installingTextController.text.trim(),
      relaunchingText: _relaunchingTextController.text.trim(),
      rollingBackText: _rollingBackTextController.text.trim(),
    );

    final relaunchArgs = _relaunchArgsController.text
        .split(' ')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    try {
      _appendLog(
        'Invoking installAndRelaunch(packagePath: $packagePath, '
        'packageType: ${_explicitPackageType?.name ?? "auto"}, '
        'showProgressDialog: $_showProgressDialog)...',
      );
      await _updater.installAndRelaunch(
        packagePath: packagePath,
        packageType: _explicitPackageType,
        showProgressDialog: _showProgressDialog,
        strings: strings,
        relaunchArgs: relaunchArgs,
        exitCurrentApp: _exitCurrentApp,
      );
      _appendLog(
        'Detached updater process launched. (exitCurrentApp=$_exitCurrentApp)',
      );
    } on PlatformException catch (e) {
      _appendLog(
        'installAndRelaunch() PlatformException: [${e.code}] ${e.message}',
      );
    } catch (e) {
      _appendLog('installAndRelaunch() error: $e');
    }
  }

  Future<void> _showBlockedEnvironmentDialog(UpdateEnvironmentInfo env) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('当前运行位置不支持直接原地更新'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('阻断原因枚举：${env.blockReason.name}'),
              const SizedBox(height: 8),
              Text('当前应用路径：${env.bundlePath}'),
              const SizedBox(height: 12),
              Text(env.statusMessage),
              if (env.blockReason ==
                      UpdateBlockReason.runningOnReadOnlyVolume ||
                  env.blockReason ==
                      UpdateBlockReason.runningInAppTranslocation) ...<Widget>[
                const SizedBox(height: 12),
                const Text(
                  '请先在 Finder 中将应用图标拖入“应用程序 (/Applications)”文件夹，然后从“应用程序”中重新打开本软件即可启用一键自动更新。',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('我知道了'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final env = _envInfo;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'xue_hua_navite_auto_update — Desktop Updater Workbench',
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh Environment Check',
            onPressed: _loadingEnv ? null : _refreshEnvironment,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            flex: 3,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                _buildEnvironmentCard(env),
                const SizedBox(height: 16),
                _buildPackageVerificationCard(),
                const SizedBox(height: 16),
                _buildProgressUiConfigCard(),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(flex: 2, child: _buildLogsPanel()),
        ],
      ),
    );
  }

  Widget _buildEnvironmentCard(UpdateEnvironmentInfo? env) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.verified_user_outlined),
                const SizedBox(width: 8),
                Text(
                  '1. Runtime Environment Pre-flight (checkEnvironment)',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _loadingEnv ? null : _refreshEnvironment,
                  icon: const Icon(Icons.radar, size: 18),
                  label: const Text('Re-check'),
                ),
              ],
            ),
            const Divider(height: 24),
            if (env == null)
              const Center(child: CircularProgressIndicator())
            else ...<Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  Chip(
                    avatar: Icon(
                      env.canAutoUpdate ? Icons.check_circle : Icons.error,
                      color: env.canAutoUpdate ? Colors.green : Colors.red,
                      size: 18,
                    ),
                    label: Text(
                      env.canAutoUpdate
                          ? 'canAutoUpdate: true'
                          : 'canAutoUpdate: false (${env.blockReason.name})',
                    ),
                  ),
                  Chip(
                    avatar: Icon(
                      env.requiresElevation
                          ? Icons.admin_panel_settings
                          : Icons.lock_open,
                      size: 18,
                    ),
                    label: Text(
                      env.requiresElevation
                          ? 'requiresElevation: true (Touch ID / UAC / Polkit)'
                          : 'requiresElevation: false (Passwordless)',
                    ),
                  ),
                  Chip(label: Text('Platform: ${env.platform}')),
                  Chip(label: Text('PID: ${env.processId}')),
                ],
              ),
              const SizedBox(height: 12),
              _buildKeyValueRow('Executable Path', env.executablePath),
              const SizedBox(height: 6),
              _buildKeyValueRow('Bundle / Install Path', env.bundlePath),
              const SizedBox(height: 6),
              _buildKeyValueRow('Diagnostic Status', env.statusMessage),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPackageVerificationCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.fingerprint),
                const SizedBox(width: 8),
                Text(
                  '2. Package Selection & Streaming SHA-256 Checksum',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _generateMockInstallerFile,
                  icon: const Icon(Icons.science_outlined, size: 18),
                  label: const Text('Create Mock Package File'),
                ),
              ],
            ),
            const Divider(height: 24),
            TextField(
              controller: _packagePathController,
              decoration: const InputDecoration(
                labelText: 'Installer Package Path (.dmg, .pkg, .exe, .AppImage, .deb, .rpm)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _expectedSha256Controller,
                    decoration: const InputDecoration(
                      labelText: 'Expected SHA-256 Hex Digest (64 chars)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: _verifyingChecksum ? null : _verifyChecksum,
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: const Text('Verify SHA-256'),
                ),
              ],
            ),
            if (_computedSha256 != null ||
                _checksumMatched != null) ...<Widget>[
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  if (_checksumMatched != null)
                    Icon(
                      _checksumMatched! ? Icons.check_circle : Icons.cancel,
                      color: _checksumMatched! ? Colors.green : Colors.red,
                      size: 18,
                    ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SelectableText(
                      'Actual File SHA-256: ${_computedSha256 ?? "-"} '
                      '(${_checksumMatched == null ? "Not compared" : (_checksumMatched! ? "MATCHED" : "MISMATCH")})',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressUiConfigCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.rocket_launch_outlined),
                const SizedBox(width: 8),
                Text(
                  '3. Out-of-Process Progress UI & Relaunch (installAndRelaunch)',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                SegmentedButton<bool>(
                  segments: const <ButtonSegment<bool>>[
                    ButtonSegment<bool>(value: true, label: Text('中文文案')),
                    ButtonSegment<bool>(value: false, label: Text('English')),
                  ],
                  selected: <bool>{_useChinesePreset},
                  onSelectionChanged: (selection) {
                    _applyLocalePreset(selection.first);
                  },
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<UpdatePackageType?>(
                    initialValue: _explicitPackageType,
                    decoration: const InputDecoration(
                      labelText: 'Package Format (packageType)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: <DropdownMenuItem<UpdatePackageType?>>[
                      const DropdownMenuItem<UpdatePackageType?>(
                        value: null,
                        child: Text('Auto-infer from extension (Default)'),
                      ),
                      ...UpdatePackageType.values.map(
                        (type) => DropdownMenuItem<UpdatePackageType?>(
                          value: type,
                          child: Text('${type.name} (.${type.wireValue})'),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _explicitPackageType = val;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _relaunchArgsController,
                    decoration: const InputDecoration(
                      labelText: 'Forwarded Relaunch Args (space-separated)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show Out-of-Process Progress Dialog'),
                    subtitle: const Text(
                      'macOS NSPanel / Windows Inno /SILENT / Linux Zenity',
                    ),
                    value: _showProgressDialog,
                    onChanged: (v) => setState(() => _showProgressDialog = v),
                  ),
                ),
                Expanded(
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Exit Current App Immediately'),
                    subtitle: const Text(
                      'Disable only when dry-running helper launch in debug mode',
                    ),
                    value: _exitCurrentApp,
                    onChanged: (v) => setState(() => _exitCurrentApp = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _windowTitleController,
                    decoration: const InputDecoration(
                      labelText: 'windowTitle',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _waitingTextController,
                    decoration: const InputDecoration(
                      labelText: 'waitingForAppExitText (Stage 1 - 15%)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _mountingTextController,
                    decoration: const InputDecoration(
                      labelText: 'mountingPackageText (Stage 2 - 40%)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _installingTextController,
                    decoration: const InputDecoration(
                      labelText: 'installingUpdateText (Stage 3 - 75%)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _relaunchingTextController,
                    decoration: const InputDecoration(
                      labelText: 'relaunchingText (Stage 4 - 100%)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _rollingBackTextController,
                    decoration: const InputDecoration(
                      labelText: 'rollingBackText (Rollback on Cancel/Error)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: _triggerInstallAndRelaunch,
                icon: const Icon(Icons.system_update_alt),
                label: const Text(
                  '立即重启并安装更新 (Install Update & Relaunch Now)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyValueRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 150,
          child: Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  Widget _buildLogsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: <Widget>[
              const Icon(Icons.terminal, size: 18),
              const SizedBox(width: 8),
              Text(
                'Event & Diagnostic Log',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(_logs.clear),
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _logs.isEmpty
              ? const Center(child: Text('No events recorded yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _logs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    return SelectableText(
                      _logs[index],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
