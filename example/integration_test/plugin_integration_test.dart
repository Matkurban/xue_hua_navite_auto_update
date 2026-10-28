import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xue_hua_navite_auto_update/xue_hua_navite_auto_update.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('checkEnvironment integration test', (WidgetTester tester) async {
    const XueHuaNaviteAutoUpdate plugin = XueHuaNaviteAutoUpdate();
    final UpdateEnvironmentInfo env = await plugin.checkEnvironment();
    expect(env.platform.isNotEmpty, isTrue);
    expect(env.executablePath.isNotEmpty, isTrue);
    expect(env.processId, greaterThan(0));
  });
}
