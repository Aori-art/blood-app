import 'dart:math' as math;

import 'package:blood/app_palette.dart';
import 'package:blood/check/result_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _ratio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  const statuses = [
    'eligible',
    'not_eligible',
    'temporary_deferred',
    'for_review',
    'pending',
  ];
  for (final (name, p) in [
    ('light', AppPalette.light),
    ('dark', AppPalette.dark),
  ]) {
    for (final s in statuses) {
      test('$s text is readable on surface and tint ($name)', () {
        final style = ResultStyle.forPalette(p, s);
        expect(
          _ratio(style.text, p.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'on surface',
        );
        expect(
          _ratio(style.text, style.tint),
          greaterThanOrEqualTo(4.5),
          reason: 'on tint',
        );
      });
    }
  }

  test('under review matches the amber used on Home and Book', () {
    final review = ResultStyle.forPalette(AppPalette.light, 'pending');
    expect(review.accent, AppPalette.light.warning);
    expect(review.kind, ResultKind.review);
  });
}
