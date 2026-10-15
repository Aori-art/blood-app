import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../main.dart' show appNavigatorKey;
import '../shared_design.dart';
import 'blood_bag_mascot.dart';

/// The picture that gets shared. Fixed 360 x 450 logical size, and it holds
/// no personal data: no name, email or ID — only the streak and the mascot.
class StreakShareCard extends StatelessWidget {
  static const double width = 360;
  static const double height = 450;

  final int streak;
  final MascotStage stage;

  const StreakShareCard({super.key, required this.streak, required this.stage});

  static const _white = TextStyle(
    color: Colors.white,
    decoration: TextDecoration.none,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: kHeaderGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
        child: Column(
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bloodtype_rounded, color: Colors.white, size: 22),
                SizedBox(width: 6),
                Text(
                  'eDonate',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    decoration: TextDecoration.none,
                    height: 1.2,
                  ),
                ),
              ],
            ),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BloodBagMascot(
                      size: 190,
                      streak: streak,
                      stage: stage,
                      animate: false,
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$streak',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 76,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                          decoration: TextDecoration.none,
                          shadows: [
                            Shadow(color: Colors.black26, blurRadius: 10),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'day streak on eDonate',
                      style: _white.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .35),
                        ),
                      ),
                      child: Text(
                        stage.stageName,
                        style: _white.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              'Every drop counts. Every life matters.',
              style: _white.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Renders the card to a PNG in the temp directory (3x pixel ratio, so the
/// image is 1080 x 1350) and returns the file.
///
/// The card is laid out in an overlay entry far off-screen. It has to be
/// *painted* (an Offstage widget would not be), so it sits at a large negative
/// offset instead.
Future<File> renderStreakShareImage(
  BuildContext context, {
  required int streak,
  required MascotStage stage,
}) async {
  final overlay =
      Overlay.maybeOf(context, rootOverlay: true) ??
      appNavigatorKey.currentState?.overlay;
  if (overlay == null) throw StateError('No overlay to render the share card.');

  final key = GlobalKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -4000,
      top: 0,
      child: RepaintBoundary(
        key: key,
        child: Material(
          type: MaterialType.transparency,
          child: StreakShareCard(streak: streak, stage: stage),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('The share card was not built.');
    if (boundary.debugNeedsPaint) {
      await WidgetsBinding.instance.endOfFrame;
    }
    final ui.Image image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not encode the share image.');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/edonate-streak-$streak.png');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return file;
  } finally {
    entry.remove();
  }
}

/// Builds the share image and opens the system share sheet. Throws on any
/// failure so the caller can show a message.
Future<void> shareStreak(
  BuildContext context, {
  required int streak,
  required MascotStage stage,
  Rect? origin,
}) async {
  final file = await renderStreakShareImage(
    context,
    streak: streak,
    stage: stage,
  );
  await SharePlus.instance.share(
    ShareParams(
      text:
          "I'm on a $streak-day streak on eDonate! Join me and help save lives. "
          '#EveryDropCounts',
      files: [XFile(file.path, mimeType: 'image/png')],
      sharePositionOrigin: origin,
    ),
  );
}

/// The on-screen rectangle of [context]'s widget, for the iPad share popover.
Rect? shareOriginFor(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  return null;
}
