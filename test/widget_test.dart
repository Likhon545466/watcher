import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watcher/main.dart';
import 'package:watcher/providers/cloud_backup_provider.dart';
import 'package:watcher/providers/settings_provider.dart';
import 'package:watcher/providers/show_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Watcher app smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ShowProvider>(create: (_) => ShowProvider()),
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider(),
          ),
          ChangeNotifierProvider<CloudBackupProvider>(
            create: (_) => CloudBackupProvider(),
          ),
        ],
        child: const WatcherApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 10));

    expect(find.text('Watcher'), findsAtLeastNWidgets(1));
  });
}
