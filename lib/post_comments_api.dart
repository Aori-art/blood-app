import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

// ── Models ───────────────────────────────────────────────────────────────────

class PostComment {
  final int id;
  final String authorName;
  final String avatar;

  /// The commenter's streak frame key, or null.
  final String? frame;
  final String content;
  final String timeAgo;
  final String createdAt;
  final bool isMine;

  /// The author hides their photo in comments: [avatar] is empty and initials
  /// are shown.
  final bool photoHidden;

  const PostComment({
    required this.id,
    required this.authorName,
    required this.avatar,
    this.frame,
    required this.content,
    required this.timeAgo,
    required this.createdAt,
    required this.isMine,
    this.photoHidden = false,
  });

  factory PostComment.fromJson(Map<String, dynamic> json) => PostComment(
    id: (json['id'] as num?)?.toInt() ?? 0,
    authorName: json['authorName']?.toString() ?? '',
    avatar: json['avatar']?.toString() ?? '',
    frame: _frameOf(json['frame']),
    content: json['content']?.toString() ?? '',
    timeAgo: json['timeAgo']?.toString() ?? '',
    createdAt: json['createdAt']?.toString() ?? '',
    isMine: json['isMine'] == true,
    photoHidden: json['photoHidden'] == true,
  );
}

// A frame key, or null for "none" (missing, empty or the text "null").
String? _frameOf(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty || s.toLowerCase() == 'null') ? null : s;
}

/// What another donor lets everybody see: a display name (first name and last
/// initial), photo, frame, whether they are verified and since when. Nothing
/// else, and no ids.
class CommenterProfile {
  final String displayName;
  final String avatar;
  final String? frame;
  final bool verified;
  final String? memberSince;

  /// The donor hides their photo in comments: [avatar] is empty.
  final bool photoHidden;

  const CommenterProfile({
    required this.displayName,
    required this.avatar,
    required this.frame,
    required this.verified,
    required this.memberSince,
    this.photoHidden = false,
  });

  factory CommenterProfile.fromJson(Map<String, dynamic> json) {
    final since = json['memberSince']?.toString().trim();
    return CommenterProfile(
      displayName: json['displayName']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      frame: _frameOf(json['frame']),
      verified: json['verified'] == true,
      memberSince: (since == null || since.isEmpty || since == 'null')
          ? null
          : since,
      photoHidden: json['photoHidden'] == true,
    );
  }
}

class ProfileResult {
  final CommenterProfile? profile;
  final String? code;
  final String? message;
  const ProfileResult({this.profile, this.code, this.message});

  bool get ok => profile != null;
  bool get notFound => code == 'COMMENT_NOT_FOUND';
}

/// The answer to hiding, un-hiding or reporting a comment.
class ModerationResult {
  final bool ok;
  final String? code;
  final String? message;
  const ModerationResult({required this.ok, this.code, this.message});
}

class CommentsPage {
  final int total;
  final bool hasMore;
  final List<PostComment> comments;
  const CommentsPage({
    required this.total,
    required this.hasMore,
    required this.comments,
  });
}

class AddCommentResult {
  final bool ok;
  final String? code;
  final String? message;
  final int? total;
  final PostComment? comment;
  const AddCommentResult({
    required this.ok,
    this.code,
    this.message,
    this.total,
    this.comment,
  });
}

class DeleteCommentResult {
  final bool ok;
  final String? message;
  final int? total;
  const DeleteCommentResult({required this.ok, this.message, this.total});
}

class CommentsException implements Exception {
  final String message;
  const CommentsException(this.message);
  @override
  String toString() => message;
}

// ── API ──────────────────────────────────────────────────────────────────────

/// Talks to the comment endpoints. The JSON body is always parsed whatever the
/// HTTP status, because errors come back as JSON with a non-200 status.
class PostCommentsApi {
  static const Duration _timeout = Duration(seconds: 12);

