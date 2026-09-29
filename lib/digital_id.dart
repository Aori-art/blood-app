import 'dart:math' as math;
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'anim.dart';
import 'book.dart';
import 'digital_id_service.dart';
import 'newsfeed.dart' show resolveMediaUrl;
import 'shared_design.dart';

// Fixed design canvas every ID card is authored at, then uniformly scaled
// (via FittedBox) to whatever box it's actually shown or captured in — so
// the same layout can never overflow on screen or crop in the PDF.
const double kCardCanvasWidth = 380;
const double kCardCanvasHeight = kCardCanvasWidth / 1.586;

class DigitalIdScreen extends StatefulWidget {
  const DigitalIdScreen({super.key});

  @override
  State<DigitalIdScreen> createState() => _DigitalIdScreenState();
}

class _DigitalIdScreenState extends State<DigitalIdScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  DigitalIdData? _data;
  bool _loading = true;
  bool _locked = false;
  bool _error = false;
  bool _masked = false;
  String? _donorId;

  late final AnimationController _flipCtrl;
  bool _isBack = false;
  bool _qrSheetOpen = false;
  bool _pdfBusy = false;

  // Tracks whether we've actually asked the OS to raise the app's window
  // brightness, so we only call the platform channel when the target state
  // changes and can cleanly put it back the way we found it.
  bool _brightnessBoosted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _flipCtrl =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 500),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed ||
              status == AnimationStatus.dismissed) {
            _updateBrightness();
          }
        });
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flipCtrl.dispose();
    _forceResetBrightness();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _forceResetBrightness();
    } else if (state == AppLifecycleState.resumed) {
      _updateBrightness();
    }
  }

  // Whether the QR code is currently on screen and scannable — either the
  // big "Show QR Code" sheet is open, or the card is flipped to its back —
  // and not blurred behind the masked-details toggle.
  bool get _qrVisible {
    if (_masked) return false;
    if (_data?.card.qrPayload == null) return false;
    return _qrSheetOpen || _isBack;
  }

  Future<void> _updateBrightness() async {
    final shouldBoost = _qrVisible;
    if (shouldBoost == _brightnessBoosted) return;
    _brightnessBoosted = shouldBoost;
    try {
      if (shouldBoost) {
        await ScreenBrightness.instance.setApplicationScreenBrightness(1.0);
      } else {
        await ScreenBrightness.instance.resetApplicationScreenBrightness();
      }
    } catch (_) {}
  }

  // Fire-and-forget variant for places that can't await (dispose, app going
  // to the background) — still only calls the platform when needed.
  void _forceResetBrightness() {
    if (!_brightnessBoosted) return;
    _brightnessBoosted = false;
    () async {
      try {
        await ScreenBrightness.instance.resetApplicationScreenBrightness();
      } catch (_) {}
    }();
  }

  Future<void> _load() async {
    if (mounted)
      setState(() {
        _loading = true;
        _error = false;
      });
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId')?.trim();
    if (donorId == null || donorId.isEmpty) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = true;
        });
      return;
    }
    _donorId = donorId;
    try {
      final masked = await DigitalIdService.isMasked(donorId);
      final data = await DigitalIdService.fetch(donorId);
      if (!mounted) return;
      setState(() {
        _masked = masked;
        _data = data;
        _locked = data == null;
        _loading = false;
      });
      _updateBrightness();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _toggleMask() async {
    final donorId = _donorId;
    if (donorId == null) return;
    HapticFeedback.selectionClick();
    final next = !_masked;
    setState(() => _masked = next);
    _updateBrightness();
    await DigitalIdService.setMasked(donorId, next);
    if (next && _qrSheetOpen && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _showMaskedQrHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Tap the eye icon at the top to show your QR code.',
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showQrSheet(DigitalIdData data) {
    if (_masked) {
      _showMaskedQrHint();
      return;
    }
    final payload = data.card.qrPayload;
    if (payload == null) return;
    HapticFeedback.lightImpact();
    _qrSheetOpen = true;
    _updateBrightness();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _qrSheetBody(sheetContext, data),
    ).whenComplete(() {
      _qrSheetOpen = false;
      _updateBrightness();
    });
  }

  void _showMaskedPdfHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Tap the eye icon to show your details before downloading.',
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<Uint8List?> _captureBoundary(GlobalKey key) async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 4.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  // The RepaintBoundary is laid out at exactly kCardCanvasWidth x
  // kCardCanvasHeight (see _downloadPdf's capture tree) — this just confirms
  // the frame actually settled at that size before we capture it.
  bool _boundarySizeOk(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    final size = box.size;
    return (size.width - kCardCanvasWidth).abs() < 1 &&
        (size.height - kCardCanvasHeight).abs() < 1;
  }

  // Renders a card at the fixed design canvas size inside a small preview
  // box — the FittedBox only scales what's shown on screen, so the
  // RepaintBoundary underneath still lays out (and captures) at exactly
  // kCardCanvasWidth x kCardCanvasHeight regardless of the dialog's own
  // width constraints, text scale or theme.
  Widget _pdfCapturePreview({
    required GlobalKey boundaryKey,
    required ThemeData theme,
    required TextStyle textStyle,
    required Widget card,
  }) {
    return SizedBox(
      width: kCardCanvasWidth * 0.4,
      height: kCardCanvasHeight * 0.4,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: kCardCanvasWidth,
          height: kCardCanvasHeight,
          child: Theme(
            data: theme,
            child: DefaultTextStyle(
              style: textStyle,
              child: MediaQuery.withNoTextScaling(
                child: RepaintBoundary(key: boundaryKey, child: card),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _downloadPdf(DigitalIdData data) async {
    if (_masked) {
      _showMaskedPdfHint();
      return;
    }
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);

    final frontKey = GlobalKey();
    final backKey = GlobalKey();
    var dialogShowing = false;
    try {
      // Captured before the dialog opens, so the preview isn't skewed by
      // the dialog's own DefaultTextStyle or a squeezed width.
      final savedTheme = Theme.of(context);
      final savedTextStyle = DefaultTextStyle.of(context).style;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Preparing your PDF…',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: kTextPrimary,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: kCrimson,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _pdfCapturePreview(
                    boundaryKey: frontKey,
                    theme: savedTheme,
                    textStyle: savedTextStyle,
                    card: _IdCardFront(data: data, masked: false),
                  ),
                  const SizedBox(height: 8),
                  _pdfCapturePreview(
                    boundaryKey: backKey,
                    theme: savedTheme,
                    textStyle: savedTextStyle,
                    card: _IdCardBack(data: data, masked: false),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      dialogShowing = true;

      final photoUrl = data.donor.photoUrl;
      if (photoUrl != null) {
        try {
          await precacheImage(NetworkImage(photoUrl), context);
        } catch (_) {}
      }
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      if (!_boundarySizeOk(frontKey) || !_boundarySizeOk(backKey)) {
        await WidgetsBinding.instance.endOfFrame;
      }

      final frontBytes = await _captureBoundary(frontKey);
      final backBytes = await _captureBoundary(backKey);
      if (frontBytes == null || backBytes == null) {
        throw DigitalIdServiceException('capture failed');
      }

      final doc = pw.Document(
        title: 'eDonate Digital Donor ID',
        author: 'eDonate',
      );
      const format = PdfPageFormat(
        85.6 * PdfPageFormat.mm,
        53.98 * PdfPageFormat.mm,
        marginAll: 0,
      );
      doc.addPage(
        pw.Page(
          pageFormat: format,
          build: (_) => pw.Container(
            width: format.width,
            height: format.height,
            alignment: pw.Alignment.center,
            child: pw.Image(pw.MemoryImage(frontBytes), fit: pw.BoxFit.contain),
          ),
        ),
      );
      doc.addPage(
        pw.Page(
          pageFormat: format,
          build: (_) => pw.Container(
            width: format.width,
            height: format.height,
            alignment: pw.Alignment.center,
            child: pw.Image(pw.MemoryImage(backBytes), fit: pw.BoxFit.contain),
          ),
        ),
      );

      if (dialogShowing && mounted) {
        Navigator.of(context).pop();
        dialogShowing = false;
      }

      final bytes = await doc.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'eDonate-Digital-Donor-ID-${data.card.code}.pdf',
      );
      HapticFeedback.mediumImpact();
    } catch (_) {
      if (dialogShowing && mounted) {
        Navigator.of(context).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't create the PDF. Please try again."),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  void _flip() {
    HapticFeedback.selectionClick();
    if (_isBack) {
      _flipCtrl.reverse();
    } else {
      _flipCtrl.forward();
    }
    setState(() => _isBack = !_isBack);
  }

  void _copyId() {
    final code = _data?.card.code;
    if (code == null || code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white),
            SizedBox(width: 8),
            Text('ID number copied'),
          ],
        ),
        backgroundColor: const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF9FAFB),
    body: SafeArea(
      child: Column(
        children: [
          _header(),
          Expanded(
            child: RefreshIndicator(
              color: kCrimson,
              onRefresh: _load,
              child: _body(),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _header() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                'Digital Donor ID',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Your official eDonate donor card',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        if (!_loading && !_locked && !_error)
          HeaderIconButton(
            icon: _masked
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            tooltip: _masked ? 'Show details' : 'Hide details',
            onTap: _toggleMask,
          ),
      ],
    ),
  );

  Widget _body() {
    if (_loading) return const _DigitalIdSkeleton();
    if (_error) return _errorView();
    if (_locked) return _lockedView();
    return _loadedView(_data!);
  }

  Widget _errorView() => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 60),
      const Icon(Icons.wifi_off_rounded, size: 56, color: Color(0xFF9CA3AF)),
      const SizedBox(height: 16),
      const Text(
        "Couldn't load your Digital Donor ID",
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: kTextPrimary,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Check your internet connection and try again.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: kTextMuted, height: 1.4),
      ),
      const SizedBox(height: 22),
      SizedBox(
        width: 200,
        child: PrimaryButton(label: 'Try Again', onTap: _load),
      ),
    ],
  );

  Widget _lockedView() => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 40),
      SizedBox(
        width: 96,
        height: 96,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    kCrimson.withValues(alpha: .14),
                    kCrimson.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            CircleAvatar(
              radius: 40,
              backgroundColor: kCrimson.withValues(alpha: .1),
              child: const Icon(Icons.lock_rounded, size: 40, color: kCrimson),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Unlock Your Digital Donor ID',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: kTextPrimary,
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'Complete your first blood donation to unlock your Digital Donor ID.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: kTextMuted, height: 1.5),
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: PrimaryButton(
          label: 'Book a Donation',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const BookScreen(showBackButton: true),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _loadedView(DigitalIdData data) => SingleChildScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
    child: Column(
      children: [
        FadeSlideIn(index: 0, child: _idCardScaleIn(data)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.touch_app_rounded, size: 14, color: kTextMuted),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _flip,
              child: const Text(
                'Tap the card to flip',
                style: TextStyle(fontSize: 11, color: kTextMuted),
              ),
            ),
          ],
        ),
        if (!data.card.isActive) ...[
          const SizedBox(height: 16),
          _banner(
            icon: Icons.error_outline_rounded,
            color: kCrimson,
            bg: const Color(0xFFFFF1F1),
            border: const Color(0xFFFECACA),
            text:
                'This Digital Donor ID is no longer valid. Please contact eDonate support.',
          ),
        ],
        if (!data.donor.isActive) ...[
          const SizedBox(height: 12),
          _banner(
            icon: Icons.info_outline_rounded,
            color: kTextMuted,
            bg: const Color(0xFFF3F4F6),
            border: const Color(0xFFE5E7EB),
            text: 'Your account is inactive.',
          ),
        ],
        const SizedBox(height: 18),
        FadeSlideIn(index: 1, child: _actionsRow(data)),
        const SizedBox(height: 18),
        FadeSlideIn(index: 2, child: _donorDetailsCard(data)),
        const SizedBox(height: 14),
        FadeSlideIn(index: 3, child: _donationRecordCard(data)),
        const SizedBox(height: 14),
        FadeSlideIn(index: 4, child: _eligibilityCard(data)),
      ],
    ),
  );

  Widget _banner({
    required IconData icon,
    required Color color,
    required Color bg,
    required Color border,
    required String text,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: bg,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: color, height: 1.4),
          ),
        ),
      ],
    ),
  );

  // ─── 2.4 The ID card ─────────────────────────────────────────────────────

  Widget _idCardScaleIn(DigitalIdData data) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.94, end: 1.0),
    duration: const Duration(milliseconds: 500),
    curve: Curves.easeOutBack,
    builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
    child: Stack(
      alignment: Alignment.center,
      children: [
        GestureDetector(
          onTap: _flip,
          child: AspectRatio(
            aspectRatio: 1.586,
            child: AnimatedBuilder(
              animation: _flipCtrl,
              builder: (context, child) {
                final angle = _flipCtrl.value * math.pi;
                final showBack = _flipCtrl.value >= 0.5;
                final display = showBack
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..rotateY(math.pi),
                        child: _IdCardBack(
                          data: data,
                          masked: _masked,
                          onQrTap: () => _showQrSheet(data),
                          onMaskedQrTap: _showMaskedQrHint,
                        ),
                      )
                    : _IdCardFront(data: data, masked: _masked);
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateY(angle),
                  child: display,
                );
              },
            ),
          ),
        ),
        if (!data.card.isActive)
          Transform.rotate(
            angle: -12 * math.pi / 180,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: kCrimson, width: 3),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white.withValues(alpha: .85),
              ),
              child: const Text(
                'REVOKED',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: kCrimson,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  // ─── 4. Full-size "Show QR Code" sheet ──────────────────────────────────

  Widget _qrSheetBody(BuildContext sheetContext, DigitalIdData data) {
    final screenWidth = MediaQuery.of(sheetContext).size.width;
    final qrSize = math.min(screenWidth - 96, 280.0);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        24 + MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
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
          const SizedBox(height: 18),
          const Text(
            'Scan to Verify',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: kTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Show this to the facility staff',
            style: TextStyle(fontSize: 13, color: kTextMuted),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.9, end: 1.0),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              builder: (_, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: _qrBox(data.card.qrPayload!, size: qrSize),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            data.donor.fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: kTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.card.code,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              letterSpacing: 1.2,
              color: kTextMuted,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              border: Border.all(color: const Color(0xFFBFDBFE)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  _brightnessBoosted
                      ? Icons.brightness_high_rounded
                      : Icons.light_mode_rounded,
                  size: 16,
                  color: const Color(0xFF1D4ED8),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _brightnessBoosted
                        ? 'Brightness turned up for easier scanning.'
                        : 'Turn your screen brightness up for faster scanning.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1D4ED8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(sheetContext),
              style: OutlinedButton.styleFrom(
                foregroundColor: kCrimson,
                side: const BorderSide(color: kCrimson, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 2.5 Actions row ─────────────────────────────────────────────────────

  Widget _actionsRow(DigitalIdData data) => Column(
    children: [
      if (data.card.qrPayload != null) ...[
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: () => _showQrSheet(data),
            icon: const Icon(Icons.qr_code_2_rounded, size: 20),
            label: const Text('Show QR Code'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kCrimson,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
      Row(
        children: [
          Expanded(
            child: _actionButton(
              icon: Icons.copy_rounded,
              label: 'Copy ID',
              onTap: _copyId,
              color: kCrimson,
              borderColor: kCrimson,
            ),
          ),
          if (data.card.qrPayload != null) ...[
            const SizedBox(width: 12),
            Expanded(
              child: _actionButton(
                icon: Icons.picture_as_pdf_rounded,
                label: _pdfBusy ? 'Preparing…' : 'Download PDF',
                onTap: _pdfBusy ? null : () => _downloadPdf(data),
                color: kCrimson,
                borderColor: kCrimson,
              ),
            ),
          ],
        ],
      ),
    ],
  );

  // ─── 2.6 Details cards ───────────────────────────────────────────────────

  Widget _detailCard(String title, List<Widget> rows) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: kBorder),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: kTextPrimary,
          ),
        ),
        const SizedBox(height: 8),
        ...rows,
      ],
    ),
  );

  Widget _detailRow(IconData icon, String label, Widget value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1F1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: kCrimson),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: kTextMuted),
              ),
              const SizedBox(height: 2),
              value,
            ],
          ),
        ),
      ],
    ),
  );

  Widget _donorDetailsCard(DigitalIdData data) {
    final donor = data.donor;
    final birthdateValue = _masked
        ? (data.masked.birthdate ?? '—')
        : donor.birthdate == null
        ? '—'
        : '${_longDate(donor.birthdate)}${donor.age != null ? ' · ${donor.age} years old' : ''}';

    return _detailCard('Donor Details', [
      _detailRow(
        Icons.person_rounded,
        'Gender',
        _maskedSwitcher(
          _boldTextStandalone(
            donor.gender ?? '—',
            key: const ValueKey('gender'),
          ),
        ),
      ),
      _detailRow(
        Icons.cake_rounded,
        'Birthdate',
        _maskedSwitcher(
          _boldTextStandalone(birthdateValue, key: ValueKey('bday_$_masked')),
        ),
      ),
      _detailRow(
        Icons.call_rounded,
        'Contact',
        _maskedSwitcher(
          _boldTextStandalone(
            _masked
                ? (data.masked.contactNumber ?? '—')
                : (donor.contactNumber ?? '—'),
            key: ValueKey('contact_$_masked'),
          ),
        ),
      ),
      _detailRow(
        Icons.location_on_rounded,
        'Address',
        _maskedSwitcher(
          _boldTextStandalone(
            _masked
                ? (data.masked.addressLine ?? '—')
                : (donor.addressLine ?? '—'),
            key: ValueKey('address_$_masked'),
          ),
        ),
      ),
      _detailRow(
        Icons.verified_user_rounded,
        'Identity',
        donor.isVerified
            ? const Text(
                'Verified',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF16A34A),
                ),
              )
            : const Text(
                'Not verified',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFD97706),
                ),
              ),
      ),
    ]);
  }

  Widget _donationRecordCard(DigitalIdData data) {
    final d = data.donations;
    return _detailCard('Donation Record', [
      Row(
        children: [
          Expanded(
            child: _statTile(
              Icons.water_drop_rounded,
              kCrimson,
              '${d.total}',
              'Donations',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statTile(
              Icons.bloodtype_rounded,
              const Color(0xFFEC4899),
              '${d.totalUnits}',
              'Units',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statTile(
              Icons.favorite_rounded,
              const Color(0xFF16A34A),
              '${d.livesHelped}',
              'Lives Helped',
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          const Icon(Icons.flag_rounded, size: 14, color: kTextMuted),
          const SizedBox(width: 6),
          const Text(
            'First donation',
            style: TextStyle(fontSize: 12, color: kTextMuted),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'First',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: kCrimson,
              ),
            ),
          ),
          const Spacer(),
          Text(
            _longDate(d.firstDonationDate),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kTextPrimary,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          const Icon(Icons.history_rounded, size: 14, color: kTextMuted),
          const SizedBox(width: 6),
          const Text(
            'Last donation',
            style: TextStyle(fontSize: 12, color: kTextMuted),
          ),
          const Spacer(),
          Text(
            _longDate(d.lastDonationDate),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kTextPrimary,
            ),
          ),
        ],
      ),
    ]);
  }

  Widget _statTile(IconData icon, Color color, String value, String label) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: kTextMuted),
            ),
          ],
        ),
      );

  Widget _eligibilityCard(DigitalIdData data) {
    final elig = data.eligibility;
    Color color;
    switch (elig?.status) {
      case 'eligible':
        color = const Color(0xFF16A34A);
        break;
      case 'temporary_deferred':
      case 'pending':
      case 'for_review':
        color = const Color(0xFFD97706);
        break;
      case 'not_eligible':
        color = kCrimson;
        break;
      default:
        color = kTextMuted;
    }
    return _detailCard('Eligibility', [
      Row(
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 8),
          Text(
            elig?.label ?? 'Unknown',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
      if (elig?.nextEligibleDate != null) ...[
        const SizedBox(height: 8),
        Text(
          'Next eligible: ${_longDate(elig!.nextEligibleDate)}',
          style: const TextStyle(fontSize: 12, color: kTextMuted),
        ),
      ],
    ]);
  }
}

