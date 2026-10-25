// Small pieces of the hospital request flow: the stock chip shown on each
// hospital, the photo picker adapter, and the screen shown after a request
// was sent.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../app_colors.dart';
import '../app_palette.dart';
import '../shared_design.dart';
import 'blood_requests_screen.dart';
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
                  // The request's own screen comes later: for now, the
                  // donor's requests.
                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const BloodRequestsScreen(initialTab: 1),
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
