import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'streak/streak_screen.dart';
import 'package:http/http.dart' as http;
import 'anim.dart';
import 'config.dart';
import 'home.dart' show FloatingNavMetrics;
import 'notification_service.dart';
import 'shared_design.dart';
import 'unread_notifications.dart';
import 'app_palette.dart';

class NotificationModel {
  final int id;
  final String title;
  final String message;
  final String notificationType;
  final bool isRead;
  final String date;
  final String createdAt;

  NotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.notificationType,
    required this.isRead,
    required this.date,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['notification_id'] ?? 0,
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      notificationType: json['notification_type'] ?? '',
      isRead: json['is_read'] ?? false,
      date: json['date'] ?? '',
      createdAt: json['created_at'] ?? '',
    );
  }

  NotificationModel copyWith({bool? isRead}) {
    return NotificationModel(
      id: id,
      title: title,
      message: message,
      notificationType: notificationType,
      isRead: isRead ?? this.isRead,
      date: date,
      createdAt: createdAt,
    );
  }
}

class AlertsScreen extends StatefulWidget {
  final int donorId;

  const AlertsScreen({super.key, required this.donorId});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<NotificationModel> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = true;
  String? _errorMessage;

  // Tracks which notification card is expanded
  int? _expandedId;

  StreamSubscription<void>? _newNotificationSub;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
    // FCM only tells us something changed — MySQL (via get_notifications.php)
    // remains the authoritative source for the inbox list.
    _newNotificationSub = NotificationService.instance.onNotificationReceived
        .listen((_) {
          if (mounted) _fetchNotifications();
        });
  }

  @override
  void dispose() {
    _newNotificationSub?.cancel();
    super.dispose();
  }

  // The badge on the Alerts icon always shows what this list says.
  void _syncBadge() => UnreadNotifications.instance.set(_unreadCount);

  Future<void> _fetchNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http
          .get(
            Uri.parse(
              '${AppConfig.baseUrl}/get_notifications.php?donor_id=${widget.donorId}',
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            _notifications = (data['notifications'] as List)
                .map((json) => NotificationModel.fromJson(json))
                .toList();
            _unreadCount = data['unread_count'] ?? 0;
            _isLoading = false;
          });
          _syncBadge();
        } else {
          setState(() {
            _errorMessage = data['message'] ?? 'Failed to load notifications';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Server error: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage =
            'Connection error. Please check your connection and try again.';
        _isLoading = false;
      });
      debugPrint('Error fetching notifications: $e');
    }
  }

  Future<void> _markAsRead(int notificationId) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/mark_notification_read.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'notification_id': notificationId,
          'donor_id': widget.donorId,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            final index = _notifications.indexWhere(
              (n) => n.id == notificationId,
            );
            if (index != -1 && !_notifications[index].isRead) {
              _notifications[index] = _notifications[index].copyWith(
                isRead: true,
              );
              if (_unreadCount > 0) _unreadCount--;
            }
          });
          _syncBadge();
        }
      }
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/mark_notification_read.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'mark_all': true, 'donor_id': widget.donorId}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            _notifications = _notifications
                .map((n) => n.copyWith(isRead: true))
                .toList();
            _unreadCount = 0;
          });
          _syncBadge();
          if (mounted) {
            _showSnack('All notifications marked as read', isSuccess: true);
          }
        }
      }
    } catch (e) {
      debugPrint('Error marking all as read: $e');
      if (mounted) _showSnack('Failed to mark all as read. Please try again.');
    }
  }

  Future<void> _deleteNotification(int notificationId) async {
    // Optimistically remove from UI
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index == -1) return;

    final removed = _notifications[index];
    setState(() {
      _notifications.removeAt(index);
      if (!removed.isRead && _unreadCount > 0) _unreadCount--;
      if (_expandedId == notificationId) _expandedId = null;
    });
    _syncBadge();

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/delete_notification.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'notification_id': notificationId,
          'donor_id': widget.donorId,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] != true) {
          // Revert if server failed
          setState(() {
            _notifications.insert(index, removed);
            if (!removed.isRead) _unreadCount++;
          });
          _syncBadge();
          if (mounted) _showSnack('Failed to delete. Please try again.');
        } else {
          if (mounted) _showSnack('Notification deleted', isSuccess: true);
        }
      }
    } catch (e) {
      debugPrint('Error deleting notification: $e');
      setState(() {
        _notifications.insert(index, removed);
        if (!removed.isRead) _unreadCount++;
      });
      _syncBadge();
      if (mounted) _showSnack('Failed to delete. Please try again.');
    }
  }

  Future<void> _confirmAndDeleteAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete All Notifications',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'Are you sure you want to delete all notifications? This cannot be undone.',
          style: TextStyle(fontSize: 13, color: context.palette.muted, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.palette.muted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: context.palette.border,
              disabledForegroundColor: context.palette.muted,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _deleteAllNotifications();
    }
  }

  Future<void> _deleteAllNotifications() async {
    final removed = List<NotificationModel>.from(_notifications);
    if (removed.isEmpty) return;

    // Optimistically clear the UI
    setState(() {
      _notifications = [];
      _unreadCount = 0;
      _expandedId = null;
    });
    _syncBadge();

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/delete_all_notifications.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'donor_id': widget.donorId}),
      );

      final succeeded =
          response.statusCode == 200 &&
          json.decode(response.body)['success'] == true;

      if (!mounted) return;
      if (succeeded) {
        _showSnack('All notifications deleted', isSuccess: true);
      } else {
        _showSnack('Failed to delete all notifications.');
        _fetchNotifications();
      }
    } catch (e) {
      debugPrint('Error deleting all notifications: $e');
      if (mounted) {
        _showSnack('Failed to delete all. Please try again.');
        _fetchNotifications();
      }
    }
  }

  void _showSnack(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(message, style: const TextStyle(fontSize: 13)),
          ],
        ),
        backgroundColor: isSuccess
            ? AppColors.success
            : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'appointment':
      case 'appointment_approved':
      case 'appointment_rescheduled':
      case 'appointment_cancelled':
      case 'appointment_completed':
        return context.palette.info;
      case 'reminder':
        return context.palette.warning;
      case 'thank_you':
        return context.palette.success;
      case 'eligibility':
      case 'eligibility_reviewed':
        return context.palette.purple;
      case 'screening_passed':
        return context.palette.success;
      case 'screening_failed':
        return context.palette.primaryText;
      case 'screening_deferred':
        return context.palette.warning;
      default:
        return context.palette.muted;
    }
  }

  Color _getTypeBg(String type) {
    switch (type) {
      case 'appointment':
      case 'appointment_approved':
      case 'appointment_rescheduled':
      case 'appointment_cancelled':
      case 'appointment_completed':
        return context.palette.infoBg;
      case 'reminder':
        return context.palette.warningBg;
      case 'thank_you':
        return context.palette.successBg;
      case 'eligibility':
      case 'eligibility_reviewed':
        return context.palette.purpleBg;
      case 'screening_passed':
        return context.palette.successBg;
      case 'screening_failed':
        return context.palette.accentBg;
      case 'screening_deferred':
        return context.palette.warningBg;
      default:
        return context.palette.surfaceAlt;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'appointment':
      case 'appointment_rescheduled':
        return Icons.calendar_month_rounded;
      case 'appointment_approved':
        return Icons.event_available_rounded;
      case 'appointment_cancelled':
        return Icons.event_busy_rounded;
      case 'appointment_completed':
        return Icons.check_circle_rounded;
      case 'reminder':
        return Icons.alarm_rounded;
      case 'thank_you':
        return Icons.favorite_rounded;
      case 'eligibility':
      case 'eligibility_reviewed':
        return Icons.water_drop_rounded;
      case 'screening_passed':
      case 'screening_failed':
        return Icons.fact_check_rounded;
      case 'screening_deferred':
        return Icons.schedule_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'appointment':
      case 'appointment_approved':
      case 'appointment_rescheduled':
      case 'appointment_cancelled':
      case 'appointment_completed':
        return 'Appointment';
      case 'reminder':
        return 'Reminder';
      case 'thank_you':
        return 'Thank You';
      case 'eligibility':
      case 'eligibility_reviewed':
        return 'Eligibility';
      case 'screening_passed':
        return 'Test Passed';
      case 'screening_failed':
        return 'Test Failed';
      case 'screening_deferred':
        return 'Test Deferred';
      default:
        return 'General';
    }
  }

  @override
  Widget build(BuildContext context) =>
      StreakScreen(id: 'alerts', child: _buildScreen(context));

  Widget _buildScreen(BuildContext context) {
    final size = MediaQuery.of(context).size;

    final showDeleteAll =
        !_isLoading && _errorMessage == null && _notifications.isNotEmpty;

    return Scaffold(
      backgroundColor: context.palette.background,
      body: Column(
        children: [
          // ── HEADER ────────────────────────────────────────────
          _buildHeader(size),

          // ── BODY ──────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: context.palette.primaryText),
                  )
                : _errorMessage != null
                ? _buildError()
                : _notifications.isEmpty
                ? _buildEmpty()
                : _buildList(size),
          ),
        ],
      ),
      floatingActionButton: showDeleteAll ? _buildDeleteAllButton() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  // ── FLOATING DELETE-ALL BUTTON ───────────────────────────────
  Widget _buildDeleteAllButton() {
    return Padding(
      padding: const EdgeInsets.only(
        bottom:
            8 + FloatingNavMetrics.barHeight + FloatingNavMetrics.bottomMargin,
        right: 4,
      ),
      child: GestureDetector(
        onTap: _confirmAndDeleteAll,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.delete_sweep_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Size size) => EdonateHeader(
    title: 'Notifications',
    subtitle: _unreadCount > 0
        ? '$_unreadCount unread message${_unreadCount > 1 ? 's' : ''}'
        : 'All caught up!',
    actions: (_unreadCount > 0 && !_isLoading && _errorMessage == null)
        ? [
            GestureDetector(
              onTap: _markAllAsRead,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white38),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.done_all_rounded, color: Colors.white, size: 13),
                    SizedBox(width: 4),
                    Text(
                      'Mark all read',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ]
        : const [],
  );

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.palette.accentBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 40,
                color: context.palette.primaryText,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Connection Error',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
                color: context.palette.foreground,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.palette.muted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchNotifications,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: context.palette.border,
                disabledForegroundColor: context.palette.muted,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.palette.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Icon(
              Icons.notifications_off_rounded,
              size: 48,
              color: context.palette.faint,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No notifications yet',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: context.palette.foreground,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "You're all caught up. We'll\nnotify you when something new arrives.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.palette.muted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(Size size) {
    return RefreshIndicator(
      onRefresh: _fetchNotifications,
      color: context.palette.primaryText,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          size.width * 0.04,
          16,
          size.width * 0.04,
          FloatingNavMetrics.bottomPadding(context),
        ),
        itemCount: _notifications.length,
        itemBuilder: (context, index) {
          return FadeSlideIn(
            index: index,
            child: _NotificationCard(
              notification: _notifications[index],
              isExpanded: _expandedId == _notifications[index].id,
              typeColor: _getTypeColor(_notifications[index].notificationType),
              typeBg: _getTypeBg(_notifications[index].notificationType),
              typeIcon: _getTypeIcon(_notifications[index].notificationType),
              typeLabel: _getTypeLabel(_notifications[index].notificationType),
              onTap: () {
                setState(() {
                  if (_expandedId == _notifications[index].id) {
                    _expandedId = null;
                  } else {
                    _expandedId = _notifications[index].id;
                    if (!_notifications[index].isRead) {
                      _markAsRead(_notifications[index].id);
                    }
                  }
                });
              },
              onDelete: () => _deleteNotification(_notifications[index].id),
            ),
          );
        },
      ),
    );
  }
}