// ─── Pure helpers shared by the State class and the standalone card widgets ─

String _initialsFor(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

String _shortDate(String? value) {
  if (value == null) return '—';
  final d = DateTime.tryParse(value);
  if (d == null) return value;
  const months = [
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
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

String _longDate(String? value) {
  if (value == null) return '—';
  final d = DateTime.tryParse(value);
  if (d == null) return value;
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
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

String _memberSinceLabel(String? value) {
  if (value == null) return 'Member since —';
  final d = DateTime.tryParse(value);
  if (d == null) return 'Member since $value';
  const months = [
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
  return 'Member since ${months[d.month - 1]} ${d.year}';
}

// Whether the next-eligible value should read as a date or "Eligible now".
(String, Color) _nextEligibleDisplay(DigitalIdData data) {
  final elig = data.eligibility;
  final raw = elig?.nextEligibleDate;
  final date = raw != null ? DateTime.tryParse(raw) : null;
  if (date != null) {
    final today = DateTime.now();
    final dateOnly = DateTime(date.year, date.month, date.day);
    final todayOnly = DateTime(today.year, today.month, today.day);
    if (!dateOnly.isAfter(todayOnly)) {
      return ('Eligible now', const Color(0xFFBBF7D0));
    }
    return (_shortDate(raw), Colors.white);
  }
  if (elig?.status == 'eligible') {
    return ('Eligible now', const Color(0xFFBBF7D0));
  }
  return ('—', Colors.white);
}

Widget _maskedSwitcher(Widget child) =>
    AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: child);

Widget _actionButton({
  required IconData icon,
  required String label,
  required VoidCallback? onTap,
  required Color color,
  required Color borderColor,
}) => OutlinedButton(
  onPressed: onTap,
  style: OutlinedButton.styleFrom(
    side: BorderSide(color: borderColor, width: 1.5),
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ).copyWith(foregroundColor: WidgetStatePropertyAll(color)),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18),
      const SizedBox(height: 4),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    ],
  ),
);

Widget _qrBox(String payload, {double size = 116}) => Container(
  padding: const EdgeInsets.all(6),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: const Color(0xFFE5E7EB)),
  ),
  child: QrImageView(
    data: payload,
    version: QrVersions.auto,
    size: size,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
    backgroundColor: Colors.white,
    gapless: true,
    padding: EdgeInsets.zero,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Color(0xFF111827),
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Color(0xFF111827),
    ),
    errorStateBuilder: (context, error) => _qrErrorContent(),
  ),
);

