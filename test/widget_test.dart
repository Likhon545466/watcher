import 'package:flutter_test/flutter_test.dart';
import 'package:watcher/main.dart';

void main() {
  testWidgets('Watcher app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const WatcherApp());
    expect(find.text('Watcher'), findsOneWidget);
  });
}
