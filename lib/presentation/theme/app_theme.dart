import 'package:flutter/material.dart';

import 'ui_tokens.dart';

/// Application theme configuration.
/// 
/// Provides consistent theming across the app with support for
/// light and dark modes.
class AppTheme {
  AppTheme._();
  
  // Color palette
  static const Color _primaryLight = Color(0xFF6366F1); // Indigo
  static const Color _primaryDark = Color(0xFF818CF8);
  static const Color _secondaryLight = Color(0xFF8B5CF6); // Violet
  static const Color _secondaryDark = Color(0xFFA78BFA);
  static const Color _errorLight = Color(0xFFEF4444);
  static const Color _errorDark = Color(0xFFF87171);
  static const Color _surfaceLight = Color(0xFFFAFAFA);
  static const Color _surfaceDark = Color(0xFF1E1E1E);
  static const Color _backgroundLight = Color(0xFFFFFFFF);
  static const Color _backgroundDark = Color(0xFF121212);
  
  // Chat bubble colors
  static const Color userBubbleLight = Color(0xFF6366F1);
  static const Color userBubbleDark = Color(0xFF4F46E5);
  static const Color assistantBubbleLight = Color(0xFFF3F4F6);
  static const Color assistantBubbleDark = Color(0xFF374151);

  static TextTheme _textTheme(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? ThemeData(brightness: Brightness.dark).textTheme
        : ThemeData(brightness: Brightness.light).textTheme;

    // Modern minimal typography tuned for small screens (Inter).
    return base.copyWith(
      headlineLarge: base.headlineLarge?.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1.06,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.35,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.35,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.25,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
  
  /// Light theme.
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Inter',
      textTheme: _textTheme(Brightness.light),
      colorScheme: ColorScheme.light(
        primary: _primaryLight,
        secondary: _secondaryLight,
        error: _errorLight,
        surface: _surfaceLight,
        onSurface: Colors.grey.shade900,
      ),
      scaffoldBackgroundColor: _backgroundLight,
      appBarTheme: AppBarTheme(
        backgroundColor: _backgroundLight,
        foregroundColor: Colors.grey.shade900,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade900,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardTheme(
        color: _surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: UiTokens.s16,
          vertical: UiTokens.s4,
        ),
        iconColor: Colors.grey.shade700,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiTokens.r16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: _primaryLight, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryLight,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _primaryLight,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: Colors.grey.shade700,
        ),
      ),
      chipTheme: ChipThemeData(
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade800,
        ),
        side: BorderSide(color: Colors.grey.shade200),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UiTokens.r16)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _primaryLight,
        linearTrackColor: Color(0xFFE5E7EB),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade200,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: _backgroundLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiTokens.r24),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: _backgroundLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiTokens.r20),
        ),
      ),
    );
  }
  
  /// Dark theme.
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Inter',
      textTheme: _textTheme(Brightness.dark),
      colorScheme: const ColorScheme.dark(
        primary: _primaryDark,
        secondary: _secondaryDark,
        error: _errorDark,
        surface: _surfaceDark,
        onSurface: Colors.white,
      ),
      scaffoldBackgroundColor: _backgroundDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: _backgroundDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardTheme(
        color: _surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade800),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: UiTokens.s16,
          vertical: UiTokens.s4,
        ),
        iconColor: Colors.grey.shade300,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiTokens.r16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey.shade900,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: _primaryDark, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryDark,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _primaryDark,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: Colors.grey.shade300,
        ),
      ),
      chipTheme: ChipThemeData(
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        side: BorderSide(color: Colors.grey.shade800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UiTokens.r16)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _primaryDark,
        linearTrackColor: Color(0xFF374151),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade800,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: _backgroundDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiTokens.r24),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: _backgroundDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiTokens.r20),
        ),
      ),
    );
  }
}