Widget _qrErrorContent() => const Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.qr_code_2_rounded, size: 40, color: kTextMuted),
      SizedBox(height: 6),
      Text('QR unavailable', style: TextStyle(fontSize: 10, color: kTextMuted)),
    ],
  ),
);

Widget _infoStripHalf(String label, String value, Color valueColor) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisSize: MainAxisSize.min,
  children: [
    Text(
      label,
      style: const TextStyle(
        fontSize: 8,
        fontWeight: FontWeight.w700,
        color: Colors.white70,
        letterSpacing: 1,
      ),
    ),
    const SizedBox(height: 2),
    FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        value,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: valueColor,
        ),
      ),
    ),
  ],
);

// Slim strip on the card front showing the last donation and next eligible
// dates — not sensitive, so it stays visible even while details are masked.
Widget _infoStrip(DigitalIdData data) {
  final next = _nextEligibleDisplay(data);
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Expanded(
          child: _infoStripHalf(
            'LAST DONATION',
            _shortDate(data.donations.lastDonationDate),
            Colors.white,
          ),
        ),
        Container(
          width: 1,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          color: Colors.white.withValues(alpha: .25),
        ),
        Expanded(child: _infoStripHalf('NEXT ELIGIBLE', next.$1, next.$2)),
      ],
    ),
  );
}

