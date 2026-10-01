import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/main.dart';

void main() {
  testWidgets('Empty topic keeps the Research button disabled', (WidgetTester tester) async {
    // Build the application.
    await tester.pumpWidget(const ResearchAssistantApp());
    await tester.pump();

    // Find the Research button.
    final buttonFinder = find.widgetWithText(FilledButton, 'Research');
    expect(buttonFinder, findsOneWidget);

    // Initial state: topic text field is empty -> button is disabled (onPressed == null).
    final FilledButton initialButton = tester.widget<FilledButton>(buttonFinder);
    expect(initialButton.onPressed, isNull);

    // Find the topic text field.
    final textFieldFinder = find.byType(TextField);
    expect(textFieldFinder, findsOneWidget);
    expect(find.text('Ask or enter a research topic'), findsOneWidget);

    // Enter a valid research topic.
    await tester.enterText(textFieldFinder, 'Quantum Computing in 2026');
    await tester.pump();

    // The button must now be enabled.
    final FilledButton enabledButton = tester.widget<FilledButton>(buttonFinder);
    expect(enabledButton.onPressed, isNotNull);

    // Clear the topic or enter whitespace only.
    await tester.enterText(textFieldFinder, '   ');
    await tester.pump();

    // The button must return to disabled.
    final FilledButton disabledAgainButton = tester.widget<FilledButton>(buttonFinder);
    expect(disabledAgainButton.onPressed, isNull);
  });
}
