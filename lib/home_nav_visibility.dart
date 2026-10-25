// Whether Home's floating nav is on screen, for everything that keeps room
// for it (scroll paddings, the bars that ride above it, Dugtong's bubble).
//
// The donor can swipe the nav down to hide it; a small handle brings it back.
// While it is hidden that room shrinks to the handle's. Outside Home (or when
// Home is closed) the progress is 1, so every screen keeps exactly the room it
// always had.
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

class HomeNavVisibility {
  HomeNavVisibility._();

  static final HomeNavVisibility instance = HomeNavVisibility._();

  /// 1 = the nav is shown, 0 = it is hidden; in between while it moves.
  final ValueNotifier<double> progress = ValueNotifier(1);

  bool get hidden => progress.value <= 0;

  /// The room kept while the nav is hidden: the handle (a 48 px target with
  /// its gap above the bottom margin).
  static const double handleReserve = 48;

  /// [shown] while the nav is on screen, [hidden] while it is away, and in
  /// between while it moves.
  double reserve(double shown, double hidden) =>
      lerpDouble(hidden, shown, progress.value.clamp(0.0, 1.0))!;

  /// Home is closed: back to "shown" for every other screen.
  void reset() => progress.value = 1;
}

/// Put by HomeScreen above its tabs, so a tab that keeps room for the nav
/// rebuilds while the nav hides or shows.
class HomeNavScope extends InheritedNotifier<ValueNotifier<double>> {
  HomeNavScope({super.key, required super.child})
    : super(notifier: HomeNavVisibility.instance.progress);

  /// The nav's progress where [context] is (1 outside Home), and a dependency
  /// on it.
  static double progressOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<HomeNavScope>();
    if (scope == null) return 1;
    return scope.notifier!.value.clamp(0.0, 1.0);
  }

  /// [shown] with the nav on screen, [hidden] without it, for [context]'s
  /// place (always [shown] outside Home).
  static double reserveOf(
    BuildContext context, {
    required double shown,
    double hidden = HomeNavVisibility.handleReserve,
  }) => lerpDouble(hidden, shown, progressOf(context))!;
}
