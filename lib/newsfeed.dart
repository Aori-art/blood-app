import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'anim.dart';
import 'book.dart';
import 'history.dart';
import 'login.dart';
import 'pin_screen.dart'; // PIN: "Go to Home" now goes through the PIN screen
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
  // Posts are made by admins or facilities, never donors. Both null when
  // the post isn't linked to an account.
  final String? authorType; // "admin" | "facility" | null
  final int? authorId;
  final bool isDonation;
  final bool donationOpen;
  final int? eventId;
  final int? donationFacilityId;
  final String timeAgo;
  final String content;
  final String? image;
  final int likes;
  final String? bloodType;
  final String? hospital;
  final String? eventDate;
  final String? eventLocation;
  final Urgency? urgency;
  final bool liked;

  const Post({
    required this.id,
    required this.type,
    required this.author,
    required this.authorAvatar,
    this.authorBadge,
    this.authorType,
    this.authorId,
    this.isDonation = false,
    this.donationOpen = true,
    this.eventId,
    this.donationFacilityId,
    required this.timeAgo,
    required this.content,
    this.image,
    required this.likes,
    this.bloodType,
    this.hospital,
    this.eventDate,
    this.eventLocation,
    this.urgency,
    this.liked = false,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as int,
      type: _postTypeFromString(json['type'] as String? ?? 'story'),
      author: json['author'] as String? ?? '',
      authorAvatar: json['authorAvatar'] as String? ?? '',
      authorBadge: json['authorBadge'] as String?,
      authorType: json['authorType'] as String?,
      authorId: (json['authorId'] as num?)?.toInt(),
      isDonation: json['isDonation'] == true,
      donationOpen: json['donationOpen'] != false,
      eventId: (json['eventId'] as num?)?.toInt(),
      donationFacilityId: (json['donationFacilityId'] as num?)?.toInt(),
      timeAgo: json['timeAgo'] as String? ?? '',
      content: json['content'] as String? ?? '',
      image: json['image'] as String?,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      bloodType: json['bloodType'] as String?,
      hospital: json['hospital'] as String?,
      eventDate: json['eventDate'] as String?,
      eventLocation: json['eventLocation'] as String?,
      urgency: _urgencyFromString(json['urgency'] as String?),
      liked: json['liked'] == true,
    );
  }
}

// ── API ──────────────────────────────────────────────────────────────────────

class NewsfeedApi {
  static Future<List<Post>> fetchPosts({
    int limit = 50,
    String? donorId,
  }) async {
    final hasDonorId = donorId != null && donorId.isNotEmpty;
    final uri = Uri.parse(
      '${AppConfig.baseUrl}/get_posts.php?limit=$limit${hasDonorId ? '&donor_id=$donorId' : ''}',
    );
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
    final color = isCritical
        ? const Color(0xFFDC2626)
        : const Color(0xFFF97316);
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

// Builds a full URL for a server-relative media path (e.g. a profile
// picture path like "uploads/profile/741.jpg"), leaving already-absolute
// URLs untouched — same convention as the ready-made image/avatar URLs
// this file already gets from get_posts.php.
String? resolveMediaUrl(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  final origin = AppConfig.baseUrl.replaceAll(RegExp(r'/api/?$'), '');
  final cleanPath = path.startsWith('/') ? path.substring(1) : path;
  return '$origin/$cleanPath';
}

Widget netImage(String url, {BoxFit fit = BoxFit.cover}) {
  return Image.network(
    url,
    fit: fit,
    errorBuilder: (context, error, stackTrace) => Container(
      color: AppColors.mutedBg,
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: AppColors.muted,
        size: 20,
      ),
    ),
    loadingBuilder: (context, child, progress) {
      if (progress == null) return child;
      return Container(color: AppColors.mutedBg);
    },
  );
}

// ── Pressable post image (press-in scale + full-screen viewer) ─────────────

class _PressableImage extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _PressableImage({required this.child, required this.onTap});

  @override
  State<_PressableImage> createState() => _PressableImageState();
}

class _PressableImageState extends State<_PressableImage> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 1.03),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ── Full-screen image viewer ────────────────────────────────────────────────

