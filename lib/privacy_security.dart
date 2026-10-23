import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'change_password.dart';
import 'config.dart';
import 'data_privacy.dart';
import 'login.dart';
import 'pin_screen.dart';
import 'privacy_statement.dart';
import 'profile_page_widgets.dart';
import 'shared_design.dart';
import 'streak/streak_controller.dart';
import 'unread_notifications.dart';
import 'my_avatar_controller.dart';
import 'streak/streak_screen.dart';
import 'app_palette.dart';

class PrivacySecurityScreen extends StatefulWidget {
  final bool showChangePin;

  const PrivacySecurityScreen({super.key, this.showChangePin = false});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  bool _deleteFlowActive = false;

  // PIN: opens the PIN screen in "change" mode (current → new → confirm).
  Future<void> _changePin() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const PinScreen(purpose: PinPurpose.change),
      ),
    );
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Your PIN was updated.')),
            ],
          ),
        ),
      );
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // Delete account: confirm password (verify only) → final confirmation →
  // delete. The password lives only in the local `password` variable of this
  // method (the dialogs get it through callbacks), and is never stored,
  // logged or kept in state.
  Future<void> _deleteAccount() async {
    if (_deleteFlowActive) return;
    _deleteFlowActive = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final donorId = prefs.getString('donorId');
      if (donorId == null || donorId.isEmpty) {
        _snack('Unable to find your account. Please sign in again.');
        return;
      }

      String? initialError;
      while (true) {
        if (!mounted) return;
        final password = await showDialog<String>(
          context: context,
          builder: (_) => _PasswordDialog(
            initialError: initialError,
            onVerify: (typed) => _callDeleteApi(donorId, typed, 'verify'),
          ),
        );
        if (password == null || !mounted) return;

        final result = await showDialog<_DeleteApiResult>(
          context: context,
          builder: (_) => _FinalConfirmDialog(
            onDelete: () => _callDeleteApi(donorId, password, 'delete'),
          ),
        );
        if (result == null || !mounted) return;

        if (result.success) {
          await _finishDeletion();
          return;
        }
        // Only INVALID_PASSWORD closes the final dialog with a failure —
        // go back to the password step.
        initialError = _deleteErrorText(result);
      }
    } finally {
      _deleteFlowActive = false;
    }
  }

  Future<void> _finishDeletion() async {
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await clearSessionKeepConsent(prefs);
    } catch (_) {}
    StreakController.instance.onLoggedOut(forgetSeen: true);
    UnreadNotifications.instance
      ..stop()
      ..clear();
    MyAvatarController.instance.reset();
    AppSession.homeInStack = false;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Your account has been deleted.'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) =>
      StreakScreen(id: 'privacy_security', child: _buildScreen(context));

  Widget _buildScreen(BuildContext context) => ProfilePage(
    title: 'Privacy & Security',
    subtitle: 'Manage your account security and privacy',
    child: ProfileCard(
      child: Column(
        children: [
          SettingsRow(
            icon: Icons.lock_outline,
            title: 'Change Password',
            subtitle: 'Update your account password.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
            ),
          ),
          const Divider(),
          _DeleteAccountRow(onTap: _deleteAccount),
          // PIN: only verified donors have (or can create) a PIN.
          if (widget.showChangePin) ...[
            const Divider(),
            SettingsRow(
              icon: Icons.password_rounded,
              title: 'Change PIN',
              subtitle: 'Update the 4-digit PIN you use to open eDonate.',
              onTap: _changePin,
            ),
          ],
          const Divider(),
          SettingsRow(
            icon: Icons.privacy_tip_outlined,
            title: 'Data Privacy',
            subtitle: 'Learn how eDonate handles your information.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DataPrivacyScreen()),
            ),
          ),
        ],
      ),
    ),
  );
}

// ─── Backend ─────────────────────────────────────────────────────────────────

class _DeleteApiResult {
  final bool success;
  final String code;
  final String? message;
  final int? attemptsRemaining;

  const _DeleteApiResult({
    required this.success,
    required this.code,
    this.message,
    this.attemptsRemaining,
  });
}

// delete_account.php answers with a JSON body on every status code (401 /
// 429 / 500 included), so the body is parsed regardless of statusCode.
Future<_DeleteApiResult> _callDeleteApi(
  String donorId,
  String password,
  String action,
) async {
  try {
    final response = await http
        .post(
          Uri.parse('${AppConfig.baseUrl}/delete_account.php'),
          body: {'donor_id': donorId, 'password': password, 'action': action},
        )
        .timeout(const Duration(seconds: 15));
    dynamic body;
    try {
      body = jsonDecode(response.body);
    } catch (_) {
      body = null;
    }
    if (body is! Map) {
      return const _DeleteApiResult(success: false, code: 'SERVER_ERROR');
    }
    final code = body['code']?.toString() ?? '';
    final expected = action == 'verify'
        ? 'PASSWORD_VERIFIED'
        : 'ACCOUNT_DELETED';
    return _DeleteApiResult(
      success: body['success'] == true && code == expected,
      code: code,
      message: body['message']?.toString(),
      attemptsRemaining: (body['attempts_remaining'] as num?)?.toInt(),
    );
  } catch (_) {
    return const _DeleteApiResult(success: false, code: 'NETWORK_ERROR');
  }
}

String _deleteErrorText(_DeleteApiResult r) {
  switch (r.code) {
    case 'NETWORK_ERROR':
      return 'Unable to reach the server. Please check your connection.';
    case 'INVALID_PASSWORD':
      final n = r.attemptsRemaining;
      if (n == null) return 'Incorrect password.';
      return 'Incorrect password. $n ${n == 1 ? 'attempt' : 'attempts'} left.';
    default:
      final message = r.message;
      return (message != null && message.isNotEmpty)
          ? message
          : 'Something went wrong. Please try again.';
  }
}

