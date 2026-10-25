// Detail screen for a single blood request — shown both to donors deciding
// whether to help and to the requester tracking their own request.
import 'package:flutter/material.dart';
import 'package:blood/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../anim.dart';
import '../check.dart';
import '../shared_design.dart';
import '../verify.dart';
import 'blood_request_api.dart';
import 'blood_request_models.dart';
import 'blood_request_widgets.dart';
import '../app_palette.dart';

class BloodRequestDetailScreen extends StatefulWidget {
  final int requestId;
  const BloodRequestDetailScreen({super.key, required this.requestId});

  @override
  State<BloodRequestDetailScreen> createState() =>
      _BloodRequestDetailScreenState();
}

class _BloodRequestDetailScreenState extends State<BloodRequestDetailScreen> {
  BloodRequestDetailResult? _result;
  bool _loading = true;
  bool _error = false;
  bool _notFound = false;
  bool _actionLoading = false;
  String? _donorId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
      _notFound = false;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      _donorId = prefs.getString('donorId');
      if (_donorId == null || _donorId!.isEmpty) {
        if (mounted)
          setState(() {
            _loading = false;
            _error = true;
          });
        return;
      }
      final result = await BloodRequestApi.fetchDetail(
        donorId: _donorId!,
        requestId: widget.requestId,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } on BloodRequestApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (e.code == 'NOT_FOUND') {
          _notFound = true;
        } else {
          _error = true;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
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

  void _copy(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnack(message);
  }

  Future<void> _callFacility(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    try {
      final opened = await launchUrl(uri);
      if (!opened) _copy(number, 'Contact number copied');
    } catch (_) {
      _copy(number, 'Contact number copied');
    }
  }

  void _showSnack(
    String message, {
    bool isError = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? kCrimson : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: Colors.white,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  void _mergeResult(BloodRequestActionResult action) {
    setState(() {
      _result = BloodRequestDetailResult(
        request: action.request,
        viewer: action.viewer ?? _result?.viewer,
      );
      _actionLoading = false;
    });
  }

  Future<void> _respond(String action) async {
    if (_actionLoading || _donorId == null) return;
    setState(() => _actionLoading = true);
    try {
      final result = await BloodRequestApi.respond(
        donorId: _donorId!,
        requestId: widget.requestId,
        action: action,
      );
      if (!mounted) return;
      if (action == 'volunteer') HapticFeedback.mediumImpact();
      _mergeResult(result);
      _showSnack(
        result.message.isNotEmpty
            ? result.message
            : action == 'volunteer'
            ? 'Thank you for volunteering!'
            : 'You have withdrawn from this request.',
      );
    } on BloodRequestApiException catch (e) {
      if (!mounted) return;
      setState(() => _actionLoading = false);
      if (e.code == 'HAS_OTHER_COMMITMENT') {
        final otherId = e.raw['other_request_id'];
        final otherIdInt = otherId == null
            ? null
            : int.tryParse(otherId.toString());
        _showSnack(
          e.message,
          isError: true,
          actionLabel: otherIdInt != null ? 'View' : null,
          onAction: otherIdInt != null ? () => _openOther(otherIdInt) : null,
        );
      } else {
        _showSnack(e.message, isError: true);
        if (const [
          'REQUEST_FULL',
          'NOT_OPEN',
          'CANNOT_WITHDRAW',
        ].contains(e.code)) {
          _load();
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _actionLoading = false);
      _showSnack(
        'Unable to reach the server. Please check your connection and try again.',
        isError: true,
      );
    }
  }

  void _openOther(int requestId) {
    if (requestId <= 0) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => BloodRequestDetailScreen(requestId: requestId),
      ),
    );
  }

  Future<void> _confirmWithdraw() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Withdraw from this request?'),
        content: const Text('The patient will need to find another donor.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Withdraw', style: TextStyle(color: context.palette.primaryText)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _respond('withdraw');
  }

  Future<void> _openVolunteerSheet(BloodRequest r) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _VolunteerConfirmSheet(request: r),
    );
    if (confirmed == true) await _respond('volunteer');
  }

