import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'app_colors.dart';
import 'app_palette.dart';
import 'config.dart';
import 'skeleton.dart';

/// The donor's cancellation allowance (get_cancel_policy.php).
class CancelPolicy {
  /// 0 means no automatic restriction.
  final int limit;
  final int consecutiveCount;

  /// Null means no automatic restriction.
  final int? remaining;
  final bool restricted;
  final String? restrictionReason;

  const CancelPolicy({
    required this.limit,
    required this.consecutiveCount,
    required this.remaining,
    required this.restricted,
    this.restrictionReason,
  });

  /// Whether cancelling is limited at all.
  bool get hasLimit => limit > 0 && remaining != null;

  /// One cancellation left before booking is paused.
  bool get lastChance => hasLimit && remaining == 1;

  factory CancelPolicy.fromJson(Map<String, dynamic> json) => CancelPolicy(
    limit: _int(json['limit']) ?? 0,
    consecutiveCount: _int(json['consecutive_count']) ?? 0,
    remaining: _int(json['remaining']),
    restricted:
        json['restricted'] == true || json['restricted'].toString() == '1',
    restrictionReason: _text(json['restriction_reason']),
  );
}

/// The answer of cancel_appointment.php.
class CancelResult {
  final bool success;
  final String? code;
  final String? message;
  final int? consecutiveCount;
  final int? limit;
  final int? remaining;
  final bool restricted;

  const CancelResult({
    required this.success,
    this.code,
    this.message,
    this.consecutiveCount,
    this.limit,
    this.remaining,
    this.restricted = false,
  });

  /// The appointment changed under the donor (already cancelled, done, gone
  /// or in the past): the sheet closes and the screen reloads.
  bool get appointmentChanged => const {
    'NOT_CANCELLABLE',
    'APPOINTMENT_PASSED',
    'APPOINTMENT_NOT_FOUND',
  }.contains(code);
}

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

String? _text(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty || s == 'null' ? null : s;
}

class CancelAppointmentApi {
  CancelAppointmentApi._();

  /// Null when the call fails (the policy is only an extra).
  static Future<CancelPolicy?> fetchPolicy(String donorId) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${AppConfig.baseUrl}/get_cancel_policy.php?donor_id=$donorId',
            ),
          )
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(response.body);
      if (response.statusCode != 200 ||
          body is! Map ||
          body['success'] != true ||
          body['policy'] is! Map) {
        return null;
      }
      return CancelPolicy.fromJson(Map<String, dynamic>.from(body['policy']));
    } catch (_) {
      return null;
    }
  }

  /// Throws on a network error (the caller shows "Connection error").
  static Future<CancelResult> cancel({
    required String donorId,
    required Object appointmentId,
    required String reason,
  }) async {
    final response = await http
        .post(
          Uri.parse('${AppConfig.baseUrl}/cancel_appointment.php'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'donor_id': int.tryParse(donorId) ?? donorId,
            'appointment_id': appointmentId,
            'reason': reason,
          }),
        )
        .timeout(const Duration(seconds: 15));
    dynamic body;
    try {
      body = jsonDecode(response.body);
    } catch (_) {
      body = null;
    }
    if (body is! Map) {
      return CancelResult(
        success: false,
        code: 'SERVER_ERROR',
        message: 'Server error: ${response.statusCode}',
      );
    }
    return CancelResult(
      success: body['success'] == true,
      code: _text(body['code']),
      message: _text(body['message']),
      consecutiveCount: _int(body['consecutive_count']),
      limit: _int(body['limit']),
      remaining: _int(body['remaining']),
      restricted:
          body['restricted'] == true || body['restricted'].toString() == '1',
    );
  }
}

/// The reasons a donor can pick from.
const List<String> kCancelReasons = [
  'Schedule conflict',
  'Not feeling well',
  'Transportation problem',
  'Found a different center',
  'Changed my mind',
  'Other',
];

const int kOtherReasonMax = 200;
const int kReasonMin = 3;

/// Opens the cancel sheet. Resolves to the server's answer when the sheet
/// closed because of it (cancelled, or the appointment changed), null when
/// the donor kept the appointment.
Future<CancelResult?> showCancelAppointmentSheet(
  BuildContext context, {
  required Map<String, dynamic> appointment,
  required String donorId,
  required String Function(String?) formatDate,
  required String Function(String?) formatTime,
  required void Function(String message) showMessage,
}) => showModalBottomSheet<CancelResult>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: context.palette.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (sheetContext) => CancelAppointmentSheet(
    appointment: appointment,
    donorId: donorId,
    formatDate: formatDate,
    formatTime: formatTime,
    showMessage: showMessage,
  ),
);

class CancelAppointmentSheet extends StatefulWidget {
  final Map<String, dynamic> appointment;
  final String donorId;
  final String Function(String?) formatDate;
  final String Function(String?) formatTime;
  final void Function(String message) showMessage;

  const CancelAppointmentSheet({
    super.key,
    required this.appointment,
    required this.donorId,
    required this.formatDate,
    required this.formatTime,
    required this.showMessage,
  });

  @override
  State<CancelAppointmentSheet> createState() => _CancelAppointmentSheetState();
}

class _CancelAppointmentSheetState extends State<CancelAppointmentSheet> {
  String? _reason; // the chosen chip label
  final _other = TextEditingController();
  bool _sending = false;
  bool _policyLoading = true;
  CancelPolicy? _policy;
  String? _error; // shown in the sheet too: a SnackBar sits behind it

