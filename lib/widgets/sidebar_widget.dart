import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';
import '../screens/pricing_screen.dart';

class SidebarWidget extends StatefulWidget {
  final int selectedIndex;
  final int selectedSubIndex;
  final bool isGuest;
  final bool isPremium;
  final void Function(int index, {int? subIndex}) onItemSelected;
  final VoidCallback? onBackToLogin;

  const SidebarWidget({
    super.key,
    required this.selectedIndex,
    this.selectedSubIndex = 0,
    this.isGuest = false,
    this.isPremium = false,
    required this.onItemSelected,
    this.onBackToLogin,
  });

  @override
  State<SidebarWidget> createState() => _SidebarWidgetState();
}

class _SidebarWidgetState extends State<SidebarWidget> {
  bool _isWorkforceExpanded = false;

  @override
  void initState() {
    super.initState();
    _isWorkforceExpanded = widget.selectedIndex == 2;
  }

  @override
  void didUpdateWidget(covariant SidebarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex == 2) {
      _isWorkforceExpanded = true;
    }
  }

  static final _menuItems = [
    ('assets/dashbaord_icon_slidebar.svg', 'sidebar_dashboard', false),
    ('assets/workers_icon_slidebar.svg', 'sidebar_workers', false),
    ('assets/workforce_icon_sldiebar.svg', 'sidebar_workforce', true),
    ('assets/expenses_icon_slidebar.svg', 'sidebar_expenses', false),
    ('assets/settings_icon_slidebar.svg', 'sidebar_settings', false),
  ];

  static final _subItems = [
    ('assets/total_salary.svg', 'sidebar_attendance'),
    ('assets/payroll_icon.svg', 'sidebar_payroll'),
    ('assets/time_off_icon.svg', 'sidebar_time_off'),
    ('assets/assets_icon.svg', 'sidebar_assets'),
    ('assets/holidays_icon.svg', 'sidebar_holidays'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 270,
      color: const Color(0xFF0247C4),
      child: Column(
        children: [
          if (!widget.isGuest && !widget.isPremium)
            GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
                  builder: (context) => const SubscriptionDialog(),
                );
              },
              child: Container(
                width: 238,
                margin: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Color(0xFFFFFFFF), width: 1.0),
                  image: const DecorationImage(
                    image: AssetImage('assets/premium_bg.png'),
                    fit: BoxFit.cover,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFFFFFFFF).withValues(alpha: 0.55),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Color(0xFF4C84E0).withValues(alpha: 0.25),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        children: [
                          Image.asset(
                            'assets/premium_icon.png',
                            width: 28,
                            height: 28,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'upgrade_pro'.tr(),
                            style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildCheckText('unlock_all_features'.tr()),
                    _buildCheckText('no_commitment'.tr()),
                    _buildCheckText('cancel_anytime'.tr()),
                    const SizedBox(height: 10),
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.centerRight,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 50,
                          padding: const EdgeInsets.only(left: 16, right: 52),
                          decoration: BoxDecoration(
                            color: Color(0xFF000000),
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(
                              color: Color(0xFFFFFFFF),
                              width: 1.0,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'get_to_pro'.tr(),
                                maxLines: 1,
                                style: TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'SF Pro',
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'subscribe_now'.tr(),
                                maxLines: 1,
                                style: TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'SF Pro',
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: -5,
                          top: -3,
                          bottom: -3,
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFFFFF),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Image.asset(
                              "assets/right_back_arrow.png",
                              width: 20,
                              height: 20,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  for (int i = 0; i < _menuItems.length; i++)
                    if (_menuItems[i].$3)
                      _buildWorkforceItem(i)
                    else
                      _buildMenuItem(
                        _menuItems[i].$1,
                        _menuItems[i].$2.tr(),
                        isSelected: widget.selectedIndex == i,
                        hasDropdown: _menuItems[i].$3,
                        onTap: () {
                          widget.onItemSelected(i);
                        },
                      ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          if (widget.isGuest)
            Container(
              height: 42,
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFFFFFFF).withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: GestureDetector(
                onTap: widget.onBackToLogin,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.arrow_back,
                        color: Color(0xFFFFFFFF),
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'back_to_login_sidebar'.tr(),
                          style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'SF Pro',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWorkforceItem(int index) {
    if (_isWorkforceExpanded) {
      final isSelected = widget.selectedIndex == index;
      return Stack(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
            decoration: BoxDecoration(
              color: Color(0xFFFFFFFF).withValues(alpha: 0.36),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _buildWorkforceHeaderItem(
                  onTap: () {
                    setState(() {
                      _isWorkforceExpanded = false;
                    });
                  },
                ),
                const SizedBox(height: 4),
                for (int i = 0; i < _subItems.length; i++)
                  _buildSubMenuItem(
                    _subItems[i].$1,
                    _subItems[i].$2.tr(),
                    isSelected:
                        widget.selectedIndex == index &&
                        widget.selectedSubIndex == i,
                    onTap: () {
                      widget.onItemSelected(index, subIndex: i);
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 11.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 50),
              width: 8,
              height: isSelected ? 32 : 0,
              decoration: const BoxDecoration(
                color: Color(0xFFFFFFFF),
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      return _buildMenuItem(
        _menuItems[index].$1,
        _menuItems[index].$2.tr(),
        isSelected: widget.selectedIndex == index,
        hasDropdown: true,
        onTap: () {
          setState(() {
            _isWorkforceExpanded = true;
          });
          widget.onItemSelected(index);
        },
      );
    }
  }

  Widget _buildWorkforceHeaderItem({VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/workforce_icon_sldiebar.svg',
              height: 22,
              width: 22,
              color: Color(0xFFFFFFFF),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'sidebar_workforce'.tr(),
                style: TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'SF Pro',
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down,
              color: Color(0xFFFFFFFF),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubMenuItem(
    String iconAsset,
    String title, {
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 50),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFFFFF).withValues(alpha: 0.36)
              : const Color(0x00FFFFFF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SvgPicture.asset(
              iconAsset,
              height: 20,
              width: 20,
              color: Color(0xFFFFFFFF),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.w500,
                  fontFamily: 'SF Pro',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckText(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/tick_icon.svg',
              width: 14,
              height: 10,
              color: Color(0xFFFFFFFF),
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    String iconAsset,
    String title, {
    bool isSelected = false,
    bool hasDropdown = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFFFFFFF).withValues(alpha: 0.36)
                  : const Color(0x00FFFFFF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  iconAsset,
                  height: 22,
                  width: 22,
                  color: Color(0xFFFFFFFF),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 18,
                      fontWeight: isSelected
                          ? FontWeight.w500
                          : FontWeight.w500,
                      fontFamily: 'SF Pro',
                    ),
                  ),
                ),
                if (hasDropdown)
                  const Icon(
                    Icons.keyboard_arrow_down,
                    color: Color(0xFFFFFFFF),
                    size: 20,
                  ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 50),
                width: 8,
                height: isSelected ? 32 : 0,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(4),
                    bottomRight: Radius.circular(4),
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
