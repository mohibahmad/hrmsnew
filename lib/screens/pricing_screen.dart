import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/preferences_service.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import 'package:provider/provider.dart';

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
  bool _isSaving = false;
  late AuthService _authService;
  late FirestoreService _firestore;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestore = Provider.of<FirestoreService>(context, listen: false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: SizedBox(
          width: 960,
          height: 680,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 920,
                  height: 610,
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

                              SvgPicture.asset(
                                'assets/app_icon.png',
                                height: 70,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(height: 36),

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
                          width: double.infinity,
                          height: double.infinity,
                          padding: const EdgeInsets.fromLTRB(48, 16, 48, 18),
                          child: SingleChildScrollView(
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
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
                                const SizedBox(height: 20),

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
                                  badgeText: 'popular',
                                ),
                                _buildPlanCard(
                                  index: 2,
                                  title: 'yearly'.tr(),
                                  price: '\$64.99',
                                  isPopular: true,
                                  badgeText: 'hottest',
                                ),
                                const SizedBox(height: 6),

                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton(                                          onPressed: _isSaving
                                        ? null
                                        : () async {
                                            setState(() => _isSaving = true);
                                            try {
                                              await PreferencesService.setPremium(
                                                true,
                                              );
                                              final isGuest =
                                                  _authService
                                                      .currentUser
                                                      ?.isAnonymous ??
                                                  false;
                                              if (!isGuest) {
                                                try {
                                                  await _firestore
                                                      .updateUserProfile({
                                                        'isPremium': true,
                                                      });
                                                } catch (_) {}
                                              }
                                            } finally {
                                              if (mounted) {
                                                setState(
                                                  () => _isSaving = false,
                                                );
                                              }
                                            }
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
                                    child: _isSaving
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(
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
                                const SizedBox(height: 16),

                                Padding(
                                  padding: EdgeInsets.zero,
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
                            
                                const SizedBox(height: 36),

                                SizedBox(
                                  width: double.infinity,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 10),
                                    child: Row(
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
                                          onTap: () {},
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
                                  ),
                                ),
                                ],
                              ),
                            ),
                          ),
                        ),

                    ],
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
    String badgeText = 'popular',
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
                    badgeText.tr(),
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
          fontSize: 11,
          fontWeight: FontWeight.w500,
          fontFamily: 'SF Pro Display',
        ),
      ),
    );
  }

  Widget _buildFooterDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '|',
        style: TextStyle(
          color: primaryBlue.withValues(alpha: 0.5),
          fontSize: 11,
        ),
      ),
    );
  }
}
