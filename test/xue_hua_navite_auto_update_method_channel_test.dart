import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_navite_auto_update/xue_hua_navite_auto_update.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final MethodChannelXueHuaNaviteAutoUpdate platform =
      MethodChannelXueHuaNaviteAutoUpdate();
  const MethodChannel channel = MethodChannel('xue_hua_navite_auto_update');

  MethodCall? recordedCall;

  setUp(() {
    recordedCall = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          recordedCall = methodCall;
          switch (methodCall.method) {
            case 'checkEnvironment':
              return <String, Object?>{
                'platform': 'macos',
                'executablePath':
                    '/Volumes/Installer/MyApp.app/Contents/MacOS/MyApp',
                'bundlePath': '/Volumes/Installer/MyApp.app',
                'processId': 9901,
                'canAutoUpdate': false,
                'requiresElevation': false,
                'blockReason': 'runningOnReadOnlyVolume',
                'statusMessage': 'Application is running directly from a mounted volume (/Volumes/).',
              };
            case 'verifyPackageChecksum':
              return true;
            case 'installAndRelaunch':
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'checkEnvironment parses read-only volume blockReason over channel',
    () async {
      final info = await platform.checkEnvironment();
      expect(info.platform, 'macos');
      expect(info.canAutoUpdate, isFalse);
      expect(info.blockReason, UpdateBlockReason.runningOnReadOnlyVolume);
      expect(info.processId, 9901);
    },
  );

  test(
    'verifyPackageChecksum invokes native channel with normalized hex',
    () async {
      const sha =
          'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD';
      final ok = await platform.verifyPackageChecksum(
        filePath: '/tmp/update.dmg',
        expectedSha256: sha,
      );
      expect(ok, isTrue);
      expect(recordedCall?.method, 'verifyPackageChecksum');
      final args = recordedCall?.arguments as Map<Object?, Object?>;
      expect(args['filePath'], '/tmp/update.dmg');
      expect(args['expectedSha256'], sha.toLowerCase());
    },
  );

  test('installAndRelaunch serializes arguments accurately', () async {
    await platform.installAndRelaunch(
      packagePath: '/tmp/update.pkg',
      packageType: UpdatePackageType.pkg,
      showProgressDialog: false,
      strings: const UpdateProgressStrings.zhCN(),
      relaunchArgs: const <String>['--restarted'],
      exitCurrentApp: false,
    );
    expect(recordedCall?.method, 'installAndRelaunch');
    final args = recordedCall?.arguments as Map<Object?, Object?>;
    expect(args['packagePath'], '/tmp/update.pkg');
    expect(args['packageType'], 'pkg');
    expect(args['showProgressDialog'], isFalse);
    expect(args['exitCurrentApp'], isFalse);
    expect(args['relaunchArgs'], <String>['--restarted']);
  });
}
