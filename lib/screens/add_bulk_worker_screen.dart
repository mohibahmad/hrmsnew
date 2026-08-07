import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:ui' as ui;
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:flutter/cupertino.dart' hide GestureDetector;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/upload_service.dart';
import '../services/error_reporter.dart';
import '../services/bulk_worker_csv_service.dart';
import '../services/bulk_worker_media_service.dart';
import '../utils/snackbar_utils.dart';
import '../utils/rate_us_helper.dart';
import '../utils/date_utils.dart';
import '../utils/worker_identity.dart';
import '../utils/validators.dart';
import '../utils/delete_dialog.dart';
import '../utils/bulk_worker_validator.dart';
import '../models/worker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../widgets/bulk_worker_edit_dialog.dart';
import '../widgets/notification_bell.dart';

/// Formats a numeric salary value with thousands separators
/// (e.g. 50000 -> "50,000"). Returns '' for empty/invalid input.
String _formatSalaryWithCommas(dynamic value) {
  final text = (value ?? '').toString().trim();
  if (text.isEmpty) return '';
  final cleaned = text.replaceAll(',', '');
  final amount = double.tryParse(cleaned);
  if (amount == null || !amount.isFinite) return '';
  return NumberFormat('#,##0.##', 'en_US').format(amount);
}

class UploadProgress {
  final String phase;
  final int completed;
  final int total;
  final String currentFile;

  const UploadProgress({
    required this.phase,
    required this.completed,
    required this.total,
    required this.currentFile,
  });
}

class AddBulkWorkerScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onProfileTap;

  const AddBulkWorkerScreen({
    super.key,
    this.onBack,
    this.onNotificationTap,
    this.onProfileTap,
  });

  @override
  AddBulkWorkerScreenState createState() => AddBulkWorkerScreenState();
}

class AddBulkWorkerScreenState extends State<AddBulkWorkerScreen> {
  static const double _tableContentWidth = 3628;
  static const double _rowHeight = 65.0;

  late AuthService _authService;
  late FirestoreService _firestore;

  bool _isSaving = false;
  bool _hasParsedFile = false;
  bool _hasUnsavedChanges = false;

  List<Map<String, dynamic>> _validWorkers = [];

  int _invalidDobCount = 0;
  int _invalidGenderCount = 0;
  int _missingRequiredCount = 0;
  int _duplicateCount = 0;

  String? _lastFileHash;

  Set<String> _cachedEmails = {};
  Set<String> _cachedNationalIds = {};
  List<String> _missingColumns = [];
  List<String> _uploadedMediaUrls = [];

  final Map<String, List<String>> _uploadedMediaByRowId = {};

  ScrollController? _hScrollController;
  StreamSubscription? _workersSubscription;
  StreamSubscription? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestore = Provider.of<FirestoreService>(context, listen: false);

