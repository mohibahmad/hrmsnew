import 'dart:convert';
import 'dart:io';
import 'dart:async';
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
import '../services/error_reporter.dart';
import '../services/upload_service.dart';
import '../utils/currency_utils.dart';
import '../utils/delete_dialog.dart';
import '../utils/localization_helper.dart';
import '../utils/snackbar_utils.dart';
import '../utils/guest_restriction.dart';
import '../utils/validators.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/notification_bell.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';

Uint8List? _compressImageBytes(Uint8List rawBytes) {
  try {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) return null;

    final resized = img.copyResize(decoded, width: 500);

    return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  } catch (_) {
    return null;
  }
}

const int _maxProfileImageBytes = 10 * 1024 * 1024;
const int _maxCompanyStampBytes = 5 * 1024 * 1024;

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
          SizedBox(width: 3),
          Text(
            'my_info'.tr(),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
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
  Uint8List? _newCompanyStampBytes;
  bool _clearCompanyStamp = false;

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
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (_initialized && !isGuest) return;
    _initialized = true;
    _loadProfile();
    if (!isGuest) {
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

  String _profileText(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    return value.toString();
  }

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
      _companyIdController.text = _profileText(profile['companyId']);
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
      PreferencesService.setCompanyCurrency(
        normalizedCurrency,
      ).catchError((_) {});
      _isLoading = false;
    });
  }

  Future<void> _loadProfile() async {
    final loadToken = ++_profileLoadToken;
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      final guestData = await PreferencesService.getGuestProfileData();
      if (mounted) {
        setState(() {
          _businessNameController.text =
              guestData?['businessName'] ?? 'ABC Corporation';
          _companyIdController.text = guestData?['companyId'] ?? '';
          _emailController.text = guestData?['email'] ?? 'guest_email'.tr();
          _currencyController.text = CurrencyUtils.normalize(
            guestData?['currency'],
          );
          _contact1Controller.text =
              guestData?['contact1'] ?? 'guest_contact_1'.tr();
          _contact2Controller.text =
              guestData?['contact2'] ?? 'guest_contact_2'.tr();
          _addressController.text =
              guestData?['address'] ?? 'guest_address'.tr();
          _profilePicUrl =
              guestData?['profilePic'] ?? AuthService.profilePicNotifier.value;
          _companyStampUrl = guestData?['companyStampUrl'];
          AuthService.profilePicNotifier.value = _profilePicUrl;
          AuthService.companyStampNotifier.value = _companyStampUrl;
          _isLoading = false;
        });
      }
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

  Uint8List? _newProfileImageBytes;
  String? _newProfileImagePath;

  Future<void> _pickProfilePic() async {
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
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
      var fileSize = file.bytes?.length;
      final filePath = file.path?.trim();
      if (fileSize == null && filePath != null && filePath.isNotEmpty) {
        fileSize = await File(filePath).length();
      }
      if (fileSize != null && fileSize > _maxProfileImageBytes) {
        if (!mounted) return;
        FlashySnackBar.show(
          context,
          message: 'file_too_large'.tr(namedArgs: {'size': '10MB'}),
          isError: true,
        );
        return;
      }
      if (file.bytes == null && (filePath == null || filePath.isEmpty)) {
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
        _newProfileImageBytes = file.bytes;
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
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      FlashySnackBar.show(
        context,
        message: 'guest_action_not_allowed'.tr(),
        isError: true,
      );
      return;
    }

    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg'],
      );
      if (file == null || !mounted) return;

      final filePath = file.path?.trim();
      final Uint8List bytes;
      if (filePath != null && filePath.isNotEmpty) {
        final selectedFile = File(filePath);
        final size = await selectedFile.length();
        if (size > _maxCompanyStampBytes) {
          throw const FileSystemException('Company stamp is larger than 5 MB.');
        }
        bytes = await selectedFile.readAsBytes();
      } else {
        bytes = await file.readAsBytes();
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
        FlashySnackBar.show(
          context,
          message:
              error is FileSystemException && error.message.contains('5 MB')
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

  Future<bool> _saveProfile() async {
    final businessName = _businessNameController.text.trim();
    final companyId = _companyIdController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final contact1 = _contact1Controller.text.trim();
    final contact2 = _contact2Controller.text.trim();
    final address = _addressController.text.trim();

    if (businessName.isEmpty &&
        companyId.isEmpty &&
        email.isEmpty &&
        contact1.isEmpty &&
        address.isEmpty) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'please_enter_field'.tr(),
          isError: true,
        );
      }
      return false;
    }

    if (businessName.isEmpty) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'please_enter_company_name'.tr(),
          isError: true,
        );
      }
      return false;
    }

    if (companyId.isEmpty) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'field_is_required'.tr(
            namedArgs: {'field': 'company_id_no'.tr()},
          ),
          isError: true,
        );
      }
      return false;
    }

    final companyIdError = Validators.companyId(companyId);
    if (companyIdError != null) {
      if (mounted) {
        FlashySnackBar.show(context, message: companyIdError, isError: true);
      }
      return false;
    }

    final emailError = _profileEmailError(email);
    if (emailError != null) {
      if (mounted) {
        FlashySnackBar.show(context, message: emailError, isError: true);
      }
      return false;
    }

    if (contact1.isEmpty) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'please_enter_contact_number'.tr(),
          isError: true,
        );
      }
      return false;
    }

    if (address.isEmpty) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'please_enter_address'.tr(),
          isError: true,
        );
      }
      return false;
    }

    final normalizedCurrency = CurrencyUtils.normalize(
      _currencyController.text,
    );
    if (!CurrencyUtils.isSupported(normalizedCurrency)) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'invalid_currency_value'.tr(),
          isError: true,
        );
      }
      return false;
    }

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

    try {
      final isGuest = _authService.currentUser?.isAnonymous ?? false;
      String? downloadUrl;
      String? stampDownloadUrl;
      String? cachedLocalPicPath;
      String? cachedLocalStampPath;

      if (!isGuest) {
        if (_newProfileImageBytes != null || _newProfileImagePath != null) {
          final fileName =
              'profile_${_authService.currentUser?.uid ?? 'user'}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          uploadedRef = FirebaseStorage.instance
              .ref()
              .child('profile_pics')
              .child(fileName);

          try {
            Uint8List? rawBytes = _newProfileImageBytes;
            if (rawBytes == null && _newProfileImagePath != null) {
              final imageFile = File(_newProfileImagePath!);
              final imageLength = await imageFile.length();
              if (imageLength > _maxProfileImageBytes) {
                throw const FileSystemException(
                  'Profile image is larger than 10 MB.',
                );
              }
              rawBytes = await imageFile.readAsBytes();
            }

            if (rawBytes == null || rawBytes.isEmpty) {
              throw const FileSystemException('Unable to read image bytes.');
            }
            if (rawBytes.length > _maxProfileImageBytes) {
              throw const FileSystemException(
                'Profile image is larger than 10 MB.',
              );
            }

            final compressedBytes = await compute(
              _compressImageBytes,
              rawBytes,
            );
            if (compressedBytes == null || compressedBytes.isEmpty) {
              throw const FormatException('Unsupported profile image format.');
            }

            await uploadedRef.putData(
              compressedBytes,
              SettableMetadata(contentType: 'image/jpeg'),
            );
            downloadUrl = await uploadedRef.getDownloadURL();
            cachedLocalPicPath = await PreferencesService.persistImageLocally(
              bytes: compressedBytes,
              fileName:
                  'company_logo_${DateTime.now().millisecondsSinceEpoch}.jpg',
            );
          } catch (error, stackTrace) {
            ErrorReporter.report(
              error,
              stackTrace,
              context: 'UploadProfileImage',
            );
            final failedRef = uploadedRef;
            try {
              await failedRef.delete();
            } catch (_) {}
            if (mounted) {
              setState(() => _isLoading = false);
            
              final isUnsupportedFormat =
                  error is FormatException &&
                  (error.message)
                      .toLowerCase()
                      .contains('unsupported');
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
            return false;
          }
        }

        if (_newCompanyStampBytes != null) {
          final stampBytes = _newCompanyStampBytes!;
          final stampFormat = _companyStampFormat(stampBytes);
          if (stampFormat == null || stampBytes.isEmpty) {
            throw const FormatException('Unsupported company stamp format.');
          }
          final stampFileName =
              'company_stamp_${_authService.currentUser?.uid ?? 'user'}_${DateTime.now().millisecondsSinceEpoch}.$stampFormat';
          uploadedStampRef = FirebaseStorage.instance
              .ref()
              .child('profile_pics')
              .child(stampFileName);
          await uploadedStampRef.putData(
            stampBytes,
            SettableMetadata(
              contentType: stampFormat == 'png' ? 'image/png' : 'image/jpeg',
            ),
          );
          stampDownloadUrl = await uploadedStampRef.getDownloadURL();
          cachedLocalStampPath = await PreferencesService.persistImageLocally(
            bytes: stampBytes,
            fileName:
                'company_stamp_${DateTime.now().millisecondsSinceEpoch}.$stampFormat',
          );
        }

        await _firestore.updateUserProfile({
          'businessName': businessName,
          'companyId': companyId,
          'email': email,
          'currency': normalizedCurrency,
          'contact1': contact1,
          'contact2': contact2,
          'address': address,
          if (downloadUrl != null) 'profilePic': downloadUrl,
          if (stampDownloadUrl != null)
            'companyStampUrl': stampDownloadUrl
          else if (_clearCompanyStamp)
            'companyStampUrl': '',
        });
        profileSaved = true;

        PreferencesService.setCompanyCurrency(
          normalizedCurrency,
        ).catchError((_) {});

        if (downloadUrl != null) {
          _profilePicUrl = downloadUrl;
          AuthService.profilePicNotifier.value = downloadUrl;
          _newProfileImageBytes = null;
          _newProfileImagePath = null;

          _authService.currentUser?.updatePhotoURL(downloadUrl).catchError((
            error,
            stackTrace,
          ) {
            ErrorReporter.report(
              error,
              stackTrace,
              context: 'UpdateAuthProfileImage',
            );
          });
          PreferencesService.setProfilePicUrl(
            cachedLocalPicPath?.isNotEmpty == true
                ? cachedLocalPicPath
                : downloadUrl,
          ).catchError((error, stackTrace) {
            ErrorReporter.report(
              error,
              stackTrace,
              context: 'CacheProfileImage',
            );
          });
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
            PreferencesService.setCompanyStampUrl(
              cachedLocalStampPath?.isNotEmpty == true
                  ? cachedLocalStampPath
                  : stampDownloadUrl,
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
          UploadService.deleteByUrl(oldProfilePicUrl).catchError((
            error,
            stackTrace,
          ) {
            ErrorReporter.report(
              error,
              stackTrace,
              context: 'CleanupOldProfilePic',
            );
          });
        }
        if ((stampDownloadUrl != null || wasClearingCompanyStamp) &&
            oldCompanyStampUrl != null &&
            oldCompanyStampUrl.isNotEmpty &&
            oldCompanyStampUrl != stampDownloadUrl) {
          UploadService.deleteByUrl(oldCompanyStampUrl).catchError((
            error,
            stackTrace,
          ) {
            ErrorReporter.report(
              error,
              stackTrace,
              context: 'CleanupOldCompanyStamp',
            );
          });
        }
      } else {
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
          final stampFormat =
              _companyStampFormat(_newCompanyStampBytes!) ?? 'png';
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

        final existingGuest =
            await PreferencesService.getGuestProfileData() ?? {};
        await PreferencesService.setGuestProfileData({
          ...existingGuest,
          'businessName': _businessNameController.text,
          'companyId': _companyIdController.text,
          'email': _emailController.text,
          'currency': normalizedCurrency,
          'contact1': _contact1Controller.text,
          'contact2': _contact2Controller.text,
          'address': _addressController.text,
          if (_profilePicUrl != null && _profilePicUrl!.isNotEmpty)
            'profilePic': _profilePicUrl!,
          if (_companyStampUrl != null && _companyStampUrl!.isNotEmpty)
            'companyStampUrl': _companyStampUrl!
          else
            'companyStampUrl': '',
        });
      }

      if (mounted) {
        setState(() => _isLoading = false);
        FlashySnackBar.show(context, message: 'profile_saved'.tr());
      }
      return true;
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'SaveProfile');
      if (!profileSaved) {
        final failedRef = uploadedRef;
        if (failedRef != null) {
          try {
            await failedRef.delete();
          } catch (_) {}
        }
        final failedStampRef = uploadedStampRef;
        if (failedStampRef != null) {
          try {
            await failedStampRef.delete();
          } catch (_) {}
        }
      }
      if (mounted) {
        setState(() => _isLoading = false);
        FlashySnackBar.show(
          context,
          message: 'error_saving_profile'.tr(
            namedArgs: {'error': error.toString()},
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
          if (mounted) {
            setState(() => _isEditing = true);
          }
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
                  backgroundColor: const Color(0xFF0247C4),
                  foregroundColor: const Color(0xFFFFFFFF),
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
                        width: 30,
                        height: 30,
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
                onTap: () {
                  final isGuest =
                      _authService.currentUser?.isAnonymous ?? false;
                  if (isGuest) {
                    showGuestRestrictionDialog(context);
                    return;
                  }
                  setState(() => _isEditing = true);
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FE),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SvgPicture.asset(
                    'assets/edit_icon.svg',
                    width: 20,
                    height: 20,
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF155ED5),
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
            color: const Color(0xFFF4F5F7),
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
      return const Icon(
        Icons.business_rounded,
        size: 40,
        color: Color(0xFF0247C4),
      );
    }

    Widget childWidget;
    if (hasNewBytes) {
      childWidget = Image.memory(
        _newProfileImageBytes!,
        width: 100,
        height: 100,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackIcon(),
      );
    } else if (hasNewPath) {
      childWidget = Image.file(
        File(_newProfileImagePath!),
        width: 100,
        height: 100,
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
        final decodedBytes = _decodeProfileDataImage(_profilePicUrl!);
        childWidget = decodedBytes == null
            ? _buildFallbackIcon()
            : Image.memory(
                decodedBytes,
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
        'assets/company_profile_placeholder.png',
        width: 100,
        height: 100,
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
                width: 25,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFF0247C4),
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
        border: Border.all(color: const Color(0xFFD8DCE5)),
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
            fontFamily: 'SF Pro Display',
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
            color: Color(0xFF6B7280),
            fontSize: 13,
            height: 1.35,
            fontFamily: 'SF Pro Display',
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
                  foregroundColor: const Color(0xFF155ED5),
                  side: const BorderSide(color: Color(0xFF155ED5)),
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
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                  ),
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
        Text(
          'company_stamp_signature'.tr(),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: Colors.black,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _isEditing
                ? const Color(0xFFFFFFFF)
                : const Color(0xFFEEEFF2),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFD8DCE5)),
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
            color: Color(0xFF6B7280),
            fontSize: 12,
            fontFamily: 'SF Pro Display',
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
    final Color bgColor = readOnly
        ? const Color(0xFFEEEFF2)
        : const Color(0xFFFFFFFF);
    final Color textColor = readOnly
        ? const Color(0xFF9CA3AF)
        : const Color(0xFF000000);
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    final hintText = isGuest
        ? isEmailField
              ? 'hint_enter_email'.tr()
              : isCompanyId
              ? 'hint_enter_company_id'.tr()
              : isBusinessName
              ? 'hint_enter_business_name'.tr()
              : isContact
              ? 'hint_enter_phone'.tr()
              : isAddress
              ? 'hint_enter_address'.tr()
              : ''
        : isEmailField
        ? 'hint_enter_email'.tr()
        : isCompanyId
        ? 'company_id_no'.tr()
        : isBusinessName
        ? 'company_name'.tr()
        : isContact
        ? 'hint_enter_phone'.tr()
        : isAddress
        ? 'hint_enter_address'.tr()
        : '';

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
                  inputFormatters:
                      isCompanyId || isContact || isBusinessName || isAddress
                      ? [
                          LengthLimitingTextInputFormatter(
                            isBusinessName
                                ? 30
                                : isAddress
                                ? 100
                                : 15,
                          ),
                          if (isContact)
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9+\-\s()]'),
                            ),
                          if (isCompanyId)
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[A-Z0-9-]'),
                            ),
                        ]
                      : null,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    hintText: hintText,
                    hintStyle: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 15,
                      fontFamily: 'SF Pro Display',
                    ),
                    counterText: '',
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
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
                  child: Text(
                    LocalizationHelper.localizeCurrency(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
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
          constraints: const BoxConstraints(),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
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
                      child: IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Color(0xFFFFFFFF),
                          size: 26,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                      ),
                    ),
                    Align(
                      alignment: Alignment(1.0, 0),
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
                        color: Color(0xFFFFFFFF),
                        shape: BoxShape.circle,
                        border: Border.all(color: Color(0xFFFFFFFF), width: 2),
                      ),
                      child: const ClipOval(child: UserAvatar(radius: 62)),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
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
                        ],
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
                          child: _buildPreviewCard(
                            'company_name'.tr(),
                            businessName,
                            'assets/preview_profile.svg',
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildPreviewCard(
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
                          child: _buildPreviewCard(
                            'company_email'.tr(),
                            email,
                            'assets/company_email.svg',
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildPreviewCard(
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
                          child: _buildPreviewCard(
                            'contact_no'.tr(),
                            contact1,
                            'assets/phone_preview.svg',
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildPreviewCard(
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

  Widget _buildPreviewCard(String label, String value, String svgPath) {
    return Container(
      height: 72,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
                      fontFamily: 'SF Pro Display',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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
                    fontFamily: 'SF Pro Display',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
