import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'streak/streak_controller.dart';
import 'streak/streak_screen.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'app_colors.dart';
import 'anim.dart';
import 'book.dart';
import 'history.dart';
import 'login.dart';
import 'post_comments.dart';
import 'pin_screen.dart'; // PIN: "Go to Home" now goes through the PIN screen
import 'config.dart';
import 'donor_avatar.dart';
import 'verify.dart';
import 'app_palette.dart';
import 'media_url.dart';
import 'my_avatar_controller.dart';
import 'widgets/image_viewer.dart';
import 'home.dart' show FloatingNavMetrics;
import 'newsfeed/category_nav_bar.dart';
import 'newsfeed/feed_chrome.dart';
import 'newsfeed/post_content_parser.dart';
import 'newsfeed/post_parts.dart';

// Other files import resolveMediaUrl from here.
export 'media_url.dart' show resolveMediaUrl;
import 'widgets/edonate_logo.dart';
// The palette lives in app_colors.dart; it is re-exported so files that took
// AppColors from here keep working.
export 'app_colors.dart';

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
  final int comments;
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
    this.comments = 0,
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
      comments: (json['comments'] as num?)?.toInt() ?? 0,
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
    // Badge fills with white content: the same in both modes.
    final color = isCritical ? AppColors.critical : AppColors.orange;
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
      color: context.palette.surfaceAlt,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: context.palette.muted,
        size: 20,
      ),
    ),
    loadingBuilder: (context, child, progress) {
      if (progress == null) return child;
      return Container(color: context.palette.surfaceAlt);
    },
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
        context.palette.info,
        context.palette.infoBg,
      );
    }
    if (authorType == 'admin') {
      return (
        Icons.verified_rounded,
        context.palette.primaryText,
        context.palette.accentBg,
      );
    }
    return (
      Icons.groups_rounded,
      context.palette.muted,
      context.palette.surfaceAlt,
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
        color: context.palette.surface,
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
        fg: context.palette.info,
        bg: context.palette.infoBg,
        border: context.palette.infoBorder,
      );
    }
    if (profile != null && authorType == 'admin') {
      final label =
          profile['role_label']?.toString() ?? 'Official eDonate Account';
      return _pill(
        icon: Icons.verified_rounded,
        label: label,
        fg: context.palette.primaryText,
        bg: context.palette.accentBg,
        border: context.palette.primaryBorder,
      );
    }
    // Loading / unlinked / error — fall back to whatever badge the post
    // itself carries, until (or unless) the typed profile pill is ready.
    if (widget.post.authorBadge != null) {
      return _pill(
        icon: Icons.emoji_events,
        label: widget.post.authorBadge!,
        fg: context.palette.primaryText,
        bg: context.palette.accentBg,
        border: context.palette.primaryBorder,
      );
    }
    return null;
  }

  Widget _iconBox(IconData icon) => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      color: context.palette.accentBg,
      borderRadius: BorderRadius.circular(10),
    ),
    alignment: Alignment.center,
    child: Icon(icon, size: 16, color: context.palette.primaryText),
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
              Text(
                "Address",
                style: TextStyle(fontSize: 11, color: context.palette.muted),
              ),
              const SizedBox(height: 2),
              Text(
                address,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.palette.foreground,
                ),
              ),
              if (subParts.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subParts.join(', '),
                  style: TextStyle(fontSize: 11, color: context.palette.muted),
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
              Text(
                "Contact",
                style: TextStyle(fontSize: 11, color: context.palette.muted),
              ),
              const SizedBox(height: 2),
              Text(
                contactNumber,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.palette.foreground,
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.copy_rounded, size: 14, color: context.palette.muted),
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
        rows.add(Divider(height: 20, color: context.palette.surfaceAlt));
      rows.add(_contactRow(contact));
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.palette.surfaceAlt,
        border: Border.all(color: context.palette.border),
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
            color: context.palette.accentBg,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                monthLabel,
                style: TextStyle(
                  fontSize: 10,
                  color: context.palette.primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                dayLabel,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.palette.foreground,
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
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.palette.foreground,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: context.palette.muted),
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
        Text(
          "Upcoming Donation Events",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.palette.muted,
          ),
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Text(
            "No upcoming events right now.",
            style: TextStyle(fontSize: 12, color: context.palette.muted),
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
              color: context.palette.warningBg,
              border: Border.all(color: context.palette.warningBorder),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: context.palette.warningText,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "This facility isn't accepting donations right now.",
                    style: TextStyle(
                      fontSize: 11,
                      color: context.palette.warningText,
                    ),
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
      color: context.palette.infoBg,
      border: Border.all(color: context.palette.infoBorder),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_rounded, size: 16, color: context.palette.info),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            "Posts from this account are official announcements from the eDonate team.",
            style: TextStyle(
              fontSize: 12,
              color: context.palette.infoText,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _basicNote() => Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Text(
      "More details about this organization aren't available yet.",
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: context.palette.muted),
    ),
  );

  Widget _loadingPlaceholders() => Column(
    children: [
      Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      const SizedBox(height: 10),
      Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      const SizedBox(height: 10),
      Container(
        width: double.infinity,
        height: 72,
        decoration: BoxDecoration(
          color: context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ],
  );

  Widget _errorSection() => Column(
    children: [
      Icon(Icons.wifi_off_rounded, color: context.palette.muted, size: 28),
      const SizedBox(height: 8),
      Text(
        "Couldn't load this profile",
        style: TextStyle(fontSize: 13, color: context.palette.muted),
      ),
      const SizedBox(height: 10),
      TextButton.icon(
        onPressed: _fetchProfile,
        icon: Icon(
          Icons.refresh_rounded,
          size: 16,
          color: context.palette.primaryText,
        ),
        label: Text(
          "Retry",
          style: TextStyle(
            color: context.palette.primaryText,
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
        decoration: BoxDecoration(
          color: context.palette.surface,
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
                  color: context.palette.border,
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
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: context.palette.foreground,
                ),
              ),
              if (pill != null) ...[const SizedBox(height: 8), pill],
              if (memberSince != null) ...[
                const SizedBox(height: 8),
                Text(
                  "On eDonate since $memberSince",
                  style: TextStyle(fontSize: 12, color: context.palette.muted),
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
                    foregroundColor: context.palette.primaryText,
                    side: BorderSide(color: context.palette.primaryText),
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

  // Who is looking: decides what the comments sheet offers (write, verify
  // first, or sign in). Reading and sharing are open to everyone.
  final bool isLoggedIn;
  final String verificationStatus;

  // Called when the comments sheet learns the donor's verification changed.
  final VoidCallback? onVerificationChanged;

  const PostCard({
    super.key,
    required this.post,
    this.canDonate = false,
    this.isLoggedIn = false,
    this.verificationStatus = 'unverified',
    this.onVerificationChanged,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late bool liked;
  late int likeCount;
  late int commentCount;
  double _likeIconScale = 1.0;

  // The text split into title, info rows and body, read once per text.
  late ParsedPost _parsed = parsePostContent(widget.post.content);

  @override
  void initState() {
    super.initState();
    liked = widget.post.liked;
    likeCount = widget.post.likes;
    commentCount = widget.post.comments;
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.content != widget.post.content) {
      _parsed = parsePostContent(widget.post.content);
    }
    if (oldWidget.post.liked != widget.post.liked ||
        oldWidget.post.likes != widget.post.likes) {
      setState(() {
        liked = widget.post.liked;
        likeCount = widget.post.likes;
      });
    }
    if (oldWidget.post.comments != widget.post.comments) {
      setState(() => commentCount = widget.post.comments);
    }
  }

  void _openComments() {
    HapticFeedback.selectionClick();
    showPostComments(
      context,
      postId: widget.post.id,
      isLoggedIn: widget.isLoggedIn,
      verificationStatus: widget.verificationStatus,
      total: commentCount,
      onTotalChanged: (total) {
        if (mounted && total != commentCount) {
          setState(() => commentCount = total);
        }
      },
      onVerificationChanged: widget.onVerificationChanged,
    );
  }

  // The text that gets shared: built from the post only, nothing about the
  // person sharing it.
  String _shareText() {
    final post = widget.post;
    String? field(String? v) =>
        (v == null || v.trim().isEmpty) ? null : v.trim();
    final lines = <String>[
      '${post.author} on eDonate:',
      post.content,
      if (field(post.eventDate) != null) 'Date: ${field(post.eventDate)}',
      if (field(post.eventLocation) != null)
        'Location: ${field(post.eventLocation)}',
      if (field(post.bloodType) != null)
        'Blood type needed: ${field(post.bloodType)}',
      if (field(post.hospital) != null) 'Hospital: ${field(post.hospital)}',
      if (resolveMediaUrl(post.image) != null) resolveMediaUrl(post.image)!,
      'Every drop counts. Every life matters. #eDonate',
    ];
    return lines.join('\n');
  }

  Future<void> _handleShare(BuildContext buttonContext) async {
    HapticFeedback.lightImpact();
    Rect? origin;
    final box = buttonContext.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      origin = box.localToGlobal(Offset.zero) & box.size;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(text: _shareText(), sharePositionOrigin: origin),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't open the share sheet. Please try again."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _countLabel(int n, String one, String many) =>
      '${formatCount(n)} ${n == 1 ? one : many}';

  Future<void> _handleLike() async {
    final wasLiked = liked;
    final previousCount = likeCount;

    HapticFeedback.lightImpact();
    setState(() {
      liked = !liked;
      likeCount += liked ? 1 : -1;
    });
    if (liked && !MediaQuery.disableAnimationsOf(context)) {
      // A quick pop: 1 → 1.3 → 1 in about 250 ms.
      setState(() => _likeIconScale = 1.3);
      Future.delayed(const Duration(milliseconds: 125), () {
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

  // A double tap on the photo only ever likes; it never takes a like back.
  void _likeFromImage() {
    if (!liked) _handleLike();
  }

  void _copyText() {
    Clipboard.setData(ClipboardData(text: widget.post.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openDonate() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookScreen(
          showBackButton: true,
          preselectedFacilityId: widget.post.donationFacilityId,
        ),
      ),
    );
  }

  // ── Reading the post ───────────────────────────────────────────────────

  bool get _isOfficial =>
      widget.post.authorType == 'admin' || widget.post.authorType == 'facility';

  static String? _field(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v.trim();

  /// The rows for the info panel: what the text lists, plus the post's own
  /// date and place when the text leaves them out. Status gets a chip.
  List<InfoRow> _infoRows() {
    final post = widget.post;
    final rows = _parsed.rows.where((r) => r.kind != InfoKind.status).toList();
    final date = _field(post.eventDate);
    if (date != null && _parsed.row(InfoKind.date) == null) {
      rows.insert(0, InfoRow(kind: InfoKind.date, label: 'Date', value: date));
    }
    final place = _field(post.eventLocation);
    if (place != null && _parsed.row(InfoKind.location) == null) {
      rows.add(
        InfoRow(kind: InfoKind.location, label: 'Location', value: place),
      );
    }
    return rows;
  }

  String? get _status {
    final post = widget.post;
    final written = _parsed.row(InfoKind.status)?.value;
    // The server's flag wins over text that still says "Open".
    if (post.isDonation &&
        !post.donationOpen &&
        (written == null || written.toLowerCase().contains('open'))) {
      return 'Closed';
    }
    if (written != null) return written;
    if (post.type == PostType.event && post.isDonation) {
      return post.donationOpen ? 'Open' : 'Closed';
    }
    return null;
  }

  /// What a screen reader hears for the header, e.g. "Official event by
  /// eDonate, 1 week ago, Capstone, Mon, October 12, 2026, Open".
  String _summary(List<InfoRow> rows) {
    final post = widget.post;
    final kind = switch (post.type) {
      PostType.event => 'event',
      PostType.urgent => 'urgent request',
      PostType.milestone => 'milestone',
      PostType.story => 'post',
    };
    final who = '${_isOfficial ? 'Official ' : ''}$kind by ${post.author}';
    final date = rows.where((r) => r.kind == InfoKind.date).firstOrNull;
    return [
      who[0].toUpperCase() + who.substring(1),
      post.timeAgo,
      _parsed.title,
      date?.value,
      _status,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');
  }

  // ── Look ───────────────────────────────────────────────────────────────

  Widget _avatar(BuildContext context) {
    final p = context.palette;
    final post = widget.post;
    final url = post.authorAvatar.trim();
    final Widget face;
    if (url.isNotEmpty) {
      face = netImage(url);
    } else if (post.authorType == 'admin') {
      face = ColoredBox(
        color: p.surface,
        child: const Padding(
          padding: EdgeInsets.all(3),
          child: EdonateLogo(size: 34),
        ),
      );
    } else {
      final name = post.author.trim();
      face = ColoredBox(
        color: p.accentBg,
        child: Center(
          child: Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: p.primaryText,
            ),
          ),
        ),
      );
    }

    final photo = Hero(
      tag: 'author_avatar_${post.id}',
      child: ClipOval(child: face),
    );
    if (!_isOfficial) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: p.border),
        ),
        child: photo,
      );
    }
    // Official posters: a brand ring and a check.
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: AppColors.primaryGradient,
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                color: p.surface,
                shape: BoxShape.circle,
              ),
              child: photo,
            ),
          ),
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: p.surface, width: 2),
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 10,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  ({String label, Color bg, Color fg}) _typeStyle(AppPalette p) =>
      switch (widget.post.type) {
        PostType.event => (label: 'EVENT', bg: p.accentBg, fg: p.primaryText),
        PostType.urgent => (
          label: 'URGENT',
          bg: AppColors.critical.withValues(alpha: p.isDark ? 0.18 : 0.08),
          fg: p.criticalText,
        ),
        PostType.milestone => (
          label: 'MILESTONE',
          bg: p.warningBg,
          fg: p.warningText,
        ),
        PostType.story => (label: 'STORY', bg: p.infoBg, fg: p.infoText),
      };

  Widget _header(BuildContext context, List<InfoRow> rows) {
    final p = context.palette;
    final post = widget.post;
    final type = _typeStyle(p);
    final badge = _field(post.authorBadge) ?? (_isOfficial ? 'Official' : null);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: _summary(rows),
            excludeSemantics: true,
            child: InkWell(
              onTap: () => _showPosterPreview(context, post: post),
              borderRadius: BorderRadius.circular(14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    _avatar(context),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  post.author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: p.foreground,
                                  ),
                                ),
                              ),
                              if (_isOfficial) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.verified_rounded,
                                  size: 16,
                                  color: p.primaryText,
                                ),
                              ],
                              if (post.type != PostType.urgent &&
                                  post.urgency != null) ...[
                                const SizedBox(width: 6),
                                UrgencyBadge(urgency: post.urgency!),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (badge != null) ...[
                                Text(
                                  badge,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: p.primaryText,
                                  ),
                                ),
                                Text(
                                  '·',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: p.muted,
                                  ),
                                ),
                              ],
                              Text(
                                post.timeAgo,
                                style: TextStyle(fontSize: 12, color: p.muted),
                              ),
                              Text(
                                '·',
                                style: TextStyle(fontSize: 12, color: p.muted),
                              ),
                              PostTypeChip(
                                label: type.label,
                                background: type.bg,
                                foreground: type.fg,
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
          ),
        ),
        _moreButton(context),
      ],
    );
  }

  Widget _moreButton(BuildContext context) {
    final p = context.palette;
    Widget item(IconData icon, String label) => Row(
      children: [
        Icon(icon, size: 20, color: p.muted),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontSize: 14, color: p.foreground)),
      ],
    );
    return Builder(
      builder: (buttonContext) => PopupMenuButton<String>(
        tooltip: 'More options',
        icon: Icon(Icons.more_horiz_rounded, color: p.muted),
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.border),
        ),
        onSelected: (value) {
          if (value == 'share') {
            _handleShare(buttonContext);
          } else {
            _copyText();
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'share',
            child: item(Icons.ios_share_rounded, 'Share post'),
          ),
          PopupMenuItem(
            value: 'copy',
            child: item(Icons.copy_rounded, 'Copy text'),
          ),
        ],
      ),
    );
  }

  /// The post's words, laid out for its kind.
  List<Widget> _content(BuildContext context, List<InfoRow> rows) {
    final p = context.palette;
    final post = widget.post;
    final bodyStyle = TextStyle(
      fontSize: 14.5,
      height: 1.5,
      color: p.foreground,
    );
    final out = <Widget>[];

    if (rows.isNotEmpty) {
      // Event: date tile and title, the details, then the note.
      final date = rows.where((r) => r.kind == InfoKind.date).firstOrNull;
      final status = _status;
      out.add(
        Row(
          children: [
            EventDateTile(date: date?.value),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _parsed.title ??
                        (post.type == PostType.event
                            ? 'Blood donation event'
                            : post.author),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: p.foreground,
                    ),
                  ),
                  if (status != null) ...[
                    const SizedBox(height: 6),
                    EventStatusChip(status: status),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
      out.add(EventInfoPanel(rows: rows));
      if (_parsed.body.isNotEmpty) out.add(PostNote(text: _parsed.body));
    } else if (post.type == PostType.milestone) {
      // Milestone: the first line in the gold band, the rest below.
      final lines = post.content.trim().split('\n');
      final headline = stripLeadingEmoji(lines.first);
      final rest = lines.skip(1).join('\n').trim();
      if (headline.isNotEmpty) out.add(MilestoneBand(headline: headline));
      if (rest.isNotEmpty) out.add(ExpandableText(rest, style: bodyStyle));
    } else if (post.content.trim().isNotEmpty) {
      out.add(
        ExpandableText(
          post.content.trim(),
          style: post.type == PostType.story
              ? TextStyle(fontSize: 15, height: 1.55, color: p.foreground)
              : bodyStyle,
        ),
      );
    }

    if (post.type == PostType.urgent &&
        (_field(post.bloodType) != null || _field(post.hospital) != null)) {
      out.add(
        UrgentNeedRow(
          bloodType: _field(post.bloodType),
          hospital: _field(post.hospital),
        ),
      );
    }
    return out;
  }

  Widget _actions() {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: ActionPill(
            icon: liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            label: likeCount > 0 ? 'Like ${formatCount(likeCount)}' : 'Like',
            semanticLabel: 'Like, ${_countLabel(likeCount, 'like', 'likes')}',
            toggled: liked,
            active: liked,
            iconScale: _likeIconScale,
            onTap: (_) => _handleLike(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          // A little wider: "Comment 12" is the longest label.
          flex: 6,
          child: ActionPill(
            icon: Icons.mode_comment_outlined,
            label: commentCount > 0
                ? 'Comment ${formatCount(commentCount)}'
                : 'Comment',
            semanticLabel:
                'Comment, ${_countLabel(commentCount, 'comment', 'comments')}',
            onTap: (_) => _openComments(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 5,
          child: ActionPill(
            icon: Icons.ios_share_rounded,
            label: 'Share',
            semanticLabel: 'Share',
            onTap: _handleShare,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final post = widget.post;
    final rows = _infoRows();
    final image = post.image;

    final sections = <Widget>[
      _header(context, rows),
      ..._content(context, rows),
      if (image != null)
        PostImage(
          url: image,
          heroTag: 'post_image_${post.id}_0',
          onOpen: () => openImageViewer(
            context,
            imageUrls: [image],
            initialIndex: 0,
            heroTagPrefix: 'post_image_${post.id}',
          ),
          onDoubleTap: _likeFromImage,
        ),
      // Donate Now — only for open donation posts, and only when the viewer
      // is a verified, logged-in donor. It glows on urgent posts.
      if (post.isDonation && post.donationOpen && widget.canDonate)
        DonateNowButton(
          onPressed: _openDonate,
          glow: post.type == PostType.urgent,
        ),
    ];

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: p.border),
          boxShadow: p.shadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (post.type == PostType.urgent)
              UrgentBand(
                level: switch (post.urgency) {
                  Urgency.critical => 'CRITICAL',
                  Urgency.high => 'HIGH',
                  _ => null,
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < sections.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    sections[i],
                  ],
                  const SizedBox(height: 12),
                  Divider(height: 1, thickness: 1, color: p.border),
                  const SizedBox(height: 4),
                  _actions(),
                ],
              ),
            ),
          ],
        ),
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
  double _lastScrollOffset = 0;

  // Scrolling only moves these two notifiers; nothing rebuilds the feed.
  /// "Go to Home" shows at the top and when scrolling back up, and hides
  /// while scrolling down.
  final ValueNotifier<bool> goHomeVisible = ValueNotifier(true);

  /// The header gets its shadow once the feed has moved under it.
  final ValueNotifier<bool> _scrolled = ValueNotifier(false);

  // The category that is selected, and the one the list shows. The list
  // fades out, switches, then fades back in.
  FeedCategory _filter = FeedCategory.all;
  FeedCategory _shownFilter = FeedCategory.all;
  bool _listVisible = true;
  Timer? _filterTimer;

  // Posts per category and the categories that exist, worked out once per
  // load of the feed.
  Map<FeedCategory, int> _counts = const {};
  List<FeedCategory> _categories = const [];

  // Where the list of posts starts (just below the welcome cards).
  final GlobalKey _postsKey = GlobalKey();

  // True while the feed scrolls itself after a category is tapped: those
  // moves must not flip "Go to Home" back. [_scrollSeq] tells the latest
  // such scroll from an earlier one that was replaced.
  bool _programmaticScroll = false;
  int _scrollSeq = 0;

  // Posts that have already played their entrance.
  final Set<int> _entered = {};
  // Only the cards on screen when the feed first shows slide in one after
  // another; any card built after that frame just fades in.
  bool _staggerDone = false;

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
    _filterTimer?.cancel();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    goHomeVisible.dispose();
    _scrolled.dispose();
    super.dispose();
  }

  /// There is a category bar to show: the feed has loaded and has more than
  /// one kind of post.
  bool get _barAvailable =>
      !_loadingPosts && _postsError == null && _categories.isNotEmpty;

  void _handleScroll() {
    final offset = _scrollController.offset;
    final delta = offset - _lastScrollOffset;
    _lastScrollOffset = offset;

    _scrolled.value = offset > 2;

    // The feed scrolling itself says nothing about which way the donor goes.
    if (_programmaticScroll) return;

    // A list too short to scroll (a bounce on iOS still reports offsets):
    // inside a category the bar stays, so the donor is never stuck in a
    // filter; with All selected it is the top of the feed again.
    if (_barAvailable && _scrollController.position.maxScrollExtent <= 0) {
      goHomeVisible.value = _filter == FeedCategory.all;
      return;
    }

    if (offset <= 0) {
      goHomeVisible.value = true;
      return;
    }
    if (delta > 6 && goHomeVisible.value) {
      goHomeVisible.value = false;
    } else if (delta < -6 && !goHomeVisible.value) {
      goHomeVisible.value = true;
    }
  }

  /// After the list changed: when it is too short to scroll there are no
  /// scroll events to go by, so decide here (see [_handleScroll]).
  void _settleBar() {
    if (!mounted || !_scrollController.hasClients) return;
    if (_barAvailable && _scrollController.position.maxScrollExtent <= 0) {
      goHomeVisible.value = _filter == FeedCategory.all;
    }
  }

  /// A scroll the feed makes itself is over (or was given up).
  void _endProgrammatic() {
    _scrollSeq++;
    _programmaticScroll = false;
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool('isLoggedIn') ?? false;
    final donorId = prefs.getString('donorId');
    final signedIn = loggedIn && donorId != null && donorId.isNotEmpty;
    // The cached photo path first, so the header has the picture straight
    // away; the server's answer follows.
    if (signedIn) await MyAvatarController.instance.loadCached();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = signedIn;
      _userName = prefs.getString('userName');
      _checkedLogin = true;
    });
    if (signedIn) unawaited(MyAvatarController.instance.refresh());
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
          // A verified ID unlocks the Verified Donor frame: make sure the
          // streak has the latest instead of trusting an older cache.
          if (_verificationStatus == 'verified') {
            unawaited(StreakController.instance.refresh());
          }
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
    await navigator.push(MaterialPageRoute(builder: (_) => const PinScreen()));
    // Back here without unlocking (the user pressed back) — refresh in case
    // anything changed while the PIN screen was open.
    if (mounted) _fetchVerificationStatus();
  }

  Future<void> _loadPosts() async {
    setState(() {
      _loadingPosts = true;
      _postsError = null;
    });
    // The newsfeed loading is also when the header photo gets refreshed.
    unawaited(MyAvatarController.instance.refresh());
    try {
      final prefs = await SharedPreferences.getInstance();
      final donorId = prefs.getString('donorId');
      final posts = await NewsfeedApi.fetchPosts(donorId: donorId);
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loadingPosts = false;
        final counts = <FeedCategory, int>{FeedCategory.all: posts.length};
        for (final p in posts) {
          final group = FeedCategory.of(p.type.name);
          counts[group] = (counts[group] ?? 0) + 1;
        }
        _counts = counts;
        _categories = FeedCategory.available(posts.map((p) => p.type.name));
        // A group that is gone after a refresh falls back to "All".
        if (_filter != FeedCategory.all && !_categories.contains(_filter)) {
          _filterTimer?.cancel();
          _endProgrammatic();
          _filter = _shownFilter = FeedCategory.all;
          _listVisible = true;
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _settleBar());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _postsError = "Couldn't load the feed.";
        _loadingPosts = false;
        _categories = const [];
      });
    }
  }

  @override
  Widget build(BuildContext context) =>
      StreakScreen(id: 'newsfeed', child: _buildScreen(context));

  Widget _buildScreen(BuildContext context) {
    // The bar floats over the feed (like Home's nav), so the feed ends with
    // room for it: the bar, its margins and a little air.
    final barRoom =
        CategoryNavBar.largeTextHeight +
        FloatingNavMetrics.bottomMargin +
        MediaQuery.paddingOf(context).bottom +
        16;
    return Scaffold(
      backgroundColor: context.palette.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  _buildHeader(context),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () => Future.wait([
                        _loadPosts(),
                        _fetchVerificationStatus(),
                      ]),
                      child: _buildFeed(
                        context,
                        bottomSpace: _barAvailable ? barRoom : 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // The category bar and "Go to Home" take turns: the bar is on
          // screen exactly when "Go to Home" is away.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ValueListenableBuilder<bool>(
              valueListenable: goHomeVisible,
              builder: (context, goHome, _) => CategoryNavBar(
                items: _categories,
                selected: _filter,
                counts: _counts,
                onSelected: _selectCategory,
                visible: _barAvailable && !goHome,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFabArea(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // ── FAB slot: "Go to Home"/"Sign In" button, or a quiet status banner ───
  Widget? _buildFabArea(BuildContext context) {
    final Widget Function(BuildContext, bool) build;
    if (!_isLoggedIn) {
      build = _buildHomeFab;
    } else if (_checkingVerification) {
      return null;
    } else if (_verificationStatus == 'verified') {
      build = _buildHomeFab;
    } else {
      build = _buildVerificationBanner;
    }
    // Only this button follows the scroll; the rest of the screen stays put.
    return ValueListenableBuilder<bool>(
      valueListenable: goHomeVisible,
      builder: (context, visible, _) => build(context, visible),
    );
  }

  Widget _buildVerificationBanner(BuildContext context, bool fabVisible) {
    final isPending = _verificationStatus == 'pending';
    final bg = isPending
        ? context.palette.warningBg
        : context.palette.surfaceAlt;
    final border = isPending
        ? context.palette.warningBorder
        : context.palette.border;
    final fg = isPending ? context.palette.warningText : context.palette.muted;
    final icon = isPending
        ? Icons.hourglass_top_rounded
        : Icons.info_outline_rounded;
    final text = isPending
        ? "Home unlocks once your ID is verified"
        : "Verify your ID to unlock the rest of the app";

    return AnimatedSlide(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      offset: fabVisible ? Offset.zero : const Offset(0, 2),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        opacity: fabVisible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !fabVisible,
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
  Widget _buildHomeFab(BuildContext context, bool fabVisible) {
    final label = _isLoggedIn ? "Go to Home" : "Sign In to Donate";

    return AnimatedSlide(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      offset: fabVisible ? Offset.zero : const Offset(0, 2),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        opacity: fabVisible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !fabVisible,
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
                  colors: AppColors.primaryGradient,
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

  /// A category was tapped: the list switches to it, the feed scrolls so its
  /// first post sits under the header, and the category bar stays on screen
  /// (it is "Go to Home" that gives way).
  void _selectCategory(FeedCategory f) {
    HapticFeedback.selectionClick();
    _filterTimer?.cancel();
    // Set before anything moves, so none of it reads as the donor scrolling.
    final seq = ++_scrollSeq;
    _programmaticScroll = true;
    goHomeVisible.value = false;

    if (f == _filter && f == _shownFilter) {
      _scrollToPosts(seq);
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _filter = _shownFilter = f);
      _scrollToPosts(seq);
      return;
    }
    setState(() {
      _filter = f;
      _listVisible = false;
    });
    _filterTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() {
        _shownFilter = _filter;
        _listVisible = true;
      });
      _scrollToPosts(seq);
    });
  }

  Future<void> _scrollToPosts(int seq) async {
    try {
      // Let the new list lay out first.
      await WidgetsBinding.instance.endOfFrame;
      final anchor = _postsKey.currentContext;
      if (!mounted || anchor == null || !anchor.mounted) return;
      if (!_scrollController.hasClients) return;
      await Scrollable.ensureVisible(
        anchor,
        alignment: 0,
        duration: MediaQuery.disableAnimationsOf(anchor)
            ? Duration.zero
            : const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } finally {
      // Only the latest scroll gives the buttons back to the donor.
      if (seq == _scrollSeq) {
        _programmaticScroll = false;
        _settleBar();
      }
    }
  }

  /// The feed: the welcome cards and filter chips, then one row per post,
  /// built as it scrolls into view.
  Widget _buildFeed(BuildContext context, {required double bottomSpace}) {
    final top = <Widget>[
      FadeSlideIn(index: 0, child: _buildSignInCta(context)),
      if (_isLoggedIn) FadeSlideIn(index: 1, child: _buildVerifyIdCta(context)),
      const SizedBox(height: 8),
    ];

    Widget? message;
    if (_loadingPosts) {
      message = const FeedSkeleton();
    } else if (_postsError != null) {
      message = FeedMessage(message: _postsError!, onRetry: _loadPosts);
    } else if (_posts.isEmpty) {
      message = const FeedMessage(message: 'No posts yet. Check back soon!');
    }
    final shown = message != null
        ? const <Post>[]
        : _posts.where((p) => _shownFilter.matches(p.type.name)).toList();
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(child: Column(children: top)),
        // Where the posts start: a category tap scrolls here.
        SliverToBoxAdapter(
          child: Column(key: _postsKey, children: const [SizedBox(height: 8)]),
        ),
        if (message != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: message,
            ),
          )
        else
          SliverList.builder(
            itemCount: shown.length + 1,
            // Cards keep their state (likes, Read more) when a filter moves
            // them.
            findChildIndexCallback: (key) {
              if (key is! ValueKey<String>) return null;
              final i = shown.indexWhere((p) => 'post-${p.id}' == key.value);
              return i < 0 ? null : i;
            },
            itemBuilder: (context, i) {
              if (i == shown.length) {
                return AnimatedOpacity(
                  opacity: _listVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: const CaughtUpFooter(),
                );
              }
              return KeyedSubtree(
                key: ValueKey('post-${shown[i].id}'),
                child: AnimatedOpacity(
                  opacity: _listVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _entrance(i, shown[i]),
                  ),
                ),
              );
            },
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: bottomSpace > 110 ? bottomSpace : 110),
        ),
      ],
    );
  }

  /// The first cards slide in one after another; cards further down fade in
  /// the first time they are built. A card plays its entrance only once.
  Widget _entrance(int i, Post post) {
    final card = PostCard(
      key: ValueKey(post.id),
      post: post,
      canDonate: _canDonate,
      isLoggedIn: _isLoggedIn,
      verificationStatus: _verificationStatus,
      onVerificationChanged: _fetchVerificationStatus,
    );
    if (!_entered.add(post.id)) return card;
    if (i < 6 && !_staggerDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _staggerDone = true);
      return FadeSlideIn(index: i, child: card);
    }
    return FadeSlideIn(child: card);
  }

  Widget _buildHeader(BuildContext context) {
    final p = context.palette;
    // Flat at the top; a soft shadow (a hairline in dark) fades in once the
    // feed scrolls under it.
    return ValueListenableBuilder<bool>(
      valueListenable: _scrolled,
      builder: (context, scrolled, child) => AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        decoration: BoxDecoration(
          color: p.surface,
          border: Border(
            bottom: BorderSide(
              color: scrolled && p.isDark ? p.border : p.border.withAlpha(0),
            ),
          ),
          boxShadow: scrolled ? p.shadow : const [],
        ),
        child: child,
      ),
      child: Row(
        children: [
          const EdonateLogo(),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: "e",
                      style: TextStyle(
                        color: context.palette.primaryText,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    TextSpan(
                      text: "Donate",
                      style: TextStyle(
                        color: context.palette.foreground,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                "BLOOD DONATION NETWORK",
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: context.palette.muted,
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

  Future<void> _openProfile() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HistoryScreen()));
    // The photo or frame may have changed over there.
    if (mounted) unawaited(MyAvatarController.instance.refresh());
  }

  Widget _buildHeaderProfileButton() {
    // Until the login check is done, leave the spot empty instead of flashing
    // the default icon at a signed-in donor.
    if (!_checkedLogin) return const SizedBox(width: 36, height: 36);

    if (!_isLoggedIn) {
      return SizedBox(
        width: 36,
        height: 36,
        child: IconButton(
          padding: EdgeInsets.zero,
          tooltip: 'Profile',
          onPressed: _openProfile,
          icon: Icon(
            Icons.person_outline_rounded,
            color: context.palette.muted,
            size: 20,
          ),
        ),
      );
    }

    // The donor's own photo and frame. The header keeps its height: the ring of
    // a frame may poke a little past the 36 px box, which is only paint.
    return ListenableBuilder(
      listenable: Listenable.merge([
        MyAvatarController.instance,
        StreakController.instance,
      ]),
      builder: (context, _) {
        final me = MyAvatarController.instance;
        final frame = me.viewerFrame;
        return SizedBox(
          width: 36,
          height: 36,
          child: Semantics(
            label: 'Open my profile',
            button: true,
            excludeSemantics: true,
            child: InkResponse(
              onTap: _openProfile,
              radius: 22,
              child: OverflowBox(
                minWidth: 0,
                minHeight: 0,
                maxWidth: 48,
                maxHeight: 48,
                child: Center(
                  child: DonorAvatar(
                    photoUrl: me.avatarPath,
                    name: me.name.isNotEmpty ? me.name : (_userName ?? ''),
                    frame: frame,
                    radius: frame != null ? 15 : 17,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSignInCta(BuildContext context) {
    // Avoid flashing the CTA before we've checked login state
    if (!_checkedLogin) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.primaryGradient,
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
                        color: AppColors.onPrimarySoft,
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
                        fontSize: 17,
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
                        color: AppColors.onPrimarySoft,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.water_drop,
                size: 34,
                color: Colors.white.withOpacity(0.3),
              ),
            ],
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
        Icon(icon, size: 11, color: AppColors.onPrimarySoft),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.onPrimarySoft),
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
          context,
          icon: Icons.hourglass_top_rounded,
          iconBg: context.palette.warningBg,
          accent: context.palette.warning,
          title: "Verification in Progress",
          subtitle: "We're reviewing your ID — hang tight",
          trailing: _outlinedButton("View", context.palette.warning),
        );
      case 'rejected':
        return _card(
          context,
          icon: Icons.gpp_bad_outlined,
          iconBg: context.palette.accentBg,
          accent: context.palette.criticalText,
          title: "Verification Unsuccessful",
          subtitle: "Please upload a clearer photo of your ID",
          trailing: _filledButton(context, "Retry"),
          borderColor: context.palette.primaryBorder,
        );
      case 'verified':
        return _verifiedCard(context);
      case 'unverified':
      default:
        return _card(
          context,
          icon: Icons.shield_outlined,
          iconBg: context.palette.accentBg,
          accent: context.palette.primaryText,
          title: "Verify Your Identity",
          subtitle: "Upload a valid ID to unlock full access",
          trailing: _outlinedButton("Verify", context.palette.primaryText),
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

  Widget _filledButton(BuildContext context, String label) => ElevatedButton(
    onPressed: onTap,
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      disabledBackgroundColor: context.palette.border,
      disabledForegroundColor: context.palette.muted,
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

  Widget _card(
    BuildContext context, {
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
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor ?? context.palette.border),
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
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.palette.foreground,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
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

  Widget _verifiedCard(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [context.palette.successBg, context.palette.successSoft],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.palette.successBorder, width: 1.5),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 26),
              child: _verifiedCardRow(context),
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
                      color: context.palette.surface.withValues(alpha: .75),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: context.palette.successDark,
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

  Widget _verifiedCardRow(BuildContext context) {
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
            decoration: BoxDecoration(
              color: context.palette.successSoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.verified_user_rounded,
              size: 20,
              color: context.palette.success,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Identity Verified",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.palette.foreground,
                ),
              ),
              Text(
                "Your account has full access to eDonate",
                style: TextStyle(fontSize: 12, color: context.palette.muted),
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
            color: AppColors.success,
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
