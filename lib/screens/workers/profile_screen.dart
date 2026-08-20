import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../utils/ui_helpers.dart';
import '../../utils/helpers.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as img;

import '../../riverpod_providers.dart';
import '../../services/auth_service.dart';
import '../../services/error_reporter.dart';
import '../../services/firestore_service.dart';
import '../../services/preferences_service.dart';
import '../../services/upload_service.dart';
import '../../utils/utils.dart';
import '../../widgets/clickable_gesture_detector.dart';
import '../../widgets/notification_bell.dart';

const int _maxProfileImageBytes = 10 * 1024 * 1024;
const int _maxCompanyStampBytes = 5 * 1024 * 1024;
const int _maxStampSide = 700;

const _kFontFamily = 'SF Pro Display';
const _kWhite = AppColors.white;
const _kBlack = AppColors.black;
const _kPrimaryBlue = AppColors.primaryBlue;
const _kDarkBlue = AppColors.primaryBlueDark;
const _kActionBlue = AppColors.linkBlue;
const _kGreyText = AppColors.textMuted;
const _kGrey6B = AppColors.textDarkGrey;
const _kBorderLight = AppColors.borderSubtle;
const _kBgGrey = AppColors.disabledBg;
const _kFormBg = AppColors.formBg;
const _kLightBlueBg = AppColors.primaryBlueLight;
const _kStampBorder = AppColors.stampBorder;
const _kRedDelete = AppColors.dangerRed;

const _kInputHintStyle = TextStyle(
  color: _kGreyText,
  fontSize: 15,
  fontFamily: _kFontFamily,
);

const _kLabelStyle = TextStyle(
  fontWeight: FontWeight.w600,
  fontSize: 15,
  color: Colors.black,
  fontFamily: _kFontFamily,
);

Uint8List? _compressImageBytes(Uint8List rawBytes) {
  try {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) return null;
    return Uint8List.fromList(
      img.encodeJpg(img.copyResize(decoded, width: 500), quality: 80),
    );
  } catch (_) {
    return null;
  }
}

Uint8List? _compressStampBytes(Uint8List rawBytes) {
  try {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) return null;

    final longestSide = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    final resized = longestSide <= _maxStampSide
        ? decoded
        : img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? _maxStampSide : null,
            height: decoded.height > decoded.width ? _maxStampSide : null,
          );

    final isPng = _companyStampFormat(rawBytes) == 'png';
    return Uint8List.fromList(
      isPng ? img.encodePng(resized) : img.encodeJpg(resized, quality: 85),
    );
  } catch (_) {
    return null;
  }
}

String? _companyStampFormat(Uint8List bytes) {
  if (bytes.lengthInBytes >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return 'png';
  }
  if (bytes.lengthInBytes >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'jpg';
  }
  return null;
}

