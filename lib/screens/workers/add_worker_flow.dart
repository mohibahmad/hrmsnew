import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hrms/riverpod_providers.dart';
import 'package:hrms/services/core/auth_service.dart';
import 'package:hrms/services/core/dummy_data.dart';
import 'package:hrms/services/core/error_reporter.dart';
import 'package:hrms/services/core/firestore_service.dart';
import 'package:hrms/services/core/preferences_service.dart';
import 'package:hrms/services/time_off/time_off_service.dart';
import 'package:hrms/services/core/upload_service.dart';
import 'package:hrms/core/utils/utils.dart';
import 'package:hrms/widgets/common/clickable_gesture_detector.dart';
import 'package:hrms/widgets/dialogs/unsaved_changes_dialog.dart';
import 'package:hrms/widgets/workers/delete_cv_dialog.dart';
import 'package:hrms/widgets/workers/documentation_section.dart';
import 'package:hrms/widgets/workers/experience_form_section.dart';
import 'package:hrms/widgets/workers/worker_detail_form_section.dart';

export 'package:hrms/widgets/workers/document_preview.dart';
export 'package:hrms/widgets/workers/documentation_section.dart';
export 'package:hrms/widgets/workers/experience_form_section.dart';
export 'package:hrms/widgets/workers/worker_detail_form_section.dart';
export 'package:hrms/widgets/workers/worker_form_fields.dart';

class AddNewWorkerFlow extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final Map<String, dynamic>? workerToEdit;

  const AddNewWorkerFlow({super.key, this.onBack, this.workerToEdit});

  @override
  ConsumerState<AddNewWorkerFlow> createState() => _AddNewWorkerFlowState();
}

