import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:pdfx/pdfx.dart';
import 'package:flutter/cupertino.dart' as import_cupertino;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import '../widgets/custom_dropdown_field.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/validators.dart';
import '../services/upload_service.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../services/dummy_data.dart';
import 'login_screen.dart';
import '../utils/snackbar_utils.dart';
import '../utils/date_utils.dart';
import '../utils/localization_helper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:webview_flutter/webview_flutter.dart';

const List<String> _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _localizedMonth(int month) {
  switch (month) {
    case 1:
      return 'month_january'.tr();
    case 2:
      return 'month_february'.tr();
    case 3:
      return 'month_march'.tr();
    case 4:
      return 'month_april'.tr();
    case 5:
      return 'month_may'.tr();
    case 6:
      return 'month_june'.tr();
    case 7:
      return 'month_july'.tr();
    case 8:
      return 'month_august'.tr();
    case 9:
      return 'month_september'.tr();
    case 10:
      return 'month_october'.tr();
    case 11:
      return 'month_november'.tr();
    case 12:
      return 'month_december'.tr();
    default:
      return '';
  }
}

// ==========================================
// ADD NEW WORKER FLOW (EXPERIENCE & DOCS)
// ==========================================
class AddNewWorkerFlow extends StatefulWidget {
  final VoidCallback? onBack;
  final Map<String, dynamic>? workerToEdit;

  const AddNewWorkerFlow({super.key, this.onBack, this.workerToEdit});

  @override
  State<AddNewWorkerFlow> createState() => _AddNewWorkerFlowState();
}

class _AddNewWorkerFlowState extends State<AddNewWorkerFlow> {
  int _activeTabIndex = 0;
  final _nameController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _religionController = TextEditingController();
  final _dobController = TextEditingController();
  final _genderController = TextEditingController(text: 'Male');
  final _addressController = TextEditingController();
  final _positionController = TextEditingController();
  final _type1Controller = TextEditingController(text: 'Full-Time');
  final _type2Controller = TextEditingController(text: 'On-Site');

  // Upgr``aded form controllers & state
  final _experienceLevelController = TextEditingController(text: 'Mid-Level');
  final _educationController = TextEditingController(text: 'Bachelor\'s');
  final _salaryTypeController = TextEditingController(text: 'Monthly');
  final _currencyController = TextEditingController(text: 'USD');
  final _salaryAmountController = TextEditingController();
  final _leavePolicyController = TextEditingController(text: 'Standard');
  final _annualLeavesController = TextEditingController();
  final _sickLeavesController = TextEditingController();
  final _casualLeavesController = TextEditingController();
  String _relationshipStatus = 'Single';

  // Upload states
  Uint8List? _profileImageBytes;
  String? _profileImageName;
  String? _existingProfileImageUrl;

  Uint8List? _frontIdBytes;
  String? _frontIdName;
  String? _existingFrontIdUrl;

  Uint8List? _backIdBytes;
  String? _backIdName;
  String? _existingBackIdUrl;

  Uint8List? _cvBytes;
  String? _cvName;
  String? _existingCvUrl;
  bool _isCvUploaded = false;

