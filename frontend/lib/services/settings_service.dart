import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supported report languages allowed by the backend.
const List<String> kAllowedReportLanguages = [
  'English',
  'Hindi',
  'Spanish',
  'French',
  'German',
  'Portuguese',
  'Bengali',
  'Tamil',
  'Telugu',
  'Marathi',
  'Arabic',
  'Japanese',
];

/// Singleton service managing app settings, local preferences, and API keys.
class SettingsService extends ChangeNotifier {
  static final SettingsService instance = SettingsService._internal();

  SettingsService._internal();

  factory SettingsService() => instance;

  // Preferences Keys
  static const String keyGroqKeys = 'settings_groq_keys';
  static const String keyTavilyKeys = 'settings_tavily_keys';
  static const String keyDefaultType = 'settings_default_type';
  static const String keyDefaultDepth = 'settings_default_depth';
  static const String keyReportLanguage = 'settings_report_language';
  static const String keyThemeMode = 'app_theme_mode';
  static const String keyCursorSpotlight = 'settings_cursor_spotlight';
  static const String keyReduceMotion = 'settings_reduce_motion';
  static const String keySaveHistory = 'settings_save_history';

  // State
  List<String> _groqKeys = [];
  List<String> _tavilyKeys = [];
  String _defaultType = 'general';
  String _defaultDepth = 'standard';
  String _reportLanguage = 'English';
  ThemeMode _themeMode = ThemeMode.system;
  bool _cursorSpotlight = true;
  bool _reduceMotion = false;
  bool _saveHistory = true;

  // Getters
  List<String> get groqKeys => List.unmodifiable(_groqKeys);
  List<String> get tavilyKeys => List.unmodifiable(_tavilyKeys);
  String get defaultType => _defaultType;
  String get defaultDepth => _defaultDepth;
  String get reportLanguage => _reportLanguage;
  ThemeMode get themeMode => _themeMode;
  bool get cursorSpotlight => _cursorSpotlight;
  bool get reduceMotion => _reduceMotion;
  bool get saveHistory => _saveHistory;

  /// Spotlight is active only if enabled and reduce motion is OFF.
  bool get isSpotlightActive => _cursorSpotlight && !_reduceMotion;

  /// Effective transition/animation duration honoring reduce-motion.
  Duration transitionDuration(Duration normal) =>
      _reduceMotion ? Duration.zero : normal;

