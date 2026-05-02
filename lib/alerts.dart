import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
        _errorMessage = 'Connection error: Unable to reach server. Please check your connection and try again.';
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
              _notifications[index] = NotificationModel(
                id: _notifications[index].id,
                title: _notifications[index].title,
                message: _notifications[index].message,
                notificationType: _notifications[index].notificationType,
                isRead: true,
                date: _notifications[index].date,
                createdAt: _notifications[index].createdAt,
              );
              _unreadCount--;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to mark as read. Please try again.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
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
            _notifications = _notifications.map((notification) {
              return NotificationModel(
                id: notification.id,
                title: notification.title,
                message: notification.message,
                notificationType: notification.notificationType,
                isRead: true,
                date: notification.date,
                createdAt: notification.createdAt,
              );
            }).toList();
            _unreadCount = 0;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('All notifications marked as read'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error marking all as read: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to mark all as read. Please try again.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'appointment':
        return Colors.blue;
      case 'reminder':
        return Colors.orange;
      case 'thank_you':
        return Colors.green;
      case 'eligibility':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'appointment':
        return Icons.calendar_today;
      case 'reminder':
        return Icons.notifications_active;
      case 'thank_you':
        return Icons.favorite;
      case 'eligibility':
        return Icons.bloodtype;
      default:
        return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final screenHeight = size.height;

    return Scaffold(
      backgroundColor: const Color(0xFFDDDDDD),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: screenHeight * 0.06,
              bottom: screenHeight * 0.03,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF750000), Color(0xFFFF4E4E)],
              ),
            ),
            child: Column(
              children: [
                const Text(
                  "Notifications",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "$_unreadCount unread",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF850000),
                      ),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _fetchNotifications,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF850000),
                                  ),
                                  child: const Text(
                                    "Retry",
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _notifications.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.notifications_off,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    "No notifications",
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _fetchNotifications,
                              child: SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: EdgeInsets.symmetric(
                                    vertical: size.height * 0.02,
                                    horizontal: size.width * 0.04),
                                child: Column(
                                  children: _notifications.map((notification) {
                                    return Padding(
                                      padding: EdgeInsets.only(
                                          bottom: size.height * 0.02),
                                      child: InkWell(
                                        onTap: () {
                                          if (!notification.isRead) {
                                            _markAsRead(notification.id);
                                          }
                                        },
                                        child: Container(
                                          padding: EdgeInsets.all(
                                              size.width * 0.04),
                                          decoration: BoxDecoration(
                                            color: notification.isRead
                                                ? Colors.white
                                                : Colors.white
                                                    .withOpacity(0.95),
                                            borderRadius:
                                                BorderRadius.circular(9),
                                            border: Border.all(
                                              color: notification.isRead
                                                  ? Colors.grey[300]!
                                                  : const Color(0xFF850000),
                                              width: notification.isRead
                                                  ? 1
                                                  : 2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                blurRadius: 4,
                                                color: Colors.black12,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Notification type icon
                                              Container(
                                                padding:
                                                    const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: _getNotificationColor(
                                                          notification
                                                              .notificationType)
                                                      .withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Icon(
                                                  _getNotificationIcon(
                                                      notification
                                                          .notificationType),
                                                  color: _getNotificationColor(
                                                      notification
                                                          .notificationType),
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              // Content
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            notification.title,
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight: notification
                                                                      .isRead
                                                                  ? FontWeight
                                                                      .w500
                                                                  : FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ),
                                                        if (!notification
                                                            .isRead)
                                                          Container(
                                                            width: 10,
                                                            height: 10,
                                                            decoration: const BoxDecoration(
                                                              color: Color(
                                                                  0xFF850000),
                                                              shape: BoxShape
                                                                  .circle,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      notification.message,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color:
                                                            Color(0xFF757575),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      notification.date,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color:
                                                            Color(0xFF757575),
                                                        fontWeight:
                                                            FontWeight.w400,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
            ),

            // MARK ALL READ BUTTON
            if (_unreadCount > 0 && !_isLoading && _errorMessage == null)
              Padding(
                padding: EdgeInsets.only(
                  bottom: size.height * 0.02,
                  left: size.width * 0.04,
                  right: size.width * 0.04,
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF850000)),
                    minimumSize: Size(double.infinity, 45),
                  ),
                  onPressed: _markAllAsRead,
                  child: const Text(
                    "Mark all as read",
                    style: TextStyle(color: Color(0xFF850000)),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
