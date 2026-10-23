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
    this.fallback,
    this.placeholderColor,
    this.decodeAtSize = false,
    this.heroTag,
    this.onTap,
    this.hiddenBadge = false,
  });

  /// A small eye-off badge on the circle's bottom right: the donor's own
  /// avatar when their photo is hidden from other people in comments.
  final bool hiddenBadge;

  /// A Hero around the round photo only (never the frame ring), so the photo
  /// can fly into a full-screen viewer while the ring stays where it is.
  final Object? heroTag;

  final VoidCallback? onTap;

  /// Shown instead of the crimson-tinted letter when there is no photo (or it
  /// fails to load). Sized by the avatar's circle.
  final Widget? fallback;

  /// While the photo loads: a plain circle of this color. Null shows the
  /// fallback, as before.
  final Color? placeholderColor;

  /// Decode the photo at the size it is shown (radius x 2 x pixel ratio).
  final bool decodeAtSize;

  /// The letter shown when there is no photo.
  static String initialOf(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = resolveMediaUrl(photoUrl);
    final size = radius * 2;
    final fallback =
        this.fallback ??
        Container(
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
    final placeholder = placeholderColor == null
        ? fallback
        : ColoredBox(color: placeholderColor!);
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
                cacheWidth: decodeAtSize
                    ? (size * MediaQuery.devicePixelRatioOf(context)).round()
                    : null,
                // A broken or blocked link never leaves a blank circle.
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : placeholder,
              ),
      ),
    );

    final photo = heroTag == null ? circle : Hero(tag: heroTag!, child: circle);
    Widget avatar = StreakAvatarFrame(
      frameKey: frame,
      radius: radius,
      child: hiddenBadge
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                photo,
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: ExcludeSemantics(child: _HiddenBadge(radius: radius)),
                ),
              ],
            )
          : photo,
    );
    if (reserveFrameSpace) {
      final extent = streakFrameExtent(radius);
      avatar = SizedBox(
        width: extent,
        height: extent,
        child: Center(child: avatar),
      );
    }
    if (onTap != null) {
      avatar = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: avatar,
      );
    }
    return Semantics(
      label: hiddenBadge
          ? '$name, profile picture. Your photo is hidden'
          : '$name, profile picture',
      image: true,
      excludeSemantics: true,
      child: avatar,
    );
  }
}

/// The eye-off badge: a 14 px disc with a 10 px icon (smaller on tiny
/// avatars).
class _HiddenBadge extends StatelessWidget {
  final double radius;
  const _HiddenBadge({required this.radius});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final size = radius < 12 ? 11.0 : 14.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.surface,
        shape: BoxShape.circle,
        border: Border.all(color: p.border),
      ),
      child: Icon(
        Icons.visibility_off_outlined,
        size: size - 4,
        color: p.muted,
      ),
    );
  }
}

/// [DonorAvatar] of the signed-in donor. It follows [MyAvatarController] and the
/// streak's equipped frame. With the photo hidden in comments it shows the
/// initials and the eye-off badge, as other people see it.
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
        final hidden = me.hidePhotoInComments;
        return DonorAvatar(
          photoUrl: hidden ? null : me.avatarPath,
          name: me.name,
          frame: me.viewerFrame,
          radius: radius,
          reserveFrameSpace: reserveFrameSpace,
          hiddenBadge: hidden,
        );
      },
    );
  }
}