  @override
  Widget build(BuildContext context) {
    final data = _result;
    final showBody = !_loading && !_notFound && !_error && data != null;
    return Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(
        child: _loading
            ? _loadingBody()
            : _notFound
            ? _notFoundBody()
            : _error || data == null
            ? _errorBody()
            : _loadedBody(data),
      ),
      bottomNavigationBar: showBody ? _bottomBarFor(data) : null,
    );
  }

  Widget _loadingBody() =>
      Center(child: CircularProgressIndicator(color: context.palette.primaryText));

  Widget _errorBody() => Column(
    children: [
      Align(
        alignment: Alignment.topLeft,
        child: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.palette.foreground),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      Expanded(
        child: BrEmptyState(
          icon: Icons.wifi_off_rounded,
          title: "Couldn't load this request",
          message: 'Check your connection and try again.',
          actionLabel: 'Try Again',
          onAction: _load,
        ),
      ),
    ],
  );

  Widget _notFoundBody() => Column(
    children: [
      Align(
        alignment: Alignment.topLeft,
        child: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.palette.foreground),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      const Expanded(
        child: BrEmptyState(
          icon: Icons.search_off_rounded,
          title: 'Request Not Found',
          message: "This request isn't available.",
        ),
      ),
    ],
  );

  Widget _loadedBody(BloodRequestDetailResult data) {
    final r = data.request;
    return Column(
      children: [
        _heroHeader(r),
        Expanded(
          child: RefreshIndicator(
            color: context.palette.primaryText,
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: _sections(r, data),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _sections(BloodRequest r, BloodRequestDetailResult data) {
    var idx = 0;
    final widgets = <Widget>[
      FadeSlideIn(index: idx++, child: _progressCard(r)),
    ];
    widgets.addAll([
      const SizedBox(height: 14),
      FadeSlideIn(index: idx++, child: _facilityCard(r)),
    ]);
    if (r.notes != null && r.notes!.isNotEmpty) {
      widgets.addAll([
        const SizedBox(height: 14),
        FadeSlideIn(index: idx++, child: _noteCard(r)),
      ]);
    }
    if (!r.isMine) {
      widgets.addAll([
        const SizedBox(height: 14),
        FadeSlideIn(index: idx++, child: _yourMatchCard(r, data.viewer)),
      ]);
      if (r.canHelp) {
        widgets.addAll([
          const SizedBox(height: 14),
          FadeSlideIn(index: idx++, child: _howToHelpCard()),
        ]);
      }
    }
    return widgets;
  }

  Widget? _bottomBarFor(BloodRequestDetailResult data) {
    final r = data.request;
    // (Requests to hospitals have their own screen: this one is for the
    // appeals, where a donor never helps their own.)
    if (r.isMine) return null;
    return _donorActionBar(r, data.viewer);
  }

  // ─── Hero header ─────────────────────────────────────────────────────────

  Widget _heroHeader(BloodRequest r) => ClipRRect(
    borderRadius: const BorderRadius.only(
      bottomLeft: Radius.circular(28),
      bottomRight: Radius.circular(28),
    ),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: kHeaderGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              HeaderIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onTap: () => Navigator.pop(context),
              ),
              const Spacer(),
              HeaderIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh',
                onTap: _load,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Hero(
            tag: 'br_drop_${r.requestId}',
            child: BloodDropBadge(
              bloodType: r.bloodType,
              size: 84,
              inverted: true,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            r.reference,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              UrgencyChip(urgency: r.urgency, onGradient: true),
              const SizedBox(width: 8),
              RequestStatusChip(
                status: r.status,
                label: r.statusLabel,
                onGradient: true,
              ),
            ],
          ),
          if (r.createdAgo != null) ...[
            const SizedBox(height: 8),
            Text(
              'Posted ${r.createdAgo}',
              style: const TextStyle(fontSize: 11, color: AppColors.onPrimary),
            ),
          ],
        ],
      ),
    ),
  );

  // ─── Shared body cards ──────────────────────────────────────────────────

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: context.palette.surface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: context.palette.border),
    boxShadow: context.palette.shadow,
  );

  bool _isUrgentTimeLeft(BloodRequest r) {
    final label = r.timeLeftLabel?.toLowerCase() ?? '';
    return label.contains('today') ||
        label.contains('1 day') ||
        label.contains('tomorrow') ||
        label.contains('hour');
  }

  Widget _progressRing(BloodRequest r) {
    final ratio = r.requiredDonors <= 0
        ? 0.0
        : (r.volunteersCount / r.requiredDonors).clamp(0.0, 1.0);
    final color = r.isFull ? context.palette.success : context.palette.primaryText;
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: ratio),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (_, value, _) => CircularProgressIndicator(
              value: value,
              strokeWidth: 8,
              backgroundColor: context.palette.surfaceAlt,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${r.volunteersCount}/${r.requiredDonors}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: context.palette.foreground,
                ),
              ),
              Text(
                'donors',
                style: TextStyle(fontSize: 10, color: context.palette.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _progressCard(BloodRequest r) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: _cardDecoration(),
    child: Row(
      children: [
        _progressRing(r),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              r.isFull
                  ? Row(
                      children: [
                        Icon(
                          Icons.celebration_rounded,
                          size: 16,
                          color: context.palette.success,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'All donors found',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: context.palette.success,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      '${r.remainingCount} more donor${r.remainingCount == 1 ? '' : 's'} needed',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.palette.foreground,
                      ),
                    ),
              const SizedBox(height: 4),
              Text(
                r.requirementText,
                style: TextStyle(
                  fontSize: 12,
                  color: context.palette.muted,
                  height: 1.4,
                ),
              ),
              if (r.timeLeftLabel != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _isUrgentTimeLeft(r)
                        ? context.palette.warningBg
                        : context.palette.surfaceAlt,
                    border: Border.all(
                      color: _isUrgentTimeLeft(r)
                          ? context.palette.warningBorder
                          : context.palette.border,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 13,
                        color: _isUrgentTimeLeft(r)
                            ? context.palette.warning
                            : context.palette.muted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        r.timeLeftLabel!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _isUrgentTimeLeft(r)
                              ? context.palette.warning
                              : context.palette.foreground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  IconData _facilityIcon(String? type) {
    switch (type) {
      case 'hospital':
        return Icons.local_hospital_rounded;
      case 'blood_bank':
        return Icons.bloodtype_rounded;
      case 'clinic':
        return Icons.medical_services_rounded;
      case 'health_center':
        return Icons.health_and_safety_rounded;
      default:
        return Icons.local_hospital_rounded;
    }
  }

  Widget _facilityCard(BloodRequest r) {
    final f = r.facility;
    final addressBits = [
      f?.address,
      f?.city,
      f?.province,
    ].where((e) => e != null && e.isNotEmpty).join(', ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.palette.accentBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_facilityIcon(f?.type), color: context.palette.primaryText, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f?.name ?? 'Facility',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.palette.foreground,
                      ),
                    ),
                    Text(
                      [
                        f?.typeLabel,
                        f?.locationLine,
                      ].where((e) => e != null && e.isNotEmpty).join(' · '),
                      style: TextStyle(fontSize: 11, color: context.palette.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (addressBits.isNotEmpty)
            _facilityRow(Icons.location_on_rounded, addressBits),
          if (f?.contactNumber != null && f!.contactNumber!.isNotEmpty)
            _facilityRow(
              Icons.call_rounded,
              f.contactNumber!,
              onTap: () => _copy(f.contactNumber!, 'Contact number copied'),
              trailing: IconButton(
                icon: Icon(
                  Icons.phone_forwarded_rounded,
                  size: 18,
                  color: context.palette.primaryText,
                ),
                tooltip: 'Call facility',
                onPressed: () => _callFacility(f.contactNumber!),
              ),
            ),
          if (r.neededBy != null)
            _facilityRow(
              Icons.event_rounded,
              'Needed by ${brLongDate(r.neededBy)}',
            ),
        ],
      ),
    );
  }

  Widget _facilityRow(
    IconData icon,
    String text, {
    VoidCallback? onTap,
    Widget? trailing,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.palette.accentBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: context.palette.primaryText),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  color: context.palette.foreground,
                  height: 1.4,
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );

  Widget _noteCard(BloodRequest r) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.palette.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      border: Border(left: BorderSide(color: context.palette.primaryText, width: 3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.format_quote_rounded, size: 16, color: context.palette.primaryText),
        const SizedBox(height: 6),
        Text(
          r.notes ?? '',
          style: TextStyle(
            fontSize: 13,
            color: context.palette.foreground,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          r.source == 'admin' ? 'From facility' : 'From the requester',
          style: TextStyle(fontSize: 11, color: context.palette.muted),
        ),
      ],
    ),
  );

  Widget _yourMatchCard(BloodRequest r, ViewerContext? viewer) {
    final matchType = r.myMatchType;
    String explanation;
    switch (matchType) {
      case 'exact':
        explanation = 'You have the exact blood type this patient needs.';
        break;
      case 'compatible':
        explanation =
            'Your blood type can safely be given to a ${r.bloodTypeLabel} patient.';
        break;
      case 'replacement_any':
        explanation = r.bloodTypeUnknown
            ? "The patient's blood type isn't known yet, so donors of any "
                  'blood type can help.'
            : "Your blood type isn't a direct match, but this hospital accepts "
                  'replacement donors of any type.';
        break;
      default:
        explanation = "Your blood type isn't a match for this request.";
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BloodDropBadge(bloodType: viewer?.bloodType, size: 36),
              const SizedBox(width: 10),
              Icon(
                Icons.arrow_forward_rounded,
                color: context.palette.muted,
                size: 18,
              ),
              const SizedBox(width: 10),
              BloodDropBadge(bloodType: r.bloodType, size: 36),
              const SizedBox(width: 12),
              MatchBadge(matchType: matchType),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            explanation,
            style: TextStyle(
              fontSize: 12,
              color: context.palette.muted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _howToHelpStep(int number, IconData icon, String title, String body) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.palette.accentBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 15, color: context.palette.primaryText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.palette.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.palette.muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _howToHelpCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.palette.accentBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.palette.primaryBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.volunteer_activism_rounded, size: 16, color: context.palette.primaryText),
            SizedBox(width: 8),
            Text(
              'How You Can Help',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: context.palette.foreground,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _howToHelpStep(
          1,
          Icons.touch_app_rounded,
          'Volunteer',
          "Tap \"I Can Donate\" below to let the facility know you're available.",
        ),
        const SizedBox(height: 12),
        _howToHelpStep(
          2,
          Icons.local_hospital_rounded,
          'Visit the facility',
          'Go to the facility before the needed-by date and mention this request.',
        ),
        const SizedBox(height: 12),
        _howToHelpStep(
          3,
          Icons.fact_check_rounded,
          'Get screened, then donate',
          "Staff will confirm you're eligible on the day, just like a regular donation.",
        ),
      ],
    ),
  );

  // ─── Donor (non-owner) action bar ───────────────────────────────────────

  Widget _barWrapper({required Widget child}) => Container(
    decoration: BoxDecoration(
      color: context.palette.surface,
      border: Border(top: BorderSide(color: context.palette.border)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );

  Widget? _donorActionBar(BloodRequest r, ViewerContext? viewer) {
    if (r.myResponse?.isCommitted == true) return _committedBar(r);
    if (viewer?.volunteerBlock != null)
      return _blockedBar(viewer!.volunteerBlock!);
    if (r.isFull) {
      return _infoOnlyBar(
        'This request has all the donors it needs. Thank you!',
      );
    }
    if (r.status != 'open') {
      return _infoOnlyBar('This request is ${r.statusLabel.toLowerCase()}.');
    }
    if (r.canHelp) return _canHelpBar(r);
    return null;
  }

  Widget _committedBar(BloodRequest r) => _barWrapper(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: context.palette.successBg,
            border: Border.all(color: context.palette.successBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.favorite_rounded,
                color: context.palette.success,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "You're donating for this request",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.palette.successDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Visit ${r.facility?.name ?? 'the facility'} before '
                      '${brLongDate(r.neededBy)} and mention ${r.reference}.',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.successDark,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (r.myResponse?.canWithdraw == true)
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: _actionLoading ? null : _confirmWithdraw,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.palette.primaryText,
                side: BorderSide(color: context.palette.primaryText, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _actionLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.palette.primaryText,
                      ),
                    )
                  : const Text(
                      'Withdraw',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          )
        else
          Text(
            'Confirmed by the facility — contact them to make changes.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
      ],
    ),
  );

  Widget _blockedBar(VolunteerBlock block) => _barWrapper(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          block.message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: context.palette.warning),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: null,
            style: ElevatedButton.styleFrom(
              disabledBackgroundColor: context.palette.border,
              disabledForegroundColor: context.palette.muted,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'I Can Donate',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (block.action == 'verify' || block.action == 'check')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextButton(
              onPressed: () => _handleBlockAction(block.action),
              child: Text(
                block.action == 'verify' ? 'Verify Now' : 'Take the Check',
                style: TextStyle(
                  color: context.palette.primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _infoOnlyBar(String text) => _barWrapper(
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: context.palette.muted),
    ),
  );

  Widget _canHelpBar(BloodRequest r) => _barWrapper(
    child: SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _actionLoading ? null : () => _openVolunteerSheet(r),
        icon: const Icon(Icons.volunteer_activism_rounded, size: 20),
        label: _actionLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'I Can Donate',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
        style: ElevatedButton.styleFrom(
          backgroundColor: kCrimson,
          disabledBackgroundColor: context.palette.border,
          disabledForegroundColor: context.palette.muted,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    ),
  );

  // ─── Requester (owner) sections ─────────────────────────────────────────

}

// ─── Volunteer confirmation sheet ───────────────────────────────────────────

class _VolunteerConfirmSheet extends StatelessWidget {
  final BloodRequest request;
  const _VolunteerConfirmSheet({required this.request});

  Widget _row(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check_circle_rounded,
          size: 18,
          color: context.palette.success,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: context.palette.foreground,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: context.palette.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Text(
              'Before you volunteer',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: context.palette.foreground,
              ),
            ),
            const SizedBox(height: 16),
            _row(context, 
              'Visit ${request.facility?.name ?? 'the facility'} before ${brShortDate(request.neededBy)}',
            ),
            _row(context, 'Bring a valid ID'),
            _row(context, 'Mention reference ${request.reference} at the blood bank'),
            _row(context, "You'll be screened again at the facility before donating"),
            const SizedBox(height: 12),
            PrimaryButton(
              label: "Confirm — I'll Donate",
              onTap: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Not now', style: TextStyle(color: context.palette.muted)),
            ),
          ],
        ),
      ),
    ),
  );
}
