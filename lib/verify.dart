import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'shared_design.dart';

// Donor identity verification — upload a photo of a valid ID and pick its
// type, then submit to the backend for manual review.
class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen>
    with TickerProviderStateMixin {
  static const List<Map<String, String>> _documentTypes = [
    {'value': 'national_id', 'label': 'National ID'},
    {'value': 'school_id', 'label': 'School ID'},
    {'value': 'company_id', 'label': 'Company ID'},
    {'value': 'barangay_certificate', 'label': 'Barangay Certificate'},
    {'value': 'government_id', 'label': 'Government-issued ID'},
    {'value': 'other', 'label': 'Other'},
  ];

  static const List<String> _donationFacts = [
    'One donation can help save up to 3 lives.',
    'Your blood type is re-checked and confirmed at every donation.',
    'A healthy adult can safely donate blood roughly every 3 months.',
    "There's no substitute for donated blood — it can't be manufactured.",
  ];

  int _donorId = 0;
  bool _loadingStatus = true;
  String _verificationStatus = 'unverified';
  Map<String, dynamic>? _latestSubmission;

  XFile? _idImage;
  String? _documentType;
  bool _submitting = false;

  late final AnimationController _resultAnimation;
  late final AnimationController _refreshIconController;
  late final String _fact = (List<String>.from(_donationFacts)..shuffle()).first;

  @override
  void initState() {
    super.initState();
    _resultAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _refreshIconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fetchStatus();
  }

  @override
  void dispose() {
    _resultAnimation.dispose();
    _refreshIconController.dispose();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = int.tryParse(prefs.getString('donorId') ?? '') ?? 0;
    if (!mounted) return;
    _donorId = donorId;

    if (donorId <= 0) {
      setState(() => _loadingStatus = false);
      return;
    }

    try {
      final response = await http
          .get(
            Uri.parse(
              '${AppConfig.baseUrl}/get_verification_status.php?donor_id=$donorId',
            ),
          )
          .timeout(const Duration(seconds: 12));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['status'] == 'success') {
          final status = (data['verification_status'] as String?) ?? 'unverified';
          setState(() {
            _verificationStatus = status;
            _latestSubmission = data['latest_submission'] is Map
                ? Map<String, dynamic>.from(data['latest_submission'])
                : null;
            _loadingStatus = false;
          });
          if (status != 'unverified') _resultAnimation.forward(from: 0);
          return;
        }
      }
      setState(() => _loadingStatus = false);
    } catch (e) {
      debugPrint('Error fetching verification status: $e');
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  Future<void> _onManualRefresh() async {
    _refreshIconController.forward(from: 0);
    await _fetchStatus();
  }

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() => _idImage = picked);
      }
    } catch (_) {
      _showSnack('Unable to open your gallery. Please try again.', isError: true);
    }
  }

  void _removeImage() => setState(() => _idImage = null);

  bool get _canSubmit =>
      !_submitting && _documentType != null && _idImage != null;

  Future<void> _submit() async {
    if (!_canSubmit) return;

    if (_donorId <= 0) {
      _showSnack('Unable to find your account. Please sign in again.', isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}/submit_verification.php'),
      );
      request.fields['donor_id'] = _donorId.toString();
      request.fields['document_type'] = _documentType!;
      request.files.add(
        await http.MultipartFile.fromPath('id_photo', _idImage!.path),
      );

      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      dynamic body;
      try {
        body = jsonDecode(response.body);
      } catch (_) {
        body = {};
      }

      if (!mounted) return;

      if (body is Map && body['success'] == true) {
        setState(() {
          _idImage = null;
          _documentType = null;
        });
        _showSnack('Your ID was submitted for verification.');
        await _fetchStatus();
      } else {
        final code = body is Map ? body['code']?.toString() : null;
        final message = body is Map ? body['message']?.toString() : null;
        _showSnack(_errorMessageFor(code, message), isError: true);
      }
    } catch (_) {
      _showSnack(
        'Unable to reach the server. Please check your connection and try again.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
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
        return 'That photo is too large. Please upload a smaller file.';
      default:
        return message ?? 'Something went wrong. Please try again.';
    }
  }

  void _showSnack(String message, {bool isError = false}) {
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
        backgroundColor: isError ? kCrimson : const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _documentTypeLabel(String value) {
    for (final d in _documentTypes) {
      if (d['value'] == value) return d['label']!;
    }
    return value;
  }

  String _formatDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF9FAFB),
    body: SafeArea(
      child: Column(
        children: [
          _header(context),
          Expanded(child: _loadingStatus ? _loadingBody() : _statusBody()),
        ],
      ),
    ),
  );

  Widget _header(BuildContext context) => Container(
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
                'Verify Your Identity',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Upload a valid ID to unlock full access',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        RotationTransition(
          turns: _refreshIconController,
          child: HeaderIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh status',
            onTap: _loadingStatus ? () {} : _onManualRefresh,
          ),
        ),
      ],
    ),
  );

  Widget _loadingBody() => const Center(
    child: CircularProgressIndicator(color: kCrimson),
  );

  Widget _statusBody() => RefreshIndicator(
    onRefresh: _fetchStatus,
    color: kCrimson,
    child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      child: _bodyContent(),
    ),
  );

  Widget _bodyContent() {
    switch (_verificationStatus) {
      case 'verified':
        return _verifiedState();
      case 'pending':
        return _pendingState();
      case 'rejected':
        return _rejectedState();
      default:
        return _uploadFormBody();
    }
  }

  // ─── Animated hero icon (shared by pending/verified/rejected) ────────────
  // Mirrors check.dart's _resultAnimation: a soft radial glow behind a
  // CircleAvatar icon, scaled+faded in with easeOutBack.
  Widget _animatedHero({
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
  }) => ScaleTransition(
    scale: CurvedAnimation(parent: _resultAnimation, curve: Curves.easeOutBack),
    child: FadeTransition(
      opacity: _resultAnimation,
      child: Column(
        children: [
          SizedBox(
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
                      colors: [
                        color.withValues(alpha: .22),
                        color.withValues(alpha: 0),
                      ],
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
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: kTextPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: kTextMuted, height: 1.5),
          ),
        ],
      ),
    ),
  );

  // ─── Submitted → Under Review → Verified/Rejected stepper ────────────────
  Color _stepColor(String status, int step) {
    switch (status) {
      case 'verified':
        return const Color(0xFF16A34A);
      case 'rejected':
        return step < 2 ? const Color(0xFF16A34A) : kCrimson;
      case 'pending':
      default:
        if (step == 0) return const Color(0xFF16A34A);
        if (step == 1) return const Color(0xFFD97706);
        return kBorder;
    }
  }

  Widget _statusStepper(String status) {
    final labels = ['Submitted', 'Under Review', status == 'rejected' ? 'Rejected' : 'Verified'];
    Widget dot(int i) {
      final color = _stepColor(status, i);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            labels[i],
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color == kBorder ? kTextMuted : kTextPrimary,
            ),
          ),
        ],
      );
    }

    Widget line(int afterStep) {
      final active = _stepColor(status, afterStep + 1) != kBorder;
      return Expanded(
        child: Container(
          height: 2,
          margin: const EdgeInsets.only(bottom: 16),
          color: active ? const Color(0xFF16A34A) : kBorder,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [dot(0), line(0), dot(1), line(1), dot(2)],
      ),
    );
  }

  Widget _detailCard(List<Widget> rows) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
  );

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: kTextMuted)),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: kTextPrimary,
          ),
        ),
      ],
    ),
  );

  Widget _factCard(String fact) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFEFF6FF),
      border: Border.all(color: const Color(0xFFBFDBFE)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lightbulb_outline_rounded, color: Color(0xFF2563EB)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Did you know?',
                style: TextStyle(
                  color: Color(0xFF1D4ED8),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                fact,
                style: const TextStyle(
                  color: Color(0xFF1D4ED8),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _verifiedState() {
    final docType = _latestSubmission?['document_type'] as String?;
    final reviewedAt = _latestSubmission?['reviewed_at'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statusStepper('verified'),
        _animatedHero(
          color: const Color(0xFF16A34A),
          icon: Icons.verified_rounded,
          title: "You're Verified!",
          subtitle: 'Your identity has been confirmed. You now have full '
              'access to book appointments and more.',
        ),
        if (docType != null || reviewedAt != null) ...[
          const SizedBox(height: 20),
          _detailCard([
            if (docType != null) _detailRow('Document type', _documentTypeLabel(docType)),
            if (reviewedAt != null) _detailRow('Verified on', _formatDate(reviewedAt)),
          ]),
        ],
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Continue',
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _pendingState() {
    final docType = _latestSubmission?['document_type'] as String?;
    final createdAt = _latestSubmission?['created_at'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statusStepper('pending'),
        _animatedHero(
          color: const Color(0xFFD97706),
          icon: Icons.hourglass_top_rounded,
          title: 'Under Review',
          subtitle: "Your ID is being reviewed by our team. We'll notify "
              "you once it's confirmed.",
        ),
        if (docType != null || createdAt != null) ...[
          const SizedBox(height: 20),
          _detailCard([
            if (docType != null) _detailRow('Document type', _documentTypeLabel(docType)),
            if (createdAt != null) _detailRow('Submitted on', _formatDate(createdAt)),
          ]),
        ],
        const SizedBox(height: 18),
        _factCard(_fact),
      ],
    );
  }

  Widget _rejectedState() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _statusStepper('rejected'),
      _animatedHero(
        color: kCrimson,
        icon: Icons.cancel_rounded,
        title: 'Verification Rejected',
        subtitle: 'Your last submission did not meet our requirements.',
      ),
      const SizedBox(height: 20),
      _rejectionBanner(),
      const SizedBox(height: 12),
      const Text(
        'Please review the reason above, then upload a new photo of a '
        'valid ID to try again.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: kTextMuted, height: 1.5),
      ),
      const SizedBox(height: 20),
      _uploadFormBody(),
    ],
  );

  Widget _rejectionBanner() {
    final reason = _latestSubmission?['rejection_reason'] as String?;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        border: Border.all(color: const Color(0xFFFECACA)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: kCrimson),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your last submission was rejected',
                  style: TextStyle(
                    color: kCrimson,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (reason == null || reason.isEmpty)
                      ? 'Please review your ID photo and try again.'
                      : reason,
                  style: const TextStyle(
                    color: kCrimson,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _uploadFormBody() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _infoBanner(),
      const SizedBox(height: 18),
      _documentTypeCard(),
      const SizedBox(height: 18),
      _uploadArea(),
      const SizedBox(height: 18),
      _requirementsCard(),
      const SizedBox(height: 24),
      PrimaryButton(
        label: _submitting ? 'Submitting...' : 'Submit for Verification',
        loading: _submitting,
        onTap: _canSubmit ? _submit : null,
      ),
      const SizedBox(height: 12),
      const Text(
        'Your ID is used only to confirm your identity as a '
        'blood donor and is never shared publicly.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: kTextMuted),
      ),
    ],
  );

  Widget _infoBanner() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFEFF6FF),
      border: Border.all(color: const Color(0xFFBFDBFE)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: Color(0xFF2563EB)),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            "To keep eDonate safe for both donors and recipients, please "
            "upload a clear photo of a valid government-issued ID (e.g. "
            "Driver's License, Passport, or National ID).",
            style: TextStyle(
              color: Color(0xFF1D4ED8),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _documentTypeCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.badge_outlined, color: kCrimson, size: 20),
            SizedBox(width: 8),
            Text(
              'ID Type',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: kTextPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppDropdown<String>(
          value: _documentType,
          hint: "Select the type of ID you're uploading",
          items: _documentTypes
              .map(
                (d) => DropdownMenuItem<String>(
                  value: d['value'],
                  child: Text(d['label']!),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _documentType = value),
        ),
      ],
    ),
  );

  Widget _uploadArea() {
    final hasImage = _idImage != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_outlined, color: kCrimson, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Valid ID Photo',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: kTextPrimary,
                ),
              ),
              const Spacer(),
              if (hasImage)
                TextButton.icon(
                  onPressed: _removeImage,
                  icon: const Icon(Icons.close_rounded, size: 16, color: kCrimson),
                  label: const Text(
                    'Remove',
                    style: TextStyle(
                      color: kCrimson,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickImage,
            borderRadius: BorderRadius.circular(14),
            child: hasImage ? _imagePreview() : _uploadPlaceholder(),
          ),
        ],
      ),
    );
  }

  Widget _uploadPlaceholder() => Container(
    width: double.infinity,
    height: 180,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: kInputFill,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kBorder, width: 1.5),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFFFF1F1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.add_photo_alternate_rounded,
            color: kCrimson,
            size: 26,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Tap to upload a photo of your ID',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: kTextPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'From your gallery · JPG or PNG',
          style: TextStyle(fontSize: 11, color: kTextMuted),
        ),
      ],
    ),
  );

  Widget _imagePreview() => Stack(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: double.infinity,
          height: 200,
          child: Image.file(File(_idImage!.path), fit: BoxFit.cover),
        ),
      ),
      Positioned(
        right: 8,
        bottom: 8,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_rounded, size: 13, color: Colors.white),
              SizedBox(width: 4),
              Text(
                'Change photo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _requirementsCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Before you upload',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: kTextPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _requirementRow('Your ID is valid and not expired'),
        _requirementRow('All four corners are visible'),
        _requirementRow('Text and photo are clear and readable'),
        _requirementRow('No glare, blur, or obstructions'),
      ],
    ),
  );

  Widget _requirementRow(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF16A34A)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: kTextPrimary, height: 1.4),
          ),
        ),
      ],
    ),
  );
}
