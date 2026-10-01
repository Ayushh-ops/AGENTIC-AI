import 'package:flutter/foundation.dart';

/// Provides the base URL for backend API requests.
///
/// Priority:
/// 1. Compile-time environment variable: `--dart-define=API_BASE_URL=...`
/// 2. Android Emulator fallback: `http://10.0.2.2:8000`
/// 3. Desktop / Web / iOS fallback: `http://127.0.0.1:8000`
class ApiConfig {
  static const String _definedBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get defaultBaseUrl {
    if (_definedBaseUrl.isNotEmpty) {
      return _definedBaseUrl;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }
}
