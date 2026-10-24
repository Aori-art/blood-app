// Likes live here, not in the post cards.
//
// A card is built and thrown away as the feed scrolls, filters and reloads,
// so what a donor tapped has to be kept somewhere that outlives it. Per post
// the store holds what is shown (the heart and the count), what the server
// last confirmed, and the latest tap. Requests for a post are sent one at a
// time, in the order of the taps, and the server's answer is the truth.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// What a card shows for a post.
@immutable
class LikeInfo {
  const LikeInfo({required this.liked, required this.likes});

  final bool liked;
  final int likes;

  @override
  bool operator ==(Object other) =>
      other is LikeInfo && other.liked == liked && other.likes == likes;

  @override
  int get hashCode => Object.hash(liked, likes);
}

/// Why a like could not be saved.
enum LikeFailure { signedOut, failed }

/// What the server answered to a like request.
class LikeAnswer {
  const LikeAnswer({this.liked, this.likes});

  final bool? liked;
  final int? likes;
}

/// Sends one like or unlike. Throws [LikeFailure.signedOut] when nobody is
/// signed in; any other exception means it was not saved.
typedef LikeSender = Future<LikeAnswer> Function(int postId, bool liked);

bool _asBool(Object? v) =>
    v == true ||
    v == 1 ||
    (v is String && (v == '1' || v.toLowerCase() == 'true'));

/// like_post.php: JSON {post_id: int, donor_id: string, liked: bool}; it
/// answers {success, likes, liked}.
Future<LikeAnswer> sendLikeToServer(int postId, bool liked) async {
  final prefs = await SharedPreferences.getInstance();
  final donorId = prefs.getString('donorId');
  if (donorId == null || donorId.isEmpty) throw LikeFailure.signedOut;

  final response = await http
      .post(
        Uri.parse('${AppConfig.baseUrl}/like_post.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'post_id': postId,
          'donor_id': donorId,
          'liked': liked,
        }),
      )
      .timeout(const Duration(seconds: 10));
  if (response.statusCode != 200) throw Exception('Like request failed');
  final body = jsonDecode(response.body);
  if (body is! Map || !_asBool(body['success'])) {
    throw Exception('Like request failed');
  }
  final likes = body['likes'];
  return LikeAnswer(
    liked: body.containsKey('liked') ? _asBool(body['liked']) : null,
    likes: likes is num ? likes.toInt() : int.tryParse('$likes'),
  );
}

class _Entry {
  _Entry(bool liked, int likes)
    : confirmedLiked = liked,
      confirmedLikes = likes,
      desired = liked,
      info = ValueNotifier(LikeInfo(liked: liked, likes: likes));

  /// What is shown.
  final ValueNotifier<LikeInfo> info;

  /// What the server last said.
  bool confirmedLiked;
  int confirmedLikes;

  /// What the donor last asked for.
  bool desired;

  /// The store's tap counter at the donor's last tap on this post.
  int lastTap = -1;
  bool working = false;

  /// The count to show for [desired], from the confirmed state.
  LikeInfo shown() => LikeInfo(
    liked: desired,
    likes:
        confirmedLikes + (desired == confirmedLiked ? 0 : (desired ? 1 : -1)),
  );
}

class PostLikeStore {
  PostLikeStore({LikeSender? send}) : _send = send ?? sendLikeToServer;

  final LikeSender _send;
  final Map<int, _Entry> _entries = {};
  int _taps = 0;

  /// Told when a like could not be saved (the heart has been put back).
  void Function(LikeFailure failure)? onFailure;

  /// The heart and count to show for [postId], kept by the store. The first
  /// call takes them from the post; later calls keep what the store knows,
  /// so a rebuilt card shows the same thing.
  ValueListenable<LikeInfo> watch(int postId, {bool? liked, int? likes}) =>
      (_entries[postId] ??= _Entry(liked ?? false, likes ?? 0)).info;

  /// The donor tapped Like (or Unlike) on [postId]: shown at once, sent in
  /// order, and settled by the server's answer.
  void setLiked(int postId, bool liked) {
    final e = _entries[postId];
    if (e == null) return;
    e.lastTap = ++_taps;
    e.desired = liked;
    e.info.value = e.shown();
    _drain(e, postId);
  }

  Future<void> _drain(_Entry e, int postId) async {
    if (e.working) return; // the running loop will pick up the new wish
    e.working = true;
    try {
      while (e.desired != e.confirmedLiked) {
        final sent = e.desired;
        final LikeAnswer answer;
        try {
          answer = await _send(postId, sent);
        } catch (error) {
          // Not saved: back to what the server last confirmed.
          e.desired = e.confirmedLiked;
          e.info.value = e.shown();
          onFailure?.call(
            error == LikeFailure.signedOut
                ? LikeFailure.signedOut
                : LikeFailure.failed,
          );
          return;
        }
        final was = e.confirmedLiked;
        e.confirmedLiked = answer.liked ?? sent;
        e.confirmedLikes =
            answer.likes ??
            (e.confirmedLiked == was
                ? e.confirmedLikes
                : e.confirmedLikes + (e.confirmedLiked ? 1 : -1));
        // The server's word wins unless the donor has tapped again since.
        if (e.desired == sent) e.desired = e.confirmedLiked;
        e.info.value = e.shown();
      }
    } finally {
      e.working = false;
    }
  }

  /// The tap counter now: pass it to [merge] with the feed that was asked
  /// for at this moment.
  int get mark => _taps;

  /// Takes the server's view of the feed. A post the donor tapped after
  /// [startedAt] (the [mark] when that feed was asked for), or whose request
  /// is still running, keeps what the donor did.
  void merge(Iterable<({int id, bool liked, int likes})> posts, int startedAt) {
    for (final p in posts) {
      final e = _entries[p.id];
      if (e == null) {
        _entries[p.id] = _Entry(p.liked, p.likes);
        continue;
      }
      if (e.working || e.desired != e.confirmedLiked || e.lastTap > startedAt) {
        continue;
      }
      e.confirmedLiked = p.liked;
      e.confirmedLikes = p.likes;
      e.desired = p.liked;
      e.info.value = e.shown();
    }
  }
}
