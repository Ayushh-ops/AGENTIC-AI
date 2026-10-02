import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/main.dart';
import 'package:mobile_app/services/settings_service.dart';
import 'package:mobile_app/widgets/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Settings Service & Helpers', () {
    test('key mask helper never reveals more than 4 chars', () {
      // Empty or short keys
      expect(SettingsService.maskKey(''), '••••');
      expect(SettingsService.maskKey('   '), '••••');
      expect(SettingsService.maskKey('a'), '••••');
      expect(SettingsService.maskKey('12'), '••••');
      expect(SettingsService.maskKey('123'), '••••');
      expect(SettingsService.maskKey('1234'), '••••');

      // Typical keys
      final mask5 = SettingsService.maskKey('12345');
      expect(mask5, '••••2345');
      expect(mask5.replaceAll('•', '').length, lessThanOrEqualTo(4));

      final groqMask = SettingsService.maskKey('gsk_0123456789abcdef');
      expect(groqMask, '••••cdef');
      expect(groqMask.replaceAll('•', '').length, lessThanOrEqualTo(4));

      final tavilyMask = SettingsService.maskKey('tvly-abcdef9876543210');
      expect(tavilyMask, '••••3210');
      expect(tavilyMask.replaceAll('•', '').length, lessThanOrEqualTo(4));

      // Extremely long key
      final longKey = 'k' * 200;
      final longMask = SettingsService.maskKey(longKey);
      expect(longMask, '••••kkkk');
      expect(longMask.replaceAll('•', '').length, lessThanOrEqualTo(4));
    });

    test('request headers built correctly (and omitted when no keys)', () {
      // When both key lists are null or empty: headers map is empty
      final emptyHeaders = SettingsService.buildKeyHeaders();
      expect(emptyHeaders, isEmpty);
      expect(emptyHeaders.containsKey('X-Groq-Keys'), isFalse);
      expect(emptyHeaders.containsKey('X-Tavily-Keys'), isFalse);

      final emptyExplicit = SettingsService.buildKeyHeaders(
        groqKeys: [],
        tavilyKeys: [],
      );
      expect(emptyExplicit, isEmpty);

      // Only Groq keys
      final groqOnly = SettingsService.buildKeyHeaders(
        groqKeys: ['key_g1', 'key_g2'],
      );
      expect(groqOnly.length, 1);
      expect(groqOnly['X-Groq-Keys'], 'key_g1,key_g2');
      expect(groqOnly.containsKey('X-Tavily-Keys'), isFalse);

      // Only Tavily keys
      final tavilyOnly = SettingsService.buildKeyHeaders(
        tavilyKeys: ['key_t1', 'key_t2', 'key_t3'],
      );
      expect(tavilyOnly.length, 1);
      expect(tavilyOnly['X-Tavily-Keys'], 'key_t1,key_t2,key_t3');
      expect(tavilyOnly.containsKey('X-Groq-Keys'), isFalse);

      // Both keys present
      final both = SettingsService.buildKeyHeaders(
        groqKeys: ['gsk_1', 'gsk_2'],
        tavilyKeys: ['tvly_1'],
      );
      expect(both.length, 2);
      expect(both['X-Groq-Keys'], 'gsk_1,gsk_2');
      expect(both['X-Tavily-Keys'], 'tvly_1');
    });

    test('settings key validation rejects empty, whitespace, duplicate, long, or >10 keys', () {
      final existing = ['key1', 'key2'];
      expect(SettingsService.validateKey('', existing), 'Key cannot be empty');
      expect(SettingsService.validateKey('   ', existing), 'Key cannot be empty');
      expect(SettingsService.validateKey('key with spaces', existing),
          'Key cannot contain whitespace');
      expect(SettingsService.validateKey('key1', existing),
          'Key already added');
      expect(SettingsService.validateKey('x' * 201, existing),
          'Key cannot exceed 200 characters');

      // Max 10 keys
      final tenKeys = List.generate(10, (i) => 'key_$i');
      expect(SettingsService.validateKey('key_11', tenKeys),
          'Maximum of 10 keys reached');

      // Valid key
      expect(SettingsService.validateKey('gsk_valid_key_123', existing), isNull);
    });

    test('settings persist round trip (SharedPreferences.setMockInitialValues)', () async {
      SharedPreferences.setMockInitialValues({
        'settings_groq_keys': ['gsk_test1', 'gsk_test2'],
        'settings_tavily_keys': ['tvly_test1'],
        'settings_report_language': 'Hindi',
        'app_theme_mode': 'dark',
        'settings_cursor_spotlight': false,
        'settings_reduce_motion': true,
        'settings_save_history': false,
      });

      final settings = SettingsService.instance;
      await settings.load();

      expect(settings.groqKeys, ['gsk_test1', 'gsk_test2']);
      expect(settings.tavilyKeys, ['tvly_test1']);
      expect(settings.reportLanguage, 'Hindi');
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.cursorSpotlight, isFalse);
      expect(settings.reduceMotion, isTrue);
      expect(settings.saveHistory, isFalse);
      expect(settings.isSpotlightActive, isFalse); // reduceMotion is true so spotlight is off

      // Modify settings and verify persistence
      await settings.addGroqKey('gsk_test3');
      await settings.removeGroqKey(0);
      await settings.setReportLanguage('Spanish');
      await settings.setThemeMode(ThemeMode.light);
      await settings.setCursorSpotlight(true);
      await settings.setReduceMotion(false);
      await settings.setSaveHistory(true);

      expect(settings.groqKeys, ['gsk_test2', 'gsk_test3']);
      expect(settings.reportLanguage, 'Spanish');
      expect(settings.themeMode, ThemeMode.light);
      expect(settings.cursorSpotlight, isTrue);
      expect(settings.reduceMotion, isFalse);
      expect(settings.saveHistory, isTrue);
      expect(settings.isSpotlightActive, isTrue);

      // Re-load and verify everything was stored
      await settings.load();
      expect(settings.groqKeys, ['gsk_test2', 'gsk_test3']);
      expect(settings.reportLanguage, 'Spanish');
      expect(settings.themeMode, ThemeMode.light);
      expect(settings.cursorSpotlight, isTrue);
      expect(settings.reduceMotion, isFalse);
      expect(settings.saveHistory, isTrue);
    });

    test('isUnencryptedHttp detects insecure HTTP URLs correctly', () {
      expect(SettingsService.isUnencryptedHttp('http://example.com:8000'), isTrue);
      expect(SettingsService.isUnencryptedHttp('http://api.myapp.com'), isTrue);
      expect(SettingsService.isUnencryptedHttp('https://api.myapp.com'), isFalse);
      expect(SettingsService.isUnencryptedHttp('http://localhost:8000'), isFalse);
      expect(SettingsService.isUnencryptedHttp('http://127.0.0.1:8000'), isFalse);
      expect(SettingsService.isUnencryptedHttp('http://10.0.2.2:8000'), isFalse);
    });
  });

  group('Settings Dialog Widget Tests', () {
    testWidgets('settings dialog at 360px has no overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({
        'settings_groq_keys': ['gsk_existing123456'],
        'settings_tavily_keys': ['tvly_existing789012'],
        'settings_report_language': 'English',
      });
      await SettingsService.instance.load();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SettingsDialog(
              baseUrl: 'http://my-backend.example.com',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'SettingsDialog has RenderFlex overflow at 360px');

      // Verify sections exist
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('API KEYS'), findsOneWidget);
      expect(find.text('REPORT'), findsOneWidget);
      expect(find.text('APPEARANCE'), findsOneWidget);
      expect(find.text('DATA'), findsOneWidget);

      // Verify status line
      expect(find.text('Using your keys'), findsOneWidget);

      // Verify masked keys
      expect(find.text('••••3456'), findsOneWidget);
      expect(find.text('••••9012'), findsOneWidget);

      // Verify insecure HTTP warning
      expect(find.textContaining('unencrypted HTTP'), findsOneWidget);

      // Verify language helper
      expect(find.text('Quotes stay in their original language.'), findsOneWidget);
    });

    testWidgets('top bar gear icon opens settings dialog on landing and workspace', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.load();

      await tester.pumpWidget(const ResearchAssistantApp());
      await tester.pumpAndSettle();

      // Top bar gear icon on landing
      final settingsButtonFinder = find.byTooltip('Settings');
      expect(settingsButtonFinder, findsOneWidget);

      await tester.tap(settingsButtonFinder);
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('API KEYS'), findsOneWidget);

      // Close dialog
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('API KEYS'), findsNothing);

      // Transition to workspace
      await tester.tap(find.widgetWithText(FilledButton, 'Get started').first);
      await tester.pumpAndSettle();

      // Top bar gear icon in workspace
      expect(settingsButtonFinder, findsOneWidget);
      await tester.tap(settingsButtonFinder);
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('REPORT'), findsOneWidget);
    });
  });
}
