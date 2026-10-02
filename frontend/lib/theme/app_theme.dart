import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central design system tokens and theme for Multi Agent Research Assistant.
/// Source of truth: reference prototype.
///
/// Light tokens:
///   --bg:    #F2F4F0 (scaffold background)
///   --sf:    #FFFFFF (surfaces, cards, search input, blockquote)
///   --ink:   #0D1210 (primary text, titles, headings)
///   --mute:  #566159 (secondary text, labels, timestamps)
///   --line:  #D9DED7 (1px border lines everywhere)
///   --acc:   #14301F (primary button bg, active segmented pill, logo bg)
///   --onacc: #EAF8C0 (primary button text, logo ring)
///   --at:    #14301F (accent links, active indicators, focus border)
///   --ok:    #0F6B3A (corroborated badge / tally count)
///   --warn:  #8A5A00 (single source badge / tally count)
///   --bad:   #A63A1E (unsupported badge / tally count)
///   --sh:    0 12px 32px -16px rgba(13,18,16,.25) (dialogs only)
///
/// Dark tokens:
///   --bg:    #0A0C0B
///   --sf:    #121614
///   --ink:   #EDF0EA
///   --mute:  #9AA59E
///   --line:  #222925
///   --acc:   #D4F03C
///   --onacc: #0A0C0B
///   --at:    #D4F03C
///   --ok:    #6FD79A
///   --warn:  #F2C14E
///   --bad:   #FF8A70
///   --sh:    0 16px 40px -18px rgba(0,0,0,.8)
///
/// Typography:
///   - Serif display: Instrument Serif (fallback: Georgia, serif)
///   - Sans body:     Geist (fallback: system sans-serif)
///   - Monospace:     Geist Mono (fallback: ui-monospace, monospace)
class AppTheme {
  // Spacing Scale
  static const double space2 = 2.0;
  static const double space4 = 4.0;
  static const double space6 = 6.0;
  static const double space8 = 8.0;
  static const double space10 = 10.0;
  static const double space12 = 12.0;
  static const double space14 = 14.0;
  static const double space16 = 16.0;
  static const double space18 = 18.0;
  static const double space20 = 20.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;
  static const double space48 = 48.0;

  // Exact radii from reference prototype
  static const double radiusSmall = 8.0; // .seg button, .logo i
  static const double radiusSeg = 10.0; // .seg
  static const double radiusMedium = 12.0; // .ib, .btn, .cl blockquote, .hi
  static const double radiusInput = 14.0; // .bar .ask
  static const double radiusLarge = 18.0; // .stats
  static const double radiusCard = 18.0; // card containers
  static const double radiusHeroInput = 20.0; // .hero .ask
  static const double radiusDialog = 24.0; // .mod > div
  static const double radiusPill = 99.0; // .bd, .eyebrow, .eg button, .mt a

  // Light Mode Tokens (:root)
  static const Color lightBg = Color(0xFFF2F4F0);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightInk = Color(0xFF0D1210);
  static const Color lightMuted = Color(0xFF566159);
  static const Color lightLines = Color(0xFFD9DED7);
  static const Color lightAcc = Color(0xFF14301F);
  static const Color lightOnAcc = Color(0xFFEAF8C0);
  static const Color lightAt = Color(0xFF14301F);
  static const Color lightOk = Color(0xFF0F6B3A);
  static const Color lightWarn = Color(0xFF8A5A00);
  static const Color lightBad = Color(0xFFA63A1E);
  static const BoxShadow lightShadow = BoxShadow(
    color: Color.fromRGBO(13, 18, 16, 0.25),
    blurRadius: 32,
    offset: Offset(0, 12),
    spreadRadius: -16,
  );

