// A horizontal drag that a widget inside a page of Home's pager would take
// (a swipe-to-delete, a strip that scrolls sideways) can be handed to the
// pager instead, in the direction where the widget has nothing to do with
// it: a rightward swipe on a notification, or a rightward drag on a strip
// that is already at its start.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Wraps [child]. A horizontal drag that starts inside it and moves in a
/// direction [handRight] / [handLeft] allow (right: the finger moves right)
/// is given to the nearest horizontal scrollable above it, the pager, so
/// the donor can swipe to the neighbor tab. Every other drag is left to the
/// widgets inside, which keep their own behavior.
///
/// This recognizer claims the drag after only a few pixels, before the
/// widget inside would (a swipe-to-delete or a list claims after the full
/// touch slop), and only when there is a pager to give it to.
class PagerHandOff extends StatefulWidget {
  const PagerHandOff({
    super.key,
    required this.child,
    this.handRight = _always,
    this.handLeft = _never,
  });

  final Widget child;

  /// May a drag to the right go to the pager now? Defaults to always.
  final bool Function() handRight;

  /// May a drag to the left go to the pager now? Defaults to never.
  final bool Function() handLeft;

  static bool _always() => true;
  static bool _never() => false;

  @override
  State<PagerHandOff> createState() => _PagerHandOffState();
}

class _PagerHandOffState extends State<PagerHandOff> {
  Drag? _drag;

  ScrollableState? get _pager =>
      Scrollable.maybeOf(context, axis: Axis.horizontal);

  bool _may(bool Function() allowed) => _pager != null && allowed();

  @override
  void dispose() {
    _drag?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _HandOffRecognizer:
            GestureRecognizerFactoryWithHandlers<_HandOffRecognizer>(
              _HandOffRecognizer.new,
              (r) {
                r.mayRight = () => _may(widget.handRight);
                r.mayLeft = () => _may(widget.handLeft);
                r.onStart = (details) {
                  _drag = _pager?.position.drag(details, () => _drag = null);
                };
                r.onUpdate = (details) => _drag?.update(details);
                r.onEnd = (details) {
                  _drag?.end(details);
                  _drag = null;
                };
                r.onCancel = () {
                  _drag?.cancel();
                  _drag = null;
                };
              },
            ),
      },
      child: widget.child,
    );
  }
}

class _HandOffRecognizer extends HorizontalDragGestureRecognizer {
  _HandOffRecognizer();

  /// Pixels of movement before this claims the drag (the touch slop is
  /// 18): enough to tell a drag from a tap, little enough to win.
  static const double _earlySlop = 6;

  bool Function() mayRight = () => false;
  bool Function() mayLeft = () => false;

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    final moved = globalDistanceMoved;
    if (moved > _earlySlop) return mayRight();
    if (moved < -_earlySlop) return mayLeft();
    return false;
  }
}
