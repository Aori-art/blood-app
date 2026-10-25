// One of the donor's requests to a hospital: where it stands (a status card
// that changes with it), the request, the hospital, the timeline and the
// private details, and cancelling it. It refreshes itself while it is open.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_colors.dart';
import '../app_palette.dart';
import '../home_nav.dart';
import '../shared_design.dart';
import 'blood_request_api.dart';
import 'blood_request_models.dart';
import 'blood_request_widgets.dart';
import 'hospital_request_api.dart';
import 'hospital_request_models.dart';
import 'hospital_request_widgets.dart';
import 'request_blood_screen.dart';

const _months = [
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

/// Statuses the hospital may still change (the screen keeps checking).
const kActiveHospitalStatuses = {'pending_review', 'approved', 'ready'};

String _time(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final period = d.hour >= 12 ? 'PM' : 'AM';
  return '$hour:${d.minute.toString().padLeft(2, '0')} $period';
}

bool _hasTime(String raw) => raw.contains(':');

/// "Oct 30, 5:00 PM" (or "Oct 30" for a date alone).
String formatHospitalDate(String raw) {
  final d = DateTime.tryParse(raw);
  if (d == null) return raw;
  final day = '${_months[d.month - 1]} ${d.day}';
  return _hasTime(raw) ? '$day, ${_time(d)}' : day;
}

/// How long is left to pick the blood up: "Today 5:00 PM", "Tomorrow
/// 9:00 AM", "in 2 days", or "Deadline passed".
String pickupCountdownLabel(String raw, DateTime now) {
  final d = DateTime.tryParse(raw);
  if (d == null) return raw;
  final timed = _hasTime(raw);
  final days = DateTime(
    d.year,
    d.month,
    d.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (days < 0 || (timed && d.isBefore(now))) return 'Deadline passed';
  if (days == 0) return timed ? 'Today ${_time(d)}' : 'Today';
  if (days == 1) return timed ? 'Tomorrow ${_time(d)}' : 'Tomorrow';
  return 'in $days days';
}

class HospitalRequestDetailScreen extends StatefulWidget {
  const HospitalRequestDetailScreen({
    super.key,
    required this.requestId,
    this.initial,
    this.refreshEvery = const Duration(seconds: 45),
    this.now = DateTime.now,
  });

  final int requestId;

  /// Shown at once (from the list or the sent screen) while the rest loads.
  final HospitalRequest? initial;

  /// How often an active request is checked while the screen is open.
  final Duration refreshEvery;

  /// The clock (tests set it).
  final DateTime Function() now;

  @override
  State<HospitalRequestDetailScreen> createState() =>
      _HospitalRequestDetailScreenState();
}

class _HospitalRequestDetailScreenState
    extends State<HospitalRequestDetailScreen>
    with WidgetsBindingObserver {
  String? _donorId;
  HospitalRequestDetailResult? _data;
  bool _loading = true;
  bool _error = false;
  bool _notFound = false;
  bool _cancelling = false;
  bool _foreground = true;
  Timer? _timer;

  HospitalRequest? get _request => _data?.request;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initial = widget.initial;
    if (initial != null) {
      _data = HospitalRequestDetailResult(request: initial, timeline: []);
    }
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (foreground) {
      // Back in the app: see what changed while it was away.
      _load(silent: true);
    } else {
      _syncTimer();
    }
  }

  /// Checks every [HospitalRequestDetailScreen.refreshEvery] while the app is
  /// in front and the request can still change; stopped otherwise.
  void _syncTimer() {
    final status = _request?.status;
    final wanted =
        mounted &&
        _foreground &&
        status != null &&
        kActiveHospitalStatuses.contains(status);
    if (!wanted) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(widget.refreshEvery, (_) {
        // Only while this screen is the one on top.
        if (!mounted) return;
        if (ModalRoute.of(context)?.isCurrent == false) return;
        _load(silent: true);
      });
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && _data == null) {
      setState(() {
        _loading = true;
        _error = false;
      });
    }
    final before = _request?.status;
    try {
      _donorId ??= (await SharedPreferences.getInstance()).getString('donorId');
      final data = await HospitalRequestApi.fetchDetail(
        donorId: _donorId ?? '',
        requestId: widget.requestId,
      );
      if (!mounted) return;
      if (before != null && before != data.request.status) {
        HapticFeedback.lightImpact();
      }
      setState(() {
        _data = data;
        _loading = false;
        _error = false;
        _notFound = false;
      });
    } on BloodRequestApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (e.code == 'NOT_FOUND') {
          _notFound = true;
        } else if (_data == null) {
          _error = true;
        }
      });
      if (_data != null && !silent && e.code != 'NOT_FOUND') {
        _showSnack(e.message, isError: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_data == null) _error = true;
      });
      if (_data != null && !silent) {
        _showSnack(
          "Couldn't refresh. Check your connection and try again.",
          isError: true,
        );
      }
    }
    _syncTimer();
  }

  // ─── Actions ────────────────────────────────────────────────────────────

  void _copy(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnack(message);
  }

  /// Dials the hospital, or copies its number when the phone can't.
  Future<void> _call(String number) async {
    try {
      final opened = await launchUrl(Uri(scheme: 'tel', path: number));
      if (!opened) _copy(number, 'Number copied');
    } catch (_) {
      _copy(number, 'Number copied');
    }
  }

  String _addressOf(BloodRequestFacility f) => [
    f.name,
    f.address,
    f.barangay,
    f.city,
    f.province,
  ].where((e) => e != null && e.isNotEmpty).join(', ');

  /// The hospital on a map: its coordinates, or else its address.
  Future<void> _directions(BloodRequestFacility f) async {
    final query = f.latitude != null && f.longitude != null
        ? '${f.latitude},${f.longitude}'
        : _addressOf(f);
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': query,
    });
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) _copy(_addressOf(f), 'Address copied');
    } catch (_) {
      _copy(_addressOf(f), 'Address copied');
    }
  }

  Future<void> _requestAgain() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const RequestBloodScreen()),
    );
  }

  Future<void> _openCancelDialog() async {
    final r = _request;
    if (r == null) return;
    final reasonCtrl = TextEditingController();
    const quickPicks = [
      'No longer needed',
      'Got blood from another hospital',
      'Patient was transferred',
      'I entered the wrong details',
    ];
    final heldForYou = r.status == 'approved' || r.status == 'ready';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) {
          final reason = reasonCtrl.text.trim();
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Cancel this request?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (heldForYou) ...[
                    Container(
                      key: const ValueKey('cancel-release-note'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: c.palette.warningBg,
                        border: Border.all(color: c.palette.warningBorder),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'The hospital will be told and the blood set aside '
                        'for you will be released.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: c.palette.isDark
                              ? c.palette.warning
                              : c.palette.warningText,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 3,
                    maxLength: 300,
                    decoration: InputDecoration(
                      hintText: 'Reason for cancelling',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  if (reason.isNotEmpty && reason.length < 3)
                    Text(
                      'Please write at least 3 characters.',
                      style: TextStyle(
                        fontSize: 11,
                        color: c.palette.primaryText,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: quickPicks
                        .map(
                          (q) => Semantics(
                            button: true,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                reasonCtrl.text = q;
                                setDialogState(() {});
                              },
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 48,
                                ),
                                child: Align(
                                  widthFactor: 1,
                                  heightFactor: 1,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: c.palette.surfaceAlt,
                                      border: Border.all(
                                        color: c.palette.border,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      q,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: c.palette.foreground,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Back'),
              ),
              TextButton(
                onPressed: reason.length >= 3
                    ? () => Navigator.pop(c, true)
                    : null,
                child: Text(
                  'Cancel Request',
                  style: TextStyle(
                    color: reason.length >= 3
                        ? c.palette.primaryText
                        : c.palette.muted,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    final reason = reasonCtrl.text.trim();
    // The dialog's field is gone after its closing animation.
    WidgetsBinding.instance.addPostFrameCallback((_) => reasonCtrl.dispose());
    if (confirmed == true) await _cancel(reason);
  }

  Future<void> _cancel(String reason) async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    try {
      final updated = await HospitalRequestApi.cancel(
        donorId: _donorId ?? '',
        requestId: widget.requestId,
        reason: reason,
      );
      if (!mounted) return;
      setState(() {
        _cancelling = false;
        if (updated != null) {
          _data = HospitalRequestDetailResult(
            request: updated,
            timeline: _data?.timeline ?? const [],
            availability: _data?.availability,
          );
        }
      });
      _showSnack('Your request was cancelled');
      _syncTimer();
      // The timeline gets its new step.
      _load(silent: true);
    } on BloodRequestApiException catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      _showSnack(e.message, isError: true);
      if (e.code == 'NOT_CANCELLABLE' || e.code == 'NOT_FOUND') {
        _load(silent: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      _showSnack(
        "Couldn't cancel. Check your connection and try again.",
        isError: true,
      );
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
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
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final Widget body;
    if (_notFound) {
      body = _messageBody(
        icon: Icons.search_off_rounded,
        title: 'Request not found',
        message: 'It may have been removed. Go back and refresh your list.',
      );
    } else if (data == null && _loading) {
      body = Column(
        children: [
          _heroBar(),
          Expanded(
            child: Center(
              child: CircularProgressIndicator(
                color: context.palette.primaryText,
              ),
            ),
          ),
        ],
      );
    } else if (_error || data == null) {
      body = _messageBody(
        icon: Icons.wifi_off_rounded,
        title: "Couldn't load this request",
        message: 'Check your connection and try again.',
        actionLabel: 'Try Again',
        onAction: _load,
      );
    } else {
      body = _loadedBody(data);
    }
    return Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(child: body),
    );
  }

  Widget _messageBody({
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) => Column(
    children: [
      _heroBar(),
      Expanded(
        child: BrEmptyState(
          icon: icon,
          title: title,
          message: message,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      ),
    ],
  );

  /// Back and refresh on the gradient (also shown while loading).
  Widget _heroBar() => Container(
    padding: const EdgeInsets.fromLTRB(11, 7, 11, 7),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: kHeaderGradient,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Row(
      children: [
        HeaderIconButton48(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Back',
          onTap: () {
            Navigator.maybePop(context);
          },
        ),
        const Spacer(),
        HeaderIconButton48(
          icon: Icons.refresh_rounded,
          tooltip: 'Refresh',
          onTap: _load,
        ),
      ],
    ),
  );

  Widget _loadedBody(HospitalRequestDetailResult data) {
    final r = data.request;
    return RefreshIndicator(
      color: context.palette.primaryText,
      onRefresh: () => _load(),
      child: ListView(
        key: const PageStorageKey('hospital-request-detail'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _hero(r),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _statusCard(r, data.availability),
                const SizedBox(height: 14),
                _summaryCard(r),
                const SizedBox(height: 14),
                if (r.facility != null) ...[
                  _hospitalCard(r.facility!),
                  const SizedBox(height: 14),
                ],
                if (data.timeline.isNotEmpty) ...[
                  _timelineCard(data.timeline),
                  const SizedBox(height: 14),
                ],
                _privateCard(r),
                if (r.canCancel) ...[
                  const SizedBox(height: 20),
                  _cancelButton(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Hero ───────────────────────────────────────────────────────────────

  Widget _hero(HospitalRequest r) => ClipRRect(
    borderRadius: const BorderRadius.only(
      bottomLeft: Radius.circular(28),
      bottomRight: Radius.circular(28),
    ),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(11, 7, 11, 24),
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
              HeaderIconButton48(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onTap: () {
                  Navigator.maybePop(context);
                },
              ),
              const Spacer(),
              HeaderIconButton48(
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh',
                onTap: _load,
              ),
            ],
          ),
          BloodDropBadge(bloodType: r.bloodType, size: 84, inverted: true),
          const SizedBox(height: 12),
          Text(
            r.reference,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              UrgencyChip(urgency: r.urgency, onGradient: true),
              HospitalStatusChip(request: r, onGradient: true),
            ],
          ),
          if (r.createdAgo != null) ...[
            const SizedBox(height: 8),
            Text(
              'Sent ${r.createdAgo}',
              style: const TextStyle(fontSize: 11, color: AppColors.onPrimary),
            ),
          ],
        ],
      ),
    ),
  );

  // ─── Status card ────────────────────────────────────────────────────────

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: context.palette.surface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: context.palette.border),
    boxShadow: context.palette.shadow,
  );

  Widget _statusCard(HospitalRequest r, StockAvailability? stock) {
    final p = context.palette;
    final hospital = r.facility?.name ?? 'the hospital';
    final number = r.facility?.contactNumber;
    switch (r.status) {
      case 'pending_review':
        return _statusShell(
          key: 'pending',
          icon: Icons.hourglass_top_rounded,
          iconColor: p.isDark ? p.warning : p.warningText,
          iconBg: p.warningBg,
          title: 'The hospital is reviewing your request',
          children: [
            _bodyText(
              'This can take a while. If it is urgent, call the hospital.',
            ),
            if (stock != null) ...[
              const SizedBox(height: 12),
              Text(
                'Its stock of ${r.bloodType} now',
                style: TextStyle(fontSize: 11, color: p.muted),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: StockChip(availability: stock, showUpdated: true),
              ),
            ],
            if (number != null) ...[
              const SizedBox(height: 14),
              _outlinedAction(
                Icons.call_rounded,
                'Call hospital',
                () => _call(number),
              ),
            ],
          ],
        );
      case 'approved':
        final approved = r.unitsApproved ?? r.unitsRequested;
        return _statusShell(
          key: 'approved',
          icon: Icons.check_circle_rounded,
          iconColor: p.info,
          iconBg: p.infoBg,
          title: 'Approved by the hospital',
          children: [
            _bodyText(
              '$approved of ${r.unitsRequested} '
              '${r.unitsRequested == 1 ? 'unit' : 'units'} set aside',
              strong: true,
            ),
            if (r.hospitalMessage != null) ...[
              const SizedBox(height: 12),
              _quote(r.hospitalMessage!, 'From $hospital'),
            ],
          ],
        );
      case 'ready':
        return _pickupCard(r);
      case 'fulfilled':
        return _statusShell(
          key: 'fulfilled',
          icon: Icons.celebration_rounded,
          iconColor: p.isDark ? p.success : p.successDark,
          iconBg: p.successBg,
          title: 'Your request is complete',
          children: [
            _bodyText('We hope the patient gets well soon.'),
            const SizedBox(height: 14),
            _filledAction(
              Icons.volunteer_activism_rounded,
              'Book a donation to help others',
              () => HomeNav.goTo(HomeTab.book),
            ),
          ],
        );
      case 'rejected':
        return _statusShell(
          key: 'rejected',
          icon: Icons.block_rounded,
          iconColor: p.isDark ? p.criticalText : p.primaryText,
          iconBg: p.accentBg,
          title: "The hospital couldn't fulfil this request",
          children: [
            if (r.rejectionReason != null)
              _quote(r.rejectionReason!, 'From $hospital'),
            const SizedBox(height: 14),
            _filledAction(
              Icons.local_hospital_rounded,
              'Request from another hospital',
              _requestAgain,
            ),
          ],
        );
      default:
        final cancelled = r.status == 'cancelled';
        return _statusShell(
          key: cancelled ? 'cancelled' : 'expired',
          icon: cancelled ? Icons.cancel_outlined : Icons.schedule_rounded,
          iconColor: p.muted,
          iconBg: p.surfaceAlt,
          title: cancelled
              ? 'You cancelled this request'
              : 'This request expired',
          children: [
            if (cancelled && r.cancellationReason != null)
              _bodyText(r.cancellationReason!)
            else if (!cancelled)
              _bodyText(
                'It expired because nobody answered it before the '
                'needed-by date.',
              ),
            const SizedBox(height: 14),
            _outlinedAction(
              Icons.replay_rounded,
              'Request again',
              _requestAgain,
            ),
          ],
        );
    }
  }

  Widget _statusShell({
    required String key,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required List<Widget> children,
  }) => Container(
    key: ValueKey('status-card-$key'),
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
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.palette.foreground,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );

  Widget _bodyText(String text, {bool strong = false}) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      height: 1.4,
      fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
      color: strong ? context.palette.foreground : context.palette.muted,
    ),
  );

  Widget _quote(String text, String from) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.palette.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      border: Border(
        left: BorderSide(color: context.palette.primaryText, width: 3),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.format_quote_rounded,
          size: 16,
          color: context.palette.primaryText,
        ),
        const SizedBox(height: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: context.palette.foreground,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          from,
          style: TextStyle(fontSize: 11, color: context.palette.muted),
        ),
      ],
    ),
  );

  Widget _filledAction(IconData icon, String label, VoidCallback onTap) =>
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label, textAlign: TextAlign.center),
          style: ElevatedButton.styleFrom(
            backgroundColor: kCrimson,
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );

  Widget _outlinedAction(IconData icon, String label, VoidCallback onTap) =>
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label, textAlign: TextAlign.center),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.palette.primaryText,
            side: BorderSide(color: context.palette.primaryBorder),
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );

  /// Ready for pickup: where, until when, what to bring, and the way there.
  Widget _pickupCard(HospitalRequest r) {
    final p = context.palette;
    final green = p.isDark ? p.success : p.successDark;
    final f = r.facility;
    final deadline = r.pickupDeadline;
    final number = f?.contactNumber;
    Widget bring(String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 16, color: green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: p.foreground, height: 1.3),
            ),
          ),
        ],
      ),
    );
    return Container(
      key: const ValueKey('status-card-ready'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.successBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.successBorder, width: 1.5),
        boxShadow: p.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.inventory_2_rounded, color: green, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Ready for pickup at ${f?.name ?? 'the hospital'}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: p.foreground,
                  ),
                ),
              ),
            ],
          ),
          if (deadline != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Pick up by ${formatHospitalDate(deadline)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: p.foreground,
                  ),
                ),
                Container(
                  key: const ValueKey('pickup-countdown'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: p.surface,
                    border: Border.all(color: p.successBorder),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    pickupCountdownLabel(deadline, widget.now()),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: green,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (r.hospitalMessage != null) ...[
            const SizedBox(height: 12),
            _quote(r.hospitalMessage!, 'From ${f?.name ?? 'the hospital'}'),
          ],
          const SizedBox(height: 12),
          Text(
            'Bring:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: p.foreground,
            ),
          ),
          bring('A valid ID'),
          bring("The hospital's blood request form"),
          bring('Reference ${r.reference}'),
          const SizedBox(height: 14),
          if (f != null)
            _filledAction(
              Icons.directions_rounded,
              'Get directions',
              () => _directions(f),
            ),
          if (number != null) ...[
            const SizedBox(height: 8),
            _outlinedAction(
              Icons.call_rounded,
              'Call hospital',
              () => _call(number),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Cards ──────────────────────────────────────────────────────────────

  Widget _cardTitle(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: context.palette.foreground,
    ),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.palette.muted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.palette.foreground,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _summaryCard(HospitalRequest r) => Container(
    key: const ValueKey('summary-card'),
    padding: const EdgeInsets.all(16),
    decoration: _cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardTitle('Request'),
        const SizedBox(height: 12),
        Row(
          children: [
            BloodDropBadge(bloodType: r.bloodType, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                r.componentLabel.isNotEmpty ? r.componentLabel : r.component,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.palette.foreground,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _row('Units requested', '${r.unitsRequested}'),
        if (r.unitsApproved != null)
          _row('Units approved', '${r.unitsApproved}'),
        _row('Urgency', r.urgencyLabel.isNotEmpty ? r.urgencyLabel : r.urgency),
        if (r.neededBy != null) _row('Needed by', brLongDate(r.neededBy)),
      ],
    ),
  );

  IconData _facilityIcon(String type) => switch (type) {
    'blood_bank' => Icons.bloodtype_rounded,
    'clinic' => Icons.medical_services_rounded,
    'health_center' => Icons.health_and_safety_rounded,
    _ => Icons.local_hospital_rounded,
  };

  Widget _hospitalCard(BloodRequestFacility f) {
    final p = context.palette;
    final address = [
      f.address,
      f.barangay,
      f.city,
      f.province,
    ].where((e) => e != null && e.isNotEmpty).join(', ');
    final number = f.contactNumber;
    return Container(
      key: const ValueKey('hospital-card'),
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.accentBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _facilityIcon(f.type),
                  color: p.primaryText,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: p.foreground,
                      ),
                    ),
                    if (f.typeLabel.isNotEmpty)
                      Text(
                        f.typeLabel,
                        style: TextStyle(fontSize: 11, color: p.muted),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Directions to ${f.name}',
                onPressed: () => _directions(f),
                icon: Icon(Icons.directions_rounded, color: p.primaryText),
              ),
            ],
          ),
          if (address.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 8, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on_rounded, size: 16, color: p.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      address,
                      style: TextStyle(
                        fontSize: 12,
                        color: p.foreground,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (number != null)
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Copy number $number',
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: () => _copy(number, 'Number copied'),
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          children: [
                            Icon(Icons.call_rounded, size: 16, color: p.muted),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                number,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: p.foreground,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.copy_rounded, size: 14, color: p.muted),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Call ${f.name}',
                  onPressed: () => _call(number),
                  icon: Icon(
                    Icons.phone_forwarded_rounded,
                    color: p.primaryText,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _timelineTime(String value) {
    final d = DateTime.tryParse(value);
    if (d == null) return value;
    return '${_months[d.month - 1]} ${d.day}, ${_time(d)}';
  }

  Widget _timelineCard(List<TimelineEvent> timeline) => Container(
    key: const ValueKey('timeline-card'),
    padding: const EdgeInsets.all(16),
    decoration: _cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardTitle('Timeline'),
        const SizedBox(height: 14),
        for (var i = 0; i < timeline.length; i++)
          _timelineRow(timeline[i], i == timeline.length - 1),
      ],
    ),
  );

  Widget _timelineRow(TimelineEvent event, bool isLast) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: event.done ? AppColors.success : context.palette.surface,
                border: event.done
                    ? null
                    : Border.all(color: context.palette.border, width: 2),
              ),
              child: event.done
                  ? const Icon(
                      Icons.check_rounded,
                      size: 13,
                      color: Colors.white,
                    )
                  : null,
            ),
            if (!isLast)
              Expanded(
                child: Container(
                  width: 2,
                  color: event.done
                      ? AppColors.success
                      : context.palette.border,
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18, top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: event.done
                        ? context.palette.foreground
                        : context.palette.muted,
                  ),
                ),
                if (event.at != null)
                  Text(
                    _timelineTime(event.at!),
                    style: TextStyle(
                      fontSize: 11,
                      color: context.palette.muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _privateCard(HospitalRequest r) => Container(
    key: const ValueKey('private-card'),
    padding: const EdgeInsets.all(16),
    decoration: _cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.lock_rounded, size: 16, color: context.palette.muted),
            const SizedBox(width: 8),
            Expanded(child: _cardTitle('Private details')),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 24, top: 2),
          child: Text(
            'Only you and the hospital can see this',
            style: TextStyle(fontSize: 11, color: context.palette.muted),
          ),
        ),
        const SizedBox(height: 12),
        _row('Patient', r.patientName.isEmpty ? '—' : r.patientName),
        _row(
          'Relationship',
          r.relationshipLabel.isNotEmpty
              ? r.relationshipLabel
              : (r.relationship.isEmpty ? '—' : r.relationship),
        ),
        _row('Contact', r.contactNumber.isEmpty ? '—' : r.contactNumber),
        if (r.hospitalReference != null)
          _row('Hospital ref.', r.hospitalReference!),
        _row(
          'Form photo',
          r.documentAttached ? 'Form photo attached' : 'Not attached',
        ),
        if (r.notes != null) ...[
          const SizedBox(height: 10),
          Text(
            'Your note',
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
          const SizedBox(height: 4),
          Text(
            r.notes!,
            style: TextStyle(
              fontSize: 13,
              color: context.palette.foreground,
              height: 1.4,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _cancelButton() => SizedBox(
    width: double.infinity,
    height: 48,
    child: OutlinedButton(
      onPressed: _cancelling ? null : _openCancelDialog,
      style: OutlinedButton.styleFrom(
        foregroundColor: context.palette.primaryText,
        side: BorderSide(color: context.palette.primaryText, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: _cancelling
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: context.palette.primaryText,
              ),
            )
          : const Text(
              'Cancel Request',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
    ),
  );
}
