import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_palette.dart';

/// The two themes of the app. Anything a screen doesn't style by hand
/// (pickers, dialogs, switches, snackbars, progress bars...) follows the
/// palette of the current mode.
class AppTheme {
  AppTheme._();

  static final ThemeData light = _build(AppPalette.light);
  static final ThemeData dark = _build(AppPalette.dark);

  static ThemeData _build(AppPalette p) {
    final brightness = p.isDark ? Brightness.dark : Brightness.light;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
        ).copyWith(
          // In dark the scheme's primary is the readable red, so text
          // buttons, pickers and selections read well. Filled buttons set
          // AppColors.primary themselves.
          primary: p.primaryText,
          onPrimary: p.isDark ? Colors.black : Colors.white,
          secondary: AppColors.primaryDark,
          onSecondary: Colors.white,
          surface: p.surface,
          onSurface: p.isDark ? p.foreground : null,
          // Dark only (light keeps the generated values): menus, pickers and
          // other Material surfaces follow the palette instead of a red tint.
          onSurfaceVariant: p.isDark ? p.muted : null,
          outline: p.isDark ? p.hint : null,
          outlineVariant: p.isDark ? p.border : null,
          surfaceContainerLowest: p.isDark ? p.background : null,
          surfaceContainerLow: p.isDark ? p.surface : null,
          surfaceContainer: p.isDark ? p.surface : null,
          surfaceContainerHigh: p.isDark ? p.surfaceAlt : null,
          surfaceContainerHighest: p.isDark ? p.surfaceAlt : null,
          error: p.primaryText,
          onError: p.isDark ? Colors.black : Colors.white,
        );

    const buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    );

    // Selected = brand red; everything else keeps the neutral look.
    WidgetStateProperty<Color?> selectedPrimary(Color? unselected) =>
        WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : unselected,
        );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: p.border),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: p.primaryText, width: 1.5),
    );
    final errorBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: p.primaryText),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.surface,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      dividerColor: p.border,
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.primaryText,
          side: BorderSide(color: p.primaryText),
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.primaryText),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primaryText,
        linearTrackColor: p.border,
        circularTrackColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Colors.white : p.hint,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : p.border,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : p.border,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: selectedPrimary(null),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: BorderSide(color: p.hint, width: 1.5),
      ),
      radioTheme: RadioThemeData(fillColor: selectedPrimary(p.hint)),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.primaryText,
        selectionColor: p.primaryText.withValues(alpha: 0.25),
        selectionHandleColor: p.primaryText,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: focusedBorder,
        errorBorder: errorBorder,
        focusedErrorBorder: focusedBorder.copyWith(
          borderSide: BorderSide(color: p.primaryText, width: 1.5),
        ),
        errorStyle: TextStyle(color: p.primaryText),
        hintStyle: TextStyle(color: p.muted),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppColors.primary,
        headerForegroundColor: Colors.white,
        confirmButtonStyle: TextButton.styleFrom(
          foregroundColor: p.primaryText,
        ),
        cancelButtonStyle: TextButton.styleFrom(foregroundColor: p.primaryText),
        todayForegroundColor: WidgetStateProperty.all(p.primaryText),
        todayBorder: BorderSide(color: p.primaryText),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? AppColors.primary : null,
        ),
        yearBackgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? AppColors.primary : null,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: p.surface,
        dialBackgroundColor: p.background,
        dialHandColor: AppColors.primary,
        hourMinuteColor: WidgetStateColor.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? p.accentBg : p.background,
        ),
        hourMinuteTextColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? p.primaryText
              : p.foreground,
        ),
        dayPeriodColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : p.surface,
        ),
        dayPeriodTextColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : p.foreground,
        ),
        entryModeIconColor: p.primaryText,
        confirmButtonStyle: TextButton.styleFrom(
          foregroundColor: p.primaryText,
        ),
        cancelButtonStyle: TextButton.styleFrom(foregroundColor: p.primaryText),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
      extensions: [p],
    );
  }
}

/// The light theme (kept for callers and tests that want "the" theme).
ThemeData buildAppTheme() => AppTheme.light;
