// The preview sheets that open when a stat card on Home is tapped: the blood
// type with who it can give to and receive from, the donations with the
// latest ones and the next milestone, and the lives saved.
//
// Nothing here talks to the server except the donations sheet, which loads
// the history with the same call as the History tab.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'anim.dart';
import 'app_colors.dart';
import 'app_palette.dart';
import 'book.dart';
import 'donation_history.dart';
import 'donation_history_data.dart';
import 'history.dart';
import 'home_nav.dart';
import 'shared_design.dart' show PrimaryButton;
import 'skeleton.dart';
import 'widgets/count_up_text.dart';

enum StatKind { bloodType, donations, lives }

/// The milestones the donations sheet counts toward.
const List<int> kDonationMilestones = [1, 3, 5, 10];

/// Opens the preview for [kind]. [bloodType] and [donations] are what Home
/// already knows.
Future<void> showStatPreview(
  BuildContext context,
  StatKind kind, {
  required String? bloodType,
  required int donations,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => StatPreviewSheet(
      kind: kind,
      bloodType: bloodType,
      donations: donations,
    ),
  );
}

// ── Blood type matching ─────────────────────────────────────────────────────

/// The eight types, in the order the chips list them.
const List<String> kBloodTypes = [
  'O-',
  'O+',
  'A-',
  'A+',
  'B-',
  'B+',
  'AB-',
  'AB+',
];

/// "A+", "ab -", "O positive" -> "A+" / "AB-" / "O+"; null when it is not one
/// of the eight types (unset, "N/A", "-", ...).
String? normalizeBloodType(String? raw) {
  final text = (raw ?? '').trim().toUpperCase();
  final m = RegExp(
    r'^(AB|A|B|O)\s*(\+|-|POS(?:ITIVE)?|NEG(?:ATIVE)?)$',
  ).firstMatch(text);
  if (m == null) return null;
  final sign = m.group(2)!;
  return '${m.group(1)}${sign.startsWith('P') || sign == '+' ? '+' : '-'}';
}

// The antigens of a type: A, B and Rh. Red cells can go from a donor to a
// recipient when the donor's antigens are a subset of the recipient's.
Set<String> _antigens(String type) => {
  if (type.startsWith('A')) 'A',
  if (type.contains('B')) 'B',
  if (type.endsWith('+')) 'Rh',
};

/// Who [bloodType] can give red cells to, and receive them from, in the
/// order of [kBloodTypes]; null for an unknown type.
({List<String> giveTo, List<String> receiveFrom})? bloodCompatibility(
  String? bloodType,
) {
  final type = normalizeBloodType(bloodType);
  if (type == null) return null;
  final mine = _antigens(type);
  return (
    giveTo: [
      for (final other in kBloodTypes)
        if (mine.every(_antigens(other).contains)) other,
    ],
    receiveFrom: [
      for (final other in kBloodTypes)
        if (_antigens(other).every(mine.contains)) other,
    ],
  );
}

// ── The sheet ───────────────────────────────────────────────────────────────

class StatPreviewSheet extends StatefulWidget {
  const StatPreviewSheet({
    super.key,
    required this.kind,
    required this.bloodType,
    required this.donations,
  });

  final StatKind kind;
  final String? bloodType;
  final int donations;

  @override
  State<StatPreviewSheet> createState() => _StatPreviewSheetState();
}

enum _Load { loading, done, failed }

class _StatPreviewSheetState extends State<StatPreviewSheet> {
  _Load _load = _Load.loading;
  List<Map<String, dynamic>> _recent = const [];

  @override
  void initState() {
    super.initState();
    if (widget.kind == StatKind.donations) _loadDonations();
  }