// ─── Standalone card front/back — shared by the on-screen flip animation ───
// and the PDF capture, so the exported PDF always matches what's on screen.

class _IdCardFront extends StatelessWidget {
  final DigitalIdData data;
  final bool masked;

  const _IdCardFront({required this.data, required this.masked});

  @override
  Widget build(BuildContext context) {
    final donor = data.donor;
    final card = data.card;
    return AspectRatio(
      aspectRatio: 1.586,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: kCardCanvasWidth,
          height: kCardCanvasHeight,
          child: MediaQuery.withNoTextScaling(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF7F1D1D),
                      Color(0xFFDC2626),
                      Color(0xFFEF4444),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kCrimson.withValues(alpha: .35),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(painter: _DiagonalSheenPainter()),
                    ),
                    Positioned(
                      right: -10,
                      bottom: -10,
                      child: CustomPaint(
                        size: const Size(140, 170),
                        painter: _DropWatermarkPainter(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const _MiniDrop(size: 16),
                              const SizedBox(width: 6),
                              const Text(
                                'eDonate',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              const Spacer(),
                              const Text(
                                'DIGITAL DONOR ID',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white70,
                                  letterSpacing: 1.4,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 8,
                                        offset: Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(11),
                                    child: _AvatarPhoto(
                                      photoUrl: donor.photoUrl,
                                      photoPath: donor.photoPath,
                                      initials: _initialsFor(donor.fullName),
                                      size: 54,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        donor.fullName,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              donor.bloodType ?? '—',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w900,
                                                color: kCrimson,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          if (donor.bloodTypeVerified)
                                            const Icon(
                                              Icons.verified_rounded,
                                              size: 14,
                                              color: Color(0xFF16A34A),
                                            )
                                          else
                                            const Text(
                                              'Unconfirmed',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFFFDE68A),
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
                          _infoStrip(data),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _maskedSwitcher(
                                Text(
                                  masked ? card.codeMasked : card.code,
                                  key: ValueKey(masked),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 1.5,
                                  ),
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
          ),
        ),
      ),
    );
  }
}

class _IdCardBack extends StatelessWidget {
  final DigitalIdData data;
  final bool masked;
  final VoidCallback? onQrTap;
  final VoidCallback? onMaskedQrTap;

  const _IdCardBack({
    required this.data,
    required this.masked,
    this.onQrTap,
    this.onMaskedQrTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = data.card;
    final qrSize = kCardCanvasHeight * 0.62;
    return AspectRatio(
      aspectRatio: 1.586,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: kCardCanvasWidth,
          height: kCardCanvasHeight,
          child: MediaQuery.withNoTextScaling(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: card.qrPayload == null
                            ? const Center(
                                child: Text(
                                  'This ID is not active',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: kTextMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            : Row(
                                children: [
                                  _maskedSwitcher(
                                    masked
                                        ? GestureDetector(
                                            key: const ValueKey('blurred_qr'),
                                            onTap: onMaskedQrTap,
                                            child: ImageFiltered(
                                              imageFilter: ImageFilter.blur(
                                                sigmaX: 8,
                                                sigmaY: 8,
                                              ),
                                              child: _qrBox(
                                                card.qrPayload!,
                                                size: qrSize,
                                              ),
                                            ),
                                          )
                                        : GestureDetector(
                                            key: const ValueKey('qr'),
                                            onTap: onQrTap,
                                            child: _qrBox(
                                              card.qrPayload!,
                                              size: qrSize,
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Scan to verify',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: kTextPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            'Staff can scan this to confirm your ID is genuine.',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: kTextMuted,
                                              height: 1.3,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _memberSinceLabel(
                                              data.donor.memberSince,
                                            ),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: kTextMuted,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Issued ${_shortDate(card.issuedOn)}',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: kTextMuted,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          _maskedSwitcher(
                                            Text(
                                              masked
                                                  ? card.codeMasked
                                                  : card.code,
                                              key: ValueKey('back_$masked'),
                                              style: const TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 12,
                                                color: kTextPrimary,
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
                    if (masked && card.qrPayload != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: kBorder),
                          ),
                          child: const Text(
                            'Tap the eye to show',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: kTextPrimary,
                            ),
                          ),
                        ),
                      ),
                    Container(
                      width: double.infinity,
                      color: kCrimson,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: const Text(
                        'eDonate · Lipa City Blood Donation Network',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          letterSpacing: 0.6,
                        ),
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
  }
}

// Small helper so masked-value texts can carry a ValueKey for
// AnimatedSwitcher without repeating the TextStyle everywhere.
Widget _boldTextStandalone(String text, {Key? key, Color? color}) => Text(
  text,
  key: key,
  style: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: color ?? kTextPrimary,
  ),
);

// ─── Cascading photo → resolved-path photo → initials avatar ───────────────

class _AvatarPhoto extends StatefulWidget {
  final String? photoUrl;
  final String? photoPath;
  final String initials;
  final double size;

  const _AvatarPhoto({
    required this.photoUrl,
    required this.photoPath,
    required this.initials,
    required this.size,
  });

  @override
  State<_AvatarPhoto> createState() => _AvatarPhotoState();
}

class _AvatarPhotoState extends State<_AvatarPhoto> {
  late int _stage;

  @override
  void initState() {
    super.initState();
    _stage = widget.photoUrl != null
        ? 0
        : (resolveMediaUrl(widget.photoPath) != null ? 1 : 2);
  }

  String? get _currentUrl {
    if (_stage == 0) return widget.photoUrl;
    if (_stage == 1) return resolveMediaUrl(widget.photoPath);
    return null;
  }

  void _advance(int fromStage) {
    if (!mounted || _stage != fromStage) return;
    final next = fromStage == 0
        ? (resolveMediaUrl(widget.photoPath) != null ? 1 : 2)
        : 2;
    setState(() => _stage = next);
  }

  @override
  Widget build(BuildContext context) {
    final url = _currentUrl;
    if (url == null) return _initialsBox();
    final stageAtBuild = _stage;
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: widget.size,
      height: widget.size,
      errorBuilder: (_, _, _) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _advance(stageAtBuild),
        );
        return _initialsBox();
      },
    );
  }

  Widget _initialsBox() => Container(
    width: widget.size,
    height: widget.size,
    color: Colors.white,
    alignment: Alignment.center,
    child: Text(
      widget.initials,
      style: TextStyle(
        color: kCrimson,
        fontWeight: FontWeight.w800,
        fontSize: widget.size * 0.34,
      ),
    ),
  );
}

class _MiniDrop extends StatelessWidget {
  final double size;
  const _MiniDrop({required this.size});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size * 1.25), painter: _MiniDropPainter());
}

class _MiniDropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..cubicTo(w * 0.5, 0, 0, h * 0.42, 0, h * 0.66)
      ..cubicTo(0, h * 0.87, w * 0.25, h, w * 0.5, h)
      ..cubicTo(w * 0.75, h, w, h * 0.87, w, h * 0.66)
      ..cubicTo(w, h * 0.42, w * 0.5, 0, w * 0.5, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _MiniDropPainter oldDelegate) => false;
}

// Huge, faint droplet watermark in the card's bottom-right corner — same
// path shape as home.dart's private _BloodDropPainter, re-implemented here
// since that one isn't exported.
class _DropWatermarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .08)
      ..style = PaintingStyle.fill;
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..cubicTo(w * 0.5, 0, w * 0.12, h * 0.42, w * 0.12, h * 0.66)
      ..cubicTo(w * 0.12, h * 0.87, w * 0.28, h, w * 0.5, h)
      ..cubicTo(w * 0.72, h, w * 0.88, h * 0.87, w * 0.88, h * 0.66)
      ..cubicTo(w * 0.88, h * 0.42, w * 0.5, 0, w * 0.5, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DropWatermarkPainter oldDelegate) => false;
}

// Two faint diagonal light bands for a laminated-card look.
class _DiagonalSheenPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: .06);
    canvas.save();
    canvas.translate(size.width * 0.15, 0);
    canvas.skew(-0.5, 0);
    canvas.drawRect(
      Rect.fromLTWH(0, -20, size.width * 0.12, size.height + 40),
      paint,
    );
    canvas.restore();
    canvas.save();
    canvas.translate(size.width * 0.45, 0);
    canvas.skew(-0.5, 0);
    canvas.drawRect(
      Rect.fromLTWH(0, -20, size.width * 0.08, size.height + 40),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DiagonalSheenPainter oldDelegate) => false;
}

// ─── Loading skeleton ───────────────────────────────────────────────────────

class _DigitalIdSkeleton extends StatefulWidget {
  const _DigitalIdSkeleton();

  @override
  State<_DigitalIdSkeleton> createState() => _DigitalIdSkeletonState();
}

class _DigitalIdSkeletonState extends State<_DigitalIdSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 0.5,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _block({double? height, double radius = 16}) => Container(
    width: double.infinity,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(radius),
    ),
  );

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      children: [
        AspectRatio(aspectRatio: 1.586, child: _block(radius: 20)),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: _block(height: 44)),
            const SizedBox(width: 12),
            Expanded(child: _block(height: 44)),
          ],
        ),
        const SizedBox(height: 18),
        _block(height: 180),
        const SizedBox(height: 14),
        _block(height: 140),
        const SizedBox(height: 14),
        _block(height: 90),
      ],
    ),
  );
}
