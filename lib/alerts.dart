import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'anim.dart';
import 'config.dart';

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

  const AlertsScreen({
    super.key,
    required this.donorId,
  });

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

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/get_notifications.php?donor_id=${widget.donorId}'),
      ).timeout(const Duration(seconds: 10));

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
        _errorMessage = 'Connection error. Please check your connection and try again.';
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
            final index = _notifications.indexWhere((n) => n.id == notificationId);
            if (index != -1 && !_notifications[index].isRead) {
              _notifications[index] = _notifications[index].copyWith(isRead: true);
              if (_unreadCount > 0) _unreadCount--;
            }
          });
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
        body: json.encode({
          'mark_all': true,
          'donor_id': widget.donorId,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
            _unreadCount = 0;
          });
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
      if (mounted) _showSnack('Failed to delete. Please try again.');
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
        backgroundColor: isSuccess ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'appointment': return const Color(0xFF2563EB);
      case 'reminder':   return const Color(0xFFF59E0B);
      case 'thank_you':  return const Color(0xFF16A34A);
      case 'eligibility': return const Color(0xFF9333EA);
      default:           return const Color(0xFF6B7280);
    }
  }

  Color _getTypeBg(String type) {
    switch (type) {
      case 'appointment': return const Color(0xFFEFF6FF);
      case 'reminder':   return const Color(0xFFFFFBEB);
      case 'thank_you':  return const Color(0xFFF0FDF4);
      case 'eligibility': return const Color(0xFFFAF5FF);
      default:           return const Color(0xFFF3F4F6);
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'appointment': return Icons.calendar_month_rounded;
      case 'reminder':   return Icons.alarm_rounded;
      case 'thank_you':  return Icons.favorite_rounded;
      case 'eligibility': return Icons.water_drop_rounded;
      default:           return Icons.notifications_rounded;
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'appointment': return 'Appointment';
      case 'reminder':   return 'Reminder';
      case 'thank_you':  return 'Thank You';
      case 'eligibility': return 'Eligibility';
      default:           return 'General';
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Column(
        children: [
          // ── HEADER ────────────────────────────────────────────
          _buildHeader(size),

          // ── BODY ──────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFDC2626)),
                  )
                : _errorMessage != null
                    ? _buildError()
                    : _notifications.isEmpty
                        ? _buildEmpty()
                        : _buildList(size),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Size size) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: size.height * 0.06,
        left: 20,
        right: 20,
        bottom: 18,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF750000), Color(0xFFFF4E4E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _unreadCount > 0
                      ? '$_unreadCount unread message${_unreadCount > 1 ? 's' : ''}'
                      : 'All caught up!',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          // Mark all read button — in header, top-right
          if (_unreadCount > 0 && !_isLoading && _errorMessage == null)
            GestureDetector(
              onTap: _markAllAsRead,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white38),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.done_all_rounded, color: Colors.white, size: 14),
                    SizedBox(width: 5),
                    Text(
                      'Mark all read',
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
      ),
    );
  }

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
                color: const Color(0xFFFFF1F1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi_off_rounded, size: 40, color: Color(0xFFDC2626)),
            ),
            const SizedBox(height: 20),
            const Text(
              'Connection Error',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchNotifications,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20),
              ],
            ),
            child: Icon(Icons.notifications_off_rounded, size: 48, color: Colors.grey.shade300),
          ),
          const SizedBox(height: 20),
          const Text(
            'No notifications yet',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "You're all caught up. We'll\nnotify you when something new arrives.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildList(Size size) {
    return RefreshIndicator(
      onRefresh: _fetchNotifications,
      color: const Color(0xFFDC2626),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: size.width * 0.04,
          vertical: 16,
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
              typeLabel: _getTypeLabel(
                _notifications[index].notificationType,
              ),
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
            color: const Color(0xFFDC2626),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_rounded, color: Colors.white, size: 24),
              SizedBox(height: 4),
              Text('Delete', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: !notification.isRead
                    ? const Color(0xFFDC2626).withOpacity(0.4)
                    : Colors.transparent,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isExpanded
                      ? typeColor.withOpacity(0.12)
                      : Colors.black.withOpacity(0.06),
                  blurRadius: isExpanded ? 16 : 6,
                  offset: const Offset(0, 3),
                ),
              ],
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
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
                                      color: Color(0xFFDC2626),
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
                                color: const Color(0xFF111827),
                              ),
                              maxLines: isExpanded ? null : 1,
                              overflow: isExpanded ? null : TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              notification.date,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF9CA3AF),
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
                          color: isExpanded ? typeColor : const Color(0xFFD1D5DB),
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
                        color: Colors.grey.shade100,
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
                                Icon(Icons.access_time_rounded,
                                    size: 13, color: Colors.grey.shade400),
                                const SizedBox(width: 4),
                                Text(
                                  notification.createdAt.isNotEmpty
                                      ? notification.createdAt
                                      : notification.date,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                                const Spacer(),
                                // Delete button
                                GestureDetector(
                                  onTap: () async {
                                    final confirm = await _confirmDelete(context);
                                    if (confirm == true) onDelete();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF1F1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.delete_outline_rounded,
                                            size: 14, color: Color(0xFFDC2626)),
                                        SizedBox(width: 4),
                                        Text(
                                          'Delete',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFFDC2626),
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
        content: const Text(
          'Are you sure you want to delete this notification? This cannot be undone.',
          style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}