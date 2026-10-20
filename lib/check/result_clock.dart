import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// One clock for everything that moves on the result screen (the scene, the
/// props, the entrance, the typewriter, the count-ups and the pulsing dots):
/// a single ticker instead of one per widget. It pauses with [TickerMode]
/// (when the screen is covered).
///
/// With animations removed it does not tick: [ResultClockScope.still] is
/// true and the time sits at [settled], so everything paints its final,
/// still frame.
class ResultClock extends StatefulWidget {
  /// A time by which every entrance has finished.
  static const Duration settled = Duration(seconds: 30);

  final Widget child;
  const ResultClock({super.key, required this.child});

  /// The clock's time (since the result appeared).
  static ValueListenable<Duration> of(BuildContext context) =>
      _scope(context).time;

  /// True when animations are removed.
  static bool stillOf(BuildContext context) => _scope(context).still;

  static ResultClockScope _scope(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ResultClockScope>();
    assert(scope != null, 'No ResultClock above this widget');
    return scope!;
  }

  @override
  State<ResultClock> createState() => _ResultClockState();
}

class _ResultClockState extends State<ResultClock>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((elapsed) => _time.value = elapsed);
  final ValueNotifier<Duration> _time = ValueNotifier(Duration.zero);
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      if (_ticker.isActive) _ticker.stop();
      _time.value = ResultClock.settled;
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ResultClockScope(time: _time, still: _still, child: widget.child);
}

class ResultClockScope extends InheritedWidget {
  final ValueListenable<Duration> time;
  final bool still;

  const ResultClockScope({
    super.key,
    required this.time,
    required this.still,
    required super.child,
  });

  @override
  bool updateShouldNotify(ResultClockScope old) =>
      old.time != time || old.still != still;
}

/// 0..1 progress of something that starts at [delay] and lasts [duration]
/// on the result clock.
double clockProgress(Duration now, Duration delay, Duration duration) {
  final t = (now - delay).inMicroseconds / duration.inMicroseconds;
  return t.clamp(0.0, 1.0);
}
