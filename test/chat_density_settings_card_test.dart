import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/services/chat_density_preference.dart';
import 'package:hermes_android/core/widgets/chat_density_settings_card.dart';

import 'support/l10n_test_utils.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    chatDensitySelection.value = ChatDensity.comfortable;
  });

  testWidgets('the card reports the stored density', (tester) async {
    SharedPreferences.setMockInitialValues({
      ChatDensity.preferenceKey: 'compact',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      testAppWithL10n(
        Scaffold(body: ChatDensitySettingsCard(preferences: prefs)),
      ),
    );

    expect(find.textContaining('Compact'), findsOneWidget);
    expect(find.textContaining('Comfortable'), findsNothing);
  });

  testWidgets('choosing Compact stores it and broadcasts the change', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = <ChatDensity>[];
    void listener() => seen.add(chatDensitySelection.value);
    chatDensitySelection.addListener(listener);
    addTearDown(() => chatDensitySelection.removeListener(listener));

    await tester.pumpWidget(
      testAppWithL10n(
        Scaffold(body: ChatDensitySettingsCard(preferences: prefs)),
      ),
    );

    await tester.tap(find.text('Chat density'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compact'));
    await tester.pumpAndSettle();

    expect(prefs.getString(ChatDensity.preferenceKey), 'compact');
    expect(chatDensitySelection.value, ChatDensity.compact);
    expect(seen, [ChatDensity.compact]);
  });
}
