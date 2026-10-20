import 'package:flutter/material.dart';

import '../app_palette.dart';
import 'result_style.dart';

/// The hero panel at the top of a result: Dugtong on a little stage.
class ResultStage extends StatelessWidget {
  final ResultStyle style;
  const ResultStage({super.key, required this.style});

  /// 250 tall, 200 on short screens. Phones around 780 tall get 220 so the
  /// main button stays above the floating navigation bar.
  static double heightFor(BuildContext context) =>
      _heightFor(MediaQuery.sizeOf(context).height);

  static double _heightFor(double screen) => screen < 700
      ? 200
      : screen < 840
      ? 220
      : 250;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: heightFor(context),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: style.border),
        boxShadow: p.shadow,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [style.tint, p.surface],
        ),
      ),
    );
  }
}
