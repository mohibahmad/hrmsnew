import 'dart:async';
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';

class NotificationSidebar extends StatefulWidget {
  final VoidCallback onClose;
  const NotificationSidebar({super.key, required this.onClose});

  @override
  State<NotificationSidebar> createState() => _NotificationSidebarState();
}

class _NotificationSidebarState extends State<NotificationSidebar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  StreamSubscription? _notifSub;
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();

    _notifSub = FirestoreService().notificationsStream.listen((snap) {
      if (mounted) {
        setState(() {
          _notifications = snap.docs
              .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
              .toList();
          _isLoading = false;
        });
      }
    }, onError: (_) {
      if (mounted) setState(() => _isLoading = false);
    });

    FirestoreService().markAllNotificationsRead();
  }

  @override
  void dispose() {
    _controller.reverse();
    _notifSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    _controller.reverse().then((_) {
      widget.onClose();
    });
  }

  String _getTimeAgo(String createdAtStr) {
    try {
      final created = DateTime.parse(createdAtStr);
      final now = DateTime.now();
      final diff = now.difference(created);
      if (diff.inMinutes < 1) return 'just_now'.tr();
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return DateFormat('dd MMM').format(created);
    } catch (_) {
      return '';
    }
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'worker_added':
        return Icons.person_add;
      case 'holiday_added':
        return Icons.celebration;
      case 'attendance_marked':
        return Icons.check_circle;
      default:
        return Icons.info;
    }
  }

  Color _getIconColor(String type) {
    switch (type) {
      case 'worker_added':
        return const Color(0xFF4C84E0);
      case 'holiday_added':
        return const Color(0xFFFF5F65);
      case 'attendance_marked':
        return const Color(0xFF4AC000);
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double headerHeight = 94;
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: EdgeInsets.only(top: headerHeight),
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: 400,
                height: MediaQuery.of(context).size.height - headerHeight,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFFFFF),
                ),
                child: Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _notifications.isEmpty
                              ? _buildEmptyState()
                              : _buildNotificationList(),
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

  Widget _buildHeader() {
    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Builder(
            builder: (context) {
              final notifText = 'notifications'.tr();
              return RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: notifText.isNotEmpty ? notifText[0] : 'N',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF000000),
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                    TextSpan(
                      text: notifText.length > 1 ? notifText.substring(1) : '',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF000000),
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          GestureDetector(
            onTap: _close,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.close,
                size: 20,
                color: Color(0xFF000000),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/notification_icon.svg',
            width: 50,
            height: 50,
            colorFilter: const ColorFilter.mode(
              Color(0xFF9CA3AF),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'no_notifications_yet'.tr(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF9CA3AF),
              fontFamily: 'SF Pro Display',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: _notifications.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final notif = _notifications[index];
        final type = (notif['type'] ?? '').toString();
        final title = (notif['title'] ?? '').toString();
        final message = (notif['message'] ?? '').toString();
        final createdAt = (notif['createdAt'] ?? '').toString();
        final isRead = notif['isRead'] == true;

        return _buildNotificationItem(
          icon: _getIcon(type),
          iconColor: _getIconColor(type),
          title: title,
          message: message,
          timeAgo: _getTimeAgo(createdAt),
          isRead: isRead,
          onTap: () {
            final id = notif['id']?.toString();
            if (id != null && !isRead) {
              FirestoreService().markNotificationRead(id);
            }
          },
        );
      },
    );
  }

  Widget _buildNotificationItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String timeAgo,
    required bool isRead,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        color: Colors.transparent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                      color: const Color(0xFF000000),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF6B7280),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeAgo,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF9CA3AF),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ],
              ),
            ),
            if (!isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(
                  color: Color(0xFF4C84E0),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