  /// Masks API keys revealing at most the last 4 characters.
  /// Never reveals more than 4 chars under any input.
  static String maskKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty || trimmed.length <= 4) {
      return '••••';
    }
    return '••••${trimmed.substring(trimmed.length - 4)}';
  }

  /// Validates a potential API key before adding.
  static String? validateKey(String key, List<String> existingKeys) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      return 'Key cannot be empty';
    }
    if (existingKeys.length >= 10) {
      return 'Maximum of 10 keys reached';
    }
    if (trimmed.contains(RegExp(r'\s'))) {
      return 'Key cannot contain whitespace';
    }
    if (trimmed.length > 200) {
      return 'Key cannot exceed 200 characters';
    }
    if (existingKeys.contains(trimmed)) {
      return 'Key already added';
    }
    return null;
  }

  /// Builds request headers for API keys, returning empty map if no keys exist.
  static Map<String, String> buildKeyHeaders({
    List<String>? groqKeys,
    List<String>? tavilyKeys,
  }) {
    final headers = <String, String>{};
    if (groqKeys != null && groqKeys.isNotEmpty) {
      headers['X-Groq-Keys'] = groqKeys.map((k) => k.trim()).join(',');
    }
    if (tavilyKeys != null && tavilyKeys.isNotEmpty) {
      headers['X-Tavily-Keys'] = tavilyKeys.map((k) => k.trim()).join(',');
    }
    return headers;
  }

  /// Returns true if the URL uses plain HTTP and is not a local development address.
  static bool isUnencryptedHttp(String url) {
    try {
      final uri = Uri.parse(url.trim());
      if (uri.scheme.toLowerCase() != 'http') return false;
      final host = uri.host.toLowerCase();
      if (host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2') {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Loads persisted settings from SharedPreferences.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _groqKeys = prefs.getStringList(keyGroqKeys) ?? [];
      _tavilyKeys = prefs.getStringList(keyTavilyKeys) ?? [];

      final savedType = prefs.getString(keyDefaultType);
      if (savedType != null && ['general', 'news', 'academic'].contains(savedType)) {
        _defaultType = savedType;
      }

      final savedDepth = prefs.getString(keyDefaultDepth);
      if (savedDepth != null && ['quick', 'standard', 'deep'].contains(savedDepth)) {
        _defaultDepth = savedDepth;
      }

      final savedLang = prefs.getString(keyReportLanguage);
      if (savedLang != null && kAllowedReportLanguages.contains(savedLang)) {
        _reportLanguage = savedLang;
      }

      final savedTheme = prefs.getString(keyThemeMode);
      if (savedTheme == 'light') {
        _themeMode = ThemeMode.light;
      } else if (savedTheme == 'dark') {
        _themeMode = ThemeMode.dark;
      } else {
        _themeMode = ThemeMode.system;
      }

      _cursorSpotlight = prefs.getBool(keyCursorSpotlight) ?? true;
      _reduceMotion = prefs.getBool(keyReduceMotion) ?? false;
      _saveHistory = prefs.getBool(keySaveHistory) ?? true;
      notifyListeners();
    } catch (_) {}
  }

  // --- Mutators ---

  Future<bool> addGroqKey(String key) async {
    final err = validateKey(key, _groqKeys);
    if (err != null) return false;
    _groqKeys.add(key.trim());
    await _persistStringList(keyGroqKeys, _groqKeys);
    notifyListeners();
    return true;
  }

  Future<void> removeGroqKey(int index) async {
    if (index >= 0 && index < _groqKeys.length) {
      _groqKeys.removeAt(index);
      await _persistStringList(keyGroqKeys, _groqKeys);
      notifyListeners();
    }
  }

  Future<bool> addTavilyKey(String key) async {
    final err = validateKey(key, _tavilyKeys);
    if (err != null) return false;
    _tavilyKeys.add(key.trim());
    await _persistStringList(keyTavilyKeys, _tavilyKeys);
    notifyListeners();
    return true;
  }

  Future<void> removeTavilyKey(int index) async {
    if (index >= 0 && index < _tavilyKeys.length) {
      _tavilyKeys.removeAt(index);
      await _persistStringList(keyTavilyKeys, _tavilyKeys);
      notifyListeners();
    }
  }

  Future<void> clearAllKeys() async {
    _groqKeys.clear();
    _tavilyKeys.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyGroqKeys);
    await prefs.remove(keyTavilyKeys);
    notifyListeners();
  }

  Future<void> setDefaultType(String type) async {
    if (['general', 'news', 'academic'].contains(type)) {
      _defaultType = type;
      await _persistString(keyDefaultType, type);
      notifyListeners();
    }
  }

  Future<void> setDefaultDepth(String depth) async {
    if (['quick', 'standard', 'deep'].contains(depth)) {
      _defaultDepth = depth;
      await _persistString(keyDefaultDepth, depth);
      notifyListeners();
    }
  }

  Future<void> setReportLanguage(String language) async {
    if (kAllowedReportLanguages.contains(language)) {
      _reportLanguage = language;
      await _persistString(keyReportLanguage, language);
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _persistString(keyThemeMode, mode.name);
    notifyListeners();
  }

  Future<void> setCursorSpotlight(bool value) async {
    _cursorSpotlight = value;
    await _persistBool(keyCursorSpotlight, value);
    notifyListeners();
  }

  Future<void> setReduceMotion(bool value) async {
    _reduceMotion = value;
    await _persistBool(keyReduceMotion, value);
    notifyListeners();
  }

  Future<void> setSaveHistory(bool value) async {
    _saveHistory = value;
    await _persistBool(keySaveHistory, value);
    notifyListeners();
  }

  // --- Helper storage writers ---

  Future<void> _persistString(String key, String val) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, val);
    } catch (_) {}
  }

  Future<void> _persistBool(String key, bool val) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, val);
    } catch (_) {}
  }

  Future<void> _persistStringList(String key, List<String> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, list);
    } catch (_) {}
  }
}
