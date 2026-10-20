import 'package:flutter/material.dart';

import '../app_palette.dart';
import 'streak_controller.dart';
import 'streak_routes.dart';
import 'streak_screen.dart';

/// The streak home, opened from the floating Dugtong: one full screen that
/// never scrolls.
class StreakHomeScreen extends StatefulWidget {
  const StreakHomeScreen({super.key});

  @override
  State<StreakHomeScreen> createState() => _StreakHomeScreenState();
}

class _StreakHomeScreenState extends State<StreakHomeScreen>
    with WidgetsBindingObserver {
  final StreakController _c = StreakController.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _c.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreakScreen(
    id: 'streak_home',
    // This screen is Dugtong: the floating bubble steps aside.
    hideBubble: true,
    child: Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _c,
          builder: (context, _) => Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const Spacer(),
              Text(
                '${_c.data?.current ?? 0}',
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.bold,
                  color: context.palette.foreground,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.push(context, streakLadderRoute()),
                child: const Text('Streak ladder'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
