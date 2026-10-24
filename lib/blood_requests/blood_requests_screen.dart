// Hub screen for the Blood Requests feature: "Help Others" (open requests a
// donor can volunteer for) and "My Requests" (requests the donor created).
import 'package:flutter/material.dart';
import 'package:blood/app_colors.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../anim.dart';
import '../check.dart';
import '../shared_design.dart';
import '../verify.dart';
import 'blood_request_api.dart';
import 'blood_request_detail_screen.dart';
import 'blood_request_models.dart';
import 'blood_request_widgets.dart';
import 'request_blood_screen.dart';
import '../app_palette.dart';

class BloodRequestsScreen extends StatefulWidget {
  final int initialTab;
  const BloodRequestsScreen({super.key, this.initialTab = 0});

  @override
  State<BloodRequestsScreen> createState() => _BloodRequestsScreenState();
}

class _BloodRequestsScreenState extends State<BloodRequestsScreen> {
  late final PageController _pageCtrl;
  late int _tab;
  String? _donorId;

  String _filter = 'all';
  bool _helpLoading = true;
  bool _helpError = false;
  BloodRequestListResult? _helpResult;

  bool _mineLoading = true;
  bool _mineError = false;
  BloodRequestListResult? _mineResult;

  final _helpScrollCtrl = ScrollController();
  final _mineScrollCtrl = ScrollController();
  bool _fabVisible = true;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _pageCtrl = PageController(initialPage: _tab);
    _helpScrollCtrl.addListener(() => _handleScroll(_helpScrollCtrl));
    _mineScrollCtrl.addListener(() => _handleScroll(_mineScrollCtrl));
    _init();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _helpScrollCtrl.dispose();
    _mineScrollCtrl.dispose();
    super.dispose();
  }

  void _handleScroll(ScrollController c) {
    if (!c.hasClients) return;
    final dir = c.position.userScrollDirection;
    if (dir == ScrollDirection.reverse && _fabVisible) {
      setState(() => _fabVisible = false);
    } else if (dir == ScrollDirection.forward && !_fabVisible) {
      setState(() => _fabVisible = true);
    }
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _donorId = prefs.getString('donorId');
    await Future.wait([_loadHelp(), _loadMine()]);
  }

  Future<void> _loadHelp() async {
    if (_donorId == null || _donorId!.isEmpty) {
      if (mounted) setState(() { _helpLoading = false; _helpError = true; });
      return;
    }
    if (mounted) setState(() { _helpLoading = true; _helpError = false; });
    try {
      final result = await BloodRequestApi.fetchRequests(
        donorId: _donorId!,
        scope: 'open',
        filter: _filter,
      );
      if (!mounted) return;
      setState(() { _helpResult = result; _helpLoading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _helpLoading = false; _helpError = true; });
    }
  }

  Future<void> _loadMine() async {
    if (_donorId == null || _donorId!.isEmpty) {
      if (mounted) setState(() { _mineLoading = false; _mineError = true; });
      return;
    }
    if (mounted) setState(() { _mineLoading = true; _mineError = false; });
    try {
      final result = await BloodRequestApi.fetchRequests(
        donorId: _donorId!,
        scope: 'mine',
      );
      if (!mounted) return;
      setState(() { _mineResult = result; _mineLoading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _mineLoading = false; _mineError = true; });
    }
  }

  Future<void> _refreshAll() => Future.wait([_loadHelp(), _loadMine()]);

  void _setFilter(String value) {
    if (value == _filter) return;
    HapticFeedback.selectionClick();
    setState(() => _filter = value);
    _loadHelp();
  }

  void _setTab(int index) {
    if (index == _tab) return;
    HapticFeedback.selectionClick();
    setState(() => _tab = index);
    _pageCtrl.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openDetail(int requestId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BloodRequestDetailScreen(requestId: requestId),
      ),
    );
    if (mounted) await _refreshAll();
  }

  Future<void> _openRequestForm() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const RequestBloodScreen()),
    );
    if (created == true && mounted) {
      setState(() => _tab = 1);
      _pageCtrl.jumpToPage(1);
      await _loadMine();
    }
  }

  void _handleBlockAction(String? action) {
    if (action == 'verify') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const VerifyScreen()),
      );
    } else if (action == 'check') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CheckScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.palette.background,
    body: SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              _header(),
              _segmentedControl(),
              const SizedBox(height: 12),
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  onPageChanged: (i) => setState(() => _tab = i),
                  children: [_helpTab(), _mineTab()],
                ),
              ),
            ],
          ),
          _fab(),
        ],
      ),
    ),
  );

  // ─── Header & segments ──────────────────────────────────────────────────

  Widget _header() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: kHeaderGradient,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Row(
      children: [
        HeaderIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Back',
          onTap: () => Navigator.pop(context),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Blood Requests',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Give blood. Get help. Save lives.',
                style: TextStyle(color: AppColors.onPrimary, fontSize: 12),
              ),
            ],
          ),
        ),
        HeaderIconButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Refresh',
          onTap: _refreshAll,
        ),
      ],
    ),
  );

  Widget _segmentedControl() {
    final allCount = _helpResult?.counts.all ?? 0;
    final mineCount = _mineResult?.requests.length ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.palette.border),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              alignment: _tab == 0 ? Alignment.centerLeft : Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: kCrimson,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(child: _segmentButton('Help Others', allCount, 0)),
                Expanded(child: _segmentButton('My Requests', mineCount, 1)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _segmentButton(String label, int count, int index) {
    final selected = _tab == index;
    return GestureDetector(
      onTap: () => _setTab(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 40,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : context.palette.muted,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: .25)
                        : context.palette.surfaceAlt,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : context.palette.muted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── Help Others tab ────────────────────────────────────────────────────

  Widget _helpTab() {
    if (_helpLoading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: const [
          BrSkeletonCard(),
          SizedBox(height: 12),
          BrSkeletonCard(),
          SizedBox(height: 12),
          BrSkeletonCard(),
        ],
      );
    }
    if (_helpError) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          BrEmptyState(
            icon: Icons.wifi_off_rounded,
            title: "Couldn't load requests",
            message: 'Check your connection and try again.',
            actionLabel: 'Try Again',
            onAction: _loadHelp,
          ),
        ],
      );
    }

    final result = _helpResult;
    final viewer = result?.viewer;
    final requests = result?.requests ?? const [];

    return RefreshIndicator(
      color: context.palette.primaryText,
      onRefresh: _loadHelp,
      child: ListView(
        controller: _helpScrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          if (viewer != null) _donorProfileStrip(viewer),
          const SizedBox(height: 16),
          _filterChips(result?.counts),
          const SizedBox(height: 12),
          if (requests.isEmpty)
            _helpEmptyState()
          else
            ...List.generate(
              requests.length,
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FadeSlideIn(
                  index: i,
                  child: BloodRequestCard(
                    request: requests[i],
                    onTap: () => _openDetail(requests[i].requestId),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _helpEmptyState() {
    switch (_filter) {
      case 'match':
        return const BrEmptyState(
          icon: Icons.volunteer_activism_rounded,
          title: 'No matches for your type yet',
          message: "We'll show requests your blood type can help with.",
        );
      case 'urgent':
        return const BrEmptyState(
          icon: Icons.volunteer_activism_rounded,
          title: 'No urgent requests',
          message: "That's good news!",
        );
      default:
        return const BrEmptyState(
          icon: Icons.volunteer_activism_rounded,
          title: 'No open requests right now',
          message: 'When patients need donors, their requests will appear here.',
        );
    }
  }

  Widget _donorProfileStrip(ViewerContext viewer) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.palette.border),
      boxShadow: context.palette.shadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BloodDropBadge(bloodType: viewer.bloodType, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    viewer.bloodType != null
                        ? "You're type ${viewer.bloodType}"
                        : 'Blood type not set',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.palette.foreground,
                    ),
                  ),
                  if (viewer.bloodType != null && !viewer.bloodTypeConfirmed) ...[
                    const SizedBox(height: 6),
                    Tooltip(
                      message: 'Your blood type is confirmed at your next donation',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: context.palette.warningBg,
                          border: Border.all(color: context.palette.warningBorder),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Unconfirmed',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: context.palette.warning,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (viewer.bloodType == null)
                    Text(
                      'You can still help requests that accept any blood type.',
                      style: TextStyle(fontSize: 11, color: context.palette.muted, height: 1.4),
                    )
                  else ...[
                    Text(
                      'Can donate to',
                      style: TextStyle(fontSize: 11, color: context.palette.muted),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: viewer.canDonateTo
                          .map(
                            (t) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: context.palette.accentBg,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                t,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: context.palette.primaryText,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (viewer.volunteerBlock != null) ...[
          const SizedBox(height: 12),
          _volunteerBlockBanner(viewer.volunteerBlock!),
        ],
        if (viewer.activeCommitment != null) ...[
          const SizedBox(height: 12),
          _activeCommitmentBanner(viewer.activeCommitment!),
        ],
      ],
    ),
  );

  Widget _volunteerBlockBanner(VolunteerBlock block) {
    const amberReasons = {'NOT_CHECKED', 'DEFERRED', 'ELIGIBILITY_REVIEW'};
    final amber = amberReasons.contains(block.reason);
    final fg = amber ? context.palette.warning : context.palette.primaryText;
    final bg = amber ? context.palette.warningBg : context.palette.accentBg;
    final border = amber ? context.palette.warningBorder : context.palette.primaryBorder;
    String? buttonLabel;
    if (block.action == 'verify') {
      buttonLabel = 'Verify Now';
    } else if (block.action == 'check') {
      buttonLabel = 'Take the Check';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            block.message,
            style: TextStyle(fontSize: 12, color: fg, height: 1.4),
          ),
          if (buttonLabel != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _handleBlockAction(block.action),
              child: Text(
                buttonLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: fg,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _activeCommitmentBanner(ActiveCommitment commitment) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.palette.successBg,
      border: Border.all(color: context.palette.successBorder),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(Icons.favorite_rounded, size: 16, color: context.palette.success),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            "You're donating for ${commitment.reference}",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.palette.successDark,
            ),
          ),
        ),
        GestureDetector(
          onTap: () => _openDetail(commitment.requestId),
          child: Text(
            'View',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.palette.success,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _filterChips(RequestCounts? counts) {
    final c = counts ?? const RequestCounts(all: 0, match: 0, urgent: 0);
    final items = [
      ('all', 'All', c.all),
      ('match', 'Matches me', c.match),
      ('urgent', 'Urgent', c.urgent),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (value, label, count) = items[i];
          final selected = _filter == value;
          return GestureDetector(
            onTap: () => _setFilter(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? kCrimson : context.palette.surface,
                border: Border.all(color: selected ? context.palette.primaryText : context.palette.border),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$label $count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : context.palette.muted,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── My Requests tab ────────────────────────────────────────────────────

  Widget _mineTab() {
    if (_mineLoading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: const [
          BrSkeletonCard(),
          SizedBox(height: 12),
          BrSkeletonCard(),
        ],
      );
    }
    if (_mineError) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          BrEmptyState(
            icon: Icons.wifi_off_rounded,
            title: "Couldn't load requests",
            message: 'Check your connection and try again.',
            actionLabel: 'Try Again',
            onAction: _loadMine,
          ),
        ],
      );
    }

    final requests = _mineResult?.requests ?? const [];
    final hasPending = requests.any((r) => r.status == 'pending_review');

    return RefreshIndicator(
      color: context.palette.primaryText,
      onRefresh: _loadMine,
      child: ListView(
        controller: _mineScrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          if (hasPending) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.palette.infoBg,
                border: Border.all(color: context.palette.infoBorder),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: context.palette.info, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Requests are reviewed by the Dugtong team before donors can see them.',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.infoText,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (requests.isEmpty)
            BrEmptyState(
              icon: Icons.bloodtype_outlined,
              title: 'No requests yet',
              message:
                  'Need blood for yourself or a loved one? Create a request '
                  'and matching donors can volunteer to help.',
              actionLabel: 'Request Blood',
              onAction: _openRequestForm,
            )
          else
            ...List.generate(
              requests.length,
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FadeSlideIn(
                  index: i,
                  child: BloodRequestCard(
                    request: requests[i],
                    ownerView: true,
                    onTap: () => _openDetail(requests[i].requestId),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── FAB ────────────────────────────────────────────────────────────────

  Widget _fab() => Positioned(
    left: 16,
    right: 16,
    bottom: 16,
    child: IgnorePointer(
      ignoring: !_fabVisible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        offset: _fabVisible ? Offset.zero : const Offset(0, 2),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: _fabVisible ? 1 : 0,
          child: Center(
            child: PressableScale(
              onTap: _openRequestForm,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: AppColors.primaryGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: kCrimson.withValues(alpha: .35),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Request Blood',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
