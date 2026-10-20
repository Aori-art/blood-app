import 'package:flutter/material.dart';

import '../app_palette.dart';
import 'dugtong_chatter.dart' show DugtongSpeechBubble;

/// The app's Dugtong speech bubble (palette.surface, a 1 px border, the
/// same text), with its tail pointing down at him. The full text is laid
/// out from the start so the bubble does not grow while it types.
class DugtongTopBubble extends StatelessWidget {
  final String text;
  final int shown;
  final TextScaler? textScaler;
  const DugtongTopBubble({
    super.key,
    required this.text,
    required this.shown,
    this.textScaler,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final base = DugtongSpeechBubble.textStyle.copyWith(
      color: p.foreground,
      fontSize: 13,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: DugtongSpeechBubble.padding,
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .1),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: text.substring(0, shown)),
                TextSpan(
                  text: text.substring(shown),
                  style: const TextStyle(color: Color(0x00000000)),
                ),
              ],
            ),
            style: base,
            textAlign: TextAlign.center,
            textScaler: textScaler,
          ),
        ),
        CustomPaint(
          size: const Size(16, 8),
          painter: _DownTail(fill: p.surface, border: p.border),
        ),
      ],
    );
  }
}

class _DownTail extends CustomPainter {
  final Color fill;
  final Color border;
  const _DownTail({required this.fill, required this.border});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, -1)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, -1);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _DownTail old) =>
      old.fill != fill || old.border != border;
}
