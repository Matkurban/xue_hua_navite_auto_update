import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_navite_auto_update_example/main.dart';

void main() {
  testWidgets('Workbench UI renders all 3 auto-update workflow sections', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const AutoUpdateExampleApp(launchArgs: <String>['--updated-from=1.0.0']),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Runtime Environment Pre-flight'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Package Selection & Streaming SHA-256'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Out-of-Process Progress UI & Relaunch'),
      findsOneWidget,
    );
  });
}
