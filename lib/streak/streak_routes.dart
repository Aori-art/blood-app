import 'package:flutter/material.dart';

import 'streak_home_screen.dart';
import 'streak_ladder_screen.dart';

/// The streak home: fades in with a slight scale (320 ms).
Route<void> streakHomeRoute() => PageRouteBuilder<void>(
  settings: const RouteSettings(name: 'streak_home'),
  transitionDuration: const Duration(milliseconds: 320),
  reverseTransitionDuration: const Duration(milliseconds: 260),
  pageBuilder: (_, _, _) => const StreakHomeScreen(),
  transitionsBuilder: (context, animation, _, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
        child: child,
      ),
    );
  },
);

/// The ladder page: slides up from the bottom (300 ms).
Route<void> streakLadderRoute() => PageRouteBuilder<void>(
  settings: const RouteSettings(name: 'streak_ladder'),
  transitionDuration: const Duration(milliseconds: 300),
  reverseTransitionDuration: const Duration(milliseconds: 260),
  pageBuilder: (_, _, _) => const StreakLadderScreen(),
  transitionsBuilder: (context, animation, _, child) => SlideTransition(
    position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        ),
    child: child,
  ),
);
