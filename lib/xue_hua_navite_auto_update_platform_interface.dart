import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'xue_hua_navite_auto_update_method_channel.dart';

abstract class XueHuaNaviteAutoUpdatePlatform extends PlatformInterface {
  /// Constructs a XueHuaNaviteAutoUpdatePlatform.
  XueHuaNaviteAutoUpdatePlatform() : super(token: _token);

  static final Object _token = Object();

  static XueHuaNaviteAutoUpdatePlatform _instance = MethodChannelXueHuaNaviteAutoUpdate();

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

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
