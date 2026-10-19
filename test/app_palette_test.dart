import 'package:blood/app_colors.dart';
import 'package:blood/app_palette.dart';
import 'package:blood/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Pair = (
  String,
  Color Function(AppPalette),
  Color Function(AppPalette),
);

// Text / icon color on the surface it sits on. Every pair must reach 4.5:1.
final List<_Pair> _pairs = [
  ('foreground on background', (p) => p.foreground, (p) => p.background),
  ('foreground on surface', (p) => p.foreground, (p) => p.surface),
  ('foreground on surfaceAlt', (p) => p.foreground, (p) => p.surfaceAlt),
  ('muted on background', (p) => p.muted, (p) => p.background),
  ('muted on surface', (p) => p.muted, (p) => p.surface),
  ('muted on surfaceAlt', (p) => p.muted, (p) => p.surfaceAlt),
  ('hint on surface', (p) => p.hint, (p) => p.surface),
  ('hint on surfaceAlt', (p) => p.hint, (p) => p.surfaceAlt),
  ('primaryText on background', (p) => p.primaryText, (p) => p.background),
  ('primaryText on surface', (p) => p.primaryText, (p) => p.surface),
  ('primaryText on surfaceAlt', (p) => p.primaryText, (p) => p.surfaceAlt),
  ('primaryText on accentBg', (p) => p.primaryText, (p) => p.accentBg),
  ('criticalText on surface', (p) => p.criticalText, (p) => p.surface),
  ('success on surface', (p) => p.success, (p) => p.surface),
  ('success on successBg', (p) => p.success, (p) => p.successBg),
  ('warning on surface', (p) => p.warning, (p) => p.surface),
  ('warningText on warningBg', (p) => p.warningText, (p) => p.warningBg),
  ('info on surface', (p) => p.info, (p) => p.surface),
  ('infoText on infoBg', (p) => p.infoText, (p) => p.infoBg),
];

/// The LIGHT palette is frozen to the colors the app has always shown (light
/// mode must look exactly as before), so these pairs were already below 4.5:1
/// in the shipped light look: a gap of the original design, not of the dark
/// palette. They are still measured and printed, and the test fails if one of
/// them gets worse. Every pair that reaches 4.5:1 today must keep doing so.
const Map<String, double> _knownLightGaps = {
  'hint on surface': 2.5,
  'hint on surfaceAlt': 2.2,
  'success on surface': 3.2,
  'success on successBg': 3.0,
  'warning on surface': 3.1,
};

void main() {
  group('AppPalette.light is today\'s look', () {
    const p = AppPalette.light;
    test('neutrals and brand text', () {
      expect(p.background, AppColors.mutedBg);
      expect(p.surfaceAlt, AppColors.mutedBg);
      expect(p.surface, Colors.white);
      expect(p.border, AppColors.border);
      expect(p.foreground, AppColors.foreground);
      expect(p.muted, AppColors.muted);
      expect(p.hint, AppColors.hint);
      expect(p.primaryText, AppColors.primary);
      expect(p.accentBg, AppColors.accentBg);
      expect(p.primaryBorder, AppColors.primaryBorder);
      expect(p.criticalText, AppColors.critical);
    });
    test('status families and shadow', () {
      expect(p.success, AppColors.success);
      expect(p.successBg, AppColors.successBg);
      expect(p.successBorder, AppColors.successBorder);
      expect(p.successSoft, AppColors.successSoft);
      expect(p.successDark, AppColors.successDark);
      expect(p.warning, AppColors.warning);
      expect(p.warningBg, AppColors.warningBg);
      expect(p.warningBorder, AppColors.warningBorder);
      expect(p.warningText, AppColors.warningDark);
      expect(p.info, AppColors.info);
      expect(p.infoBg, AppColors.infoBg);
      expect(p.infoBorder, AppColors.infoBorder);
      expect(p.infoText, AppColors.infoDark);
      expect(p.orange, AppColors.orange);
      expect(p.shadow, AppColors.cardShadow);
    });
    test('the light theme is built from it', () {
      final t = AppTheme.light;
      expect(t.scaffoldBackgroundColor, AppColors.mutedBg);
      expect(t.colorScheme.primary, AppColors.primary);
      expect(t.colorScheme.surface, Colors.white);
      expect(t.extension<AppPalette>(), AppPalette.light);
    });
  });

  group('dark palette contrast (4.5:1)', () {
    for (final (name, fg, bg) in _pairs) {
      test(name, () {
        final ratio = contrastRatio(fg(AppPalette.dark), bg(AppPalette.dark));
        expect(ratio, greaterThanOrEqualTo(4.5), reason: '$name = $ratio');
      });
    }
    test('white on the brand red', () {
      expect(
        contrastRatio(AppColors.onPrimary, AppColors.primary),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('light palette contrast (the shipped look)', () {
    for (final (name, fg, bg) in _pairs) {
      test(name, () {
        final ratio = contrastRatio(fg(AppPalette.light), bg(AppPalette.light));
        final gap = _knownLightGaps[name];
        if (gap == null) {
          expect(ratio, greaterThanOrEqualTo(4.5), reason: '$name = $ratio');
        } else {
          // Already below 4.5 in the original design; it must not get worse.
          expect(ratio, greaterThanOrEqualTo(gap), reason: '$name = $ratio');
        }
      });
    }
  });

  test('lerp animates every color', () {
    final mid = AppPalette.light.lerp(AppPalette.dark, 0.5);
    expect(mid.background, isNot(AppPalette.light.background));
    expect(mid.background, isNot(AppPalette.dark.background));
    expect(mid.foreground, isNot(AppPalette.light.foreground));
    expect(mid.primaryText, isNot(AppPalette.dark.primaryText));
    expect(
      AppPalette.light.lerp(AppPalette.dark, 1).surface,
      AppPalette.dark.surface,
    );
    expect(
      AppPalette.light.lerp(AppPalette.dark, 0).surface,
      AppPalette.light.surface,
    );
  });
}
