import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'anim.dart';
import 'history.dart';
import 'login.dart';
import 'home.dart';
import 'config.dart';
// ── Theme Colors ─────────────────────────────────────────────────────────────

class AppColors {
  static const primary = Color(0xFFC41E3A);
  static const primaryDark = Color(0xFF8B0000);
  static const foreground = Color(0xFF1A1A1A);
  static const muted = Color(0xFF6B6B6B);
  static const mutedBg = Color(0xFFF2F2F2);
  static const border = Color(0xFFE5E5E5);
  static const accentBg = Color(0xFFFDF0F1);
}

// ── Models ───────────────────────────────────────────────────────────────────

enum PostType { event, story, urgent, milestone }

enum Urgency { critical, high, normal }

PostType _postTypeFromString(String value) {
  switch (value) {
    case 'event':
      return PostType.event;
    case 'urgent':
      return PostType.urgent;
    case 'milestone':
      return PostType.milestone;
    case 'story':
    default:
      return PostType.story;
  }
}

Urgency? _urgencyFromString(String? value) {
  switch (value) {
    case 'critical':
      return Urgency.critical;
    case 'high':
      return Urgency.high;
    case 'normal':
      return Urgency.normal;
    default:
      return null;
  }
}

class Post {
  final int id;
  final PostType type;
  final String author;
  final String authorAvatar;
  final String? authorBadge;
  final String timeAgo;
  final String content;
  final String? image;
  final int likes;
  final String? bloodType;
  final String? hospital;
  final String? eventDate;
  final String? eventLocation;
  final Urgency? urgency;

  const Post({
    required this.id,
    required this.type,
    required this.author,
    required this.authorAvatar,
    this.authorBadge,
    required this.timeAgo,
    required this.content,
    this.image,
    required this.likes,
    this.bloodType,
    this.hospital,
    this.eventDate,
    this.eventLocation,
    this.urgency,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as int,
      type: _postTypeFromString(json['type'] as String? ?? 'story'),
      author: json['author'] as String? ?? '',
      authorAvatar: json['authorAvatar'] as String? ?? '',
      authorBadge: json['authorBadge'] as String?,
      timeAgo: json['timeAgo'] as String? ?? '',
      content: json['content'] as String? ?? '',
      image: json['image'] as String?,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      bloodType: json['bloodType'] as String?,
      hospital: json['hospital'] as String?,
      eventDate: json['eventDate'] as String?,
      eventLocation: json['eventLocation'] as String?,
      urgency: _urgencyFromString(json['urgency'] as String?),
    );
  }
}

// ── API ──────────────────────────────────────────────────────────────────────