  @override
  void initState() {
    super.initState();
    _loadPolicy();
  }

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  Future<void> _loadPolicy() async {
    final policy = await CancelAppointmentApi.fetchPolicy(widget.donorId);
    if (!mounted) return;
    setState(() {
      _policy = policy;
      _policyLoading = false;
    });
  }

  /// What is sent: the chip label, or the typed text for "Other".
  String? get _finalReason {
    final r = _reason;
    if (r == null) return null;
    if (r != 'Other') return r;
    final text = _other.text.trim();
    return text.length >= kReasonMin ? text : null;
  }

  Future<void> _confirm() async {
    final reason = _finalReason;
    final id = widget.appointment['appointment_id'];
    if (reason == null || id == null || _sending) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _sending = true;
      _error = null;
    });
    final CancelResult result;
    try {
      result = await CancelAppointmentApi.cancel(
        donorId: widget.donorId,
        appointmentId: id,
        reason: reason,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Connection error';
      });
      widget.showMessage('Connection error');
      return;
    }
    if (!mounted) return;
    if (result.success || result.appointmentChanged) {
      Navigator.of(context).pop(result);
      return;
    }
    final message = result.message ?? 'Could not cancel the appointment.';
    setState(() {
      _sending = false;
      _error = message;
    });
    widget.showMessage(message);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final a = widget.appointment;
    return PopScope(
      canPop: !_sending,
      child: SafeArea(
        top: false,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Cancel this appointment?',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: p.foreground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tell us why, so we can improve.',
                  style: TextStyle(fontSize: 12.5, color: p.muted),
                ),
                const SizedBox(height: 16),
                _summary(a),
                const SizedBox(height: 16),
                Text(
                  'Reason',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: p.foreground,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [for (final r in kCancelReasons) _chip(r)],
                ),
                if (_reason == 'Other') ...[
                  const SizedBox(height: 4),
                  TextField(
                    controller: _other,
                    maxLength: kOtherReasonMax,
                    maxLines: 3,
                    minLines: 1,
                    enabled: !_sending,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(fontSize: 14, color: p.foreground),
                    decoration: InputDecoration(
                      hintText:
                          'Tell us more (at least $kReasonMin characters)',
                      hintStyle: TextStyle(color: p.hint),
                      filled: true,
                      fillColor: p.surfaceAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: p.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: p.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: p.primaryText,
                          width: 1.5,
                        ),
                      ),
                      counterStyle: TextStyle(fontSize: 11, color: p.muted),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _policyNotice(),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: p.criticalText,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton(
                          onPressed: _sending
                              ? null
                              : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: p.foreground,
                            side: BorderSide(color: p.border),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const _OneLine('Keep Appointment'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _finalReason == null || _sending
                              ? null
                              : _confirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.critical,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: p.border,
                            disabledForegroundColor: p.muted,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _sending
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const _OneLine(
                                  'Cancel Appointment',
                                  bold: true,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label) {
    final p = context.palette;
    final selected = _reason == label;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _sending
            ? null
            : () {
                HapticFeedback.selectionClick();
                setState(() => _reason = label);
              },
        child: ConstrainedBox(
          // The pill is 36 px; the touch target is 48.
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              // No alignment: the pill is as wide as its text.
              padding: const EdgeInsets.symmetric(horizontal: 14),
              constraints: const BoxConstraints(minHeight: 36),
              decoration: BoxDecoration(
                color: selected ? p.accentBg : p.surfaceAlt,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? p.primaryText : p.border,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    Icon(Icons.check_rounded, size: 15, color: p.primaryText),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? p.primaryText : p.foreground,
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

  Widget _summary(Map<String, dynamic> a) {
    final p = context.palette;
    Widget row(IconData icon, String label, String value) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.accentBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: p.primaryText),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: p.muted)),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: p.foreground,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.surfaceAlt,
          border: Border.all(color: p.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            row(
              Icons.event_rounded,
              'Date',
              widget.formatDate(a['appointment_date']?.toString()),
            ),
            const SizedBox(height: 12),
            row(
              Icons.schedule_rounded,
              'Time',
              widget.formatTime(a['appointment_time']?.toString()),
            ),
            const SizedBox(height: 12),
            row(
              Icons.location_on_rounded,
              'Donation center',
              a['donation_center']?.toString() ?? 'N/A',
            ),
          ],
        ),
      ),
    );
  }

  Widget _policyNotice() {
    final p = context.palette;
    if (_policyLoading) {
      return const SkeletonPulse(child: SkeletonBox(height: 14, radius: 7));
    }
    final policy = _policy;
    // A failed call, or no automatic restriction: nothing to say.
    if (policy == null || !policy.hasLimit) return const SizedBox.shrink();
    final last = policy.lastChance;
    final n = policy.consecutiveCount;
    final String text;
    if (last) {
      text = 'This is your last cancellation before booking is paused.';
    } else if (n > 0) {
      text =
          "You've cancelled $n appointment${n == 1 ? '' : 's'} in a row. "
          'After ${policy.limit} in a row, booking is paused until our team '
          'reviews your account.';
    } else {
      text =
          'After ${policy.limit} cancellations in a row, booking is paused '
          'until our team reviews your account.';
    }
    final fg = last ? p.warningText : p.infoText;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: last ? p.warningBg : p.infoBg,
        border: Border.all(color: last ? p.warningBorder : p.infoBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            last ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
            size: 16,
            color: fg,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: fg)),
          ),
        ],
      ),
    );
  }
}

/// A button label that shrinks (instead of overflowing) with large text.
class _OneLine extends StatelessWidget {
  final String text;
  final bool bold;
  const _OneLine(this.text, {this.bold = false});

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(
      text,
      maxLines: 1,
      style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w700),
    ),
  );
}