class _ImageViewerPage extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final String heroTagPrefix;

  const _ImageViewerPage({
    required this.imageUrls,
    required this.initialIndex,
    required this.heroTagPrefix,
  });

  @override
  State<_ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<_ImageViewerPage> {
  late final PageController _pageController;
  late int _currentIndex;
  final TransformationController _transformController =
      TransformationController();
  bool _isZoomed = false;

  bool _dragging = false;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _transformController.addListener(_handleTransformChange);
  }

  @override
  void dispose() {
    _transformController.removeListener(_handleTransformChange);
    _transformController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _handleTransformChange() {
    final zoomed = _transformController.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _isZoomed) setState(() => _isZoomed = zoomed);
  }

  void _handleDoubleTap(TapDownDetails details) {
    if (_isZoomed) {
      _transformController.value = Matrix4.identity();
      return;
    }
    final position = details.localPosition;
    const scale = 2.5;
    final x = -position.dx * (scale - 1);
    final y = -position.dy * (scale - 1);
    _transformController.value = Matrix4.identity()
      ..translate(x, y)
      ..scale(scale);
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_isZoomed) return;
    setState(() {
      _dragging = true;
      _dragOffset = (_dragOffset + details.delta.dy).clamp(0, 400);
    });
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (_isZoomed) return;
    final flungDown = details.velocity.pixelsPerSecond.dy > 700;
    if (_dragOffset > 120 || flungDown) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _dragging = false;
      _dragOffset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final opacity = (1 - (_dragOffset / 400)).clamp(0.25, 1.0);
    final multiple = widget.imageUrls.length > 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          onVerticalDragUpdate: _handleVerticalDragUpdate,
          onVerticalDragEnd: _handleVerticalDragEnd,
          child: AnimatedContainer(
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            width: double.infinity,
            height: double.infinity,
            color: Colors.black.withValues(alpha: opacity),
            transform: Matrix4.translationValues(0, _dragOffset, 0),
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                  physics: _isZoomed
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  itemCount: widget.imageUrls.length,
                  onPageChanged: (i) => setState(() {
                    _currentIndex = i;
                    _isZoomed = false;
                    _transformController.value = Matrix4.identity();
                  }),
                  itemBuilder: (context, index) {
                    final url = widget.imageUrls[index];
                    return GestureDetector(
                      onDoubleTapDown: _handleDoubleTap,
                      child: InteractiveViewer(
                        transformationController: _transformController,
                        minScale: 1,
                        maxScale: 4,
                        // Panning is only meaningful once zoomed in — keeping
                        // it off at rest lets our own vertical-drag-to-close
                        // gesture win the arena instead of InteractiveViewer.
                        panEnabled: _isZoomed,
                        child: Center(
                          child: Hero(
                            tag: '${widget.heroTagPrefix}_$index',
                            child: Image.network(
                              url,
                              fit: BoxFit.contain,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) =>
                                  Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.broken_image_outlined,
                                          color: Colors.grey[400],
                                          size: 40,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          "Couldn't load image",
                                          style: TextStyle(
                                            color: Colors.grey[400],
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.topLeft,
                          child: Tooltip(
                            message: 'Close',
                            child: InkWell(
                              onTap: () => Navigator.of(context).pop(),
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(
                                  color: Colors.black45,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (multiple)
                          Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${_currentIndex + 1} / ${widget.imageUrls.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _openImageViewer(
  BuildContext context, {
  required List<String> imageUrls,
  required int initialIndex,
  required String heroTagPrefix,
}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) => _ImageViewerPage(
        imageUrls: imageUrls,
        initialIndex: initialIndex,
        heroTagPrefix: heroTagPrefix,
      ),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

// ── Poster (admin/facility) profile preview sheet ───────────────────────────

void _showPosterPreview(BuildContext context, {required Post post}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => _PosterPreviewSheet(post: post),
  );
}

String? _formatMonthYear(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final date = DateTime.tryParse(raw);
  if (date == null) return null;
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

String? _formatTime12(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final parts = raw.split(':');
  if (parts.length < 2) return null;
  final hour24 = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour24 == null || minute == null) return null;
  final period = hour24 >= 12 ? 'PM' : 'AM';
  var hour = hour24 % 12;
  if (hour == 0) hour = 12;
  return '$hour:${minute.toString().padLeft(2, '0')} $period';
}

IconData _facilityTypeIcon(String? facilityType) {
  switch (facilityType) {
    case 'hospital':
      return Icons.local_hospital_rounded;
    case 'blood_bank':
      return Icons.bloodtype_rounded;
    case 'clinic':
      return Icons.medical_services_rounded;
    case 'health_center':
      return Icons.health_and_safety_rounded;
    default:
      return Icons.apartment_rounded;
  }
}

class _PosterPreviewSheet extends StatefulWidget {
  final Post post;
  const _PosterPreviewSheet({required this.post});

  @override
  State<_PosterPreviewSheet> createState() => _PosterPreviewSheetState();
}

class _PosterPreviewSheetState extends State<_PosterPreviewSheet> {
  bool get _isLinked =>
      widget.post.authorType != null && widget.post.authorId != null;

  bool _loading = true;
  bool _error = false;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    if (_isLinked) {
      _fetchProfile();
    } else {
      _loading = false;
    }
  }

  Future<void> _fetchProfile() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final uri = Uri.parse(
        '${AppConfig.baseUrl}/get_poster_profile_preview.php'
        '?type=${widget.post.authorType}&id=${widget.post.authorId}',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map &&
            data['status'] == 'success' &&
            data['profile'] is Map) {
          setState(() {
            _profile = Map<String, dynamic>.from(data['profile']);
            _loading = false;
          });
          return;
        }
      }
      setState(() {
        _loading = false;
        _error = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  String get _displayName {
    final postAuthor = widget.post.author.trim();
    if (postAuthor.isNotEmpty) return postAuthor;
    return _profile?['name']?.toString() ?? 'Unknown';
  }

  (IconData, Color, Color) _avatarFallbackStyle() {
    final authorType = widget.post.authorType;
    if (authorType == 'facility') {
      final facilityType = _profile?['facility_type']?.toString();
      return (
        _facilityTypeIcon(facilityType),
        const Color(0xFF2563EB),
        const Color(0xFFEFF6FF),
      );
    }
    if (authorType == 'admin') {
      return (
        Icons.verified_rounded,
        const Color(0xFFDC2626),
        const Color(0xFFFFF1F1),
      );
    }
    return (
      Icons.groups_rounded,
      const Color(0xFF6B7280),
      const Color(0xFFF3F4F6),
    );
  }

  Widget _avatar() {
    const size = 80.0;
    final isFacility = widget.post.authorType == 'facility';
    final (icon, fg, bg) = _avatarFallbackStyle();
    final innerRadius = BorderRadius.circular(isFacility ? 20 : size / 2);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isFacility ? 23 : size / 2 + 3),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: innerRadius,
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(
            widget.post.authorAvatar,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: bg,
              alignment: Alignment.center,
              child: Icon(icon, color: fg, size: 32),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill({
    required IconData icon,
    required String label,
    required Color fg,
    required Color bg,
    required Color border,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: fg),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ],
    ),
  );

  Widget? _typePill() {
    final profile = _profile;
    final authorType = widget.post.authorType;

    if (profile != null && authorType == 'facility') {
      final facilityType = profile['facility_type']?.toString();
      final label = profile['facility_type_label']?.toString() ?? 'Facility';
      return _pill(
        icon: _facilityTypeIcon(facilityType),
        label: label,
        fg: const Color(0xFF2563EB),
        bg: const Color(0xFFEFF6FF),
        border: const Color(0xFFBFDBFE),
      );
    }
    if (profile != null && authorType == 'admin') {
      final label =
          profile['role_label']?.toString() ?? 'Official eDonate Account';
      return _pill(
        icon: Icons.verified_rounded,
        label: label,
        fg: const Color(0xFFDC2626),
        bg: const Color(0xFFFFF1F1),
        border: const Color(0xFFFECACA),
      );
    }
    // Loading / unlinked / error — fall back to whatever badge the post
    // itself carries, until (or unless) the typed profile pill is ready.
    if (widget.post.authorBadge != null) {
      return _pill(
        icon: Icons.emoji_events,
        label: widget.post.authorBadge!,
        fg: const Color(0xFFDC2626),
        bg: const Color(0xFFFFF1F1),
        border: const Color(0xFFFECACA),
      );
    }
    return null;
  }

  Widget _iconBox(IconData icon) => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F1),
      borderRadius: BorderRadius.circular(10),
    ),
    alignment: Alignment.center,
    child: Icon(icon, size: 16, color: const Color(0xFFDC2626)),
  );

  Widget _addressBlock(Map<String, dynamic> profile) {
    final address = profile['address']!.toString();
    final subParts = <String>[];
    for (final key in ['barangay_name', 'city', 'province']) {
      final v = profile[key]?.toString();
      if (v != null &&
          v.isNotEmpty &&
          !address.toLowerCase().contains(v.toLowerCase())) {
        subParts.add(v);
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _iconBox(Icons.location_on_rounded),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Address",
                style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 2),
              Text(
                address,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              if (subParts.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subParts.join(', '),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _contactRow(String contactNumber) => InkWell(
    onTap: () {
      Clipboard.setData(ClipboardData(text: contactNumber));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Contact number copied"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    },
    borderRadius: BorderRadius.circular(10),
    child: Row(
      children: [
        _iconBox(Icons.call_rounded),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Contact",
                style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 2),
              Text(
                contactNumber,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF9CA3AF)),
      ],
    ),
  );

  Widget _facilityInfoCard(Map<String, dynamic> profile) {
    final address = profile['address']?.toString();
    final contact = profile['contact_number']?.toString();
    final rows = <Widget>[];
    if (address != null && address.isNotEmpty) rows.add(_addressBlock(profile));
    if (contact != null && contact.isNotEmpty) {
      if (rows.isNotEmpty)
        rows.add(const Divider(height: 20, color: Color(0xFFF3F4F6)));
      rows.add(_contactRow(contact));
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: rows),
    );
  }

  Widget _eventRow(Map<String, dynamic> event) {
    final date = DateTime.tryParse(event['event_date']?.toString() ?? '');
    const monthsShort = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final monthLabel = date != null ? monthsShort[date.month - 1] : '—';
    final dayLabel = date != null ? '${date.day}' : '—';

    final start = _formatTime12(event['start_time']?.toString());
    final end = _formatTime12(event['end_time']?.toString());
    final timeLabel = (start != null && end != null)
        ? '$start – $end'
        : (start ?? end ?? '');
    final location = event['location_name']?.toString();
    final subtitle = [
      if (timeLabel.isNotEmpty) timeLabel,
      if (location != null && location.isNotEmpty) location,
    ].join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1F1),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                monthLabel,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFFDC2626),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                dayLabel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event['title']?.toString() ?? '',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _upcomingEventsSection(Map<String, dynamic> profile) {
    final events = profile['upcoming_events'];
    final list = events is List ? events : const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Upcoming Donation Events",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          const Text(
            "No upcoming events right now.",
            style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
          )
        else
          for (final e in list) ...[
            _eventRow(Map<String, dynamic>.from(e as Map)),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _facilitySections(Map<String, dynamic> profile) {
    final showInactiveNote = profile['is_active'] == false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showInactiveNote) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              border: Border.all(color: const Color(0xFFFDE68A)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: Color(0xFFB45309),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "This facility isn't accepting donations right now.",
                    style: TextStyle(fontSize: 11, color: Color(0xFFB45309)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        _facilityInfoCard(profile),
        const SizedBox(height: 16),
        _upcomingEventsSection(profile),
      ],
    );
  }

  Widget _adminBanner() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFEFF6FF),
      border: Border.all(color: const Color(0xFFBFDBFE)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_rounded, size: 16, color: Color(0xFF2563EB)),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            "Posts from this account are official announcements from the eDonate team.",
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF1D4ED8),
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _basicNote() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Text(
      "More details about this organization aren't available yet.",
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
    ),
  );

  Widget _loadingPlaceholders() => Column(
    children: [
      Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      const SizedBox(height: 10),
      Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      const SizedBox(height: 10),
      Container(
        width: double.infinity,
        height: 72,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ],
  );

  Widget _errorSection() => Column(
    children: [
      const Icon(Icons.wifi_off_rounded, color: Color(0xFF9CA3AF), size: 28),
      const SizedBox(height: 8),
      const Text(
        "Couldn't load this profile",
        style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
      ),
      const SizedBox(height: 10),
      TextButton.icon(
        onPressed: _fetchProfile,
        icon: const Icon(
          Icons.refresh_rounded,
          size: 16,
          color: Color(0xFFDC2626),
        ),
        label: const Text(
          "Retry",
          style: TextStyle(
            color: Color(0xFFDC2626),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final profile = _profile;
    final pill = _typePill();
    final memberSince = profile != null
        ? _formatMonthYear(profile['member_since']?.toString())
        : null;

    Widget sections;
    if (_isLinked && _loading) {
      sections = _loadingPlaceholders();
    } else if (_isLinked && _error) {
      sections = _errorSection();
    } else if (post.authorType == 'facility' && profile != null) {
      sections = _facilitySections(profile);
    } else if (post.authorType == 'admin' && profile != null) {
      sections = _adminBanner();
    } else {
      sections = _basicNote();
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),
              _avatar(),
              const SizedBox(height: 12),
              Text(
                _displayName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
              if (pill != null) ...[const SizedBox(height: 8), pill],
              if (memberSince != null) ...[
                const SizedBox(height: 8),
                Text(
                  "On eDonate since $memberSince",
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              sections,
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFDC2626)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Close",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Post Card ────────────────────────────────────────────────────────────────

class PostCard extends StatefulWidget {
  final Post post;
  final bool canDonate;
  const PostCard({super.key, required this.post, this.canDonate = false});

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
    liked = widget.post.liked;
    likeCount = widget.post.likes;
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.liked != widget.post.liked ||
        oldWidget.post.likes != widget.post.likes) {
      setState(() {
        liked = widget.post.liked;
        likeCount = widget.post.likes;
      });
    }
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
      if (donorId == null || donorId.isEmpty) {
        // Not logged in — undo the optimistic toggle instead of leaving the
        // heart in a state that was never actually persisted.
        if (mounted) {
          setState(() {
            liked = wasLiked;
            likeCount = previousCount;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sign in to like posts.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

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
            child: InkWell(
              onTap: () => _showPosterPreview(context, post: post),
              borderRadius: BorderRadius.circular(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Hero(
                        tag: 'author_avatar_${post.id}',
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.2),
                              width: 2,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: netImage(post.authorAvatar),
                        ),
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
                            child: const Icon(
                              Icons.water_drop,
                              size: 8,
                              color: Colors.white,
                            ),
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
                              const Icon(
                                Icons.emoji_events,
                                size: 10,
                                color: AppColors.primary,
                              ),
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
                              const Text(
                                "·",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              post.timeAgo,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
            _PressableImage(
              onTap: () => _openImageViewer(
                context,
                imageUrls: [post.image!],
                initialIndex: 0,
                heroTagPrefix: 'post_image_${post.id}',
              ),
              child: Hero(
                tag: 'post_image_${post.id}_0',
                child: Container(
                  color: AppColors.mutedBg,
                  constraints: const BoxConstraints(maxHeight: 240),
                  width: double.infinity,
                  child: netImage(post.image!),
                ),
              ),
            ),

          // Donate block — only for open donation posts, and only when the
          // viewer is a verified, logged-in donor.
          if (post.isDonation && post.donationOpen && widget.canDonate)
            _DonateBlock(post: post),

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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
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
                            color: liked ? AppColors.primary : AppColors.muted,
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

// ── Donate block (shown on open donation posts to verified donors) ────────

class _DonateBlock extends StatefulWidget {
  final Post post;
  const _DonateBlock({required this.post});

  @override
  State<_DonateBlock> createState() => _DonateBlockState();
}

class _DonateBlockState extends State<_DonateBlock> {
  double _scale = 1.0;

  Widget _detailRow(IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 14, color: AppColors.primary),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, color: AppColors.foreground),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final hasDate = post.eventDate != null && post.eventDate!.isNotEmpty;
    final hasLocation =
        post.eventLocation != null && post.eventLocation!.isNotEmpty;

    final detailRows = <Widget>[];
    if (hasDate)
      detailRows.add(_detailRow(Icons.event_rounded, post.eventDate!));
    if (hasLocation) {
      if (detailRows.isNotEmpty) detailRows.add(const SizedBox(height: 6));
      detailRows.add(
        _detailRow(Icons.location_on_rounded, post.eventLocation!),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...detailRows,
          if (detailRows.isNotEmpty) const SizedBox(height: 10),
          GestureDetector(
            onTapDown: (_) => setState(() => _scale = 0.97),
            onTapUp: (_) => setState(() => _scale = 1.0),
            onTapCancel: () => setState(() => _scale = 1.0),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BookScreen(
                    showBackButton: true,
                    preselectedFacilityId: post.donationFacilityId,
                  ),
                ),
              );
            },
            child: AnimatedScale(
              scale: _scale,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: Container(
                width: double.infinity,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.primaryDark],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.water_drop, size: 16, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      "Donate Now",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right, size: 18, color: Colors.white),
                  ],
                ),
              ),
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
  bool _verifiedCardDismissed = false;

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
    final donorIdString = prefs.getString('donorId');
    final donorId = int.tryParse(donorIdString ?? '') ?? 0;
    if (!mounted) return;

    final dismissed = donorIdString == null || donorIdString.isEmpty
        ? false
        : prefs.getBool('verified_card_dismissed_$donorIdString') ?? false;

    if (donorId <= 0) {
      setState(() {
        _verificationStatus = 'unverified';
        _checkingVerification = false;
        _verifiedCardDismissed = dismissed;
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
            _verificationStatus =
                (data['verification_status'] as String?) ?? _verificationStatus;
            _checkingVerification = false;
            _verifiedCardDismissed = dismissed;
          });
          return;
        }
      }
      // Unexpected shape/non-200 — keep whatever status we last knew about
      // rather than flashing the unverified card on a network hiccup.
      setState(() {
        _checkingVerification = false;
        _verifiedCardDismissed = dismissed;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _checkingVerification = false;
          _verifiedCardDismissed = dismissed;
        });
      }
    }
  }

  Future<void> _dismissVerifiedCard() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');
    if (donorId == null || donorId.isEmpty) return;
    HapticFeedback.selectionClick();
    await prefs.setBool('verified_card_dismissed_$donorId', true);
    if (!mounted) return;
    setState(() => _verifiedCardDismissed = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Verification card hidden'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('verified_card_dismissed_$donorId');
            if (mounted) setState(() => _verifiedCardDismissed = false);
          },
        ),
      ),
    );
  }

  void _scrollToVerifyCta() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openVerifyScreen() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const VerifyScreen()));
    if (mounted) _fetchVerificationStatus();
  }

  // PIN: "Go to Home" is protected by the eDonate PIN. The PIN screen
  // creates a PIN first if the donor doesn't have one yet, then opens Home.
  // If this newsfeed was opened from an already-unlocked Home screen, just
  // go back to it instead of asking for the PIN again.
  Future<void> _goHome() async {
    final navigator = Navigator.of(context);
    if (AppSession.homeInStack && navigator.canPop()) {
      navigator.pop();
      return;
    }
    HapticFeedback.selectionClick();
    await navigator.push(
      MaterialPageRoute(builder: (_) => const PinScreen()),
    );
    // Back here without unlocking (the user pressed back) — refresh in case
    // anything changed while the PIN screen was open.
    if (mounted) _fetchVerificationStatus();
  }

  Future<void> _loadPosts() async {
    setState(() {
      _loadingPosts = true;
      _postsError = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final donorId = prefs.getString('donorId');
      final posts = await NewsfeedApi.fetchPosts(donorId: donorId);
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
                onRefresh: () =>
                    Future.wait([_loadPosts(), _fetchVerificationStatus()]),
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
    final icon = isPending
        ? Icons.hourglass_top_rounded
        : Icons.info_outline_rounded;
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
                _goHome(); // PIN: ask for (or create) the PIN first
              } else {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
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
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _canDonate =>
      _isLoggedIn &&
      !_checkingVerification &&
      _verificationStatus == 'verified';

  Widget _buildPostsList() {
    if (_loadingPosts) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
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
            OutlinedButton(onPressed: _loadPosts, child: const Text("Retry")),
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
            child: PostCard(
              key: ValueKey(_posts[i].id),
              post: _posts[i],
              canDonate: _canDonate,
            ),
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
          _buildHeaderProfileButton(),
        ],
      ),
    );
  }

  Widget _buildHeaderProfileButton() {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: 'Profile',
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const HistoryScreen())),
        icon: const Icon(
          Icons.person_outline_rounded,
          color: AppColors.muted,
          size: 20,
        ),
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
                      _isLoggedIn
                          ? "Ready to Save a Life?"
                          : "Become a Donor Today",
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
              Icon(
                Icons.water_drop,
                size: 40,
                color: Colors.white.withOpacity(0.3),
              ),
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
    if (_checkingVerification) return const SizedBox.shrink();
    if (_verificationStatus == 'verified' && _verifiedCardDismissed) {
      return const SizedBox.shrink();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          axisAlignment: -1,
          child: child,
        ),
      ),
      child: _VerificationCard(
        key: ValueKey(_verificationStatus),
        status: _verificationStatus,
        onTap: _openVerifyScreen,
        onDismiss: _dismissVerifiedCard,
      ),
    );
  }

  Widget _statChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: Colors.white70),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white70),
        ),
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

