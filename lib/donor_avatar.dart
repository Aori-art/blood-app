import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'newsfeed.dart' show resolveMediaUrl;
import 'shared_design.dart' show kCrimson;
import 'streak/avatar_frame.dart';
import 'streak/streak_controller.dart';

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
          color: kCrimson,
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

/// The signed-in donor's own photo and frame, shared by the newsfeed header
/// and the comment composer.
///
/// The photo path is cached in preferences ('my_avatar_path') so it shows
/// straight away on the next start, then [refresh] asks the server.
class MyAvatar extends ChangeNotifier {
  MyAvatar._();
  static final MyAvatar instance = MyAvatar._();

  static const String _kPath = 'my_avatar_path';

  String? path;

  /// The frame the server last said is still valid for this donor.
  String? frame;
  String name = '';

  // Bumped by [clear]: an answer that was on its way is for a donor who is
  // gone.
  int _epoch = 0;

  /// The frame to show: the streak's equipped frame (reactive, so equipping
  /// one updates every avatar at once). Only while the streak has not been
  /// loaded does the frame from the server's avatar answer stand in.
  String? get viewerFrame {
    final streak = StreakController.instance;
    if (streak.data != null) return streak.equippedFrame;
    return streak.equippedFrame ?? frame;
  }

  /// Reads what is cached, so the first frame already has the photo.
  Future<void> load() async {
    final epoch = _epoch;
    final prefs = await SharedPreferences.getInstance();
    if (epoch != _epoch) return;
    final cached = prefs.getString(_kPath);
    final userName = prefs.getString('userName') ?? '';
    if (cached != path || userName != name) {
      path = (cached == null || cached.isEmpty) ? null : cached;
      name = userName;
      notifyListeners();
    }
  }

  /// Asks the server for the photo and frame. Errors are ignored: what is
  /// shown stays as it was.
  Future<void> refresh() async {
    final epoch = _epoch;
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString('donorId');
      if (id == null || id.isEmpty) return;
      final response = await http
          .get(Uri.parse('${AppConfig.baseUrl}/get_my_avatar.php?donor_id=$id'))
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true || epoch != _epoch) return;
      final avatar = body['avatar']?.toString();
      final f = body['frame']?.toString();
      final newPath = (avatar == null || avatar.isEmpty) ? null : avatar;
      final newFrame = (f == null || f.isEmpty || f == 'null') ? null : f;
      if (newPath == null) {
        await prefs.remove(_kPath);
      } else {
        await prefs.setString(_kPath, newPath);
      }
      if (epoch != _epoch) return;
      final userName = prefs.getString('userName') ?? name;
      if (newPath != path || newFrame != frame || userName != name) {
        path = newPath;
        frame = newFrame;
        name = userName;
        notifyListeners();
      }
    } catch (_) {
      // Offline or a server hiccup: keep the cached photo.
    }
  }

  /// Forget the donor (sign out, account deletion).
  void clear() {
    _epoch++;
    path = null;
    frame = null;
    name = '';
    notifyListeners();
  }
}

/// [DonorAvatar] of the signed-in donor. It follows [MyAvatar] and the
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
        MyAvatar.instance,
        StreakController.instance,
      ]),
      builder: (context, _) {
        final me = MyAvatar.instance;
        return DonorAvatar(
          photoUrl: me.path,
          name: me.name,
          frame: me.viewerFrame,
          radius: radius,
          reserveFrameSpace: reserveFrameSpace,
        );
      },
    );
  }
}
