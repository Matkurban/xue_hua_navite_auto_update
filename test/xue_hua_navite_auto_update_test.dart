import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_navite_auto_update/xue_hua_navite_auto_update.dart';
import 'package:xue_hua_navite_auto_update/xue_hua_navite_auto_update_platform_interface.dart';
import 'package:xue_hua_navite_auto_update/xue_hua_navite_auto_update_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockXueHuaNaviteAutoUpdatePlatform
    with MockPlatformInterfaceMixin
    implements XueHuaNaviteAutoUpdatePlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final XueHuaNaviteAutoUpdatePlatform initialPlatform = XueHuaNaviteAutoUpdatePlatform.instance;

  test('$MethodChannelXueHuaNaviteAutoUpdate is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelXueHuaNaviteAutoUpdate>());
  });

  test('getPlatformVersion', () async {
    XueHuaNaviteAutoUpdate xueHuaNaviteAutoUpdatePlugin = XueHuaNaviteAutoUpdate();
    MockXueHuaNaviteAutoUpdatePlatform fakePlatform = MockXueHuaNaviteAutoUpdatePlatform();
    XueHuaNaviteAutoUpdatePlatform.instance = fakePlatform;

    expect(await xueHuaNaviteAutoUpdatePlugin.getPlatformVersion(), '42');
  });
}
