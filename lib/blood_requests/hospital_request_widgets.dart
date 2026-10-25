// Small pieces of the hospital request flow: the stock chip shown on each
// hospital, the photo picker adapter, and the screen shown after a request
// was sent.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../app_colors.dart';
import '../app_palette.dart';
import '../shared_design.dart';
import 'blood_request_widgets.dart';
import 'hospital_request_detail_screen.dart';
import 'hospital_request_models.dart';

// ─── Stock chip ─────────────────────────────────────────────────────────────

/// The colors of a stock level. The dot uses the level's role color; the
/// text uses the same family's darker role in light mode, where the plain
/// one is too faint on its tint for small text (3.2:1 for green).
({Color fg, Color bg, Color dot}) stockColors(AppPalette p, StockLevel level) =>
    switch (level) {
      StockLevel.available => (
        fg: p.isDark ? p.success : p.successDark,
        bg: p.successBg,
        dot: p.success,
      ),
      StockLevel.limited => (
        fg: p.isDark ? p.warning : p.warningText,
        bg: p.warningBg,
        dot: p.warning,
      ),
      StockLevel.out => (
        fg: p.isDark ? p.criticalText : p.primaryText,
        bg: p.accentBg,
        dot: p.criticalText,
      ),
      StockLevel.unknown => (fg: p.muted, bg: p.surfaceAlt, dot: p.muted),
    };

/// A hospital's stock of one blood type: "In stock", "Limited", "Out of
/// stock" or "Not listed". A level only, never a count.
class StockChip extends StatelessWidget {
  final StockAvailability availability;

  /// Adds the "updated 2 hours ago" line under the chip.
  final bool showUpdated;

  const StockChip({
    super.key,
    required this.availability,
    this.showUpdated = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = stockColors(p, availability.level);
    final chip = Container(
      key: ValueKey('stock-${availability.level.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: c.dot.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.dot),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              availability.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: c.fg,
              ),
            ),
          ),
        ],
      ),
    );
    final updated = availability.updatedAgo;
    if (!showUpdated || updated == null) return chip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        chip,
        const SizedBox(height: 3),
        Text(
          'updated $updated',
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 10.5, color: p.muted),
        ),
      ],
    );
  }
}

/// The chip's place while the stock is loading.
class StockChipSkeleton extends StatelessWidget {
  const StockChipSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading stock',
    child: Container(
      width: 64,
      height: 22,
      decoration: BoxDecoration(
        color: context.palette.surfaceAlt,
        border: Border.all(color: context.palette.border),
        borderRadius: BorderRadius.circular(999),
      ),
    ),
  );
}

// ─── Request status ─────────────────────────────────────────────────────────

/// What the donor sees for each status (when the server sends no label).
String hospitalStatusLabel(HospitalRequest r) {
  if (r.statusLabel.isNotEmpty) return r.statusLabel;
  return switch (r.status) {
    'pending_review' => 'Waiting for the hospital',
    'approved' => 'Approved',
    'ready' => 'Ready for pickup',
    'fulfilled' => 'Completed',
    'rejected' => 'Declined',
    'cancelled' => 'Cancelled',
    'expired' => 'Expired',
    _ => r.status,
  };
}

/// The colors of a status: waiting = warning, approved = info, ready and
/// completed = success, declined = critical, cancelled and expired = muted.
/// (Light mode writes the label in the family's darker role, as the stock
/// chip does, so small text stays readable on its tint.)
({Color fg, Color bg, Color dot}) hospitalStatusColors(
  AppPalette p,
  String status,
) => switch (status) {
  'pending_review' => (
    fg: p.isDark ? p.warning : p.warningText,
    bg: p.warningBg,
    dot: p.warning,
  ),
  'approved' => (fg: p.infoText, bg: p.infoBg, dot: p.info),
  'ready' || 'fulfilled' => (
    fg: p.isDark ? p.success : p.successDark,
    bg: p.successBg,
    dot: p.success,
  ),
  'rejected' => (
    fg: p.isDark ? p.criticalText : p.primaryText,
    bg: p.accentBg,
    dot: p.criticalText,
  ),
  _ => (fg: p.muted, bg: p.surfaceAlt, dot: p.muted),
};

/// The dot before a status. [pulsing] makes it breathe (a still dot when
/// animations are off).
class StatusDot extends StatefulWidget {
  final Color color;
  final bool pulsing;

