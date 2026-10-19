// Regression test: opening a modal with accessibility (semantics) enabled must
// not throw. Previously `ModalCard` set `scopesRoute` without
// `explicitChildNodes`, which crashed every dialog ("explicitChildNodes must be
// set to true if scopes route is true").
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/core/providers.dart';
import 'package:lockin/core/widgets/lock_button.dart';
import 'package:lockin/core/widgets/modal_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('ModalCard opens with semantics enabled without throwing', (tester) async {
    final semantics = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showAppModal<void>(
                    context,
                    builder: (ctx) => ModalCard(
                      title: 'Lock this commitment?',
                      children: [
                        const Text('Body'),
                        LockButton(title: 'YES', onPressed: () => Navigator.of(ctx).pop()),
                      ],
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Lock this commitment?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
