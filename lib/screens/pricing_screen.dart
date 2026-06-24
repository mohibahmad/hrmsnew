import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/preferences_service.dart';
import '../services/firestore_service.dart';

class SubscriptionDialog extends StatefulWidget {
  final bool isPremium;
  const SubscriptionDialog({super.key, this.isPremium = false});

  @override
  State<SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends State<SubscriptionDialog> {
  final Color primaryBlue = const Color(0xFF0247C4);
  final Color leftPanelBlue = const Color(0xFF0247C4);
  final Color cardLightBlue = const Color(0xFFE5EEFC);
  int _selectedPlanIndex = 1;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: SizedBox(
          width: 960,
          height: 670,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 920,
                  height: 620,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 11,
                        child: Container(
                          decoration: const BoxDecoration(
                            image: DecorationImage(
                              image: AssetImage('assets/splashscreenbg.png'),
                              fit: BoxFit.cover,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 20,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const SizedBox(height: 20),
                              // --- App Icon (Premium HR App Icon) ---
                              SvgPicture.asset(
                                'assets/app_icon.svg',
                                height: 70,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(height: 36),

                              // --- Heading ---
                              Text(
                                'all_in_one_hr'.tr(),
                                style: TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              const SizedBox(height: 22),

                              // --- Features List (with solid play arrow triangles) ---
                              _buildFeatureItem('secure_staff_records'.tr()),
                              _buildFeatureItem('modern_hrms_experience'.tr()),
                              _buildFeatureItem('leave_shift_management'.tr()),
                              _buildFeatureItem('employee_asset_tracking'.tr()),
                              _buildFeatureItem(
                                'smart_workforce_management'.tr(),
                              ),
                              _buildFeatureItem(
                                'attendance_payroll_automation'.tr(),
                              ),
                            ],
                          ),
                        ),
                      ),

                      Expanded(
                        flex: 11,
                        child: Container(
                          color: Color(0xFFFFFFFF),
                          padding: const EdgeInsets.fromLTRB(48, 16, 48, 24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  'choose_your_plan'.tr(),
                                  style: TextStyle(
                                    color: primaryBlue,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ),
                              Text(
                                'select_subscription'.tr(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: primaryBlue,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  height: 1.3,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              const SizedBox(height: 24),

                              // --- Subscription Cards ---
                              _buildPlanCard(
                                index: 0,
                                title: 'monthly'.tr(),
                                price: '\$6.99',
                              ),
                              _buildPlanCard(
                                index: 1,
                                title: 'six_month'.tr(),
                                price: '\$46.99',
                                isPopular: true,
                              ),
                              _buildPlanCard(
                                index: 2,
                                title: 'yearly'.tr(),
                                price: '\$64.99',
                              ),
                              const SizedBox(height: 6),

                              // --- Continue Button ---
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: () async {
                                    // Current implementation is fake - just sets premium to true
                                    await PreferencesService.setPremium(true);
                                    try {
                                      await FirestoreService()
                                          .updateUserProfile({
                                            'isPremium': true,
                                          });
                                    } catch (_) {}
                                    if (context.mounted) {
                                      Navigator.of(context).pop(true);
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryBlue,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(50),
                                    ),
                                  ),
                                  child: Text(
                                    'continue'.tr(),
                                    style: TextStyle(
                                      color: Color(0xFFFFFFFF),
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),

                               GestureDetector(
                                onTap: () => Navigator.of(context).pop(false),
                                child: Text(
                                  'continue_free_plan'.tr(),
                                  style: TextStyle(
                                    color: Color(0xFF0242AE),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 28),

                              // --- Disclaimer Text ---
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'subscription_disclaimer'.tr(),
                                  textAlign: TextAlign.center,

                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 11,
                                    height: 1.3,
                                    fontWeight: FontWeight.w400,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // --- Footer Links ---
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildFooterLink(
                                    'privacy_policy'.tr(),
                                    onTap: () => launchUrl(
                                      Uri.parse(
                                        'https://docs.google.com/document/d/1ul6JAXXkdGKgfe9en6yF77u0EChQp32R/edit?rtpof=true&sd=true&tab=t.0',
                                      ),
                                    ),
                                  ),
                                  _buildFooterDivider(),
                                  _buildFooterLink(
                                    'restore'.tr(),
                                    onTap: () {
                                      // TODO: Implement restore purchases
                                    },
                                  ),
                                  _buildFooterDivider(),
                                  GestureDetector(
                                    onTap: () => launchUrl(
                                      Uri.parse(
                                        'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
                                      ),
                                    ),
                                    behavior: HitTestBehavior.opaque,
                                    child: _buildFooterLink(
                                      'terms_of_use'.tr(),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Positioned(
                top: -7,
                right: -10,
                child: Container(
                  decoration: BoxDecoration(
                    color: Color(0xFFFFFFFF),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF000000).withValues(alpha: 0.15),
                        blurRadius: 0.5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Color(0xFF0A44A9),
                      size: 22,
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          const ImageIcon(
            AssetImage('assets/left_arrow.png'),
            color: Color(0xFFFFFFFF),
            size: 18,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 18,
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required int index,
    required String title,
    required String price,
    bool isPopular = false,
  }) {
    bool isSelected = _selectedPlanIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPlanIndex = index;
        });
      },
      child: Container(
        height: 68,
        margin: const EdgeInsets.only(bottom: 17),
        decoration: BoxDecoration(
          color: cardLightBlue,
          borderRadius: BorderRadius.circular(6),
          border: isSelected ? Border.all(color: primaryBlue, width: 2) : null,
        ),
        child: Stack(
          children: [
            // Centered content (radio button, title, and right-aligned price)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: primaryBlue, width: 2),
                      ),
                      child: isSelected
                          ? Center(
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: primaryBlue,
                                ),
                              ),
                            )
                          : const SizedBox(),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      title,
                      style: TextStyle(
                        color: primaryBlue,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                    const Spacer(),
                    Text(
                      price,
                      style: TextStyle(
                        color: primaryBlue,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Popular badge
            if (isPopular)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: primaryBlue,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                    ),
                  ),
                  child: Text(
                    'popular'.tr(),
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
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

  Widget _buildFooterLink(String text, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        text,
        style: TextStyle(
          color: primaryBlue,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          fontFamily: 'SF Pro Display',
        ),
      ),
    );
  }

  Widget _buildFooterDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        '|',
        style: TextStyle(
          color: primaryBlue.withValues(alpha: 0.5),
          fontSize: 14,
        ),
      ),
    );
  }
}
