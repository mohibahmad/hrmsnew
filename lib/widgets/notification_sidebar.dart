import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../services/dummy_data.dart';
import '../utils/delete_dialog.dart';

class NotificationSidebar extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<String>? onNotificationTap;
  const NotificationSidebar({
    super.key,
    required this.onClose,
    this.onNotificationTap,
  });

  @override
  ConsumerState<NotificationSidebar> createState() => _NotificationSidebarState();
}

class _NotificationSidebarState extends ConsumerState<NotificationSidebar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  StreamSubscription? _notifSub;
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  late AuthService _authService;
  late FirestoreService _firestore;

  @override
  void initState() {
    super.initState();
    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);
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

    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      _notifications = List<Map<String, dynamic>>.from(DummyData.notifications);

      var backfilled = false;
      for (var i = 0; i < _notifications.length; i++) {
        final id = _notifications[i]['id']?.toString();
        if (id == null || id.isEmpty) {
          _notifications[i]['id'] = 'notif_$i';
          backfilled = true;
        }
      }
      if (backfilled) {
        unawaited(DummyData.saveToPrefs());
      }
      _isLoading = false;
    } else {
      _notifSub = _firestore.notificationsStream.listen(
        (snap) {
          if (mounted) {
            setState(() {
              _notifications = snap.docs
                  .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
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

  Future<void> _removeNotification(String notificationId) async {
    if (notificationId.trim().isEmpty) return;
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      DummyData.notifications.removeWhere(
        (notification) => notification['id']?.toString() == notificationId,
      );
      await DummyData.saveToPrefs();
    } else {
      await _firestore.deleteNotification(notificationId);
    }
    if (mounted) {
      setState(() {
        _notifications.removeWhere((n) => n['id'] == notificationId);
      });
    }
  }

  String _localizedTitle(Map<String, dynamic> notif) {
    final type = (notif['type'] ?? '').toString();
    final data = notif['data'] is Map ? notif['data'] as Map : {};
    final args = <String, String>{
      for (final e in data.entries)
        if (e.value != null) e.key.toString(): e.value.toString(),
    };
    switch (type) {
      case 'welcome':
        return args.containsKey('name')
            ? 'notif_title_welcome'.tr(namedArgs: args)
            : (notif['title'] ?? 'notif_title_welcome').toString();
      case 'worker_added':
        return args.containsKey('count')
            ? 'notif_title_bulk_workers'.tr(namedArgs: args)
            : (args.containsKey('name')
                  ? 'notif_title_new_member'.tr(namedArgs: args)
                  : (notif['title'] ?? 'notif_title_new_member').toString());
      case 'attendance_marked':
        return args.containsKey('name')
            ? 'notif_title_attendance'.tr(namedArgs: args)
            : (notif['title'] ?? 'notif_title_attendance').toString();
      case 'payroll_added':
        return args.containsKey('name')
            ? 'notif_title_payroll'.tr(namedArgs: args)
            : (notif['title'] ?? 'notif_title_payroll').toString();
      case 'payroll_due':
        return 'notif_title_payroll_due'.tr();
      case 'time_off_added':
        return args.containsKey('name')
            ? 'notif_title_time_off'.tr(namedArgs: args)
            : (notif['title'] ?? 'notif_title_time_off').toString();
      case 'holiday_added':
        return args.containsKey('name')
            ? 'notif_title_holiday'.tr(namedArgs: args)
            : (notif['title'] ?? 'notif_title_holiday').toString();
      case 'expense_added':
        if (args.containsKey('category') &&
            (args['category'] ?? '').isNotEmpty) {
          return 'notif_title_expense_category'.tr(namedArgs: args);
        }
        if (args.containsKey('amount') && (args['amount'] ?? '').isNotEmpty) {
          return 'notif_title_expense'.tr();
        }
        return (notif['title'] ?? 'notif_title_expense').toString();
      case 'asset_added':
        if (args.containsKey('type') && (args['type'] ?? '').isNotEmpty) {
          return 'notif_title_asset_type'.tr(namedArgs: args);
        }
        return (notif['title'] ?? 'notif_title_asset').toString();
      default:
        return (notif['title'] ?? '').toString();
    }
  }

  String _localizedMessage(Map<String, dynamic> notif) {
    final type = (notif['type'] ?? '').toString();
    final data = notif['data'] is Map ? notif['data'] as Map : {};
    final args = <String, String>{
      for (final e in data.entries)
        if (e.value != null) e.key.toString(): e.value.toString(),
    };
    switch (type) {
      case 'welcome':
        return 'notif_msg_welcome'.tr();
      case 'worker_added':
        return args.containsKey('count')
            ? 'notif_msg_bulk_workers'.tr(namedArgs: args)
            : (args.containsKey('name')
                  ? 'notif_msg_new_member'.tr(namedArgs: args)
                  : (notif['message'] ?? 'notif_msg_new_member').toString());
      case 'attendance_marked':
        return args.containsKey('name')
            ? 'notif_msg_attendance'.tr(namedArgs: args)
            : (notif['message'] ?? 'notif_msg_attendance').toString();
      case 'payroll_added':
        if (args.containsKey('amount') && (args['amount'] ?? '').isNotEmpty) {
          return 'notif_msg_payroll_amount'.tr(namedArgs: args);
        }
        return args.containsKey('name')
            ? 'notif_msg_payroll'.tr(namedArgs: args)
            : (notif['message'] ?? 'notif_msg_payroll').toString();
      case 'payroll_due':
        return args.containsKey('count') && args.containsKey('period')
            ? 'notif_msg_payroll_due'.tr(namedArgs: args)
            : (notif['message'] ?? '').toString();
      case 'time_off_added':
        return args.containsKey('name')
            ? 'notif_msg_time_off'.tr(namedArgs: args)
            : (notif['message'] ?? 'notif_msg_time_off').toString();
      case 'holiday_added':
        return args.containsKey('name')
            ? 'notif_msg_holiday'.tr(namedArgs: args)
            : (notif['message'] ?? 'notif_msg_holiday').toString();
      case 'expense_added':
        if (args.containsKey('amount') && (args['amount'] ?? '').isNotEmpty) {
          return 'notif_msg_expense_amount'.tr(namedArgs: args);
        }
        return 'notif_msg_expense'.tr();
      case 'asset_added':
        if (args.containsKey('type') && (args['type'] ?? '').isNotEmpty) {
          return 'notif_msg_asset_type'.tr(namedArgs: args);
        }
        return args.containsKey('name')
            ? 'notif_msg_asset'.tr(namedArgs: args)
            : (notif['message'] ?? 'notif_msg_asset').toString();
      default:
        return (notif['message'] ?? '').toString();
    }
  }

  String _getTimeAgo(dynamic createdAt) {
    try {
      DateTime created;
      if (createdAt is Timestamp) {
        created = createdAt.toDate();
      } else if (createdAt is String) {
        created = DateTime.parse(createdAt);
      } else {
        return '';
      }
      final now = DateTime.now();
      final diff = now.difference(created);
      if (diff.inMinutes < 1) return 'just_now'.tr();
      if (diff.inMinutes < 60)
        return 'time_ago_minutes'.tr(namedArgs: {'count': '${diff.inMinutes}'});
      if (diff.inHours < 24)
        return 'time_ago_hours'.tr(namedArgs: {'count': '${diff.inHours}'});
      if (diff.inDays < 7)
        return 'time_ago_days'.tr(namedArgs: {'count': '${diff.inDays}'});
      return DateFormat('time_ago_date'.tr(), context.locale.toString())
          .format(created);
    } catch (_) {
      return '';
    }
  }

  _NotifStyle _getStyle(String type) {
    switch (type) {
      case 'welcome':
        return _NotifStyle(
          icon: Icons.waving_hand_rounded,
          color: const Color(0xFF4C84E0),
          bgColor: const Color(0xFFEAF0FF),
          label: 'notif_welcome'.tr(),
          isWelcome: true,
        );
      case 'worker_added':
        return _NotifStyle(
          icon: Icons.person_add_rounded,
          color: const Color(0xFF4C84E0),
          bgColor: const Color(0xFFEAF0FF),
          label: 'notif_new_member'.tr(),
          iconAsset: 'assets/workers_icon_slidebar.svg',
        );
      case 'holiday_added':
        return _NotifStyle(
          icon: Icons.celebration_rounded,
          color: const Color(0xFFFF5F65),
          bgColor: const Color(0xFFFFECED),
          label: 'notif_holiday'.tr(),
          iconAsset: 'assets/holidays_icon.svg',
        );
      case 'attendance_marked':
        return _NotifStyle(
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF22C55E),
          bgColor: const Color(0xFFE8FAF0),
          label: 'notif_attendance'.tr(),
          iconAsset: 'assets/total_salary.svg',
        );
      case 'payroll_added':
        return _NotifStyle(
          icon: Icons.account_balance_wallet_rounded,
          color: const Color(0xFF8B5CF6),
          bgColor: const Color(0xFFF3EEFF),
          label: 'notif_payroll'.tr(),
          iconAsset: 'assets/payroll_icon.svg',
        );
      case 'payroll_due':
        return _NotifStyle(
          icon: Icons.info_rounded,
          color: const Color(0xFFEF4444),
          bgColor: const Color(0xFFFFECEC),
          label: 'notif_info'.tr(),
        );
      case 'time_off_added':
        return _NotifStyle(
          icon: Icons.beach_access_rounded,
          color: const Color(0xFFF59E0B),
          bgColor: const Color(0xFFFFF8E8),
          label: 'notif_time_off'.tr(),
          iconAsset: 'assets/time_off_icon.svg',
        );
      case 'asset_added':
        return _NotifStyle(
          icon: Icons.devices_rounded,
          color: const Color(0xFF14B8A6),
          bgColor: const Color(0xFFE6FAF8),
          label: 'notif_asset'.tr(),
          iconAsset: 'assets/asset_icon.png',
        );
      case 'expense_added':
        return _NotifStyle(
          icon: Icons.receipt_rounded,
          color: const Color(0xFFEF4444),
          bgColor: const Color(0xFFFFECEC),
          label: 'notif_expense'.tr(),
          iconAsset: 'assets/expenses_icon_slidebar.svg',
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
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF1A1A1A)
                      : const Color(0xFFFFFFFF),
                  border: Border(
                    left: BorderSide(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[800]!
                          : const Color(0xFFE5E7EB),
                      width: 1,
                    ),
                  ),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFFFFFF),
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey[800]! : const Color(0xFFEEEEEE),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                'notifications'.tr(),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF000000),
                  fontFamily: 'SF Pro Display',
                ),
              ),
              if (_notifications.isNotEmpty) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0247C4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_notifications.length}',
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
              if (_notifications.length > 1)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () async {
                      final confirmed = await DeleteDialog.show(
                        context: context,
                        title: 'delete_all_notifications'.tr(),
                        content: 'delete_all_notifications_desc'.tr(),
                        confirmButtonText: 'clear_all',
                      );
                      if (confirmed) {
                        final isGuest =
                            _authService.currentUser?.isAnonymous ?? false;
                        if (!isGuest) {
                          await _firestore.clearAllNotifications();
                        } else {
                          DummyData.notifications.clear();
                          await DummyData.saveToPrefs();
                        }
                        setState(() {
                          _notifications.clear();
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0247C4).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF0247C4).withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.clear_all,
                            size: 16,
                            color: const Color(0xFF0247C4),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'clear_all'.tr(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF0247C4),
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ],
                      ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/notification_icon.svg',
            width: 50,
            height: 50,
            colorFilter: ColorFilter.mode(
              isDark ? Colors.grey[600]! : const Color(0xFF9CA3AF),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'no_notifications_yet'.tr(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[600] : const Color(0xFF9CA3AF),
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
      separatorBuilder: (_, _) => Divider(
        height: 1,
        thickness: 1,
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[800]
            : const Color(0xFFF3F4F6),
        indent: 24,
        endIndent: 24,
      ),
      itemBuilder: (context, index) {
        final notif = _notifications[index];
        final type = (notif['type'] ?? '').toString();
        final title = _localizedTitle(notif);
        final message = _localizedMessage(notif);
        final createdAt = notif['createdAt'];
        final style = _getStyle(type);

        if (style.isWelcome) {
          return _buildWelcomeCard(
            title: title,
            message: message,
            timeAgo: _getTimeAgo(createdAt),
            notificationId: notif['id'] ?? '',
          );
        }

        return _buildNotificationItem(
          type: type,
          style: style,
          title: title,
          message: message,
          timeAgo: _getTimeAgo(createdAt),
          notificationId: notif['id'] ?? '',
        );
      },
    );
  }

  Widget _buildWelcomeCard({
    required String title,
    required String message,
    required String timeAgo,
    required String notificationId,
  }) {
    return GestureDetector(
      onTap: () {
        widget.onNotificationTap?.call('welcome');
        _removeNotification(notificationId);
      },
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/app_icon.png',
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
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
                                'notif_welcome'.tr(),
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
                      const Spacer(),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.6),
                          fontFamily: 'SF Pro Display',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () async {
                          await _removeNotification(notificationId);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'mark_read'.tr(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
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
    );
  }

  Widget _buildNotificationItem({
    required String type,
    required _NotifStyle style,
    required String title,
    required String message,
    required String timeAgo,
    required String notificationId,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: (isDark ? Colors.grey[850] : const Color(0xFFF8FAFF)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          GestureDetector(
            onTap: () {
              widget.onNotificationTap?.call(type);
              _removeNotification(notificationId);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
                          ? (style.iconAsset!.endsWith('.png')
                                ? Image.asset(
                                    style.iconAsset!,
                                    width: 22,
                                    height: 22,
                                    color: style.color,
                                  )
                                : SvgPicture.asset(
                                    style.iconAsset!,
                                    width: 22,
                                    height: 22,
                                    colorFilter: ColorFilter.mode(
                                      style.color,
                                      BlendMode.srcIn,
                                    ),
                                  ))
                          : Icon(style.icon, size: 22, color: style.color),
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              timeAgo,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.grey[600]
                                    : const Color(0xFF9CA3AF),
                                fontFamily: 'SF Pro Display',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: theme.primaryColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF111827),
                            fontFamily: 'SF Pro Display',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          message,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: isDark
                                ? Colors.grey[400]
                                : const Color(0xFF6B7280),
                            fontFamily: 'SF Pro Display',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            top: 8,
            right: 8,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () async {
                  await _removeNotification(notificationId);
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.grey[200],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),
            ),
          ),
        ],
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
  const _NotifStyle({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.label,
    this.isWelcome = false,
    this.iconAsset,
  });
}