  Future<void> _loadDonations() async {
    setState(() => _load = _Load.loading);
    try {
      final prefs = await SharedPreferences.getInstance();
      final donorId = prefs.getString('donorId');
      final all = donorId == null || donorId.isEmpty
          ? <Map<String, dynamic>>[]
          : await DonationHistoryApi.fetch(donorId);
      if (!mounted) return;
      setState(() {
        _recent = all.take(3).toList();
        _load = _Load.done;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _load = _Load.failed);
    }
  }

  // ── Leaving the sheet ───────────────────────────────────────────────────

  /// Closes the sheet, then runs [go] with the navigator that was under it.
  void _thenGo(void Function(NavigatorState navigator) go) {
    final navigator = Navigator.of(context);
    navigator.pop();
    go(navigator);
  }

  void _goToTab(HomeTab tab, Widget Function() fallbackScreen) {
    _thenGo((navigator) {
      if (HomeNav.goTo(tab)) return;
      navigator.push(MaterialPageRoute(builder: (_) => fallbackScreen()));
    });
  }

  void _openHistory() =>
      _goToTab(HomeTab.history, () => const DonationHistoryScreen());

  void _openBook() =>
      _goToTab(HomeTab.book, () => const BookScreen(showBackButton: true));

  void _openProfile() => _thenGo(
    (navigator) => navigator.push(
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    ),
  );

  // ── Look ────────────────────────────────────────────────────────────────

  ({IconData icon, Color color, Color bg, String title, String subtitle})
  _header(AppPalette p) => switch (widget.kind) {
    StatKind.bloodType => (
      icon: Icons.water_drop_rounded,
      color: p.primaryText,
      bg: p.accentBg,
      title: 'Your blood type',
      subtitle: 'Who you can donate to and receive from',
    ),
    StatKind.donations => (
      icon: Icons.favorite_rounded,
      color: p.pink,
      bg: p.pinkBg,
      title: 'Your donations',
      subtitle: 'Your record with Dugtong',
    ),
    StatKind.lives => (
      icon: Icons.people_rounded,
      color: p.success,
      bg: p.successBg,
      title: 'Lives saved',
      subtitle: 'The difference you have made',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final h = _header(p);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    final (body, footer) = switch (widget.kind) {
      StatKind.bloodType => (_bloodTypeBody(p), _bloodTypeFooter()),
      StatKind.donations => (
        _donationsBody(p),
        PrimaryButton(label: 'View donation history', onTap: _openHistory),
      ),
      StatKind.lives => (
        _livesBody(p),
        PrimaryButton(label: 'Book a donation', onTap: _openBook),
      ),
    };

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: p.border),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The grab handle.
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: h.bg,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(h.icon, size: 28, color: h.color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            h.title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: p.foreground,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          h.subtitle,
                          style: TextStyle(fontSize: 13, color: p.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: p.muted),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: body,
                ),
              ),
              const SizedBox(height: 12),
              FadeSlideIn(index: 5, child: footer),
            ],
          ),
        ),
      ),
    );
  }

  // ── Blood type ──────────────────────────────────────────────────────────

  Widget _bloodTypeFooter() =>
      widget.bloodType != null && bloodCompatibility(widget.bloodType) != null
      ? const SizedBox.shrink()
      : PrimaryButton(label: 'Open profile', onTap: _openProfile);

  Widget _bloodTypeBody(AppPalette p) {
    final type = normalizeBloodType(widget.bloodType);
    final match = bloodCompatibility(widget.bloodType);
    if (type == null || match == null) {
      return FadeSlideIn(
        index: 0,
        child: _InfoCard(
          icon: Icons.info_outline_rounded,
          text:
              "Your blood type isn't set yet. You can add it in your profile.",
        ),
      );
    }
    return Column(
      children: [
        FadeSlideIn(
          index: 0,
          child: Semantics(
            label: 'Your blood type is $type',
            excludeSemantics: true,
            child: Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.accentBg,
                shape: BoxShape.circle,
                border: Border.all(color: p.primaryBorder, width: 2),
              ),
              child: Text(
                type,
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: p.primaryText,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FadeSlideIn(
          index: 1,
          child: _TypeChips(
            title: 'You can donate to',
            types: match.giveTo,
            mine: type,
          ),
        ),
        const SizedBox(height: 16),
        FadeSlideIn(
          index: 2,
          child: _TypeChips(
            title: 'You can receive from',
            types: match.receiveFrom,
            mine: type,
          ),
        ),
        const SizedBox(height: 14),
        FadeSlideIn(
          index: 3,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Matching shown for red blood cells. The donation center '
              'confirms the final match.',
              style: TextStyle(fontSize: 11.5, height: 1.4, color: p.muted),
            ),
          ),
        ),
      ],
    );
  }

  // ── Donations ───────────────────────────────────────────────────────────

  Widget _donationsBody(AppPalette p) {
    final n = widget.donations;
    final next = kDonationMilestones.where((m) => m > n).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FadeSlideIn(
          index: 0,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              CountUpText(
                n,
                duration: const Duration(milliseconds: 700),
                style: TextStyle(
                  fontSize: 44,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                  color: p.foreground,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                n == 1 ? 'donation' : 'donations',
                style: TextStyle(fontSize: 16, color: p.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FadeSlideIn(index: 1, child: _milestone(p, n, next)),
        const SizedBox(height: 20),
        FadeSlideIn(
          index: 2,
          child: Text(
            'Recent donations',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: p.foreground,
            ),
          ),
        ),
        const SizedBox(height: 10),
        FadeSlideIn(index: 3, child: _recentDonations(p)),
      ],
    );
  }

  Widget _milestone(AppPalette p, int n, int? next) {
    if (next == null) {
      return Row(
        children: [
          Icon(Icons.emoji_events_rounded, size: 18, color: p.warningText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "You've reached every milestone. Thank you!",
              style: TextStyle(fontSize: 13, color: p.foreground),
            ),
          ),
        ],
      );
    }
    final left = next - n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$left more ${left == 1 ? 'donation' : 'donations'} to reach $next',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: p.foreground,
          ),
        ),
        const SizedBox(height: 8),
        SlimProgressBar(
          value: n / next,
          color: AppColors.primary,
          trackColor: p.border,
        ),
      ],
    );
  }

  Widget _recentDonations(AppPalette p) {
    switch (_load) {
      case _Load.loading:
        return const SkeletonPulse(
          child: Column(
            children: [
              _DonationSkeletonRow(),
              SizedBox(height: 10),
              _DonationSkeletonRow(),
              SizedBox(height: 10),
              _DonationSkeletonRow(),
            ],
          ),
        );
      case _Load.failed:
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.wifi_off_rounded, size: 18, color: p.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Couldn't load your donations",
                  style: TextStyle(fontSize: 13, color: p.foreground),
                ),
              ),
              TextButton(
                onPressed: _loadDonations,
                style: TextButton.styleFrom(
                  foregroundColor: p.primaryText,
                  minimumSize: const Size(64, 48),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      case _Load.done:
        if (_recent.isEmpty) return _emptyDonations(p);
        return Column(
          children: [
            for (final (i, d) in _recent.indexed) ...[
              if (i > 0) const SizedBox(height: 10),
              _DonationRow(donation: d),
            ],
          ],
        );
    }
  }

  Widget _emptyDonations(AppPalette p) {
    return Column(
      children: [
        const SizedBox(height: 4),
        Container(
          width: 88,
          height: 88,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: p.accentBg, shape: BoxShape.circle),
          child: ExcludeSemantics(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.water_drop_rounded, size: 50, color: p.primaryText),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Icon(
                    Icons.favorite_rounded,
                    size: 16,
                    color: p.accentBg,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'No donations yet. Your first donation can help save up to 3 lives.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.5, color: p.muted),
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          onPressed: _openBook,
          style: OutlinedButton.styleFrom(
            foregroundColor: p.primaryText,
            side: BorderSide(color: p.primaryBorder),
            minimumSize: const Size(0, 48),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          child: const Text('Book an appointment'),
        ),
      ],
    );
  }

  // ── Lives ───────────────────────────────────────────────────────────────

  Widget _livesBody(AppPalette p) {
    final n = widget.donations;
    final lives = n * 3;
    const shown = 12;
    final filled = lives < shown ? lives : shown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FadeSlideIn(
          index: 0,
          child: CountUpText(
            lives,
            duration: const Duration(milliseconds: 700),
            style: TextStyle(
              fontSize: 44,
              height: 1.1,
              fontWeight: FontWeight.w900,
              color: p.foreground,
            ),
          ),
        ),
        const SizedBox(height: 14),
        FadeSlideIn(
          index: 1,
          child: Semantics(
            label: '$filled of $shown people',
            excludeSemantics: true,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var i = 0; i < shown; i++)
                  Icon(
                    i < filled
                        ? Icons.person_rounded
                        : Icons.person_outline_rounded,
                    size: 22,
                    color: i < filled ? p.success : p.border,
                  ),
                if (lives > shown)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      '+${lives - shown} more',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: p.successDark,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FadeSlideIn(
          index: 2,
          child: Text(
            n == 0
                ? 'Your first donation could help save up to 3 lives.'
                : '$n ${n == 1 ? 'donation' : 'donations'} x 3 lives',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: p.foreground,
            ),
          ),
        ),
        const SizedBox(height: 6),
        FadeSlideIn(
          index: 3,
          child: Text(
            'One donation can help save up to 3 lives. These are estimates.',
            style: TextStyle(fontSize: 12, height: 1.4, color: p.muted),
          ),
        ),
      ],
    );
  }
}