  const StatusDot({super.key, required this.color, this.pulsing = false});

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool get _pulsing =>
      widget.pulsing && !MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(StatusDot old) {
    super.didUpdateWidget(old);
    _syncPulse();
  }

  void _syncPulse() {
    if (_pulsing) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating || _pulse.value != 0) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 10,
    height: 10,
    child: Center(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final t = _pulse.value;
          return Container(
            width: 6 + 4 * t,
            height: 6 + 4 * t,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 1 - .5 * t),
            ),
          );
        },
      ),
    ),
  );
}

/// A request's status. "Ready for pickup" has a pulsing dot.
class HospitalStatusChip extends StatelessWidget {
  final HospitalRequest request;

  /// On the gradient hero: the chip sits on the card color.
  final bool onGradient;

  const HospitalStatusChip({
    super.key,
    required this.request,
    this.onGradient = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = hospitalStatusColors(p, request.status);
    return Container(
      key: ValueKey('status-${request.status}'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: onGradient ? p.surface : c.bg,
        border: Border.all(
          color: onGradient ? Colors.white : c.dot.withValues(alpha: .35),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusDot(color: c.dot, pulsing: request.status == 'ready'),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              hospitalStatusLabel(request),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: c.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Home's slim strip for the donor's latest active request: the reference
/// and where it stands, what and where, and when it last changed, tinted by
/// status (ready for pickup: success, with a pulsing dot).
class HospitalStatusStrip extends StatelessWidget {
  final HospitalLatestRequest latest;

  /// How many requests are active in all (a "+N more" when over one).
  final int activeCount;
  final VoidCallback onTap;

  const HospitalStatusStrip({
    super.key,
    required this.latest,
    required this.activeCount,
    required this.onTap,
  });

  IconData get _icon => switch (latest.status) {
    'ready' => Icons.local_hospital_rounded,
    'approved' => Icons.check_circle_rounded,
    _ => Icons.hourglass_top_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = hospitalStatusColors(p, latest.status);
    final ready = latest.status == 'ready';
    final what = [
      '${latest.unitsRequested} ${latest.unitsRequested == 1 ? 'unit' : 'units'}'
          '${latest.bloodType.isEmpty ? '' : ' of ${latest.bloodType}'}',
      if (latest.facilityName.isNotEmpty) 'at ${latest.facilityName}',
    ].join(' ');
    final updated = [
      if (latest.updatedAgo != null) 'Updated ${latest.updatedAgo}',
      if (activeCount > 1) '+${activeCount - 1} more active',
    ].join(' · ');
    return Semantics(
      container: true,
      button: true,
      child: Material(
        key: const ValueKey('request-status-strip'),
        color: c.bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: c.dot.withValues(alpha: .4)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(_icon, color: c.fg, size: 22),
                    if (ready)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: StatusDot(color: c.dot, pulsing: true),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          latest.reference,
                          if (latest.statusLabel.isNotEmpty) latest.statusLabel,
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: c.fg,
                        ),
                      ),
                      Text(
                        what,
                        style: TextStyle(fontSize: 11.5, color: p.foreground),
                      ),
                      if (updated.isNotEmpty)
                        Text(
                          updated,
                          style: TextStyle(fontSize: 11, color: p.muted),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: p.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "2 units · Whole blood · A+"
String hospitalRequestSummaryLine(HospitalRequest r) {
  final units =
      '${r.unitsRequested} ${r.unitsRequested == 1 ? 'unit' : 'units'}';
  final component = r.componentLabel.isNotEmpty
      ? r.componentLabel
      : r.component;
  return [units, component, r.bloodType].where((s) => s.isNotEmpty).join(' · ');
}

/// One of the donor's requests in the list. A request ready for pickup has a
/// success border and an "Action needed" label.
class HospitalRequestCard extends StatelessWidget {
  final HospitalRequest request;
  final VoidCallback onTap;

  const HospitalRequestCard({
    super.key,
    required this.request,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = request;
    final ready = r.status == 'ready';
    final when = [
      if (r.neededBy != null) 'Needed by ${brShortDate(r.neededBy)}',
      if ((r.updatedAgo ?? r.createdAgo) != null)
        'Updated ${r.updatedAgo ?? r.createdAgo}',
    ].join(' · ');
    return Semantics(
      container: true,
      button: true,
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: ValueKey('request-card-${r.requestId}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: ready ? p.success.withValues(alpha: .7) : p.border,
                width: ready ? 1.5 : 1,
              ),
              boxShadow: p.shadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ready || r.needsAttention)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.notifications_active_rounded,
                          size: 14,
                          color: p.isDark ? p.success : p.successDark,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'Action needed',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: p.isDark ? p.success : p.successDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    BloodDropBadge(bloodType: r.bloodType, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.facility?.name ?? 'Hospital',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: p.foreground,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hospitalRequestSummaryLine(r),
                            style: TextStyle(fontSize: 12, color: p.muted),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: p.muted),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    UrgencyChip(urgency: r.urgency),
                    HospitalStatusChip(request: r),
                  ],
                ),
                if (when.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(when, style: TextStyle(fontSize: 11, color: p.muted)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── The form photo picker ──────────────────────────────────────────────────

enum FormPhotoSource { camera, gallery }

/// Where the form photo comes from: the camera or the gallery. Screens take
/// one of these so tests can give them a fake.
abstract class FormPhotoPicker {
  const FormPhotoPicker();

  /// The photo, or null when the donor backed out.
  Future<FormPhoto?> pick(FormPhotoSource source);
}

/// The real one: image_picker (as in verify.dart), scaled to 1600 px wide at
/// 80 % quality.
class ImagePickerFormPhotoPicker extends FormPhotoPicker {
  const ImagePickerFormPhotoPicker();

  @override
  Future<FormPhoto?> pick(FormPhotoSource source) async {
    final file = await ImagePicker().pickImage(
      source: source == FormPhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    var name = file.name;
    if (name.isEmpty) {
      final parts = file.path.split(RegExp(r'[\\/]'));
      name = parts.isEmpty ? 'form.jpg' : parts.last;
    }
    return FormPhoto(bytes: bytes, filename: name);
  }
}

// ─── Sent ───────────────────────────────────────────────────────────────────

class HospitalRequestSubmittedScreen extends StatelessWidget {
  final HospitalRequest request;

  /// The hospital's name, when the request came back without its facility.
  final String? hospitalName;

  const HospitalRequestSubmittedScreen({
    super.key,
    required this.request,
    this.hospitalName,
  });

  String get _hospital =>
      request.facility?.name ?? hospitalName ?? 'the hospital';

  void _copyReference(BuildContext context) {
    Clipboard.setData(ClipboardData(text: request.reference));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white),
            SizedBox(width: 8),
            Text('Reference copied'),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final steps = [
      'The hospital reviews your request and form',
      'You get a notification when it is approved',
      'Pick up the blood at $_hospital with your ID and the form',
    ];

    return Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.6, end: 1),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutBack,
                  builder: (_, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.palette.successBg,
                      border: Border.all(
                        color: context.palette.successBorder,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: context.palette.success.withValues(alpha: .2),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 54,
                      color: context.palette.success,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Request Sent',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: context.palette.foreground,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$_hospital has your request.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: context.palette.muted),
                ),
                const SizedBox(height: 16),
                Semantics(
                  button: true,
                  label: 'Reference ${request.reference}, copy',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () => _copyReference(context),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: context.palette.surfaceAlt,
                        border: Border.all(color: context.palette.border),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              request.reference,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                                color: context.palette.foreground,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.copy_rounded,
                            size: 16,
                            color: context.palette.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: context.palette.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.palette.border),
                    boxShadow: context.palette.shadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What happens next',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: context.palette.foreground,
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (var i = 0; i < steps.length; i++)
                        _stepRow(
                          context,
                          i + 1,
                          steps[i],
                          i == steps.length - 1,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: 'Track Request',
                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => HospitalRequestDetailScreen(
                        requestId: request.requestId,
                        initial: request,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Done',
                    style: TextStyle(color: context.palette.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepRow(
    BuildContext context,
    int number,
    String label,
    bool isLast,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: kCrimson,
                ),
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: context.palette.border),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16, top: 3),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: context.palette.foreground,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// HeaderIconButton's look (a 38 px glass circle on the gradient) in a
/// 48 px tap target. Put it where a HeaderIconButton was with 5 px less
/// padding around it, and it sits where that one did.
class HeaderIconButton48 extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const HeaderIconButton48({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.16),
                border: Border.all(color: Colors.white30, width: 1.2),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
          ),
        ),
      ),
    ),
  );
}
