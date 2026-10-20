import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_palette.dart';

/// The four result states of the eligibility check.
enum ResultKind { eligible, notEligible, deferred, review }

ResultKind resultKindOf(String status) => switch (status) {
  'eligible' => ResultKind.eligible,
  'temporary_deferred' => ResultKind.deferred,
  'for_review' || 'pending' => ResultKind.review,
  _ => ResultKind.notEligible,
};

/// Colors and labels of a result state. Decoration only: buttons keep their
/// own fills.
class ResultStyle {
  final ResultKind kind;

  /// Icons, halos and scene shapes.
  final Color accent;

  /// Chip and label text: at least 4.5:1 on palette.surface and on [tint].
  final Color text;

  /// Backdrops and icon tiles.
  final Color tint;
  final Color border;
  final IconData icon;
  final String chipLabel;

  const ResultStyle({
    required this.kind,
    required this.accent,
    required this.text,
    required this.tint,
    required this.border,
    required this.icon,
    required this.chipLabel,
  });

  static ResultStyle of(BuildContext context, String status) =>
      forPalette(context.palette, status);

  static ResultStyle forPalette(AppPalette p, String status) {
    final kind = resultKindOf(status);
    switch (kind) {
      case ResultKind.eligible:
        return ResultStyle(
          kind: kind,
          accent: p.isDark ? p.success : const Color(0xFF16A34A),
          text: p.isDark ? p.success : const Color(0xFF15803D),
          tint: p.successBg,
          border: p.successBorder,
          icon: Icons.verified_rounded,
          chipLabel: 'ELIGIBLE',
        );
      case ResultKind.notEligible:
        return ResultStyle(
          kind: kind,
          accent: p.isDark ? p.primaryText : AppColors.primary,
          text: p.primaryText,
          tint: p.accentBg,
          border: p.primaryBorder,
          icon: Icons.block_rounded,
          chipLabel: 'NOT ELIGIBLE',
        );
      case ResultKind.deferred:
        return ResultStyle(
          kind: kind,
          accent: p.warning,
          text: p.warningText,
          tint: p.warningBg,
          border: p.warningBorder,
          icon: Icons.schedule_rounded,
          chipLabel: 'DEFERRED',
        );
      case ResultKind.review:
        return ResultStyle(
          kind: kind,
          accent: p.warning,
          text: p.warningText,
          tint: p.warningBg,
          border: p.warningBorder,
          icon: Icons.fact_check_rounded,
          chipLabel: 'UNDER REVIEW',
        );
    }
  }
}
