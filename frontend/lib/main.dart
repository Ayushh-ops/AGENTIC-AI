import 'package:flutter/material.dart';
import 'api/api_service.dart';
import 'screens/home_screen.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';

/// Global notifier for toggling between system, light, and dark themes.
final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier<ThemeMode>(ThemeMode.system);

/// Loads the persisted theme mode from local storage.
Future<void> loadThemeMode() async {
  try {
    await SettingsService.instance.load();
    themeModeNotifier.value = SettingsService.instance.themeMode;
  } catch (_) {}
}

/// Persists the selected theme mode to local storage.
Future<void> saveThemeMode(ThemeMode mode) async {
  try {
    await SettingsService.instance.setThemeMode(mode);
    themeModeNotifier.value = mode;
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.instance.load();
  await loadThemeMode();
  runApp(const ResearchAssistantApp());
}

class ResearchAssistantApp extends StatelessWidget {
  final ApiService? apiService;
  const ResearchAssistantApp({super.key, this.apiService});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'Agentic Research Assistant',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          home: HomeScreen(apiService: apiService),
        );
      },
    );
  }
}