// ── Verification status card ────────────────────────────────────────────────

class _VerificationCard extends StatelessWidget {
  final String status;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _VerificationCard({
    super.key,
    required this.status,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'pending':
        return _card(
          icon: Icons.hourglass_top_rounded,
          iconBg: const Color(0xFFFFFBEB),
          accent: const Color(0xFFD97706),
          title: "Verification in Progress",
          subtitle: "We're reviewing your ID — hang tight",
          trailing: _outlinedButton("View", const Color(0xFFD97706)),
        );
      case 'rejected':
        return _card(
          icon: Icons.gpp_bad_outlined,
          iconBg: const Color(0xFFFFF1F1),
          accent: const Color(0xFFDC2626),
          title: "Verification Unsuccessful",
          subtitle: "Please upload a clearer photo of your ID",
          trailing: _filledButton("Retry"),
          borderColor: const Color(0xFFFECACA),
        );
      case 'verified':
        return _verifiedCard();
      case 'unverified':
      default:
        return _card(
          icon: Icons.shield_outlined,
          iconBg: const Color(0xFFFFF1F1),
          accent: const Color(0xFFDC2626),
          title: "Verify Your Identity",
          subtitle: "Upload a valid ID to unlock full access",
          trailing: _outlinedButton("Verify", const Color(0xFFDC2626)),
        );
    }
  }