class _AddNewWorkerFlowState extends ConsumerState<AddNewWorkerFlow> {
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
  final _salaryAmountController = TextEditingController();
  final _leavePolicyController = TextEditingController(text: 'Standard');
  final _annualLeavesController = TextEditingController();
  final _sickLeavesController = TextEditingController();
  final _casualLeavesController = TextEditingController();
  final _medicalLeavesController = TextEditingController();
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
  DateTime? _selectedDob;
  DateTime? _selectedJoiningDate;

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
    if (_salaryAmountController.text.trim().isNotEmpty) return true;
    if (_leavePolicyController.text.trim() != 'Standard') return true;
    if (_annualLeavesController.text.trim().isNotEmpty) return true;
    if (_sickLeavesController.text.trim().isNotEmpty) return true;
    if (_casualLeavesController.text.trim().isNotEmpty) return true;
    if (_medicalLeavesController.text.trim().isNotEmpty) return true;
    if ((_joiningDate ?? '').trim().isNotEmpty &&
        _joiningDate != AppDateUtils.formatDate(DateTime.now())) {
      return true;
    }
    if (_frontIdBytes != null) return true;
    if (_backIdBytes != null) return true;
    if (_cvBytes != null) return true;
    if (_profileImageBytes != null) return true;
    return false;
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) return true;
    return UnsavedChangesDialog.show(context);
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
      _selectedDob = AppDateUtils.dateFromValue(widget.workerToEdit!['dob']);
      _dobController.text = _selectedDob == null
          ? (widget.workerToEdit!['dob'] ?? '').toString()
          : AppDateUtils.formatDate(_selectedDob!);

      _genderController.text = (widget.workerToEdit!['gender'] ?? 'Male')
          .toString();
      if (_genderController.text.isEmpty) _genderController.text = 'Male';

      _addressController.text = (widget.workerToEdit!['address'] ?? '')
          .toString();
      _positionController.text = (widget.workerToEdit!['position'] ?? '')
          .toString();

      _type1Controller.text =
          (widget.workerToEdit!['workType'] ??
                  widget.workerToEdit!['type1'] ??
                  'Full-Time')
              .toString();
      if (_type1Controller.text.isEmpty) _type1Controller.text = 'Full-Time';

      _type2Controller.text =
          (widget.workerToEdit!['attendanceType'] ??
                  widget.workerToEdit!['type2'] ??
                  'On-Site')
              .toString();
      if (_type2Controller.text.isEmpty) _type2Controller.text = 'On-Site';

      _experienceLevelController.text =
          (widget.workerToEdit!['experienceLevel'] ?? 'Mid-Level').toString();
      if (_experienceLevelController.text.isEmpty) {
        _experienceLevelController.text = 'Mid-Level';
      }

      _educationController.text =
          (widget.workerToEdit!['education'] ?? 'Bachelor').toString();
      if (_educationController.text.trim() == 'Bachelors') {
        _educationController.text = 'Bachelor';
      }
      if (_educationController.text.isEmpty) {
        _educationController.text = 'Bachelor';
      }

      _salaryAmountController.text = CurrencyUtils.formatWithCommas(
        widget.workerToEdit!['salaryAmount'],
      );

      _leavePolicyController.text =
          (widget.workerToEdit!['leavePolicy'] ?? 'Standard').toString();
      if (_leavePolicyController.text.isEmpty) {
        _leavePolicyController.text = 'Standard';
      }

      _annualLeavesController.text = LeaveBalanceHelper.leaveDaysText(
        widget.workerToEdit!['annualLeaves'],
      );
      _sickLeavesController.text = LeaveBalanceHelper.leaveDaysText(
        widget.workerToEdit!['sickLeaves'],
      );
      _casualLeavesController.text = LeaveBalanceHelper.leaveDaysText(
        widget.workerToEdit!['casualLeaves'],
      );
      _medicalLeavesController.text = LeaveBalanceHelper.leaveDaysText(
        widget.workerToEdit!['medicalLeaves'],
      );

      _relationshipStatus =
          (widget.workerToEdit!['relationshipStatus'] ?? 'Single').toString();
      if (_relationshipStatus.isEmpty) _relationshipStatus = 'Single';

      _existingProfileImageUrl = widget.workerToEdit!['profileImage']
          ?.toString();

      String? firstNonEmpty(List<String?> values) {
        for (final v in values) {
          final s = v?.toString();
          if (s != null && s.isNotEmpty && s != 'null') return s;
        }
        return null;
      }

      _existingFrontIdUrl = firstNonEmpty([
        widget.workerToEdit!['frontId']?.toString(),
        widget.workerToEdit!['front_id']?.toString(),
        widget.workerToEdit!['idFront']?.toString(),
        widget.workerToEdit!['frontID']?.toString(),
        widget.workerToEdit!['id_front']?.toString(),
      ]);
      if (_existingFrontIdUrl != null && _existingFrontIdUrl!.isNotEmpty) {
        _frontIdName = cleanUploadedDocumentFileName(_existingFrontIdUrl!);
      }

      _existingBackIdUrl = firstNonEmpty([
        widget.workerToEdit!['backId']?.toString(),
        widget.workerToEdit!['back_id']?.toString(),
        widget.workerToEdit!['idBack']?.toString(),
        widget.workerToEdit!['backID']?.toString(),
        widget.workerToEdit!['id_back']?.toString(),
      ]);
      if (_existingBackIdUrl != null && _existingBackIdUrl!.isNotEmpty) {
        _backIdName = cleanUploadedDocumentFileName(_existingBackIdUrl!);
      }

      _existingCvUrl = widget.workerToEdit!['cv']?.toString();
      if (_existingCvUrl != null && _existingCvUrl!.isNotEmpty) {
        _isCvUploaded = true;
        _cvName =
            firstNonEmpty([
              widget.workerToEdit!['cvFileName']?.toString(),
              widget.workerToEdit!['cv_file_name']?.toString(),
              widget.workerToEdit!['cvName']?.toString(),
            ]) ??
            cleanUploadedDocumentFileName(_existingCvUrl!);
      }
      _joiningDate = _workerDateText(widget.workerToEdit!['joiningDate']);
      _selectedJoiningDate = AppDateUtils.dateFromValue(
        widget.workerToEdit!['joiningDate'],
      );
    } else {
      final today = DateTime.now();
      _selectedJoiningDate = DateTime(today.year, today.month, today.day);
      _joiningDate = AppDateUtils.formatDate(_selectedJoiningDate!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);

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
    _salaryAmountController.addListener(_onControllerChanged);
    _leavePolicyController.addListener(_onControllerChanged);
    _annualLeavesController.addListener(_onControllerChanged);
    _sickLeavesController.addListener(_onControllerChanged);
    _casualLeavesController.addListener(_onControllerChanged);
    _medicalLeavesController.addListener(_onControllerChanged);

    _annualLeavesController.addListener(_clampAnnualLeaves);
    _sickLeavesController.addListener(_clampSickLeaves);
    _casualLeavesController.addListener(_clampCasualLeaves);
    _medicalLeavesController.addListener(_clampMedicalLeaves);

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
      final annual = LeaveBalanceHelper.leaveDaysText(
        active['annualLeaveDays'] ?? 0,
      );
      final sick = LeaveBalanceHelper.leaveDaysText(active['sickLeaves'] ?? 0);
      final casual = LeaveBalanceHelper.leaveDaysText(
        active['casualLeaves'] ?? 0,
      );
      final medical = LeaveBalanceHelper.leaveDaysText(
        active['medicalLeaves'] ?? 0,
      );
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
        if (_medicalLeavesController.text.trim().isEmpty) {
          _medicalLeavesController.text = medical;
        }
        if (policyName.isNotEmpty &&
            _leavePolicyController.text.trim() == 'Standard') {
          _leavePolicyController.text = policyName;
        }
      });
    } catch (_) {}
  }

  void _clampAnnualLeaves() => _clampLeaveDays(_annualLeavesController);

  void _clampSickLeaves() => _clampLeaveDays(_sickLeavesController);

  void _clampCasualLeaves() => _clampLeaveDays(_casualLeavesController);

  void _clampMedicalLeaves() => _clampLeaveDays(_medicalLeavesController);

  void _clampLeaveDays(TextEditingController controller) {
    final text = controller.text;
    if (text.startsWith('-') || text.startsWith('+')) {
      controller.text = text.replaceAll(RegExp(r'^[+\-]+'), '');
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
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
    final memoryBytes = await file.readAsBytes();
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

  static Future<List<UploadFile>> _prepareUploadFilesBatched({
    required List<
      ({
        String folder,
        String? fileName,
        String fallbackFileName,
        Uint8List bytes,
        bool compressImages,
      })
    >
    specs,
  }) async {
    if (specs.isEmpty) return const [];

    final compressedList = await Future.wait(
      specs.map((spec) async {
        Uint8List bytesToUpload = spec.bytes;
        if (spec.compressImages && bytesToUpload.length > 350 * 1024) {
          try {
            final compressed = await compute(compressImageBytes, bytesToUpload);
            if (compressed.isNotEmpty) {
              bytesToUpload = compressed;
            }
          } catch (_) {}
        }
        return bytesToUpload;
      }),
    );

    final files = <UploadFile>[];
    for (var i = 0; i < specs.length; i++) {
      final spec = specs[i];
      final fileName = spec.fileName?.trim().isNotEmpty == true
          ? spec.fileName!.trim()
          : spec.fallbackFileName;
      final mimeType = mimeTypeForExtension(
        fileName,
        fallback: 'application/octet-stream',
      );

      files.add(
        UploadFile(
          folder: spec.folder,
          fileName: fileName,
          bytes: compressedList[i],
          mimeType: mimeType,
        ),
      );
    }
    return files;
  }

  String? _workerDateText(dynamic value) {
    if (value == null) return null;
    final date = AppDateUtils.dateFromValue(value);
    return date != null ? AppDateUtils.formatDate(date) : value.toString();
  }

  DateTime? _parseWorkerDate(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;

    final parsed =
        AppDateUtils.parseDdMmYyyy(text) ?? AppDateUtils.parseDateString(text);
    if (parsed != null) {
      return DateTime(parsed.year, parsed.month, parsed.day);
    }

    final normalized = text.replaceAll(',', '').trim();
    final parts = normalized.split(RegExp(r'\s+'));
    if (parts.length == 3) {
      final day = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      final englishMonthIndex = LocalizationHelper.englishMonthNames.indexWhere(
        (month) => month.toLowerCase() == parts[0].toLowerCase(),
      );
      final localizedMonthIndex = List<int>.generate(12, (index) => index + 1)
          .indexWhere(
            (month) =>
                LocalizationHelper.localizedMonth(month).toLowerCase() ==
                parts[0].toLowerCase(),
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
    final sickLeavesText = _sickLeavesController.text.trim();
    final casualLeavesText = _casualLeavesController.text.trim();
    final medicalLeavesText = _medicalLeavesController.text.trim();
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

    if (sickLeavesText.isNotEmpty) {
      final sickLeaves = int.tryParse(sickLeavesText);
      if (sickLeaves == null || sickLeaves < 0) {
        FlashySnackBar.show(
          context,
          message: 'please_enter_sick_leaves'.tr(),
          isError: true,
        );
        return false;
      }
    }

    if (casualLeavesText.isNotEmpty) {
      final casualLeaves = int.tryParse(casualLeavesText);
      if (casualLeaves == null || casualLeaves < 0) {
        FlashySnackBar.show(
          context,
          message: 'please_enter_casual_leaves'.tr(),
          isError: true,
        );
        return false;
      }
    }

    if (medicalLeavesText.isNotEmpty) {
      final medicalLeaves = int.tryParse(medicalLeavesText);
      if (medicalLeaves == null || medicalLeaves < 0) {
        FlashySnackBar.show(
          context,
          message: 'please_enter_medical_leaves'.tr(),
          isError: true,
        );
        return false;
      }
    }

    if (joiningDateText.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_select_a_joining_date'.tr(),
        isError: true,
      );
      return false;
    }

    final joiningDate =
        _selectedJoiningDate ?? AppDateUtils.parseDdMmYyyy(joiningDateText);
    if (joiningDate == null) {
      FlashySnackBar.show(
        context,
        message: '${'joining_date_title'.tr()}: ${'invalid_date_format'.tr()}',
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
      final result = await FilePicker.pickFiles(type: FileType.image);
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
    final dob = _selectedDob ?? AppDateUtils.parseDdMmYyyy(dobStr);
    if (dob == null) {
      FlashySnackBar.show(
        context,
        message: '${'date_of_birth'.tr()}: ${'invalid_date_format'.tr()}',
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
    if (!_sameWorkerDate(_dobController.text, _workerDateText(edit['dob']))) {
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
        (edit['workType'] ?? edit['type1'] ?? 'Full-Time').toString().trim()) {
      return true;
    }
    if (_type2Controller.text.trim() !=
        (edit['attendanceType'] ?? edit['type2'] ?? 'On-Site').toString().trim()) {
      return true;
    }
    if (_experienceLevelController.text.trim() !=
        (edit['experienceLevel'] ?? 'Mid-Level').toString().trim()) {
      return true;
    }
    String normalizeEducation(String value) {
      final trimmed = value.trim();
      return trimmed == 'Bachelors' ? 'Bachelor' : trimmed;
    }

    if (normalizeEducation(_educationController.text) !=
        normalizeEducation((edit['education'] ?? 'Bachelor').toString())) {
      return true;
    }
    if (CurrencyUtils.amountText(
          _salaryAmountController.text.replaceAll(',', ''),
        ) !=
        CurrencyUtils.amountText(edit['salaryAmount'])) {
      return true;
    }
    if (_leavePolicyController.text.trim() !=
        (edit['leavePolicy'] ?? 'Standard').toString().trim()) {
      return true;
    }
    if (_annualLeavesController.text.trim() !=
        LeaveBalanceHelper.leaveDaysText(edit['annualLeaves']).trim()) {
      return true;
    }
    if (_sickLeavesController.text.trim() !=
        LeaveBalanceHelper.leaveDaysText(edit['sickLeaves']).trim()) {
      return true;
    }
    if (_casualLeavesController.text.trim() !=
        LeaveBalanceHelper.leaveDaysText(edit['casualLeaves']).trim()) {
      return true;
    }
    if (_medicalLeavesController.text.trim() !=
        LeaveBalanceHelper.leaveDaysText(edit['medicalLeaves']).trim()) {
      return true;
    }
    if (!_sameWorkerDate(_joiningDate, _workerDateText(edit['joiningDate']))) {
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

  Future<void> _saveWorker() async {
    if (_isSaving) return;

    final name = Validators.titleCase(_nameController.text);
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final nationalId = _nationalIdController.text.trim();
    final religion = Validators.capitalizeFirst(_religionController.text);
    final position = Validators.titleCase(_positionController.text);
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

    if (_fatherNameController.text.trim().isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'field_is_required'.tr(
          namedArgs: {'field': 'worker_father_husband_name'.tr()},
        ),
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

    if (!Validators.isValidPhone(phone)) {
      FlashySnackBar.show(
        context,
        message: 'validation_invalid_phone'.tr(),
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

    if (Validators.isPlaceholderEmailDomain(email)) {
      FlashySnackBar.show(
        context,
        message: 'validation_invalid_email_domain'.tr(),
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

    if (!Validators.isValidNationalId(nationalId)) {
      FlashySnackBar.show(
        context,
        message: 'validation_invalid_national_id'.tr(),
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

    final validatedSalaryAmount = double.tryParse(
      _salaryAmountController.text.trim().replaceAll(',', ''),
    );
    if (validatedSalaryAmount == null || validatedSalaryAmount <= 0) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_salary_amount'.tr(),
        isError: true,
      );
      return;
    }

    final joiningDate =
        _selectedJoiningDate ??
        AppDateUtils.parseDdMmYyyy((_joiningDate ?? '').trim());
    if (joiningDate == null) return;

    final hasProfileImage =
        _profileImageBytes != null ||
        (_existingProfileImageUrl != null &&
            _existingProfileImageUrl!.isNotEmpty);
    if (!hasProfileImage) {
      FlashySnackBar.show(
        context,
        message: 'profile_image_required'.tr(),
        isError: true,
      );
      setState(() => _activeTabIndex = 0);
      return;
    }

    final hasFrontId =
        _frontIdBytes != null ||
        (_existingFrontIdUrl != null && _existingFrontIdUrl!.isNotEmpty);
    if (!hasFrontId) {
      FlashySnackBar.show(
        context,
        message: 'upload_cnic_front_required'.tr(),
        isError: true,
      );
      return;
    }

    final hasBackId =
        _backIdBytes != null ||
        (_existingBackIdUrl != null && _existingBackIdUrl!.isNotEmpty);
    if (!hasBackId) {
      FlashySnackBar.show(
        context,
        message: 'upload_cnic_back_required'.tr(),
        isError: true,
      );
      return;
    }

    final hasCv =
        _cvBytes != null ||
        (_existingCvUrl != null && _existingCvUrl!.isNotEmpty);
    if (!hasCv) {
      FlashySnackBar.show(
        context,
        message: 'upload_cv_required'.tr(),
        isError: true,
      );
      return;
    }

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
      } else if (isEditing) {
        final duplicateField = await _firestore.findDuplicateWorkerField(
          email: email,
          nationalId: nationalId,
          excludeId: widget.workerToEdit!['id']?.toString(),
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
        final uploadFiles = await _prepareUploadFilesBatched(
          specs: [
            if (_profileImageBytes != null)
              (
                folder: 'profile_images',
                fileName: _profileImageName,
                fallbackFileName: 'profile.jpg',
                bytes: _profileImageBytes!,
                compressImages: true,
              ),
            if (_frontIdBytes != null)
              (
                folder: 'id_cards/front',
                fileName: _frontIdName,
                fallbackFileName: 'front.jpg',
                bytes: _frontIdBytes!,
                compressImages: true,
              ),
            if (_backIdBytes != null)
              (
                folder: 'id_cards/back',
                fileName: _backIdName,
                fallbackFileName: 'back.jpg',
                bytes: _backIdBytes!,
                compressImages: true,
              ),
            if (_cvBytes != null)
              (
                folder: 'cvs',
                fileName: _cvName,
                fallbackFileName: 'cv.pdf',
                bytes: _cvBytes!,
                compressImages: false,
              ),
          ],
        );

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

      final newAnnual = int.tryParse(_annualLeavesController.text.trim()) ?? 0;
      final newSick = int.tryParse(_sickLeavesController.text.trim()) ?? 0;
      final newCasual = int.tryParse(_casualLeavesController.text.trim()) ?? 0;
      final newMedical =
          int.tryParse(_medicalLeavesController.text.trim()) ?? 0;

      int availAnnual = newAnnual;
      int availSick = newSick;
      int availCasual = newCasual;
      int availMedical = newMedical;

      if (widget.workerToEdit != null) {
        final worker = widget.workerToEdit!;
        final timeOffRecords = isGuest
            ? List<Map<String, dynamic>>.from(DummyData.timeoff)
            : await _firestore.getTimeoffOnce(
                workerId: worker['id']?.toString(),
              );
        final assignedByType = TimeOffService.paidDaysUsedForWorkerByType(
          worker,
          timeOffRecords,
        );
        final assignedAnnual = assignedByType['Annual Leave'] ?? 0;
        final assignedSick = assignedByType['Sick Leave'] ?? 0;
        final assignedCasual = assignedByType['Casual Leave'] ?? 0;
        final assignedMedical = assignedByType['Medical Leave'] ?? 0;

        final leaveValidations = [
          (type: 'Annual Leave', newValue: newAnnual, assigned: assignedAnnual),
          (type: 'Sick Leave', newValue: newSick, assigned: assignedSick),
          (type: 'Casual Leave', newValue: newCasual, assigned: assignedCasual),
          (
            type: 'Medical Leave',
            newValue: newMedical,
            assigned: assignedMedical,
          ),
        ];

        for (final item in leaveValidations) {
          if (item.assigned > 0 && item.newValue < item.assigned) {
            if (mounted) {
              setState(() {
                _isSaving = false;
              });
              FlashySnackBar.show(
                context,
                message:
                    '${item.assigned} ${item.type} days are already assigned. '
                    'The allowance cannot be set below ${item.assigned}.',
                isError: true,
              );
            }
            return;
          }
        }

        availAnnual = (newAnnual - assignedAnnual).clamp(0, newAnnual);
        availSick = (newSick - assignedSick).clamp(0, newSick);
        availCasual = (newCasual - assignedCasual).clamp(0, newCasual);
        availMedical = (newMedical - assignedMedical).clamp(0, newMedical);
      }

      final data = <String, dynamic>{
        'name': name,
        'fatherName': Validators.titleCase(_fatherNameController.text),
        'email': WorkerIdentity.normalizeEmail(email),
        'phone': phone,
        'nationalId': _nationalIdController.text.trim(),
        'religion': religion,
        'dob': isGuest
            ? _dobController.text.trim()
            : Timestamp.fromDate(DateTime(dob.year, dob.month, dob.day)),
        'gender': _genderController.text.trim(),
        'address': _addressController.text.trim(),
        'relationshipStatus': _relationshipStatus,
        'workType': _type1Controller.text.isNotEmpty
            ? _type1Controller.text
            : 'Full-Time',
        'position': position.isNotEmpty ? position : 'Employee',
        'attendanceType': _type2Controller.text.isNotEmpty
            ? _type2Controller.text
            : 'On-Site',
        'experienceLevel': _experienceLevelController.text.trim(),
        'education': _educationController.text.trim(),
        'salaryAmount': validatedSalaryAmount,
        'annualLeaves': newAnnual,
        'availableAnnualLeaves': availAnnual,
        'sickLeaves': newSick,
        'availableSickLeaves': availSick,
        'casualLeaves': newCasual,
        'availableCasualLeaves': availCasual,
        'medicalLeaves': newMedical,
        'availableMedicalLeaves': availMedical,
        'leaveBalances': {
          'annualLeave': availAnnual,
          'sickLeave': availSick,
          'casualLeave': availCasual,
          'medicalLeave': availMedical,
        },
        'joiningDate': isGuest
            ? (_joiningDate ?? '')
            : Timestamp.fromDate(
                DateTime(joiningDate.year, joiningDate.month, joiningDate.day),
              ),
        'profileImage': profileImageUrl,
        'idFront': frontIdUrl,
        'idBack': backIdUrl,
        'cv': cvUrl,
        if (cvUrl != null && cvUrl.trim().isNotEmpty)
          'cvFileName': _cvName ?? cleanUploadedDocumentFileName(cvUrl),
        'payroll_initialized': true,
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
          try {
            await _firestore.addWorker(data);
          } on DuplicateWorkerException catch (dup) {
            if (mounted) {
              setState(() => _isSaving = false);
              final messageKey = switch (dup.field) {
                DuplicateWorkerField.name => 'duplicate_name',
                DuplicateWorkerField.email => 'duplicate_email',
                DuplicateWorkerField.nationalId => 'duplicate_national_id',
              };
              FlashySnackBar.show(
                context,
                message: messageKey.tr(),
                isError: true,
              );
              return;
            }
          }
        }
      }

      if (widget.workerToEdit != null) {
        final currentUrls = <String>{
          ?profileImageUrl,
          ?frontIdUrl,
          ?backIdUrl,
          ?cvUrl,
        };
        final oldUrls = <String>{
          ?oldProfileImageUrl,
          ?oldFrontIdUrl,
          ?oldBackIdUrl,
          ?oldCvUrl,
        };
        final deleteFutures = <Future<void>>[];
        for (final oldUrl in oldUrls) {
          if (oldUrl.isNotEmpty && !currentUrls.contains(oldUrl)) {
            deleteFutures.add(
              UploadService.deleteByUrl(oldUrl).catchError((
                cleanupError,
                cleanupStack,
              ) {
                ErrorReporter.report(
                  cleanupError,
                  cleanupStack,
                  context: 'workerEditCleanupOldFile',
                );
              }),
            );
          }
        }
        if (deleteFutures.isNotEmpty) {
          unawaited(Future.wait(deleteFutures));
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

    if (_fatherNameController.text.trim().isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'field_is_required'.tr(
          namedArgs: {'field': 'worker_father_husband_name'.tr()},
        ),
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

    if (!Validators.isValidPhone(phone)) {
      FlashySnackBar.show(
        context,
        message: 'validation_invalid_phone'.tr(),
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

    if (Validators.isPlaceholderEmailDomain(email)) {
      FlashySnackBar.show(
        context,
        message: 'validation_invalid_email_domain'.tr(),
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

    if (!Validators.isValidNationalId(nationalId)) {
      FlashySnackBar.show(
        context,
        message: 'validation_invalid_national_id'.tr(),
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
        final duplicateField = await _firestore.findDuplicateWorkerField(
          email: email,
          nationalId: nationalId,
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
    _salaryAmountController.dispose();
    _leavePolicyController.dispose();
    _annualLeavesController.dispose();
    _sickLeavesController.dispose();
    _casualLeavesController.dispose();
    _medicalLeavesController.dispose();
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
                            widget.workerToEdit != null
                                ? 'edit_worker'.tr()
                                : 'add_new_worker'.tr(),
                            style: const TextStyle(
                              color: Color(0xFF000000),
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            widget.workerToEdit != null
                                ? 'update_worker_details'.tr()
                                : 'fill_worker_details'.tr(),
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
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

                      if (isEditMode && !hasChanges) {
                        return const SizedBox.shrink();
                      }

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
                                  isEditMode
                                      ? 'save_changes'.tr()
                                      : 'save'.tr(),
                                  style: TextStyle(
                                    color: isSaveReady
                                        ? const Color(0xFFFFFFFF)
                                        : const Color(0xFF555555),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
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
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF000000,
                            ).withValues(alpha: 0.02),
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
                            color: const Color(
                              0xFFE0E0E0,
                            ).withValues(alpha: 0.5),
                          ),
                          Expanded(child: _buildTopTab('experience'.tr(), 1)),
                          VerticalDivider(
                            width: 1,
                            color: const Color(
                              0xFFE0E0E0,
                            ).withValues(alpha: 0.5),
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
                        onDobChanged: (date) {
                          setState(() => _selectedDob = date);
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
                        salaryAmountController: _salaryAmountController,
                        leavePolicyController: _leavePolicyController,
                        annualLeavesController: _annualLeavesController,
                        sickLeavesController: _sickLeavesController,
                        casualLeavesController: _casualLeavesController,
                        medicalLeavesController: _medicalLeavesController,
                        selectedJoiningDate: _joiningDate,
                        onJoiningDateChanged: (date) {
                          setState(() {
                            _selectedJoiningDate = DateTime(
                              date.year,
                              date.month,
                              date.day,
                            );
                            _joiningDate = AppDateUtils.formatDate(date);
                          });
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
                          showDeleteCvConfirmationDialog(
                            context,
                            onConfirm: () {
                              setState(() {
                                _cvBytes = null;
                                _cvName = null;
                                _existingCvUrl = null;
                                _isCvUploaded = false;
                              });
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
    final bool isActive = _activeTabIndex == index;
    final borderRadius = switch ((isActive, index)) {
      (true, 0) => const BorderRadius.only(
        topLeft: Radius.circular(6),
        bottomLeft: Radius.circular(6),
      ),
      (true, 2) => const BorderRadius.only(
        topRight: Radius.circular(6),
        bottomRight: Radius.circular(6),
      ),
      _ => null,
    };
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
        ),
      ),
    );
  }
}
