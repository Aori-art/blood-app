import 'package:flutter/material.dart';

import 'media_url.dart';
import 'my_avatar_controller.dart';
import 'shared_design.dart' show kCrimson;
import 'streak/avatar_frame.dart';
import 'streak/streak_controller.dart';
import 'app_palette.dart';

/// A donor's profile picture with their streak frame, drawn the same way
/// everywhere (the newsfeed header, comments, the profile sheet).
///
/// [photoUrl] may be a server-relative path; it goes through
/// [resolveMediaUrl]. Without a usable photo, a crimson-tinted circle with the
/// first letter of [name] is shown. The ring of [frame] is drawn outside the
/// circle, so the photo itself keeps its size.
class DonorAvatar extends StatelessWidget {
  final String? photoUrl;
  final String name;
  final String? frame;
  final double radius;

  /// Reserve the room a frame needs even when there is none, so a list of
  /// avatars lines up whether or not each donor has a frame.
  final bool reserveFrameSpace;

  const DonorAvatar({
    super.key,
    this.photoUrl,
    required this.name,
    this.frame,
    required this.radius,
    this.reserveFrameSpace = false,
  });

  /// The letter shown when there is no photo.
  static String initialOf(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = resolveMediaUrl(photoUrl);
    final size = radius * 2;
    final fallback = Container(
      width: size,
      height: size,
      color: kCrimson.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Text(
        initialOf(name),
        style: TextStyle(
          color: context.palette.primaryText,
          fontSize: radius * 0.9,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
    final circle = SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: url == null
            ? fallback
            : Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : fallback,
              ),
      ),
    );

    Widget avatar = StreakAvatarFrame(
      frameKey: frame,
      radius: radius,
      child: circle,
    );
    if (reserveFrameSpace) {
      final extent = streakFrameExtent(radius);
      avatar = SizedBox(
        width: extent,
        height: extent,
        child: Center(child: avatar),
      );
    }
    return Semantics(
      label: '$name, profile picture',
      image: true,
      excludeSemantics: true,
      child: avatar,
    );
  }
}

/// [DonorAvatar] of the signed-in donor. It follows [MyAvatarController] and the
/// streak's equipped frame.
class ViewerAvatar extends StatelessWidget {
  final double radius;
  final bool reserveFrameSpace;

  const ViewerAvatar({
    super.key,
    required this.radius,
    this.reserveFrameSpace = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        MyAvatarController.instance,
        StreakController.instance,
      ]),
      builder: (context, _) {
        final me = MyAvatarController.instance;
        return DonorAvatar(
          photoUrl: me.avatarPath,
          name: me.name,
          frame: me.viewerFrame,
          radius: radius,
          reserveFrameSpace: reserveFrameSpace,
        );
      },
    );
  }
}