// ─── UI ──────────────────────────────────────────────────────────────────────

// Same layout as SettingsRow, with the icon on a pale red circle. The circle
// is wider than the 21px icon slot, so it overflows evenly on both sides to
// keep the title aligned with the rows above and below.
class _DeleteAccountRow extends StatelessWidget {
  final VoidCallback onTap;
  const _DeleteAccountRow({required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        children: [
          SizedBox(
            width: 21,
            height: 32,
            child: OverflowBox(
              maxWidth: 32,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.palette.accentBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delete_forever_rounded,
                  color: context.palette.primaryText,
                  size: 19,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Delete Account',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.palette.primaryText,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Permanently remove your account and personal data',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.palette.muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: context.palette.muted),
        ],
      ),
    ),
  );
}

TextStyle _dialogTitleStyle(BuildContext context) => TextStyle(
  fontWeight: FontWeight.bold,
  fontSize: 16,
  color: context.palette.foreground,
);

TextStyle _dialogBodyStyle(BuildContext context) => TextStyle(
  fontSize: 13,
  color: context.palette.muted,
  height: 1.5,
);

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
  );
}

ButtonStyle _redButtonStyle() => ElevatedButton.styleFrom(
  backgroundColor: kCrimson,
  foregroundColor: Colors.white,
  disabledBackgroundColor: kCrimson.withValues(alpha: .7),
  disabledForegroundColor: Colors.white,
  elevation: 0,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
);

// Step 1 + 2: asks for the password and checks it with action=verify. Pops
// with the typed password on success, or null when cancelled.
class _PasswordDialog extends StatefulWidget {
  final String? initialError;
  final Future<_DeleteApiResult> Function(String password) onVerify;

  const _PasswordDialog({required this.onVerify, this.initialError});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _visible = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_loading) return;
    final password = _controller.text;
    if (password.isEmpty) {
      setState(() => _error = 'Please enter your password.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.onVerify(password);
    if (!mounted) return;
    if (result.success) {
      Navigator.pop(context, password);
      return;
    }
    setState(() {
      _loading = false;
      _error = _deleteErrorText(result);
    });
  }

  OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_loading,
    child: AlertDialog(
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Confirm your password', style: _dialogTitleStyle(context)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter your password to continue.',
            style: _dialogBodyStyle(context),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            enabled: !_loading,
            autofocus: true,
            obscureText: !_visible,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _continue(),
            style: TextStyle(color: context.palette.foreground, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Password',
              hintStyle: TextStyle(
                color: context.palette.muted,
                fontSize: 14,
              ),
              filled: true,
              fillColor: context.palette.surfaceAlt,
              errorText: _error,
              errorMaxLines: 3,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              suffixIcon: IconButton(
                tooltip: _visible ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => _visible = !_visible),
                icon: Icon(
                  _visible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: context.palette.muted,
                ),
              ),
              border: _border(context.palette.border),
              enabledBorder: _border(context.palette.border),
              disabledBorder: _border(context.palette.border),
              focusedBorder: _border(context.palette.primaryText, 1.5),
              errorBorder: _border(context.palette.primaryText),
              focusedErrorBorder: _border(context.palette.primaryText, 1.5),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: context.palette.muted)),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _continue,
          style: _redButtonStyle(),
          child: _loading ? const _ButtonSpinner() : const Text('Continue'),
        ),
      ],
    ),
  );
}

// Step 3 + 4: the final confirmation, which also performs action=delete.
// Pops null when cancelled, the successful result once the account is
// deleted, or an INVALID_PASSWORD result so the flow can ask again. Any other
// failure stays inline so the user can retry or cancel.
class _FinalConfirmDialog extends StatefulWidget {
  final Future<_DeleteApiResult> Function() onDelete;

  const _FinalConfirmDialog({required this.onDelete});

  @override
  State<_FinalConfirmDialog> createState() => _FinalConfirmDialogState();
}

class _FinalConfirmDialogState extends State<_FinalConfirmDialog> {
  bool _deleting = false;
  String? _error;

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    final result = await widget.onDelete();
    if (!mounted) return;
    if (result.success || result.code == 'INVALID_PASSWORD') {
      Navigator.pop(context, result);
      return;
    }
    setState(() {
      _deleting = false;
      _error = _deleteErrorText(result);
    });
  }

  Widget _group(String label, List<String> items) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: context.palette.foreground,
        ),
      ),
      const SizedBox(height: 6),
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 6, right: 8),
                child: Icon(Icons.circle, size: 5, color: context.palette.muted),
              ),
              Expanded(child: Text(item, style: _dialogBodyStyle(context))),
            ],
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_deleting,
    child: AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.palette.accentBg,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.delete_forever_rounded,
          color: context.palette.primaryText,
          size: 30,
        ),
      ),
      title: Text(
        'Delete your account?',
        textAlign: TextAlign.center,
        style: _dialogTitleStyle(context),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _group('Permanently deleted', const [
              'Your profile, contact details and address',
              'Your ID photos and verification records',
              'Your eligibility screening answers',
              'Your appointments and notifications',
            ]),
            const SizedBox(height: 10),
            _group('Kept without your identity', const ['Donation records']),
            const SizedBox(height: 12),
            Text(
              'This cannot be undone.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: context.palette.primaryText,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: 12.5,
                  color: context.palette.primaryText,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: context.palette.muted)),
        ),
        ElevatedButton(
          onPressed: _deleting ? null : _delete,
          style: _redButtonStyle(),
          child: _deleting
              ? const _ButtonSpinner()
              : const Text('Delete My Account'),
        ),
      ],
    ),
  );
}
