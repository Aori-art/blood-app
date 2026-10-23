import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'donor_avatar.dart';
import 'my_avatar_controller.dart';
import 'shared_design.dart' show kCrimson;
import 'streak/avatar_frame.dart';
import 'streak/streak_controller.dart';

/// The signed-in donor's own avatar: their photo (from [MyAvatarController])
/// in a circle, with the streak's equipped frame drawn outside it. Without a
/// photo, or when it fails to load, their initials in the look each screen
/// had before.
class MyAvatar extends StatelessWidget {
  final double radius;
  final bool showFrame;

  /// On the red headers (Home): a translucent white circle with white
  /// initials. Otherwise a crimson circle with white initials.
  final bool onGradient;

  /// A thin ring around the circle when no frame is shown (the Home header's
  /// white outline).
  final Color? ringColor;

  /// Overrides the frame (the Edit Frame and ladder previews show each
  /// frame on the donor's own photo).
  final String? frameOverride;

  const MyAvatar({
    super.key,
    required this.radius,
    this.showFrame = true,
    this.onGradient = false,
    this.ringColor,
    this.frameOverride,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      MyAvatarController.instance,
      StreakController.instance,
    ]),
    builder: (context, _) {
      final me = MyAvatarController.instance;
      final frame = frameOverride ?? (showFrame ? me.viewerFrame : null);
      final size = radius * 2;
      final initials = onGradient
          ? DonorAvatar.initialOf(me.name)
          : me.initials;
      final fallback = Container(
        width: size,
        height: size,
        color: onGradient ? Colors.white24 : kCrimson,
        alignment: Alignment.center,
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * (onGradient ? 0.9 : 0.66),
            fontWeight: FontWeight.bold,
            height: 1,
          ),
        ),
      );
      Widget avatar = DonorAvatar(
        photoUrl: me.avatarPath,
        name: me.name,
        frame: frame,
        radius: radius,
        fallback: fallback,
        placeholderColor: context.palette.surfaceAlt,
        decodeAtSize: true,
      );
      final ring = ringColor;
      // A frame draws its own ring; the plain outline is for no frame.
      final framed = frame != null && kStreakFrameKeys.contains(frame);
      if (!framed && ring != null) {
        avatar = Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ring, width: 2),
          ),
          child: avatar,
        );
      }
      return avatar;
    },
  );
}
