import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../services/dummy_data.dart';

class NotificationBell extends ConsumerStatefulWidget {
  final VoidCallback? onTap;
  const NotificationBell({super.key, required this.onTap});

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  StreamSubscription? _notifSub;
  int _unreadCount = 0;
  late AuthService _authService;
  late FirestoreService _firestore;

  @override
  void initState() {
    super.initState();
    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      return;
    }
    _notifSub = _firestore.notificationsStream.listen((snap) {
      if (mounted) {
        setState(() {
          _unreadCount = snap.docs.where((d) {
            final data = d.data() as Map<String, dynamic>?;
            return data?['isRead'] != true;
          }).length;
        });
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = _authService.currentUser?.isAnonymous ?? false;

    final int unreadCount = isGuest
        ? DummyData.notifications.where((n) => n['isRead'] != true).length
        : _unreadCount;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          widget.onTap?.call();
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SvgPicture.asset(
              'assets/notification_icon.svg',
              width: 22,
              height: 26,
              colorFilter: const ColorFilter.mode(
                Color(0xFF000000),
                BlendMode.srcIn,
              ),
            ),
            if (unreadCount > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$unreadCount',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
