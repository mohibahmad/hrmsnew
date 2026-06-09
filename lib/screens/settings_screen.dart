import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;

  const SettingsScreen({
    super.key,
    required this.onLogout,
    required this.onProfileTap,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedLanguage = 'United State';

  void _showLanguageModal(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.05), // Very light transparent bg
              builder: (BuildContext context) {
                return StatefulBuilder(
                  builder: (context, setModalState) {
                    String langSearchQuery = '';
                    final allLanguages = ['United State', 'Chinese', 'French', 'German', 'Russian', 'Italian', 'UK'];
                    return StatefulBuilder(
                      builder: (context, setInnerState) {
                        final filteredLanguages = allLanguages.where((lang) {
                          return lang.toLowerCase().contains(langSearchQuery.toLowerCase());
                        }).toList();
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
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey.shade300, width: 1),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.1),
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
                                        color: Colors.black,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Container(
                                      height: 40,
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey.shade300),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                        child: TextField(
                                          onChanged: (val) {
                                            setInnerState(() {
                                              langSearchQuery = val;
                                            });
                                          },
                                          decoration: InputDecoration(
                                            hintText: 'Search language',
                                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                                            prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 18),
                                            suffixIcon: langSearchQuery.isNotEmpty
                                                ? GestureDetector(
                                                    onTap: () {
                                                      setInnerState(() {
                                                        langSearchQuery = '';
                                                      });
                                                    },
                                                    child: const Icon(Icons.close, size: 16, color: Colors.grey),
                                                  )
                                                : null,
                                            border: InputBorder.none,
                                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                          ),
                                        ),
                                    ),
                                    const SizedBox(height: 16),
                                    ...filteredLanguages.map((lang) {
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
                                                  color: Colors.black,
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
                  ),
                  _buildActionSettingItem(
                    'assets/permenantly_delete.svg',
                    'Permanently remove your profile and account data securely.',
                    'Delete Profile',
                  ),
                  _buildLanguageItem(),
                  _buildSimpleSettingItem('assets/share.svg', 'Share App'),
                  _buildSimpleSettingItem('assets/terms&condition.svg', 'Terms & Condition'),
                  _buildSimpleSettingItem('assets/privacy_policy.svg', 'Privacy Policy'),
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
        color: Colors.white,
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
                  color: Colors.black,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'SF Pro Display',
                  height: 1.0,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const Spacer(),
          SvgPicture.asset(
            'assets/notification_icon.svg',
            height: 24,
            width: 24,
            colorFilter: const ColorFilter.mode(
              Colors.black,
              BlendMode.srcIn,
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

  Widget _buildActionSettingItem(String iconPath, String text, String buttonText) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              iconPath,
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
              text,
              style: const TextStyle(
                fontSize: 18,
                color: Colors.black,
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
                height: 1.0,
                letterSpacing: 0,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              buttonText,
              style: const TextStyle(
                fontSize: 18,
                color: Colors.black,
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
                height: 1.0,
                letterSpacing: 0,
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/lanuguage.svg',
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
            ),
            const SizedBox(width: 16),
            const Text(
              'Language',
              style: TextStyle(
                fontSize: 18,
                color: Colors.black,
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
                color: Colors.black,
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
                height: 1.0,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_drop_down, color: Colors.black, size: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleSettingItem(String iconPath, String text, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              iconPath,
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
            ),
            const SizedBox(width: 16),
            Text(
              text,
              style: const TextStyle(
                fontSize: 18,
                color: Colors.black,
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
