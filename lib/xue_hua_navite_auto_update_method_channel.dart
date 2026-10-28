import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'xue_hua_navite_auto_update_platform_interface.dart';

/// An implementation of [XueHuaNaviteAutoUpdatePlatform] that uses method channels.
class MethodChannelXueHuaNaviteAutoUpdate extends XueHuaNaviteAutoUpdatePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('xue_hua_navite_auto_update');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
