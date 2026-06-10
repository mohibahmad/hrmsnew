import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;
  final bool isGuest;
  final VoidCallback? onNotificationTap;

  const SettingsScreen({
    super.key,
    required this.onLogout,
    required this.onProfileTap,
    this.isGuest = false,
    this.onNotificationTap,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedLanguage = 'United State';

  Future<void> _resetPassword(BuildContext context) async {
    final email = AuthService().currentUser?.email;
    if (email != null) {
      try {
        await AuthService().resetPassword(email);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Password reset email sent to $email')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to send reset email: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0xFF000000).withValues(alpha: 0.4),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.warning_rounded,
                    color: Color(0xFFEF4444),
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Delete Account?',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF000000),
                  fontFamily: 'SF Pro Display',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Are you sure you want to permanently delete your profile and all data? This action cannot be undone.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w400,
                  fontFamily: 'SF Pro Display',
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, false),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, true),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Text(
                          'Delete Account',
                          style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm != true) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirestoreService().deleteUserData();
        await user.delete();
        await AuthService().signOut();

        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Account permanently deleted.')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        String message = 'Failed to delete account. $e';
        if (e is FirebaseAuthException && e.code == 'requires-recent-login') {
          message = 'Please sign out and sign back in to delete your account for security reasons.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }

  void _showLanguageModal(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Color(0xFF000000).withValues(alpha: 0.05), // Very light transparent bg
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final allLanguages = ['United State', 'Chinese', 'French', 'German', 'Russian', 'Italian', 'UK'];
            return Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 60.0, top: 40.0),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 320,
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF000000).withValues(alpha: 0.1),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        )
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Select Language',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF000000),
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...allLanguages.map((lang) {
                          final isSel = _selectedLanguage == lang;
                          return InkWell(
                            onTap: () {
                              setModalState(() {
                                _selectedLanguage = lang;
                              });
                              setState(() {});
                              Future.delayed(const Duration(milliseconds: 150), () {
                                if (context.mounted) {
                                  Navigator.pop(context);
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: isSel ? const Color(0xFFF1F3F5) : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    lang,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF000000),
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                  if (isSel)
                                    const Icon(Icons.check, color: Color(0xFF0247C4), size: 16),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Column(
                children: [
                  _buildActionSettingItem(
                    'assets/changepassword.svg',
                    'Change your password to keep your account secure.',
                    'Reset Password',
                    onTap: widget.isGuest ? null : () => _resetPassword(context),
                    disabled: widget.isGuest,
                  ),
                  _buildActionSettingItem(
                    'assets/permenantly_delete.svg',
                    'Permanently remove your profile and account data securely.',
                    'Delete Profile',
                    onTap: widget.isGuest ? null : () => _deleteAccount(context),
                    disabled: widget.isGuest,
                  ),
                  _buildLanguageItem(),
                  _buildSimpleSettingItem('assets/share.svg', 'Share App'),
                  _buildSimpleSettingItem(
                    'assets/terms&condition.svg',
                    'Terms & Condition',
                    onTap: () => launchUrl(Uri.parse('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/')),
                  ),
                  _buildSimpleSettingItem('assets/privacy_policy.svg', 'Privacy Policy'),
                  if (!widget.isGuest)
                    _buildSimpleSettingItem(
                      'assets/signout.svg',
                      'Sign out',
                      onTap: widget.onLogout,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= CONTENT BUILDERS =================

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(
          bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1),
        ),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text(
                'Setting',
                style: TextStyle(
                  color: Color(0xFF000000),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'SF Pro Display',
                  height: 1.0,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: widget.onNotificationTap,
            child: SvgPicture.asset(
              'assets/notification_icon.svg',
              height: 24,
              width: 24,
              colorFilter: const ColorFilter.mode(
                Color(0xFF000000),
                BlendMode.srcIn,
              ),
            ),
          ),
          const SizedBox(width: 20),
          GestureDetector(
            onTap: widget.onProfileTap,
            child: CircleAvatar(
              radius: 19,
              backgroundImage: const AssetImage('assets/profileimage.png'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionSettingItem(String iconPath, String text, String buttonText, {VoidCallback? onTap, bool disabled = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              iconPath,
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(
                disabled ? const Color(0xFFAAAAAA) : const Color(0xFF000000),
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
              text,
              style: TextStyle(
                fontSize: 18,
                color: disabled ? const Color(0xFFAAAAAA) : const Color(0xFF000000),
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
                height: 1.0,
                letterSpacing: 0,
              ),
            ),
          ),
          GestureDetector(
            onTap: disabled ? null : onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: disabled ? const Color(0xFFE0E0E0) : const Color(0xFFF1F3F5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                buttonText,
                style: TextStyle(
                  fontSize: 18,
                  color: disabled ? const Color(0xFFAAAAAA) : const Color(0xFF000000),
                  fontWeight: FontWeight.w500,
                  fontFamily: 'SF Pro Display',
                  height: 1.0,
                  letterSpacing: 0,
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildLanguageItem() {
    return GestureDetector(
      onTap: () => _showLanguageModal(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/lanuguage.svg',
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(Color(0xFF000000), BlendMode.srcIn),
            ),
            const SizedBox(width: 16),
            const Text(
              'Language',
              style: TextStyle(
                fontSize: 18,
                color: Color(0xFF000000),
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
                height: 1.0,
                letterSpacing: 0,
              ),
            ),
            const Spacer(),
            Text(
              _selectedLanguage,
              style: const TextStyle(
                fontSize: 18,
                color: Color(0xFF000000),
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
                height: 1.0,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_drop_down, color: Color(0xFF000000), size: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleSettingItem(String iconPath, String text, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              iconPath,
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(Color(0xFF000000), BlendMode.srcIn),
            ),
            const SizedBox(width: 16),
            Text(
              text,
              style: const TextStyle(
                fontSize: 18,
                color: Color(0xFF000000),
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
                height: 1.0,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