class NewsfeedApi {
  static Future<List<Post>> fetchPosts({int limit = 50}) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/get_posts.php?limit=$limit');
    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Failed to load posts (${response.statusCode})');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw Exception(body['error']?.toString() ?? 'Failed to load posts');
    }

    final List<dynamic> data = body['posts'] as List<dynamic>? ?? [];
    return data
        .map((item) => Post.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

String formatCount(int n) {
  if (n >= 1000) {
    final v = n / 1000;
    final s = v.toStringAsFixed(1);
    return (s.endsWith(".0") ? s.substring(0, s.length - 2) : s) + "K";
  }
  return n.toString();
}

// ── Urgency Badge ────────────────────────────────────────────────────────────

class UrgencyBadge extends StatelessWidget {
  final Urgency urgency;
  const UrgencyBadge({super.key, required this.urgency});

  @override
  Widget build(BuildContext context) {
    if (urgency == Urgency.normal) return const SizedBox.shrink();

    final isCritical = urgency == Urgency.critical;
    final color = isCritical ? const Color(0xFFDC2626) : const Color(0xFFF97316);
    final label = isCritical ? "CRITICAL" : "URGENT";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 10, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Network Image Helper (graceful fallback) ────────────────────────────────

Widget netImage(String url, {BoxFit fit = BoxFit.cover}) {
  return Image.network(
    url,
    fit: fit,
    errorBuilder: (context, error, stackTrace) => Container(
      color: AppColors.mutedBg,
      child: const Icon(Icons.image_not_supported_outlined,
          color: AppColors.muted, size: 20),
    ),
    loadingBuilder: (context, child, progress) {
      if (progress == null) return child;
      return Container(color: AppColors.mutedBg);
    },
  );
}

// ── Post Card ────────────────────────────────────────────────────────────────

class PostCard extends StatefulWidget {
  final Post post;
  const PostCard({super.key, required this.post});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late bool liked;
  late int likeCount;
  double _likeIconScale = 1.0;

  @override
  void initState() {
    super.initState();
    liked = false;
    likeCount = widget.post.likes;
  }

  Future<void> _handleLike() async {
    final wasLiked = liked;
    final previousCount = likeCount;

    setState(() {
      liked = !liked;
      likeCount += liked ? 1 : -1;
    });
    if (liked) {
      setState(() => _likeIconScale = 1.4);
      Future.delayed(const Duration(milliseconds: 140), () {
        if (mounted) setState(() => _likeIconScale = 1.0);
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final donorId = prefs.getString('donorId');
      if (donorId == null || donorId.isEmpty) return; // not logged in, skip persisting

      final uri = Uri.parse('${AppConfig.baseUrl}/like_post.php');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'post_id': widget.post.id,
              'donor_id': donorId,
              'liked': liked,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Like request failed');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['success'] != true) {
        throw Exception('Like request failed');
      }
      if (mounted && body['likes'] != null) {
        setState(() => likeCount = (body['likes'] as num).toInt());
      }
    } catch (_) {
      // Revert on failure so the UI doesn't lie about the like state.
      if (mounted) {
        setState(() {
          liked = wasLiked;
          likeCount = previousCount;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.2), width: 2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: netImage(post.authorAvatar),
                    ),
                    if (post.type == PostType.urgent)
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.water_drop,
                              size: 8, color: Colors.white),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            post.author,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.foreground,
                            ),
                          ),
                          if (post.urgency != null)
                            UrgencyBadge(urgency: post.urgency!),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (post.authorBadge != null) ...[
                            const Icon(Icons.emoji_events,
                                size: 10, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Text(
                              post.authorBadge!,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text("·",
                                style: TextStyle(
                                    fontSize: 11, color: AppColors.muted)),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            post.timeAgo,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Event banner
          if (post.type == PostType.event && post.eventDate != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.accentBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.calendar_today,
                        size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.eventDate!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.foreground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.location_on,
                                size: 9, color: AppColors.muted),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                post.eventLocation ?? "",
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.muted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      "RSVP",
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),

          // Milestone banner
          if (post.type == PostType.milestone)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [Colors.red.shade50, Colors.pink.shade50],
                ),
                border: Border.all(color: AppColors.primary.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child:
                        const Icon(Icons.trending_up, size: 18, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "50,000",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                          height: 1,
                        ),
                      ),
                      Text(
                        "Donations completed",
                        style: TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 76,
                    height: 32,
                    child: Stack(
                      children: [
                        for (final entry in [
                          "photo-1494790108755-2616b612b786",
                          "photo-1539571696357-5a69c17a67c6",
                          "photo-1507003211169-0a1dd7228f2d",
                        ].asMap().entries)
                          Positioned(
                            left: entry.key * 20.0,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: netImage(
                                  "https://images.unsplash.com/${entry.value}?w=64&h=64&fit=crop&auto=format"),
                            ),
                          ),
                        Positioned(
                          left: 60,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              "+99k",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Post text
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              post.content,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: AppColors.foreground,
              ),
            ),
          ),

          // Post image
          if (post.image != null)
            Container(
              color: AppColors.mutedBg,
              constraints: const BoxConstraints(maxHeight: 240),
              width: double.infinity,
              child: netImage(post.image!),
            ),

          // Action bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: _handleLike,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedScale(
                          scale: _likeIconScale,
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOut,
                          child: Icon(
                            liked ? Icons.favorite : Icons.favorite_border,
                            size: 17,
                            color:
                                liked ? AppColors.primary : AppColors.muted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          liked ? "Liked" : "Like",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: liked ? AppColors.primary : AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  "${formatCount(likeCount)} likes",
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Main Newsfeed Page ───────────────────────────────────────────────────────

class NewsfeedPage extends StatefulWidget {
  const NewsfeedPage({super.key});

  @override
  State<NewsfeedPage> createState() => _NewsfeedPageState();
}

class _NewsfeedPageState extends State<NewsfeedPage> {
  bool _isLoggedIn = false;
  String? _userName;
  bool _checkedLogin = false;

  List<Post> _posts = [];
  bool _loadingPosts = true;
  String? _postsError;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
    _loadPosts();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool('isLoggedIn') ?? false;
    final donorId = prefs.getString('donorId');
    if (!mounted) return;
    setState(() {
      _isLoggedIn = loggedIn && donorId != null && donorId.isNotEmpty;
      _userName = prefs.getString('userName');
      _checkedLogin = true;
    });
  }

  Future<void> _loadPosts() async {
    setState(() {
      _loadingPosts = true;
      _postsError = null;
    });
    try {
      final posts = await NewsfeedApi.fetchPosts();
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loadingPosts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _postsError = 'Could not load the newsfeed. Pull down to try again.';
        _loadingPosts = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.mutedBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadPosts,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    FadeSlideIn(index: 0, child: _buildSignInCta(context)),
                    FadeSlideIn(index: 1, child: _buildTrendingAlert(context)),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildPostsList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostsList() {
    if (_loadingPosts) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (_postsError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Icon(Icons.wifi_off, color: AppColors.muted, size: 32),
            const SizedBox(height: 8),
            Text(
              _postsError!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _loadPosts,
              child: const Text("Retry"),
            ),
          ],
        ),
      );
    }

    if (_posts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            "No posts yet. Check back soon!",
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < _posts.length; i++) ...[
          FadeSlideIn(
            index: i,
            child: PostCard(post: _posts[i]),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryDark],
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.water_drop, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: "e",
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    TextSpan(
                      text: "Donate",
                      style: TextStyle(
                        color: AppColors.foreground,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              const Text(
                "BLOOD DONATION NETWORK",
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
  onTap: () => _handleProfileTap(context),
  child: ClipOval(
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.mutedBg,
        border: Border.all(
            color: AppColors.primary.withOpacity(0.3), width: 2),
      ),
      child: const Icon(
        Icons.person,
        color: AppColors.muted,
        size: 20,
      ),
    ),
  ),
),
        ],
      ),
    );
  }

  Future<void> _handleProfileTap(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
  final donorId = prefs.getString('donorId');

  if (isLoggedIn && donorId != null && donorId.isNotEmpty) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }
}

  Widget _buildSignInCta(BuildContext context) {
  // Avoid flashing the CTA before we've checked login state
  if (!_checkedLogin) return const SizedBox.shrink();

  return Container(
    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.primary, AppColors.primaryDark],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isLoggedIn
                        ? "WELCOME BACK${_userName != null ? ', ${_userName!.split(' ').first.toUpperCase()}' : ''}"
                        : "YOUR BLOOD CAN SAVE 3 LIVES",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _isLoggedIn ? "Ready to Save a Life?" : "Become a Donor Today",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _isLoggedIn
                        ? "View your donation history, track your impact, and manage your profile."
                        : "Sign in to schedule your donation, track your impact, and earn badges.",
                    style: const TextStyle(
                      color: Color(0xFFFECACA),
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.water_drop,
                size: 40, color: Colors.white.withOpacity(0.3)),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              if (_isLoggedIn) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                );
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.water_drop, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  _isLoggedIn ? "Go to Home" : "Sign In to Donate",
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right, size: 16, color: AppColors.primary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _statChip(Icons.people, "128K donors"),
              _dot(),
              _statChip(Icons.favorite, "50K+ lives saved"),
              _dot(),
              _statChip(Icons.emoji_events, "Free health check"),
            ],
          ),
        ),
      ],
    ),
  );
}

  Widget _statChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: Colors.white70),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ],
    );
  }

  Widget _dot() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      width: 3,
      height: 3,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.3),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildTrendingAlert(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.trending_up, size: 15, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Trending: Mega Blood Drive",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.foreground,
                  ),
                ),
                Text(
                  "142 people are going · SM MoA, this Saturday",
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withOpacity(0.3)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              "Join",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}