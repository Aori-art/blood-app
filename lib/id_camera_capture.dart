import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'config.dart';
import 'shared_design.dart';

enum _CaptureStep {
  selectType,
  captureFront,
  reviewFront,
  backChoice,
  captureBack,
  reviewBack,
  processing,
}

enum _CaptureSide { front, back }

// Guided, step-by-step camera capture flow for ID verification — an
// alternative entry point to VerifyScreen's manual gallery upload that
// submits through the exact same backend contract.
class IdCameraCaptureScreen extends StatefulWidget {
  final List<Map<String, String>> documentTypes;
  final Set<String> backOptionalTypes;
  final int donorId;

  const IdCameraCaptureScreen({
    super.key,
    required this.documentTypes,
    required this.backOptionalTypes,
    required this.donorId,
  });

  @override
  State<IdCameraCaptureScreen> createState() => _IdCameraCaptureScreenState();
}

class _IdCameraCaptureScreenState extends State<IdCameraCaptureScreen>
    with SingleTickerProviderStateMixin {
  static const _statusLines = ['Uploading photos...', 'Almost done...'];

  _CaptureStep _step = _CaptureStep.selectType;

  String? _documentType;
  XFile? _frontImage;
  XFile? _backImage;

  String? _captureError;

  bool _submitSucceeded = false;
  String? _submitError;

  Timer? _statusTimer;
  int _statusIndex = 0;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  bool get _backRequired =>
      _documentType == null || !widget.backOptionalTypes.contains(_documentType);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _statusTimer?.cancel();
    super.dispose();
  }

  void _goTo(_CaptureStep step) => setState(() => _step = step);

  Future<void> _capture(_CaptureSide side) async {
    setState(() => _captureError = null);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (!mounted || picked == null) return;
      setState(() {
        if (side == _CaptureSide.front) {
          _frontImage = picked;
          _step = _CaptureStep.reviewFront;
        } else {
          _backImage = picked;
          _step = _CaptureStep.reviewBack;
        }
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _captureError = e.code == 'camera_access_denied'
            ? "Camera access is required to continue. Please grant camera "
                "permission in your device settings and try again."
            : 'Unable to open the camera. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _captureError = 'Unable to open the camera. Please try again.');
    }
  }

  void _retake(_CaptureSide side) {
    setState(() {
      _step = side == _CaptureSide.front
          ? _CaptureStep.captureFront
          : _CaptureStep.captureBack;
    });
    _capture(side);
  }

  void _continueFromReview(_CaptureSide side) {
    if (side == _CaptureSide.front) {
      _goTo(_backRequired ? _CaptureStep.captureBack : _CaptureStep.backChoice);
    } else {
      _startSubmission();
    }
  }

  void _startSubmission() {
    setState(() => _step = _CaptureStep.processing);
    _submit();
  }

  void _startStatusCycle() {
    _statusIndex = 0;
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!mounted) return;
      setState(() => _statusIndex = (_statusIndex + 1) % _statusLines.length);
    });
  }

  void _stopStatusCycle() {
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  // Mirrors _VerifyScreenState._submit()'s exact request construction so
  // both upload paths stay in sync with the backend's expected shape.
  Future<void> _submit() async {
    if (!mounted) return;
    setState(() {
      _submitError = null;
      _submitSucceeded = false;
    });
    _startStatusCycle();
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}/submit_verification.php'),
      );
      request.fields['donor_id'] = widget.donorId.toString();
      request.fields['document_type'] = _documentType!;
      request.files.add(
        await http.MultipartFile.fromPath('id_front', _frontImage!.path),
      );
      if (_backImage != null) {
        request.files.add(
          await http.MultipartFile.fromPath('id_back', _backImage!.path),
        );
      }

      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      dynamic body;
      try {
        body = jsonDecode(response.body);
      } catch (_) {
        body = {};
      }

      _stopStatusCycle();
      if (!mounted) return;

      if (body is Map && body['success'] == true) {
        setState(() => _submitSucceeded = true);
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) Navigator.of(context).pop(true);
      } else {
        final code = body is Map ? body['code']?.toString() : null;
        final message = body is Map ? body['message']?.toString() : null;
        setState(() => _submitError = _errorMessageFor(code, message));
      }
    } catch (_) {
      _stopStatusCycle();
      if (!mounted) return;
      setState(() {
        _submitError =
            'Unable to reach the server. Please check your connection and try again.';
      });
    }
  }

  String _errorMessageFor(String? code, String? message) {
    switch (code) {
      case 'ALREADY_VERIFIED':
        return "You're already verified — there's no need to resubmit.";
      case 'VERIFICATION_PENDING':
        return 'You already have a submission awaiting review.';
      case 'INVALID_FILE_TYPE':
        return 'Please upload a JPG or PNG photo of your ID.';
      case 'FILE_TOO_LARGE':
        return 'One of your photos is too large. Please upload a smaller file.';
      case 'MISSING_FRONT':
        return 'Please upload a photo of the front of your ID.';
      case 'MISSING_BACK':
        return 'Please upload a photo of the back of your ID.';
      case 'INVALID_DOCUMENT_TYPE':
        return 'Please select a valid ID type.';
      case 'UPLOAD_FAILED':
        return "We couldn't save your photos. Please try again.";
      default:
        return message ?? 'Something went wrong. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF9FAFB),
    body: SafeArea(
      child: Column(
        children: [
          _header(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _stepBody(),
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
          onTap: () => Navigator.of(context).pop(false),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Text(
            'Verify with Your Camera',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _stepBody() {
    switch (_step) {
      case _CaptureStep.selectType:
        return _selectTypeStep();
      case _CaptureStep.captureFront:
        return _captureInstructionStep(_CaptureSide.front);
      case _CaptureStep.reviewFront:
        return _reviewStep(_CaptureSide.front);
      case _CaptureStep.backChoice:
        return _backChoiceStep();
      case _CaptureStep.captureBack:
        return _captureInstructionStep(_CaptureSide.back);
      case _CaptureStep.reviewBack:
        return _reviewStep(_CaptureSide.back);
      case _CaptureStep.processing:
        return _processingStep();
    }
  }

  // ─── a) Type selection ───────────────────────────────────────────────────
  Widget _selectTypeStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'What type of ID are you uploading?',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: kTextPrimary),
      ),
      const SizedBox(height: 6),
      const Text(
        "We'll guide you through photographing it correctly.",
        style: TextStyle(fontSize: 13, color: kTextMuted),
      ),
      const SizedBox(height: 20),
      Expanded(
        child: ListView.separated(
          itemCount: widget.documentTypes.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final type = widget.documentTypes[i];
            final selected = _documentType == type['value'];
            return InkWell(
              onTap: () => setState(() => _documentType = type['value']),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFFFFF1F1) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? kCrimson : kBorder,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected ? kCrimson : kTextMuted,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        type['label']!,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: kTextPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 16),
      PrimaryButton(
        label: 'Continue',
        onTap: _documentType == null
            ? null
            : () => _goTo(_CaptureStep.captureFront),
      ),
    ],
  );

  // ─── b/d) Instructional capture screen (front, or back when required) ───
  Widget _captureInstructionStep(_CaptureSide side) {
    final isFront = side == _CaptureSide.front;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          isFront ? Icons.credit_card_rounded : Icons.flip_rounded,
          color: kCrimson,
          size: 56,
        ),
        const SizedBox(height: 20),
        Text(
          isFront
              ? 'Take a photo of the FRONT of your ID'
              : 'Take a photo of the BACK of your ID',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: kTextPrimary),
        ),
        const SizedBox(height: 10),
        const Text(
          "Make sure all four corners are visible and there's no glare.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: kTextMuted, height: 1.5),
        ),
        const SizedBox(height: 32),
        if (_captureError != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              border: Border.all(color: const Color(0xFFFECACA)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              _captureError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kCrimson, fontSize: 12, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
        ],
        InkWell(
          onTap: () => _capture(side),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: kCrimson, shape: BoxShape.circle),
            child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 34),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _captureError != null ? 'Tap to try again' : 'Tap to open camera',
          style: const TextStyle(fontSize: 12, color: kTextMuted),
        ),
      ],
    );
  }

  // ─── c/e) Review captured photo ───────────────────────────────────────────
  Widget _reviewStep(_CaptureSide side) {
    final isFront = side == _CaptureSide.front;
    final image = isFront ? _frontImage : _backImage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isFront ? 'Review front photo' : 'Review back photo',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: kTextPrimary),
        ),
        const SizedBox(height: 6),
        const Text(
          'Make sure the ID is clear and readable.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: kTextMuted),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: image == null
                ? const SizedBox()
                : Image.file(File(image.path), fit: BoxFit.cover, width: double.infinity),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: OutlineBtn(label: 'Retake', onTap: () => _retake(side))),
            const SizedBox(width: 12),
            Expanded(
              child: PrimaryButton(
                label: 'Continue',
                onTap: () => _continueFromReview(side),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── d) Optional back-photo choice ────────────────────────────────────────
  Widget _backChoiceStep() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.flip_rounded, color: kCrimson, size: 56),
      const SizedBox(height: 20),
      const Text(
        'Add a photo of the back? (optional)',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: kTextPrimary),
      ),
      const SizedBox(height: 10),
      const Text(
        'Some IDs have important details on the back. You can skip this if it '
        "doesn't apply to yours.",
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: kTextMuted, height: 1.5),
      ),
      const SizedBox(height: 32),
      PrimaryButton(
        label: 'Take Photo',
        onTap: () {
          setState(() => _step = _CaptureStep.captureBack);
          _capture(_CaptureSide.back);
        },
      ),
      const SizedBox(height: 12),
      OutlineBtn(label: 'Skip', onTap: _startSubmission),
    ],
  );

  // ─── f) Processing / submitting ──────────────────────────────────────────
  Widget _processingStep() {
    if (_submitSucceeded) {
      return _resultGlow(
        color: const Color(0xFF16A34A),
        icon: Icons.check_circle_rounded,
        title: 'Submitted!',
        subtitle: 'Redirecting you back...',
        pulse: false,
      );
    }
    if (_submitError != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _resultGlow(
            color: kCrimson,
            icon: Icons.error_outline_rounded,
            title: 'Submission Failed',
            subtitle: _submitError!,
            pulse: false,
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlineBtn(
                  label: 'Back',
                  onTap: () => setState(() {
                    _submitError = null;
                    _step = _backImage != null
                        ? _CaptureStep.reviewBack
                        : _CaptureStep.reviewFront;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton(label: 'Try Again', onTap: _submit),
              ),
            ],
          ),
        ],
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _resultGlow(
          color: kCrimson,
          icon: Icons.cloud_upload_rounded,
          title: 'Processing your ID...',
          subtitle: 'This will only take a moment.',
          pulse: true,
        ),
        const SizedBox(height: 14),
        Text(
          _statusLines[_statusIndex],
          style: const TextStyle(fontSize: 12, color: kTextMuted),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: 160,
          child: OutlineBtn(
            label: 'Exit',
            onTap: () => Navigator.of(context).pop(false),
          ),
        ),
      ],
    );
  }

  // Mirrors _VerifyScreenState._animatedHero's soft radial-glow structure.
  Widget _resultGlow({
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool pulse,
  }) {
    final hero = SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [color.withValues(alpha: .22), color.withValues(alpha: 0)],
              ),
            ),
          ),
          CircleAvatar(
            radius: 48,
            backgroundColor: color.withValues(alpha: .12),
            child: Icon(icon, size: 54, color: color),
          ),
        ],
      ),
    );
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        pulse ? ScaleTransition(scale: _pulse, child: hero) : hero,
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: kTextPrimary),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: kTextMuted, height: 1.5),
        ),
      ],
    );
  }
}