    _authSubscription = _authService.authStateChanges.listen((_) {
      _clearIdentityCache();
    });
  }

  @override
  void dispose() {
    _hScrollController?.dispose();
    _workersSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  void _clearIdentityCache() {
    _cachedEmails = {};
    _cachedNationalIds = {};
  }

  bool get hasUnsavedChanges => _hasUnsavedChanges;

  Future<bool> confirmDiscard() => _onWillPop();

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
                                height: 56,
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
                                height: 56,
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

  Map<String, dynamic> _preNormalizeForWorker(Map<String, dynamic> w) {
    final normalized = Map<String, dynamic>.from(w);
    for (final key in ['dob', 'joiningDate']) {
      final raw = normalized[key]?.toString().trim() ?? '';
      if (raw.isNotEmpty) {
        final parsed = AppDateUtils.parseDateString(raw);
        normalized[key] = parsed != null
            ? parsed.toUtc().toIso8601String()
            : '';
      }
    }
    return normalized;
  }

  List<Map<String, dynamic>> get _workersReadyToSave =>
      _validWorkers.where((w) => !hasWorkerErrors(w)).map((w) {
        final clean = Map<String, dynamic>.from(w);
        clean.remove('_fieldErrors');
        clean.remove('_rowNumber');
        final rowId = (w['clientRowId'] ?? w['client_row_id'] ?? '')
            .toString()
            .trim();
        final result = Worker.fromMap(_preNormalizeForWorker(clean)).toMap();
        if (rowId.isNotEmpty) {
          result['clientRowId'] = rowId;
        }
        return result;
      }).toList();

  String _computeFileHash(Uint8List bytes) => computeFileHash(bytes);

  Future<void> _downloadTemplate() async {
    try {
      await downloadTemplate(context);
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'could_not_download_template'.tr(),
          isError: true,
        );
      }
    }
  }

  Future<void> _pickCsvAndParse() async {
    try {
      final bytes = await pickCsvFile();
      if (bytes == null) return;

      final fileHash = _computeFileHash(bytes);
      if (_lastFileHash != null && _lastFileHash == fileHash) {
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'same_csv_file_already_uploaded'.tr(),
            isError: true,
          );
        }
        return;
      }

      final rows = await compute(parseCsvInBackground, bytes);

      if (!mounted) return;
      final didParse = await _processCsvData(rows);
      if (didParse) {
        _lastFileHash = fileHash;
      }
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'error_picking_csv'.tr(),
          isError: true,
        );
      }
    }
  }

  Future<({Set<String> emails, Set<String> nationalIds})>
  _loadExistingIdentitySets() async {
    if (_cachedEmails.isNotEmpty || _cachedNationalIds.isNotEmpty) {
      return (emails: _cachedEmails, nationalIds: _cachedNationalIds);
    }

    final bool isGuest = _authService.currentUser?.isAnonymous ?? false;
    final emails = <String>{};
    final nationalIds = <String>{};

    if (isGuest) {
      for (final w in DummyData.workers) {
        final e = WorkerIdentity.normalizeEmail(w['email']);
        if (e.isNotEmpty) emails.add(e);
        final n = WorkerIdentity.normalizeNationalId(w['nationalId']);
        if (n.isNotEmpty) nationalIds.add(n);
      }
    } else {
      final snapshot = await _firestore.getWorkersOnce();
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final e = WorkerIdentity.normalizeEmail(data['email']);
        if (e.isNotEmpty) emails.add(e);
        final n = WorkerIdentity.normalizeNationalId(data['nationalId']);
        if (n.isNotEmpty) nationalIds.add(n);
      }
    }

    _cachedEmails = emails;
    _cachedNationalIds = nationalIds;

    return (emails: emails, nationalIds: nationalIds);
  }

  Future<bool> _processCsvData(List<List<String>> rows) async {
    if (rows.isEmpty) return false;

    if (mounted) {
      setState(() {
        _invalidDobCount = 0;
        _invalidGenderCount = 0;
        _missingRequiredCount = 0;
        _duplicateCount = 0;
      });
    }

    final headers = rows.first
        .map((e) => e.toString().trim().toLowerCase())
        .toList();

    final foundFields = <String>{};
    for (final header in headers) {
      final mapped = kHeaderMap[header] ?? header;
      if (kRequiredFields.contains(mapped)) {
        foundFields.add(mapped);
      }
    }

    final missingColumns = kRequiredFields
        .where((field) => !foundFields.contains(field))
        .toList();

    final ({Set<String> emails, Set<String> nationalIds}) existing;
    try {
      existing = await _loadExistingIdentitySets();
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'could_not_validate_csv_duplicates'.tr(),
          isError: true,
        );
      }
      return false;
    }
    final existingEmails = existing.emails;
    final existingNationalIds = existing.nationalIds;

    if (!mounted) return false;

    final parsedWorkers = <Map<String, dynamic>>[];
    final csvEmails = <String>{};
    final csvNationalIds = <String>{};

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.every((e) => e.toString().trim().isEmpty)) {
        continue;
      }

      final workerData = <String, dynamic>{
        'name': '',
        'phone': '',
        'fatherName': '',
        'email': '',
        'nationalId': '',
        'religion': '',
        'dob': '',
        'gender': '',
        'address': '',
        'relationshipStatus': '',
        'type1': '',
        'position': '',
        'type2': '',
        'experienceLevel': '',
        'education': '',
        'salaryAmount': '',
        'leavePolicy': '',
        'annualLeaves': '',
        'sickLeaves': '',
        'casualLeaves': '',
        'medicalLeaves': '',
        'joiningDate': '',
        'profileImage': '',
        'frontId': '',
        'backId': '',
        'cv': '',
      };

      for (int j = 0; j < headers.length && j < row.length; j++) {
        final value = row[j].toString().trim();
        if (value.isEmpty) continue;

        final mappedKey = kHeaderMap[headers[j]] ?? headers[j];
        String matchedKey = mappedKey;
        for (final key in workerData.keys) {
          if (key.toLowerCase() == mappedKey.toLowerCase()) {
            matchedKey = key;
            break;
          }
        }
        if (workerData[matchedKey]?.toString().trim().isNotEmpty ?? false) {
          continue;
        }
        workerData[matchedKey] = value;
      }

      final fieldErrors = validateWorkerData(
        workerData,
        existingEmails: existingEmails,
        existingNationalIds: existingNationalIds,
        csvEmails: csvEmails,
        csvNationalIds: csvNationalIds,
      );

      final email = WorkerIdentity.normalizeEmail(workerData['email']);
      final nationalId = WorkerIdentity.normalizeNationalId(
        workerData['nationalId'],
      );
      if (email.isNotEmpty) csvEmails.add(email);
      if (nationalId.isNotEmpty) csvNationalIds.add(nationalId);

      workerData['_rowNumber'] = i + 1;
      workerData['_fieldErrors'] = fieldErrors;
      workerData['clientRowId'] = 'row_${i + 1}';
      parsedWorkers.add(workerData);
    }

    if (parsedWorkers.isEmpty) {
      setState(() {
        _validWorkers = [];
        _missingColumns = [];
        _hasParsedFile = false;
        _hasUnsavedChanges = false;
      });
      FlashySnackBar.show(
        context,
        message: 'no_valid_workers_found_in_csv'.tr(),
        isError: true,
      );
      return false;
    }

    final counts = validationCounts(parsedWorkers);

    setState(() {
      _validWorkers = parsedWorkers;
      _missingColumns = missingColumns;
      _hasParsedFile = true;
      _hasUnsavedChanges = true;
      _missingRequiredCount = counts.missing;
      _invalidDobCount = counts.invalidDob;
      _invalidGenderCount = counts.invalidGender;
      _duplicateCount = counts.duplicate;
    });

    final requiredMessage = 'validation_required'.tr();
    final duplicateEmailMessage = 'validation_duplicate_email'.tr();
    final duplicateNationalIdMessage = 'validation_duplicate_national_id'.tr();

    final allMissingFieldNames = <String>{};
    for (final worker in parsedWorkers) {
      for (final entry in fieldErrors(worker).entries) {
        if (entry.value == requiredMessage) {
          allMissingFieldNames.add(entry.key);
        }
      }
    }

    final duplicateWorkers = parsedWorkers.where((worker) {
      final errors = fieldErrors(worker);
      return errors['email'] == duplicateEmailMessage ||
          errors['nationalId'] == duplicateNationalIdMessage;
    }).length;

    final hasAnyIssue =
        missingColumns.isNotEmpty || parsedWorkers.any(hasWorkerErrors);

    if (hasAnyIssue) {
      final snackParts = <String>[
        'csv_workers_found'.tr(namedArgs: {'count': '${parsedWorkers.length}'}),
      ];
      if (missingColumns.isNotEmpty) {
        final columns = missingColumns
            .map((field) => kFieldLabels[field] ?? field)
            .join(', ');
        snackParts.add(
          'csv_missing_columns'.tr(namedArgs: {'columns': columns}),
        );
      }
      if (allMissingFieldNames.isNotEmpty) {
        final fields = allMissingFieldNames
            .map((field) => kFieldLabels[field] ?? field)
            .join(', ');
        snackParts.add('csv_empty_fields'.tr(namedArgs: {'fields': fields}));
      }
      if (duplicateWorkers > 0) {
        snackParts.add(
          'csv_duplicates_found'.tr(namedArgs: {'count': '$duplicateWorkers'}),
        );
      }
      FlashySnackBar.show(
        context,
        title: 'csv_uploaded_with_issues_title'.tr(),
        message: snackParts.join('\n'),
        isError: true,
        maxLines: null,
        displayDuration: const Duration(seconds: 15),
      );
    } else {
      FlashySnackBar.show(
        context,
        title: 'csv_uploaded_title'.tr(),
        message: 'csv_all_workers_ready'.tr(
          namedArgs: {'count': parsedWorkers.length.toString()},
        ),
      );
    }

    return true;
  }

  Future<bool> _revalidateAllWorkers() async {
    final ({Set<String> emails, Set<String> nationalIds}) existing;
    try {
      existing = await _loadExistingIdentitySets();
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'could_not_validate_csv_duplicates'.tr(),
          isError: true,
        );
      }
      return false;
    }
    final existingEmails = existing.emails;
    final existingNationalIds = existing.nationalIds;

    final csvEmails = <String>{};
    final csvNationalIds = <String>{};

    for (final workerData in _validWorkers) {
      final fieldErrs = validateWorkerData(
        workerData,
        existingEmails: existingEmails,
        existingNationalIds: existingNationalIds,
        csvEmails: csvEmails,
        csvNationalIds: csvNationalIds,
      );

      final email = WorkerIdentity.normalizeEmail(workerData['email']);
      final nationalId = WorkerIdentity.normalizeNationalId(
        workerData['nationalId'],
      );
      if (email.isNotEmpty) csvEmails.add(email);
      if (nationalId.isNotEmpty) csvNationalIds.add(nationalId);

      workerData['_fieldErrors'] = fieldErrs;
    }

    final counts = validationCounts(_validWorkers);

    if (mounted) {
      setState(() {
        _duplicateCount = counts.duplicate;
        _missingRequiredCount = counts.missing;
        _invalidDobCount = counts.invalidDob;
        _invalidGenderCount = counts.invalidGender;
      });
    }

    return true;
  }

  Future<void> _revalidateSingleWorker(int workerIndex) async {
    if (workerIndex < 0 || workerIndex >= _validWorkers.length) return;

    final ({Set<String> emails, Set<String> nationalIds}) existing;
    try {
      existing = await _loadExistingIdentitySets();
    } catch (_) {
      return;
    }
    final existingEmails = existing.emails;
    final existingNationalIds = existing.nationalIds;

    final csvEmails = <String>{};
    final csvNationalIds = <String>{};
    for (int i = 0; i < _validWorkers.length; i++) {
      if (i == workerIndex) continue;
      final email = WorkerIdentity.normalizeEmail(
        _validWorkers[i]['email']?.toString() ?? '',
      );
      final nationalId = WorkerIdentity.normalizeNationalId(
        _validWorkers[i]['nationalId']?.toString() ?? '',
      );
      if (email.isNotEmpty) csvEmails.add(email);
      if (nationalId.isNotEmpty) csvNationalIds.add(nationalId);
    }

    final workerData = _validWorkers[workerIndex];
    final fieldErrs = validateWorkerData(
      workerData,
      existingEmails: existingEmails,
      existingNationalIds: existingNationalIds,
      csvEmails: csvEmails,
      csvNationalIds: csvNationalIds,
    );
    workerData['_fieldErrors'] = fieldErrs;

    final counts = validationCounts(_validWorkers);
    if (mounted) {
      setState(() {
        _duplicateCount = counts.duplicate;
        _missingRequiredCount = counts.missing;
        _invalidDobCount = counts.invalidDob;
        _invalidGenderCount = counts.invalidGender;
      });
    }
  }

  Future<void> _saveBulkWorkers() async {
    if (_isSaving) return;

    final revalidated = await _revalidateAllWorkers();
    if (!revalidated || !mounted) return;

    if (_validWorkers.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'no_valid_workers_found_in_csv'.tr(),
        isError: true,
      );
      return;
    }

    final workersWithErrors = _validWorkers.where(hasWorkerErrors).toList();
    var workersReadyToSave = _workersReadyToSave;

    if (workersReadyToSave.isEmpty) {
      final parts = <String>[];
      if (_missingRequiredCount > 0) {
        parts.add(
          'skipped_missing_required_message'.tr(
            namedArgs: {'count': _missingRequiredCount.toString()},
          ),
        );
      }
      if (_invalidDobCount > 0) {
        parts.add(
          'skipped_invalid_dob_message'.tr(
            namedArgs: {'count': _invalidDobCount.toString()},
          ),
        );
      }
      if (_invalidGenderCount > 0) {
        parts.add(
          'skipped_invalid_gender_message'.tr(
            namedArgs: {'count': _invalidGenderCount.toString()},
          ),
        );
      }
      if (_duplicateCount > 0) {
        parts.add(
          'skipped_duplicates_message'.tr(
            namedArgs: {'count': _duplicateCount.toString()},
          ),
        );
      }

      final invalidFields = workersWithErrors
          .expand((worker) => fieldErrors(worker).keys)
          .toSet()
          .map((field) => kFieldLabels[field] ?? field)
          .join(', ');
      if (invalidFields.isNotEmpty) {
        parts.add(invalidFields);
      }

      FlashySnackBar.show(
        context,
        message: 'csv_validation_errors_found'.tr(
          namedArgs: {'errors': parts.join('\n')},
        ),
        isError: true,
        displayDuration: const Duration(seconds: 10),
        maxLines: null,
      );
      return;
    }

    final requiredMessage = 'validation_required'.tr();
    final duplicateEmailMessage = 'validation_duplicate_email'.tr();
    final duplicateNationalIdMessage = 'validation_duplicate_national_id'.tr();

    int localDuplicateCount = 0;
    int localMissingCount = 0;
    int localInvalidDobCount = 0;
    int localInvalidGenderCount = 0;

    for (final worker in workersWithErrors) {
      final errors = fieldErrors(worker);
      if (errors['email'] == duplicateEmailMessage ||
          errors['nationalId'] == duplicateNationalIdMessage) {
        localDuplicateCount++;
      }
      if (errors.values.contains(requiredMessage)) {
        localMissingCount++;
      }
      if (errors.containsKey('dob') && errors['dob'] != requiredMessage) {
        localInvalidDobCount++;
      }
      if (errors.containsKey('gender') && errors['gender'] != requiredMessage) {
        localInvalidGenderCount++;
      }
    }

    setState(() => _isSaving = true);

    final bool isGuest = _authService.currentUser?.isAnonymous ?? false;
    _uploadedMediaUrls = [];
    _showBulkProgressDialog();

    try {
      int importedCount = workersReadyToSave.length;
      int guestSkippedDuplicates = 0;
      BulkWorkerResult? bulkResult;

      if (isGuest) {
        final existingWorkers = DummyData.workers.toList();
        final acceptedWorkers = <Map<String, dynamic>>[];
        for (final worker in workersReadyToSave) {
          final duplicateField = WorkerIdentity.duplicateField(worker, [
            ...existingWorkers,
            ...acceptedWorkers,
          ]);
          if (duplicateField != null) {
            guestSkippedDuplicates++;
            continue;
          }
          acceptedWorkers.add(worker);
        }
        importedCount = acceptedWorkers.length;
        for (int i = 0; i < acceptedWorkers.length; i++) {
          final newId = 'dummy_${DateTime.now().microsecondsSinceEpoch}_$i';
          DummyData.workers.insert(0, {...acceptedWorkers[i], 'id': newId});
        }
        await DummyData.saveToPrefs();
      } else {
        workersReadyToSave = await uploadEmbeddedWorkerMedia(
          workersReadyToSave,
          uploadedMediaUrls: _uploadedMediaUrls,
          uploadedMediaByRowId: _uploadedMediaByRowId,
        );
        bulkResult = await _firestore.addBulkWorkers(workersReadyToSave);
        importedCount = bulkResult.imported;

        if (bulkResult.skippedClientRowIds.isNotEmpty &&
            _uploadedMediaByRowId.isNotEmpty) {
          final orphanUrls = <String>[];
          for (final rowId in bulkResult.skippedClientRowIds) {
            final urls = _uploadedMediaByRowId[rowId];
            if (urls != null && urls.isNotEmpty) {
              orphanUrls.addAll(urls);
            }
          }
          if (orphanUrls.isNotEmpty) {
            try {
              await Future.wait(orphanUrls.map(UploadService.deleteByUrl));
            } catch (cleanupError, cleanupStack) {
              ErrorReporter.report(
                cleanupError,
                cleanupStack,
                context: 'BulkWorkerSkippedRowMediaCleanup',
              );
            }
          }
        }
      }

      _clearIdentityCache();

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final serverDuplicateCount =
          bulkResult?.skipReasons.where((reason) {
            return reason.trim().toLowerCase().startsWith('duplicate ');
          }).length ??
          0;
      final finalSkippedDuplicates =
          localDuplicateCount + serverDuplicateCount + guestSkippedDuplicates;

      final summaryParts = <String>[
        'workers_added_successfully'.tr(
          namedArgs: {'count': importedCount.toString()},
        ),
      ];

      if (finalSkippedDuplicates > 0) {
        summaryParts.add(
          'skipped_duplicates_message'.tr(
            namedArgs: {'count': finalSkippedDuplicates.toString()},
          ),
        );
      }
      if (bulkResult != null && bulkResult.skipReasons.isNotEmpty) {
        for (final reason in bulkResult.skipReasons) {
          summaryParts.add('  • $reason');
        }
      }
      if (localMissingCount > 0) {
        summaryParts.add(
          'skipped_missing_required_message'.tr(
            namedArgs: {'count': localMissingCount.toString()},
          ),
        );
      }
      if (localInvalidDobCount > 0) {
        summaryParts.add(
          'skipped_invalid_dob_message'.tr(
            namedArgs: {'count': localInvalidDobCount.toString()},
          ),
        );
      }
      if (localInvalidGenderCount > 0) {
        summaryParts.add(
          'skipped_invalid_gender_message'.tr(
            namedArgs: {'count': localInvalidGenderCount.toString()},
          ),
        );
      }

      final hasSkipped =
          workersWithErrors.isNotEmpty ||
          (bulkResult?.skipped ?? 0) > 0 ||
          guestSkippedDuplicates > 0;

      FlashySnackBar.show(
        context,
        title: hasSkipped
            ? 'csv_uploaded_with_issues_title'.tr()
            : 'csv_uploaded_title'.tr(),
        message: summaryParts.join('\n'),
        isError: hasSkipped,
        maxLines: null,
        displayDuration: hasSkipped
            ? const Duration(seconds: 12)
            : const Duration(seconds: 5),
      );

      if (importedCount > 0) {
        await tryShowFirstMilestoneRateUs('bulk_worker');
      }

      final keepInvalidWorkers = !isGuest && workersWithErrors.isNotEmpty;

      setState(() {
        if (keepInvalidWorkers) {
          _validWorkers = workersWithErrors;
          _hasParsedFile = true;
          _hasUnsavedChanges = true;
        } else {
          _validWorkers = [];
          _missingColumns = [];
          _hasParsedFile = false;
          _hasUnsavedChanges = false;
        }
      });

      if (!isGuest) {
        _workersSubscription?.cancel();
        _workersSubscription = _firestore.workersStream.listen((_) {
          if (mounted) setState(() {});
        });
      } else {
        DummyData.loadFromPrefs();
      }

      if (!keepInvalidWorkers) {
        widget.onBack?.call();
      }
    } catch (error, stackTrace) {
      debugPrint('Add bulk worker save failed: ${readableSaveError(error)}');
      ErrorReporter.report(
        error,
        stackTrace,
        context: 'AddBulkWorkerScreen.save',
      );

      if (!isGuest && _uploadedMediaUrls.isNotEmpty) {
        try {
          await Future.wait(_uploadedMediaUrls.map(UploadService.deleteByUrl));
        } catch (_) {}
      }
      _uploadedMediaUrls = [];
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        FlashySnackBar.show(
          context,
          message:
              '${'could_not_save_worker'.tr()}\n'
              '${readableSaveError(error)}',
          isError: true,
          maxLines: null,
          displayDuration: const Duration(seconds: 10),
        );
      }
    } finally {
      _uploadedMediaUrls = [];
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showBulkProgressDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black38,
      builder: (_) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  'saving_bulk_workers'.tr(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
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
  }

  Future<void> _editCell(int workerIndex, String fieldKey) async {
    if (workerIndex >= _validWorkers.length) return;

    final worker = _validWorkers[workerIndex];
    final currentValue = (worker[fieldKey] ?? '').toString();
    final label = kFieldLabels[fieldKey] ?? fieldKey;
    final isLeavesField =
        fieldKey == 'annualLeaves' ||
        fieldKey == 'sickLeaves' ||
        fieldKey == 'casualLeaves' ||
        fieldKey == 'medicalLeaves';

    final existingEmails = <String>{};
    final existingNationalIds = <String>{};
    final bool needsExistingIdentity =
        fieldKey == 'email' || fieldKey == 'nationalId';
    if (needsExistingIdentity) {
      try {
        final existing = await _loadExistingIdentitySets();
        existingEmails.addAll(existing.emails);
        existingNationalIds.addAll(existing.nationalIds);
      } catch (_) {}
    }
    if (!mounted) return;

    final result = await showDialog<String>(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (ctx) {
        final controller = TextEditingController(text: currentValue);
        String? dialogError;

        final isMediaField =
            fieldKey == 'profileImage' ||
            fieldKey == 'frontId' ||
            fieldKey == 'backId' ||
            fieldKey == 'cv';
        String? mediaDataUrl;
        String? mediaFileName;
        bool hasExistingUpload = false;
        if (isMediaField && currentValue.isNotEmpty) {
          // Treat any existing value (http(s) link or data: URL) as an
          // existing upload so the field is locked and shows "uploaded".
          hasExistingUpload = true;
          final storedName = worker['${fieldKey}_name'];
          if (currentValue.startsWith('data:')) {
            if (storedName != null && storedName.toString().isNotEmpty) {
              controller.text = storedName.toString();
            } else {
              final mime = currentValue.split(';').first.split(':').last;
              controller.text = mime == 'application/pdf'
                  ? 'document.pdf'
                  : 'image.jpg';
            }
          }
          controller.selection = TextSelection.collapsed(
            offset: controller.text.length,
          );
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 40,
          ),
          child: Center(
            child: Container(
              width: 440,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0247C4).withValues(alpha: 0.18),
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
              child: StatefulBuilder(
                builder: (_, setDialogState) {
                  Future<void> _pickMediaFile() async {
                    try {
                      final result = await FilePicker.pickFiles(
                        type: FileType.custom,
                        allowMultiple: false,
                        withData: true,
                        allowedExtensions: fieldKey == 'cv'
                            ? ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png']
                            : ['jpg', 'jpeg', 'png'],
                      );
                      if (result != null && result.files.isNotEmpty) {
                        final file = result.files.first;
                        Uint8List? bytes = file.bytes;
                        if (bytes != null && bytes.length > 10 * 1024 * 1024) {
                          setDialogState(() {
                            dialogError = 'file_too_large'.tr(
                              namedArgs: {'size': '10MB'},
                            );
                          });
                          return;
                        }
                        if (bytes == null && file.path != null) {
                          final selectedFile = io.File(file.path!);
                          if (await selectedFile.length() > 10 * 1024 * 1024) {
                            setDialogState(() {
                              dialogError = 'file_too_large'.tr(
                                namedArgs: {'size': '10MB'},
                              );
                            });
                            return;
                          }
                          bytes = await selectedFile.readAsBytes();
                        }
                        if (bytes != null && bytes.isNotEmpty) {
                          final ext = file.name.split('.').last.toLowerCase();
                          const mimeMap = {
                            'pdf': 'application/pdf',
                            'doc': 'application/msword',
                            'docx':
                                'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                            'png': 'image/png',
                            'jpg': 'image/jpeg',
                            'jpeg': 'image/jpeg',
                          };
                          final mime = mimeMap[ext] ?? 'image/jpeg';
                          final dataUrl =
                              'data:$mime;base64,${base64Encode(bytes)}';
                          setDialogState(() {
                            mediaDataUrl = dataUrl;
                            mediaFileName = file.name;
                            hasExistingUpload = true;
                            controller.text = file.name;
                            controller.selection = TextSelection.collapsed(
                              offset: controller.text.length,
                            );
                          });
                        }
                      }
                    } catch (e) {
                      setDialogState(() {
                        dialogError = 'failed_to_pick_image'.tr();
                      });
                    }
                  }

                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF374151),
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (isDateField(fieldKey))
                                  buildDateField(
                                    context: ctx,
                                    fieldKey: fieldKey,
                                    currentValue: controller.text,
                                    label: label,
                                    setDialogState: setDialogState,
                                    onDateSelected: (dateStr) {
                                      controller.text = dateStr;
                                    },
                                  )
                                else
                                  Container(
                                    clipBehavior: Clip.hardEdge,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFFD1D5DB),
                                        width: 1.2,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    child: TextField(
                                      controller: controller,
                                      readOnly:
                                          isMediaField &&
                                          (mediaDataUrl != null ||
                                              hasExistingUpload),
                                      autofocus: !isMediaField,
                                      maxLines: isMediaField ? 1 : null,
                                      minLines: 1,
                                      expands: false,
                                      keyboardType: keyboardTypeForField(
                                        fieldKey,
                                      ),
                                      inputFormatters: inputFormattersForField(
                                        fieldKey,
                                      ),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontFamily: 'SF Pro Display',
                                        color:
                                            (isMediaField &&
                                                (mediaDataUrl != null ||
                                                    hasExistingUpload))
                                            ? const Color(0xFF9CA3AF)
                                            : const Color(0xFF111827),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      decoration: InputDecoration(
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 14,
                                            ),
                                        hintText: isLeavesField
                                            ? '0'
                                            : isMediaField
                                                ? mediaFieldHint(fieldKey)
                                                : 'edit_cell_enter_value'.tr(
                                                    namedArgs: {
                                                      'label': label,
                                                    },
                                                  ),
                                        hintStyle: const TextStyle(
                                          color: Color(0xFF9CA3AF),
                                          fontSize: 15,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                        suffixIcon:
                                            (fieldKey == 'profileImage' ||
                                                fieldKey == 'frontId' ||
                                                fieldKey == 'backId' ||
                                                fieldKey == 'cv')
                                            ? GestureDetector(
                                                onTap: () => _pickMediaFile(),
                                                child: Container(
                                                  margin:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 8,
                                                      ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        (mediaDataUrl != null ||
                                                            hasExistingUpload)
                                                        ? const Color(
                                                            0xFFDCFCE7,
                                                          )
                                                        : const Color(
                                                            0xFFEEF2FF,
                                                          ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        (mediaDataUrl != null ||
                                                                hasExistingUpload)
                                                            ? Icons
                                                                  .check_circle_rounded
                                                            : fieldKey == 'cv'
                                                            ? Icons
                                                                  .attach_file_rounded
                                                            : fieldKey ==
                                                                  'profileImage'
                                                            ? Icons
                                                                  .add_a_photo_rounded
                                                            : Icons
                                                                  .badge_rounded,
                                                        size: 18,
                                                        color:
                                                            (mediaDataUrl !=
                                                                    null ||
                                                                hasExistingUpload)
                                                            ? const Color(
                                                                0xFF16A34A,
                                                              )
                                                            : const Color(
                                                                0xFF0247C4,
                                                              ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        (mediaDataUrl != null ||
                                                                hasExistingUpload)
                                                            ? 'uploaded'.tr()
                                                            : fieldKey == 'cv'
                                                            ? 'upload_cv'.tr()
                                                            : 'upload_image'
                                                                  .tr(),
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color:
                                                              (mediaDataUrl !=
                                                                      null ||
                                                                  hasExistingUpload)
                                                              ? const Color(
                                                                  0xFF16A34A,
                                                                )
                                                              : const Color(
                                                                  0xFF0247C4,
                                                                ),
                                                          fontFamily:
                                                              'SF Pro Display',
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              )
                                            : null,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          if (fieldHint(fieldKey).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.lightbulb_outline,
                                    size: 13,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      fieldHint(fieldKey),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF9CA3AF),
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          if (dialogError != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline_rounded,
                                    size: 14,
                                    color: Color(0xFFDC2626),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      dialogError!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFFDC2626),
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          Container(
                            margin: const EdgeInsets.only(top: 16),
                            decoration: const BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: Color(0xFFE5E7EB),
                                  width: 1,
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF6B7280),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: Text(
                                    'cancel'.tr(),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0247C4),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shadowColor: Colors.transparent,
                                    minimumSize: const Size(0, 42),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 10,
                                    ),
                                  ),
                                  onPressed: () {
                                    final val = controller.text
                                        .replaceAll(RegExp(r'[\r\n]+'), ' ')
                                        .trim();
                                    if (!isMediaField && val.isEmpty) {
                                      setDialogState(() {
                                        dialogError =
                                            'edit_cell_cannot_be_empty'.tr();
                                      });
                                    } else if (isMediaField &&
                                        val.isEmpty &&
                                        (mediaDataUrl == null ||
                                            mediaDataUrl!.isEmpty)) {
                                      setDialogState(() {
                                        dialogError =
                                            'edit_cell_cannot_be_empty'.tr();
                                      });
                                    } else if (fieldKey == 'email' &&
                                        val.isNotEmpty) {
                                      final normalizedEmail =
                                          WorkerIdentity.normalizeEmail(val);
                                      if (!Validators.isValidEmail(
                                            normalizedEmail,
                                          ) ||
                                          Validators.isPlaceholderEmailDomain(
                                            normalizedEmail,
                                          )) {
                                        setDialogState(() {
                                          dialogError =
                                              'validation_invalid_email'.tr();
                                        });
                                      } else {
                                        final isDuplicate =
                                            existingEmails.contains(
                                              normalizedEmail,
                                            ) ||
                                            _validWorkers.asMap().entries.any((
                                              entry,
                                            ) {
                                              return entry.key != workerIndex &&
                                                  WorkerIdentity.normalizeEmail(
                                                        entry.value['email']
                                                                ?.toString() ??
                                                            '',
                                                      ) ==
                                                      normalizedEmail;
                                            });
                                        if (isDuplicate) {
                                          setDialogState(() {
                                            dialogError =
                                                'validation_duplicate_email'
                                                    .tr();
                                          });
                                        } else {
                                          Navigator.of(
                                            ctx,
                                          ).pop(normalizedEmail);
                                        }
                                      }
                                    } else if (fieldKey == 'nationalId' &&
                                        val.isNotEmpty) {
                                      if (!Validators.isValidNationalId(val)) {
                                        setDialogState(() {
                                          dialogError =
                                              'validation_invalid_national_id'
                                                  .tr();
                                        });
                                        return;
                                      }
                                      final normalizedId =
                                          WorkerIdentity.normalizeNationalId(
                                            val,
                                          );
                                      final isDuplicate =
                                          existingNationalIds.contains(
                                            normalizedId,
                                          ) ||
                                          _validWorkers.asMap().entries.any((
                                            entry,
                                          ) {
                                            return entry.key != workerIndex &&
                                                WorkerIdentity.normalizeNationalId(
                                                      entry.value['nationalId']
                                                              ?.toString() ??
                                                          '',
                                                    ) ==
                                                    normalizedId;
                                          });
                                      if (isDuplicate) {
                                        setDialogState(() {
                                          dialogError =
                                              'validation_duplicate_national_id'
                                                  .tr();
                                        });
                                      } else {
                                        Navigator.of(ctx).pop(val);
                                      }
                                    } else if (fieldKey == 'gender') {
                                      final normalized = val.toLowerCase();
                                      const valid = {
                                        'male',
                                        'female',
                                        'other',
                                        'others',
                                      };
                                      if (!valid.contains(normalized)) {
                                        setDialogState(() {
                                          dialogError =
                                              'validation_invalid_gender'.tr();
                                        });
                                      } else {
                                        Navigator.of(ctx).pop(
                                          normalized == 'others'
                                              ? 'Other'
                                              : normalized == 'male'
                                              ? 'Male'
                                              : normalized == 'female'
                                              ? 'Female'
                                              : val,
                                        );
                                      }
                                    } else if (fieldKey ==
                                        'relationshipStatus') {
                                      final normalized = val.toLowerCase();
                                      const valid = {'single', 'married'};
                                      if (!valid.contains(normalized)) {
                                        setDialogState(() {
                                          dialogError =
                                              'validation_invalid_relationship'
                                                  .tr();
                                        });
                                      } else {
                                        final display =
                                            normalized[0].toUpperCase() +
                                            normalized.substring(1);
                                        Navigator.of(ctx).pop(display);
                                      }
                                    } else if (fieldKey == 'experienceLevel') {
                                      final normalized = val.toLowerCase();
                                      const valid = {
                                        'fresher',
                                        'junior',
                                        'mid-level',
                                        'mid level',
                                        'senior',
                                      };
                                      if (!valid.contains(normalized)) {
                                        setDialogState(() {
                                          dialogError =
                                              'validation_invalid_experience_level'
                                                  .tr();
                                        });
                                      } else {
                                        final display = normalized == 'fresher'
                                            ? 'Fresher'
                                            : normalized == 'junior'
                                            ? 'Junior'
                                            : normalized == 'mid-level' ||
                                                  normalized == 'mid level'
                                            ? 'Mid-Level'
                                            : 'Senior';
                                        Navigator.of(ctx).pop(display);
                                      }
                                    } else if (fieldKey == 'education') {
                                      final normalizedEducation =
                                          normalizeEducation(val);
                                      if (normalizedEducation == null) {
                                        setDialogState(() {
                                          dialogError =
                                              'validation_invalid_education'
                                                  .tr();
                                        });
                                      } else {
                                        Navigator.of(
                                          ctx,
                                        ).pop(normalizedEducation);
                                      }
                                    } else if (fieldKey == 'type1') {
                                      final normalized = val.toLowerCase();
                                      const valid = {
                                        'full-time',
                                        'full time',
                                        'part-time',
                                        'part time',
                                        'contract',
                                        'intern',
                                      };
                                      if (!valid.contains(normalized)) {
                                        setDialogState(() {
                                          dialogError =
                                              'validation_invalid_employee_type'
                                                  .tr();
                                        });
                                      } else if (normalized == 'full-time' ||
                                          normalized == 'full time') {
                                        Navigator.of(ctx).pop('Full-Time');
                                      } else if (normalized == 'part-time' ||
                                          normalized == 'part time') {
                                        Navigator.of(ctx).pop('Part-Time');
                                      } else if (normalized == 'contract') {
                                        Navigator.of(ctx).pop('Contract');
                                      } else {
                                        Navigator.of(ctx).pop('Intern');
                                      }
                                    } else if (fieldKey == 'type2') {
                                      final normalized = val.toLowerCase();
                                      const valid = {
                                        'on-site',
                                        'on site',
                                        'onsite',
                                        'remote',
                                        'hybrid',
                                      };
                                      if (!valid.contains(normalized)) {
                                        setDialogState(() {
                                          dialogError =
                                              'validation_invalid_work_model'
                                                  .tr();
                                        });
                                      } else if (normalized == 'remote') {
                                        Navigator.of(ctx).pop('Remote');
                                      } else if (normalized == 'hybrid') {
                                        Navigator.of(ctx).pop('Hybrid');
                                      } else {
                                        Navigator.of(ctx).pop('On-Site');
                                      }
                                    } else if (fieldKey == 'salaryAmount') {
                                      final amount = Validators.parseAmount(
                                        val,
                                      );
                                      if (amount == null) {
                                        setDialogState(() {
                                          dialogError = 'valid_amount_required'
                                              .tr();
                                        });
                                      } else if (amount <= 0) {
                                        setDialogState(() {
                                          dialogError =
                                              'amount_must_be_positive'.tr();
                                        });
                                      } else {
                                        Navigator.of(ctx).pop(val);
                                      }
                                    } else if (fieldKey == 'annualLeaves' ||
                                        fieldKey == 'sickLeaves' ||
                                        fieldKey == 'casualLeaves' ||
                                        fieldKey == 'medicalLeaves') {
                                      final leaves = int.tryParse(val);
                                      if (leaves == null ||
                                          leaves < 0 ||
                                          leaves > 366) {
                                        setDialogState(() {
                                          dialogError = 'invalid_number'.tr();
                                        });
                                      } else {
                                        Navigator.of(
                                          ctx,
                                        ).pop(leaves.toString());
                                      }
                                    } else if (fieldKey == 'dob') {
                                      final dob = AppDateUtils.parseDateString(
                                        val,
                                      );
                                      if (dob == null) {
                                        setDialogState(() {
                                          dialogError =
                                              'validation_invalid_date'.tr();
                                        });
                                      } else if (!isAtLeast18(dob)) {
                                        setDialogState(() {
                                          dialogError = 'validation_min_age'
                                              .tr();
                                        });
                                      } else {
                                        Navigator.of(ctx).pop(val);
                                      }
                                    } else if (fieldKey == 'joiningDate') {
                                      final joiningDate =
                                          AppDateUtils.parseDateString(val);
                                      if (joiningDate == null) {
                                        setDialogState(() {
                                          dialogError =
                                              'validation_invalid_date'.tr();
                                        });
                                      } else {
                                        final now = DateTime.now();
                                        final today = DateTime(
                                          now.year,
                                          now.month,
                                          now.day,
                                        );
                                        final joiningOnly = DateTime(
                                          joiningDate.year,
                                          joiningDate.month,
                                          joiningDate.day,
                                        );
                                        if (joiningOnly.isAfter(today)) {
                                          setDialogState(() {
                                            dialogError =
                                                'joining_date_cannot_be_future'
                                                    .tr();
                                          });
                                        } else {
                                          Navigator.of(ctx).pop(val);
                                        }
                                      }
                                    } else {
                                      if (isMediaField) {
                                        if (mediaDataUrl != null) {
                                          worker['${fieldKey}_name'] =
                                              mediaFileName ?? '';
                                          Navigator.of(ctx).pop(mediaDataUrl);
                                        } else if (hasExistingUpload) {
                                          worker['${fieldKey}_name'] =
                                              _extractFileName(
                                                currentValue,
                                                fieldKey,
                                              );
                                          Navigator.of(ctx).pop(currentValue);
                                        } else if (val.isNotEmpty &&
                                            !val.startsWith('data:')) {
                                          final uri = Uri.tryParse(val);
                                          if (uri == null ||
                                              !uri.hasAuthority ||
                                              (uri.scheme != 'http' &&
                                                  uri.scheme != 'https')) {
                                            setDialogState(() {
                                              dialogError =
                                                  'bulk_media_invalid_url'.tr();
                                            });
                                            return;
                                          }
                                          final lastSegment =
                                              uri.pathSegments.isEmpty
                                              ? ''
                                              : uri.pathSegments.last;
                                          final ext = lastSegment.contains('.')
                                              ? lastSegment
                                                    .split('.')
                                                    .last
                                                    .toLowerCase()
                                              : '';
                                          const imageExts = {
                                            'png',
                                            'jpeg',
                                            'jpg',
                                          };
                                          const cvExts = {
                                            'pdf',
                                            'doc',
                                            'docx',
                                            'jpg',
                                            'jpeg',
                                            'png',
                                          };
                                          if (fieldKey == 'cv' &&
                                              ext.isNotEmpty &&
                                              !cvExts.contains(ext)) {
                                            setDialogState(() {
                                              dialogError =
                                                  'bulk_media_cv_format_error'
                                                      .tr();
                                            });
                                          } else if (fieldKey != 'cv' &&
                                              ext.isNotEmpty &&
                                              !imageExts.contains(ext)) {
                                            setDialogState(() {
                                              dialogError =
                                                  'bulk_media_image_format_error'
                                                      .tr(
                                                        namedArgs: {
                                                          'received': ext,
                                                        },
                                                      );
                                            });
                                          } else {
                                            worker['${fieldKey}_name'] =
                                                _extractFileName(val, fieldKey);
                                            Navigator.of(ctx).pop(val);
                                          }
                                        } else {
                                          worker['${fieldKey}_name'] =
                                              _extractFileName(val, fieldKey);
                                          Navigator.of(ctx).pop(val);
                                        }
                                      } else {
                                        Navigator.of(ctx).pop(val);
                                      }
                                    }
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.check_rounded, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'save'.tr(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );

    if (result != null && mounted && workerIndex < _validWorkers.length) {
      setState(() {
        _validWorkers[workerIndex][fieldKey] = result;
        if (fieldKey == 'annualLeaves') {
          final annualLeaves = int.tryParse(result) ?? 0;
          _validWorkers[workerIndex]['availableAnnualLeaves'] = annualLeaves
              .toString();
          _validWorkers[workerIndex]['leavesUsed'] = '0';
        } else if (fieldKey == 'sickLeaves' ||
            fieldKey == 'casualLeaves' ||
            fieldKey == 'medicalLeaves') {
          _validWorkers[workerIndex][fieldKey] = (int.tryParse(result) ?? 0)
              .toString();
        }
        // Recompute missing columns so that a column the user has now filled
        // for every worker no longer appears in the missing-columns banner.
        _missingColumns = _missingColumns
            .where((field) => _validWorkers.any(
                (w) => (w[field] ?? '').toString().trim().isEmpty))
            .toList();
        _hasUnsavedChanges = true;
      });
      await _revalidateSingleWorker(workerIndex);
    }
  }

  Future<void> _deleteWorker(int index) async {
    if (index < 0 || index >= _validWorkers.length) return;
    final confirmed = await DeleteDialog.show(
      context: context,
      title: 'delete_worker'.tr(),
      content: 'delete_worker_desc'.tr(),
    );
    if (!confirmed) return;
    setState(() {
      _validWorkers.removeAt(index);
      _hasUnsavedChanges = _validWorkers.isNotEmpty;
      if (_validWorkers.isEmpty) {
        _hasParsedFile = false;
        _missingColumns = [];
      }
    });
    final counts = validationCounts(_validWorkers);
    if (mounted) {
      setState(() {
        _duplicateCount = counts.duplicate;
        _missingRequiredCount = counts.missing;
        _invalidDobCount = counts.invalidDob;
        _invalidGenderCount = counts.invalidGender;
      });
    }
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
            _buildTopBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildActionButtons(),
                    const SizedBox(height: 32),
                    if (_hasParsedFile) ...[
                      _buildSummaryCard(),
                      const SizedBox(height: 0),
                      if (_missingColumns.isNotEmpty) ...[
                        _buildMissingColumnsBanner(),
                        const SizedBox(height: 12),
                      ],
                      Expanded(child: _buildWorkerTable()),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
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
                  padding: EdgeInsets.all(8),
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
                    'add_bulk_workers'.tr(),
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
                    'upload_csv_subtitle'.tr(),
                    style: const TextStyle(
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

          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onNotificationTap != null) ...[
                NotificationBell(onTap: widget.onNotificationTap!),
                const SizedBox(width: 16),
              ],
              if (widget.onProfileTap != null) ...[
                GestureDetector(
                  onTap: widget.onProfileTap,
                  child: const UserAvatar(),
                ),
                const SizedBox(width: 16),
              ],
              if (_hasParsedFile &&
                  _validWorkers.isNotEmpty &&
                  _validWorkers.every((w) => !hasWorkerErrors(w)))
                _buildSaveAllButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSaveAllButton() {
    final bool isCurrentlySaving = _isSaving;
    return GestureDetector(
      onTap: () => _saveBulkWorkers(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: isCurrentlySaving
              ? const Color(0xFFE6EAEF)
              : const Color(0xFF0B50C3),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: isCurrentlySaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                'save_all'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'SF Pro Display',
                ),
              ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: _downloadTemplate,
          icon: const Icon(Icons.download, size: 20),
          label: Text('download_template'.tr()),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF0B50C3),
            elevation: 0,
            side: const BorderSide(color: Color(0xFF0B50C3)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          onPressed: _pickCsvAndParse,
          icon: const Icon(Icons.upload_file, size: 20),
          label: Text('upload_csv_file'.tr()),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0B50C3),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard() {
    final bool anyErrors = _validWorkers.any(hasWorkerErrors);
    final int errorCount = _validWorkers.where(hasWorkerErrors).length;

    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEBF5FF), Color(0xFFF3F9FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD0E5FF), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color:
                  (anyErrors
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF34D399))
                      .withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              anyErrors
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_rounded,
              color: anyErrors
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF059669),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'preview_csv_workers_found'.tr(
                  namedArgs: {
                    'count': _validWorkers.length.toString(),
                    'errors': errorCount.toString(),
                  },
                ),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E293B),
                  fontFamily: 'SF Pro Display',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                (anyErrors
                        ? 'fix_red_fields_upload_again'
                        : 'review_details_save_all')
                    .tr(),
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w400,
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMissingColumnsBanner() {
    final columns = _missingColumns
        .map((field) => kFieldLabels[field] ?? field)
        .join(', ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFB45309),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'csv_missing_columns'.tr(namedArgs: {'columns': columns}),
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerTable() {
    _hScrollController ??= ScrollController();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: Scrollbar(
              controller: _hScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: _hScrollController,
                child: SizedBox(
                  width: _tableContentWidth,
                  child: Column(
                    children: [
                      _buildTableHeader(),
                      Expanded(child: _buildTableRows()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
      ),
      child: Row(
        children: [
          _buildHeaderCell('full_name'.tr(), 150, fieldKey: 'name'),
          _buildHeaderCell('contact_number'.tr(), 130, fieldKey: 'phone'),
          _buildHeaderCell('email_address'.tr(), 150, fieldKey: 'email'),
          _buildHeaderCell('job_position'.tr(), 130, fieldKey: 'position'),
          _buildHeaderCell('salary_amount'.tr(), 130, fieldKey: 'salaryAmount'),
          _buildHeaderCell('father_name'.tr(), 150, fieldKey: 'fatherName'),
          _buildHeaderCell(
            'national_id_title'.tr(),
            130,
            fieldKey: 'nationalId',
          ),
          _buildHeaderCell('religion_title'.tr(), 120, fieldKey: 'religion'),
          _buildHeaderCell('date_of_birth'.tr(), 120, fieldKey: 'dob'),
          _buildHeaderCell('gender_title'.tr(), 100, fieldKey: 'gender'),
          _buildHeaderCell('address_title'.tr(), 130, fieldKey: 'address'),
          _buildHeaderCell(
            'relationship_status_title'.tr(),
            130,
            fieldKey: 'relationshipStatus',
          ),
          _buildHeaderCell('employee_type'.tr(), 130, fieldKey: 'type1'),
          _buildHeaderCell('work_model'.tr(), 130, fieldKey: 'type2'),
          _buildHeaderCell(
            'experience_level_title'.tr(),
            130,
            fieldKey: 'experienceLevel',
          ),
          _buildHeaderCell('education_title'.tr(), 130, fieldKey: 'education'),
          _buildHeaderCell(
            'annual_leaves_title'.tr(),
            120,
            fieldKey: 'annualLeaves',
          ),
          _buildHeaderCell(
            'sick_leaves_title'.tr(),
            120,
            fieldKey: 'sickLeaves',
          ),
          _buildHeaderCell(
            'casual_leaves_title'.tr(),
            120,
            fieldKey: 'casualLeaves',
          ),
          _buildHeaderCell(
            'medical_leaves_title'.tr(),
            120,
            fieldKey: 'medicalLeaves',
          ),
          _buildHeaderCell(
            'joining_date_title'.tr(),
            130,
            fieldKey: 'joiningDate',
          ),
          _buildHeaderCell(
            'profile_image_url'.tr(),
            110,
            fieldKey: 'profileImage',
          ),
          _buildHeaderCell('front_id_image_url'.tr(), 110, fieldKey: 'frontId'),
          _buildHeaderCell('back_id_image_url'.tr(), 110, fieldKey: 'backId'),
          _buildHeaderCell('cv_url'.tr(), 110, fieldKey: 'cv'),
        ],
      ),
    );
  }

  Widget _buildTableRows() {
    return ListView.builder(
      itemCount: _validWorkers.length,
      itemExtent: _rowHeight,
      itemBuilder: (_, index) =>
          RepaintBoundary(child: _buildWorkerRow(_validWorkers[index], index)),
    );
  }

  Widget _buildWorkerRow(Map<String, dynamic> worker, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      color: index.isEven ? const Color(0xFFFAFBFC) : Colors.white,
      child: Row(
        children: [
          _buildDataCell(
            worker['name']?.toString() ?? '',
            150,
            hasError: hasFieldError(worker, 'name'),
            fieldKey: 'name',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['phone']?.toString() ?? '',
            130,
            hasError: hasFieldError(worker, 'phone'),
            fieldKey: 'phone',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['email']?.toString() ?? '',
            150,
            hasError: hasFieldError(worker, 'email'),
            fieldKey: 'email',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['position']?.toString() ?? '',
            130,
            hasError: hasFieldError(worker, 'position'),
            fieldKey: 'position',
            workerIndex: index,
          ),
          _buildDataCell(
            _formatSalaryWithCommas(worker['salaryAmount']),
            130,
            hasError: hasFieldError(worker, 'salaryAmount'),
            fieldKey: 'salaryAmount',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['fatherName']?.toString() ?? '',
            150,
            hasError: hasFieldError(worker, 'fatherName'),
            fieldKey: 'fatherName',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['nationalId']?.toString() ?? '',
            130,
            hasError: hasFieldError(worker, 'nationalId'),
            fieldKey: 'nationalId',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['religion']?.toString() ?? '',
            120,
            hasError: hasFieldError(worker, 'religion'),
            fieldKey: 'religion',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['dob']?.toString() ?? '',
            120,
            hasError: hasFieldError(worker, 'dob'),
            fieldKey: 'dob',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['gender']?.toString() ?? '',
            100,
            hasError: hasFieldError(worker, 'gender'),
            fieldKey: 'gender',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['address']?.toString() ?? '',
            130,
            hasError: hasFieldError(worker, 'address'),
            fieldKey: 'address',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['relationshipStatus']?.toString() ?? '',
            130,
            hasError: hasFieldError(worker, 'relationshipStatus'),
            fieldKey: 'relationshipStatus',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['type1']?.toString() ?? '',
            130,
            hasError: hasFieldError(worker, 'type1'),
            fieldKey: 'type1',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['type2']?.toString() ?? '',
            130,
            hasError: hasFieldError(worker, 'type2'),
            fieldKey: 'type2',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['experienceLevel']?.toString() ?? '',
            130,
            hasError: hasFieldError(worker, 'experienceLevel'),
            fieldKey: 'experienceLevel',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['education']?.toString() ?? '',
            130,
            hasError: hasFieldError(worker, 'education'),
            fieldKey: 'education',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['annualLeaves']?.toString() ?? '',
            120,
            hasError: hasFieldError(worker, 'annualLeaves'),
            fieldKey: 'annualLeaves',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['sickLeaves']?.toString() ?? '',
            120,
            hasError: hasFieldError(worker, 'sickLeaves'),
            fieldKey: 'sickLeaves',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['casualLeaves']?.toString() ?? '',
            120,
            hasError: hasFieldError(worker, 'casualLeaves'),
            fieldKey: 'casualLeaves',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['medicalLeaves']?.toString() ?? '',
            120,
            hasError: hasFieldError(worker, 'medicalLeaves'),
            fieldKey: 'medicalLeaves',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['joiningDate']?.toString() ?? '',
            130,
            hasError: hasFieldError(worker, 'joiningDate'),
            fieldKey: 'joiningDate',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['profileImage']?.toString() ?? '',
            110,
            hasError: hasFieldError(worker, 'profileImage'),
            fieldKey: 'profileImage',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['frontId']?.toString() ?? '',
            110,
            hasError: hasFieldError(worker, 'frontId'),
            fieldKey: 'frontId',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['backId']?.toString() ?? '',
            110,
            hasError: hasFieldError(worker, 'backId'),
            fieldKey: 'backId',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['cv']?.toString() ?? '',
            110,
            hasError: hasFieldError(worker, 'cv'),
            fieldKey: 'cv',
            workerIndex: index,
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => _deleteWorker(index),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: SvgPicture.asset(
                  'assets/delete_icon.svg',
                  width: 16,
                  height: 16,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFFEF4444),
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

  Widget _buildHeaderCell(String text, double width, {String? fieldKey}) {
    final bool hasErr =
        fieldKey != null && errorFieldNames(_validWorkers).contains(fieldKey);
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      margin: const EdgeInsets.only(right: 16),
      child: Row(
        children: [
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: hasErr
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF475569),
                fontFamily: 'SF Pro Display',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasErr) ...[
            const SizedBox(width: 4),
            const Icon(Icons.error, size: 14, color: Color(0xFFDC2626)),
          ],
        ],
      ),
    );
  }

  Widget _buildDataCell(
    String text,
    double width, {
    bool isBold = false,
    bool hasError = false,
    String? fieldKey,
    int workerIndex = -1,
  }) {
    final isMediaField =
        fieldKey == 'profileImage' ||
        fieldKey == 'frontId' ||
        fieldKey == 'backId' ||
        fieldKey == 'cv';

    final hasValue = text.isNotEmpty && text != '-';

    String displayText;
    if (hasError && text.isEmpty) {
      displayText = 'required_field'.tr();
    } else if (isMediaField && hasValue) {
      if (workerIndex >= 0 && workerIndex < _validWorkers.length) {
        final storedName = _validWorkers[workerIndex]['${fieldKey}_name'];
        if (storedName != null && storedName.toString().isNotEmpty) {
          displayText = storedName.toString();
        } else if (text.startsWith('data:')) {
          final mime = text.split(';').first.split(':').last;
          displayText = mime == 'application/pdf'
              ? 'document.pdf'
              : 'image.jpg';
        } else {
          displayText = _extractFileName(text, fieldKey);
        }
      } else if (text.startsWith('data:')) {
        final mime = text.split(';').first.split(':').last;
        displayText = mime == 'application/pdf' ? 'document.pdf' : 'image.jpg';
      } else {
        displayText = _extractFileName(text, fieldKey);
      }
    } else if (text.isEmpty) {
      displayText = '-';
    } else {
      displayText = text;
    }

    if (displayText.contains('\n') || displayText.contains('\r')) {
      displayText = displayText.replaceAll(RegExp(r'[\r\n]+'), ' ');
    }

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      margin: const EdgeInsets.only(right: 16),
      child: Row(
        children: [
          if (isMediaField && hasValue) ...[
            _buildMediaThumbnail(text, fieldKey),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              displayText,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: hasError
                    ? const Color(0xFFDC2626)
                    : isBold
                    ? const Color(0xFF0F172A)
                    : const Color(0xFF334155),
                fontFamily: 'SF Pro Display',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (workerIndex >= 0 && fieldKey != null)
            GestureDetector(
              onTap: () => _editCell(workerIndex, fieldKey),
              child: Container(
                margin: const EdgeInsets.only(left: 4),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: hasError
                      ? const Color(0xFFDC2626).withValues(alpha: 0.1)
                      : const Color(0xFF6B7280).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  Icons.edit_rounded,
                  size: 13,
                  color: hasError
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF6B7280),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _extractFileName(String url, String? fieldKey) {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return url;
      final path = uri.path;
      if (path.isEmpty || path == '/') return url;
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) return url;
      final lastSegment = segments.last;
      if (lastSegment.contains('.')) return lastSegment;
      final defaultName = switch (fieldKey) {
        'profileImage' => 'profile.jpg',
        'frontId' => 'front_id.jpg',
        'backId' => 'back_id.jpg',
        'cv' => 'document.pdf',
        _ => 'file',
      };
      return defaultName;
    } catch (_) {
      return url;
    }
  }

  Widget _buildMediaThumbnail(String value, String? fieldKey) {
    const imageFallback = SizedBox(
      width: 24,
      height: 24,
      child: Center(
        child: Icon(Icons.image_outlined, size: 18, color: Color(0xFF64748B)),
      ),
    );

    final documentFallback = SizedBox(
      width: 24,
      height: 24,
      child: Image.asset(
        'assets/resume.png',
        width: 24,
        height: 24,
        fit: BoxFit.contain,
      ),
    );

    if (value.startsWith('data:image')) {
      try {
        final commaIndex = value.indexOf(',');
        if (commaIndex >= 0) {
          final bytes = base64Decode(value.substring(commaIndex + 1));
          if (bytes.isNotEmpty) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.memory(
                bytes,
                width: 24,
                height: 24,
                fit: BoxFit.cover,
                cacheWidth: 48,
                cacheHeight: 48,
                errorBuilder: (_, _, _) => imageFallback,
              ),
            );
          }
        }
      } catch (_) {
        // Fall through to the fallback icon.
      }
      return imageFallback;
    }

    if (value.startsWith('data:')) {
      return fieldKey == 'cv' ? documentFallback : imageFallback;
    }

    if (fieldKey == 'cv') return documentFallback;

    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return imageFallback;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        value,
        width: 24,
        height: 24,
        fit: BoxFit.cover,
        cacheWidth: 48,
        cacheHeight: 48,
        errorBuilder: (_, _, _) => imageFallback,
      ),
    );
  }
}
