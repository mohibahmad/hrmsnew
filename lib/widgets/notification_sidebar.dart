import 'dart:async';
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';

class NotificationSidebar extends StatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<String>? onNotificationTypeTapped;
  const NotificationSidebar({
    super.key,
    required this.onClose,
    this.onNotificationTypeTapped,
  });

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
    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();

    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (isGuest) {
      _isLoading = false;
    } else {
      _notifSub = FirestoreService().notificationsStream.listen(
        (snap) {
          if (mounted) {
            setState(() {
              _notifications = snap.docs
                  .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                  .where((n) => n['isRead'] != true)
                  .toList();
              _isLoading = false;
            });
          }
        },
        onError: (_) {
          if (mounted) setState(() => _isLoading = false);
        },
      );
    }
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

  _NotifStyle _getStyle(String type) {
    switch (type) {
      case 'new_member':
      case 'worker_added':
        return _NotifStyle(
          icon: Icons.person_add_rounded,
          color: const Color(0xFF4C84E0),
          bgColor: const Color(0xFFEAF0FF),
          label: 'notif_new_member'.tr(),
          isWelcome: true,
        );
      case 'holiday_added':
        return _NotifStyle(
          icon: Icons.celebration_rounded,
          color: const Color(0xFFFF5F65),
          bgColor: const Color(0xFFFFECED),
          label: 'notif_holiday'.tr(),
        );
      case 'attendance_marked':
        return _NotifStyle(
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF22C55E),
          bgColor: const Color(0xFFE8FAF0),
          label: 'notif_attendance'.tr(),
        );
      case 'payroll_added':
        return _NotifStyle(
          icon: Icons.account_balance_wallet_rounded,
          color: const Color(0xFF8B5CF6),
          bgColor: const Color(0xFFF3EEFF),
          label: 'notif_payroll'.tr(),
        );
      case 'time_off_added':
        return _NotifStyle(
          icon: Icons.beach_access_rounded,
          color: const Color(0xFFF59E0B),
          bgColor: const Color(0xFFFFF8E8),
          label: 'notif_time_off'.tr(),
        );
      case 'asset_added':
        return _NotifStyle(
          icon: Icons.devices_rounded,
          color: const Color(0xFF14B8A6),
          bgColor: const Color(0xFFE6FAF8),
          label: 'notif_asset'.tr(),
        );
      case 'expense_added':
        return _NotifStyle(
          icon: Icons.receipt_rounded,
          color: const Color(0xFFEF4444),
          bgColor: const Color(0xFFFFECEC),
          label: 'notif_expense'.tr(),
          iconAsset: 'assets/expenses.png',
          iconSize: 32,
        );
      default:
        return _NotifStyle(
          icon: Icons.info_rounded,
          color: const Color(0xFF9CA3AF),
          bgColor: const Color(0xFFF3F4F6),
          label: 'notif_info'.tr(),
        );
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
                decoration: const BoxDecoration(color: Color(0xFFFFFFFF)),
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
    final unreadCount = _notifications.where((n) => n['isRead'] != true).length;
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
          Row(
            children: [
              Text(
                'notifications'.tr(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF000000),
                  fontFamily: 'SF Pro Display',
                ),
              ),
              if (unreadCount > 0) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4C84E0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$unreadCount',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFFFFFF),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ),
              ],
            ],
          ),
          Row(
            children: [
              if (unreadCount >= 1)
                GestureDetector(
                  onTap: () async {
                    await FirestoreService().clearAllNotifications();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'clear_all'.tr(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFEF4444),
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
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
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        thickness: 1,
        color: Color(0xFFF3F4F6),
        indent: 24,
        endIndent: 24,
      ),
      itemBuilder: (context, index) {
        final notif = _notifications[index];
        final type = (notif['type'] ?? '').toString();
        final title = (notif['title'] ?? '').toString();
        final message = (notif['message'] ?? '').toString();
        final createdAt = (notif['createdAt'] ?? '').toString();
        final isRead = notif['isRead'] == true;
        final style = _getStyle(type);

        if (style.isWelcome) {
          return _buildWelcomeCard(
            title: title,
            message: message,
            timeAgo: _getTimeAgo(createdAt),
            isRead: isRead,
            onTap: () {
              widget.onNotificationTypeTapped?.call(type);
              _close();
            },
          );
        }

        return _buildNotificationItem(
          style: style,
          title: title,
          message: message,
          timeAgo: _getTimeAgo(createdAt),
          isRead: isRead,
          onTap: () {
            widget.onNotificationTypeTapped?.call(type);
            _close();
          },
        );
      },
    );
  }

  Widget _buildWelcomeCard({
    required String title,
    required String message,
    required String timeAgo,
    required bool isRead,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4C84E0), Color(0xFF0247C4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4C84E0).withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Decorative circles
            Positioned(
              top: -20,
              right: -20,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: -15,
              left: 60,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.waving_hand_rounded,
                          color: Color(0xFFFFFFFF),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'notif_new_member'.tr(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFFFFFFF),
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFFFFF),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFFFFFF),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withValues(alpha: 0.8),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    timeAgo,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.6),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationItem({
    required _NotifStyle style,
    required String title,
    required String message,
    required String timeAgo,
    required bool isRead,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        color: isRead ? Colors.transparent : const Color(0xFFF8FAFF),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: style.bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: style.iconAsset != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ColorFiltered(
                          colorFilter: const ColorFilter.mode(
                            Color(0xFFEF4444),
                            BlendMode.srcIn,
                          ),
                          child: Image.asset(
                            style.iconAsset!,
                            width: style.iconSize,
                            height: style.iconSize,
                            fit: BoxFit.contain,
                          ),
                        ),
                      )
                    : Icon(
                        style.icon,
                        size: style.iconSize,
                        color: style.color,
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: style.bgColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          style.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: style.color,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        timeAgo,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                      if (!isRead) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: style.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                      color: const Color(0xFF111827),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF6B7280),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotifStyle {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String label;
  final bool isWelcome;
  final String? iconAsset;
  final double iconSize;

  const _NotifStyle({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.label,
    this.isWelcome = false,
    this.iconAsset,
    this.iconSize = 22,
  });
}
