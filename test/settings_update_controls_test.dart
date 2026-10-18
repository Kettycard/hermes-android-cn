import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('update controls remain available if dashboard settings fail', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(
          connection: SavedConnection(
            id: 'offline-dashboard',
            label: 'Offline dashboard',
            host: '127.0.0.1',
            port: 8642,
            dashboardPortOverride: 1,
            apiKey: 'test-only',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Failed to load settings'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.text('Check for updates on launch'), findsOneWidget);
    await tester.tap(find.text('Check for updates on launch'));
    await tester.pumpAndSettle();
    expect(
      await SharedPreferences.getInstance().then(
        (prefs) => prefs.getBool('app_update_check_on_launch_v1'),
      ),
      isFalse,
    );
  });
}
