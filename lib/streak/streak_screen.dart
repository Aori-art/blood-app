import 'package:flutter/widgets.dart';

import 'streak_controller.dart';

/// Wrap a screen in this to keep the floating streak bubble off it. The bubble
/// stays hidden for as long as at least one of these is mounted.
class StreakBubbleHidden extends StatefulWidget {
  final Widget child;

  const StreakBubbleHidden({super.key, required this.child});

  @override
  State<StreakBubbleHidden> createState() => _StreakBubbleHiddenState();
}

class _StreakBubbleHiddenState extends State<StreakBubbleHidden> {
  @override
  void initState() {
    super.initState();
    StreakController.instance.pushHidden();
  }

  @override
  void dispose() {
    StreakController.instance.popHidden();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
