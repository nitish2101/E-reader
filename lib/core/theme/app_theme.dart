import 'package:flutter/material.dart';

/// Paper & Ink: a quiet charcoal canvas with olive accents.
class AppTheme {
  static const canvas = Color(0xFF1F231D);
  static const panel = Color(0xFF282D25);
  static const ink = Color(0xFFEEECE5);
  static const muted = Color(0xFFB9C1B1);
  static const accent = Color(0xFFAAB895);
  static const outline = Color(0xFF7B8575);
  static const divider = Color(0xFF444B3F);
  static const placeholder = Color(0xFF343B30);

  static ThemeData get darkTheme {
    final colors =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          primary: accent,
          onPrimary: canvas,
          primaryContainer: placeholder,
          onPrimaryContainer: ink,
          secondary: accent,
          onSecondary: canvas,
          surface: canvas,
          onSurface: ink,
          onSurfaceVariant: muted,
          outline: outline,
          outlineVariant: divider,
          error: const Color(0xFFF3B4AB),
        ).copyWith(
          surfaceContainerLowest: canvas,
          surfaceContainerLow: panel,
          surfaceContainer: panel,
          surfaceContainerHigh: placeholder,
          surfaceContainerHighest: placeholder,
        );
    final base = ThemeData(useMaterial3: true, colorScheme: colors);
    final text = base.textTheme.apply(bodyColor: ink, displayColor: ink);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    return base.copyWith(
      scaffoldBackgroundColor: canvas,
      textTheme: text.copyWith(
        headlineLarge: const TextStyle(
          fontFamily: 'Newsreader',
          fontSize: 36,
          height: 1.15,
          color: ink,
        ),
        headlineMedium: const TextStyle(
          fontFamily: 'Newsreader',
          fontSize: 32,
          height: 1.2,
          color: ink,
        ),
        titleLarge: const TextStyle(
          fontFamily: 'Newsreader',
          fontSize: 24,
          height: 1.25,
          color: ink,
        ),
        titleMedium: text.titleMedium?.copyWith(fontSize: 16, height: 1.4),
        bodyLarge: text.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 14, height: 1.45),
        bodySmall: text.bodySmall?.copyWith(
          fontSize: 12,
          height: 1.4,
          color: muted,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      dividerTheme: const DividerThemeData(color: divider, thickness: 1),
      iconTheme: const IconThemeData(color: muted, size: 24),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.all(12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: ink,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: const BorderSide(color: outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        hintStyle: const TextStyle(color: muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: accent, width: 2),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: canvas,
        selectedColor: accent,
        labelStyle: const TextStyle(color: ink, fontSize: 14),
        checkmarkColor: canvas,
        side: const BorderSide(color: outline),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: canvas,
        indicatorColor: placeholder,
        selectedIconTheme: IconThemeData(color: accent),
        unselectedIconTheme: IconThemeData(color: muted),
        selectedLabelTextStyle: TextStyle(color: ink, fontSize: 12),
        unselectedLabelTextStyle: TextStyle(color: muted, fontSize: 12),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: canvas,
        indicatorColor: placeholder,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        constraints: BoxConstraints(maxWidth: 640),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: accent,
        inactiveTrackColor: divider,
        thumbColor: accent,
        trackHeight: 4,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: divider,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: placeholder,
        contentTextStyle: TextStyle(color: ink, fontSize: 14),
        actionTextColor: accent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
