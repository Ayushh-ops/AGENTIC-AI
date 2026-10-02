import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/api/api_service.dart';
import 'package:mobile_app/main.dart';
import 'package:mobile_app/models/history_item.dart';
import 'package:mobile_app/utils/report_export_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestMockApiService extends ApiService {
  Completer<AskResponse> completer = Completer<AskResponse>();

  @override
  Future<AskResponse> ask(
    String message, {
    String? researchType = 'general',
    String? depth = 'standard',
  }) {
    return completer.future;
  }
}

void main() {
  test('Markdown builder includes title, tally, and claim status', () {
    const research = ResearchResponse(
      topic: 'Quantum Computing 2026',
      reportMarkdown: 'Quantum computers have achieved fault tolerance.',
      sources: [
        SourceItem(title: 'Nature Physics', url: 'https://nature.com/article1', content: 'Details.'),
      ],
      claims: [
        ClaimItem(
          statement: 'Error threshold exceeded.',
          status: 'supported',
          evidence: 'Logical error rate dropped.',
          sourceUrls: ['https://nature.com/article1'],
        ),
        ClaimItem(
          statement: 'Consumer quantum laptops exist.',
          status: 'unsupported',
          evidence: 'No hardware available.',
          sourceUrls: [],
        ),
      ],
    );

    final md = buildReportMarkdown(research: research, type: 'news', depth: 'deep');

    expect(md, contains('Quantum Computing 2026'));
    expect(md, contains('Tally:'));
    expect(md, contains('supported'));
    expect(md, contains('AI-generated, unverified. Read the evidence under each claim.'));
  });

  test('JSON report export then parse round trip equals original', () {
    const original = ResearchResponse(
      topic: 'Renewable Energy Progress',
      reportMarkdown: 'Solar installations surged worldwide.',
      sources: [
        SourceItem(title: 'IEA Report', url: 'https://iea.org/solar', content: 'Capacity up 30%.'),
      ],
      claims: [
        ClaimItem(
          statement: 'Solar generation capacity grew by 30%.',
          status: 'supported',
          evidence: 'Verified across regional grids.',
          sourceUrls: ['https://iea.org/solar'],
        ),
      ],
    );

    final exportedMap = buildReportJson(
      research: original,
      type: 'academic',
      depth: 'standard',
    );
    final jsonStr = jsonEncode(exportedMap);
    final parsed = parseReportJson(jsonStr);

    expect(parsed.app, 'Multi Agent Research Assistant');
    expect(parsed.version, 1);
    expect(parsed.topic, original.topic);
    expect(parsed.type, 'academic');
    expect(parsed.depth, 'standard');
    expect(parsed.result.topic, original.topic);
    expect(parsed.result.reportMarkdown, original.reportMarkdown);
    expect(parsed.result.claims.length, 1);
    expect(parsed.result.claims.first.statement, original.claims.first.statement);
    expect(parsed.result.claims.first.status, original.claims.first.status);
    expect(parsed.result.claims.first.evidence, original.claims.first.evidence);
    expect(parsed.result.sources.length, 1);
    expect(parsed.result.sources.first.title, original.sources.first.title);
    expect(parsed.result.sources.first.url, original.sources.first.url);
  });

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

    // Verify default selector text on visible segmented controls
    expect(find.text('General'), findsWidgets);
    expect(find.text('Standard'), findsWidgets);
  });

  testWidgets('About dialog displays Researcher, Fact-Checker, and Synthesizer agents with depth description', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ResearchAssistantApp());
    await tester.pumpAndSettle();

    // Find and tap About button in top bar (or hero footer)
    final aboutFinder = find.byTooltip('About Multi Agent Research Assistant');
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

    // Open workspace from landing screen
    final openAppFinder = find.widgetWithText(FilledButton, 'Get started');
    if (openAppFinder.evaluate().isNotEmpty) {
      await tester.tap(openAppFinder.first);
      await tester.pumpAndSettle();
    }

    // Verify sidebar shows formatted label "News - Deep"
    expect(find.text('News - Deep'), findsOneWidget);

    // Tap the history item in sidebar
    await tester.tap(find.text('Quantum Computing'));
    await tester.pumpAndSettle();

    // Verify report card renders chips for Type and Depth
    expect(find.text('Type: News'), findsWidgets);
    expect(find.text('Depth: Deep'), findsWidgets);
    expect(find.textContaining('QUANTUM COMPUTING REPORT'), findsOneWidget);
  });

  testWidgets('Layout renders without RenderFlex overflow at widths 360, 768, and 1280 in light and dark mode', (WidgetTester tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      themeModeNotifier.value = ThemeMode.system;
    });

    for (final width in [360.0, 768.0, 1280.0]) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        themeModeNotifier.value = mode;

        await tester.pumpWidget(const ResearchAssistantApp());
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'RenderFlex overflow occurred on landing screen at width $width in $mode');

        final openAppFinder = find.widgetWithText(FilledButton, 'Get started');
        if (openAppFinder.evaluate().isNotEmpty) {
          await tester.tap(openAppFinder.first);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull,
              reason: 'RenderFlex overflow occurred in workspace at width $width in $mode');
        }
      }
    }
  });

  testWidgets('Composer button placement uses MainAxisAlignment.spaceBetween', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ResearchAssistantApp());
    await tester.pumpAndSettle();

    // Landing composer controls row
    final landingRowFinder = find.byKey(const ValueKey('composer_controls_row'));
    expect(landingRowFinder, findsOneWidget);
    final landingRow = tester.widget<Row>(landingRowFinder);
    expect(landingRow.mainAxisAlignment, MainAxisAlignment.spaceBetween);

    // Enter workspace empty state
    final getStartedFinder = find.widgetWithText(FilledButton, 'Get started');
    await tester.tap(getStartedFinder.first);
    await tester.pumpAndSettle();

    // Workspace empty state composer controls row
    final wsRowFinder = find.byKey(const ValueKey('composer_controls_row'));
    expect(wsRowFinder, findsOneWidget);
    final wsRow = tester.widget<Row>(wsRowFinder);
    expect(wsRow.mainAxisAlignment, MainAxisAlignment.spaceBetween);
  });

  testWidgets('Stable top bar row 1 has height 64 and About/theme pinned to right across empty, loading, and result', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockApi = _TestMockApiService();
    await tester.pumpWidget(ResearchAssistantApp(apiService: mockApi));
    await tester.pumpAndSettle();

    // Enter workspace empty state
    await tester.tap(find.widgetWithText(FilledButton, 'Get started').first);
    await tester.pumpAndSettle();

    // --- 1. EMPTY STATE ---
    final row1Finder = find.byKey(const ValueKey('top_bar_row_1'));
    expect(row1Finder, findsOneWidget);
    expect(tester.getSize(row1Finder).height, 64.0);
    final double row1Top = tester.getTopLeft(row1Finder).dy;

    final aboutFinder = find.widgetWithText(TextButton, 'About');
    final themeFinder = find.byTooltip('Switch to dark mode');
    expect(aboutFinder, findsOneWidget);
    expect(themeFinder, findsOneWidget);

    final row1RectEmpty = tester.getRect(row1Finder);
    final themeRectEmpty = tester.getRect(themeFinder);
    final aboutRectEmpty = tester.getRect(aboutFinder);
    expect(row1RectEmpty.right - themeRectEmpty.right, lessThanOrEqualTo(24.0));
    expect(aboutRectEmpty.right, lessThanOrEqualTo(themeRectEmpty.left));
    expect(find.byKey(const ValueKey('top_bar_row_2')), findsNothing);

    // --- 2. LOADING STATE ---
    await tester.enterText(find.byType(TextField), 'Test Quantum');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Research'));
    await tester.pump(); // starts request without settling

    expect(tester.getSize(row1Finder).height, 64.0);
    expect(tester.getTopLeft(row1Finder).dy, row1Top);
    final themeRectLoading = tester.getRect(themeFinder);
    expect(row1RectEmpty.right - themeRectLoading.right, lessThanOrEqualTo(24.0));
    expect(find.byKey(const ValueKey('top_bar_row_2')), findsOneWidget);

    // --- 3. RESULT STATE ---
    mockApi.completer.complete(
      const AskResponse(
        mode: 'research',
        research: ResearchResponse(
          topic: 'Test Quantum',
          reportMarkdown: 'Result content',
          sources: [
            SourceItem(title: 'Src', url: 'https://example.com', content: 'Info'),
          ],
          claims: [
            ClaimItem(
              statement: 'Claim statement',
              status: 'supported',
              evidence: 'Info',
              sourceUrls: ['https://example.com'],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(row1Finder).height, 64.0);
    expect(tester.getTopLeft(row1Finder).dy, row1Top);
    final themeRectResult = tester.getRect(themeFinder);
    expect(row1RectEmpty.right - themeRectResult.right, lessThanOrEqualTo(24.0));
    expect(find.byKey(const ValueKey('top_bar_row_2')), findsOneWidget);
  });

  testWidgets('Seamless transition between landing and workspace with scroll reset on return', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ResearchAssistantApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('landing_content')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace_content')), findsNothing);

    // Tap Get started to transition to workspace
    await tester.tap(find.widgetWithText(FilledButton, 'Get started').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('landing_content')), findsNothing);
    expect(find.byKey(const ValueKey('workspace_content')), findsOneWidget);

    // Tap wordmark to return to landing
    await tester.tap(find.textContaining('Multi Agent').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('landing_content')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace_content')), findsNothing);
  });
}



