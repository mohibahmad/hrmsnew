import 'package:flutter/material.dart' hide GestureDetector;
import '../../widgets/clickable_gesture_detector.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../services/preferences_service.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../riverpod_providers.dart';

class SubscriptionDialog extends ConsumerStatefulWidget {
  final bool isPremium;

  const SubscriptionDialog({super.key, this.isPremium = false});

  @override
  ConsumerState<SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends ConsumerState<SubscriptionDialog> {
  final Color primaryBlue = const Color(0xFF0B4DB7);
  final Color leftPanelBlue = const Color(0xFF0B4DB7);
  final Color cardLightBlue = const Color(0xFFDBE7F9);

  int _selectedPlanIndex = 1;
  bool _isSaving = false;

  late AuthService _authService;
  late FirestoreService _firestore;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: SizedBox(
          width: 920,
          height: 680,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 880,
                  height: 610,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(14),
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
                            horizontal: 33,
                            vertical: 20,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 10),

                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.asset(
                                  'assets/app_icon.png',
                                  width: 70,
                                  height: 70,
                                  fit: BoxFit.cover,
                                ),
                              ),

                              const SizedBox(height: 35),

                              Text(
                                'all_in_one_hr'.tr(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  height: 1.1,
                                ),
                              ),

                              Expanded(
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _buildFeatureItem(
                                      'secure_staff_records'.tr(),
                                    ),
                                    _buildFeatureItem(
                                      'modern_hrms_experience'.tr(),
                                    ),
                                    _buildFeatureItem(
                                      'leave_shift_management'.tr(),
                                    ),
                                    _buildFeatureItem(
                                      'employee_asset_tracking'.tr(),
                                    ),
                                    _buildFeatureItem(
                                      'smart_workforce_management'.tr(),
                                    ),
                                    _buildFeatureItem(
                                      'attendance_payroll_automation'.tr(),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      Expanded(
                        flex: 11,
                        child: Container(
                          color: const Color(0xFFFFFFFF),
                          width: double.infinity,
                          height: double.infinity,
                          padding: const EdgeInsets.fromLTRB(33, 20, 33, 20),
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text(
                                    'choose_your_plan'.tr(),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: primaryBlue,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
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
                                  ),
                                ),

                                const SizedBox(height: 14),

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

                                const SizedBox(height: 8),

                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: ElevatedButton(
                                    onPressed: _isSaving
                                        ? null
                                        : () async {
                                            setState(() {
                                              _isSaving = true;
                                            });

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
                                                setState(() {
                                                  _isSaving = false;
                                                });
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
                                            width: 26,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(
                                            'continue'.tr(),
                                            style: const TextStyle(
                                              color: Color(0xFFFFFFFF),
                                              fontSize: 19,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                ),

                                const SizedBox(height: 10),

                                GestureDetector(
                                  onTap: () {
                                    Navigator.of(context).pop(false);
                                  },
                                  child: Text(
                                    'continue_free_plan'.tr(),
                                    style: TextStyle(
                                      color: primaryBlue,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 30),

                                Text(
                                  'subscription_disclaimer'.tr(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFF222222),
                                    fontSize: 11,
                                    height: 1.3,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),

                                const SizedBox(height: 30),

                                FractionallySizedBox(
                                  widthFactor: 1.1,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      _buildFooterLink(
                                        'privacy_policy'.tr(),
                                        onTap: () {
                                          launchUrl(
                                            Uri.parse(
                                              'https://docs.google.com/document/d/1ul6JAXXkdGKgfe9en6yF77u0EChQp32R/edit?rtpof=true&sd=true&tab=t.0',
                                            ),
                                          );
                                        },
                                      ),

                                      _buildFooterDivider(),

                                      _buildFooterLink(
                                        'restore'.tr(),
                                        onTap: () {},
                                      ),

                                      _buildFooterDivider(),

                                      _buildFooterLink(
                                        'terms_of_use'.tr(),
                                        onTap: () {
                                          launchUrl(
                                            Uri.parse(
                                              'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
                                            ),
                                          );
                                        },
                                      ),
                                    ],
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
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
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 20,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
              height: 1.15,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlanCard({
    required int index,
    required String title,
    required String price,
    bool isPopular = false,
    String badgeText = 'popular',
  }) {
    final bool isSelected = _selectedPlanIndex == index;

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

                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: primaryBlue,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: Text(
                  price,
                  style: TextStyle(
                    color: primaryBlue,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
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
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
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
        textAlign: TextAlign.center,
        style: TextStyle(
          color: primaryBlue,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildFooterDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(width: 1, height: 13, color: primaryBlue),
    );
  }
}
