import 'dart:async';

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
  testWidgets('a restored preference reaches the mounted card', (tester) async {
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      testAppWithL10n(
        Scaffold(body: ChatDensitySettingsCard(preferences: prefs)),
      ),
    );
    expect(find.textContaining('Comfortable'), findsOneWidget);

    // What an import does: storage is rewritten, then read back through the
    // store. Nothing remounts the card, so only the broadcast can update it.
    await prefs.setString(ChatDensity.preferenceKey, 'compact');
    ChatDensityStore(prefs).read();
    await tester.pump();

    expect(find.textContaining('Compact'), findsOneWidget);
    expect(find.textContaining('Comfortable'), findsNothing);
  });

  testWidgets('a picker dismissed mid-write does not close Settings', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = Completer<void>();

    await tester.pumpWidget(
      testAppWithL10n(
        Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: ChatDensitySettingsCard(
                      preferences: prefs,
                      testSaveDensity: (_) => pending.future,
                    ),
                  ),
                ),
              ),
              child: const Text('open settings'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chat density'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compact'));
    await tester.pump();

    // The user dismisses the picker while the write is still in flight.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Chat density'), findsOneWidget);

    pending.complete();
    await tester.pumpAndSettle();

    // Settings, not the picker, must survive the late pop.
    expect(find.text('Chat density'), findsOneWidget);
    expect(find.textContaining('Compact'), findsOneWidget);
  });
}
