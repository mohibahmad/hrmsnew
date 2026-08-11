import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers.dart';
import '../../services/auth_service.dart';

class TopHeader extends ConsumerWidget {
  final VoidCallback onProfileTap;
  final VoidCallback onNotificationTap;
  final int unreadCount;
  const TopHeader({
    super.key,
    required this.onProfileTap,
    required this.onNotificationTap,
    this.unreadCount = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.read(authServiceProvider).currentUser;
    String name = user?.displayName ?? 'User';
    if (name.trim().isEmpty || name == 'User') {
      name = 'user_name'.tr();
    } else if (name == 'Guest User') {
      name = 'guest_user'.tr();
    }

    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(bottom: BorderSide(color: Color(0xFFEEEFF2))),
        boxShadow: [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'welcome_user'.tr(namedArgs: {'name': name}),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF000000),
                  fontFamily: 'SF Pro Display',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              Text(
                'welcome_subtitle'.tr(),
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF000000),
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ],
          ),
          Row(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                onTap: onNotificationTap,
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              ),
              const SizedBox(width: 20),
              GestureDetector(onTap: onProfileTap, child: const UserAvatar()),
            ],
          ),
        ],
      ),
    );
  }
}