// ── NOTIFICATION CARD ─────────────────────────────────────────────────────────

class _NotificationCard extends StatelessWidget {
  final NotificationModel notification;
  final bool isExpanded;
  final Color typeColor;
  final Color typeBg;
  final IconData typeIcon;
  final String typeLabel;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NotificationCard({
    required this.notification,
    required this.isExpanded,
    required this.typeColor,
    required this.typeBg,
    required this.typeIcon,
    required this.typeLabel,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: Key('notif_${notification.id}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async {
          return await _confirmDelete(context);
        },
        onDismissed: (_) => onDelete(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_rounded, color: Colors.white, size: 24),
              SizedBox(height: 4),
              Text(
                'Delete',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: !notification.isRead
                    ? AppColors.primary.withOpacity(0.4)
                    : context.palette.border,
                width: !notification.isRead ? 1.5 : 1,
              ),
              // An open card lifts with a soft glow in its type color.
              boxShadow: isExpanded
                  ? [
                      BoxShadow(
                        color: typeColor.withOpacity(0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : context.palette.shadow,
            ),
            child: Column(
              children: [
                // ── COLLAPSED ROW ───────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Icon
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: typeBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(typeIcon, color: typeColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      // Title + date
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // Type badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: typeBg,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    typeLabel,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: typeColor,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                                if (!notification.isRead) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              notification.title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: notification.isRead
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                                color: context.palette.foreground,
                              ),
                              maxLines: isExpanded ? null : 1,
                              overflow: isExpanded
                                  ? null
                                  : TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              notification.date,
                              style: TextStyle(
                                fontSize: 11,
                                color: context.palette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Expand chevron
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: isExpanded
                              ? typeColor
                              : context.palette.faint,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── EXPANDED DETAILS ────────────────────────────
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 300),
                  crossFadeState: isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(
                        height: 1,
                        color: context.palette.surfaceAlt,
                        indent: 14,
                        endIndent: 14,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Message body
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: typeBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                notification.message,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: typeColor.withOpacity(0.85),
                                  height: 1.55,
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Footer row: timestamp + delete button
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 13,
                                  color: context.palette.muted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  notification.createdAt.isNotEmpty
                                      ? notification.createdAt
                                      : notification.date,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.palette.muted,
                                  ),
                                ),
                                const Spacer(),
                                // Delete button
                                GestureDetector(
                                  onTap: () async {
                                    final confirm = await _confirmDelete(
                                      context,
                                    );
                                    if (confirm == true) onDelete();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: context.palette.accentBg,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.delete_outline_rounded,
                                          size: 14,
                                          color: context.palette.primaryText,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Delete',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: context.palette.primaryText,
                                          ),
                                        ),
                                      ],
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Notification',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'Are you sure you want to delete this notification? This cannot be undone.',
          style: TextStyle(fontSize: 13, color: context.palette.muted, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.palette.muted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: context.palette.border,
              disabledForegroundColor: context.palette.muted,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
