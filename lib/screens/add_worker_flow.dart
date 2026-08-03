import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:pdfx/pdfx.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoDatePicker, CupertinoDatePickerMode, CupertinoIcons;
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:archive/archive.dart';
import '../widgets/clickable_gesture_detector.dart';
import '../widgets/custom_dropdown_field.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/validators.dart';
import '../services/upload_service.dart';
import '../services/error_reporter.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../services/dummy_data.dart';
import '../services/preferences_service.dart';
import '../utils/snackbar_utils.dart';
import '../utils/date_utils.dart';
import '../utils/currency_utils.dart';
import '../utils/worker_identity.dart';
import '../utils/localization_helper.dart';
import '../utils/rate_us_helper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:provider/provider.dart';

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

Uint8List _compressImageTask(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final maxWidth = args['maxWidth'] as int;
  final quality = args['quality'] as int;
  img.Image? image = img.decodeImage(bytes);
  if (image == null) return bytes;
  if (image.width > maxWidth) {
    image = img.copyResize(image, width: maxWidth);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

class AddNewWorkerFlow extends StatefulWidget {
  final VoidCallback? onBack;
  final Map<String, dynamic>? workerToEdit;

  const AddNewWorkerFlow({super.key, this.onBack, this.workerToEdit});

  @override
  State<AddNewWorkerFlow> createState() => _AddNewWorkerFlowState();
}

class _AddNewWorkerFlowState extends State<AddNewWorkerFlow> {
  late AuthService _authService;
  late FirestoreService _firestore;
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

  final _experienceLevelController = TextEditingController(text: 'Mid-Level');
  final _educationController = TextEditingController(text: 'Bachelor');
  final _salaryTypeController = TextEditingController(text: 'Monthly');
  final _currencyController = TextEditingController(text: 'USD');
  final _salaryAmountController = TextEditingController();
  final _leavePolicyController = TextEditingController(text: 'Standard');
  final _annualLeavesController = TextEditingController();
  final _sickLeavesController = TextEditingController();
  final _casualLeavesController = TextEditingController();
  String _relationshipStatus = 'Single';

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
  bool _isChecking = false;

  bool get _hasUnsavedChanges {
    if (widget.workerToEdit != null) return _hasChanges();
    if (_nameController.text.trim().isNotEmpty) return true;
    if (_fatherNameController.text.trim().isNotEmpty) return true;
    if (_emailController.text.trim().isNotEmpty) return true;
    if (_phoneController.text.trim().isNotEmpty) return true;
    if (_nationalIdController.text.trim().isNotEmpty) return true;
    if (_religionController.text.trim().isNotEmpty) return true;
    if (_dobController.text.trim().isNotEmpty) return true;
    if (_addressController.text.trim().isNotEmpty) return true;
    if (_positionController.text.trim().isNotEmpty) return true;
    if (_genderController.text.trim() != 'Male') return true;
    if (_relationshipStatus != 'Single') return true;
    if (_type1Controller.text.trim() != 'Full-Time') return true;
    if (_type2Controller.text.trim() != 'On-Site') return true;
    if (_experienceLevelController.text.trim() != 'Mid-Level') return true;
    if (_educationController.text.trim() != 'Bachelor') return true;
    if (_salaryTypeController.text.trim() != 'Monthly') return true;
    if (CurrencyUtils.normalize(_currencyController.text) != 'USD') return true;
    if (_salaryAmountController.text.trim().isNotEmpty) return true;
    if (_leavePolicyController.text.trim() != 'Standard') return true;
    if (_annualLeavesController.text.trim().isNotEmpty) return true;
    if (_sickLeavesController.text.trim().isNotEmpty) return true;
    if (_casualLeavesController.text.trim().isNotEmpty) return true;
    if ((_joiningDate ?? '').trim().isNotEmpty) return true;
    if (_frontIdBytes != null) return true;
    if (_backIdBytes != null) return true;
    if (_cvBytes != null) return true;
    if (_profileImageBytes != null) return true;
    return false;
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) return true;
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'UnsavedChangesDialog',
      barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.3),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: 12 * animation.value,
            sigmaY: 12 * animation.value,
          ),
          child: FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: curve,
              child: Dialog(
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
                      Text(
                        'discard_changes'.tr(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF000000),
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'unsaved_changes_message'.tr(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
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
                                child: Text(
                                  'cancel'.tr(),
                                  style: const TextStyle(
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
                                      color: const Color(
                                        0xFFEF4444,
                                      ).withValues(alpha: 0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  'discard'.tr(),
                                  style: const TextStyle(
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
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.workerToEdit != null) {
      _nameController.text = (widget.workerToEdit!['name'] ?? '').toString();
      _fatherNameController.text = (widget.workerToEdit!['fatherName'] ?? '')
          .toString();
      _emailController.text = (widget.workerToEdit!['email'] ?? '').toString();
      _phoneController.text =
          (widget.workerToEdit!['phone'] ??
                  widget.workerToEdit!['contact'] ??
                  '')
              .toString();
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
          (widget.workerToEdit!['education'] ?? 'Bachelor').toString();
      if (_educationController.text.isEmpty)
        _educationController.text = 'Bachelor';

      _salaryTypeController.text =
          (widget.workerToEdit!['salaryType'] ?? 'Monthly').toString();
      if (_salaryTypeController.text.isEmpty)
        _salaryTypeController.text = 'Monthly';

      _currencyController.text = CurrencyUtils.normalize(
        widget.workerToEdit!['currency'],
      );

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

      _existingProfileImageUrl = widget.workerToEdit!['profileImage']
          ?.toString();

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
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestore = Provider.of<FirestoreService>(context, listen: false);

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

    _annualLeavesController.addListener(_clampAnnualLeaves);

    if (widget.workerToEdit == null) {
      _applyActiveLeavePolicyToNewWorker();
    }
  }

  Future<void> _applyActiveLeavePolicyToNewWorker() async {
    if (!mounted) return;
    try {
      final policies = await _firestore.getLeavePolicies();
      if (!mounted || policies.isEmpty) return;
      final active = policies.first;
      final annual = (active['annualLeaveDays'] ?? 0).toString();
      final sick = (active['sickLeaves'] ?? '0').toString();
      final casual = (active['casualLeaves'] ?? '0').toString();
      final policyName = (active['policyName'] ?? '').toString();

      setState(() {
        if (_annualLeavesController.text.trim().isEmpty) {
          _annualLeavesController.text = annual;
        }
        if (_sickLeavesController.text.trim().isEmpty) {
          _sickLeavesController.text = sick;
        }
        if (_casualLeavesController.text.trim().isEmpty) {
          _casualLeavesController.text = casual;
        }
        if (policyName.isNotEmpty &&
            _leavePolicyController.text.trim() == 'Standard') {
          _leavePolicyController.text = policyName;
        }
      });
    } catch (_) {}
  }

  void _clampAnnualLeaves() {
    final text = _annualLeavesController.text;
    if (text.startsWith('-') || text.startsWith('+')) {
      _annualLeavesController.text = text.replaceAll(RegExp(r'^[+\-]+'), '');
      _annualLeavesController.selection = TextSelection.collapsed(
        offset: _annualLeavesController.text.length,
      );
    }
  }

  DateTime _adultCutoff() {
    final now = DateTime.now();
    return DateTime(now.year - 18, now.month, now.day);
  }

  Future<Uint8List?> _readPickedFileBytes(
    PlatformFile file, {
    required int maxBytes,
    required String sizeLabel,
  }) async {
    final memoryBytes = file.bytes;
    if (memoryBytes != null) {
      if (memoryBytes.length > maxBytes) {
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'file_too_large'.tr(namedArgs: {'size': sizeLabel}),
            isError: true,
          );
        }
        return null;
      }
      return memoryBytes;
    }

    final path = file.path;
    if (path == null || path.trim().isEmpty) {
      throw StateError('failed_to_pick_file'.tr());
    }

    final diskFile = io.File(path);
    final fileSize = await diskFile.length();
    if (fileSize > maxBytes) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'file_too_large'.tr(namedArgs: {'size': sizeLabel}),
          isError: true,
        );
      }
      return null;
    }

    return diskFile.readAsBytes();
  }

  String _mimeTypeForFileName(String fileName) {
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';

    return switch (extension) {
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'bmp' => 'image/bmp',
      'webp' => 'image/webp',
      'jpg' || 'jpeg' => 'image/jpeg',
      _ => 'application/octet-stream',
    };
  }

  String _filePickerErrorMessage(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('permission') ||
        message.contains('denied') ||
        message.contains('access') ||
        message.contains('sandbox')) {
      return 'macos_file_access_permission_error'.tr();
    }
    return 'failed_to_pick_file'.tr();
  }

  String _jpegFileName(String fileName, String fallback) {
    final cleanName = fileName.trim().isEmpty ? fallback : fileName.trim();
    final dotIndex = cleanName.lastIndexOf('.');
    final baseName = dotIndex > 0
        ? cleanName.substring(0, dotIndex)
        : cleanName;
    return '$baseName.jpg';
  }

  Future<UploadFile> _prepareUploadFile({
    required String folder,
    required String? fileName,
    required String fallbackFileName,
    required Uint8List bytes,
    required bool compressImages,
  }) async {
    final resolvedName = fileName?.trim().isNotEmpty == true
        ? fileName!.trim()
        : fallbackFileName;
    final mimeType = _mimeTypeForFileName(resolvedName);

    if (compressImages && mimeType.startsWith('image/')) {
      return UploadFile(
        folder: folder,
        fileName: _jpegFileName(resolvedName, fallbackFileName),
        bytes: await _compressImage(bytes),
        mimeType: 'image/jpeg',
      );
    }

    return UploadFile(
      folder: folder,
      fileName: resolvedName,
      bytes: bytes,
      mimeType: mimeType,
    );
  }

  DateTime? _parseWorkerDate(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;

    final parsed = AppDateUtils.parseDateString(text);
    if (parsed != null) {
      return DateTime(parsed.year, parsed.month, parsed.day);
    }

    final normalized = text.replaceAll(',', '').trim();
    final parts = normalized.split(RegExp(r'\s+'));
    if (parts.length == 3) {
      final day = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      final englishMonthIndex = _months.indexWhere(
        (month) => month.toLowerCase() == parts[0].toLowerCase(),
      );
      final localizedMonthIndex = List<int>.generate(12, (index) => index + 1)
          .indexWhere(
            (month) =>
                _localizedMonth(month).toLowerCase() == parts[0].toLowerCase(),
          );
      final monthIndex = englishMonthIndex >= 0
          ? englishMonthIndex
          : localizedMonthIndex;
      if (day != null &&
          year != null &&
          monthIndex >= 0 &&
          day >= 1 &&
          day <= DateTime(year, monthIndex + 2, 0).day) {
        return DateTime(year, monthIndex + 1, day);
      }
    }

    return null;
  }

  bool _sameWorkerDate(String? first, String? second) {
    final firstDate = _parseWorkerDate(first);
    final secondDate = _parseWorkerDate(second);

    if (firstDate == null || secondDate == null) {
      return (first ?? '').trim() == (second ?? '').trim();
    }

    return firstDate.year == secondDate.year &&
        firstDate.month == secondDate.month &&
        firstDate.day == secondDate.day;
  }

  bool _validateExperienceData() {
    final position = _positionController.text.trim();
    final salaryText = _salaryAmountController.text.trim().replaceAll(',', '');
    final annualLeavesText = _annualLeavesController.text.trim();
    final joiningDateText = (_joiningDate ?? '').trim();

    if (position.isEmpty &&
        salaryText.isEmpty &&
        annualLeavesText.isEmpty &&
        joiningDateText.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_fill_all_fields'.tr(),
        isError: true,
      );
      return false;
    }

    if (position.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_job_position'.tr(),
        isError: true,
      );
      return false;
    }

    final salaryAmount = double.tryParse(salaryText);
    if (salaryAmount == null || !salaryAmount.isFinite || salaryAmount <= 0) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_salary_amount'.tr(),
        isError: true,
      );
      return false;
    }

    final annualLeaves = int.tryParse(annualLeavesText);
    if (annualLeaves == null || annualLeaves < 0) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_annual_leaves'.tr(),
        isError: true,
      );
      return false;
    }

    if (!CurrencyUtils.isSupported(_currencyController.text)) {
      FlashySnackBar.show(
        context,
        message: 'invalid_currency_value'.tr(),
        isError: true,
      );
      return false;
    }

    if (joiningDateText.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_select_a_joining_date'.tr(),
        isError: true,
      );
      return false;
    }

    final joiningDate = _parseWorkerDate(joiningDateText);
    if (joiningDate == null) {
      FlashySnackBar.show(
        context,
        message: 'invalid_date_format'.tr(),
        isError: true,
      );
      return false;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (joiningDate.isAfter(today)) {
      FlashySnackBar.show(
        context,
        message: 'joining_date_cannot_be_future'.tr(),
        isError: true,
      );
      return false;
    }

    return true;
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
        final bytes = await _readPickedFileBytes(
          file,
          maxBytes: 10 * 1024 * 1024,
          sizeLabel: '10MB',
        );
        if (bytes == null || !mounted) return;
        setState(() {
          _profileImageBytes = bytes;
          _profileImageName = file.name;
        });
        if (!mounted) return;
        FlashySnackBar.show(context, message: 'file_uploaded'.tr());
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: _filePickerErrorMessage(e),
          isError: true,
        );
      }
    }
  }

  Future<void> _pickFrontId() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'jpg',
          'jpeg',
          'png',
          'gif',
          'bmp',
          'webp',
        ],
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty && mounted) {
        final file = result.files.first;
        final bytes = await _readPickedFileBytes(
          file,
          maxBytes: 10 * 1024 * 1024,
          sizeLabel: '10MB',
        );
        if (bytes == null || !mounted) return;
        setState(() {
          _frontIdBytes = bytes;
          _frontIdName = file.name;
        });
        FlashySnackBar.show(context, message: 'file_uploaded'.tr());
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: _filePickerErrorMessage(e),
          isError: true,
        );
      }
    }
  }

  Future<void> _pickBackId() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'jpg',
          'jpeg',
          'png',
          'gif',
          'bmp',
          'webp',
        ],
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty && mounted) {
        final file = result.files.first;
        final bytes = await _readPickedFileBytes(
          file,
          maxBytes: 10 * 1024 * 1024,
          sizeLabel: '10MB',
        );
        if (bytes == null || !mounted) return;
        setState(() {
          _backIdBytes = bytes;
          _backIdName = file.name;
        });
        FlashySnackBar.show(context, message: 'file_uploaded'.tr());
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: _filePickerErrorMessage(e),
          isError: true,
        );
      }
    }
  }

  Future<void> _pickCv() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'jpg',
          'jpeg',
          'png',
          'gif',
          'bmp',
          'webp',
        ],
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty && mounted) {
        final file = result.files.first;
        final bytes = await _readPickedFileBytes(
          file,
          maxBytes: 20 * 1024 * 1024,
          sizeLabel: '20MB',
        );
        if (bytes == null || !mounted) return;
        setState(() {
          _cvBytes = bytes;
          _cvName = file.name;
          _isCvUploaded = true;
        });
        FlashySnackBar.show(context, message: 'file_uploaded'.tr());
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: _filePickerErrorMessage(e),
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
    if (dobStr.isEmpty) return null;
    final dob = AppDateUtils.parseDateString(dobStr);
    if (dob == null) {
      FlashySnackBar.show(
        context,
        message: 'invalid_date_format'.tr(),
        isError: true,
      );
      return null;
    }
    final cutoff = _adultCutoff();
    if (dob.isAfter(cutoff)) {
      FlashySnackBar.show(
        context,
        message: 'worker_must_be_18'.tr(),
        isError: true,
      );
      return null;
    }
    return dob;
  }

  bool _hasChanges() {
    if (widget.workerToEdit == null) return true;
    final edit = widget.workerToEdit!;

    String firstNonEmpty(List<dynamic> values) {
      for (final value in values) {
        final text = value?.toString().trim() ?? '';
        if (text.isNotEmpty && text != 'null') return text;
      }
      return '';
    }

    if (_nameController.text.trim() != (edit['name'] ?? '').toString().trim()) {
      return true;
    }
    if (_fatherNameController.text.trim() !=
        (edit['fatherName'] ?? '').toString().trim()) {
      return true;
    }
    if (WorkerIdentity.normalizeEmail(_emailController.text) !=
        WorkerIdentity.normalizeEmail(edit['email'])) {
      return true;
    }
    if (_phoneController.text.trim() !=
        (edit['phone'] ?? edit['contact'] ?? '').toString().trim()) {
      return true;
    }
    if (WorkerIdentity.normalizeNationalId(_nationalIdController.text) !=
        WorkerIdentity.normalizeNationalId(edit['nationalId'])) {
      return true;
    }
    if (_religionController.text.trim() !=
        (edit['religion'] ?? '').toString().trim()) {
      return true;
    }
    if (!_sameWorkerDate(_dobController.text, edit['dob']?.toString())) {
      return true;
    }
    if (_genderController.text.trim() !=
        (edit['gender'] ?? 'Male').toString().trim()) {
      return true;
    }
    if (_addressController.text.trim() !=
        (edit['address'] ?? '').toString().trim()) {
      return true;
    }
    if (_relationshipStatus.trim() !=
        (edit['relationshipStatus'] ?? 'Single').toString().trim()) {
      return true;
    }
    if (_positionController.text.trim() !=
        (edit['position'] ?? '').toString().trim()) {
      return true;
    }
    if (_type1Controller.text.trim() !=
        (edit['type1'] ?? 'Full-Time').toString().trim()) {
      return true;
    }
    if (_type2Controller.text.trim() !=
        (edit['type2'] ?? 'On-Site').toString().trim()) {
      return true;
    }
    if (_experienceLevelController.text.trim() !=
        (edit['experienceLevel'] ?? 'Mid-Level').toString().trim()) {
      return true;
    }
    if (_educationController.text.trim() !=
        (edit['education'] ?? 'Bachelor').toString().trim()) {
      return true;
    }
    if (_salaryTypeController.text.trim() !=
        (edit['salaryType'] ?? 'Monthly').toString().trim()) {
      return true;
    }
    if (CurrencyUtils.normalize(_currencyController.text) !=
        CurrencyUtils.normalize(edit['currency'])) {
      return true;
    }
    if (_salaryAmountController.text.trim() !=
        (edit['salaryAmount'] ?? '').toString().trim()) {
      return true;
    }
    if (_leavePolicyController.text.trim() !=
        (edit['leavePolicy'] ?? 'Standard').toString().trim()) {
      return true;
    }
    if (_annualLeavesController.text.trim() !=
        (edit['annualLeaves'] ?? '').toString().trim()) {
      return true;
    }
    if (_sickLeavesController.text.trim() !=
        (edit['sickLeaves'] ?? '').toString().trim()) {
      return true;
    }
    if (_casualLeavesController.text.trim() !=
        (edit['casualLeaves'] ?? '').toString().trim()) {
      return true;
    }
    if (!_sameWorkerDate(_joiningDate, edit['joiningDate']?.toString())) {
      return true;
    }
    if (_profileImageBytes != null ||
        (_existingProfileImageUrl ?? '').trim() !=
            (edit['profileImage'] ?? '').toString().trim()) {
      return true;
    }
    if (_frontIdBytes != null ||
        (_existingFrontIdUrl ?? '').trim() !=
            firstNonEmpty([
              edit['frontId'],
              edit['front_id'],
              edit['idFront'],
              edit['frontID'],
              edit['id_front'],
            ])) {
      return true;
    }
    if (_backIdBytes != null ||
        (_existingBackIdUrl ?? '').trim() !=
            firstNonEmpty([
              edit['backId'],
              edit['back_id'],
              edit['idBack'],
              edit['backID'],
              edit['id_back'],
            ])) {
      return true;
    }
    if (_cvBytes != null ||
        (_existingCvUrl ?? '').trim() != (edit['cv'] ?? '').toString().trim()) {
      return true;
    }

    return false;
  }

  Future<Uint8List> _compressImage(
    Uint8List bytes, {
    int maxWidth = 1200,
    int quality = 80,
  }) async {
    return compute(_compressImageTask, {
      'bytes': bytes,
      'maxWidth': maxWidth,
      'quality': quality,
    });
  }

  Future<void> _saveWorker() async {
    if (_isSaving) return;

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final nationalId = _nationalIdController.text.trim();
    final religion = _religionController.text.trim();
    final address = _addressController.text.trim();

    final allFieldsEmpty =
        name.isEmpty &&
        phone.isEmpty &&
        email.isEmpty &&
        nationalId.isEmpty &&
        religion.isEmpty &&
        _dobController.text.trim().isEmpty &&
        address.isEmpty;

    if (allFieldsEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_fill_all_fields'.tr(),
        isError: true,
      );
      return;
    }

    if (name.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_worker_name'.tr(),
        isError: true,
      );
      return;
    }

    if (phone.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_contact_number'.tr(),
        isError: true,
      );
      return;
    }

    if (email.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'email_is_required'.tr(),
        isError: true,
      );
      return;
    }

    if (!Validators.isValidEmail(email)) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_valid_email'.tr(),
        isError: true,
      );
      return;
    }

    if (nationalId.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'field_is_required'.tr(
          namedArgs: {'field': 'national_id_title'.tr()},
        ),
        isError: true,
      );
      return;
    }

    if (religion.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'field_is_required'.tr(
          namedArgs: {'field': 'religion_title'.tr()},
        ),
        isError: true,
      );
      return;
    }

    if (_dobController.text.trim().isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'field_is_required'.tr(
          namedArgs: {'field': 'date_of_birth'.tr()},
        ),
        isError: true,
      );
      return;
    }

    if (address.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'field_is_required'.tr(
          namedArgs: {'field': 'address_title'.tr()},
        ),
        isError: true,
      );
      return;
    }

    final dob = _validateAndParseDob();
    if (dob == null) return;

    if (!_validateExperienceData()) return;

    final joiningDate = _parseWorkerDate(_joiningDate);
    if (joiningDate == null) return;

    setState(() {
      _isSaving = true;
    });

    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    final isEditing = widget.workerToEdit != null;

    try {
      if (isGuest) {
        final guestWorkers = await PreferencesService.getGuestWorkers();
        final existingWorkers = guestWorkers ?? DummyData.workers;
        final duplicateField = WorkerIdentity.duplicateField(
          {'email': email, 'nationalId': nationalId},
          existingWorkers,
          excludeId: isEditing ? widget.workerToEdit!['id']?.toString() : null,
        );
        if (duplicateField != null && mounted) {
          setState(() => _isSaving = false);
          final messageKey = switch (duplicateField) {
            DuplicateWorkerField.name => 'duplicate_name',
            DuplicateWorkerField.email => 'duplicate_email',
            DuplicateWorkerField.nationalId => 'duplicate_national_id',
          };
          FlashySnackBar.show(context, message: messageKey.tr(), isError: true);
          return;
        }
      } else {
        final isDuplicate = await _firestore.hasDuplicateWorker(
          email: email,
          nationalId: nationalId,
          excludeId: isEditing ? widget.workerToEdit!['id']?.toString() : null,
        );
        if (isDuplicate && mounted) {
          setState(() => _isSaving = false);
          FlashySnackBar.show(
            context,
            message: 'duplicate_email_or_national_id'.tr(),
            isError: true,
          );
          return;
        }
      }
    } catch (_) {}

    String? profileImageUrl = _existingProfileImageUrl;
    String? frontIdUrl = _existingFrontIdUrl;
    String? backIdUrl = _existingBackIdUrl;
    String? cvUrl = _existingCvUrl;
    final newUploadUrls = <String>[];

    final oldProfileImageUrl = _existingProfileImageUrl;
    final oldFrontIdUrl = _existingFrontIdUrl;
    final oldBackIdUrl = _existingBackIdUrl;
    final oldCvUrl = _existingCvUrl;

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
          uploadFiles.add(
            await _prepareUploadFile(
              folder: 'profile_images',
              fileName: _profileImageName,
              fallbackFileName: 'profile.jpg',
              bytes: _profileImageBytes!,
              compressImages: true,
            ),
          );
        }
        if (_frontIdBytes != null) {
          uploadFiles.add(
            await _prepareUploadFile(
              folder: 'id_cards/front',
              fileName: _frontIdName,
              fallbackFileName: 'front.jpg',
              bytes: _frontIdBytes!,
              compressImages: true,
            ),
          );
        }
        if (_backIdBytes != null) {
          uploadFiles.add(
            await _prepareUploadFile(
              folder: 'id_cards/back',
              fileName: _backIdName,
              fallbackFileName: 'back.jpg',
              bytes: _backIdBytes!,
              compressImages: true,
            ),
          );
        }
        if (_cvBytes != null) {
          uploadFiles.add(
            await _prepareUploadFile(
              folder: 'cvs',
              fileName: _cvName,
              fallbackFileName: 'cv.pdf',
              bytes: _cvBytes!,
              compressImages: false,
            ),
          );
        }

        if (uploadFiles.isNotEmpty) {
          final results = await UploadService.uploadFiles(files: uploadFiles);
          final uploadFailed = results.any((result) => !result.isSuccess);

          for (final result in results) {
            if (result.isSuccess) {
              final url = result.url!;
              newUploadUrls.add(url);
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
                  message: 'file_upload_failed'.tr(
                    namedArgs: {'file': result.file.fileName},
                  ),
                  isError: true,
                );
              }
            }
          }
          if (uploadFailed) {
            if (newUploadUrls.isNotEmpty) {
              try {
                await Future.wait(newUploadUrls.map(UploadService.deleteByUrl));
              } catch (_) {}
            }
            if (mounted) setState(() => _isSaving = false);
            return;
          }
        }
      }

      final data = <String, dynamic>{
        'name': name,
        'fatherName': _fatherNameController.text.trim(),
        'email': WorkerIdentity.normalizeEmail(email),
        'phone': phone,
        'nationalId': _nationalIdController.text.trim(),
        'religion': _religionController.text.trim(),
        'dob': isGuest
            ? _dobController.text.trim()
            : AppDateUtils.formatDate(dob),
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
        'currency': CurrencyUtils.normalize(_currencyController.text),
        'salaryAmount':
            double.tryParse(
              _salaryAmountController.text.trim().replaceAll(',', ''),
            ) ??
            0.0,
        'leavePolicy': _leavePolicyController.text.trim(),
        'annualLeaves': int.tryParse(_annualLeavesController.text.trim()) ?? 0,
        'availableAnnualLeaves':
            int.tryParse(_annualLeavesController.text.trim()) ?? 0,
        'leavesUsed': 0,
        'sickLeaves': int.tryParse(_sickLeavesController.text.trim()) ?? 0,
        'casualLeaves': int.tryParse(_casualLeavesController.text.trim()) ?? 0,
        'joiningDate': isGuest
            ? (_joiningDate ?? '')
            : AppDateUtils.formatDate(joiningDate),
        'profileImage': profileImageUrl,

        'frontId': frontIdUrl,
        'backId': backIdUrl,

        'front_id': frontIdUrl,
        'back_id': backIdUrl,
        'idFront': frontIdUrl,
        'idBack': backIdUrl,
        'id_front': frontIdUrl,
        'id_back': backIdUrl,

        'cv': cvUrl,
        'payroll_initialized': true,
      };

      final annualLeaveTotal =
          int.tryParse(_annualLeavesController.text.trim()) ?? 0;

      if (!isEditing) {
        data.addAll({
          'leavesUsed': '0',
          'availableAnnualLeaves': annualLeaveTotal.toString(),
        });
      } else if (!isGuest) {
        data.remove('leavesUsed');
        data.remove('availableAnnualLeaves');
      }

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
            DummyData.workers[index] = {
              ...DummyData.workers[index],
              ...data,
              'id': editId,
            };
            await DummyData.saveToPrefs();
          }
        } else {
          await _firestore.updateWorker(editId, data);
        }
      } else {
        if (isGuest) {
          final newId = 'dummy_${DateTime.now().millisecondsSinceEpoch}';
          DummyData.workers.insert(0, {...data, 'id': newId});
          await DummyData.saveToPrefs();
          if (mounted) setState(() {});
        } else {
          await _firestore.addWorker(data);
        }
      }

      if (widget.workerToEdit != null) {
        final currentUrls = <String>{
          if (profileImageUrl != null) profileImageUrl,
          if (frontIdUrl != null) frontIdUrl,
          if (backIdUrl != null) backIdUrl,
          if (cvUrl != null) cvUrl,
        };
        final oldUrls = <String>{
          if (oldProfileImageUrl != null) oldProfileImageUrl,
          if (oldFrontIdUrl != null) oldFrontIdUrl,
          if (oldBackIdUrl != null) oldBackIdUrl,
          if (oldCvUrl != null) oldCvUrl,
        };
        for (final oldUrl in oldUrls) {
          if (oldUrl.isNotEmpty && !currentUrls.contains(oldUrl)) {
            try {
              await UploadService.deleteByUrl(oldUrl);
            } catch (cleanupError, cleanupStack) {
              ErrorReporter.report(
                cleanupError,
                cleanupStack,
                context: 'workerEditCleanupOldFile',
              );
            }
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      if (!context.mounted) return;
      final workerName = name;
      FlashySnackBar.show(
        context,
        message: widget.workerToEdit != null
            ? 'worker_updated_successfully'.tr(namedArgs: {'name': workerName})
            : 'worker_added_successfully'.tr(),
      );
      await tryShowFirstMilestoneRateUs('worker');
      if (context.mounted) {
        widget.onBack?.call();
      }
    } on DuplicateWorkerException catch (e) {
      if (newUploadUrls.isNotEmpty) {
        try {
          await Future.wait(newUploadUrls.map(UploadService.deleteByUrl));
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        final messageKey = switch (e.field) {
          DuplicateWorkerField.name => 'duplicate_name',
          DuplicateWorkerField.email => 'duplicate_email',
          DuplicateWorkerField.nationalId => 'duplicate_national_id',
        };
        FlashySnackBar.show(context, message: messageKey.tr(), isError: true);
      }
    } on ValidationException catch (e) {
      if (newUploadUrls.isNotEmpty) {
        try {
          await Future.wait(newUploadUrls.map(UploadService.deleteByUrl));
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        FlashySnackBar.show(context, message: e.message, isError: true);
      }
    } catch (e) {
      if (newUploadUrls.isNotEmpty) {
        try {
          await Future.wait(newUploadUrls.map(UploadService.deleteByUrl));
        } catch (_) {}
      }
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

  Future<void> _validateAndGoToExperience() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final nationalId = _nationalIdController.text.trim();
    final religion = _religionController.text.trim();
    final address = _addressController.text.trim();
    final dobStr = _dobController.text.trim();

    final allFieldsEmpty =
        name.isEmpty &&
        phone.isEmpty &&
        email.isEmpty &&
        nationalId.isEmpty &&
        religion.isEmpty &&
        dobStr.isEmpty &&
        address.isEmpty;

    if (allFieldsEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_fill_all_fields'.tr(),
        isError: true,
      );
      return;
    }

    if (name.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_worker_name'.tr(),
        isError: true,
      );
      return;
    }

    if (phone.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_contact_number'.tr(),
        isError: true,
      );
      return;
    }

    if (email.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'email_is_required'.tr(),
        isError: true,
      );
      return;
    }

    if (!Validators.isValidEmail(email)) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_valid_email'.tr(),
        isError: true,
      );
      return;
    }

    if (nationalId.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'field_is_required'.tr(
          namedArgs: {'field': 'national_id_title'.tr()},
        ),
        isError: true,
      );
      return;
    }

    if (religion.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'field_is_required'.tr(
          namedArgs: {'field': 'religion_title'.tr()},
        ),
        isError: true,
      );
      return;
    }

    if (dobStr.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'field_is_required'.tr(
          namedArgs: {'field': 'date_of_birth'.tr()},
        ),
        isError: true,
      );
      return;
    }

    if (_validateAndParseDob() == null) return;

    if (address.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'field_is_required'.tr(
          namedArgs: {'field': 'address_title'.tr()},
        ),
        isError: true,
      );
      return;
    }

    if (_profileImageBytes == null &&
        (_existingProfileImageUrl == null ||
            _existingProfileImageUrl!.isEmpty)) {
      FlashySnackBar.show(
        context,
        message: 'profile_image_required'.tr(),
        isError: true,
      );
      return;
    }

    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    final isEditing = widget.workerToEdit != null;

    setState(() => _isChecking = true);
    try {
      if (isGuest) {
        final guestWorkers = await PreferencesService.getGuestWorkers();
        final existingWorkers = guestWorkers ?? DummyData.workers;
        final duplicateField = WorkerIdentity.duplicateField(
          {'email': email, 'nationalId': nationalId},
          existingWorkers,
          excludeId: isEditing ? widget.workerToEdit!['id']?.toString() : null,
        );
        if (duplicateField != null && mounted) {
          final messageKey = switch (duplicateField) {
            DuplicateWorkerField.name => 'duplicate_name',
            DuplicateWorkerField.email => 'duplicate_email',
            DuplicateWorkerField.nationalId => 'duplicate_national_id',
          };
          FlashySnackBar.show(context, message: messageKey.tr(), isError: true);
          return;
        }
      } else {
        final isDuplicate = await _firestore.hasDuplicateWorker(
          email: email,
          nationalId: nationalId,
          excludeId: isEditing ? widget.workerToEdit!['id']?.toString() : null,
        );
        if (isDuplicate && mounted) {
          FlashySnackBar.show(
            context,
            message: 'duplicate_email_or_national_id'.tr(),
            isError: true,
          );
          return;
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }

    setState(() => _activeTabIndex = 1);
  }

  void _validateAndGoToDocumentation() {
    if (!_validateExperienceData()) return;
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          widget.onBack?.call();
        }
      },
      child: Container(
        color: const Color(0xFFF7F8FA),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                        onTap: () async {
                          final shouldPop = await _onWillPop();
                          if (shouldPop) widget.onBack?.call();
                        },
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

                  Builder(
                    builder: (context) {
                      final bool isEditMode = widget.workerToEdit != null;
                      final bool hasChanges = _hasChanges();

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

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                          Expanded(
                            child: _buildTopTab('worker_detail'.tr(), 0),
                          ),
                          VerticalDivider(
                            width: 1,
                            color: Color(0xFFE0E0E0).withValues(alpha: 0.5),
                          ),
                          Expanded(child: _buildTopTab('experience'.tr(), 1)),
                          VerticalDivider(
                            width: 1,
                            color: Color(0xFFE0E0E0).withValues(alpha: 0.5),
                          ),
                          Expanded(
                            child: _buildTopTab('documentation'.tr(), 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

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
                        onDeleteProfileTap: () {
                          setState(() {
                            _profileImageBytes = null;
                            _profileImageName = null;
                            _existingProfileImageUrl = null;
                          });
                        },
                        relationshipStatus: _relationshipStatus,
                        onRelationshipStatusChanged: (status) {
                          setState(() {
                            _relationshipStatus = status;
                          });
                        },
                        onNextStep: _validateAndGoToExperience,
                        isChecking: _isChecking,
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
                          showGeneralDialog(
                            context: context,
                            barrierDismissible: true,
                            barrierLabel: 'DeleteCvDialog',
                            barrierColor: const Color(
                              0xFF0F172A,
                            ).withValues(alpha: 0.3),
                            transitionDuration: const Duration(
                              milliseconds: 400,
                            ),
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    const SizedBox(),
                            transitionBuilder: (context, animation, secondaryAnimation, child) {
                              final curve = CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutBack,
                              );
                              return BackdropFilter(
                                filter: ui.ImageFilter.blur(
                                  sigmaX: 12 * animation.value,
                                  sigmaY: 12 * animation.value,
                                ),
                                child: FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    scale: curve,
                                    child: Dialog(
                                      backgroundColor: Colors.transparent,
                                      child: Container(
                                        width: 380,
                                        padding: const EdgeInsets.all(28),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFFFFF),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(
                                                0xFF000000,
                                              ).withValues(alpha: 0.15),
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
                                            Text(
                                              'confirm_delete'.tr(),
                                              style: const TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF000000),
                                                fontFamily: 'SF Pro Display',
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              'delete_cv_confirmation'.tr(),
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
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
                                                    onTap: () => Navigator.of(
                                                      context,
                                                    ).pop(),
                                                    behavior:
                                                        HitTestBehavior.opaque,
                                                    child: Container(
                                                      height: 48,
                                                      alignment:
                                                          Alignment.center,
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                          0xFFF1F5F9,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        'cancel'.tr(),
                                                        style: const TextStyle(
                                                          color: Color(
                                                            0xFF000000,
                                                          ),
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontFamily:
                                                              'SF Pro Display',
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: GestureDetector(
                                                    onTap: () {
                                                      Navigator.of(
                                                        context,
                                                      ).pop();
                                                      setState(() {
                                                        _cvBytes = null;
                                                        _cvName = null;
                                                        _existingCvUrl = null;
                                                        _isCvUploaded = false;
                                                      });
                                                    },
                                                    behavior:
                                                        HitTestBehavior.opaque,
                                                    child: Container(
                                                      height: 48,
                                                      alignment:
                                                          Alignment.center,
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                          0xFFEF4444,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color:
                                                                const Color(
                                                                  0xFFEF4444,
                                                                ).withValues(
                                                                  alpha: 0.2,
                                                                ),
                                                            blurRadius: 8,
                                                            offset:
                                                                const Offset(
                                                                  0,
                                                                  4,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                      child: Text(
                                                        'delete'.tr(),
                                                        style: const TextStyle(
                                                          color: Color(
                                                            0xFFFFFFFF,
                                                          ),
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontFamily:
                                                              'SF Pro Display',
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
                                  ),
                                ),
                              );
                            },
                          );
                        },
                        onPrevStep: () => setState(() => _activeTabIndex = 1),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
  final bool isChecking;
  final Uint8List? profileImageBytes;
  final String? profileImageName;
  final String? existingProfileImageUrl;
  final VoidCallback? onUploadProfileTap;
  final VoidCallback? onDeleteProfileTap;
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
    this.isChecking = false,
    this.profileImageBytes,
    this.profileImageName,
    this.existingProfileImageUrl,
    this.onUploadProfileTap,
    this.onDeleteProfileTap,
    required this.relationshipStatus,
    required this.onRelationshipStatusChanged,
  });

  final Color formBgGrey = const Color(0xFFF2F3F6);

  void _showCupertinoDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required ValueChanged<DateTime> onDateSelected,
  }) {
    final now = DateTime.now();
    final maximumDate = DateTime(now.year - 18, now.month, now.day);
    DateTime selected = initialDate;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Date Picker',
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          child: FadeTransition(
            opacity: anim,
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 40,
              ),
              child: Center(
                child: StatefulBuilder(
                  builder: (_, setPickerState) {
                    return Container(
                      width: 380,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF0247C4,
                            ).withValues(alpha: 0.18),
                            blurRadius: 40,
                            offset: const Offset(0, 12),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                            child: Row(
                              children: [
                                const Icon(
                                  CupertinoIcons.calendar,
                                  size: 20,
                                  color: Color(0xFF0247C4),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'date_of_birth'.tr(),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF111827),
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                const Icon(
                                  CupertinoIcons.exclamationmark_circle,
                                  size: 14,
                                  color: Color(0xFF6B7280),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'worker_must_be_18'.tr(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 200,
                            child: CupertinoDatePicker(
                              mode: CupertinoDatePickerMode.date,
                              initialDateTime: initialDate,
                              minimumDate: DateTime(1950),
                              maximumDate: maximumDate,
                              onDateTimeChanged: (DateTime newDate) {
                                setPickerState(() {
                                  selected = newDate;
                                });
                              },
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => Navigator.of(ctx).pop(),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF3F4F6),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'cancel'.tr(),
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF374151),
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      onDateSelected(selected);
                                      Navigator.of(ctx).pop();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0247C4),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'done'.tr(),
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
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
                            isEmail: true,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildInputField(
                            'contact_no_label'.tr(),
                            'enter_contact_number'.tr(),
                            controller: phoneController,
                            isContact: true,
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
                            isNationalId: true,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildInputField(
                            'religion_title'.tr(),
                            'enter_your_religion'.tr(),
                            controller: religionController,
                            isReligion: true,
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
                              final now = DateTime.now();
                              final minimumDob = DateTime(1950);
                              final maximumDob = DateTime(
                                now.year - 18,
                                now.month,
                                now.day,
                              );
                              final parsedDob = AppDateUtils.parseDateString(
                                dobController.text.trim(),
                              );
                              final initialDob = parsedDob == null
                                  ? maximumDob
                                  : parsedDob.isBefore(minimumDob)
                                  ? minimumDob
                                  : parsedDob.isAfter(maximumDob)
                                  ? maximumDob
                                  : parsedDob;
                              _showCupertinoDatePicker(
                                context: context,
                                initialDate: initialDob,
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

            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                      height: 360,
                      width: 360,
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
                      child: _buildProfileContent(context),
                    ),
                  ),
                  const SizedBox(height: 20),

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
                      const SizedBox(width: 120),
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

  Widget _buildProfileContent(BuildContext context) {
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
            errorBuilder: (context, error, stackTrace) =>
                _buildUploadPlaceholder(),
          )
        else
          Image(
            image: getProfileImageProvider(existingProfileImageUrl),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _buildUploadPlaceholder(),
          ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: Colors.black.withValues(alpha: 0.54),
            child: Text(
              profileImageName ?? 'worker_profile'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
        ),
        if (onDeleteProfileTap != null)
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              onTap: () {
                showGeneralDialog(
                  context: context,
                  barrierDismissible: true,
                  barrierLabel: 'RemoveProfileImage',
                  barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.3),
                  transitionDuration: const Duration(milliseconds: 400),
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const SizedBox(),
                  transitionBuilder:
                      (context, animation, secondaryAnimation, child) {
                        final curve = CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutBack,
                        );
                        return BackdropFilter(
                          filter: ui.ImageFilter.blur(
                            sigmaX: 12 * animation.value,
                            sigmaY: 12 * animation.value,
                          ),
                          child: FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: curve,
                              child: Dialog(
                                backgroundColor: Colors.transparent,
                                child: Container(
                                  width: 380,
                                  padding: const EdgeInsets.all(28),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFFFF),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF000000,
                                        ).withValues(alpha: 0.15),
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
                                      Text(
                                        'remove_profile_image'.tr(),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF000000),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'remove_profile_image_desc'.tr(),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
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
                                              onTap: () =>
                                                  Navigator.of(context).pop(),
                                              behavior: HitTestBehavior.opaque,
                                              child: Container(
                                                height: 48,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFF1F5F9,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  'cancel'.tr(),
                                                  style: const TextStyle(
                                                    color: Color(0xFF000000),
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.bold,
                                                    fontFamily:
                                                        'SF Pro Display',
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () {
                                                Navigator.of(context).pop();
                                                onDeleteProfileTap?.call();
                                              },
                                              behavior: HitTestBehavior.opaque,
                                              child: Container(
                                                height: 48,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFEF4444,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: const Color(
                                                        0xFFEF4444,
                                                      ).withValues(alpha: 0.2),
                                                      blurRadius: 8,
                                                      offset: const Offset(
                                                        0,
                                                        4,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                child: Text(
                                                  'remove'.tr(),
                                                  style: const TextStyle(
                                                    color: Color(0xFFFFFFFF),
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.bold,
                                                    fontFamily:
                                                        'SF Pro Display',
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
                            ),
                          ),
                        );
                      },
                );
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.54),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 18),
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
            color: Colors.black.withValues(alpha: 0.54),
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
  final Color formBgGrey = const Color(0xFFF2F3F6);
  late DateTime _calendarMonth;
  DateTime? _selectedDate;
  bool _dependenciesReady = false;

  @override
  void initState() {
    super.initState();
    _parseSelectedDate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    _dependenciesReady = true;
    _parseSelectedDate(includeLocalizedMonth: true);
  }

  @override
  void didUpdateWidget(covariant ExperienceFormSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedJoiningDate != oldWidget.selectedJoiningDate) {
      _parseSelectedDate(includeLocalizedMonth: true);
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

  void _parseSelectedDate({bool includeLocalizedMonth = false}) {
    final dateStr = widget.selectedJoiningDate?.trim() ?? '';
    DateTime? parsedDate;

    if (dateStr.isNotEmpty) {
      parsedDate = AppDateUtils.parseDateString(dateStr);

      if (parsedDate == null) {
        final normalized = dateStr.replaceAll(',', '').trim();
        final parts = normalized.split(RegExp(r'\s+'));
        if (parts.length == 3) {
          final day = int.tryParse(parts[1]);
          final year = int.tryParse(parts[2]);
          final englishMonthIndex = _months.indexWhere(
            (month) => month.toLowerCase() == parts[0].toLowerCase(),
          );
          final localizedMonthIndex = includeLocalizedMonth
              ? List<int>.generate(12, (index) => index + 1).indexWhere(
                  (month) =>
                      DateFormat(
                        'MMMM',
                        context.locale.toString(),
                      ).format(DateTime(2000, month)).toLowerCase() ==
                      parts[0].toLowerCase(),
                )
              : -1;
          final monthIndex = englishMonthIndex >= 0
              ? englishMonthIndex
              : localizedMonthIndex;
          if (day != null &&
              year != null &&
              monthIndex >= 0 &&
              day >= 1 &&
              day <= DateTime(year, monthIndex + 2, 0).day) {
            parsedDate = DateTime(year, monthIndex + 1, day);
          }
        }
      }
    }

    _selectedDate = parsedDate == null
        ? null
        : DateTime(parsedDate.year, parsedDate.month, parsedDate.day);
    _calendarMonth = parsedDate == null
        ? DateTime(DateTime.now().year, DateTime.now().month, 1)
        : DateTime(parsedDate.year, parsedDate.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
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
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 32),

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
                            Flexible(
                              child: Text(
                                '${DateFormat('MMMM', context.locale.toString()).format(_calendarMonth).toUpperCase()} ${_calendarMonth.year}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  letterSpacing: 1.0,
                                  fontFamily: 'SF Pro Display',
                                ),
                                overflow: TextOverflow.ellipsis,
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
                              child: _buildDayPill('weekday_sun'.tr(), true),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _buildDayPill('weekday_mon'.tr(), false),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _buildDayPill('weekday_tue'.tr(), false),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _buildDayPill('weekday_wed'.tr(), false),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _buildDayPill('weekday_thu'.tr(), false),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _buildDayPill(
                                'weekday_fri'.tr(),
                                false,
                                isGreen: true,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _buildDayPill('weekday_sat'.tr(), false),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

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
                            final trailingPadCount =
                                42 - (padCount + daysInMonth);

                            return GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 7,
                              mainAxisExtent: 28,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 4,
                              children: [
                                for (int i = 0; i < padCount; i++)
                                  const SizedBox.shrink(),
                                for (int day = 1; day <= daysInMonth; day++)
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      final selected = DateTime(
                                        _calendarMonth.year,
                                        _calendarMonth.month,
                                        day,
                                      );
                                      final now = DateTime.now();
                                      final today = DateTime(
                                        now.year,
                                        now.month,
                                        now.day,
                                      );
                                      if (selected.isAfter(today)) {
                                        FlashySnackBar.show(
                                          context,
                                          message:
                                              'joining_date_cannot_be_future'
                                                  .tr(),
                                          isError: true,
                                        );
                                        return;
                                      }
                                      final monthName = _localizedMonth(
                                        selected.month,
                                      );
                                      final formatted =
                                          '$monthName ${selected.day}, ${selected.year}';
                                      widget.onJoiningDateChanged?.call(
                                        formatted,
                                      );
                                      setState(() {
                                        _selectedDate = selected;
                                      });
                                      FlashySnackBar.show(
                                        context,
                                        message: 'joining_date_is'.tr(
                                          namedArgs: {'date': formatted},
                                        ),
                                        isError: false,
                                      );
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
                                        final cellDate = DateTime(
                                          _calendarMonth.year,
                                          _calendarMonth.month,
                                          day,
                                        );
                                        final isSunday = cellDate.weekday == 7;
                                        final isFriday = cellDate.weekday == 5;
                                        final dayColor = isSunday
                                            ? const Color(0xFFFF0004)
                                            : (isFriday
                                                  ? const Color(0xFF4AC000)
                                                  : Colors.black);
                                        final selectedBg = isFriday
                                            ? const Color(0xFF4AC000)
                                            : const Color(0xFF0B50C3);
                                        return Container(
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? selectedBg
                                                : Color(0xFFFFFFFF),
                                            border: isSelected
                                                ? null
                                                : Border.all(
                                                    color: isSunday
                                                        ? const Color(
                                                            0xFFFF0004,
                                                          ).withValues(
                                                            alpha: 0.4,
                                                          )
                                                        : (isFriday
                                                              ? const Color(
                                                                  0xFF4AC000,
                                                                ).withValues(
                                                                  alpha: 0.4,
                                                                )
                                                              : Colors
                                                                    .grey
                                                                    .shade300),
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
                                                  : dayColor,
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
                                for (int i = 0; i < trailingPadCount; i++)
                                  const SizedBox.shrink(),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Text(
          'salary_section'.tr(),
          style: TextStyle(
            color: Color(0xFF000000),
            fontSize: 20,
            fontWeight: FontWeight.w800,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: Container(
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
                            selectedValue:
                                widget.currencyController.text.isEmpty
                                ? 'USD'
                                : widget.currencyController.text,
                            hint: 'enter_your_currency'.tr(),
                            items: CurrencyUtils.supportedCodes,
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
                            isAmount: true,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildInputField(
                            'annual_leaves_days'.tr(),
                            'hint_annual_leaves'.tr(),
                            controller: widget.annualLeavesController,
                            isLeaves: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 32),
            const Expanded(flex: 2, child: SizedBox()),
          ],
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
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
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
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 36,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'id_card_label'.tr(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final h = (constraints.maxWidth * 1.8).clamp(
                        360.0,
                        700.0,
                      );
                      return Container(
                        height: h,
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F3F6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: onUploadFrontTap,
                                  child: Text(
                                    'upload_front_side'.tr(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                if (frontIdBytes != null ||
                                    (existingFrontIdUrl != null &&
                                        existingFrontIdUrl!.isNotEmpty))
                                  GestureDetector(
                                    onTap: onUploadFrontTap,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF000000),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'edit'.tr(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                              fontFamily: 'SF Pro Display',
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          SvgPicture.asset(
                                            'assets/edit_icon.svg',
                                            height: 14,
                                            width: 14,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildIdUploadBox(
                              label: 'upload_front_id_hint'.tr(),
                              bytes: frontIdBytes,
                              fileName: frontIdName,
                              existingUrl: existingFrontIdUrl,
                              onTap: onUploadFrontTap,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: onUploadBackTap,
                                  child: Text(
                                    'upload_back_side'.tr(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                if (backIdBytes != null ||
                                    (existingBackIdUrl != null &&
                                        existingBackIdUrl!.isNotEmpty))
                                  GestureDetector(
                                    onTap: onUploadBackTap,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF000000),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'edit'.tr(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                              fontFamily: 'SF Pro Display',
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          SvgPicture.asset(
                                            'assets/edit_icon.svg',
                                            height: 14,
                                            width: 14,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
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
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),

            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 36,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'upload_cv_label'.tr(),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const Spacer(),
                        if (isCvUploaded) ...[
                          GestureDetector(
                            onTap: onUploadCvTap,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF000000),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'edit'.tr(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  SvgPicture.asset(
                                    'assets/edit_icon.svg',
                                    height: 14,
                                    width: 14,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
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
    var sourceName = fileName?.trim() ?? '';
    if (sourceName.isEmpty && existingUrl != null && existingUrl.isNotEmpty) {
      try {
        final decodedPath = Uri.decodeComponent(Uri.parse(existingUrl).path);
        sourceName = decodedPath.split('/').last;
      } catch (_) {
        sourceName = existingUrl.split('?').first.split('/').last;
      }
    }
    final lowerSourceName = sourceName.toLowerCase();
    final bool isPdf =
        lowerSourceName.endsWith('.pdf') ||
        (existingUrl?.startsWith('data:application/pdf') ?? false);
    final bool isImage =
        lowerSourceName.endsWith('.jpg') ||
        lowerSourceName.endsWith('.jpeg') ||
        lowerSourceName.endsWith('.png') ||
        lowerSourceName.endsWith('.gif') ||
        lowerSourceName.endsWith('.bmp') ||
        lowerSourceName.endsWith('.webp') ||
        (existingUrl?.startsWith('data:image') ?? false);

    return GestureDetector(
      onTap: hasFile ? null : onTap,
      child: Container(
        height: 250,
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
                    PdfPagePreview(cvBytes: bytes, existingCvUrl: existingUrl)
                  else if (bytes != null && isImage)
                    Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildIdPlaceholder(label, hasFile),
                    )
                  else if (existingUrl != null &&
                      existingUrl.startsWith('http') &&
                      isImage)
                    CachedNetworkImage(
                      imageUrl: existingUrl,
                      fit: BoxFit.contain,
                      placeholder: (context, url) => Shimmer.fromColors(
                        baseColor: Colors.grey.shade300,
                        highlightColor: Colors.grey.shade100,
                        child: Container(
                          color: Colors.grey.shade300,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                      errorWidget: (context, url, error) =>
                          _buildIdPlaceholder(label, hasFile),
                    )
                  else if (existingUrl != null &&
                      existingUrl.startsWith('data:image'))
                    Image.memory(
                      base64Decode(existingUrl.split(',').last),
                      fit: BoxFit.contain,
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
                      color: Colors.black.withValues(alpha: 0.54),
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
        Image.asset(
          'assets/Id card.png',
          width: 50,
          height: 50,
          fit: BoxFit.contain,
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

  Widget _buildCvPreview(BuildContext buildContext) {
    final lowerName = (cvName ?? '').toLowerCase();
    final isImage =
        cvName != null &&
        (lowerName.endsWith('.png') ||
            lowerName.endsWith('.jpg') ||
            lowerName.endsWith('.jpeg') ||
            lowerName.endsWith('.gif') ||
            lowerName.endsWith('.bmp') ||
            lowerName.endsWith('.webp'));
    final isPdf = cvName != null && lowerName.endsWith('.pdf');
    final isDoc =
        cvName != null &&
        (lowerName.endsWith('.doc') || lowerName.endsWith('.docx'));

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final containerHeight = (availableWidth * 1.8).clamp(360.0, 700.0);
        return Container(
          height: containerHeight,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFF2F3F6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey.shade200, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: isImage
                  ? Center(
                      child: AspectRatio(
                        aspectRatio: 1 / 1.414, // A4 page ratio like PDF
                        child: Container(
                          color: Colors.white,
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
                                        placeholder: (context, url) =>
                                            Shimmer.fromColors(
                                              baseColor: Colors.grey.shade300,
                                              highlightColor:
                                                  Colors.grey.shade100,
                                              child: Container(
                                                color: Colors.grey.shade300,
                                                width: double.infinity,
                                                height: double.infinity,
                                              ),
                                            ),
                                        errorWidget: (context, url, error) =>
                                            const Center(
                                              child: Icon(
                                                Icons.broken_image,
                                                size: 48,
                                              ),
                                            ),
                                      )
                                    : const SizedBox.shrink()),
                        ),
                      ),
                    )
                  : (isPdf || isDoc)
                  ? Stack(
                      children: [
                        if (cvBytes == null &&
                            (existingCvUrl == null || existingCvUrl!.isEmpty))
                          Container(
                            height: double.infinity,
                            width: double.infinity,
                            color: Colors.grey.shade200,
                          ),
                        if (isPdf &&
                            (cvBytes != null ||
                                (existingCvUrl != null &&
                                    existingCvUrl!.isNotEmpty)))
                          Positioned.fill(
                            child: IgnorePointer(
                              child: PdfPagePreview(
                                cvBytes: cvBytes,
                                existingCvUrl: existingCvUrl,
                              ),
                            ),
                          ),
                        if (isDoc &&
                            (cvBytes != null ||
                                (existingCvUrl != null &&
                                    existingCvUrl!.isNotEmpty)))
                          Center(
                            child: AspectRatio(
                              aspectRatio: 1 / 1.414, // A4 page ratio like PDF
                              child: IgnorePointer(
                                child: DocPreview(
                                  docBytes: cvBytes,
                                  docName: cvName,
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
                  : Center(
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
                            cvName ?? 'upload_cv_label'.tr(),
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
        );
      },
    );
  }

  Widget _buildCvContainer({required Widget overlay}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final containerHeight = (availableWidth * 1.8).clamp(360.0, 700.0);
        return Container(
          height: containerHeight,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFF2F3F6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey.shade200, width: 1),
          ),
          child: Center(child: overlay),
        );
      },
    );
  }
}

Widget _buildInputField(
  String label,
  String hint, {
  IconData? suffixIcon,
  bool isDropdown = false,
  bool isTextArea = false,
  bool isEmail = false,
  bool isAmount = false,
  bool isLeaves = false,
  bool isContact = false,
  bool isNationalId = false,
  bool isReligion = false,
  TextEditingController? controller,
  TextAlign textAlign = TextAlign.start,
}) {
  final isEmailField = isEmail;
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
                    isAmount
                        ? RegExp(r'^\d*\.?\d*')
                        : (isNationalId
                              ? RegExp(r'^[\d-]*')
                              : isContact
                              ? RegExp(r'[0-9+\-\s()]')
                              : RegExp(r'^\d*')),
                  ),
                  if (isAmount) LengthLimitingTextInputFormatter(15),
                  if (isContact) LengthLimitingTextInputFormatter(20),
                  if (isNationalId) LengthLimitingTextInputFormatter(20),
                  if (isLeaves) ...[
                    LengthLimitingTextInputFormatter(3),
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      if (newValue.text.isEmpty) return newValue;
                      final value = int.tryParse(newValue.text);
                      if (value == null || value > 366) {
                        return oldValue;
                      }
                      return newValue;
                    }),
                  ],
                ]
              : () {
                  final list = <TextInputFormatter>[];
                  if (isEmailField)
                    list.add(LengthLimitingTextInputFormatter(100));
                  if (isReligion)
                    list.add(LengthLimitingTextInputFormatter(30));
                  return list.isEmpty ? null : list;
                }(),
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
  final selectedColor = Color(0xFF0247C4);
  final borderColor = isSelected ? selectedColor : Color(0xFF000000);
  final textColor = isSelected ? selectedColor : Color(0xFF000000);

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
            border: Border.all(color: borderColor, width: 2),
          ),
          child: isSelected
              ? Center(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selectedColor,
                    ),
                  ),
                )
              : const SizedBox(),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 16,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ],
    ),
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

class DocPreview extends StatefulWidget {
  final Uint8List? docBytes;
  final String? docName;

  const DocPreview({super.key, this.docBytes, this.docName});

  @override
  State<DocPreview> createState() => _DocPreviewState();
}

class _DocPreviewState extends State<DocPreview> {
  String _content = '';
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _extractContent();
  }

  @override
  void didUpdateWidget(covariant DocPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.docBytes != oldWidget.docBytes) {
      _extractContent();
    }
  }

  Future<void> _extractContent() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _content = '';
    });

    final isDocx = (widget.docName ?? '').toLowerCase().endsWith('.docx');
    final bytes = widget.docBytes;

    if (bytes == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'documentation'.tr();
        });
      }
      return;
    }

    try {
      String text = '';
      if (isDocx) {
        try {
          final archive = ZipDecoder().decodeBytes(bytes);
          final docFile = archive.files.firstWhere(
            (file) => file.name == 'word/document.xml',
            orElse: () => throw StateError('no_document_xml'.tr()),
          );
          final xmlString = utf8.decode(docFile.content as List<int>);

          final textRegex = RegExp(r'<w:t[^>]*>([^<]*)</w:t>');
          final paragraphs = xmlString.split('</w:p>');
          final lines = <String>[];
          for (final paragraph in paragraphs) {
            final matches = textRegex
                .allMatches(paragraph)
                .map((m) => m.group(1) ?? '')
                .join();
            if (matches.trim().isNotEmpty) lines.add(matches);
          }
          text = lines.join('\n');
        } catch (e) {
          rethrow;
        }
      }

      if (text.trim().isEmpty) {
        setState(() {
          _isLoading = false;
          _content = '';
        });
        return;
      }

      if (mounted) {
        setState(() {
          _content = text;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            ),
            const SizedBox(height: 8),
            Text(
              'documentation'.tr(),
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null || _content.trim().isEmpty) {
      final isDocx = (widget.docName ?? '').toLowerCase().endsWith('.docx');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isDocx ? Icons.article_outlined : Icons.description_outlined,
              size: 64,
              color: const Color(0xFF0B50C3),
            ),
            const SizedBox(height: 8),
            Text(
              widget.docName ?? 'documentation'.tr(),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontFamily: 'SF Pro Display',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Text(
          _content,
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: Color(0xFF333333),
            fontFamily: 'SF Pro Display',
          ),
        ),
      ),
    );
  }
}

class PdfPagePreview extends StatefulWidget {
  final Uint8List? cvBytes;
  final String? existingCvUrl;
  final BoxFit fit;

  const PdfPagePreview({
    super.key,
    this.cvBytes,
    this.existingCvUrl,
    this.fit = BoxFit.contain,
  });

  @override
  State<PdfPagePreview> createState() => _PdfPagePreviewState();
}

class _PdfPagePreviewState extends State<PdfPagePreview> {
  List<Uint8List> _pageImages = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _renderPdfPages();
  }

  @override
  void didUpdateWidget(covariant PdfPagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cvBytes != oldWidget.cvBytes ||
        widget.existingCvUrl != oldWidget.existingCvUrl) {
      _renderPdfPages();
    }
  }

  Future<void> _renderPdfPages() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _pageImages = [];
    });

    PdfDocument? document;
    io.HttpClient? client;

    try {
      if (widget.cvBytes != null) {
        document = await PdfDocument.openData(widget.cvBytes!);
      } else if (widget.existingCvUrl != null &&
          widget.existingCvUrl!.isNotEmpty) {
        if (widget.existingCvUrl!.startsWith('http')) {
          client = io.HttpClient()
            ..connectionTimeout = const Duration(seconds: 15);
          final request = await client
              .getUrl(Uri.parse(widget.existingCvUrl!))
              .timeout(const Duration(seconds: 15));
          final response = await request.close().timeout(
            const Duration(seconds: 20),
          );

          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw io.HttpException(
              'HTTP ${response.statusCode}',
              uri: Uri.parse(widget.existingCvUrl!),
            );
          }

          const maxPreviewBytes = 20 * 1024 * 1024;
          if (response.contentLength > maxPreviewBytes) {
            throw const FormatException('PDF preview file is too large.');
          }

          final bytesBuilder = BytesBuilder();
          var receivedBytes = 0;
          await for (final chunk in response) {
            receivedBytes += chunk.length;
            if (receivedBytes > maxPreviewBytes) {
              throw const FormatException('PDF preview file is too large.');
            }
            bytesBuilder.add(chunk);
          }

          document = await PdfDocument.openData(bytesBuilder.takeBytes());
        } else if (widget.existingCvUrl!.startsWith('data:application/pdf')) {
          final base64Content = widget.existingCvUrl!.split(',').last;
          document = await PdfDocument.openData(base64Decode(base64Content));
        }
      }

      if (document == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      final pages = <Uint8List>[];
      if (document.pagesCount >= 1) {
        final page = await document.getPage(1);
        try {
          final pageImage = await page.render(
            width: page.width * 3,
            height: page.height * 3,
            format: PdfPageImageFormat.png,
            backgroundColor: '#ffffff',
          );
          if (pageImage != null) {
            pages.add(pageImage.bytes);
          }
        } finally {
          await page.close();
        }
      }

      if (mounted) {
        setState(() {
          _pageImages = pages;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    } finally {
      if (document != null) {
        try {
          await document.close();
        } catch (_) {}
      }
      client?.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            ),
            const SizedBox(height: 8),
            Text(
              'documentation'.tr(),
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return const SizedBox.shrink();
    }
    if (_pageImages.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
        child: SizedBox.expand(
          child: Image.memory(
            _pageImages[0],
            fit: widget.fit,
            filterQuality: FilterQuality.high,
            width: double.infinity,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
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
