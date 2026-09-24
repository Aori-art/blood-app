import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'anim.dart';
import 'login.dart';
import 'home.dart';
import 'config.dart';
import 'verify.dart';
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

  String _verificationStatus = 'unverified';
  bool _checkingVerification = true;
  bool _manualRefreshing = false;

  List<Post> _posts = [];
  bool _loadingPosts = true;
  String? _postsError;

  final ScrollController _scrollController = ScrollController();
  bool _fabVisible = true;
  double _lastScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
    _fetchVerificationStatus();
    _loadPosts();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    final offset = _scrollController.offset;
    final delta = offset - _lastScrollOffset;
    _lastScrollOffset = offset;

    if (offset <= 0) {
      if (!_fabVisible) setState(() => _fabVisible = true);
      return;
    }
    if (delta > 6 && _fabVisible) {
      setState(() => _fabVisible = false);
    } else if (delta < -6 && !_fabVisible) {
      setState(() => _fabVisible = true);
    }
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

  Future<void> _fetchVerificationStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = int.tryParse(prefs.getString('donorId') ?? '') ?? 0;
    if (!mounted) return;

    if (donorId <= 0) {
      setState(() {
        _verificationStatus = 'unverified';
        _checkingVerification = false;
      });
      return;
    }

    try {
      final response = await http
          .get(
            Uri.parse(
              '${AppConfig.baseUrl}/get_verification_status.php?donor_id=$donorId',
            ),
          )
          .timeout(const Duration(seconds: 12));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['status'] == 'success') {
          setState(() {
            _verificationStatus = (data['verification_status'] as String?) ?? 'unverified';
            _checkingVerification = false;
          });
          return;
        }
      }
      setState(() {
        _verificationStatus = 'unverified';
        _checkingVerification = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _verificationStatus = 'unverified';
          _checkingVerification = false;
        });
      }
    }
  }

  void _scrollToVerifyCta() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _onManualRefresh() async {
    if (_manualRefreshing) return;
    setState(() => _manualRefreshing = true);
    await Future.wait([_loadPosts(), _fetchVerificationStatus()]);
    if (mounted) setState(() => _manualRefreshing = false);
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
                onRefresh: () => Future.wait([_loadPosts(), _fetchVerificationStatus()]),
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(bottom: 110),
                  children: [
                    FadeSlideIn(index: 0, child: _buildSignInCta(context)),
                    if (_isLoggedIn)
                      FadeSlideIn(index: 1, child: _buildVerifyIdCta(context)),
                    const SizedBox(height: 16),
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
      floatingActionButton: _buildFabArea(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // ── FAB slot: "Go to Home"/"Sign In" button, or a quiet status banner ───
  Widget? _buildFabArea(BuildContext context) {
    if (!_isLoggedIn) return _buildHomeFab(context);
    if (_checkingVerification) return null;
    if (_verificationStatus == 'verified') return _buildHomeFab(context);
    return _buildVerificationBanner(context);
  }

  Widget _buildVerificationBanner(BuildContext context) {
    final isPending = _verificationStatus == 'pending';
    final bg = isPending ? const Color(0xFFFFFBEB) : const Color(0xFFF3F4F6);
    final border = isPending ? const Color(0xFFFDE68A) : AppColors.border;
    final fg = isPending ? const Color(0xFFB45309) : AppColors.muted;
    final icon = isPending ? Icons.hourglass_top_rounded : Icons.info_outline_rounded;
    final text = isPending
        ? "Home unlocks once your ID is verified"
        : "Verify your ID to unlock the rest of the app";

    return AnimatedSlide(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      offset: _fabVisible ? Offset.zero : const Offset(0, 2),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        opacity: _fabVisible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !_fabVisible,
          child: GestureDetector(
            onTap: isPending ? null : _scrollToVerifyCta,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: fg),
                  const SizedBox(width: 8),
                  Text(
                    text,
                    style: TextStyle(
                      color: fg,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Floating "Go to Home" / "Sign In" button ────────────────────────────
  Widget _buildHomeFab(BuildContext context) {
    final label = _isLoggedIn ? "Go to Home" : "Sign In to Donate";

    return AnimatedSlide(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      offset: _fabVisible ? Offset.zero : const Offset(0, 2),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        opacity: _fabVisible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !_fabVisible,
          child: GestureDetector(
            onTap: () {
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.water_drop, size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right, size: 18, color: Colors.white),
                ],
              ),
            ),
          ),
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
          _buildHeaderRefreshButton(),
        ],
      ),
    );
  }

  Widget _buildHeaderRefreshButton() {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: 'Refresh',
        onPressed: _manualRefreshing ? null : _onManualRefresh,
        icon: _manualRefreshing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.muted,
                ),
              )
            : const Icon(Icons.refresh_rounded, color: AppColors.muted, size: 20),
      ),
    );
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
        const SizedBox(height: 14),
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

  Widget _buildVerifyIdCta(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
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
            child: const Icon(Icons.verified_user_outlined,
                size: 15, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Verify Your Identity",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.foreground,
                  ),
                ),
                Text(
                  "Upload a valid ID to unlock full access",
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VerifyScreen()),
              );
            },
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
              "Verify",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
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

}