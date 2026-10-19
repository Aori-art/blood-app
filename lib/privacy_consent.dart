import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'privacy_statement.dart';
import 'shared_design.dart';
import 'streak/streak_screen.dart';
import 'app_palette.dart';

// ─── Consent receipt ─────────────────────────────────────────────────────────
// An anonymous record that this install accepted a policy version. It never
// blocks navigation: on any failure the receipt is flagged as pending and
// retried on the next launch.

bool _receiptInFlight = false;

String _randomInstallId() {
  final rng = Random.secure();
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Future<String> _getOrCreateInstallId(SharedPreferences prefs) async {
  final existing = prefs.getString(kPrivacyInstallIdKey);
  if (existing != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(existing)) {
    return existing;
  }
  final created = _randomInstallId();
  await prefs.setString(kPrivacyInstallIdKey, created);
  return created;
}

Future<bool> _postReceipt(String installId, String policyVersion) async {
  final response = await http
      .post(
        Uri.parse('${AppConfig.baseUrl}/record_privacy_receipt.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'subject_hash': installId,
          'policy_version': policyVersion,
          'purpose': 'data-privacy-consent',
          'choices': {'accepted': true},
        }),
      )
      .timeout(const Duration(seconds: 8));
  dynamic body;
  try {
    body = jsonDecode(response.body);
  } catch (_) {
    body = null;
  }
  return body is Map && body['success'] == true;
}

Future<void> sendPrivacyReceipt() async {
  if (_receiptInFlight) return;
  _receiptInFlight = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    var ok = false;
    try {
      final installId = await _getOrCreateInstallId(prefs);
      final version =
          prefs.getString(kPrivacyConsentVersionKey) ?? kPrivacyPolicyVersion;
      ok = await _postReceipt(installId, version);
    } catch (_) {
      ok = false;
    }
    await prefs.setBool(kPrivacyReceiptPendingKey, !ok);
  } catch (_) {
    // Preferences unavailable — nothing more we can record.
  } finally {
    _receiptInFlight = false;
  }
}

Future<void> retryPendingPrivacyReceipt() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(kPrivacyReceiptPendingKey) != true) return;
    await sendPrivacyReceipt();
  } catch (_) {}
}

// ─── Consent screen ──────────────────────────────────────────────────────────

class PrivacyConsentScreen extends StatefulWidget {
  final WidgetBuilder nextBuilder;

  const PrivacyConsentScreen({super.key, required this.nextBuilder});

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  bool _agreed = false;
  bool _saving = false;

  Future<void> _onAccept() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Confirm your consent',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'By continuing, you agree to the Data Privacy Statement. You can '
          'review it anytime in Profile > Privacy & Security.',
          style: TextStyle(
            fontSize: 13,
            color: context.palette.muted,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Go Back',
              style: TextStyle(color: context.palette.muted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kCrimson,
              disabledBackgroundColor: context.palette.border,
              disabledForegroundColor: context.palette.muted,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPrivacyConsentVersionKey, kPrivacyPolicyVersion);
      await prefs.setString(
        kPrivacyConsentAtKey,
        DateTime.now().toUtc().toIso8601String(),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Something went wrong. Please try again.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    unawaited(sendPrivacyReceipt());
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (ctx, animation, secondaryAnimation) =>
            widget.nextBuilder(ctx),
        transitionsBuilder: (_, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  Future<void> _onDecline() async {
    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Consent required',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'You need to accept the Data Privacy Statement to use eDonate.',
          style: TextStyle(
            fontSize: 13,
            color: context.palette.muted,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Review Again',
              style: TextStyle(color: context.palette.muted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kCrimson,
              disabledBackgroundColor: context.palette.border,
              disabledForegroundColor: context.palette.muted,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Exit App'),
          ),
        ],
      ),
    );
    if (exit == true) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) => StreakScreen(
    id: 'consent',
    hideBubble: true,
    child: _buildScreen(context),
  );

  Widget _buildScreen(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      backgroundColor: context.palette.background,
      body: Column(
        children: [
          // Fixed chrome: cap its text scaling so a large system font can't
          // push the scrollable statement off small screens.
          MediaQuery.withClampedTextScaling(
            minScaleFactor: 1.0,
            maxScaleFactor: 1.2,
            child: EdonateHeader(
              title: 'Data Privacy & Security',
              subtitle: 'Please read before you continue',
              leading: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .16),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white30, width: 1.2),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.palette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.palette.border),
                  boxShadow: context.palette.shadow,
                ),
                child: const PrivacyStatementView(),
              ),
            ),
          ),
          _bottomPanel(),
        ],
      ),
    ),
  );

  Widget _bottomPanel() => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: context.palette.surface,
      border: Border(top: BorderSide(color: context.palette.border)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .06),
          blurRadius: 10,
          offset: const Offset(0, -3),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      // Never taller than half the screen; scrolls on small screens or with
      // large text so the buttons stay reachable without overflowing.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.5,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _saving
                    ? null
                    : () => setState(() => _agreed = !_agreed),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _agreed,
                      activeColor: context.palette.primaryText,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _agreed = v ?? false),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: 12, right: 4),
                        child: Text(
                          'I have read and understood the Data Privacy '
                          'Statement, and I agree to the collection and '
                          'processing of my personal information as described.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: context.palette.foreground,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              PrimaryButton(
                label: 'Accept and Continue',
                loading: _saving,
                onTap: _agreed && !_saving ? _onAccept : null,
              ),
              TextButton(
                onPressed: _saving ? null : _onDecline,
                child: Text(
                  'Decline',
                  style: TextStyle(
                    color: context.palette.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
