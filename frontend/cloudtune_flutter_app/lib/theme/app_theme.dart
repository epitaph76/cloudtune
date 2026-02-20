import 'package:flutter/material.dart';

enum AppVisualMode { light, dark }

enum AppAccentScheme { green, blue, yellow, pink, purple, peach }

class AppPalette {
  const AppPalette({
    required this.background,
    required this.foreground,
    required this.card,
    required this.cardForeground,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.secondaryForeground,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.accentForeground,
    required this.destructive,
    required this.destructiveForeground,
    required this.border,
    required this.inputBackground,
  });

  final Color background;
  final Color foreground;
  final Color card;
  final Color cardForeground;
  final Color primary;
  final Color primaryForeground;
  final Color secondary;
  final Color secondaryForeground;
  final Color muted;
  final Color mutedForeground;
  final Color accent;
  final Color accentForeground;
  final Color destructive;
  final Color destructiveForeground;
  final Color border;
  final Color inputBackground;
}

class AppTheme {
  static const _destructive = Color(0xFFD4738F);
  static const _destructiveForeground = Color(0xFFFFFFFF);

  static AppPalette palette(AppVisualMode mode, AppAccentScheme scheme) {
    final isDark = mode == AppVisualMode.dark;

    switch (scheme) {
      case AppAccentScheme.green:
        return isDark
            ? const AppPalette(
                background: Color(0xFF0F1A15),
                foreground: Color(0xFFE8F1EC),
                card: Color(0xFF1A2620),
                cardForeground: Color(0xFFE8F1EC),
                primary: Color(0xFF7CB899),
                primaryForeground: Color(0xFF0F1A15),
                secondary: Color(0xFF2A3930),
                secondaryForeground: Color(0xFFE8F1EC),
                muted: Color(0xFF2A3930),
                mutedForeground: Color(0xFFA8C4B5),
                accent: Color(0xFF3A4A40),
                accentForeground: Color(0xFFE8F1EC),
                destructive: _destructive,
                destructiveForeground: _destructiveForeground,
                border: Color(0x337CB899),
                inputBackground: Color(0xFF2A3930),
              )
            : const AppPalette(
                background: Color(0xFFF4F8F5),
                foreground: Color(0xFF1A3A2E),
                card: Color(0xFFFFFFFF),
                cardForeground: Color(0xFF1A3A2E),
                primary: Color(0xFF7CB899),
                primaryForeground: Color(0xFFFFFFFF),
                secondary: Color(0xFFD4E8DD),
                secondaryForeground: Color(0xFF1A3A2E),
                muted: Color(0xFFE8F1EC),
                mutedForeground: Color(0xFF5A7266),
                accent: Color(0xFFB4D8C5),
                accentForeground: Color(0xFF1A3A2E),
                destructive: _destructive,
                destructiveForeground: _destructiveForeground,
                border: Color(0x337CB899),
                inputBackground: Color(0xFFE8F1EC),
              );
      case AppAccentScheme.blue:
        return isDark
            ? const AppPalette(
                background: Color(0xFF0F1A20),
                foreground: Color(0xFFE8F2F8),
                card: Color(0xFF1A2630),
                cardForeground: Color(0xFFE8F2F8),
                primary: Color(0xFF7CB8D8),
                primaryForeground: Color(0xFF0F1A20),
                secondary: Color(0xFF2A3945),
                secondaryForeground: Color(0xFFE8F2F8),
                muted: Color(0xFF2A3945),
                mutedForeground: Color(0xFFA8C4D8),
                accent: Color(0xFF3A4A58),
                accentForeground: Color(0xFFE8F2F8),
                destructive: _destructive,
                destructiveForeground: _destructiveForeground,
                border: Color(0x337CB8D8),
                inputBackground: Color(0xFF2A3945),
              )
            : const AppPalette(
                background: Color(0xFFF0F7FC),
                foreground: Color(0xFF1A3850),
                card: Color(0xFFFFFFFF),
                cardForeground: Color(0xFF1A3850),
                primary: Color(0xFF7CB8D8),
                primaryForeground: Color(0xFFFFFFFF),
                secondary: Color(0xFFD4E5F0),
                secondaryForeground: Color(0xFF1A3850),
                muted: Color(0xFFE8F2F8),
                mutedForeground: Color(0xFF5A7088),
                accent: Color(0xFFB4D5E8),
                accentForeground: Color(0xFF1A3850),
                destructive: _destructive,
                destructiveForeground: _destructiveForeground,
                border: Color(0x337CB8D8),
                inputBackground: Color(0xFFE8F2F8),
              );
      case AppAccentScheme.yellow:
        return isDark
            ? const AppPalette(
                background: Color(0xFF1A1810),
                foreground: Color(0xFFF9F3E8),
                card: Color(0xFF26201A),
                cardForeground: Color(0xFFF9F3E8),
                primary: Color(0xFFD8B87C),
                primaryForeground: Color(0xFF1A1810),
                secondary: Color(0xFF3A342A),
                secondaryForeground: Color(0xFFF9F3E8),
                muted: Color(0xFF3A342A),
                mutedForeground: Color(0xFFC4B498),
                accent: Color(0xFF4A443A),
                accentForeground: Color(0xFFF9F3E8),
                destructive: _destructive,
                destructiveForeground: _destructiveForeground,
                border: Color(0x33D8B87C),
                inputBackground: Color(0xFF3A342A),
              )
            : const AppPalette(
                background: Color(0xFFFCF9F0),
                foreground: Color(0xFF4A4020),
                card: Color(0xFFFFFFFF),
                cardForeground: Color(0xFF4A4020),
                primary: Color(0xFFD8B87C),
                primaryForeground: Color(0xFFFFFFFF),
                secondary: Color(0xFFF5ECD4),
                secondaryForeground: Color(0xFF4A4020),
                muted: Color(0xFFF9F3E8),
                mutedForeground: Color(0xFF7A6A50),
                accent: Color(0xFFE8D8B4),
                accentForeground: Color(0xFF4A4020),
                destructive: _destructive,
                destructiveForeground: _destructiveForeground,
                border: Color(0x33D8B87C),
                inputBackground: Color(0xFFF9F3E8),
              );
      case AppAccentScheme.pink:
        return isDark
            ? const AppPalette(
                background: Color(0xFF1A0F15),
                foreground: Color(0xFFF9E8F1),
                card: Color(0xFF261A20),
                cardForeground: Color(0xFFF9E8F1),
                primary: Color(0xFFD88CB8),
                primaryForeground: Color(0xFF1A0F15),
                secondary: Color(0xFF3A2A35),
                secondaryForeground: Color(0xFFF9E8F1),
                muted: Color(0xFF3A2A35),
                mutedForeground: Color(0xFFC4A8B8),
                accent: Color(0xFF4A3A45),
                accentForeground: Color(0xFFF9E8F1),
                destructive: _destructive,
                destructiveForeground: _destructiveForeground,
                border: Color(0x33D88CB8),
                inputBackground: Color(0xFF3A2A35),
              )
            : const AppPalette(
                background: Color(0xFFFCF0F5),
                foreground: Color(0xFF4A1A30),
                card: Color(0xFFFFFFFF),
                cardForeground: Color(0xFF4A1A30),
                primary: Color(0xFFD88CB8),
                primaryForeground: Color(0xFFFFFFFF),
                secondary: Color(0xFFF5D4E8),
                secondaryForeground: Color(0xFF4A1A30),
                muted: Color(0xFFF9E8F1),
                mutedForeground: Color(0xFF7A5A70),
                accent: Color(0xFFE8B4D8),
                accentForeground: Color(0xFF4A1A30),
                destructive: _destructive,
                destructiveForeground: _destructiveForeground,
                border: Color(0x33D88CB8),
                inputBackground: Color(0xFFF9E8F1),
              );
      case AppAccentScheme.purple:
        return isDark
            ? const AppPalette(
                background: Color(0xFF150F1A),
                foreground: Color(0xFFEBE8F9),
                card: Color(0xFF201A26),
                cardForeground: Color(0xFFEBE8F9),
                primary: Color(0xFFA88CD8),
                primaryForeground: Color(0xFF150F1A),
                secondary: Color(0xFF352A3A),
                secondaryForeground: Color(0xFFEBE8F9),
                muted: Color(0xFF352A3A),
                mutedForeground: Color(0xFFB8A8C4),
                accent: Color(0xFF453A4A),
                accentForeground: Color(0xFFEBE8F9),
                destructive: _destructive,
                destructiveForeground: _destructiveForeground,
                border: Color(0x33A88CD8),
                inputBackground: Color(0xFF352A3A),
              )
            : const AppPalette(
                background: Color(0xFFF5F0FC),
                foreground: Color(0xFF2A1A4A),
                card: Color(0xFFFFFFFF),
                cardForeground: Color(0xFF2A1A4A),
                primary: Color(0xFFA88CD8),
                primaryForeground: Color(0xFFFFFFFF),
                secondary: Color(0xFFDDD4F5),
                secondaryForeground: Color(0xFF2A1A4A),
                muted: Color(0xFFEBE8F9),
                mutedForeground: Color(0xFF655A7A),
                accent: Color(0xFFC8B4E8),
                accentForeground: Color(0xFF2A1A4A),
                destructive: _destructive,
                destructiveForeground: _destructiveForeground,
                border: Color(0x33A88CD8),
                inputBackground: Color(0xFFEBE8F9),
              );
      case AppAccentScheme.peach:
        return isDark
            ? const AppPalette(
                background: Color(0xFF1A150F),
                foreground: Color(0xFFF9EBE8),
                card: Color(0xFF26201A),
                cardForeground: Color(0xFFF9EBE8),
                primary: Color(0xFFD8A88C),
                primaryForeground: Color(0xFF1A150F),
                secondary: Color(0xFF3A352A),
                secondaryForeground: Color(0xFFF9EBE8),
                muted: Color(0xFF3A352A),
                mutedForeground: Color(0xFFC4B8A8),
                accent: Color(0xFF4A453A),
                accentForeground: Color(0xFFF9EBE8),
                destructive: _destructive,
                destructiveForeground: _destructiveForeground,
                border: Color(0x33D8A88C),
                inputBackground: Color(0xFF3A352A),
              )
            : const AppPalette(
                background: Color(0xFFFCF5F0),
                foreground: Color(0xFF4A2A1A),
                card: Color(0xFFFFFFFF),
                cardForeground: Color(0xFF4A2A1A),
                primary: Color(0xFFD8A88C),
                primaryForeground: Color(0xFFFFFFFF),
                secondary: Color(0xFFF5DDD4),
                secondaryForeground: Color(0xFF4A2A1A),
                muted: Color(0xFFF9EBE8),
                mutedForeground: Color(0xFF7A655A),
                accent: Color(0xFFE8C8B4),
                accentForeground: Color(0xFF4A2A1A),
                destructive: _destructive,
                destructiveForeground: _destructiveForeground,
                border: Color(0x33D8A88C),
                inputBackground: Color(0xFFF9EBE8),
              );
    }
  }