Uint8List? _decodeProfileDataImage(String value) {
  try {
    final commaIndex = value.indexOf(',');
    if (commaIndex < 0 || commaIndex == value.length - 1) return null;
    return base64Decode(value.substring(commaIndex + 1));
  } catch (_) {
    return null;
  }
}

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
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: _kWhite,
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
          const SizedBox(width: 3),
          Text(
            'my_info'.tr(),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: _kBlack,
              fontFamily: _kFontFamily,
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

class ProfileBody extends ConsumerStatefulWidget {
  final bool isActive;

  const ProfileBody({super.key, this.isActive = true});

  @override
  ConsumerState<ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends ConsumerState<ProfileBody> {
  late final TextEditingController _businessNameController;
  late final TextEditingController _companyIdController;
  late final TextEditingController _emailController;
  late final TextEditingController _currencyController;
  late final TextEditingController _contact1Controller;
  late final TextEditingController _contact2Controller;
  late final TextEditingController _addressController;

  late AuthService _authService;
  late FirestoreService _firestore;

  bool _isLoading = true;
  bool _isEditing = false;
  bool _initialized = false;
  int _profileLoadToken = 0;

  StreamSubscription<Map<String, dynamic>?>? _profileSub;

  String? _profilePicUrl;
  String? _companyStampUrl;
  Uint8List? _newProfileImageBytes;
  String? _newProfileImagePath;
  Uint8List? _newCompanyStampBytes;
  bool _clearCompanyStamp = false;

  bool _sessionTimeoutEnabled = true;
  int _sessionTimeoutDuration = 3;

  bool get _isGuest => _authService.currentUser?.isAnonymous ?? false;

  @override
  void initState() {
    super.initState();
    _businessNameController = TextEditingController();
    _companyIdController = TextEditingController();
    _emailController = TextEditingController();
    _currencyController = TextEditingController(text: 'USD');
    _contact1Controller = TextEditingController();
    _contact2Controller = TextEditingController();
    _addressController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);

    if (_initialized && !_isGuest) return;
    _initialized = true;

    final sessionSettings = ref.read(sessionTimeoutSettingsProvider);
    _sessionTimeoutEnabled = sessionSettings.enabled;
    _sessionTimeoutDuration = sessionSettings.durationMinutes;

    _loadProfile();

    if (!_isGuest) {
      _profileSub = _firestore.userProfileStream.listen(
        (profile) {
          if (!mounted || _isEditing) return;
          _applyAuthenticatedProfile(profile);
        },
        onError: (Object error, StackTrace stackTrace) {
          ErrorReporter.report(error, stackTrace, context: 'ProfileStream');
        },
      );
    }
  }

  @override
  void didUpdateWidget(ProfileBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive && oldWidget.isActive) {
      setState(() {
        _isEditing = false;
        _newProfileImageBytes = null;
        _newProfileImagePath = null;
        _newCompanyStampBytes = null;
        _clearCompanyStamp = false;
      });
      _loadProfile();
    }
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _businessNameController.dispose();
    _companyIdController.dispose();
    _emailController.dispose();
    _currencyController.dispose();
    _contact1Controller.dispose();
    _contact2Controller.dispose();
    _addressController.dispose();
    super.dispose();
  }

  String _profileText(dynamic value, {String fallback = ''}) =>
      value?.toString() ?? fallback;

  String? _profileImageText(dynamic value) {
    final text = _profileText(value).trim();
    return text.isEmpty ? null : text;
  }

  void _applyAuthenticatedProfile(Map<String, dynamic>? profile) {
    if (!mounted) return;

    if (profile == null) {
      setState(() {
        _profilePicUrl = null;
        _companyStampUrl = null;
        AuthService.profilePicNotifier.value = null;
        AuthService.companyStampNotifier.value = null;
        _isLoading = false;
      });
      return;
    }

    final normalizedCurrency = CurrencyUtils.normalize(profile['currency']);
    final profileImage = _profileImageText(profile['profilePic']);
    final companyStamp = _profileImageText(profile['companyStampUrl']);

    setState(() {
      _businessNameController.text = _profileText(profile['businessName']);
      _companyIdController.text = _profileText(
        profile['companyId'],
      ).toUpperCase();
      _emailController.text = _profileText(
        profile['email'],
        fallback: _authService.currentUser?.email ?? '',
      );
      _currencyController.text = normalizedCurrency;
      _contact1Controller.text = _profileText(profile['contact1']);
      _contact2Controller.text = _profileText(profile['contact2']);
      _addressController.text = _profileText(profile['address']);
      _profilePicUrl = profileImage;
      _companyStampUrl = companyStamp;
      _newCompanyStampBytes = null;
      _clearCompanyStamp = false;
      AuthService.profilePicNotifier.value = profileImage;
      AuthService.companyStampNotifier.value = companyStamp;
      _isLoading = false;
    });

    PreferencesService.setCompanyCurrency(
      normalizedCurrency,
    ).catchError((_) {});
  }

  Future<void> _loadProfile() async {
    final loadToken = ++_profileLoadToken;

    final sessionSettings = ref.read(sessionTimeoutSettingsProvider);
    _sessionTimeoutEnabled = sessionSettings.enabled;
    _sessionTimeoutDuration = sessionSettings.durationMinutes;

    if (_isGuest) {
      await _loadGuestProfile();
      return;
    }

    try {
      final profile = await _firestore.getUserProfile();
      if (!mounted || loadToken != _profileLoadToken) return;
      _applyAuthenticatedProfile(profile);
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'LoadProfile');
      if (!mounted || loadToken != _profileLoadToken) return;
      setState(() => _isLoading = false);
      if (widget.isActive) {
        FlashySnackBar.show(
          context,
          message: 'unexpected_error'.tr(),
          isError: true,
        );
      }
    }
  }

  Future<void> _loadGuestProfile() async {
    final guestData = await PreferencesService.getGuestProfileData();
    if (!mounted) return;
    final sessionSettings = ref.read(sessionTimeoutSettingsProvider);
    setState(() {
      _sessionTimeoutEnabled = sessionSettings.enabled;
      _sessionTimeoutDuration = sessionSettings.durationMinutes;
      _businessNameController.text =
          guestData?['businessName'] ?? 'ABC Corporation';
      _companyIdController.text = (guestData?['companyId'] ?? '').toUpperCase();
      _emailController.text = guestData?['email'] ?? 'guest_email'.tr();
      _currencyController.text = CurrencyUtils.normalize(
        guestData?['currency'],
      );
      _contact1Controller.text =
          guestData?['contact1'] ?? 'guest_contact_1'.tr();
      _contact2Controller.text =
          guestData?['contact2'] ?? 'guest_contact_2'.tr();
      _addressController.text = guestData?['address'] ?? 'guest_address'.tr();
      _profilePicUrl =
          guestData?['profilePic'] ?? AuthService.profilePicNotifier.value;
      _companyStampUrl = guestData?['companyStampUrl'];
      AuthService.profilePicNotifier.value = _profilePicUrl;
      AuthService.companyStampNotifier.value = _companyStampUrl;
      _isLoading = false;
    });
  }

  Future<void> _pickProfilePic() async {
    if (_isGuest) {
      FlashySnackBar.show(
        context,
        message: 'guest_action_not_allowed'.tr(),
        isError: true,
      );
      return;
    }

    try {
      final result = await FilePicker.pickFiles(type: FileType.image);
      if (result == null || !mounted) return;

      final file = result.files.single;
      final fileBytes = await file.readAsBytes();
      final filePath = file.path?.trim();

      if (fileBytes.length > _maxProfileImageBytes) {
        if (!mounted) return;
        FlashySnackBar.show(
          context,
          message: 'file_too_large'.tr(namedArgs: {'size': '10MB'}),
          isError: true,
        );
        return;
      }

      if (fileBytes.isEmpty && (filePath == null || filePath.isEmpty)) {
        if (!mounted) return;
        FlashySnackBar.show(
          context,
          message: 'error_selecting_image'.tr(
            namedArgs: {'error': 'unexpected_error'.tr()},
          ),
          isError: true,
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _newProfileImageBytes = fileBytes;
        _newProfileImagePath = filePath;
      });
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'SelectProfileImage');
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'error_selecting_image'.tr(
            namedArgs: {'error': error.toString()},
          ),
          isError: true,
        );
      }
    }
  }

  Future<void> _pickCompanyStamp() async {
    if (_isGuest) {
      FlashySnackBar.show(
        context,
        message: 'guest_action_not_allowed'.tr(),
        isError: true,
      );
      return;
    }

    try {
      final file = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg'],
      );
      if (file == null || !mounted) return;

      final pickedFile = file.files.first;
      final filePath = pickedFile.path?.trim();
      Uint8List bytes;

      if (filePath != null && filePath.isNotEmpty) {
        final selectedFile = File(filePath);
        if (await selectedFile.length() > _maxCompanyStampBytes) {
          throw const FileSystemException('Company stamp is larger than 5 MB.');
        }
        bytes = await selectedFile.readAsBytes();
      } else {
        bytes = await pickedFile.readAsBytes();
      }

      if (bytes.isEmpty) {
        throw const FileSystemException('Unable to read company stamp.');
      }
      if (bytes.lengthInBytes > _maxCompanyStampBytes) {
        throw const FileSystemException('Company stamp is larger than 5 MB.');
      }
      if (_companyStampFormat(bytes) == null ||
          img.decodeImage(bytes) == null) {
        throw const FormatException(
          'Only valid PNG or JPG images are allowed.',
        );
      }

      if (!mounted) return;
      setState(() {
        _newCompanyStampBytes = bytes;
        _clearCompanyStamp = false;
      });
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'SelectCompanyStamp');
      if (mounted) {
        final isFileTooLarge =
            error is FileSystemException && error.message.contains('5 MB');
        FlashySnackBar.show(
          context,
          message: isFileTooLarge
              ? 'file_too_large'.tr(namedArgs: {'size': '5MB'})
              : 'company_stamp_invalid'.tr(),
          isError: true,
        );
      }
    }
  }

  String? _profileEmailError(String value) {
    final email = value.trim();
    if (email.isEmpty) return 'email_is_required'.tr();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'enter_valid_email'.tr();
    }
    return null;
  }

  bool _validateProfileFields() {
    final businessName = _businessNameController.text.trim();
    final companyId = _companyIdController.text.trim().toUpperCase();
    final email = _emailController.text.trim().toLowerCase();
    final contact1 = _contact1Controller.text.trim();
    final address = _addressController.text.trim();
    final normalizedCurrency = CurrencyUtils.normalize(
      _currencyController.text,
    );

    if (businessName.isEmpty &&
        companyId.isEmpty &&
        email.isEmpty &&
        contact1.isEmpty &&
        address.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_field'.tr(),
        isError: true,
      );
      return false;
    }

    if (businessName.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_company_name'.tr(),
        isError: true,
      );
      return false;
    }

    if (companyId.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'field_is_required'.tr(
          namedArgs: {'field': 'company_id_no'.tr()},
        ),
        isError: true,
      );
      return false;
    }

    final companyIdError = Validators.companyId(companyId);
    if (companyIdError != null) {
      FlashySnackBar.show(context, message: companyIdError, isError: true);
      return false;
    }

    final emailError = _profileEmailError(email);
    if (emailError != null) {
      FlashySnackBar.show(context, message: emailError, isError: true);
      return false;
    }

    if (contact1.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_contact_number'.tr(),
        isError: true,
      );
      return false;
    }

    if (address.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_address'.tr(),
        isError: true,
      );
      return false;
    }

    if (!CurrencyUtils.isSupported(normalizedCurrency)) {
      FlashySnackBar.show(
        context,
        message: 'invalid_currency_value'.tr(),
        isError: true,
      );
      return false;
    }

    return true;
  }

  Future<bool> _saveProfile() async {
    if (!mounted) return false;
    if (!_validateProfileFields()) return false;

    final businessName = _businessNameController.text.trim();
    final companyId = _companyIdController.text.trim().toUpperCase();
    final email = _emailController.text.trim().toLowerCase();
    final contact1 = _contact1Controller.text.trim();
    final contact2 = _contact2Controller.text.trim();
    final address = _addressController.text.trim();
    final normalizedCurrency = CurrencyUtils.normalize(
      _currencyController.text,
    );

    _businessNameController.text = businessName;
    _companyIdController.text = companyId;
    _emailController.text = email;
    _currencyController.text = normalizedCurrency;
    _contact1Controller.text = contact1;
    _contact2Controller.text = contact2;
    _addressController.text = address;

    if (!mounted) return false;
    setState(() => _isLoading = true);

    final oldProfilePicUrl = _profilePicUrl;
    final oldCompanyStampUrl = _companyStampUrl;
    final wasClearingCompanyStamp = _clearCompanyStamp;

    Reference? uploadedRef;
    Reference? uploadedStampRef;
    var profileSaved = false;
    var errorAlreadyShown = false;

    try {
      if (_isGuest) {
        await _saveGuestProfile(normalizedCurrency);
      } else {
        await _saveFirestoreProfile(
          businessName: businessName,
          companyId: companyId,
          email: email,
          normalizedCurrency: normalizedCurrency,
          contact1: contact1,
          contact2: contact2,
          address: address,
          uploadedRef: (ref) => uploadedRef = ref,
          uploadedStampRef: (ref) => uploadedStampRef = ref,
          onError: () => errorAlreadyShown = true,
          oldProfilePicUrl: oldProfilePicUrl,
          oldCompanyStampUrl: oldCompanyStampUrl,
          wasClearingCompanyStamp: wasClearingCompanyStamp,
        );
        profileSaved = true;
      }

      await ref.read(sessionTimeoutSettingsProvider.notifier).setEnabled(_sessionTimeoutEnabled);
      await ref.read(sessionTimeoutSettingsProvider.notifier).setDurationMinutes(_sessionTimeoutDuration);

      if (mounted) {
        setState(() => _isLoading = false);
        FlashySnackBar.show(context, message: 'profile_saved'.tr());
      }
      return true;
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'SaveProfile');

      if (!profileSaved) {
        try {
          await uploadedRef?.delete();
        } catch (_) {}
        try {
          await uploadedStampRef?.delete();
        } catch (_) {}
      }

      if (mounted) {
        setState(() => _isLoading = false);
        if (!errorAlreadyShown) {
          FlashySnackBar.show(
            context,
            message: 'error_saving_profile'.tr(
              namedArgs: {'error': error.toString()},
            ),
            isError: true,
          );
        }
      }
      return false;
    }
  }

  Future<void> _saveGuestProfile(String normalizedCurrency) async {
    String? downloadUrl;

    if (_newProfileImageBytes != null) {
      final localPath = await PreferencesService.persistImageLocally(
        bytes: _newProfileImageBytes!,
        fileName: 'company_logo.png',
      );
      downloadUrl =
          localPath ??
          'data:image/png;base64,${base64Encode(_newProfileImageBytes!)}';
    } else if (_newProfileImagePath != null) {
      Uint8List? pickedBytes;
      try {
        pickedBytes = await File(_newProfileImagePath!).readAsBytes();
      } catch (_) {}

      if (pickedBytes != null && pickedBytes.isNotEmpty) {
        downloadUrl =
            await PreferencesService.persistImageLocally(
              bytes: pickedBytes,
              fileName: 'company_logo.png',
            ) ??
            _newProfileImagePath;
      } else {
        downloadUrl = _newProfileImagePath;
      }
    }

    if (downloadUrl != null) {
      _profilePicUrl = downloadUrl;
      AuthService.profilePicNotifier.value = downloadUrl;
      try {
        await PreferencesService.setProfilePicUrl(downloadUrl);
      } catch (_) {}
      _newProfileImageBytes = null;
      _newProfileImagePath = null;
    }

    if (_newCompanyStampBytes != null) {
      final stampFormat = _companyStampFormat(_newCompanyStampBytes!) ?? 'png';
      final localPath = await PreferencesService.persistImageLocally(
        bytes: _newCompanyStampBytes!,
        fileName: 'company_stamp.$stampFormat',
      );
      _companyStampUrl =
          localPath ??
          'data:image/$stampFormat;base64,${base64Encode(_newCompanyStampBytes!)}';
      AuthService.companyStampNotifier.value = _companyStampUrl;
      try {
        await PreferencesService.setCompanyStampUrl(_companyStampUrl);
      } catch (_) {}
      _newCompanyStampBytes = null;
    } else if (_clearCompanyStamp) {
      _companyStampUrl = null;
      AuthService.companyStampNotifier.value = null;
      try {
        await PreferencesService.setCompanyStampUrl(null);
      } catch (_) {}
      _clearCompanyStamp = false;
    }

    final existing =
        await PreferencesService.getGuestProfileData() ??
        const <String, String>{};

    final updatedProfile = <String, String>{
      ...existing,
      'businessName': _businessNameController.text,
      'companyId': _companyIdController.text,
      'email': _emailController.text,
      'currency': normalizedCurrency,
      'contact1': _contact1Controller.text,
      'contact2': _contact2Controller.text,
      'address': _addressController.text,
    };

    if (_profilePicUrl != null && _profilePicUrl!.isNotEmpty) {
      updatedProfile['profilePic'] = _profilePicUrl!;
    }

    updatedProfile['companyStampUrl'] =
        (_companyStampUrl != null && _companyStampUrl!.isNotEmpty)
        ? _companyStampUrl!
        : '';

    await PreferencesService.setGuestProfileData(updatedProfile);
  }

  Future<void> _saveFirestoreProfile({
    required String businessName,
    required String companyId,
    required String email,
    required String normalizedCurrency,
    required String contact1,
    required String contact2,
    required String address,
    required void Function(Reference?) uploadedRef,
    required void Function(Reference?) uploadedStampRef,
    required VoidCallback onError,
    required String? oldProfilePicUrl,
    required String? oldCompanyStampUrl,
    required bool wasClearingCompanyStamp,
  }) async {
    String? downloadUrl;
    String? stampDownloadUrl;
    String? cachedLocalPicPath;
    String? cachedLocalStampPath;

    final hasNewProfileImage =
        _newProfileImageBytes != null || _newProfileImagePath != null;
    final hasNewStamp = _newCompanyStampBytes != null;

    final uploadTasks = <Future<void>>[];

    if (hasNewProfileImage) {
      uploadTasks.add(
        _uploadProfileImage(
          onUrl: (url) => downloadUrl = url,
          onCachedPath: (path) => cachedLocalPicPath = path,
          onRef: uploadedRef,
          onError: onError,
        ),
      );
    }

    if (hasNewStamp) {
      uploadTasks.add(
        _uploadCompanyStamp(
          onUrl: (url) => stampDownloadUrl = url,
          onCachedPath: (path) => cachedLocalStampPath = path,
          onRef: uploadedStampRef,
        ),
      );
    }

    if (uploadTasks.isNotEmpty) {
      await Future.wait(uploadTasks);
    }

    final profileUpdate = <String, dynamic>{
      'businessName': businessName,
      'companyId': companyId,
      'email': email,
      'currency': normalizedCurrency,
      'contact1': contact1,
      'contact2': contact2,
      'address': address,
    };

    if (downloadUrl != null) {
      profileUpdate['profilePic'] = downloadUrl;
    }

    if (stampDownloadUrl != null) {
      profileUpdate['companyStampUrl'] = stampDownloadUrl;
    } else if (_clearCompanyStamp) {
      profileUpdate['companyStampUrl'] = '';
    }

    await _firestore.updateUserProfile(profileUpdate);

    PreferencesService.setCompanyCurrency(
      normalizedCurrency,
    ).catchError((_) {});

    _applyUploadResults(
      downloadUrl,
      stampDownloadUrl,
      cachedLocalPicPath,
      cachedLocalStampPath,
      oldProfilePicUrl,
      oldCompanyStampUrl,
      wasClearingCompanyStamp,
    );
  }

  Future<void> _uploadProfileImage({
    required void Function(String) onUrl,
    required void Function(String?) onCachedPath,
    required void Function(Reference?) onRef,
    required VoidCallback onError,
  }) async {
    Uint8List? rawBytes = _newProfileImageBytes;

    if (rawBytes == null && _newProfileImagePath != null) {
      final imageFile = File(_newProfileImagePath!);
      if (await imageFile.length() > _maxProfileImageBytes) {
        throw const FileSystemException('Profile image is larger than 10 MB.');
      }
      rawBytes = await imageFile.readAsBytes();
    }

    if (rawBytes == null || rawBytes.isEmpty) {
      throw const FileSystemException('Unable to read image bytes.');
    }
    if (rawBytes.length > _maxProfileImageBytes) {
      throw const FileSystemException('Profile image is larger than 10 MB.');
    }

    final compressedBytes = await compute(_compressImageBytes, rawBytes);
    if (compressedBytes == null || compressedBytes.isEmpty) {
      throw const FormatException('Unsupported profile image format.');
    }

    final uid = _authService.currentUser?.uid ?? 'user';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'profile_${uid}_$ts.jpg';

    Reference? ref;
    try {
      ref = FirebaseStorage.instance
          .ref()
          .child('profile_pics')
          .child(fileName);
      onRef(ref);
      await ref.putData(
        compressedBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await ref.getDownloadURL();
      onUrl(url);
      onCachedPath(
        await PreferencesService.persistImageLocally(
          bytes: compressedBytes,
          fileName: 'company_logo_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'UploadProfileImage');
      try {
        await ref?.delete();
      } catch (_) {}
      if (mounted) {
        final isUnsupportedFormat =
            error is FormatException &&
            error.message.toLowerCase().contains('unsupported');
        FlashySnackBar.show(
          context,
          message: isUnsupportedFormat
              ? 'profile_image_format_unsupported'.tr()
              : 'profile_image_upload_failed_detail'.tr(
                  namedArgs: {'error': error.toString()},
                ),
          isError: true,
        );
      }
      onError();
      rethrow;
    }
  }

  Future<void> _uploadCompanyStamp({
    required void Function(String) onUrl,
    required void Function(String?) onCachedPath,
    required void Function(Reference?) onRef,
  }) async {
    final rawStampBytes = _newCompanyStampBytes!;
    final detectedFormat = _companyStampFormat(rawStampBytes);

    if (detectedFormat == null || rawStampBytes.isEmpty) {
      throw const FormatException('Unsupported company stamp format.');
    }

    final compressedStamp = await compute(_compressStampBytes, rawStampBytes);
    if (compressedStamp == null || compressedStamp.isEmpty) {
      throw const FormatException('Unsupported company stamp format.');
    }

    final uid = _authService.currentUser?.uid ?? 'user';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final stampFileName = 'company_stamp_${uid}_$ts.$detectedFormat';
    final contentType = detectedFormat == 'png' ? 'image/png' : 'image/jpeg';

    final stampRef = FirebaseStorage.instance
        .ref()
        .child('profile_pics')
        .child(stampFileName);
    onRef(stampRef);

    await stampRef.putData(
      compressedStamp,
      SettableMetadata(contentType: contentType),
    );
    onUrl(await stampRef.getDownloadURL());
    onCachedPath(
      await PreferencesService.persistImageLocally(
        bytes: compressedStamp,
        fileName:
            'company_stamp_${DateTime.now().millisecondsSinceEpoch}.$detectedFormat',
      ),
    );
  }

  void _applyUploadResults(
    String? downloadUrl,
    String? stampDownloadUrl,
    String? cachedLocalPicPath,
    String? cachedLocalStampPath,
    String? oldProfilePicUrl,
    String? oldCompanyStampUrl,
    bool wasClearingCompanyStamp,
  ) {
    if (downloadUrl != null) {
      _profilePicUrl = downloadUrl;
      AuthService.profilePicNotifier.value = downloadUrl;
      _newProfileImageBytes = null;
      _newProfileImagePath = null;

      _authService.currentUser
          ?.updatePhotoURL(downloadUrl)
          .catchError(
            (e, s) =>
                ErrorReporter.report(e, s, context: 'UpdateAuthProfileImage'),
          );

      final effectivePicUrl = cachedLocalPicPath?.isNotEmpty == true
          ? cachedLocalPicPath
          : downloadUrl;
      PreferencesService.setProfilePicUrl(effectivePicUrl).catchError(
        (e, s) => ErrorReporter.report(e, s, context: 'CacheProfileImage'),
      );

      if (cachedLocalPicPath != null && cachedLocalPicPath.isNotEmpty) {
        PreferencesService.setProfilePicLocalPath(
          cachedLocalPicPath,
        ).catchError((_) {});
      }
    }

    if (stampDownloadUrl != null || _clearCompanyStamp) {
      _companyStampUrl = stampDownloadUrl;
      AuthService.companyStampNotifier.value = stampDownloadUrl;

      if (stampDownloadUrl != null) {
        final effectiveStampUrl = cachedLocalStampPath?.isNotEmpty == true
            ? cachedLocalStampPath
            : stampDownloadUrl;
        PreferencesService.setCompanyStampUrl(
          effectiveStampUrl,
        ).catchError((_) {});
      } else {
        PreferencesService.setCompanyStampUrl(null).catchError((_) {});
      }

      _newCompanyStampBytes = null;
      _clearCompanyStamp = false;
    }

    if (downloadUrl != null &&
        oldProfilePicUrl != null &&
        oldProfilePicUrl.isNotEmpty &&
        oldProfilePicUrl != downloadUrl) {
      UploadService.deleteByUrl(oldProfilePicUrl).catchError(
        (e, s) => ErrorReporter.report(e, s, context: 'CleanupOldProfilePic'),
      );
    }

    if ((stampDownloadUrl != null || wasClearingCompanyStamp) &&
        oldCompanyStampUrl != null &&
        oldCompanyStampUrl.isNotEmpty &&
        oldCompanyStampUrl != stampDownloadUrl) {
      UploadService.deleteByUrl(oldCompanyStampUrl).catchError(
        (e, s) => ErrorReporter.report(e, s, context: 'CleanupOldCompanyStamp'),
      );
    }
  }

  void _showPreviewDialog() {
    showDialog(
      context: context,
      barrierColor: _kPrimaryBlue.withOpacity(0.5),
      builder: (_) => ProfilePreviewDialog(
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
          if (mounted) setState(() => _isEditing = true);
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
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: _buildProfileIcon(),
            ),
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
                  backgroundColor: _kPrimaryBlue,
                  foregroundColor: _kWhite,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 36,
                    vertical: 19,
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
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: _kFontFamily,
                        ),
                      ),
              )
            else
              InkWell(
                onTap: () {
                  if (_isGuest) {
                    showGuestRestrictionDialog(context);
                    return;
                  }
                  setState(() => _isEditing = true);
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: _kLightBlueBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SvgPicture.asset(
                    'assets/edit_icon.svg',
                    width: 20,
                    height: 20,
                    colorFilter: const ColorFilter.mode(
                      _kActionBlue,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _kFormBg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              _buildFormRow(
                _buildInputField(
                  'company_name'.tr(),
                  _businessNameController,
                  readOnly: !_isEditing,
                  isBusinessName: true,
                ),
                _buildInputField(
                  'company_id_no'.tr(),
                  _companyIdController,
                  readOnly: !_isEditing,
                  isCompanyId: true,
                ),
              ),
              const SizedBox(height: 16),
              _buildFormRow(
                _buildInputField(
                  'company_email'.tr(),
                  _emailController,
                  readOnly: !_isEditing,
                  isEmailField: true,
                ),
                _buildCurrencyField(_isEditing),
              ),
              const SizedBox(height: 16),
              _buildFormRow(
                _buildInputField(
                  'contact_number'.tr(),
                  _contact1Controller,
                  readOnly: !_isEditing,
                  isContact: true,
                ),
                _buildInputField(
                  'address'.tr(),
                  _addressController,
                  readOnly: !_isEditing,
                  isAddress: true,
                ),
              ),
              const SizedBox(height: 16),
              _buildCompanyStampField(),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSessionSecuritySection(),
      ],
    );
  }

  Widget _buildSessionSecuritySection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kFormBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'session_security'.tr(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFamily: _kFontFamily,
              color: _kBlack,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'enable_session_timeout'.tr(),
                      style: _kLabelStyle,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _sessionTimeoutEnabled
                          ? 'session_locked_message'.tr(namedArgs: {'minutes': _sessionTimeoutDuration.toString()})
                          : 'enable_session_timeout'.tr(),
                      style: const TextStyle(
                        fontSize: 13,
                        color: _kGreyText,
                        fontFamily: _kFontFamily,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _sessionTimeoutEnabled,
                onChanged: !_isEditing
                    ? null
                    : (val) {
                        setState(() {
                          _sessionTimeoutEnabled = val;
                        });
                      },
                activeColor: _kPrimaryBlue,
              ),
            ],
          ),
          if (_sessionTimeoutEnabled) ...[
            const SizedBox(height: 20),
            _buildSessionDurationField(_isEditing),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionDurationField(bool isEditing) {
    final durations = [1, 3, 5, 10, 30];
    final String label = 'session_timeout_duration'.tr();

    if (!isEditing) {
      final text = _getDurationLabel(_sessionTimeoutDuration);
      return _buildInputField(
        label,
        TextEditingController(text: text),
        readOnly: true,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _kLabelStyle),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: durations.contains(_sessionTimeoutDuration)
                  ? _sessionTimeoutDuration
                  : 3,
              isExpanded: true,
              itemHeight: 48,
              dropdownColor: Colors.white,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black,
                fontFamily: _kFontFamily,
              ),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _sessionTimeoutDuration = val);
                }
              },
              items: durations
                  .map(
                    (value) => DropdownMenuItem<int>(
                      value: value,
                      child: Text(
                        _getDurationLabel(value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  String _getDurationLabel(int minutes) {
    if (minutes == 1) {
      return '1_minute'.tr();
    }
    return '${minutes}_minutes'.tr();
  }

  Widget _buildProfileIcon() {
    final hasNewBytes = _newProfileImageBytes != null;
    final hasNewPath = _newProfileImagePath != null;
    final hasCustomPic = _profilePicUrl != null && _profilePicUrl!.isNotEmpty;

    Widget fallback() =>
        const Icon(Icons.business_rounded, size: 40, color: _kPrimaryBlue);

    Widget loading() => const Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );

    Widget child;

    if (hasNewBytes) {
      child = Image.memory(
        _newProfileImageBytes!,
        width: 100,
        height: 100,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
      );
    } else if (hasNewPath) {
      child = Image.file(
        File(_newProfileImagePath!),
        width: 100,
        height: 100,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
      );
    } else if (hasCustomPic) {
      final url = _profilePicUrl!;
      if (url.startsWith('http')) {
        child = CachedNetworkImage(
          imageUrl: url,
          width: 90,
          height: 90,
          fit: BoxFit.cover,
          placeholder: (_, __) => loading(),
          errorWidget: (_, __, ___) => fallback(),
        );
      } else if (url.startsWith('data:image')) {
        final decoded = _decodeProfileDataImage(url);
        child = decoded == null
            ? fallback()
            : Image.memory(
                decoded,
                width: 90,
                height: 90,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback(),
              );
      } else {
        child = Image.file(
          File(url),
          width: 90,
          height: 90,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback(),
        );
      }
    } else {
      child = Image.asset(
        'assets/company_profile_placeholder.png',
        width: 100,
        height: 100,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
      );
    }

    return GestureDetector(
      onTap: _isEditing ? _pickProfilePic : null,
      child: Stack(
        children: [
          Container(
            width: 90,
            height: 90,
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Center(child: child),
          ),
          if (_isEditing)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 25,
                height: 28,
                decoration: const BoxDecoration(
                  color: _kPrimaryBlue,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(6),
                child: SvgPicture.asset(
                  'assets/edit_pencil_profile.svg',
                  colorFilter: const ColorFilter.mode(_kWhite, BlendMode.srcIn),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompanyStampField() {
    final hasNewStamp = _newCompanyStampBytes != null;
    final hasSavedStamp =
        !_clearCompanyStamp &&
        _companyStampUrl != null &&
        _companyStampUrl!.trim().isNotEmpty;
    final hasStamp = hasNewStamp || hasSavedStamp;

    final preview = Container(
      width: 180,
      height: 104,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _kStampBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(child: _buildCompanyStampPreview()),
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasStamp
              ? 'company_stamp_ready'.tr()
              : 'company_stamp_not_uploaded'.tr(),
          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 15,
            fontWeight: FontWeight.w600,
            fontFamily: _kFontFamily,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 5),
        Text(
          hasStamp
              ? 'company_stamp_pdf_note'.tr()
              : 'company_stamp_fallback_note'.tr(),
          style: const TextStyle(
            color: _kGrey6B,
            fontSize: 13,
            height: 1.35,
            fontFamily: _kFontFamily,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (_isEditing) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _pickCompanyStamp,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(
                  hasStamp
                      ? 'replace_company_stamp'.tr()
                      : 'upload_company_stamp'.tr(),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kActionBlue,
                  side: const BorderSide(color: _kActionBlue),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              if (hasStamp)
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () async {
                          final confirmed = await DeleteDialog.show(
                            context: context,
                            title: 'remove_company_stamp_title'.tr(),
                            content: 'remove_company_stamp_desc'.tr(),
                            confirmButtonText: 'remove',
                          );
                          if (!confirmed || !mounted) return;
                          setState(() {
                            _newCompanyStampBytes = null;
                            _clearCompanyStamp = true;
                          });
                        },
                  style: TextButton.styleFrom(foregroundColor: _kRedDelete),
                  child: Text('remove'.tr()),
                ),
            ],
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('company_stamp_signature'.tr(), style: _kLabelStyle),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _isEditing ? _kWhite : _kBgGrey,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _kStampBorder),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [preview, const SizedBox(height: 14), details],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  preview,
                  const SizedBox(width: 18),
                  Expanded(child: details),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'company_stamp_format_hint'.tr(),
          style: const TextStyle(
            color: _kGrey6B,
            fontSize: 12,
            fontFamily: _kFontFamily,
          ),
        ),
      ],
    );
  }

  Widget _buildCompanyStampPreview() {
    Widget fallback() => Center(
      child: Image.asset(
        'assets/default_hr_stamp.png',
        width: 96,
        height: 96,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.approval_outlined,
          size: 48,
          color: Color(0xFF0B2A6F),
        ),
      ),
    );

    if (_newCompanyStampBytes != null) {
      return Image.memory(
        _newCompanyStampBytes!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => fallback(),
      );
    }

    if (_clearCompanyStamp ||
        _companyStampUrl == null ||
        _companyStampUrl!.trim().isEmpty) {
      return fallback();
    }

    final value = _companyStampUrl!.trim();

    if (value.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: value,
        fit: BoxFit.contain,
        placeholder: (_, __) => const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (_, __, ___) => fallback(),
      );
    }

    if (value.startsWith('data:image')) {
      final bytes = _decodeProfileDataImage(value);
      return bytes == null
          ? fallback()
          : Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => fallback(),
            );
    }

    return Image.file(
      File(value),
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => fallback(),
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
    bool isEmailField = false,
    bool isCompanyId = false,
    bool isBusinessName = false,
    bool isContact = false,
    bool isAddress = false,
  }) {
    final bgColor = readOnly ? _kBgGrey : _kWhite;
    final textColor = readOnly ? _kGreyText : _kBlack;

    final String hintText;
    if (isEmailField) {
      hintText = 'hint_enter_email'.tr();
    } else if (isCompanyId) {
      hintText = _isGuest ? 'hint_enter_company_id'.tr() : 'company_id_no'.tr();
    } else if (isBusinessName) {
      hintText = _isGuest
          ? 'hint_enter_business_name'.tr()
          : 'company_name'.tr();
    } else if (isContact) {
      hintText = 'hint_enter_phone'.tr();
    } else if (isAddress) {
      hintText = 'hint_enter_address'.tr();
    } else {
      hintText = '';
    }

    final List<TextInputFormatter>? formatters;
    if (isBusinessName) {
      formatters = [LengthLimitingTextInputFormatter(30)];
    } else if (isAddress) {
      formatters = [LengthLimitingTextInputFormatter(100)];
    } else if (isContact) {
      formatters = [
        LengthLimitingTextInputFormatter(15),
        FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]')),
      ];
    } else if (isCompanyId) {
      formatters = [
        LengthLimitingTextInputFormatter(15),
        TextInputFormatter.withFunction(
          (oldValue, newValue) =>
              newValue.copyWith(text: newValue.text.toUpperCase()),
        ),
        FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9-]')),
      ];
    } else {
      formatters = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _kLabelStyle,
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
            border: readOnly ? Border.all(color: _kBorderLight) : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: maxLines,
                  readOnly: readOnly,
                  keyboardType: isEmailField
                      ? TextInputType.emailAddress
                      : isContact
                      ? TextInputType.phone
                      : TextInputType.text,
                  textCapitalization: isCompanyId
                      ? TextCapitalization.characters
                      : TextCapitalization.none,
                  autocorrect: !isEmailField && !isCompanyId,
                  enableSuggestions: !isEmailField && !isCompanyId,
                  inputFormatters: formatters,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    hintText: hintText,
                    hintStyle: _kInputHintStyle,
                    counterText: '',
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    color: textColor,
                    fontFamily: _kFontFamily,
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

    final currentCurrency = _currencyController.text;
    final currencies = <String>[
      if (!CurrencyUtils.commonCodes.contains(currentCurrency) &&
          CurrencyUtils.isSupported(currentCurrency))
        currentCurrency,
      ...CurrencyUtils.commonCodes,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('currency'.tr(), style: _kLabelStyle),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currencies.contains(_currencyController.text)
                  ? _currencyController.text
                  : currencies.first,
              isExpanded: true,
              itemHeight: 48,
              dropdownColor: Colors.white,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black,
                fontFamily: _kFontFamily,
              ),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _currencyController.text = val);
                }
              },
              items: currencies
                  .map(
                    (value) => DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        LocalizationHelper.localizeCurrency(value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}
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

  static const Color _primaryBlue = Color(0xFF0B51C1);
  static const Color _lightBlueBg = Color(0xFFE8F0FE);

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
            color: _kWhite,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: _kBlack.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              Container(
                color: _kDarkBlue,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      'profile_preview'.tr(),
                      style: const TextStyle(
                        color: _kWhite,
                        fontSize: 19,
                        fontFamily: _kFontFamily,
                        fontWeight: FontWeight.w500
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: _kWhite, size: 26),
                        onPressed: () => Navigator.of(context).pop(),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                      ),
                    ),
                    Align(
                      alignment: const Alignment(1.0, 0),
                      child: IconButton(
                        icon: SvgPicture.asset(
                          'assets/edit_icon.svg',
                          height: 20,
                          width: 20,
                          colorFilter: const ColorFilter.mode(
                            _kWhite,
                            BlendMode.srcIn,
                          ),
                        ),
                        onPressed: onEdit,
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                color: const Color(0xFF0247C4),
                padding: const EdgeInsets.fromLTRB(28, 14, 28, 14),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: _kWhite,
                        shape: BoxShape.circle,
                        border: Border.all(color: _kWhite, width: 2),
                      ),
                      child: const ClipOval(child: UserAvatar(radius: 62)),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          businessName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _kWhite,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            fontFamily: _kFontFamily,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _previewCard(
                            'company_name'.tr(),
                            businessName,
                            'assets/preview_profile.svg',
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _previewCard(
                            'company_id_no'.tr(),
                            companyId,
                            'assets/company_id.svg',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _previewCard(
                            'company_email'.tr(),
                            email,
                            'assets/company_email.svg',
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _previewCard(
                            'currency'.tr(),
                            currency,
                            'assets/currency_preview.svg',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _previewCard(
                            'contact_no'.tr(),
                            contact1,
                            'assets/phone_preview.svg',
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _previewCard(
                            'address'.tr(),
                            address,
                            'assets/location_preview.svg',
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
      ),
    );
  }

  Widget _previewCard(String label, String value, String svgPath) {
    return Container(
      height: 72,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: _kWhite,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _lightBlueBg,
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.all(8),
            child: SvgPicture.asset(
              svgPath,
              colorFilter: const ColorFilter.mode(
                _primaryBlue,
                BlendMode.srcIn,
              ),
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
                      fontFamily: _kFontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                      color: _kBlack,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: _kFontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                    color: _kBlack,
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
