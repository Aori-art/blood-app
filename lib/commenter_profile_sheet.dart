import 'dart:async';

import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'package:flutter/services.dart';

import 'donor_avatar.dart';
import 'post_comments_api.dart';
import 'shared_design.dart' show kCrimson;
import 'skeleton.dart';
import 'streak/streak_controller.dart';

/// Opens the brief profile of the donor behind [comment].
Future<void> showCommenterProfile(
  BuildContext context, {
  required PostComment comment,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CommenterProfileSheet(comment: comment),
  );
}

const List<String> _months = [
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

/// "March 2025" from the server's member-since date (or an already written
/// "March 2025"); null when it can't be read.
String? memberSinceLabel(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final d = DateTime.tryParse(raw.trim());
  if (d != null) return '${_months[d.month - 1]} ${d.year}';
  if (RegExp(r'^[A-Za-z]+ \d{4}$').hasMatch(raw.trim())) return raw.trim();
  return null;
}

/// A compact sheet with what everybody may see about a commenter: photo with
/// frame, display name, a Verified Donor chip and since when they are on
/// eDonate. No contact details and no ids.
class CommenterProfileSheet extends StatefulWidget {
  final PostComment comment;
  const CommenterProfileSheet({super.key, required this.comment});

  @override
  State<CommenterProfileSheet> createState() => _CommenterProfileSheetState();
}

class _CommenterProfileSheetState extends State<CommenterProfileSheet> {
  bool _loading = true;
  ProfileResult? _result;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _result = null;
    });
    final result = await PostCommentsApi.profile(widget.comment.id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 22),
                if (_loading)
                  _skeleton()
                else if (_result?.ok ?? false)
                  _content(_result!.profile!)
                else
                  _problem(_result),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kCrimson,
                      side: const BorderSide(color: kCrimson, width: 1.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(fontWeight: FontWeight.w700),
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

  Widget _skeleton() => const SkeletonPulse(
    child: Column(
      children: [
        SkeletonBox.circle(96),
        SizedBox(height: 16),
        SkeletonBox(width: 150, height: 18),
        SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SkeletonBox(width: 110, height: 28, radius: 14),
            SizedBox(width: 8),
            SkeletonBox(width: 150, height: 28, radius: 14),
          ],
        ),
      ],
    ),
  );

  Widget _content(CommenterProfile p) {
    final name = p.displayName.isEmpty
        ? widget.comment.authorName
        : p.displayName;
    final since = memberSinceLabel(p.memberSince);
    final frameLabel = p.frame == null
        ? null
        : StreakController.instance.frameLabel(p.frame!);
    return Column(
      children: [
        DonorAvatar(
          photoUrl: p.avatar.isEmpty ? widget.comment.avatar : p.avatar,
          name: name,
          frame: p.frame,
          radius: 48,
        ),
        const SizedBox(height: 14),
        Text(
          name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.foreground,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (p.verified)
              _chip(
                icon: Icons.verified_user_rounded,
                text: 'Verified Donor',
                color: AppColors.success,
                bg: AppColors.successBg,
              ),
            if (since != null)
              _chip(
                icon: Icons.calendar_month_rounded,
                text: 'On eDonate since $since',
                color: AppColors.muted,
                bg: AppColors.mutedBg,
              ),
            if (frameLabel != null)
              _chip(
                icon: Icons.workspace_premium_rounded,
                text: frameLabel,
                color: kCrimson,
                bg: AppColors.accentBg,
              ),
          ],
        ),
      ],
    );
  }

  Widget _chip({
    required IconData icon,
    required String text,
    required Color color,
    required Color bg,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );

  // The comment is gone, or the profile could not be loaded.
  Widget _problem(ProfileResult? r) {
    final gone = r?.notFound ?? false;
    return Column(
      children: [
        Icon(
          gone ? Icons.person_off_outlined : Icons.wifi_off_rounded,
          size: 40,
          color: AppColors.muted,
        ),
        const SizedBox(height: 12),
        Text(
          gone
              ? "This profile isn't available."
              : (r?.message ?? "Couldn't load this profile."),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            height: 1.4,
            color: AppColors.muted,
          ),
        ),
        if (!gone) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: _load,
            style: TextButton.styleFrom(foregroundColor: kCrimson),
            child: const Text(
              'Retry',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }
}
