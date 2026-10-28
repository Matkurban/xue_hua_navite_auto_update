import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:xue_hua_navite_auto_update/xue_hua_navite_auto_update.dart';

class MockXueHuaNaviteAutoUpdatePlatform
    with MockPlatformInterfaceMixin
    implements XueHuaNaviteAutoUpdatePlatform {
  String? lastPackagePath;
  UpdatePackageType? lastPackageType;
  bool? lastShowProgressDialog;
  UpdateProgressStrings? lastStrings;
  List<String>? lastRelaunchArgs;

  @override
  Future<UpdateEnvironmentInfo> checkEnvironment() async {
    return const UpdateEnvironmentInfo(
      platform: 'macos',
      executablePath: '/Applications/XueHuaApp.app/Contents/MacOS/XueHuaApp',
      bundlePath: '/Applications/XueHuaApp.app',
      processId: 4242,
      canAutoUpdate: true,
      requiresElevation: false,
      blockReason: UpdateBlockReason.none,
      statusMessage: 'Ready for passwordless in-place auto-update.',
    );
  }

  @override
  Future<bool> verifyPackageChecksum({
    required String filePath,
    required String expectedSha256,
  }) async {
    return expectedSha256.toLowerCase() ==
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
  }

  @override
  Future<void> installAndRelaunch({
    required String packagePath,
    required UpdatePackageType packageType,
    bool showProgressDialog = true,
    UpdateProgressStrings strings = const UpdateProgressStrings(),
    List<String> relaunchArgs = const <String>[],
    bool exitCurrentApp = true,
  }) async {
    lastPackagePath = packagePath;
    lastPackageType = packageType;
    lastShowProgressDialog = showProgressDialog;
    lastStrings = strings;
    lastRelaunchArgs = relaunchArgs;
  }
}

void main() {
  final XueHuaNaviteAutoUpdatePlatform initialPlatform =
      XueHuaNaviteAutoUpdatePlatform.instance;

  test('$MethodChannelXueHuaNaviteAutoUpdate is the default instance', () {
    expect(
      initialPlatform,
      isInstanceOf<MethodChannelXueHuaNaviteAutoUpdate>(),
    );
  });

  test(
    'checkEnvironment returns strongly-typed UpdateEnvironmentInfo',
    () async {
      const plugin = XueHuaNaviteAutoUpdate();
      final fakePlatform = MockXueHuaNaviteAutoUpdatePlatform();
      XueHuaNaviteAutoUpdatePlatform.instance = fakePlatform;

      final env = await plugin.checkEnvironment();
      expect(env.platform, 'macos');
      expect(env.bundlePath, '/Applications/XueHuaApp.app');
      expect(env.processId, 4242);
      expect(env.canAutoUpdate, isTrue);
      expect(env.requiresElevation, isFalse);
      expect(env.blockReason, UpdateBlockReason.none);
    },
  );

  test('UpdatePackageType.inferFromPath detects all 6 desktop formats', () {
    expect(
      UpdatePackageType.inferFromPath('/tmp/app_2.0.0.dmg'),
      UpdatePackageType.dmg,
    );
    expect(
      UpdatePackageType.inferFromPath('/tmp/app_2.0.0.PKG'),
      UpdatePackageType.pkg,
    );
    expect(
      UpdatePackageType.inferFromPath(r'C:\Temp\setup_2.0.0.exe'),
      UpdatePackageType.exe,
    );
    expect(
      UpdatePackageType.inferFromPath('/tmp/app-x86_64.AppImage'),
      UpdatePackageType.appImage,
    );
    expect(
      UpdatePackageType.inferFromPath('/tmp/app_amd64.deb'),
      UpdatePackageType.deb,
    );
    expect(
      UpdatePackageType.inferFromPath('/tmp/app.x86_64.rpm'),
      UpdatePackageType.rpm,
    );
    expect(
      () => UpdatePackageType.inferFromPath('/tmp/archive.zip'),
      throwsArgumentError,
    );
  });

  test(
    'StreamingSha256 computes standard NIST vectors and file digests',
    () async {
      final abcDigest = await StreamingSha256.computeStringSha256('abc');
      expect(
        abcDigest,
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );

      final tempDir = await Directory.systemTemp.createTemp(
        'xue_hua_sha_test_',
      );
      try {
        final tempFile = File('${tempDir.path}/sample.dmg');
        await tempFile.writeAsString('abc', flush: true);
        final fileDigest = await StreamingSha256.computeFileSha256(
          tempFile.path,
        );
        expect(
          StreamingSha256.equalsDigest(
            fileDigest,
            'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD',
          ),
          isTrue,
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test(
    'installAndRelaunch infers packageType and forwards localized strings',
    () async {
      const plugin = XueHuaNaviteAutoUpdate();
      final fakePlatform = MockXueHuaNaviteAutoUpdatePlatform();
      XueHuaNaviteAutoUpdatePlatform.instance = fakePlatform;

      const customStrings = UpdateProgressStrings.zhCN(
        windowTitle: '正在升级雪花桌面端',
      );

      await plugin.installAndRelaunch(
        packagePath: '/tmp/XueHuaDesktop-2.0.0.dmg',
        showProgressDialog: true,
        strings: customStrings,
        relaunchArgs: const <String>['--updated-from=1.0.0'],
      );

      expect(fakePlatform.lastPackagePath, '/tmp/XueHuaDesktop-2.0.0.dmg');
      expect(fakePlatform.lastPackageType, UpdatePackageType.dmg);
      expect(fakePlatform.lastShowProgressDialog, isTrue);
      expect(fakePlatform.lastStrings?.windowTitle, '正在升级雪花桌面端');
      expect(fakePlatform.lastRelaunchArgs, <String>['--updated-from=1.0.0']);
    },
  );
}
