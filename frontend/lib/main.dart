import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api/api_service.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

/// Global notifier for toggling between system, light, and dark themes.
final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier<ThemeMode>(ThemeMode.system);

/// Loads the persisted theme mode from local storage.
Future<void> loadThemeMode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('app_theme_mode');
    if (saved == 'light') {
      themeModeNotifier.value = ThemeMode.light;
    } else if (saved == 'dark') {
      themeModeNotifier.value = ThemeMode.dark;
    } else {
      themeModeNotifier.value = ThemeMode.system;
    }
  } catch (_) {}
}

/// Persists the selected theme mode to local storage.
Future<void> saveThemeMode(ThemeMode mode) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_theme_mode', mode.name);
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