  static Map<String, dynamic>? _decode(http.Response r) {
    try {
      final d = jsonDecode(r.body);
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return null;
  }

  static const String _offline =
      'Unable to reach the server. Please check your connection.';

  static Future<CommentsPage> fetch({
    required int postId,
    String? donorId,
    int limit = 30,
    int? beforeId,
  }) async {
    final query = <String, String>{
      'post_id': '$postId',
      'limit': '$limit',
      if (donorId != null && donorId.isNotEmpty) 'donor_id': donorId,
      if (beforeId != null) 'before_id': '$beforeId',
    };
    final uri = Uri.parse(
      '${AppConfig.baseUrl}/get_post_comments.php',
    ).replace(queryParameters: query);
    final http.Response response;
    try {
      response = await http.get(uri).timeout(_timeout);
    } catch (_) {
      throw const CommentsException(_offline);
    }
    final body = _decode(response);
    if (body == null || body['success'] != true) {
      throw CommentsException(
        body?['message']?.toString() ?? "Couldn't load comments.",
      );
    }
    final list = body['comments'];
    final comments = list is List
        ? list
              .whereType<Map>()
              .map((e) => PostComment.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : <PostComment>[];
    return CommentsPage(
      total: (body['total'] as num?)?.toInt() ?? comments.length,
      hasMore: body['hasMore'] == true,
      comments: comments,
    );
  }

  static Future<AddCommentResult> add({
    required int postId,
    required String donorId,
    required String content,
  }) async {
    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/add_post_comment.php'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'post_id': postId,
              'donor_id': donorId,
              'content': content,
            }),
          )
          .timeout(_timeout);
    } catch (_) {
      return const AddCommentResult(
        ok: false,
        code: 'NETWORK_ERROR',
        message: _offline,
      );
    }
    final body = _decode(response);
    if (body == null) {
      return const AddCommentResult(
        ok: false,
        code: 'SERVER_ERROR',
        message: "Couldn't post your comment. Please try again.",
      );
    }
    final c = body['comment'];
    return AddCommentResult(
      ok: body['success'] == true,
      code: body['code']?.toString(),
      message: body['message']?.toString(),
      total: (body['total'] as num?)?.toInt(),
      comment: c is Map
          ? PostComment.fromJson(Map<String, dynamic>.from(c))
          : null,
    );
  }

  static Future<DeleteCommentResult> delete({
    required int commentId,
    required String donorId,
  }) async {
    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/delete_post_comment.php'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'comment_id': commentId, 'donor_id': donorId}),
          )
          .timeout(_timeout);
    } catch (_) {
      return const DeleteCommentResult(ok: false, message: _offline);
    }
    final body = _decode(response);
    return DeleteCommentResult(
      ok: body?['success'] == true,
      message: body?['message']?.toString(),
      total: (body?['total'] as num?)?.toInt(),
    );
  }

  /// The brief public profile behind one comment. The server looks the donor
  /// up from the comment, so no donor id ever reaches the app.
  static Future<ProfileResult> profile(int commentId) async {
    final http.Response response;
    try {
      response = await http
          .get(
            Uri.parse(
              '${AppConfig.baseUrl}/get_commenter_profile.php'
              '?comment_id=$commentId',
            ),
          )
          .timeout(_timeout);
    } catch (_) {
      return const ProfileResult(code: 'NETWORK_ERROR', message: _offline);
    }
    final body = _decode(response);
    final p = body?['profile'];
    if (body != null && body['success'] == true && p is Map) {
      return ProfileResult(
        profile: CommenterProfile.fromJson(Map<String, dynamic>.from(p)),
      );
    }
    return ProfileResult(
      code: body?['code']?.toString() ?? 'SERVER_ERROR',
      message: body?['message']?.toString() ?? "Couldn't load this profile.",
    );
  }

  /// Hides a comment from the viewer only ('hide') or brings it back
  /// ('unhide').
  static Future<ModerationResult> setHidden({
    required int commentId,
    required String donorId,
    required bool hide,
  }) => _moderate('hide_post_comment.php', {
    'donor_id': donorId,
    'comment_id': commentId,
    'action': hide ? 'hide' : 'unhide',
  });

  /// Reports a comment to the team. [reason] is one of spam, harassment,
  /// inappropriate, false_information or other.
  static Future<ModerationResult> report({
    required int commentId,
    required String donorId,
    required String reason,
    String? details,
  }) => _moderate('report_post_comment.php', {
    'donor_id': donorId,
    'comment_id': commentId,
    'reason': reason,
    if (details != null && details.trim().isNotEmpty) 'details': details.trim(),
  });

  static Future<ModerationResult> _moderate(
    String endpoint,
    Map<String, Object> payload,
  ) async {
    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
    } catch (_) {
      return const ModerationResult(
        ok: false,
        code: 'NETWORK_ERROR',
        message: _offline,
      );
    }
    final body = _decode(response);
    if (body == null) {
      return const ModerationResult(
        ok: false,
        code: 'SERVER_ERROR',
        message: 'Something went wrong. Please try again.',
      );
    }
    return ModerationResult(
      ok: body['success'] == true,
      code: body['code']?.toString(),
      message: body['message']?.toString(),
    );
  }
}
