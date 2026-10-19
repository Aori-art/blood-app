import 'package:flutter/material.dart';

/// The one palette of the app. It is the newsfeed's palette: every screen takes
/// its backgrounds, headers, buttons, cards, icons, borders and text from here
/// (directly, or through the aliases in shared_design.dart).
class AppColors {
  AppColors._();

  // ── Brand ─────────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFFC41E3A);
  static const Color primaryDark = Color(0xFF8B0000);

  /// Filled buttons and headers: begin top-left, end bottom-right.
  static const List<Color> primaryGradient = [primary, primaryDark];

  /// Pale red surfaces: icon circles, tinted banners, selected backgrounds.
  static const Color accentBg = Color(0xFFFDF0F1);

  /// A border for those pale red surfaces: [primary] at 20 % opacity (the same
  /// colour as `primary.withValues(alpha: 0.2)`, but usable in const code).
  static const Color primaryBorder = Color(0x33C41E3A);

  // ── Text and icons ON a red surface ───────────────────────────────────────
  // Anything drawn over primary / primaryDark / primaryGradient (headers, CTA
  // cards, filled buttons, splash, login, PIN...) takes one of these, never a
  // red or a pale-red tint. Pale-red text on a red surface is invisible.

  /// Titles, icons and button labels on red.
  static const Color onPrimary = Colors.white;

  /// Secondary text and icons on red: white at 70 %.
  static const Color onPrimaryMuted = Color(0xB3FFFFFF);

  /// Helper lines on red (the newsfeed welcome card subtitle): pale pink.
  static const Color onPrimarySoft = Color(0xFFFECACA);

  // ── Neutrals ──────────────────────────────────────────────────────────────
  static const Color foreground = Color(0xFF1A1A1A);
  static const Color muted = Color(0xFF6B6B6B);
  static const Color mutedBg = Color(0xFFF2F2F2);
  static const Color border = Color(0xFFE5E5E5);

  /// Hints, placeholders and disabled content.
  static const Color hint = Color(0xFF9CA3AF);

  // ── Status colors (what the newsfeed already uses) ────────────────────────
  /// Critical / urgent / rejected status badges, chips and dots only. Errors
  /// and destructive actions use [primary].
  static const Color critical = Color(0xFFDC2626);

  static const Color success = Color(0xFF16A34A);
  static const Color successBg = Color(0xFFF0FDF4);
  static const Color successBorder = Color(0xFFBBF7D0);
  static const Color successSoft = Color(0xFFDCFCE7);
  static const Color successDark = Color(0xFF15803D);

  static const Color warning = Color(0xFFD97706);
  static const Color warningBg = Color(0xFFFFFBEB);
  static const Color warningBorder = Color(0xFFFDE68A);
  static const Color warningDark = Color(0xFFB45309);

  static const Color info = Color(0xFF2563EB);
  static const Color infoBg = Color(0xFFEFF6FF);
  static const Color infoBorder = Color(0xFFBFDBFE);
  static const Color infoDark = Color(0xFF1D4ED8);

  /// "Urgent" (second level after critical).
  static const Color orange = Color(0xFFF97316);
  static const Color orangeBg = Color(0xFFFFF7ED);
  static const Color orangeBorder = Color(0xFFFED7AA);

  // ── Cards ─────────────────────────────────────────────────────────────────
  /// The shadow under every card: black at 4 %, blur 6, offset (0, 2) (the
  /// newsfeed's PostCard).
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2)),
  ];
}

/// WCAG 2.x contrast ratio between two colors, from 1 (identical) to 21 (black
/// on white). A translucent [a] is first composited over [b], so
/// `contrastRatio(onPrimaryMuted, primary)` is what the eye actually sees.
///
/// Targets: 4.5 for normal text, 3 for large text (18 pt, or 14 pt bold) and
/// icons.
double contrastRatio(Color a, Color b) {
  final top = Color.alphaBlend(a, b);
  final la = top.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
