import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/api/api_service.dart';
import 'package:mobile_app/main.dart';
import 'package:mobile_app/models/history_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('HistoryItem deserialization supports new and legacy items safely', () {
    // New item with type and depth
    final newItem = HistoryItem.fromJson({
      'id': '1',
      'message': 'Test query',
      'mode': 'research',
      'research_type': 'news',
      'depth': 'deep',
      'timestamp': 1000,
    });
    expect(newItem.formattedTypeAndDepth, 'News - Deep');

    // Legacy item without type and depth
    final legacyItem = HistoryItem.fromJson({
      'id': '2',
      'message': 'Old query',
      'mode': 'research',
      'timestamp': 1000,
    });
    expect(legacyItem.formattedTypeAndDepth, 'General - Standard');

    // Chat mode item
    final chatItem = HistoryItem.fromJson({
      'id': '3',
      'message': 'hello',
      'mode': 'chat',
      'timestamp': 1000,
    });
    expect(chatItem.formattedTypeAndDepth, isNull);
  });

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

  testWidgets('Type and depth selectors render with default values', (WidgetTester tester) async {
    await tester.pumpWidget(const ResearchAssistantApp());
    await tester.pump();

    // Verify default selector text
    expect(find.text('Type: General'), findsOneWidget);
    expect(find.text('Depth: Standard'), findsOneWidget);
  });

  testWidgets('About dialog displays Researcher, Fact-Checker, and Synthesizer agents with depth description', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ResearchAssistantApp());
    await tester.pumpAndSettle();

    // Find and tap About button in top bar (or hero footer)
    final aboutFinder = find.byTooltip('About Multi-Agent Assistant');
    expect(aboutFinder, findsOneWidget);
    await tester.tap(aboutFinder);
    await tester.pumpAndSettle();

    // Verify agent names
    expect(find.textContaining('Researcher:'), findsOneWidget);
    expect(find.textContaining('Fact-Checker:'), findsOneWidget);
    expect(find.textContaining('Synthesizer:'), findsOneWidget);

    // Verify research depth description
    expect(
      find.textContaining(
        'Quick provides a fast single-search summary, Standard balances speed and corroboration, while Deep checks more sources but takes longer and uses more API calls.',
      ),
      findsOneWidget,
    );

    // Close the dialog
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('Selecting a history item displays research result with type and depth chips', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    const historyItem = HistoryItem(
      id: 'item_1',
      message: 'Quantum Computing',
      mode: 'research',
      researchType: 'news',
      depth: 'deep',
      research: ResearchResponse(
        topic: 'Quantum Computing',
        reportMarkdown: '# Quantum Computing Report\nRecent breakthroughs observed.',
        sources: [
          SourceItem(title: 'Nature News', url: 'https://nature.com/article1', content: 'Breakthrough details.'),
        ],
        claims: [
          ClaimItem(
            statement: 'Quantum error correction improved.',
            status: 'supported',
            evidence: 'Error rate dropped.',
            sourceUrls: ['https://nature.com/article1'],
          ),
        ],
      ),
      timestamp: 1000,
    );

    SharedPreferences.setMockInitialValues({
      'research_history_items_v2': jsonEncode([historyItem.toJson()]),
    });

    await tester.pumpWidget(const ResearchAssistantApp());
    await tester.pumpAndSettle();

    // Verify sidebar shows formatted label "News - Deep"
    expect(find.text('News - Deep'), findsOneWidget);

    // Tap the history item in sidebar
    await tester.tap(find.text('Quantum Computing'));
    await tester.pumpAndSettle();

    // Verify report card renders chips for Type and Depth
    expect(find.text('Type: News'), findsWidgets);
    expect(find.text('Depth: Deep'), findsWidgets);
    expect(find.textContaining('Quantum Computing Report'), findsOneWidget);
  });
}