  // Dark Mode Tokens ([data-theme="dark"])
  static const Color darkBg = Color(0xFF0A0C0B);
  static const Color darkSurface = Color(0xFF121614);
  static const Color darkInk = Color(0xFFEDF0EA);
  static const Color darkMuted = Color(0xFF9AA59E);
  static const Color darkLines = Color(0xFF222925);
  static const Color darkAcc = Color(0xFFD4F03C);
  static const Color darkOnAcc = Color(0xFF0A0C0B);
  static const Color darkAt = Color(0xFFD4F03C);
  static const Color darkOk = Color(0xFF6FD79A);
  static const Color darkWarn = Color(0xFFF2C14E);
  static const Color darkBad = Color(0xFFFF8A70);
  static const BoxShadow darkShadow = BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.8),
    blurRadius: 40,
    offset: Offset(0, 16),
    spreadRadius: -18,
  );

  // Status mapping aliases
  static const Color statusSupportedLight = lightOk;
  static const Color statusSupportedDark = darkOk;
  static const Color statusSingleSourceLight = lightWarn;
  static const Color statusSingleSourceDark = darkWarn;
  static const Color statusUnsupportedLight = lightBad;
  static const Color statusUnsupportedDark = darkBad;

  // Legacy aliases for backward compatibility if referenced
  static const Color lightButtonBg = lightAcc;
  static const Color lightButtonText = lightOnAcc;
  static const Color darkButtonBg = darkAcc;
  static const Color darkButtonText = darkOnAcc;
  static const Color primarySeed = lightAcc;
  static const Color statusSupported = lightOk;
  static const Color statusSingleSource = lightWarn;
  static const Color statusUnsupported = lightBad;

  // ---------------------------------------------------------------------------
  // Typography: Instrument Serif, Geist, Geist Mono (with offline fallbacks)
  // ---------------------------------------------------------------------------

  /// Serif display font (Instrument Serif) for headings, wordmark, stats, titles
  static TextStyle displayFont({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
    TextDecoration? decoration,
  }) {
    final fallbacks = [
      GoogleFonts.notoSans().fontFamily ?? 'Noto Sans',
      GoogleFonts.notoSansDevanagari().fontFamily ?? 'Noto Sans Devanagari',
      'Georgia',
      'serif',
    ];
    try {
      return GoogleFonts.instrumentSerif(
        textStyle: (textStyle ?? const TextStyle()).copyWith(
          fontFamilyFallback: fallbacks,
        ),
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
        fontFamily: 'Georgia, serif',
        fontFamilyFallback: fallbacks,
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

  /// Sans body font (Geist) for regular UI text, search input, buttons, claims
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
    final fallbacks = [
      GoogleFonts.notoSans().fontFamily ?? 'Noto Sans',
      GoogleFonts.notoSansDevanagari().fontFamily ?? 'Noto Sans Devanagari',
      'sans-serif',
    ];
    try {
      return GoogleFonts.geist(
        textStyle: (textStyle ?? const TextStyle()).copyWith(
          fontFamilyFallback: fallbacks,
        ),
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
        fontFamilyFallback: fallbacks,
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

  /// Monospace font (Geist Mono) for badges (.bd), dates (.hg), counts, tags
  static TextStyle monoFont({
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
      return GoogleFonts.geistMono(
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
        fontFamily: 'monospace',
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

  // ---------------------------------------------------------------------------
  // ColorSchemes
  // ---------------------------------------------------------------------------

  static ColorScheme get lightColorScheme {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: lightAcc,
      onPrimary: lightOnAcc,
      primaryContainer: Color(0xFFE5EDE6),
      onPrimaryContainer: lightInk,
      secondary: lightMuted,
      onSecondary: lightSurface,
      secondaryContainer: Color(0xFFE8ECE8),
      onSecondaryContainer: lightInk,
      tertiary: lightAt,
      onTertiary: lightOnAcc,
      error: lightBad,
      onError: Colors.white,
      errorContainer: Color(0xFFFBECE9),
      onErrorContainer: lightBad,
      surface: lightSurface,
      onSurface: lightInk,
      onSurfaceVariant: lightMuted,
      outline: lightMuted,
      outlineVariant: lightLines,
      shadow: Color(0x400D1210),
      scrim: Colors.black54,
      inverseSurface: lightInk,
      onInverseSurface: lightBg,
      inversePrimary: lightOnAcc,
    );
  }

  static ColorScheme get darkColorScheme {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: darkAcc,
      onPrimary: darkOnAcc,
      primaryContainer: Color(0xFF1B231D),
      onPrimaryContainer: darkInk,
      secondary: darkMuted,
      onSecondary: darkSurface,
      secondaryContainer: Color(0xFF181F1B),
      onSecondaryContainer: darkInk,
      tertiary: darkAt,
      onTertiary: darkOnAcc,
      error: darkBad,
      onError: Colors.black,
      errorContainer: Color(0xFF3B1A14),
      onErrorContainer: darkBad,
      surface: darkSurface,
      onSurface: darkInk,
      onSurfaceVariant: darkMuted,
      outline: darkMuted,
      outlineVariant: darkLines,
      shadow: Colors.black,
      scrim: Colors.black87,
      inverseSurface: darkInk,
      onInverseSurface: darkBg,
      inversePrimary: darkOnAcc,
    );
  }

  // ---------------------------------------------------------------------------
  // ThemeData
  // ---------------------------------------------------------------------------

  static ThemeData get lightTheme {
    final scheme = lightColorScheme;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: lightBg,
      dividerColor: lightLines,
      dividerTheme: const DividerThemeData(
        color: lightLines,
        thickness: 1.0,
        space: 1.0,
      ),
      textTheme: _buildTextTheme(scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: lightBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: displayFont(
          fontSize: 22,
          fontWeight: FontWeight.normal,
          color: lightInk,
        ),
        iconTheme: const IconThemeData(color: lightInk),
        shape: const Border(
          bottom: BorderSide(color: lightLines, width: 1.0),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          side: const BorderSide(color: lightLines, width: 1.0),
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusDialog),
          side: const BorderSide(color: lightLines, width: 1.0),
        ),
        titleTextStyle: displayFont(
          fontSize: 36,
          fontWeight: FontWeight.normal,
          color: lightInk,
        ),
        contentTextStyle: bodyFont(
          fontSize: 15,
          color: lightMuted,
          height: 1.5,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return lightLines;
            }
            return lightAcc;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return lightMuted;
            }
            return lightOnAcc;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMedium),
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          ),
          textStyle: WidgetStatePropertyAll(
            bodyFont(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          foregroundColor: const WidgetStatePropertyAll(lightInk),
          backgroundColor: const WidgetStatePropertyAll(lightSurface),
          side: const WidgetStatePropertyAll(
            BorderSide(color: lightLines, width: 1.0),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusPill),
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          textStyle: WidgetStatePropertyAll(
            bodyFont(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurface,
        hintStyle: bodyFont(
          fontSize: 16,
          color: lightMuted,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: lightLines, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: lightLines, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: lightAt, width: 1.5),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: lightInk,
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        textStyle: monoFont(fontSize: 11, color: lightSurface),
      ),
    );
  }

  static ThemeData get darkTheme {
    final scheme = darkColorScheme;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: darkBg,
      dividerColor: darkLines,
      dividerTheme: const DividerThemeData(
        color: darkLines,
        thickness: 1.0,
        space: 1.0,
      ),
      textTheme: _buildTextTheme(scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: darkBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: displayFont(
          fontSize: 22,
          fontWeight: FontWeight.normal,
          color: darkInk,
        ),
        iconTheme: const IconThemeData(color: darkInk),
        shape: const Border(
          bottom: BorderSide(color: darkLines, width: 1.0),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          side: const BorderSide(color: darkLines, width: 1.0),
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusDialog),
          side: const BorderSide(color: darkLines, width: 1.0),
        ),
        titleTextStyle: displayFont(
          fontSize: 36,
          fontWeight: FontWeight.normal,
          color: darkInk,
        ),
        contentTextStyle: bodyFont(
          fontSize: 15,
          color: darkMuted,
          height: 1.5,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return darkLines;
            }
            return darkAcc;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return darkMuted;
            }
            return darkOnAcc;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMedium),
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          ),
          textStyle: WidgetStatePropertyAll(
            bodyFont(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          foregroundColor: const WidgetStatePropertyAll(darkInk),
          backgroundColor: const WidgetStatePropertyAll(darkSurface),
          side: const WidgetStatePropertyAll(
            BorderSide(color: darkLines, width: 1.0),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusPill),
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          textStyle: WidgetStatePropertyAll(
            bodyFont(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        hintStyle: bodyFont(
          fontSize: 16,
          color: darkMuted,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: darkLines, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: darkLines, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: darkAt, width: 1.5),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: darkInk,
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        textStyle: monoFont(fontSize: 11, color: darkSurface),
      ),
    );
  }

  static TextTheme _buildTextTheme(ColorScheme scheme) {
    return TextTheme(
      displayLarge: displayFont(
        fontSize: 58,
        color: scheme.onSurface,
        height: 1.0,
      ),
      displayMedium: displayFont(
        fontSize: 44,
        color: scheme.onSurface,
        height: 1.0,
      ),
      displaySmall: displayFont(
        fontSize: 36,
        color: scheme.onSurface,
        height: 1.05,
      ),
      headlineLarge: displayFont(
        fontSize: 32,
        color: scheme.onSurface,
      ),
      headlineMedium: displayFont(
        fontSize: 24,
        color: scheme.onSurface,
      ),
      headlineSmall: displayFont(
        fontSize: 20,
        color: scheme.onSurface,
      ),
      titleLarge: bodyFont(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleMedium: bodyFont(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleSmall: bodyFont(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      bodyLarge: bodyFont(
        fontSize: 16,
        color: scheme.onSurface,
        height: 1.55,
      ),
      bodyMedium: bodyFont(
        fontSize: 14,
        color: scheme.onSurface,
        height: 1.5,
      ),
      bodySmall: bodyFont(
        fontSize: 12,
        color: scheme.onSurfaceVariant,
        height: 1.45,
      ),
      labelLarge: bodyFont(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      labelMedium: monoFont(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.04,
        color: scheme.onSurface,
      ),
      labelSmall: monoFont(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.08,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