// ── Pieces ──────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.infoBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.infoBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: p.infoText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13.5, height: 1.45, color: p.infoText),
            ),
          ),
        ],
      ),
    );
  }
}

/// "You can donate to" and the chips under it; the donor's own type is
/// filled with the brand red.
class _TypeChips extends StatelessWidget {
  const _TypeChips({
    required this.title,
    required this.types,
    required this.mine,
  });

  final String title;
  final List<String> types;
  final String mine;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: p.muted,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          container: true,
          label: '$title: ${types.join(', ')}',
          excludeSemantics: true,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in types)
                Container(
                  constraints: const BoxConstraints(minWidth: 48),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: t == mine ? AppColors.primary : p.surfaceAlt,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: t == mine ? AppColors.primary : p.border,
                    ),
                  ),
                  child: Text(
                    t,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: t == mine ? Colors.white : p.foreground,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonationRow extends StatelessWidget {
  const _DonationRow({required this.donation});

  final Map<String, dynamic> donation;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final date = formatDonationDate('${donation['donation_date'] ?? ''}');
    final center =
        (donation['facility_name'] ??
                donation['center_name'] ??
                donation['facility'])
            ?.toString();
    final units = int.tryParse('${donation['blood_units']}') ?? 0;
    final status = donation['donation_status']?.toString();
    final colors = donationStatusChipColors(p, status);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: p.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (center != null && center.isNotEmpty) center,
                    '$units ${units == 1 ? 'unit' : 'units'}',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colors.bg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              donationStatusLabel(status),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DonationSkeletonRow extends StatelessWidget {
  const _DonationSkeletonRow();

  @override
  Widget build(BuildContext context) => Container(
    height: 62,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.palette.surfaceAlt,
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SkeletonBox(width: 90, height: 12),
              SizedBox(height: 8),
              SkeletonBox(width: 150, height: 10),
            ],
          ),
        ),
        SkeletonBox(width: 64, height: 22, radius: 999),
      ],
    ),
  );
}
