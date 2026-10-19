import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Every color that depends on the mode (light / dark).
///
/// Read it with `context.palette`: it goes through the [Theme], so any widget
/// that uses it rebuilds when the mode changes. Colors that are the same in
/// both modes stay in [AppColors]: the brand fills ([AppColors.primary],
/// [AppColors.primaryDark], the gradients), `onPrimary*`, the critical badge
/// fill, and all Dugtong / frame / streak artwork.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final bool isDark;

  // Surfaces
  final Color background; // screen background
  final Color surface; // cards, sheets, dialogs, nav bar
  final Color surfaceAlt; // input fills, chips, skeletons
  final Color border;

  // Text
  final Color foreground;
  final Color muted;
  final Color hint;

  /// The brand red when it is TEXT, an ICON or an OUTLINE on a surface.
  final Color primaryText;
  final Color accentBg;
  final Color primaryBorder;

  /// Critical / urgent as text (badge fills stay [AppColors.critical]).
  final Color criticalText;

  // Status families
  final Color success, successBg, successBorder, successSoft, successDark;
  final Color warning, warningBg, warningBorder, warningText;
  final Color info, infoBg, infoBorder, infoText;
  final Color orange, orangeBg, orangeBorder;

  // Category accents (purple eligibility / privacy, pink donations).
  final Color purple, purpleBg, purpleBorder, pink, pinkBg;

  /// Decorative icons that are meant to be quiet (chevrons, empty-state
  /// illustrations, unselected radio marks): the hairline [border] in light,
  /// a gray that still reaches 3:1 in dark.
  final Color faint;

  /// The shadow under cards; none in dark, where the 1 px border does the job.
  final List<BoxShadow> shadow;

  const AppPalette({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.foreground,
    required this.muted,
    required this.hint,
    required this.primaryText,
    required this.accentBg,
    required this.primaryBorder,
    required this.criticalText,
    required this.success,
    required this.successBg,
    required this.successBorder,
    required this.successSoft,
    required this.successDark,
    required this.warning,
    required this.warningBg,
    required this.warningBorder,
    required this.warningText,
    required this.info,
    required this.infoBg,
    required this.infoBorder,
    required this.infoText,
    required this.orange,
    required this.orangeBg,
    required this.orangeBorder,
    required this.purple,
    required this.purpleBg,
    required this.purpleBorder,
    required this.pink,
    required this.pinkBg,
    required this.faint,
    required this.shadow,
  });

  /// EXACTLY the values the app has always used.
  static const AppPalette light = AppPalette(
    isDark: false,
    background: AppColors.mutedBg,
    surface: Colors.white,
    surfaceAlt: AppColors.mutedBg,
    border: AppColors.border,
    foreground: AppColors.foreground,
    muted: AppColors.muted,
    hint: AppColors.hint,
    primaryText: AppColors.primary,
    accentBg: AppColors.accentBg,
    primaryBorder: AppColors.primaryBorder,
    criticalText: AppColors.critical,
    success: AppColors.success,
    successBg: AppColors.successBg,
    successBorder: AppColors.successBorder,
    successSoft: AppColors.successSoft,
    successDark: AppColors.successDark,
    warning: AppColors.warning,
    warningBg: AppColors.warningBg,
    warningBorder: AppColors.warningBorder,
    warningText: AppColors.warningDark,
    info: AppColors.info,
    infoBg: AppColors.infoBg,
    infoBorder: AppColors.infoBorder,
    infoText: AppColors.infoDark,
    orange: AppColors.orange,
    orangeBg: AppColors.orangeBg,
    orangeBorder: AppColors.orangeBorder,
    purple: Color(0xFF9333EA),
    purpleBg: Color(0xFFFAF5FF),
    purpleBorder: Color(0xFFE9D5FF),
    pink: Color(0xFFEC4899),
    pinkBg: Color(0xFFFDF2F8),
    faint: AppColors.border,
    shadow: AppColors.cardShadow,
  );

  static const AppPalette dark = AppPalette(
    isDark: true,
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    surfaceAlt: Color(0xFF2A2A2A),
    border: Color(0xFF333333),
    foreground: Color(0xFFF2F2F2),
    muted: Color(0xFFB0B0B0),
    hint: Color(0xFF9A9A9A),
    primaryText: Color(0xFFFF6B81),
    accentBg: Color(0xFF2B171B),
    primaryBorder: Color(0xFF5C2A33),
    criticalText: Color(0xFFF87171),
    success: Color(0xFF4ADE80),
    successBg: Color(0xFF12261A),
    successBorder: Color(0xFF1F4A2E),
    successSoft: Color(0xFF173A24),
    successDark: Color(0xFF86EFAC),
    warning: Color(0xFFFBBF24),
    warningBg: Color(0xFF2A2110),
    warningBorder: Color(0xFF5A4514),
    warningText: Color(0xFFFCD34D),
    info: Color(0xFF60A5FA),
    infoBg: Color(0xFF0F2036),
    infoBorder: Color(0xFF1E3A5F),
    infoText: Color(0xFF93C5FD),
    orange: Color(0xFFFB923C),
    orangeBg: Color(0xFF2A1A0F),
    orangeBorder: Color(0xFF5A3514),
    purple: Color(0xFFC084FC),
    purpleBg: Color(0xFF231530),
    purpleBorder: Color(0xFF4A2A6B),
    pink: Color(0xFFF472B6),
    pinkBg: Color(0xFF2A1521),
    faint: Color(0xFF6B6B6B),
    shadow: <BoxShadow>[],
  );

  @override
  AppPalette copyWith({
    bool? isDark,
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? foreground,
    Color? muted,
    Color? hint,
    Color? primaryText,
    Color? accentBg,
    Color? primaryBorder,
    Color? criticalText,
    Color? success,
    Color? successBg,
    Color? successBorder,
    Color? successSoft,
    Color? successDark,
    Color? warning,
    Color? warningBg,
    Color? warningBorder,
    Color? warningText,
    Color? info,
    Color? infoBg,
    Color? infoBorder,
    Color? infoText,
    Color? orange,
    Color? orangeBg,
    Color? orangeBorder,
    Color? purple,
    Color? purpleBg,
    Color? purpleBorder,
    Color? pink,
    Color? pinkBg,
    Color? faint,
    List<BoxShadow>? shadow,
  }) => AppPalette(
    isDark: isDark ?? this.isDark,
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceAlt: surfaceAlt ?? this.surfaceAlt,
    border: border ?? this.border,
    foreground: foreground ?? this.foreground,
    muted: muted ?? this.muted,
    hint: hint ?? this.hint,
    primaryText: primaryText ?? this.primaryText,
    accentBg: accentBg ?? this.accentBg,
    primaryBorder: primaryBorder ?? this.primaryBorder,
    criticalText: criticalText ?? this.criticalText,
    success: success ?? this.success,
    successBg: successBg ?? this.successBg,
    successBorder: successBorder ?? this.successBorder,
    successSoft: successSoft ?? this.successSoft,
    successDark: successDark ?? this.successDark,
    warning: warning ?? this.warning,
    warningBg: warningBg ?? this.warningBg,
    warningBorder: warningBorder ?? this.warningBorder,
    warningText: warningText ?? this.warningText,
    info: info ?? this.info,
    infoBg: infoBg ?? this.infoBg,
    infoBorder: infoBorder ?? this.infoBorder,
    infoText: infoText ?? this.infoText,
    orange: orange ?? this.orange,
    orangeBg: orangeBg ?? this.orangeBg,
    orangeBorder: orangeBorder ?? this.orangeBorder,
    purple: purple ?? this.purple,
    purpleBg: purpleBg ?? this.purpleBg,
    purpleBorder: purpleBorder ?? this.purpleBorder,
    pink: pink ?? this.pink,
    pinkBg: pinkBg ?? this.pinkBg,
    faint: faint ?? this.faint,
    shadow: shadow ?? this.shadow,
  );

  /// Lerps EVERY color, so the switch between modes animates.
  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      isDark: t < 0.5 ? isDark : other.isDark,
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceAlt: c(surfaceAlt, other.surfaceAlt),
      border: c(border, other.border),
      foreground: c(foreground, other.foreground),
      muted: c(muted, other.muted),
      hint: c(hint, other.hint),
      primaryText: c(primaryText, other.primaryText),
      accentBg: c(accentBg, other.accentBg),
      primaryBorder: c(primaryBorder, other.primaryBorder),
      criticalText: c(criticalText, other.criticalText),
      success: c(success, other.success),
      successBg: c(successBg, other.successBg),
      successBorder: c(successBorder, other.successBorder),
      successSoft: c(successSoft, other.successSoft),
      successDark: c(successDark, other.successDark),
      warning: c(warning, other.warning),
      warningBg: c(warningBg, other.warningBg),
      warningBorder: c(warningBorder, other.warningBorder),
      warningText: c(warningText, other.warningText),
      info: c(info, other.info),
      infoBg: c(infoBg, other.infoBg),
      infoBorder: c(infoBorder, other.infoBorder),
      infoText: c(infoText, other.infoText),
      orange: c(orange, other.orange),
      orangeBg: c(orangeBg, other.orangeBg),
      orangeBorder: c(orangeBorder, other.orangeBorder),
      purple: c(purple, other.purple),
      purpleBg: c(purpleBg, other.purpleBg),
      purpleBorder: c(purpleBorder, other.purpleBorder),
      pink: c(pink, other.pink),
      pinkBg: c(pinkBg, other.pinkBg),
      faint: c(faint, other.faint),
      shadow: BoxShadow.lerpList(shadow, other.shadow, t) ?? const [],
    );
  }
}

extension AppPaletteX on BuildContext {
  /// The palette of the current mode. Going through the [Theme] is what makes
  /// a widget rebuild when the mode changes.
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
