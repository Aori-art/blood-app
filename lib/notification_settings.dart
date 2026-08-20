import 'dart:convert';

import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'profile_page_widgets.dart';
import 'shared_design.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  String? donorId;
  bool enabled = false,
      deviceRegistered = false,
      loading = true,
      updating = false,
      online = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void snack(String message) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    donorId = prefs.getString('donorId');
    if (donorId == null || donorId!.isEmpty) {
      if (mounted) setState(() => loading = false);
      return;
    }
    enabled = prefs.getBool('push_enabled_' + donorId!) ?? false;
    if (mounted) setState(() => loading = false);
    try {
      final r = await http
          .get(
            Uri.parse(
              AppConfig.baseUrl +
                  '/get_notification_settings.php?donor_id=' +
                  donorId!,
            ),
          )
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(r.body);
      if (r.statusCode == 200 && body is Map && body['status'] == 'success') {
        enabled =
            body['push_enabled'] == true ||
            body['push_enabled'] == 1 ||
            body['push_enabled'] == '1';
        deviceRegistered =
            body['device_registered'] == true ||
            body['device_registered'] == 1 ||
            body['device_registered'] == '1';
        await prefs.setBool('push_enabled_' + donorId!, enabled);
        if (mounted) setState(() {});
      } else {
        online = false;
      }
    } catch (_) {
      online = false;
    }
    if (mounted) setState(() {});
  }

  Future<bool> _updateBackend(bool value) async {
    final r = await http
        .post(
          Uri.parse(AppConfig.baseUrl + '/update_notification_settings.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'donor_id': int.tryParse(donorId!) ?? donorId!,
            'push_enabled': value,
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return false;
    try {
      final body = jsonDecode(r.body);
      return body is Map && body['status'] == 'success';
    } catch (_) {
      return false;
    }
  }

  Future<bool> _saveToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return false;
    final r = await http
        .post(
          Uri.parse(AppConfig.baseUrl + '/save_fcm_token.php'),
          body: {'donor_id': donorId!, 'fcm_token': token},
        )
        .timeout(const Duration(seconds: 10));
    return r.statusCode == 200;
  }

  Future<void> _toggle(bool value) async {
    if (updating) return;
    if (!online) {
      snack('Internet connection is required to change notification settings.');
      return;
    }
    setState(() => updating = true);
    try {
      if (value) {
        final permission = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        if (permission.authorizationStatus == AuthorizationStatus.denied ||
            permission.authorizationStatus ==
                AuthorizationStatus.notDetermined) {
          snack(
            'Notification permission is disabled. Enable it in your phone settings.',
          );
          return;
        }
      }
      if (!await _updateBackend(value)) {
        snack('Something went wrong. Please try again.');
        return;
      }
      if (value && !await _saveToken()) {
        snack(
          'Push notifications were enabled, but this device could not be registered yet. Please try again.',
        );
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('push_enabled_' + donorId!, value);
      if (mounted)
        setState(() {
          enabled = value;
          deviceRegistered = value;
        });
      snack(
        value
            ? 'Push notifications enabled.'
            : 'Push notifications disabled. Alerts remain available in the app.',
      );
    } catch (_) {
      snack('Internet connection is required to change notification settings.');
    }
    if (mounted) setState(() => updating = false);
  }

  @override
  Widget build(BuildContext context) => ProfilePage(
    title: 'Notification Settings',
    subtitle: 'Control how eDonate notifies you',
    child: loading
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: kCrimson),
            ),
          )
        : Column(
            children: [
              if (!online) ...[
                profileInfoCard(
                  'Showing your saved notification preference. Changing this setting requires internet.',
                  icon: Icons.cloud_off_outlined,
                ),
                const SizedBox(height: 16),
              ],
              ProfileCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Account Push Notifications',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: kTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SettingsRow(
                      icon: Icons.notifications_active_outlined,
                      title: 'Push Notifications',
                      subtitle:
                          'Receive appointment, eligibility and donation updates.',
                      trailing: Switch(
                        value: enabled,
                        activeColor: kCrimson,
                        onChanged: updating ? null : _toggle,
                      ),
                    ),
                    if (updating)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: LinearProgressIndicator(color: kCrimson),
                      ),
                    const Divider(),
                    Text(
                      deviceRegistered
                          ? 'This device is registered for push notifications.'
                          : 'This device is not currently registered for push notifications.',
                      style: const TextStyle(fontSize: 12, color: kTextMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ProfileCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Phone Notification Permission',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: kTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Android and iOS control notification permission at the device level. If permission is denied, enable it in your phone settings.',
                      style: TextStyle(
                        fontSize: 13,
                        color: kTextMuted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: AppSettings.openAppSettings,
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Open Device Notification Settings'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kCrimson,
                          side: const BorderSide(color: kCrimson),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
  );
}
