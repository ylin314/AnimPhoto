import 'package:flutter/material.dart';

abstract final class AppColors {
  static const blue = Color(0xFF1A73E8);
  static const blueDeep = Color(0xFF0B57D0);
  static const blueSoft = Color(0xFFDCE9FF);
  static const coral = Color(0xFFE9785D);
  static const blush = Color(0xFFFFE4DC);
  static const sage = Color(0xFF6F8876);
}

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.blue,
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xFFA8C7FA) : AppColors.blueDeep,
        onPrimary: Colors.white,
        primaryContainer: dark ? const Color(0xFF173A68) : AppColors.blueSoft,
        onPrimaryContainer: dark
            ? const Color(0xFFD6E6FF)
            : const Color(0xFF123E78),
        secondary: dark ? const Color(0xFFFFB4A3) : AppColors.coral,
        secondaryContainer: dark ? const Color(0xFF633529) : AppColors.blush,
        tertiary: dark ? const Color(0xFFADC7B2) : AppColors.sage,
        surface: dark ? const Color(0xFF111318) : const Color(0xFFF9F9FC),
        onSurface: dark ? const Color(0xFFE2E2E9) : const Color(0xFF1A1C1E),
        surfaceContainerHighest: dark
            ? const Color(0xFF33353A)
            : const Color(0xFFE3E2E6),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamilyFallback: const ['Noto Sans CJK SC', 'Microsoft YaHei'],
    textTheme: ThemeData(brightness: brightness).textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}