  Widget _outlinedButton(String label, Color color) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: color.withOpacity(0.3)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );

  Widget _filledButton(String label) => ElevatedButton(
    onPressed: onTap,
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFFDC2626),
      foregroundColor: Colors.white,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );

  Widget _card({
    required IconData icon,
    required Color iconBg,
    required Color accent,
    required String title,
    required String subtitle,
    required Widget trailing,
    Color? borderColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor ?? AppColors.border),
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
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(icon, size: 20, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.foreground,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _verifiedCard() {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF0FDF4), Color(0xFFDCFCE7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFBBF7D0), width: 1.5),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 26),
              child: _verifiedCardRow(),
            ),
            Positioned(
              top: -4,
              right: -8,
              child: Tooltip(
                message: 'Dismiss',
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onDismiss,
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .75),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: Color(0xFF15803D),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _verifiedCardRow() {
    return Row(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.9, end: 1.0),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutBack,
          builder: (_, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFFDCFCE7),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.verified_user_rounded,
              size: 20,
              color: Color(0xFF16A34A),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Identity Verified",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
              Text(
                "Your account has full access to eDonate",
                style: TextStyle(fontSize: 12, color: AppColors.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF16A34A),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded, size: 14, color: Colors.white),
              SizedBox(width: 4),
              Text(
                "Verified",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}