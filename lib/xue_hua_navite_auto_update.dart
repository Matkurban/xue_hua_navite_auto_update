
import 'xue_hua_navite_auto_update_platform_interface.dart';

class XueHuaNaviteAutoUpdate {
  Future<String?> getPlatformVersion() {
    return XueHuaNaviteAutoUpdatePlatform.instance.getPlatformVersion();
  }
}
