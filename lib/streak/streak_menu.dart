import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'streak_routes.dart';

/// The streak home's top-right "more" menu.
class StreakMoreMenu extends StatelessWidget {
  final Widget child;
  const StreakMoreMenu({super.key, required this.child});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'More options',
    offset: const Offset(0, 8),
    position: PopupMenuPosition.under,
    onOpened: HapticFeedback.selectionClick,
    onSelected: (value) {
      HapticFeedback.selectionClick();
      if (value == 'ladder') Navigator.push(context, streakLadderRoute());
    },
    itemBuilder: (context) => const [
      PopupMenuItem(value: 'ladder', child: Text('Streak ladder')),
    ],
    child: SizedBox.square(dimension: 48, child: Center(child: child)),
  );
}
