import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'src/models.dart';
import 'xue_hua_navite_auto_update_method_channel.dart';

/// The interface that platform-specific implementations of
/// `xue_hua_navite_auto_update` must extend.
abstract class XueHuaNaviteAutoUpdatePlatform extends PlatformInterface {
  /// Constructs a [XueHuaNaviteAutoUpdatePlatform].
  XueHuaNaviteAutoUpdatePlatform() : super(token: _token);

  static final Object _token = Object();

  static XueHuaNaviteAutoUpdatePlatform _instance =
      MethodChannelXueHuaNaviteAutoUpdate();

  /// The default instance of [XueHuaNaviteAutoUpdatePlatform] to use.
  ///
  /// Defaults to [MethodChannelXueHuaNaviteAutoUpdate].
  static XueHuaNaviteAutoUpdatePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [XueHuaNaviteAutoUpdatePlatform] when
  /// they register themselves.
  static set instance(XueHuaNaviteAutoUpdatePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Inspects the current desktop runtime environment to determine whether
  /// in-place auto-update is supported and whether administrator elevation is
  /// required.
  Future<UpdateEnvironmentInfo> checkEnvironment() {
    throw UnimplementedError('checkEnvironment() has not been implemented.');
  }

  /// Streams and verifies the SHA-256 checksum of [filePath] against
  /// [expectedSha256].
  Future<bool> verifyPackageChecksum({
    required String filePath,
    required String expectedSha256,
  }) {
    throw UnimplementedError(
      'verifyPackageChecksum() has not been implemented.',
    );
  }

  /// Spawns the detached native out-of-process updater for [packagePath] and
  /// terminates the current application so the update can be installed and
  /// relaunched.
  Future<void> installAndRelaunch({
    required String packagePath,
    required UpdatePackageType packageType,
    bool showProgressDialog = true,
    UpdateProgressStrings strings = const UpdateProgressStrings(),
    List<String> relaunchArgs = const <String>[],
    bool exitCurrentApp = true,
  }) {
    throw UnimplementedError('installAndRelaunch() has not been implemented.');
  }
}
