import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central theme definition for Agentic Research Assistant.
/// Features a custom Deep Teal / Ocean Indigo palette with warm Amber accents,
/// modern typography (Space Grotesk + Inter) with offline fallbacks,
/// and consistent spacing, elevation, and card shapes.
class AppTheme {
  // Spacing Scale
  static const double space4 = 4.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space20 = 20.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;
  static const double space48 = 48.0;

  // Corner Radius
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 18.0;
  static const double radiusCard = 16.0;
  static const double radiusPill = 28.0;

  // Distinctive Palette Seeds
  static const Color primarySeed = Color(0xFF0F766E); // Deep Teal
  static const Color accentSeed = Color(0xFFF59E0B); // Warm Amber
  static const Color indigoAccent = Color(0xFF4338CA); // Deep Indigo

  // Verification Status Colors (WCAG compliant)
  static const Color statusSupported = Color(0xFF10B981); // Emerald
  static const Color statusSupportedBgLight = Color(0xFFD1FAE5);
  static const Color statusSupportedBgDark = Color(0xFF064E3B);

  static const Color statusSingleSource = Color(0xFFF59E0B); // Amber
  static const Color statusSingleSourceBgLight = Color(0xFFFEF3C7);
  static const Color statusSingleSourceBgDark = Color(0xFF78350F);

  static const Color statusUnsupported = Color(0xFFEF4444); // Crimson
  static const Color statusUnsupportedBgLight = Color(0xFFFEE2E2);
  static const Color statusUnsupportedBgDark = Color(0xFF7F1D1D);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF0F766E), Color(0xFF0284C7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient primaryGradientDark = LinearGradient(
    colors: [Color(0xFF0D9488), Color(0xFF2563EB)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroTitleGradient = LinearGradient(
    colors: [Color(0xFF0F766E), Color(0xFF0284C7), Color(0xFF6366F1)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroTitleGradientDark = LinearGradient(
    colors: [Color(0xFF2DD4BF), Color(0xFF38BDF8), Color(0xFFA78BFA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Typography with safe offline fallback
  static TextStyle displayFont({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
  }) {
    try {
      return GoogleFonts.spaceGrotesk(
        textStyle: textStyle,
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
      );
    } catch (_) {
      return TextStyle(
        fontFamily: 'sans-serif',
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
      );
    }
  }

  static TextStyle bodyFont({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
    TextDecoration? decoration,
  }) {
    try {
      return GoogleFonts.inter(
        textStyle: textStyle,
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
        fontStyle: fontStyle,
        decoration: decoration,
      );
    } catch (_) {
      return TextStyle(
        fontFamily: 'sans-serif',
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
        fontStyle: fontStyle,
        decoration: decoration,
      );
    }
  }

  /// Light ColorScheme
  static ColorScheme get lightColorScheme {
    return ColorScheme.fromSeed(
      seedColor: primarySeed,
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xFF0F766E), // Deep Teal
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFCCFBF1),
      onPrimaryContainer: const Color(0xFF115E59),
      secondary: const Color(0xFFD97706), // Warm Amber
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFFEF3C7),
      onSecondaryContainer: const Color(0xFF78350F),
      tertiary: const Color(0xFF4F46E5), // Indigo
      surface: const Color(0xFFF8FAFC), // Slate 50
      onSurface: const Color(0xFF0F172A), // Slate 900
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF1F5F9), // Slate 100
      surfaceContainer: const Color(0xFFFFFFFF),
      surfaceContainerHigh: const Color(0xFFF1F5F9),
      surfaceContainerHighest: const Color(0xFFE2E8F0), // Slate 200
      outline: const Color(0xFF94A3B8), // Slate 400
      outlineVariant: const Color(0xFFCBD5E1), // Slate 300
      onSurfaceVariant: const Color(0xFF475569), // Slate 600
    );
  }

  /// Dark ColorScheme
  static ColorScheme get darkColorScheme {
    return ColorScheme.fromSeed(
      seedColor: primarySeed,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF2DD4BF), // Vibrant Teal
      onPrimary: const Color(0xFF042F2C),
      primaryContainer: const Color(0xFF134E4A),
      onPrimaryContainer: const Color(0xFFCCFBF1),
      secondary: const Color(0xFFFBBF24), // Bright Amber
      onSecondary: const Color(0xFF451A03),
      secondaryContainer: const Color(0xFF78350F),
      onSecondaryContainer: const Color(0xFFFEF3C7),
      tertiary: const Color(0xFF818CF8), // Light Indigo
      surface: const Color(0xFF0B132B), // Deep Midnight Slate
      onSurface: const Color(0xFFF1F5F9), // Slate 100
      surfaceContainerLowest: const Color(0xFF070C1B),
      surfaceContainerLow: const Color(0xFF0E172C),
      surfaceContainer: const Color(0xFF131D36),
      surfaceContainerHigh: const Color(0xFF1A2644),
      surfaceContainerHighest: const Color(0xFF223256),
      outline: const Color(0xFF64748B), // Slate 500
      outlineVariant: const Color(0xFF2E3D5B),
      onSurfaceVariant: const Color(0xFF94A3B8), // Slate 400
    );
  }

  /// Light ThemeData
  static ThemeData get lightTheme {
    final scheme = lightColorScheme;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.5),
      textTheme: _buildTextTheme(Brightness.light, scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface.withValues(alpha: 0.85),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: displayFont(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        textStyle: bodyFont(fontSize: 12, color: scheme.surface),
      ),
    );
  }

  /// Dark ThemeData
  static ThemeData get darkTheme {
    final scheme = darkColorScheme;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.5),
      textTheme: _buildTextTheme(Brightness.dark, scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface.withValues(alpha: 0.85),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: displayFont(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        textStyle: bodyFont(fontSize: 12, color: scheme.surface),
      ),
    );
  }

  static TextTheme _buildTextTheme(Brightness brightness, ColorScheme scheme) {
    return TextTheme(
      headlineLarge: displayFont(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: scheme.onSurface,
        letterSpacing: -0.5,
      ),
      headlineMedium: displayFont(
        fontSize: 26,
        fontWeight: FontWeight.bold,
        color: scheme.onSurface,
        letterSpacing: -0.3,
      ),
      headlineSmall: displayFont(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleLarge: displayFont(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleMedium: bodyFont(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleSmall: bodyFont(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      bodyLarge: bodyFont(
        fontSize: 15,
        color: scheme.onSurface,
        height: 1.5,
      ),
      bodyMedium: bodyFont(
        fontSize: 13,
        color: scheme.onSurface,
        height: 1.5,
      ),
      bodySmall: bodyFont(
        fontSize: 11,
        color: scheme.onSurfaceVariant,
        height: 1.4,
      ),
      labelLarge: bodyFont(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
