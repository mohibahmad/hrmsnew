import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter/services.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/preferences_service.dart';
import '../utils/snackbar_utils.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/notification_bell.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ProfileInlineHeader — used inside HomeScreen's profile view
// ─────────────────────────────────────────────────────────────────────────────

class ProfileInlineHeader extends StatelessWidget {
  final VoidCallback onLogout;
  final VoidCallback onNotificationTap;

  const ProfileInlineHeader({
    super.key,
    required this.onLogout,
    required this.onNotificationTap,
  });

  @override
  Widget build(BuildContext context) {

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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'my_info'.tr(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF000000),
              fontFamily: 'SF Pro Display',
            ),
          ),
          const Spacer(),
          NotificationBell(onTap: onNotificationTap),
          const SizedBox(width: 20),
          const UserAvatar(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ProfileBody
// ─────────────────────────────────────────────────────────────────────────────

class ProfileBody extends StatefulWidget {
  final bool isActive;
  const ProfileBody({super.key, this.isActive = true});

  @override
  State<ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<ProfileBody> {
  late final TextEditingController _businessNameController;
  late final TextEditingController _companyIdController;
  late final TextEditingController _emailController;
  late final TextEditingController _currencyController;
  late final TextEditingController _contact1Controller;
  late final TextEditingController _contact2Controller;
  late final TextEditingController _addressController;
  bool _isLoading = true;
  bool _isEditing = false;
  String? _profilePicUrl;

  @override
  void initState() {
    super.initState();
    _businessNameController = TextEditingController();
    _companyIdController = TextEditingController();
    _emailController = TextEditingController(
      text: AuthService().currentUser?.email ?? '',
    );
    _currencyController = TextEditingController(text: 'USD');
    _contact1Controller = TextEditingController();
    _contact2Controller = TextEditingController();
    _addressController = TextEditingController();
    _loadProfile();
  }

  @override
  void didUpdateWidget(ProfileBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive && oldWidget.isActive) {
      // Screen became inactive, clear unsaved changes
      if (mounted) {
        setState(() {
          _isEditing = false;
          _newProfileImageBytes = null;
          _newProfileImagePath = null;
          _loadProfile();
        });
      }
    }
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _companyIdController.dispose();
    _emailController.dispose();
    _currencyController.dispose();
    _contact1Controller.dispose();
    _contact2Controller.dispose();
    _addressController.dispose();
    super.dispose();
  }

  /// In-memory guest profile cache (persists during session)
  static Map<String, String>? _guestProfileCache;

  Future<void> _loadProfile() async {
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (!isGuest) {
      _guestProfileCache = null;
    }
    if (isGuest) {
      if (mounted) {
        setState(() {
          _businessNameController.text =
              _guestProfileCache?['businessName'] ?? 'Guest Company Ltd.';
          _companyIdController.text =
              _guestProfileCache?['companyId'] ?? '';
          _emailController.text =
              _guestProfileCache?['email'] ?? 'guest@example.com';
          _currencyController.text = _guestProfileCache?['currency'] ?? 'USD';
          _contact1Controller.text =
              _guestProfileCache?['contact1'] ?? '+1 415-555-0198';
          _contact2Controller.text = _guestProfileCache?['contact2'] ?? '+1 415-555-0299';
          _addressController.text =
              _guestProfileCache?['address'] ?? '123 Demo Street, Test City';
          _profilePicUrl = AuthService.profilePicNotifier.value;
          _isLoading = false;
        });
      }
      return;
    }

    final profile = await FirestoreService().getUserProfile();
    if (profile != null && mounted) {
      setState(() {
        _businessNameController.text = profile['businessName'] ?? '';
        _companyIdController.text = profile['companyId'] ?? '';
        _emailController.text =
            profile['email'] ?? AuthService().currentUser?.email ?? '';
        _currencyController.text = profile['currency'] ?? 'USD';
        _contact1Controller.text = profile['contact1'] ?? '';
        _contact2Controller.text = profile['contact2'] ?? '';
        _addressController.text = profile['address'] ?? '';
        _profilePicUrl = profile['profilePic'];
        AuthService.profilePicNotifier.value = _profilePicUrl;
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() {
        _profilePicUrl = AuthService.profilePicNotifier.value;
        _isLoading = false;
      });
    }
  }

  Uint8List? _newProfileImageBytes;
  String? _newProfileImagePath;

  Future<void> _pickProfilePic() async {
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (isGuest) {
      FlashySnackBar.show(
        context,
        message: 'guest_action_not_allowed'.tr(),
        isError: true,
      );
      return;
    }
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result == null || !mounted) return;

      final file = result.files.single;
      if (file.bytes != null && file.bytes!.length > 10 * 1024 * 1024) {
        FlashySnackBar.show(
          context,
          message: 'file_too_large'.tr(namedArgs: {'size': '10MB'}),
          isError: true,
        );
        return;
      }

      setState(() {
        _newProfileImageBytes = file.bytes;
        _newProfileImagePath = file.path;
      });
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'error_selecting_image'.tr(
            namedArgs: {'error': e.toString()},
          ),
          isError: true,
        );
      }
    }
  }

  Future<bool> _saveProfile() async {
    if (_businessNameController.text.trim().isEmpty) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'please_enter_business_name'.tr(),
          isError: true,
        );
      }
      return false;
    }

    if (_companyIdController.text.trim().isEmpty) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'please_enter_company_number'.tr(),
          isError: true,
        );
      }
      return false;
    }

    if (_contact1Controller.text.trim().isEmpty) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'please_enter_contact_number'.tr(),
          isError: true,
        );
      }
      return false;
    }

    if (_addressController.text.trim().isEmpty) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'please_enter_address'.tr(),
          isError: true,
        );
      }
      return false;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final isGuest = AuthService().currentUser?.isAnonymous ?? false;
      String? downloadUrl;

      if (!isGuest) {
        if (_newProfileImageBytes != null || _newProfileImagePath != null) {
          final fileName =
              'profile_${AuthService().currentUser?.uid ?? 'user'}_${DateTime.now().millisecondsSinceEpoch}.png';
          final ref = FirebaseStorage.instance
              .ref()
              .child('profile_pics')
              .child(fileName);

          try {
            if (_newProfileImageBytes != null) {
              await ref.putData(_newProfileImageBytes!);
            } else if (_newProfileImagePath != null) {
              await ref.putFile(File(_newProfileImagePath!));
            }
            downloadUrl = await ref.getDownloadURL();
          } catch (e) {
            if (mounted) {
              FlashySnackBar.show(
                context,
                message: 'file_upload_failed'.tr(namedArgs: {'file': fileName}),
                isError: true,
              );
            }
            setState(() => _isLoading = false);
            return false;
          }
        }

        if (downloadUrl != null) {
          await AuthService().currentUser?.updatePhotoURL(downloadUrl);
          _profilePicUrl = downloadUrl;
          AuthService.profilePicNotifier.value = downloadUrl;
          await PreferencesService.setProfilePicUrl(downloadUrl);
          _newProfileImageBytes = null;
          _newProfileImagePath = null;
        }

        await FirestoreService().updateUserProfile({
          'businessName': _businessNameController.text,
          'companyId': _companyIdController.text,
          'email': _emailController.text,
          'currency': _currencyController.text,
          'contact1': _contact1Controller.text,
          'contact2': _contact2Controller.text,
          'address': _addressController.text,
          if (downloadUrl != null) 'profilePic': downloadUrl,
        });
      } else {
        // Guest user: save temporary preview image link to notifier in-memory.
        if (_newProfileImageBytes != null) {
          final base64String = base64Encode(_newProfileImageBytes!);
          downloadUrl = 'data:image/png;base64,$base64String';
        } else if (_newProfileImagePath != null) {
          downloadUrl = _newProfileImagePath;
        }

        if (downloadUrl != null) {
          _profilePicUrl = downloadUrl;
          AuthService.profilePicNotifier.value = downloadUrl;
          _newProfileImageBytes = null;
          _newProfileImagePath = null;
        }

        // Cache guest profile data in memory for session persistence
        _guestProfileCache = {
          'businessName': _businessNameController.text,
          'companyId': _companyIdController.text,
          'email': _emailController.text,
          'currency': _currencyController.text,
          'contact1': _contact1Controller.text,
          'contact2': _contact2Controller.text,
          'address': _addressController.text,
        };
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        FlashySnackBar.show(context, message: 'profile_saved'.tr());
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        FlashySnackBar.show(
          context,
          message: 'error_saving_profile'.tr(
            namedArgs: {'error': e.toString()},
          ),
          isError: true,
        );
      }
      return false;
    }
  }

  void _showPreviewDialog() {
    showDialog(
      context: context,
      barrierColor: Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (context) => ProfilePreviewDialog(
        businessName: _businessNameController.text,
        companyId: _companyIdController.text,
        email: _emailController.text,
        currency: _currencyController.text,
        contact1: _contact1Controller.text,
        contact2: _contact2Controller.text,
        address: _addressController.text,
        onSave: _saveProfile,
        onEdit: () {
          Navigator.of(context).pop();
          setState(() => _isEditing = true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildProfileIcon(),
            if (_isEditing)
              ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                        final saved = await _saveProfile();
                        if (saved && mounted) {
                          setState(() => _isEditing = false);
                          _showPreviewDialog();
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF155ED5),
                  foregroundColor: const Color(0xFFFFFFFF),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'save'.tr(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
              )
            else
              InkWell(
                onTap: () => setState(() => _isEditing = true),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FE),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SvgPicture.asset(
                    'assets/edit_icon.svg',
                    width: 22,
                    height: 22,
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF155ED5),
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 30),
        Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F5F7),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              _buildFormRow(
                _buildInputField(
                  'business_name'.tr(),
                  _businessNameController,
                  readOnly: !_isEditing,
                ),
                _buildInputField(
                  'company_id_no'.tr(),
                  _companyIdController,
                  readOnly: !_isEditing,
                ),
              ),
              const SizedBox(height: 24),
              _buildFormRow(
                _buildInputField(
                  'company_email'.tr(),
                  _emailController,
                  readOnly: true,
                ),
                _buildCurrencyField(_isEditing),
              ),
              const SizedBox(height: 24),
              _buildFormRow(
                _buildInputField(
                  'contact_number'.tr(),
                  _contact1Controller,
                  readOnly: !_isEditing,
                ),
                _buildInputField(
                  'secondary_contact'.tr(),
                  _contact2Controller,
                  readOnly: !_isEditing,
                ),
              ),
              const SizedBox(height: 24),
              _buildFormRow(
                _buildInputField(
                  'address'.tr(),
                  _addressController,
                  maxLines: 2,
                  readOnly: !_isEditing,
                ),
                const SizedBox(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileIcon() {
    final hasNewBytes = _newProfileImageBytes != null;
    final hasNewPath = _newProfileImagePath != null;
    final hasCustomPic = _profilePicUrl != null && _profilePicUrl!.isNotEmpty;

    Widget _buildLoadingIndicator() {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    Widget _buildFallbackIcon() {
      return Icon(Icons.person, size: 40, color: Colors.grey.shade400);
    }

    Widget childWidget;
    if (hasNewBytes) {
      childWidget = Image.memory(
        _newProfileImageBytes!,
        width: 90,
        height: 90,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackIcon(),
      );
    } else if (hasNewPath) {
      childWidget = Image.file(
        File(_newProfileImagePath!),
        width: 90,
        height: 90,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackIcon(),
      );
    } else if (hasCustomPic) {
      if (_profilePicUrl!.startsWith('http')) {
        childWidget = CachedNetworkImage(
          imageUrl: _profilePicUrl!,
          width: 90,
          height: 90,
          fit: BoxFit.cover,
          placeholder: (_, __) => _buildLoadingIndicator(),
          errorWidget: (_, __, ___) => _buildFallbackIcon(),
        );
      } else if (_profilePicUrl!.startsWith('data:image')) {
        final String base64Content = _profilePicUrl!.substring(
          _profilePicUrl!.indexOf(',') + 1,
        );
        childWidget = Image.memory(
          base64Decode(base64Content),
          width: 90,
          height: 90,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackIcon(),
        );
      } else {
        childWidget = Image.file(
          File(_profilePicUrl!),
          width: 90,
          height: 90,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackIcon(),
        );
      }
    } else {
      childWidget = Image.asset(
        'assets/profile_placeholder.png',
        width: 90,
        height: 90,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackIcon(),
      );
    }

    return GestureDetector(
      onTap: _isEditing ? _pickProfilePic : null,
      child: Stack(
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: Center(child: childWidget),
          ),
          if (_isEditing)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFF155ED5),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: SvgPicture.asset(
                    'assets/edit_pencil_profile.svg',
                    colorFilter: const ColorFilter.mode(
                      Color(0xFFFFFFFF),
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFormRow(Widget leftChild, Widget rightChild) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: leftChild),
        const SizedBox(width: 40),
        Expanded(child: rightChild),
      ],
    );
  }

  Widget _buildInputField(
    String label,
    TextEditingController controller, {
    bool isDropdown = false,
    int maxLines = 1,
    bool readOnly = false,
  }) {
    final bool isEmailField = label == 'company_email'.tr();
    final bool isCompanyId = label == 'company_id_no'.tr();
    final bool isBusinessName = label == 'business_name'.tr();
    final bool isContact =
        label.toLowerCase().contains('contact') ||
        label.toLowerCase().contains('phone');
    final bool isAddress = label.toLowerCase().contains('address');
    final Color bgColor = readOnly
        ? const Color(0xFFEEEFF2)
        : const Color(0xFFFFFFFF);
    final Color textColor = readOnly
        ? const Color(0xFF9CA3AF)
        : const Color(0xFF000000);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: Colors.black,
                fontFamily: 'SF Pro Display',
              ),
            ),
            if (isEmailField) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.lock_outline,
                size: 13,
                color: Color(0xFF9CA3AF),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
            border: readOnly
                ? Border.all(color: const Color(0xFFE5E7EB))
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: maxLines,
                  readOnly: readOnly,
                  inputFormatters: isCompanyId || isContact || isBusinessName || isAddress
                      ? [
                          LengthLimitingTextInputFormatter(isBusinessName ? 30 : isAddress ? 100 : 15),
                          if (isContact)
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9+\-\s()]'),
                            ),
                          if (isCompanyId)
                            FilteringTextInputFormatter.digitsOnly,
                        ]
                      : null,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    hintText: isEmailField
                        ? 'example@company.com'
                        : isCompanyId
                            ? 'e.g. 12345678'
                            : isBusinessName
                                ? 'e.g. ABC Corporation'
                                : isContact
                                    ? '+1 415-555-0198'
                                    : isAddress
                                        ? 'e.g. 123 Main St, City'
                                        : '',
                    hintStyle: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 15,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    color: textColor,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ),
              if (isDropdown)
                const Icon(Icons.arrow_drop_down, color: Colors.grey),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCurrencyField(bool isEditing) {
    if (!isEditing) {
      return _buildInputField(
        'currency'.tr(),
        _currencyController,
        readOnly: true,
      );
    }

    final currencies = ['USD', 'EUR', 'GBP', 'JPY', 'INR', 'RUB', 'BRL', 'SAR'];
    String localize(String val) {
      switch (val) {
        case 'USD':
          return 'usd_desc'.tr();
        case 'EUR':
          return 'eur_desc'.tr();
        case 'GBP':
          return 'gbp_desc'.tr();
        case 'JPY':
          return 'jpy_desc'.tr();
        case 'INR':
          return 'inr_desc'.tr();
        case 'RUB':
          return 'rub_desc'.tr();
        case 'BRL':
          return 'brl_desc'.tr();
        case 'SAR':
          return 'sar_desc'.tr();
        default:
          return val;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'currency'.tr(),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: Colors.black,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currencies.contains(_currencyController.text)
                  ? _currencyController.text
                  : 'USD',
              isExpanded: true,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black,
                fontFamily: 'SF Pro Display',
              ),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _currencyController.text = newValue;
                  });
                }
              },
              items: currencies.map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(localize(value), maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ProfilePreviewDialog
// ─────────────────────────────────────────────────────────────────────────────

class ProfilePreviewDialog extends StatelessWidget {
  final String businessName;
  final String companyId;
  final String email;
  final String currency;
  final String contact1;
  final String contact2;
  final String address;
  final VoidCallback? onSave;
  final VoidCallback? onEdit;

  const ProfilePreviewDialog({
    super.key,
    required this.businessName,
    required this.companyId,
    required this.email,
    required this.currency,
    required this.contact1,
    required this.contact2,
    required this.address,
    this.onSave,
    this.onEdit,
  });

  static const Color primaryBlue = Color(0xFF0B51C1);
  static const Color lightBlueBg = Color(0xFFE8F0FE);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Container(
          width: 480,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Color(0xFF000000).withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                color: const Color(0xFF004FDE),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      'profile_preview'.tr(),
                      style: TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 20,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Color(0xFFFFFFFF),
                            size: 28,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: IconButton(
                          icon: SvgPicture.asset(
                            'assets/edit_icon.svg',
                            height: 20,
                            width: 20,
                            colorFilter: const ColorFilter.mode(
                              Color(0xFFFFFFFF),
                              BlendMode.srcIn,
                            ),
                          ),
                          onPressed: () {
                            onEdit?.call();
                          },
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Blue banner with logo and company name
              Container(
                color: const Color(0xFF0247C4),
                padding: const EdgeInsets.fromLTRB(24, 15, 24, 15),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Color(0xFFFFFFFF),
                        shape: BoxShape.circle,
                        border: Border.all(color: Color(0xFFFFFFFF), width: 2),
                      ),
                      child: const ClipOval(child: UserAvatar(radius: 70)),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Text(
                        businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFFFFFF),
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Body Section (Cards List)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
                child: Column(
                  children: [
                    // Row 1: Business Name + Company ID
                    Row(
                      children: [
                        Expanded(
                          child: _buildPreviewCard(
                            'business_name'.tr(),
                            businessName,
                            'assets/preview_profile.svg',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildPreviewCard(
                            'company_id_no'.tr(),
                            companyId,
                            'assets/company_id.svg',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Row 2: Company E-mail + Currency
                    Row(
                      children: [
                        Expanded(
                          child: _buildPreviewCard(
                            'company_email'.tr(),
                            email,
                            'assets/company_email.svg',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildPreviewCard(
                            'currency'.tr(),
                            currency,
                            'assets/currency_preview.svg',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Row 3: Contact No + Address
                    Row(
                      children: [
                        Expanded(
                          child: _buildPreviewCard(
                            'contact_no'.tr(),
                            contact1,
                            'assets/phone_preview.svg',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildPreviewCard(
                            'address'.tr(),
                            address,
                            'assets/location_preview.svg',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard(String label, String value, String svgPath) {
    return Container(
      height: 70,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: lightBlueBg,
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.all(8),
            child: SvgPicture.asset(
              svgPath,
              colorFilter: const ColorFilter.mode(primaryBlue, BlendMode.srcIn),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (label.isNotEmpty) ...[
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.0,
                      letterSpacing: 0,
                      color: Color(0xFF000000),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.0,
                    letterSpacing: 0,
                    color: Color(0xFF000000),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