  static ThemeData buildTheme({
    required AppPalette palette,
    required Brightness brightness,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: palette.primary,
      onPrimary: palette.primaryForeground,
      secondary: palette.secondary,
      onSecondary: palette.secondaryForeground,
      tertiary: palette.accent,
      onTertiary: palette.accentForeground,
      error: palette.destructive,
      onError: palette.destructiveForeground,
      surface: palette.card,
      onSurface: palette.foreground,
      outline: palette.border,
      shadow: Colors.black.withValues(alpha: 0.12),
      inverseSurface: palette.foreground,
      onInverseSurface: palette.background,
      inversePrimary: palette.primary,
      surfaceTint: Colors.transparent,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.background,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: palette.foreground,
        displayColor: palette.foreground,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        foregroundColor: palette.foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: palette.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: palette.border),
        ),
      ),
      dividerColor: palette.border,
      iconTheme: IconThemeData(color: palette.foreground),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.inputBackground,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.primary, width: 1.5),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.foreground,
        contentTextStyle: TextStyle(color: palette.background),
        behavior: SnackBarBehavior.floating,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.primary,
        inactiveTrackColor: palette.muted,
        thumbColor: palette.primary,
        overlayColor: palette.primary.withValues(alpha: 0.16),
      ),
    );
  }
}
