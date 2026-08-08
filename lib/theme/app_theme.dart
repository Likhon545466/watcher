import 'package:flutter/material.dart';
import '../providers/settings_provider.dart';

class AppTheme {
  static Color getSeedColor(AppPalette palette) {
    switch (palette) {
      case AppPalette.defaultBlue:
        return const Color(0xFF2563EB);
      case AppPalette.skyBlue:
        return const Color(0xFF0284C7);
      case AppPalette.teal:
        return const Color(0xFF0D9488);
      case AppPalette.green:
        return const Color(0xFF16A34A);
      case AppPalette.purple:
        return const Color(0xFF7C3AED);
      case AppPalette.indigo:
        return const Color(0xFF4F46E5);
      case AppPalette.rose:
        return const Color(0xFFE11D48);
      case AppPalette.amber:
        return const Color(0xFFD97706);
      case AppPalette.orange:
        return const Color(0xFFEA580C);
      case AppPalette.cyberpunk:
        return const Color(0xFF06B6D4);
      case AppPalette.midnightOled:
        return const Color(0xFF6366F1);
      case AppPalette.sunsetAurora:
        return const Color(0xFFF43F5E);
      case AppPalette.oceanAbyss:
        return const Color(0xFF0284C7);
    }
  }

  static List<Color> getPaletteDots(AppPalette palette) {
    switch (palette) {
      case AppPalette.defaultBlue:
        return const [Color(0xFF2563EB), Color(0xFF93C5FD), Color(0xFFE0E7FF)];
      case AppPalette.skyBlue:
        return const [Color(0xFF38BDF8), Color(0xFF7DD3FC), Color(0xFFBAE6FD)];
      case AppPalette.teal:
        return const [Color(0xFF14B8A6), Color(0xFF5EEAD4), Color(0xFFCCFBF1)];
      case AppPalette.green:
        return const [Color(0xFF22C55E), Color(0xFF86EFAC), Color(0xFFDCFCE7)];
      case AppPalette.purple:
        return const [Color(0xFF8B5CF6), Color(0xFFC4B5FD), Color(0xFFEDE9FE)];
      case AppPalette.indigo:
        return const [Color(0xFF6366F1), Color(0xFFA5B4FC), Color(0xFFE0E7FF)];
      case AppPalette.rose:
        return const [Color(0xFFF43F5E), Color(0xFFFDA4AF), Color(0xFFFFE4E6)];
      case AppPalette.amber:
        return const [Color(0xFFF59E0B), Color(0xFFFCD34D), Color(0xFFFEF3C7)];
      case AppPalette.orange:
        return const [Color(0xFFF97316), Color(0xFFFDBA74), Color(0xFFFFEDD5)];
      case AppPalette.cyberpunk:
        return const [Color(0xFF06B6D4), Color(0xFFEC4899), Color(0xFFA855F7)];
      case AppPalette.midnightOled:
        return const [Color(0xFF6366F1), Color(0xFF312E81), Color(0xFF1E1B4B)];
      case AppPalette.sunsetAurora:
        return const [Color(0xFFF43F5E), Color(0xFFFB923C), Color(0xFFFBBF24)];
      case AppPalette.oceanAbyss:
        return const [Color(0xFF0284C7), Color(0xFF0D9488), Color(0xFF1E3A8A)];
    }
  }

  static String getPaletteName(AppPalette palette) {
    switch (palette) {
      case AppPalette.defaultBlue:
        return 'Default Blue';
      case AppPalette.skyBlue:
        return 'Sky Blue';
      case AppPalette.teal:
        return 'Teal';
      case AppPalette.green:
        return 'Green';
      case AppPalette.purple:
        return 'Purple';
      case AppPalette.indigo:
        return 'Indigo';
      case AppPalette.rose:
        return 'Rose';
      case AppPalette.amber:
        return 'Amber';
      case AppPalette.orange:
        return 'Orange';
      case AppPalette.cyberpunk:
        return 'Cyberpunk';
      case AppPalette.midnightOled:
        return 'Midnight OLED';
      case AppPalette.sunsetAurora:
        return 'Sunset Aurora';
      case AppPalette.oceanAbyss:
        return 'Ocean Abyss';
    }
  }

  static ThemeData light({
    ColorScheme? scheme,
    AppPalette palette = AppPalette.defaultBlue,
  }) {
    final seed = getSeedColor(palette);
    final colors =
        scheme ??
        ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    return _build(colors, const Color(0xFFF8FAFC));
  }

  static ThemeData dark({
    ColorScheme? scheme,
    AppPalette palette = AppPalette.defaultBlue,
  }) {
    final seed = getSeedColor(palette);
    final colors =
        scheme ??
        ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    final isOled = palette == AppPalette.midnightOled && scheme == null;
    return _build(colors, isOled ? Colors.black : const Color(0xFF0F172A));
  }

  static ThemeData _build(ColorScheme colors, Color scaffoldBackground) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: scaffoldBackground,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: colors.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: colors.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerHighest.withOpacity(.45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        isDense: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant.withOpacity(.3),
      ),
    );
  }
}
