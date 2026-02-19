import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'palette.dart';

class AppTheme {
  static ThemeData light({required AccentPalette palette}) {
    AppPalette.applyPalette(palette);
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = _systemTextTheme(
      base.textTheme,
    ).apply(bodyColor: AppPalette.ink, displayColor: AppPalette.ink);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppPalette.primary,
      primary: AppPalette.primary,
      secondary: AppPalette.secondary,
      tertiary: AppPalette.accent,
      surface: AppPalette.surface,
      error: AppPalette.danger,
      brightness: Brightness.light,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppPalette.mist,
      textTheme: textTheme.copyWith(
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.3),
      ),
      cardTheme: CardThemeData(
        color: AppPalette.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppPalette.outline.withValues(alpha: 0.6)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppPalette.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppPalette.outline.withValues(alpha: 0.6),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppPalette.outline.withValues(alpha: 0.6),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppPalette.primary, width: 1.6),
        ),
      ),
      dividerColor: AppPalette.outline.withValues(alpha: 0.6),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppPalette.inkSoft.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: textTheme.labelMedium?.copyWith(color: Colors.white),
      ),
    );
  }

  static ThemeData dark({required AccentPalette palette}) {
    AppPalette.applyPalette(palette);
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = _systemTextTheme(base.textTheme).apply(
      bodyColor: const Color(0xFFEAF0F5),
      displayColor: const Color(0xFFEAF0F5),
    );

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppPalette.primary,
      brightness: Brightness.dark,
      primary: AppPalette.primary,
      secondary: AppPalette.secondary,
      tertiary: AppPalette.accent,
      surface: const Color(0xFF111821),
      error: AppPalette.danger,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF0C121A),
      textTheme: textTheme.copyWith(
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.3),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF111821),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: const Color(0xFF2A3746).withValues(alpha: 0.7),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF141E29),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: const Color(0xFF2A3746).withValues(alpha: 0.9),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: const Color(0xFF2A3746).withValues(alpha: 0.9),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppPalette.primary, width: 1.6),
        ),
      ),
      dividerColor: const Color(0xFF2A3746).withValues(alpha: 0.8),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF18212C).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: textTheme.labelMedium?.copyWith(color: Colors.white),
      ),
    );
  }

  static TextTheme _systemTextTheme(TextTheme base) {
    final platform = defaultTargetPlatform;
    final family = switch (platform) {
      TargetPlatform.macOS => '.SF Pro Text',
      TargetPlatform.iOS => '.SF Pro Text',
      TargetPlatform.windows => 'Segoe UI',
      TargetPlatform.linux => 'Ubuntu',
      _ => null,
    };

    return base.apply(
      fontFamily: family,
      fontFamilyFallback: const [
        'SF Pro Text',
        'SF Pro Display',
        'Segoe UI',
        'Helvetica Neue',
        'Arial',
        'sans-serif',
      ],
    );
  }
}