  String? _joiningDate;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Guest users should not access this screen directly
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (isGuest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      });
      return;
    }
    if (widget.workerToEdit != null) {
      _nameController.text = (widget.workerToEdit!['name'] ?? '').toString();
      _fatherNameController.text = (widget.workerToEdit!['fatherName'] ?? '')
          .toString();
      _emailController.text = (widget.workerToEdit!['email'] ?? '').toString();
      _phoneController.text = (widget.workerToEdit!['phone'] ?? '').toString();
      _nationalIdController.text = (widget.workerToEdit!['nationalId'] ?? '')
          .toString();
      _religionController.text = (widget.workerToEdit!['religion'] ?? '')
          .toString();
      _dobController.text = (widget.workerToEdit!['dob'] ?? '').toString();

      _genderController.text = (widget.workerToEdit!['gender'] ?? 'Male')
          .toString();
      if (_genderController.text.isEmpty) _genderController.text = 'Male';

      _addressController.text = (widget.workerToEdit!['address'] ?? '')
          .toString();
      _positionController.text = (widget.workerToEdit!['position'] ?? '')
          .toString();

      _type1Controller.text = (widget.workerToEdit!['type1'] ?? 'Full-Time')
          .toString();
      if (_type1Controller.text.isEmpty) _type1Controller.text = 'Full-Time';

      _type2Controller.text = (widget.workerToEdit!['type2'] ?? 'On-Site')
          .toString();
      if (_type2Controller.text.isEmpty) _type2Controller.text = 'On-Site';

      _experienceLevelController.text =
          (widget.workerToEdit!['experienceLevel'] ?? 'Mid-Level').toString();
      if (_experienceLevelController.text.isEmpty)
        _experienceLevelController.text = 'Mid-Level';

      _educationController.text =
          (widget.workerToEdit!['education'] ?? 'Bachelor\'s').toString();
      if (_educationController.text.isEmpty)
        _educationController.text = 'Bachelor\'s';

      _salaryTypeController.text =
          (widget.workerToEdit!['salaryType'] ?? 'Monthly').toString();
      if (_salaryTypeController.text.isEmpty)
        _salaryTypeController.text = 'Monthly';

      _currencyController.text = (widget.workerToEdit!['currency'] ?? 'USD')
          .toString();
      if (_currencyController.text.isEmpty) _currencyController.text = 'USD';

      _salaryAmountController.text =
          (widget.workerToEdit!['salaryAmount'] ?? '').toString();

      _leavePolicyController.text =
          (widget.workerToEdit!['leavePolicy'] ?? 'Standard').toString();
      if (_leavePolicyController.text.isEmpty)
        _leavePolicyController.text = 'Standard';

      _annualLeavesController.text =
          (widget.workerToEdit!['annualLeaves'] ?? '').toString();
      _sickLeavesController.text = (widget.workerToEdit!['sickLeaves'] ?? '')
          .toString();
      _casualLeavesController.text =
          (widget.workerToEdit!['casualLeaves'] ?? '').toString();

      _relationshipStatus =
          (widget.workerToEdit!['relationshipStatus'] ?? 'Single').toString();
      if (_relationshipStatus.isEmpty) _relationshipStatus = 'Single';

_existingProfileImageUrl = widget.workerToEdit!['profileImage']?.toString();

       // Backward/forward compatible keys:
       // Some worker documents may store id images under different key names.
       String? _firstNonEmpty(List<String?> values) {
         for (final v in values) {
           final s = v?.toString();
           if (s != null && s.isNotEmpty && s != 'null') return s;
         }
         return null;
       }

       _existingFrontIdUrl = _firstNonEmpty([
         widget.workerToEdit!['frontId']?.toString(),
         widget.workerToEdit!['front_id']?.toString(),
         widget.workerToEdit!['idFront']?.toString(),
         widget.workerToEdit!['frontID']?.toString(),
         widget.workerToEdit!['id_front']?.toString(),
       ]);
       if (_existingFrontIdUrl != null && _existingFrontIdUrl!.isNotEmpty) {
          _frontIdName = _cleanFileName(_existingFrontIdUrl!);
        }

      _existingFrontIdUrl = _firstNonEmpty([
        widget.workerToEdit!['frontId']?.toString(),
        widget.workerToEdit!['front_id']?.toString(),
        widget.workerToEdit!['idFront']?.toString(),
        widget.workerToEdit!['frontID']?.toString(),
        widget.workerToEdit!['id_front']?.toString(),
      ]);
      if (_existingFrontIdUrl != null && _existingFrontIdUrl!.isNotEmpty) {
        _frontIdName = _cleanFileName(_existingFrontIdUrl!);
      }

      _existingBackIdUrl = _firstNonEmpty([
        widget.workerToEdit!['backId']?.toString(),
        widget.workerToEdit!['back_id']?.toString(),
        widget.workerToEdit!['idBack']?.toString(),
        widget.workerToEdit!['backID']?.toString(),
        widget.workerToEdit!['id_back']?.toString(),
      ]);
      if (_existingBackIdUrl != null && _existingBackIdUrl!.isNotEmpty) {
        _backIdName = _cleanFileName(_existingBackIdUrl!);
      }

      _existingCvUrl = widget.workerToEdit!['cv']?.toString();
      if (_existingCvUrl != null && _existingCvUrl!.isNotEmpty) {
        _isCvUploaded = true;
        _cvName = _cleanFileName(_existingCvUrl!);
      }
      _joiningDate = widget.workerToEdit!['joiningDate']?.toString();
    } else {
      _loadDefaultCompanyCurrency();
    }
    // Do not auto-default joining date - user must explicitly set it.

    _nameController.addListener(_onControllerChanged);
    _nameController.addListener(() {
      if (_nameController.text.length > 50) {
        _nameController.text = _nameController.text.substring(0, 50);
        _nameController.selection = TextSelection.fromPosition(
          TextPosition(offset: _nameController.text.length),
        );
      }
    });
    _fatherNameController.addListener(_onControllerChanged);
    _fatherNameController.addListener(() {
      if (_fatherNameController.text.length > 50) {
        _fatherNameController.text = _fatherNameController.text.substring(
          0,
          50,
        );
        _fatherNameController.selection = TextSelection.fromPosition(
          TextPosition(offset: _fatherNameController.text.length),
        );
      }
    });
    _emailController.addListener(_onControllerChanged);
    _phoneController.addListener(_onControllerChanged);
    _nationalIdController.addListener(_onControllerChanged);
    _religionController.addListener(_onControllerChanged);
    _dobController.addListener(_onControllerChanged);
    _genderController.addListener(_onControllerChanged);
    _addressController.addListener(_onControllerChanged);
    _addressController.addListener(() {
      if (_addressController.text.length > 500) {
        _addressController.text = _addressController.text.substring(0, 500);
        _addressController.selection = TextSelection.fromPosition(
          TextPosition(offset: _addressController.text.length),
        );
      }
    });
    _positionController.addListener(_onControllerChanged);
    _positionController.addListener(() {
      if (_positionController.text.length > 60) {
        _positionController.text = _positionController.text.substring(0, 60);
        _positionController.selection = TextSelection.fromPosition(
          TextPosition(offset: _positionController.text.length),
        );
      }
    });
    _type1Controller.addListener(_onControllerChanged);
    _type2Controller.addListener(_onControllerChanged);
    _experienceLevelController.addListener(_onControllerChanged);
    _educationController.addListener(_onControllerChanged);
    _salaryTypeController.addListener(_onControllerChanged);
    _currencyController.addListener(_onControllerChanged);
    _salaryAmountController.addListener(_onControllerChanged);
    _leavePolicyController.addListener(_onControllerChanged);
    _annualLeavesController.addListener(_onControllerChanged);
    _sickLeavesController.addListener(_onControllerChanged);
    _casualLeavesController.addListener(_onControllerChanged);

    _sickLeavesController.addListener(_autoCalcAnnualLeaves);
    _casualLeavesController.addListener(_autoCalcAnnualLeaves);
    if (widget.workerToEdit == null) {
      _autoCalcAnnualLeaves();
    }
  }

  void _autoCalcAnnualLeaves() {
    if (_leavePolicyController.text == 'Custom') return;
    final sick = (int.tryParse(_sickLeavesController.text) ?? 0).clamp(0, 999);
    final casual = (int.tryParse(_casualLeavesController.text) ?? 0).clamp(
      0,
      999,
    );
    final sum = sick + casual;
    final sumText = sum.toString();
    final truncated = sumText.length > 3 ? sumText.substring(0, 3) : sumText;
    _annualLeavesController.value = TextEditingValue(
      text: truncated,
      selection: TextSelection.collapsed(offset: truncated.length),
    );
  }

  Future<void> _pickProfileImage() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty && mounted) {
        final file = result.files.first;
        if (file.bytes != null && file.bytes!.length > 10 * 1024 * 1024) {
          if (mounted) {
            FlashySnackBar.show(
              context,
              message: 'file_too_large'.tr(namedArgs: {'size': '10MB'}),
              isError: true,
            );
          }
          return;
        }
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = io.File(file.path!).readAsBytesSync();
        }
        setState(() {
          _profileImageBytes = bytes;
          _profileImageName = file.name;
        });
      }
    } catch (e) {
      debugPrint('Error picking profile image: $e');
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'failed_to_pick_image'.tr(),
          isError: true,
        );
      }
    }
  }

  Future<void> _pickFrontId() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty && mounted) {
        final file = result.files.first;
        if (file.bytes != null && file.bytes!.length > 10 * 1024 * 1024) {
          if (mounted) {
            FlashySnackBar.show(
              context,
              message: 'file_too_large'.tr(namedArgs: {'size': '10MB'}),
              isError: true,
            );
          }
          return;
        }
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = io.File(file.path!).readAsBytesSync();
        }
        setState(() {
          _frontIdBytes = bytes;
          _frontIdName = file.name;
        });
      }
    } catch (e) {
      debugPrint('Error picking front ID: $e');
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'failed_to_pick_file'.tr(),
          isError: true,
        );
      }
    }
  }

  Future<void> _pickBackId() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty && mounted) {
        final file = result.files.first;
        if (file.bytes != null && file.bytes!.length > 10 * 1024 * 1024) {
          if (mounted) {
            FlashySnackBar.show(
              context,
              message: 'file_too_large'.tr(namedArgs: {'size': '10MB'}),
              isError: true,
            );
          }
          return;
        }
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = io.File(file.path!).readAsBytesSync();
        }
        setState(() {
          _backIdBytes = bytes;
          _backIdName = file.name;
        });
      }
    } catch (e) {
      debugPrint('Error picking back ID: $e');
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'failed_to_pick_file'.tr(),
          isError: true,
        );
      }
    }
  }

  Future<void> _pickCv() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx'],
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty && mounted) {
        final file = result.files.first;
        if (file.bytes != null && file.bytes!.length > 20 * 1024 * 1024) {
          if (mounted) {
            FlashySnackBar.show(
              context,
              message: 'file_too_large'.tr(namedArgs: {'size': '20MB'}),
              isError: true,
            );
          }
          return;
        }
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = io.File(file.path!).readAsBytesSync();
        }
        setState(() {
          _cvBytes = bytes;
          _cvName = file.name;
          _isCvUploaded = true;
        });
      }
    } catch (e) {
      debugPrint('Error picking CV: $e');
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'failed_to_pick_file'.tr(),
          isError: true,
        );
      }
    }
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  DateTime? _validateAndParseDob() {
    final dobStr = _dobController.text.trim();
    if (dobStr.isEmpty) return DateTime.now();
    final dob = AppDateUtils.parseDateString(dobStr);
    if (dob == null) {
      FlashySnackBar.show(
        context,
        message: 'invalid_date_format'.tr(),
        title: 'validation_error'.tr(),
        isError: true,
      );
      return null;
    }
    final cutoff = DateTime.now().subtract(const Duration(days: 365 * 18));
    if (dob.isAfter(cutoff)) {
      FlashySnackBar.show(
        context,
        message: 'worker_must_be_18'.tr(),
        title: 'validation_error'.tr(),
        isError: true,
      );
      return null;
    }
    return dob;
  }

  Future<void> _loadDefaultCompanyCurrency() async {
    try {
      final profile = await FirestoreService().getUserProfile();
      if (profile != null && profile['currency'] != null) {
        final currency = profile['currency'].toString();
        if (currency.isNotEmpty) {
          setState(() {
            _currencyController.text = currency;
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to load company currency: $e');
    }
  }

  bool _hasChanges() {
    if (widget.workerToEdit == null) return true;
    final edit = widget.workerToEdit!;

    if (_nameController.text.trim() != (edit['name'] ?? '').toString().trim())
      return true;
    if (_fatherNameController.text.trim() !=
        (edit['fatherName'] ?? '').toString().trim())
      return true;
    if (_emailController.text.trim() != (edit['email'] ?? '').toString().trim())
      return true;
    if (_phoneController.text.trim() != (edit['phone'] ?? '').toString().trim())
      return true;
    if (_nationalIdController.text.trim() !=
        (edit['nationalId'] ?? '').toString().trim())
      return true;
    if (_religionController.text.trim() !=
        (edit['religion'] ?? '').toString().trim())
      return true;
    if (_dobController.text.trim() != (edit['dob'] ?? '').toString().trim())
      return true;
    if (_genderController.text.trim() !=
        (edit['gender'] ?? '').toString().trim())
      return true;
    if (_addressController.text.trim() !=
        (edit['address'] ?? '').toString().trim())
      return true;
    if (_relationshipStatus != (edit['relationshipStatus'] ?? 'Single'))
      return true;

    if (_positionController.text.trim() !=
        (edit['position'] ?? '').toString().trim())
      return true;
    if (_type1Controller.text.trim() != (edit['type1'] ?? '').toString().trim())
      return true;
    if (_type2Controller.text.trim() != (edit['type2'] ?? '').toString().trim())
      return true;
    if (_experienceLevelController.text.trim() !=
        (edit['experienceLevel'] ?? '').toString().trim())
      return true;
    if (_educationController.text.trim() !=
        (edit['education'] ?? '').toString().trim())
      return true;
    if (_salaryTypeController.text.trim() !=
        (edit['salaryType'] ?? '').toString().trim())
      return true;
    if (_currencyController.text.trim() !=
        (edit['currency'] ?? '').toString().trim())
      return true;
    if (_salaryAmountController.text.trim() !=
        (edit['salaryAmount'] ?? '').toString().trim())
      return true;
    if (_leavePolicyController.text.trim() !=
        (edit['leavePolicy'] ?? '').toString().trim())
      return true;
    if (_annualLeavesController.text.trim() !=
        (edit['annualLeaves'] ?? '').toString().trim())
      return true;
    if (_sickLeavesController.text.trim() !=
        (edit['sickLeaves'] ?? '').toString().trim())
      return true;
    if (_casualLeavesController.text.trim() !=
        (edit['casualLeaves'] ?? '').toString().trim())
      return true;

    final editJoiningDate = edit['joiningDate']?.toString();
    if (_joiningDate != editJoiningDate) return true;

    if (_profileImageBytes != null) return true;
    if (_frontIdBytes != null) return true;
    if (_backIdBytes != null) return true;
    if (_cvBytes != null) return true;

    final editCv = (edit['cv'] ?? '').toString();
    if (_isCvUploaded == false && editCv.isNotEmpty) return true;

    return false;
  }

  Future<void> _saveWorker() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_worker_name'.tr(),
        title: 'validation_error'.tr(),
        isError: true,
      );
      return;
    }

    if (phone.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_contact_number'.tr(),
        title: 'validation_error'.tr(),
        isError: true,
      );
      return;
    }

    if (email.isNotEmpty &&
        !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_valid_email'.tr(),
        title: 'validation_error'.tr(),
        isError: true,
      );
      return;
    }

    final hasFrontId =
        _frontIdBytes != null ||
        (_existingFrontIdUrl != null && _existingFrontIdUrl!.isNotEmpty);
    final hasBackId =
        _backIdBytes != null ||
        (_existingBackIdUrl != null && _existingBackIdUrl!.isNotEmpty);
    final hasCv =
        _cvBytes != null ||
        (_existingCvUrl != null && _existingCvUrl!.isNotEmpty);

    if (!hasFrontId) {
      FlashySnackBar.show(
        context,
        message: 'upload_cnic_front_required'.tr(),
        title: 'validation_error'.tr(),
        isError: true,
      );
      return;
    }

    if (!hasBackId) {
      FlashySnackBar.show(
        context,
        message: 'upload_cnic_back_required'.tr(),
        title: 'validation_error'.tr(),
        isError: true,
      );
      return;
    }

    if (!hasCv) {
      FlashySnackBar.show(
        context,
        message: 'upload_cv_required'.tr(),
        title: 'validation_error'.tr(),
        isError: true,
      );
      return;
    }

    final dob = _validateAndParseDob();
    if (dob == null) return;

    setState(() {
      _isSaving = true;
    });

    String? profileImageUrl = _existingProfileImageUrl;
    String? frontIdUrl = _existingFrontIdUrl;
    String? backIdUrl = _existingBackIdUrl;
    String? cvUrl = _existingCvUrl;

    final isGuest = AuthService().currentUser?.isAnonymous ?? false;

    try {
      if (isGuest) {
        if (_profileImageBytes != null) {
          profileImageUrl =
              'data:image/jpeg;base64,${base64Encode(_profileImageBytes!)}';
        }
        if (_frontIdBytes != null) {
          frontIdUrl = 'data:image/jpeg;base64,${base64Encode(_frontIdBytes!)}';
        }
        if (_backIdBytes != null) {
          backIdUrl = 'data:image/jpeg;base64,${base64Encode(_backIdBytes!)}';
        }
        if (_cvBytes != null) {
          cvUrl = 'data:application/pdf;base64,${base64Encode(_cvBytes!)}';
        }
      } else {
        final uploadFiles = <UploadFile>[];
        if (_profileImageBytes != null) {
          uploadFiles.add(UploadFile(
            folder: 'profile_images',
            fileName: _profileImageName ?? 'profile.jpg',
            bytes: _profileImageBytes!,
            mimeType: 'image/jpeg',
          ));
        }
        if (_frontIdBytes != null) {
          uploadFiles.add(UploadFile(
            folder: 'id_cards/front',
            fileName: _frontIdName ?? 'front.jpg',
            bytes: _frontIdBytes!,
            mimeType: 'image/jpeg',
          ));
        }
        if (_backIdBytes != null) {
          uploadFiles.add(UploadFile(
            folder: 'id_cards/back',
            fileName: _backIdName ?? 'back.jpg',
            bytes: _backIdBytes!,
            mimeType: 'image/jpeg',
          ));
        }
        if (_cvBytes != null) {
          uploadFiles.add(UploadFile(
            folder: 'cvs',
            fileName: _cvName ?? 'cv.pdf',
            bytes: _cvBytes!,
            mimeType: 'application/pdf',
          ));
        }

        if (uploadFiles.isNotEmpty) {
          final results = await UploadService.uploadFiles(
            files: uploadFiles,
          );

          for (final result in results) {
            if (result.isSuccess) {
              final url = result.url!;
              switch (result.file.folder) {
                case 'profile_images':
                  profileImageUrl = url;
                case 'id_cards/front':
                  frontIdUrl = url;
                case 'id_cards/back':
                  backIdUrl = url;
                case 'cvs':
                  cvUrl = url;
              }
            } else {
              if (mounted) {
                FlashySnackBar.show(
                  context,
                  message: 'file_upload_failed'
                      .tr(namedArgs: {'file': result.file.fileName}),
                  isError: true,
                );
              }
            }
          }
        }
      }

      final data = {
        'name': name,
        'fatherName': _fatherNameController.text.trim(),
        'email': email.isNotEmpty ? email : 'worker@email.com',
        'phone': phone,
        'nationalId': _nationalIdController.text.trim(),
        'religion': _religionController.text.trim(),
        'dob': _dobController.text.trim(),
        'gender': _genderController.text.trim(),
        'address': _addressController.text.trim(),
        'relationshipStatus': _relationshipStatus,
        'type1': _type1Controller.text.isNotEmpty
            ? _type1Controller.text
            : 'Full-Time',
        'position': _positionController.text.isNotEmpty
            ? _positionController.text.trim()
            : 'Employee',
        'type2': _type2Controller.text.isNotEmpty
            ? _type2Controller.text
            : 'On-Site',
        'experienceLevel': _experienceLevelController.text.trim(),
        'education': _educationController.text.trim(),
        'salaryType': _salaryTypeController.text.trim(),
        'currency': _currencyController.text.trim(),
        'salaryAmount': _salaryAmountController.text.trim(),
        'leavePolicy': _leavePolicyController.text.trim(),
        'annualLeaves': _annualLeavesController.text.trim(),
        'sickLeaves': _sickLeavesController.text.trim(),
        'casualLeaves': _casualLeavesController.text.trim(),
        'joiningDate':
            _joiningDate ?? DateFormat('MMMM d, yyyy').format(DateTime.now()),
        'profileImage': profileImageUrl,

        // Canonical keys (UI expects these):
        'frontId': frontIdUrl,
        'backId': backIdUrl,

        // Legacy keys (older docs / other screens might use these):
        'front_id': frontIdUrl,
        'back_id': backIdUrl,
        'idFront': frontIdUrl,
        'idBack': backIdUrl,
        'id_front': frontIdUrl,
        'id_back': backIdUrl,

        'cv': cvUrl,
      };

      if (widget.workerToEdit != null) {
        final editId = widget.workerToEdit!['id']?.toString();
        if (editId == null || editId.isEmpty) {
          if (mounted) {
            FlashySnackBar.show(
              context,
              message: 'could_not_save_worker'.tr(),
              isError: true,
            );
          }
          setState(() {
            _isSaving = false;
          });
          return;
        }
        if (isGuest) {
          final index = DummyData.workers.indexWhere((w) => w['id'] == editId);
          if (index != -1) {
            DummyData.workers[index] = {...data, 'id': editId};
          }
        } else {
          await FirestoreService().updateWorker(editId, data);
        }
      } else {
        if (isGuest) {
          final newId = 'dummy_${DateTime.now().millisecondsSinceEpoch}';
          DummyData.workers.insert(0, {...data, 'id': newId});
          await DummyData.saveToPrefs();
        } else {
          await FirestoreService().addWorker(data);
        }
      }

      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      if (!context.mounted) return;
      FlashySnackBar.show(
        context,
        message: 'worker_added_successfully'.tr(),
      );
      widget.onBack?.call();
    } on ValidationException catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        FlashySnackBar.show(
          context,
          message: e.message,
          isError: true,
        );
      }
    } catch (e) {
      debugPrint('Error saving worker: $e');
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        FlashySnackBar.show(
          context,
          message: 'could_not_save_worker'.tr(),
          isError: true,
        );
      }
    }
  }

  void _validateAndGoToExperience() {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    // Check required fields
    if (name.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_worker_name'.tr(),
        title: 'validation_error'.tr(),
        isError: true,
      );
      return;
    }

    if (phone.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_contact_number'.tr(),
        title: 'validation_error'.tr(),
        isError: true,
      );
      return;
    }

    if (email.isNotEmpty &&
        !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_valid_email'.tr(),
        title: 'validation_error'.tr(),
        isError: true,
      );
      return;
    }

    if (_validateAndParseDob() == null) return;

    setState(() => _activeTabIndex = 1);
  }

  void _validateAndGoToDocumentation() {
    final position = _positionController.text.trim();
    final salaryAmount = _salaryAmountController.text.trim();

    if (position.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_job_position'.tr(),
        title: 'validation_error'.tr(),
        isError: true,
      );
      return;
    }

    if (salaryAmount.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_salary_amount'.tr(),
        title: 'validation_error'.tr(),
        isError: true,
      );
      return;
    }

    if (_joiningDate == null || _joiningDate!.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_select_a_joining_date'.tr(),
        title: 'validation_error'.tr(),
        isError: true,
      );
      return;
    }

    setState(() => _activeTabIndex = 2);
  }

  String _cleanFileName(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      final oIndex = path.indexOf('/o/');
      String rawName;
      if (oIndex != -1) {
        final encodedPath = path.substring(oIndex + 3);
        final decoded = Uri.decodeComponent(encodedPath);
        rawName = decoded.split('/').last;
      } else {
        rawName = path.split('/').last;
      }
      final nameWithoutExt = rawName.contains('.')
          ? rawName.substring(0, rawName.lastIndexOf('.'))
          : rawName;
      if (RegExp(r'^\d{13}_').hasMatch(nameWithoutExt)) {
        return rawName.substring(14);
      }
      return rawName;
    } catch (_) {
      final name = url.split('/').last.split('?').first;
      final decoded = Uri.decodeComponent(name);
      final nameWithoutExt = decoded.contains('.')
          ? decoded.substring(0, decoded.lastIndexOf('.'))
          : decoded;
      if (RegExp(r'^\d{13}_').hasMatch(nameWithoutExt)) {
        return decoded.substring(14);
      }
      return decoded;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _fatherNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _nationalIdController.dispose();
    _religionController.dispose();
    _dobController.dispose();
    _genderController.dispose();
    _addressController.dispose();
    _positionController.dispose();
    _type1Controller.dispose();
    _type2Controller.dispose();
    _experienceLevelController.dispose();
    _educationController.dispose();
    _salaryTypeController.dispose();
    _currencyController.dispose();
    _salaryAmountController.dispose();
    _leavePolicyController.dispose();
    _annualLeavesController.dispose();
    _sickLeavesController.dispose();
    _casualLeavesController.dispose();
    _profileImageBytes?.fillRange(0, _profileImageBytes!.length, 0);
    _profileImageBytes = null;
    _frontIdBytes?.fillRange(0, _frontIdBytes!.length, 0);
    _frontIdBytes = null;
    _backIdBytes?.fillRange(0, _backIdBytes!.length, 0);
    _backIdBytes = null;
    _cvBytes?.fillRange(0, _cvBytes!.length, 0);
    _cvBytes = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF7F8FA), // Dashboard background
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header Area
          Container(
            height: 94,
            padding: const EdgeInsets.symmetric(horizontal: 40),
            decoration: const BoxDecoration(
              color: Color(0xFFFFFFFF),
              border: Border(
                bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => widget.onBack?.call(),
                      child: const Padding(
                        padding: EdgeInsets.only(top: 2.0),
                        child: Icon(
                          Icons.arrow_back_ios_new,
                          color: Color(0xFF000000),
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'add_new_worker'.tr(),
                          style: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'fill_worker_details'.tr(),
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // Save Button (Blue state based on image 2)
                Builder(
                  builder: (context) {
                    final bool isEditMode = widget.workerToEdit != null;
                    final bool hasChanges = _hasChanges();

                    final bool hasFrontId =
                        _frontIdBytes != null ||
                        (_existingFrontIdUrl != null &&
                            _existingFrontIdUrl!.isNotEmpty);
                    final bool hasCv =
                        _cvBytes != null ||
                        (_existingCvUrl != null && _existingCvUrl!.isNotEmpty);
                    final bool isSaveReady = isEditMode
                        ? hasChanges
                        : (_activeTabIndex == 2 &&
                              _nameController.text.trim().isNotEmpty &&
                              _phoneController.text.trim().isNotEmpty);
                    final bool canSave = isSaveReady && !_isSaving;

                    return GestureDetector(
                      onTap: canSave ? _saveWorker : null,
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        decoration: BoxDecoration(
                          color: isSaveReady
                              ? const Color(0xFF0B50C3)
                              : const Color(0xFFE6EAEF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: _isSaving
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
                                  color: isSaveReady
                                      ? const Color(0xFFFFFFFF)
                                      : const Color(0xFF555555),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Tabs and Form Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tabs Section
                  Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF000000).withValues(alpha: 0.02),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(child: _buildTopTab('worker_detail'.tr(), 0)),
                        Expanded(child: _buildTopTab('experience'.tr(), 1)),
                        Expanded(child: _buildTopTab('documentation'.tr(), 2)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Switch Content based on active tab
                  if (_activeTabIndex == 0)
                    WorkerDetailFormSection(
                      nameController: _nameController,
                      fatherNameController: _fatherNameController,
                      emailController: _emailController,
                      phoneController: _phoneController,
                      nationalIdController: _nationalIdController,
                      religionController: _religionController,
                      dobController: _dobController,
                      genderController: _genderController,
                      addressController: _addressController,
                      profileImageBytes: _profileImageBytes,
                      profileImageName: _profileImageName,
                      existingProfileImageUrl: _existingProfileImageUrl,
                      onUploadProfileTap: _pickProfileImage,
                      relationshipStatus: _relationshipStatus,
                      onRelationshipStatusChanged: (status) {
                        setState(() {
                          _relationshipStatus = status;
                        });
                      },
                      onNextStep: _validateAndGoToExperience,
                    ),
                  if (_activeTabIndex == 1)
                    ExperienceFormSection(
                      positionController: _positionController,
                      type1Controller: _type1Controller,
                      type2Controller: _type2Controller,
                      experienceLevelController: _experienceLevelController,
                      educationController: _educationController,
                      salaryTypeController: _salaryTypeController,
                      currencyController: _currencyController,
                      salaryAmountController: _salaryAmountController,
                      leavePolicyController: _leavePolicyController,
                      annualLeavesController: _annualLeavesController,
                      sickLeavesController: _sickLeavesController,
                      casualLeavesController: _casualLeavesController,
                      selectedJoiningDate: _joiningDate,
                      onJoiningDateChanged: (date) {
                        setState(() => _joiningDate = date);
                      },
                      onNextStep: _validateAndGoToDocumentation,
                      onPrevStep: () => setState(() => _activeTabIndex = 0),
                    ),
                  if (_activeTabIndex == 2)
                    DocumentationSection(
                      frontIdBytes: _frontIdBytes,
                      frontIdName: _frontIdName,
                      existingFrontIdUrl: _existingFrontIdUrl,
                      onUploadFrontTap: _pickFrontId,
                      backIdBytes: _backIdBytes,
                      backIdName: _backIdName,
                      existingBackIdUrl: _existingBackIdUrl,
                      onUploadBackTap: _pickBackId,
                      cvBytes: _cvBytes,
                      cvName: _cvName,
                      existingCvUrl: _existingCvUrl,
                      isCvUploaded: _isCvUploaded,
                      onUploadCvTap: _pickCv,
                      onDeleteCvTap: () {
                        setState(() {
                          _cvBytes = null;
                          _cvName = null;
                          _existingCvUrl = null;
                          _isCvUploaded = false;
                        });
                      },
                      onPrevStep: () => setState(() => _activeTabIndex = 1),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTab(String title, int index) {
    bool isActive = _activeTabIndex == index;
    BorderRadiusGeometry? borderRadius;
    if (isActive) {
      if (index == 0) {
        borderRadius = const BorderRadius.only(
          topLeft: Radius.circular(6),
          bottomLeft: Radius.circular(6),
        );
      } else if (index == 2) {
        borderRadius = const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        );
      }
    }
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFE8EEF9) : Colors.transparent,
        borderRadius: borderRadius,
      ),
      child: Text(
        title,
        style: TextStyle(
          color: const Color(0xFF000000),
          fontSize: 15,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          fontFamily: 'SF Pro Display',
        ),
      ),
    );
  }
}

// ==========================================
// WORKER DETAIL FORM SECTION
// ==========================================
class WorkerDetailFormSection extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController fatherNameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController nationalIdController;
  final TextEditingController religionController;
  final TextEditingController dobController;
  final TextEditingController genderController;
  final TextEditingController addressController;
  final VoidCallback? onNextStep;
  final Uint8List? profileImageBytes;
  final String? profileImageName;
  final String? existingProfileImageUrl;
  final VoidCallback? onUploadProfileTap;
  final String relationshipStatus;
  final ValueChanged<String> onRelationshipStatusChanged;

  const WorkerDetailFormSection({
    super.key,
    required this.nameController,
    required this.fatherNameController,
    required this.emailController,
    required this.phoneController,
    required this.nationalIdController,
    required this.religionController,
    required this.dobController,
    required this.genderController,
    required this.addressController,
    this.onNextStep,
    this.profileImageBytes,
    this.profileImageName,
    this.existingProfileImageUrl,
    this.onUploadProfileTap,
    required this.relationshipStatus,
    required this.onRelationshipStatusChanged,
  });

  final Color formBgGrey = const Color(0xFFF3F5F8);

  void _showCupertinoDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required ValueChanged<DateTime> onDateSelected,
  }) {
    DateTime tempPickedDate = initialDate;
    showDialog(
      context: context,
      builder: (BuildContext builder) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 320,
            height: 300,
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    import_cupertino.CupertinoButton(
                      child: Text(
                        'cancel'.tr(),
                        style: TextStyle(color: Colors.red),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    import_cupertino.CupertinoButton(
                      child: Text(
                        'done'.tr(),
                        style: TextStyle(color: Color(0xFF0247C4)),
                      ),
                      onPressed: () {
                        onDateSelected(tempPickedDate);
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
                Expanded(
                  child: import_cupertino.CupertinoDatePicker(
                    mode: import_cupertino.CupertinoDatePickerMode.date,
                    initialDateTime: initialDate,
                    minimumDate: DateTime(1950),
                    maximumDate: DateTime.now().subtract(
                      const Duration(days: 365 * 18),
                    ),
                    onDateTimeChanged: (DateTime newDate) {
                      tempPickedDate = newDate;
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sub-header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'personal_information'.tr(),
              style: TextStyle(
                color: Color(0xFF000000),
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFamily: 'SF Pro Display',
              ),
            ),
            GestureDetector(
              onTap: onNextStep,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F9FD),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
                ),
                child: Row(
                  children: [
                    Text(
                      'next_step'.tr(),
                      style: const TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward,
                      size: 18,
                      color: Color(0xFF000000),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: formBgGrey,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputField(
                            'worker_name_label'.tr(),
                            'enter_your_name'.tr(),
                            controller: nameController,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildInputField(
                            'worker_father_husband_name'.tr(),
                            'enter_your_name'.tr(),
                            controller: fatherNameController,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputField(
                            'worker_email'.tr(),
                            'enter_your_email'.tr(),
                            controller: emailController,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildInputField(
                            'contact_no_label'.tr(),
                            'enter_contact_number'.tr(),
                            controller: phoneController,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputField(
                            'national_id'.tr(),
                            'hint_enter_national_id'.tr(),
                            controller: nationalIdController,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildInputField(
                            'professed_religion'.tr(),
                            'enter_your_religion'.tr(),
                            controller: religionController,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              _showCupertinoDatePicker(
                                context: context,
                                initialDate: DateTime.now().subtract(
                                  const Duration(days: 365 * 18),
                                ),
                                onDateSelected: (date) {
                                  final day = date.day.toString().padLeft(
                                    2,
                                    '0',
                                  );
                                  final month = date.month.toString().padLeft(
                                    2,
                                    '0',
                                  );
                                  final year = date.year.toString();
                                  dobController.text = '$day/$month/$year';
                                },
                              );
                            },
                            child: AbsorbPointer(
                              child: _buildInputField(
                                'worker_dob'.tr(),
                                'date_format'.tr(),
                                suffixIcon: Icons.calendar_month,
                                controller: dobController,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildDropdownField(
                            label: 'gender_label'.tr(),
                            selectedValue: genderController.text,
                            hint: 'enter_gender'.tr(),
                            items: const ['Male', 'Female', 'Other'],
                            itemLabelBuilder: (val) => _localizeGender(val),
                            onChanged: (val) {
                              if (val != null) {
                                genderController.text = val;
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildInputField(
                      'worker_address'.tr(),
                      'enter_your_address'.tr(),
                      isTextArea: true,
                      controller: addressController,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 32),

            // === RIGHT: Profile Upload & Status ===
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile Upload Section
                  Text(
                    'worker_profile'.tr(),
                    style: TextStyle(
                      color: Color(0xFF000000),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: onUploadProfileTap,
                    child: Container(
                      height: 280,
                      width: double.infinity,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF000000,
                            ).withValues(alpha: 0.01),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: _buildProfileContent(),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Relationship Status Section
                  Text(
                    'relationship_status'.tr(),
                    style: TextStyle(
                      color: Color(0xFF000000),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildCustomRadio(
                        label: 'married'.tr(),
                        isSelected: relationshipStatus == 'Married',
                        onTap: () => onRelationshipStatusChanged('Married'),
                      ),
                      const SizedBox(width: 40),
                      _buildCustomRadio(
                        label: 'single'.tr(),
                        isSelected: relationshipStatus == 'Single',
                        onTap: () => onRelationshipStatusChanged('Single'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProfileContent() {
    final hasImageBytes = profileImageBytes != null;
    final hasImageUrl =
        existingProfileImageUrl != null && existingProfileImageUrl!.isNotEmpty;

    if (!hasImageBytes && !hasImageUrl) return _buildUploadPlaceholder();

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasImageBytes)
          Image.memory(
            profileImageBytes!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildUploadPlaceholder(),
          )
        else
          Image(
            image: getProfileImageProvider(existingProfileImageUrl),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildUploadPlaceholder(),
          ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: Colors.black.withOpacity(0.54),
            child: Text(
              profileImageName ?? 'Profile Image',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset('assets/Upload_profile.svg', height: 64, width: 64),
        const SizedBox(height: 12),
        Text(
          'upload_profile'.tr(),
          style: TextStyle(
            color: Color(0xFF000000),
            fontWeight: FontWeight.w700,
            fontSize: 14,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'tap_to_upload_profile_image'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.black.withOpacity(0.54),
            fontSize: 12,
            fontWeight: FontWeight.w500,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ],
    );
  }

  String _localizeGender(String value) =>
      LocalizationHelper.localizeGender(value);
}

// ==========================================
// EXPERIENCE SECTION (IMAGE 1 + CUSTOM LEAVE)
// ==========================================
class ExperienceFormSection extends StatefulWidget {
  final TextEditingController positionController;
  final TextEditingController type1Controller;
  final TextEditingController type2Controller;
  final TextEditingController experienceLevelController;
  final TextEditingController educationController;
  final TextEditingController salaryTypeController;
  final TextEditingController currencyController;
  final TextEditingController salaryAmountController;
  final TextEditingController leavePolicyController;
  final TextEditingController annualLeavesController;
  final TextEditingController sickLeavesController;
  final TextEditingController casualLeavesController;
  final String? selectedJoiningDate;
  final ValueChanged<String>? onJoiningDateChanged;
  final VoidCallback? onNextStep;
  final VoidCallback? onPrevStep;

  const ExperienceFormSection({
    super.key,
    required this.positionController,
    required this.type1Controller,
    required this.type2Controller,
    required this.experienceLevelController,
    required this.educationController,
    required this.salaryTypeController,
    required this.currencyController,
    required this.salaryAmountController,
    required this.leavePolicyController,
    required this.annualLeavesController,
    required this.sickLeavesController,
    required this.casualLeavesController,
    this.selectedJoiningDate,
    this.onJoiningDateChanged,
    this.onNextStep,
    this.onPrevStep,
  });

  @override
  State<ExperienceFormSection> createState() => _ExperienceFormSectionState();
}

class _ExperienceFormSectionState extends State<ExperienceFormSection> {
  final Color formBgGrey = const Color(0xFFF3F5F8);
  late DateTime _calendarMonth;
  DateTime? _selectedDate;
  DateTime? _initialDate;

  @override
  void initState() {
    super.initState();
    _parseSelectedDate();
  }

  @override
  void didUpdateWidget(covariant ExperienceFormSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedJoiningDate != oldWidget.selectedJoiningDate) {
      _parseSelectedDate();
    }
  }

  String _localizeType1(String value) =>
      LocalizationHelper.localizeType1(value);
  String _localizeType2(String value) =>
      LocalizationHelper.localizeType2(value);
  String _localizeExperience(String value) =>
      LocalizationHelper.localizeExperience(value);
  String _localizeEducation(String value) =>
      LocalizationHelper.localizeEducation(value);
  String _localizeSalaryType(String value) =>
      LocalizationHelper.localizeSalaryType(value);
  String _localizeCurrency(String value) =>
      LocalizationHelper.localizeCurrency(value);
  String _localizeLeavePolicy(String value) =>
      LocalizationHelper.localizeLeavePolicy(value);

  void _parseSelectedDate() {
    if (widget.selectedJoiningDate != null &&
        widget.selectedJoiningDate!.isNotEmpty) {
      try {
        final dateStr = widget.selectedJoiningDate!;
        final parts = dateStr.split(' ');
        if (parts.length >= 3) {
          final monthName = parts[0];
          final day = int.parse(parts[1].replaceAll(',', ''));
          final year = int.parse(parts[2]);
          final monthIndex = _months.indexWhere(
            (m) => m.toLowerCase() == monthName.toLowerCase(),
          );
          if (monthIndex != -1) {
            setState(() {
              _selectedDate = DateTime(year, monthIndex + 1, day);
              _calendarMonth = DateTime(year, monthIndex + 1, 1);
              _initialDate = _selectedDate;
            });
            return;
          }
        }
      } catch (e) {
        debugPrint('Error parsing joining date: $e');
      }
    }
    setState(() {
      _selectedDate = DateTime.now();
      _calendarMonth = DateTime(_selectedDate!.year, _selectedDate!.month, 1);
      _initialDate = _selectedDate;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sub-header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'job_experience_info'.tr(),
              style: TextStyle(
                color: Color(0xFF000000),
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFamily: 'SF Pro Display',
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onPrevStep != null) ...[
                  GestureDetector(
                    onTap: widget.onPrevStep,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F9FD),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFE0E0E0),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.arrow_back,
                            size: 18,
                            color: Color(0xFF000000),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'previous_step'.tr(),
                            style: const TextStyle(
                              color: Color(0xFF000000),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                GestureDetector(
                  onTap: widget.onNextStep,
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F9FD),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFFE0E0E0),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'next_step'.tr(),
                          style: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward,
                          size: 18,
                          color: Color(0xFF000000),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Main Grid & Right Panel (Calendar)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Form
            Expanded(
              flex: 5,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: formBgGrey,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputField(
                            'job_position_label'.tr(),
                            'enter_your_level'.tr(),
                            controller: widget.positionController,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildDropdownField(
                            label: 'experience_level_label'.tr(),
                            selectedValue:
                                widget.experienceLevelController.text,
                            hint: 'enter_your_level'.tr(),
                            items: const [
                              'Fresher',
                              'Junior',
                              'Mid-Level',
                              'Senior',
                            ],
                            itemLabelBuilder: (val) => _localizeExperience(val),
                            onChanged: (val) {
                              if (val != null) {
                                widget.experienceLevelController.text = val;
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdownField(
                            label: 'work_type_label'.tr(),
                            selectedValue: widget.type1Controller.text,
                            hint: 'enter_your_work'.tr(),
                            items: const [
                              'Full-Time',
                              'Part-Time',
                              'Contract',
                              'Freelance',
                            ],
                            itemLabelBuilder: (val) => _localizeType1(val),
                            onChanged: (val) {
                              if (val != null) {
                                widget.type1Controller.text = val;
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildDropdownField(
                            label: 'education_label'.tr(),
                            selectedValue: widget.educationController.text,
                            hint: 'enter_your_education'.tr(),
                            items: const [
                              'Matric',
                              'Intermediate',
                              'Bachelor',
                              'Master',
                              'Other',
                            ],
                            itemLabelBuilder: (val) => _localizeEducation(val),
                            onChanged: (val) {
                              if (val != null) {
                                widget.educationController.text = val;
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdownField(
                            label: 'attendance_type_label'.tr(),
                            selectedValue: widget.type2Controller.text,
                            hint: 'enter_your_attendance_type'.tr(),
                            items: const ['On-Site', 'Remote', 'Hybrid'],
                            itemLabelBuilder: (val) => _localizeType2(val),
                            onChanged: (val) {
                              if (val != null) {
                                widget.type2Controller.text = val;
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 24),
                        const Expanded(
                          child: SizedBox(),
                        ), // Empty space to match image
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 32),
            // Right Calendar
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'joining_date_set'.tr(),
                    style: TextStyle(
                      color: Color(0xFF000000),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF000000).withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _calendarMonth = DateTime(
                                    _calendarMonth.year,
                                    _calendarMonth.month - 1,
                                    1,
                                  );
                                });
                              },
                              child: const Icon(
                                Icons.keyboard_arrow_left,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 20),
                            Text(
                              '${DateFormat('MMMM', context.locale.toString()).format(_calendarMonth).toUpperCase()}${_calendarMonth.year}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                letterSpacing: 1.0,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                            const SizedBox(width: 20),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _calendarMonth = DateTime(
                                    _calendarMonth.year,
                                    _calendarMonth.month + 1,
                                    1,
                                  );
                                });
                              },
                              child: const Icon(
                                Icons.keyboard_arrow_right,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Center(
                                child: _buildDayPill('weekday_sun'.tr(), true),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: _buildDayPill('weekday_mon'.tr(), false),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: _buildDayPill('weekday_tue'.tr(), false),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: _buildDayPill('weekday_wed'.tr(), false),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: _buildDayPill('weekday_thu'.tr(), false),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: _buildDayPill(
                                  'weekday_fri'.tr(),
                                  false,
                                  isGreen: true,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: _buildDayPill('weekday_sat'.tr(), false),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Calendar Grid View (CrossAxisCount 7 for perfect column alignment)
                        Builder(
                          builder: (context) {
                            final firstDay = DateTime(
                              _calendarMonth.year,
                              _calendarMonth.month,
                              1,
                            );
                            final firstWeekday = firstDay.weekday;
                            final daysInMonth = DateTime(
                              _calendarMonth.year,
                              _calendarMonth.month + 1,
                              0,
                            ).day;
                            final padCount = firstWeekday == 7
                                ? 0
                                : firstWeekday;

                            return GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 7,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              children: [
                                for (int i = 0; i < padCount; i++)
                                  const SizedBox.shrink(),
                                for (int day = 1; day <= daysInMonth; day++)
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedDate = DateTime(
                                          _calendarMonth.year,
                                          _calendarMonth.month,
                                          day,
                                        );
                                      });
                                    },
                                    child: Builder(
                                      builder: (context) {
                                        final isSelected =
                                            _selectedDate != null &&
                                            _selectedDate!.year ==
                                                _calendarMonth.year &&
                                            _selectedDate!.month ==
                                                _calendarMonth.month &&
                                            _selectedDate!.day == day;
                                        return Container(
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFF0B50C3)
                                                : Color(0xFFFFFFFF),
                                            border: isSelected
                                                ? null
                                                : Border.all(
                                                    color: Colors.grey.shade300,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            '$day',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: isSelected
                                                  ? Color(0xFFFFFFFF)
                                                  : Colors.black,
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.w500,
                                              fontFamily: 'SF Pro Display',
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (_initialDate != null) {
                                    _selectedDate = _initialDate;
                                    _calendarMonth = DateTime(
                                      _initialDate!.year,
                                      _initialDate!.month,
                                      1,
                                    );
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'cancel'.tr(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                if (_selectedDate != null) {
                                  final monthName = _localizedMonth(
                                    _selectedDate!.month,
                                  );
                                  final formatted =
                                      '$monthName ${_selectedDate!.day}, ${_selectedDate!.year}';
                                  widget.onJoiningDateChanged?.call(formatted);
                                  setState(() {
                                    _initialDate = _selectedDate;
                                  });
                                  FlashySnackBar.show(
                                    context,
                                    message: 'joining_date_is'.tr(
                                      namedArgs: {'date': formatted},
                                    ),
                                    isError: false,
                                  );
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0B50C3),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'set'.tr(),
                                  style: TextStyle(
                                    color: Color(0xFFFFFFFF),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
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
          ],
        ),
        const SizedBox(height: 40),

        // Salary Section
        Text(
          'salary_section'.tr(),
          style: TextStyle(
            color: Color(0xFF000000),
            fontSize: 20,
            fontWeight: FontWeight.w800,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: formBgGrey,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildDropdownField(
                      label: 'salary_type_label'.tr(),
                      selectedValue: widget.salaryTypeController.text,
                      hint: 'enter_your_salary_type'.tr(),
                      items: const ['Monthly', 'Hourly', 'Contract'],
                      itemLabelBuilder: (val) => _localizeSalaryType(val),
                      onChanged: (val) {
                        if (val != null) {
                          widget.salaryTypeController.text = val;
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: _buildDropdownField(
                      label: 'currency_label'.tr(),
                      selectedValue: widget.currencyController.text,
                      hint: 'enter_your_currency'.tr(),
                      items: const [
                        'USD',
                        'EUR',
                        'GBP',
                        'JPY',
                        'INR',
                        'RUB',
                        'BRL',
                        'SAR',
                      ],
                      itemLabelBuilder: (val) => _localizeCurrency(val),
                      onChanged: (val) {
                        if (val != null) {
                          widget.currencyController.text = val;
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      'salary_amount_label'.tr(),
                      'enter_your_amount'.tr(),
                      controller: widget.salaryAmountController,
                    ),
                  ),
                  const SizedBox(width: 24),
                  const Expanded(child: SizedBox()), // empty
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),

        // Custom Leave Section (As Requested by user)
        Text(
          'leave_section'.tr(),
          style: TextStyle(
            color: Color(0xFF000000),
            fontSize: 20,
            fontWeight: FontWeight.w800,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: formBgGrey,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildDropdownField(
                      label: 'leave_policy_label'.tr(),
                      selectedValue: widget.leavePolicyController.text,
                      hint: 'enter_leave_policy'.tr(),
                      items: const ['Standard', 'Custom', 'Sick/Casual Only'],
                      itemLabelBuilder: (val) => _localizeLeavePolicy(val),
                      onChanged: (val) {
                        if (val != null) {
                          widget.leavePolicyController.text = val;
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: _buildInputField(
                      'annual_leaves_days'.tr(),
                      'hint_annual_leaves'.tr(),
                      controller: widget.annualLeavesController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      'sick_leaves_days'.tr(),
                      'hint_sick_leaves'.tr(),
                      controller: widget.sickLeavesController,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: _buildInputField(
                      'casual_leaves_days'.tr(),
                      'hint_casual_leaves'.tr(),
                      controller: widget.casualLeavesController,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 60),
      ],
    );
  }

  Widget _buildDayPill(String text, bool isRed, {bool isGreen = false}) {
    Color bg = isRed
        ? Colors.red
        : (isGreen ? Colors.green : const Color(0xFF0B50C3));
    final display = text.length > 3 ? text.substring(0, 3) : text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        display,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 8,
          fontWeight: FontWeight.bold,
          fontFamily: 'SF Pro Display',
        ),
      ),
    );
  }
}

// ==========================================
// DOCUMENTATION SECTION (IMAGE 2)
// ==========================================
class DocumentationSection extends StatelessWidget {
  final Uint8List? frontIdBytes;
  final String? frontIdName;
  final String? existingFrontIdUrl;
  final VoidCallback? onUploadFrontTap;

  final Uint8List? backIdBytes;
  final String? backIdName;
  final String? existingBackIdUrl;
  final VoidCallback? onUploadBackTap;

  final Uint8List? cvBytes;
  final String? cvName;
  final String? existingCvUrl;
  final bool isCvUploaded;
  final VoidCallback? onUploadCvTap;
  final VoidCallback? onDeleteCvTap;
  final VoidCallback? onPrevStep;

  const DocumentationSection({
    super.key,
    this.frontIdBytes,
    this.frontIdName,
    this.existingFrontIdUrl,
    this.onUploadFrontTap,
    this.backIdBytes,
    this.backIdName,
    this.existingBackIdUrl,
    this.onUploadBackTap,
    this.cvBytes,
    this.cvName,
    this.existingCvUrl,
    this.isCvUploaded = false,
    this.onUploadCvTap,
    this.onDeleteCvTap,
    this.onPrevStep,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'personal_documentation'.tr(),
              style: TextStyle(
                color: Color(0xFF000000),
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFamily: 'SF Pro Display',
              ),
            ),
            if (onPrevStep != null)
              GestureDetector(
                onTap: onPrevStep,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9F9FD),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFFE0E0E0),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.arrow_back,
                        size: 18,
                        color: Color(0xFF000000),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'previous_step'.tr(),
                        style: const TextStyle(
                          color: Color(0xFF000000),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Side: ID Card Upload
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'id_card_label'.tr(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F5F8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'upload_front_side'.tr(),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildIdUploadBox(
                          label: 'upload_front_id_hint'.tr(),
                          bytes: frontIdBytes,
                          fileName: frontIdName,
                          existingUrl: existingFrontIdUrl,
                          onTap: onUploadFrontTap,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'upload_back_side'.tr(),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildIdUploadBox(
                          label: 'upload_back_id_hint'.tr(),
                          bytes: backIdBytes,
                          fileName: backIdName,
                          existingUrl: existingBackIdUrl,
                          onTap: onUploadBackTap,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 32),
            // Right Side: CV Upload Preview
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'upload_cv_label'.tr(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 16),
                  isCvUploaded ? _buildCvPreview(context) : _buildCvUpload(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIdUploadBox({
    required String label,
    Uint8List? bytes,
    String? fileName,
    String? existingUrl,
    VoidCallback? onTap,
  }) {
    final bool hasFile =
        bytes != null || (existingUrl != null && existingUrl.isNotEmpty);
    final bool isPdf =
        (fileName != null && fileName.toLowerCase().endsWith('.pdf')) ||
        (existingUrl != null && existingUrl.toLowerCase().endsWith('.pdf'));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 200,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: hasFile
                ? const Color(0xFF0B50C3).withValues(alpha: 0.5)
                : Colors.grey.shade200,
            width: hasFile ? 2 : 1,
          ),
        ),
        child: hasFile
            ? Stack(
                fit: StackFit.expand,
                children: [
                  if (isPdf)
                    Container(
                      color: Colors.white,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.picture_as_pdf,
                            color: Color(0xFFE53935),
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              fileName ?? 'pdf_document'.tr(),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    )
                  else if (bytes != null)
                    Image.memory(bytes, fit: BoxFit.cover)
                  else if (existingUrl != null &&
                      existingUrl.startsWith('http'))
                    CachedNetworkImage(
                      imageUrl: existingUrl,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) =>
                          _buildIdPlaceholder(label, hasFile),
                    )
                  else if (existingUrl != null &&
                      existingUrl.startsWith('data:image'))
                    Image.memory(
                      base64Decode(existingUrl.split(',').last),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildIdPlaceholder(label, hasFile),
                    )
                  else
                    _buildIdPlaceholder(label, hasFile),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      color: Colors.black.withOpacity(0.54),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Colors.greenAccent,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              fileName ?? 'file_uploaded'.tr(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : _buildIdPlaceholder(label, false),
      ),
    );
  }

  Widget _buildIdPlaceholder(String label, bool hasFile) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.badge,
          size: 48,
          color: hasFile ? const Color(0xFF0B50C3) : Colors.grey.shade400,
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'tap_to_select_file'.tr(),
          style: TextStyle(
            color: Colors.grey.shade300,
            fontSize: 12,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ],
    );
  }

  Widget _buildCvUpload() {
    return _buildCvContainer(
      overlay: GestureDetector(
        onTap: onUploadCvTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF000000),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'upload'.tr(),
                style: TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              const SizedBox(width: 8),
              SvgPicture.asset(
                'assets/Upload_profile.svg',
                height: 18,
                width: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDocumentPreview(BuildContext context) {
    final isImage =
        cvName != null &&
        (cvName!.toLowerCase().endsWith('.png') ||
            cvName!.toLowerCase().endsWith('.jpg') ||
            cvName!.toLowerCase().endsWith('.jpeg'));
    final isPdf =
        cvName != null && cvName!.toLowerCase().endsWith('.pdf');
    final isDoc =
        cvName != null &&
        (cvName!.toLowerCase().endsWith('.doc') ||
            cvName!.toLowerCase().endsWith('.docx'));

    if (isDoc) {
      String? fileUrl;
      if (existingCvUrl != null && existingCvUrl!.isNotEmpty) {
        fileUrl = existingCvUrl;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _DocPreviewScreen(
            fileUrl: fileUrl,
            fileName: cvName,
            cvBytes: cvBytes,
          ),
        ),
      );
      return;
    }

    if (!isImage && !isPdf) {
      if (existingCvUrl != null && existingCvUrl!.isNotEmpty) {
        launchUrl(
          Uri.parse(existingCvUrl!),
          mode: LaunchMode.externalApplication,
        );
      } else if (cvBytes != null && cvName != null) {
        try {
          final tempDir = io.Directory.systemTemp;
          final tempFile = io.File('${tempDir.path}/$cvName');
          tempFile.writeAsBytesSync(cvBytes!);
          launchUrl(
            Uri.file(tempFile.path),
            mode: LaunchMode.externalApplication,
          );
        } catch (e) {
          debugPrint('Error opening CV preview: $e');
        }
      }
      return;
    }

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: MediaQuery.of(ctx).size.width * 0.9,
              height: MediaQuery.of(ctx).size.height * 0.85,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    color: const Color(0xFFF5F5F5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            cvName ?? 'CV',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'SF Pro Display',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 22),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: isImage
                        ? InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 4.0,
                            child: cvBytes != null
                                ? Image.memory(cvBytes!, fit: BoxFit.contain)
                                : CachedNetworkImage(
                                    imageUrl: existingCvUrl ?? '',
                                    fit: BoxFit.contain,
                                    errorWidget: (context, url, error) =>
                                        const Center(
                                      child: Icon(Icons.broken_image,
                                          size: 48),
                                    ),
                                  ),
                          )
                        : PdfPagePreview(
                            cvBytes: cvBytes,
                            existingCvUrl: existingCvUrl,
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCvPreview(BuildContext buildContext) {
    final isImage =
        cvName != null &&
        (cvName!.toLowerCase().endsWith('.png') ||
            cvName!.toLowerCase().endsWith('.jpg') ||
            cvName!.toLowerCase().endsWith('.jpeg'));
    final isPdf =
        cvName != null && cvName!.toLowerCase().endsWith('.pdf');
    final isDoc =
        cvName != null &&
        (cvName!.toLowerCase().endsWith('.doc') ||
            cvName!.toLowerCase().endsWith('.docx'));

    return Container(
      height: 580,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 24,
            bottom: 24,
            left: 24,
            right: 24,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: isImage
                  ? GestureDetector(
                      onTap: () => _openDocumentPreview(buildContext),
                      child: cvBytes != null
                          ? Image.memory(
                              cvBytes!,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.high,
                            )
                          : (existingCvUrl != null &&
                                    existingCvUrl!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: existingCvUrl!,
                                    fit: BoxFit.cover,
                                    errorWidget:
                                        (context, url, error) =>
                                            const Center(
                                              child: Icon(
                                                Icons.broken_image,
                                                size: 48,
                                              ),
                                            ),
                                  )
                                : const SizedBox.shrink()),
                    )
                  : (isPdf || isDoc)
                      ? ImageFiltered(
                          imageFilter:
                              ui.ImageFilter.blur(sigmaX: 1.0, sigmaY: 1.0),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (cvBytes == null &&
                                  (existingCvUrl == null ||
                                      existingCvUrl!.isEmpty))
                                Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        height: 16,
                                        width: 150,
                                        color: Colors.grey.shade200,
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        height: 10,
                                        width: 100,
                                        color: Colors.grey.shade200,
                                      ),
                                      const SizedBox(height: 40),
                                      ...List.generate(
                                        6,
                                        (index) => Padding(
                                          padding: const EdgeInsets.only(
                                              bottom: 12),
                                          child: Container(
                                            height: 10,
                                            width: double.infinity,
                                            color: Colors.grey.shade200,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (isPdf &&
                                  (cvBytes != null ||
                                      (existingCvUrl != null &&
                                          existingCvUrl!.isNotEmpty)))
                                Positioned.fill(
                                  child: PdfPagePreview(
                                    cvBytes: cvBytes,
                                    existingCvUrl: existingCvUrl,
                                  ),
                                ),
                              if (isDoc)
                                Positioned.fill(
                                  child: DocPagePreview(
                                    fileUrl: existingCvUrl,
                                    cvBytes: cvBytes,
                                    fileName: cvName,
                                  ),
                                ),
                              Positioned.fill(
                                child: GestureDetector(
                                  onTap: () =>
                                      _openDocumentPreview(buildContext),
                                  behavior: HitTestBehavior.opaque,
                                ),
                              ),
                            ],
                          ),
                        )
                      : GestureDetector(
                          onTap: () => _openDocumentPreview(buildContext),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.insert_drive_file,
                                  size: 64,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  cvName ?? 'CV',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
            ),
          ),

          // Centered controls overlay (Edit / Delete) in the middle of the preview container
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: onUploadCvTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF000000),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'edit'.tr(),
                          style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const SizedBox(width: 8),
                        SvgPicture.asset(
                          'assets/edit_icon.svg',
                          height: 18,
                          width: 18,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: onDeleteCvTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF000000),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'delete'.tr(),
                          style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const SizedBox(width: 8),
                        SvgPicture.asset(
                          'assets/delete_icon.svg',
                          height: 18,
                          width: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCvContainer({required Widget overlay}) {
    return Container(
      height: 580,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    height: 16,
                    width: 200,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 10,
                    width: 150,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 40),
                  ...List.generate(
                    8,
                    (index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        height: 12,
                        width: double.infinity,
                        color: Colors.grey.shade300,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(color: const Color(0xFFFFFFFF).withValues(alpha: 0.5)),
          overlay,
        ],
      ),
    );
  }
}

// ==========================================
// FILE-LEVEL SHARED HELPERS
// ==========================================
Widget _buildInputField(
  String label,
  String hint, {
  IconData? suffixIcon,
  bool isDropdown = false,
  bool isTextArea = false,
  TextEditingController? controller,
  TextAlign textAlign = TextAlign.start,
}) {
  final isAmount = label.toLowerCase().contains('amount');
  final isLeaves = label.toLowerCase().contains('leaves');
  final isContact =
      label.toLowerCase().contains('contact') ||
      label.toLowerCase().contains('phone');
  final isNationalId =
      label.toLowerCase().contains('national id') ||
      label.toLowerCase().contains('national_id');
  final isNumeric = isAmount || isLeaves || isContact || isNationalId;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFF000000),
          fontSize: 14,
          fontWeight: FontWeight.bold,
          fontFamily: 'SF Pro Display',
        ),
      ),
      const SizedBox(height: 8),
      Container(
        height: isTextArea ? 90 : 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: isTextArea ? Alignment.topLeft : Alignment.center,
        child: TextField(
          textAlign: textAlign,
          maxLines: isTextArea ? 4 : 1,
          controller: controller,
          keyboardType: isNumeric
              ? (isAmount
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.number)
              : null,
          inputFormatters: isNumeric
              ? [
                  FilteringTextInputFormatter.allow(
                    isAmount ? RegExp(r'^\d*\.?\d*') : RegExp(r'^\d*'),
                  ),
                  if (isAmount) LengthLimitingTextInputFormatter(15),
                  if (isContact) LengthLimitingTextInputFormatter(20),
                  if (isNationalId) LengthLimitingTextInputFormatter(20),
                  if (isLeaves) LengthLimitingTextInputFormatter(3),
                ]
              : null,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF000000),
            fontFamily: 'SF Pro Display',
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 14,
              fontFamily: 'SF Pro Display',
            ),
            border: InputBorder.none,
            isDense: true,
            contentPadding: isTextArea
                ? const EdgeInsets.only(top: 14)
                : const EdgeInsets.symmetric(vertical: 12),
            suffixIcon: isDropdown
                ? Icon(
                    Icons.arrow_drop_down,
                    color: Colors.grey.shade400,
                    size: 22,
                  )
                : (suffixIcon != null
                      ? Icon(suffixIcon, color: Colors.grey.shade400, size: 22)
                      : null),
          ),
        ),
      ),
    ],
  );
}

Widget _buildCustomRadio({
  required String label,
  required bool isSelected,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF000000), width: 2),
          ),
          child: isSelected
              ? Center(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF000000),
                    ),
                  ),
                )
              : const SizedBox(),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF000000),
            fontSize: 16,
            fontWeight: FontWeight.w500,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ],
    ),
  );
}

Widget _buildMenuRadio(bool isSelected, String text) {
  final Color activeColor = const Color(0xFF0B50C3);
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? activeColor : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
        child: isSelected
            ? Center(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: activeColor,
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
      const SizedBox(width: 12),
      Text(
        text,
        style: TextStyle(
          color: isSelected ? activeColor : Colors.grey.shade500,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          fontSize: 14,
          fontFamily: 'SF Pro Display',
        ),
      ),
    ],
  );
}

Widget _buildDropdownField({
  required String label,
  required String selectedValue,
  required String hint,
  required List<String> items,
  required ValueChanged<String?> onChanged,
  String? Function(String item)? itemLabelBuilder,
}) {
  return CustomDropdownField(
    label: label,
    selectedValue: selectedValue,
    hint: hint,
    items: items,
    onChanged: onChanged,
    itemLabelBuilder: itemLabelBuilder,
  );
}

// Stateful widget that renders the first page of the PDF CV file
class PdfPagePreview extends StatefulWidget {
  final Uint8List? cvBytes;
  final String? existingCvUrl;

  const PdfPagePreview({super.key, this.cvBytes, this.existingCvUrl});

  @override
  State<PdfPagePreview> createState() => _PdfPagePreviewState();
}

class _PdfPagePreviewState extends State<PdfPagePreview> {
  Uint8List? _pageImageBytes;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _renderPdfPage();
  }

  @override
  void didUpdateWidget(covariant PdfPagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cvBytes != oldWidget.cvBytes ||
        widget.existingCvUrl != oldWidget.existingCvUrl) {
      _renderPdfPage();
    }
  }

  Future<void> _renderPdfPage() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _pageImageBytes = null;
    });

    try {
      PdfDocument? document;
      if (widget.cvBytes != null) {
        document = await PdfDocument.openData(widget.cvBytes!);
      } else if (widget.existingCvUrl != null &&
          widget.existingCvUrl!.isNotEmpty) {
        if (widget.existingCvUrl!.startsWith('http')) {
          final request = await io.HttpClient().getUrl(
            Uri.parse(widget.existingCvUrl!),
          );
          final response = await request.close();
          final bytesBuilder = BytesBuilder();
          await for (var chunk in response) {
            bytesBuilder.add(chunk);
          }
          final bytes = bytesBuilder.takeBytes();
          document = await PdfDocument.openData(bytes);
        } else if (widget.existingCvUrl!.startsWith('data:application/pdf')) {
          final base64Content =
              widget.existingCvUrl!.split(',').last;
          final bytes = base64Decode(base64Content);
          document = await PdfDocument.openData(bytes);
        }
      }

      if (document != null) {
        final page = await document.getPage(1);
        final pageImage = await page.render(
          width: page.width * 5,
          height: page.height * 5,
          format: PdfPageImageFormat.png,
        );
        if (pageImage != null) {
          if (mounted) {
            setState(() {
              _pageImageBytes = pageImage.bytes;
              _isLoading = false;
            });
          }
        } else {
          throw Exception('Failed to render PDF page');
        }
        await document.close();
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error rendering PDF page preview: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.0),
        ),
      );
    }
    if (_error != null) {
      return const SizedBox.shrink();
    }
    if (_pageImageBytes != null) {
      return Image.memory(
        _pageImageBytes!,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        width: double.infinity,
        height: double.infinity,
      );
    }
    return const SizedBox.shrink();
  }
}

class DocPagePreview extends StatefulWidget {
  final String? fileUrl;
  final Uint8List? cvBytes;
  final String? fileName;

  const DocPagePreview({
    super.key,
    this.fileUrl,
    this.cvBytes,
    this.fileName,
  });

  @override
  State<DocPagePreview> createState() => _DocPagePreviewState();
}

class _DocPagePreviewState extends State<DocPagePreview> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      );
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    if (widget.fileUrl != null && widget.fileUrl!.isNotEmpty) {
      final googleDocsUrl =
          'https://docs.google.com/gview?url=${Uri.encodeComponent(widget.fileUrl!)}&embedded=true';
      _controller.loadRequest(Uri.parse(googleDocsUrl));
    } else if (widget.cvBytes != null && widget.fileName != null) {
      try {
        final tempDir = io.Directory.systemTemp;
        final tempFile = io.File('${tempDir.path}/${widget.fileName}');
        await tempFile.writeAsBytes(widget.cvBytes!);
        _controller.loadRequest(tempFile.uri);
      } catch (e) {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            ),
          ),
      ],
    );
  }
}

class _DocPreviewScreen extends StatefulWidget {
  final String? fileUrl;
  final String? fileName;
  final Uint8List? cvBytes;

  const _DocPreviewScreen({
    this.fileUrl,
    this.fileName,
    this.cvBytes,
  });

  @override
  State<_DocPreviewScreen> createState() => _DocPreviewScreenState();
}

class _DocPreviewScreenState extends State<_DocPreviewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _error = 'Failed to load document';
              });
            }
          },
        ),
      );

    if (widget.fileUrl != null && widget.fileUrl!.isNotEmpty) {
      final googleDocsUrl =
          'https://docs.google.com/gview?url=${Uri.encodeComponent(widget.fileUrl!)}&embedded=true';
      _controller.loadRequest(Uri.parse(googleDocsUrl));
    } else if (widget.cvBytes != null && widget.fileName != null) {
      try {
        final tempDir = io.Directory.systemTemp;
        final tempFile = io.File('${tempDir.path}/${widget.fileName}');
        await tempFile.writeAsBytes(widget.cvBytes!);
        _controller.loadRequest(tempFile.uri);
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = 'Failed to load document: $e';
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'No document data available';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.fileName ?? 'Document',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'SF Pro Display',
            color: Colors.black,
          ),
        ),
        centerTitle: false,
      ),
      body: Stack(
        children: [
          if (_error != null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ],
              ),
            )
          else
            WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(strokeWidth: 2.0),
            ),
        ],
      ),
    );
  }
}

ImageProvider getProfileImageProvider(String? url) {
  if (url == null || url.isEmpty) {
    return const AssetImage('assets/profileimage.png');
  }
  if (url.startsWith('data:image/')) {
    final base64Content = url.split(',').last;
    return MemoryImage(base64Decode(base64Content));
  }
  if (url.startsWith('http')) {
    return CachedNetworkImageProvider(url);
  }
  return AssetImage(url);
}
