import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:ui' as ui;
import '../../utils/ui_helpers.dart';
import '../../utils/helpers.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/worker.dart';
import '../../providers.dart';
import '../../services/auth_service.dart';
import '../../services/bulk_worker_csv_service.dart';
import '../../services/bulk_worker_media_service.dart';
import '../../services/dummy_data.dart';
import '../../services/error_reporter.dart';
import '../../services/firestore_service.dart';
import '../../services/time_off_service.dart';
import '../../services/upload_service.dart';
import '../../utils/utils.dart';
import '../../widgets/bulk_worker_edit_dialog.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/unsaved_changes_dialog.dart';

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

class AddBulkWorkerScreen extends ConsumerStatefulWidget {
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

class AddBulkWorkerScreenState extends ConsumerState<AddBulkWorkerScreen> {
  static const double _tableContentWidth = 3628;
  static const double _rowHeight = 65.0;

  late final AuthService _authService;
  late final FirestoreService _firestore;

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
  bool _identityCacheLoaded = false;
  List<String> _missingColumns = [];
  List<String> _uploadedMediaUrls = [];

  final Map<String, List<String>> _uploadedMediaByRowId = {};

  ScrollController? _hScrollController;
  StreamSubscription? _workersSubscription;
  StreamSubscription? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);
    _authSubscription = _authService.authStateChanges.listen((_) {
      _clearIdentityCache();
    });
            _loadExistingIdentitySets().ignore();
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
    _identityCacheLoaded = false;
  }

  bool get hasUnsavedChanges => _hasUnsavedChanges;

  Future<bool> confirmDiscard() => _onWillPop();

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) return true;
    return UnsavedChangesDialog.show(context);
  }

  Map<String, dynamic> _preNormalizeForWorker(Map<String, dynamic> w) {
    final normalized = Map<String, dynamic>.from(w);

    for (final key in ['dob', 'joiningDate']) {
      final raw = normalized[key]?.toString().trim() ?? '';
      if (raw.isEmpty) continue;

      final parsed =
          AppDateUtils.parseDdMmYyyy(raw) ?? AppDateUtils.dateFromValue(raw);
      normalized[key] = parsed != null
          ? AppDateUtils.asUtcDateOnly(parsed)
          : '';
    }

    return normalized;
  }

  List<Map<String, dynamic>> get _workersReadyToSave {
    return _validWorkers.where((w) => !hasWorkerErrors(w)).map((w) {
      final clean = Map<String, dynamic>.from(w)
        ..remove('_fieldErrors')
        ..remove('_rowNumber');

      final rowId = (w['clientRowId'] ?? w['client_row_id'] ?? '')
          .toString()
          .trim();
      final normalizedMap = _preNormalizeForWorker(clean);
      final result = Worker.fromMap(normalizedMap).toMap();
      result['payroll_initialized'] = true;

      if (rowId.isNotEmpty) {
        result['clientRowId'] = rowId;
      }

      return result;
    }).toList();
  }

  String _computeFileHash(Uint8List bytes) => computeFileHash(bytes);

  Future<void> _downloadTemplate() async {
    try {
      await downloadTemplate(context);
    } catch (_) {
      if (!mounted) return;
      FlashySnackBar.show(
        context,
        message: 'could_not_download_template'.tr(),
        isError: true,
      );
    }
  }

  Future<void> _pickCsvAndParse() async {
    try {
      final bytes = await pickCsvFile();
      if (bytes == null) return;

      final fileHash = _computeFileHash(bytes);
      if (_lastFileHash != null && _lastFileHash == fileHash) {
        if (!mounted) return;
        FlashySnackBar.show(
          context,
          message: 'same_csv_file_already_uploaded'.tr(),
          isError: true,
        );
        return;
      }

      final rows = await compute(parseCsvInBackground, bytes);
      if (!mounted) return;

      final didParse = await _processCsvData(rows);
      if (didParse) {
        _lastFileHash = fileHash;
      }
    } catch (_) {
      if (!mounted) return;
      FlashySnackBar.show(
        context,
        message: 'error_picking_csv'.tr(),
        isError: true,
      );
    }
  }

  Future<({Set<String> emails, Set<String> nationalIds})>
  _loadExistingIdentitySets() async {
            if (_identityCacheLoaded) {
      return (emails: _cachedEmails, nationalIds: _cachedNationalIds);
    }

    final isGuest = _authService.currentUser?.isAnonymous ?? false;
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
    _identityCacheLoaded = true;

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
        .where((f) => !foundFields.contains(f))
        .toList();

    final ({Set<String> emails, Set<String> nationalIds}) existing;
    try {
      existing = await _loadExistingIdentitySets();
    } catch (_) {
      if (!mounted) return false;
      FlashySnackBar.show(
        context,
        message: 'could_not_validate_csv_duplicates'.tr(),
        isError: true,
      );
      return false;
    }

    if (!mounted) return false;

    final parsedWorkers = <Map<String, dynamic>>[];
    final csvEmails = <String>{};
    final csvNationalIds = <String>{};

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.every((e) => e.toString().trim().isEmpty))
        continue;

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

        if (workerData[matchedKey]?.toString().trim().isNotEmpty ?? false)
          continue;
        workerData[matchedKey] = value;
      }

      final errors = validateWorkerData(
        workerData,
        existingEmails: existing.emails,
        existingNationalIds: existing.nationalIds,
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
      workerData['_fieldErrors'] = errors;
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
            .map((f) => kFieldLabels[f] ?? f)
            .join(', ');
        snackParts.add(
          'csv_missing_columns'.tr(namedArgs: {'columns': columns}),
        );
      }

      if (allMissingFieldNames.isNotEmpty) {
        final fields = allMissingFieldNames
            .map((f) => kFieldLabels[f] ?? f)
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
    ({Set<String> emails, Set<String> nationalIds}) existing;
    try {
      existing = await _loadExistingIdentitySets();
    } catch (e) {
      debugPrint('Error loading existing identity sets: $e');
      existing = (emails: <String>{}, nationalIds: <String>{});
    }

    final csvEmails = <String>{};
    final csvNationalIds = <String>{};

    for (final workerData in _validWorkers) {
      final errors = validateWorkerData(
        workerData,
        existingEmails: existing.emails,
        existingNationalIds: existing.nationalIds,
        csvEmails: csvEmails,
        csvNationalIds: csvNationalIds,
      );

      final email = WorkerIdentity.normalizeEmail(workerData['email']);
      final nationalId = WorkerIdentity.normalizeNationalId(
        workerData['nationalId'],
      );
      if (email.isNotEmpty) csvEmails.add(email);
      if (nationalId.isNotEmpty) csvNationalIds.add(nationalId);

      workerData['_fieldErrors'] = errors;
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
    workerData['_fieldErrors'] = validateWorkerData(
      workerData,
      existingEmails: existing.emails,
      existingNationalIds: existing.nationalIds,
      csvEmails: csvEmails,
      csvNationalIds: csvNationalIds,
    );

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

    setState(() => _isSaving = true);
    _showBulkProgressDialog();
    var progressDialogOpen = true;

    void dismissProgressDialog() {
      if (!progressDialogOpen) return;
      progressDialogOpen = false;
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    final isGuest = _authService.currentUser?.isAnonymous ?? false;

    try {
      final revalidated = await _revalidateAllWorkers();
      if (!revalidated || !mounted) return;

      if (_validWorkers.isEmpty) {
        dismissProgressDialog();
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
        dismissProgressDialog();
        _showNoValidWorkersMessage(workersWithErrors);
        return;
      }

      final errorCounts = _countErrorTypes(workersWithErrors);
      _uploadedMediaUrls = [];

      final saveResult = await _performSave(
        isGuest: isGuest,
        workersReadyToSave: workersReadyToSave,
      );

      _clearIdentityCache();
      if (!mounted) return;

      dismissProgressDialog();

      _showSaveResultSnackBar(
        saveResult: saveResult,
        workersWithErrors: workersWithErrors,
        errorCounts: errorCounts,
        isGuest: isGuest,
      );

      if (saveResult.importedCount > 0) {
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

      if (isGuest) {
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
      dismissProgressDialog();

      if (mounted) {
        FlashySnackBar.show(
          context,
          message:
              '${'could_not_save_worker'.tr()}\n${readableSaveError(error)}',
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

  void _showNoValidWorkersMessage(
    List<Map<String, dynamic>> workersWithErrors,
  ) {
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
  }

  ({int duplicate, int missing, int invalidDob, int invalidGender})
  _countErrorTypes(List<Map<String, dynamic>> workersWithErrors) {
    final requiredMsg = 'validation_required'.tr();
    final dupEmailMsg = 'validation_duplicate_email'.tr();
    final dupNidMsg = 'validation_duplicate_national_id'.tr();

    int duplicate = 0;
    int missing = 0;
    int invalidDob = 0;
    int invalidGender = 0;

    for (final worker in workersWithErrors) {
      final errors = fieldErrors(worker);

      if (errors['email'] == dupEmailMsg || errors['nationalId'] == dupNidMsg) {
        duplicate++;
      }
      if (errors.values.contains(requiredMsg)) {
        missing++;
      }
      if (errors.containsKey('dob') && errors['dob'] != requiredMsg) {
        invalidDob++;
      }
      if (errors.containsKey('gender') && errors['gender'] != requiredMsg) {
        invalidGender++;
      }
    }

    return (
      duplicate: duplicate,
      missing: missing,
      invalidDob: invalidDob,
      invalidGender: invalidGender,
    );
  }

  Future<_SaveResult> _performSave({
    required bool isGuest,
    required List<Map<String, dynamic>> workersReadyToSave,
  }) async {
    if (isGuest) {
      return _saveAsGuest(workersReadyToSave);
    }
    return _saveToFirestore(workersReadyToSave);
  }

  Future<_SaveResult> _saveAsGuest(
    List<Map<String, dynamic>> workersReadyToSave,
  ) async {
    final existingWorkers = DummyData.workers.toList();
    final acceptedWorkers = <Map<String, dynamic>>[];
    int guestSkippedDuplicates = 0;

            final knownEmails = <String>{};
    final knownNationalIds = <String>{};
    for (final w in existingWorkers) {
      final e = WorkerIdentity.normalizeEmail(w['email']);
      if (e.isNotEmpty) knownEmails.add(e);
      final n = WorkerIdentity.normalizeNationalId(w['nationalId']);
      if (n.isNotEmpty) knownNationalIds.add(n);
    }

    for (final worker in workersReadyToSave) {
      final email = WorkerIdentity.normalizeEmail(worker['email']);
      final nationalId = WorkerIdentity.normalizeNationalId(worker['nationalId']);

      final isDuplicate = (email.isNotEmpty && knownEmails.contains(email)) ||
          (nationalId.isNotEmpty && knownNationalIds.contains(nationalId));

      if (isDuplicate) {
        guestSkippedDuplicates++;
        continue;
      }
      if (email.isNotEmpty) knownEmails.add(email);
      if (nationalId.isNotEmpty) knownNationalIds.add(nationalId);
      acceptedWorkers.add(worker);
    }

        final nowMicros = DateTime.now().microsecondsSinceEpoch;
    final newWorkers = <Map<String, dynamic>>[
      for (var i = 0; i < acceptedWorkers.length; i++)
        {...acceptedWorkers[i], 'id': 'dummy_${nowMicros}_$i'},
    ];
    DummyData.workers
      ..clear()
      ..addAll([...newWorkers.reversed, ...existingWorkers]);

            await DummyData.saveWorkersToPrefs();

    return _SaveResult(
      importedCount: acceptedWorkers.length,
      guestSkippedDuplicates: guestSkippedDuplicates,
    );
  }

  Future<_SaveResult> _saveToFirestore(
    List<Map<String, dynamic>> workersReadyToSave,
  ) async {
    workersReadyToSave = await uploadEmbeddedWorkerMedia(
      workersReadyToSave,
      uploadedMediaUrls: _uploadedMediaUrls,
      uploadedMediaByRowId: _uploadedMediaByRowId,
    );

    final bulkResult = await _firestore.addBulkWorkers(
      workersReadyToSave,
      existingEmails: _cachedEmails,
      existingNationalIds: _cachedNationalIds,
    );

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

    return _SaveResult(
      importedCount: bulkResult.imported,
      bulkResult: bulkResult,
    );
  }

  void _showSaveResultSnackBar({
    required _SaveResult saveResult,
    required List<Map<String, dynamic>> workersWithErrors,
    required ({int duplicate, int missing, int invalidDob, int invalidGender})
    errorCounts,
    required bool isGuest,
  }) {
    final serverDuplicateCount =
        saveResult.bulkResult?.skipReasons
            .where((r) => r.trim().toLowerCase().startsWith('duplicate '))
            .length ??
        0;

    final finalSkippedDuplicates =
        errorCounts.duplicate +
        serverDuplicateCount +
        saveResult.guestSkippedDuplicates;

    final summaryParts = <String>[
      'workers_added_successfully'.tr(
        namedArgs: {'count': saveResult.importedCount.toString()},
      ),
    ];

    if (finalSkippedDuplicates > 0) {
      summaryParts.add(
        'skipped_duplicates_message'.tr(
          namedArgs: {'count': finalSkippedDuplicates.toString()},
        ),
      );
    }

    if (saveResult.bulkResult != null) {
      for (final reason in saveResult.bulkResult!.skipReasons) {
        summaryParts.add('  • $reason');
      }
    }

    if (errorCounts.missing > 0) {
      summaryParts.add(
        'skipped_missing_required_message'.tr(
          namedArgs: {'count': errorCounts.missing.toString()},
        ),
      );
    }

    if (errorCounts.invalidDob > 0) {
      summaryParts.add(
        'skipped_invalid_dob_message'.tr(
          namedArgs: {'count': errorCounts.invalidDob.toString()},
        ),
      );
    }

    if (errorCounts.invalidGender > 0) {
      summaryParts.add(
        'skipped_invalid_gender_message'.tr(
          namedArgs: {'count': errorCounts.invalidGender.toString()},
        ),
      );
    }

    final hasSkipped =
        workersWithErrors.isNotEmpty ||
        (saveResult.bulkResult?.skipped ?? 0) > 0 ||
        saveResult.guestSkippedDuplicates > 0;

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

    final existingEmails = <String>{};
    final existingNationalIds = <String>{};

    if (fieldKey == 'email' || fieldKey == 'nationalId') {
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
      builder: (ctx) => _EditCellDialog(
        currentValue: currentValue,
        fieldKey: fieldKey,
        label: label,
        workerIndex: workerIndex,
        worker: worker,
        validWorkers: _validWorkers,
        existingEmails: existingEmails,
        existingNationalIds: existingNationalIds,
      ),
    );

    if (result == null || !mounted || workerIndex >= _validWorkers.length)
      return;

    setState(() {
      _validWorkers[workerIndex][fieldKey] = result;

      if (fieldKey == 'annualLeaves') {
        final leaves = int.tryParse(result) ?? 0;
        _validWorkers[workerIndex]['annualLeaves'] = leaves;
        _validWorkers[workerIndex]['availableAnnualLeaves'] = leaves;
        _validWorkers[workerIndex]['leavesUsed'] = 0;
      } else if (fieldKey == 'sickLeaves' ||
          fieldKey == 'casualLeaves' ||
          fieldKey == 'medicalLeaves') {
        final days = int.tryParse(result) ?? 0;
        _validWorkers[workerIndex][fieldKey] = days;
        final availableKey =
            'available${fieldKey[0].toUpperCase()}${fieldKey.substring(1)}';
        _validWorkers[workerIndex][availableKey] = days;
      }

      _validWorkers[workerIndex].addAll(
        TimeOffService.canonicalWorkerLeaveFields(_validWorkers[workerIndex]),
      );

      _missingColumns = _missingColumns
          .where(
            (field) => _validWorkers.any(
              (w) => (w[field] ?? '').toString().trim().isEmpty,
            ),
          )
          .toList();

      _hasUnsavedChanges = true;
    });

    await _revalidateSingleWorker(workerIndex);
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
      onPopInvokedWithResult: (didPop, _) async {
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
                    ] else
                      Expanded(child: _buildEmptyState()),
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
    return GestureDetector(
      onTap: _saveBulkWorkers,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: _isSaving ? const Color(0xFFE6EAEF) : const Color(0xFF0B50C3),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
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
    final anyErrors = _validWorkers.any(hasWorkerErrors);
    final errorCount = _validWorkers.where(hasWorkerErrors).length;

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
    final columns = _missingColumns.map((f) => kFieldLabels[f] ?? f).join(', ');

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

  Widget _buildEmptyState() {
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
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEFF6FF),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.upload_file_rounded,
                                  size: 40,
                                  color: Color(0xFF0B50C3),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'upload_csv_to_preview'.tr(),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'upload_csv_hint'.tr(),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w400,
                                  fontFamily: 'SF Pro Display',
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
          _headerCell('full_name'.tr(), 150, fieldKey: 'name'),
          _headerCell('contact_number'.tr(), 130, fieldKey: 'phone'),
          _headerCell('email_address'.tr(), 150, fieldKey: 'email'),
          _headerCell('job_position'.tr(), 130, fieldKey: 'position'),
          _headerCell('salary_amount'.tr(), 130, fieldKey: 'salaryAmount'),
          _headerCell('father_name'.tr(), 150, fieldKey: 'fatherName'),
          _headerCell('national_id_title'.tr(), 130, fieldKey: 'nationalId'),
          _headerCell('religion_title'.tr(), 120, fieldKey: 'religion'),
          _headerCell('date_of_birth'.tr(), 120, fieldKey: 'dob'),
          _headerCell('gender_title'.tr(), 100, fieldKey: 'gender'),
          _headerCell('address_title'.tr(), 130, fieldKey: 'address'),
          _headerCell(
            'relationship_status_title'.tr(),
            130,
            fieldKey: 'relationshipStatus',
          ),
          _headerCell('employee_type'.tr(), 130, fieldKey: 'type1'),
          _headerCell('work_model'.tr(), 130, fieldKey: 'type2'),
          _headerCell(
            'experience_level_title'.tr(),
            130,
            fieldKey: 'experienceLevel',
          ),
          _headerCell('education_title'.tr(), 130, fieldKey: 'education'),
          _headerCell(
            'annual_leaves_title'.tr(),
            120,
            fieldKey: 'annualLeaves',
          ),
          _headerCell('sick_leaves_title'.tr(), 120, fieldKey: 'sickLeaves'),
          _headerCell(
            'casual_leaves_title'.tr(),
            120,
            fieldKey: 'casualLeaves',
          ),
          _headerCell(
            'medical_leaves_title'.tr(),
            120,
            fieldKey: 'medicalLeaves',
          ),
          _headerCell('joining_date_title'.tr(), 130, fieldKey: 'joiningDate'),
          _headerCell('profile_image_url'.tr(), 110, fieldKey: 'profileImage'),
          _headerCell('front_id_image_url'.tr(), 110, fieldKey: 'frontId'),
          _headerCell('back_id_image_url'.tr(), 110, fieldKey: 'backId'),
          _headerCell('cv_url'.tr(), 110, fieldKey: 'cv'),
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
    String cellValue(String key) => worker[key]?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      color: index.isEven ? const Color(0xFFFAFBFC) : Colors.white,
      child: Row(
        children: [
          _dataCell(
            cellValue('name'),
            150,
            fieldKey: 'name',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('phone'),
            130,
            fieldKey: 'phone',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('email'),
            150,
            fieldKey: 'email',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('position'),
            130,
            fieldKey: 'position',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            (worker['salaryAmount'] != null &&
                    worker['salaryAmount'].toString().trim().isNotEmpty)
                ? '${CurrencyUtils.symbolFor(CurrencyUtils.companyCurrency)} ${CurrencyUtils.formatWithCommas(worker['salaryAmount'])}'
                : '',
            130,
            fieldKey: 'salaryAmount',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('fatherName'),
            150,
            fieldKey: 'fatherName',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('nationalId'),
            130,
            fieldKey: 'nationalId',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('religion'),
            120,
            fieldKey: 'religion',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('dob'),
            120,
            fieldKey: 'dob',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('gender'),
            100,
            fieldKey: 'gender',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('address'),
            130,
            fieldKey: 'address',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('relationshipStatus'),
            130,
            fieldKey: 'relationshipStatus',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('type1'),
            130,
            fieldKey: 'type1',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('type2'),
            130,
            fieldKey: 'type2',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('experienceLevel'),
            130,
            fieldKey: 'experienceLevel',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('education'),
            130,
            fieldKey: 'education',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('annualLeaves'),
            120,
            fieldKey: 'annualLeaves',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('sickLeaves'),
            120,
            fieldKey: 'sickLeaves',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('casualLeaves'),
            120,
            fieldKey: 'casualLeaves',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('medicalLeaves'),
            120,
            fieldKey: 'medicalLeaves',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('joiningDate'),
            130,
            fieldKey: 'joiningDate',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('profileImage'),
            110,
            fieldKey: 'profileImage',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('frontId'),
            110,
            fieldKey: 'frontId',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('backId'),
            110,
            fieldKey: 'backId',
            workerIndex: index,
            worker: worker,
          ),
          _dataCell(
            cellValue('cv'),
            110,
            fieldKey: 'cv',
            workerIndex: index,
            worker: worker,
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

  Widget _headerCell(String text, double width, {String? fieldKey}) {
    final hasErr =
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

  Widget _dataCell(
    String text,
    double width, {
    bool isBold = false,
    required String fieldKey,
    required int workerIndex,
    required Map<String, dynamic> worker,
  }) {
    final hasError = hasFieldError(worker, fieldKey);
    final isMediaField = _isMediaField(fieldKey);
    final hasValue = text.isNotEmpty && text != '-';

    final displayText = _resolveDisplayText(
      text: text,
      hasError: hasError,
      isMediaField: isMediaField,
      hasValue: hasValue,
      workerIndex: workerIndex,
      fieldKey: fieldKey,
    ).replaceAll(RegExp(r'[\r\n]+'), ' ');

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
          if (workerIndex >= 0)
            GestureDetector(
              onTap: () => _editCell(workerIndex, fieldKey),
              child: Container(
                margin: const EdgeInsets.only(left: 4),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color:
                      (hasError
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF6B7280))
                          .withValues(alpha: 0.1),
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

  bool _isMediaField(String fieldKey) {
    return fieldKey == 'profileImage' ||
        fieldKey == 'frontId' ||
        fieldKey == 'backId' ||
        fieldKey == 'cv';
  }

  String _resolveDisplayText({
    required String text,
    required bool hasError,
    required bool isMediaField,
    required bool hasValue,
    required int workerIndex,
    required String fieldKey,
  }) {
    if (hasError && text.isEmpty) return 'required_field'.tr();

    if (isMediaField && hasValue) {
      if (workerIndex >= 0 && workerIndex < _validWorkers.length) {
        final storedName = _validWorkers[workerIndex]['${fieldKey}_name'];
        if (storedName != null && storedName.toString().isNotEmpty) {
          return storedName.toString();
        }
      }

      if (text.startsWith('data:')) {
        final mime = text.split(';').first.split(':').last;
        return mime == 'application/pdf' ? 'document.pdf' : 'image.jpg';
      }

      return _extractFileName(text, fieldKey);
    }

    if (text.isEmpty) return '-';
    return text;
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

      return switch (fieldKey) {
        'profileImage' => 'profile.jpg',
        'frontId' => 'front_id.jpg',
        'backId' => 'back_id.jpg',
        'cv' => 'document.pdf',
        _ => 'file',
      };
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

    final trimmed = value.trim();
    if (trimmed.isEmpty) return imageFallback;

    if (fieldKey == 'cv' ||
        trimmed.endsWith('.pdf') ||
        trimmed.contains('application/pdf')) {
      return documentFallback;
    }

    if (trimmed.startsWith('data:')) {
      return _thumbnailFromDataUri(trimmed, imageFallback);
    }

    if (trimmed.startsWith('assets/')) {
      return _thumbnailFromAsset(trimmed, imageFallback);
    }

    if (isHttpUrl(trimmed)) {
      return _thumbnailFromNetwork(trimmed, imageFallback);
    }

    if (trimmed.startsWith('/') || trimmed.startsWith('file://')) {
      return _thumbnailFromFile(trimmed, imageFallback);
    }

    return _thumbnailFromRawBase64(trimmed, imageFallback);
  }

  Widget _thumbnailFromDataUri(String dataUri, Widget fallback) {
    try {
      final commaIndex = dataUri.indexOf(',');
      final base64Content = commaIndex >= 0
          ? dataUri.substring(commaIndex + 1)
          : dataUri;
      final bytes = base64Decode(base64Content.trim());

      if (bytes.isEmpty) return fallback;

      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          bytes,
          width: 24,
          height: 24,
          fit: BoxFit.cover,
          cacheWidth: 48,
          cacheHeight: 48,
          errorBuilder: (_, _, _) => fallback,
        ),
      );
    } catch (_) {
      return fallback;
    }
  }

  Widget _thumbnailFromAsset(String assetPath, Widget fallback) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.asset(
        assetPath,
        width: 24,
        height: 24,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }

  Widget _thumbnailFromNetwork(String url, Widget fallback) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        url,
        width: 24,
        height: 24,
        fit: BoxFit.cover,
        cacheWidth: 48,
        cacheHeight: 48,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }

  Widget _thumbnailFromFile(String path, Widget fallback) {
    try {
      final filePath = path.startsWith('file://')
          ? Uri.parse(path).toFilePath()
          : path;
      final file = io.File(filePath);

      if (!file.existsSync()) return fallback;

      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          file,
          width: 24,
          height: 24,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        ),
      );
    } catch (_) {
      return fallback;
    }
  }

  Widget _thumbnailFromRawBase64(String raw, Widget fallback) {
    try {
      final bytes = base64Decode(raw);

      if (bytes.isEmpty) return fallback;

      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          bytes,
          width: 24,
          height: 24,
          fit: BoxFit.cover,
          cacheWidth: 48,
          cacheHeight: 48,
          errorBuilder: (_, _, _) => fallback,
        ),
      );
    } catch (_) {
      return fallback;
    }
  }
}

class _EditCellDialog extends StatefulWidget {
  final String currentValue;
  final String fieldKey;
  final String label;
  final int workerIndex;
  final Map<String, dynamic> worker;
  final List<Map<String, dynamic>> validWorkers;
  final Set<String> existingEmails;
  final Set<String> existingNationalIds;

  const _EditCellDialog({
    required this.currentValue,
    required this.fieldKey,
    required this.label,
    required this.workerIndex,
    required this.worker,
    required this.validWorkers,
    required this.existingEmails,
    required this.existingNationalIds,
  });

  @override
  State<_EditCellDialog> createState() => _EditCellDialogState();
}

class _EditCellDialogState extends State<_EditCellDialog> {
  late final TextEditingController _controller;
  String? _dialogError;
  String? _mediaDataUrl;
  String? _mediaFileName;
  bool _isValidatingMedia = false;
  bool _hasExistingUpload = false;

  bool get _isMediaField =>
      widget.fieldKey == 'profileImage' ||
      widget.fieldKey == 'frontId' ||
      widget.fieldKey == 'backId' ||
      widget.fieldKey == 'cv';

  bool get _isLeavesField =>
      widget.fieldKey == 'annualLeaves' ||
      widget.fieldKey == 'sickLeaves' ||
      widget.fieldKey == 'casualLeaves' ||
      widget.fieldKey == 'medicalLeaves';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentValue);

    if (_isMediaField && widget.currentValue.isNotEmpty) {
      _hasExistingUpload = true;
      final storedName = widget.worker['${widget.fieldKey}_name'];

      if (widget.currentValue.startsWith('data:')) {
        if (storedName != null && storedName.toString().isNotEmpty) {
          _controller.text = storedName.toString();
        } else {
          final mime = widget.currentValue.split(';').first.split(':').last;
          _controller.text = mime == 'application/pdf'
              ? 'document.pdf'
              : 'image.jpg';
        }
      }

      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickMediaFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: widget.fieldKey == 'cv'
            ? ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png']
            : ['jpg', 'jpeg', 'png'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = await file.readAsBytes();

      if (bytes.length > 10 * 1024 * 1024) {
        setState(() {
          _dialogError = 'file_too_large'.tr(namedArgs: {'size': '10MB'});
        });
        return;
      }

      if (bytes.isEmpty) return;

      final mime = mimeTypeForExtension(file.name);
      final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';

      setState(() {
        _mediaDataUrl = dataUrl;
        _mediaFileName = file.name;
        _hasExistingUpload = true;
        _controller.text = file.name;
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      });
    } catch (_) {
      setState(() {
        _dialogError = 'failed_to_pick_image'.tr();
      });
    }
  }

  Future<void> _onSave() async {
    if (_isValidatingMedia) return;

    final val = _controller.text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

    if (!_isMediaField && val.isEmpty) {
      setState(() => _dialogError = 'edit_cell_cannot_be_empty'.tr());
      return;
    }

    if (_isMediaField &&
        val.isEmpty &&
        (_mediaDataUrl == null || _mediaDataUrl!.isEmpty)) {
      setState(() => _dialogError = 'edit_cell_cannot_be_empty'.tr());
      return;
    }

    final result = await _validateAndGetResult(val);
    if (result != null && mounted) {
      Navigator.of(context).pop(result);
    }
  }

  Future<String?> _validateAndGetResult(String val) async {
    switch (widget.fieldKey) {
      case 'email':
        return _validateEmail(val);
      case 'nationalId':
        return _validateNationalId(val);
      case 'gender':
        return _validateGender(val);
      case 'relationshipStatus':
        return _validateRelationshipStatus(val);
      case 'experienceLevel':
        return _validateExperienceLevel(val);
      case 'education':
        return _validateEducation(val);
      case 'type1':
        return _validateType1(val);
      case 'type2':
        return _validateType2(val);
      case 'salaryAmount':
        return _validateSalaryAmount(val);
      case 'annualLeaves':
      case 'sickLeaves':
      case 'casualLeaves':
      case 'medicalLeaves':
        return _validateLeaves(val);
      case 'dob':
        return _validateDob(val);
      case 'joiningDate':
        return _validateJoiningDate(val);
      case 'profileImage':
      case 'frontId':
      case 'backId':
      case 'cv':
        return _validateMedia(val);
      default:
        return val;
    }
  }

  String? _validateEmail(String val) {
    if (val.isEmpty) return val;

    final normalized = WorkerIdentity.normalizeEmail(val);

    if (!Validators.isValidEmail(normalized) ||
        Validators.isPlaceholderEmailDomain(normalized)) {
      setState(() => _dialogError = 'validation_invalid_email'.tr());
      return null;
    }

    final isDuplicate =
        widget.existingEmails.contains(normalized) ||
        widget.validWorkers.asMap().entries.any((entry) {
          return entry.key != widget.workerIndex &&
              WorkerIdentity.normalizeEmail(
                    entry.value['email']?.toString() ?? '',
                  ) ==
                  normalized;
        });

    if (isDuplicate) {
      setState(() => _dialogError = 'validation_duplicate_email'.tr());
      return null;
    }

    return normalized;
  }

  String? _validateNationalId(String val) {
    if (val.isEmpty) return val;

    if (!Validators.isValidNationalId(val)) {
      setState(() => _dialogError = 'validation_invalid_national_id'.tr());
      return null;
    }

    final normalized = WorkerIdentity.normalizeNationalId(val);

    final isDuplicate =
        widget.existingNationalIds.contains(normalized) ||
        widget.validWorkers.asMap().entries.any((entry) {
          return entry.key != widget.workerIndex &&
              WorkerIdentity.normalizeNationalId(
                    entry.value['nationalId']?.toString() ?? '',
                  ) ==
                  normalized;
        });

    if (isDuplicate) {
      setState(() => _dialogError = 'validation_duplicate_national_id'.tr());
      return null;
    }

    return val;
  }

  String? _validateGender(String val) {
    final normalized = val.toLowerCase();
    const valid = {'male', 'female', 'other', 'others'};

    if (!valid.contains(normalized)) {
      setState(() => _dialogError = 'validation_invalid_gender'.tr());
      return null;
    }

    return switch (normalized) {
      'male' => 'Male',
      'female' => 'Female',
      'other' || 'others' => 'Other',
      _ => val,
    };
  }

  String? _validateRelationshipStatus(String val) {
    final normalized = val.toLowerCase();
    const valid = {'single', 'married'};

    if (!valid.contains(normalized)) {
      setState(() => _dialogError = 'validation_invalid_relationship'.tr());
      return null;
    }

    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  String? _validateExperienceLevel(String val) {
    final normalized = val.toLowerCase();
    const valid = {'fresher', 'junior', 'mid-level', 'mid level', 'senior'};

    if (!valid.contains(normalized)) {
      setState(() => _dialogError = 'validation_invalid_experience_level'.tr());
      return null;
    }

    return switch (normalized) {
      'fresher' => 'Fresher',
      'junior' => 'Junior',
      'mid-level' || 'mid level' => 'Mid-Level',
      'senior' => 'Senior',
      _ => val,
    };
  }

  String? _validateEducation(String val) {
    final normalized = normalizeEducation(val);

    if (normalized == null) {
      setState(() => _dialogError = 'validation_invalid_education'.tr());
      return null;
    }

    return normalized;
  }

  String? _validateType1(String val) {
    final normalized = val.toLowerCase();
    const valid = {
      'full-time',
      'full time',
      'part-time',
      'part time',
      'contract',
      'freelance',
      'intern',
    };

    if (!valid.contains(normalized)) {
      setState(() => _dialogError = 'validation_invalid_employee_type'.tr());
      return null;
    }

    return switch (normalized) {
      'full-time' || 'full time' => 'Full-Time',
      'part-time' || 'part time' => 'Part-Time',
      'contract' => 'Contract',
      'freelance' => 'Freelance',
      'intern' => 'Intern',
      _ => val,
    };
  }

  String? _validateType2(String val) {
    final normalized = val.toLowerCase();
    const valid = {'on-site', 'on site', 'onsite', 'remote', 'hybrid'};

    if (!valid.contains(normalized)) {
      setState(() => _dialogError = 'validation_invalid_work_model'.tr());
      return null;
    }

    return switch (normalized) {
      'remote' => 'Remote',
      'hybrid' => 'Hybrid',
      _ => 'On-Site',
    };
  }

  String? _validateSalaryAmount(String val) {
    final amount = Validators.parseAmount(val);

    if (amount == null) {
      setState(() => _dialogError = 'valid_amount_required'.tr());
      return null;
    }

    if (amount <= 0) {
      setState(() => _dialogError = 'amount_must_be_positive'.tr());
      return null;
    }

    return val;
  }

  String? _validateLeaves(String val) {
    final leaves = int.tryParse(val);

    if (leaves == null || leaves < 0 || leaves > 366) {
      setState(() => _dialogError = 'invalid_number'.tr());
      return null;
    }

    return leaves.toString();
  }

  String? _validateDob(String val) {
    final dob = AppDateUtils.parseDdMmYyyy(val);

    if (dob == null) {
      setState(() => _dialogError = 'validation_invalid_date'.tr());
      return null;
    }

    if (!isAtLeast18(dob)) {
      setState(() => _dialogError = 'validation_min_age'.tr());
      return null;
    }

    return val;
  }

  String? _validateJoiningDate(String val) {
    final joiningDate = AppDateUtils.parseDdMmYyyy(val);

    if (joiningDate == null) {
      setState(() => _dialogError = 'validation_invalid_date'.tr());
      return null;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final joiningOnly = DateTime(
      joiningDate.year,
      joiningDate.month,
      joiningDate.day,
    );

    if (joiningOnly.isAfter(today)) {
      setState(() => _dialogError = 'joining_date_cannot_be_future'.tr());
      return null;
    }

    return val;
  }

  Future<String?> _validateMedia(String val) async {
    if (_mediaDataUrl != null) {
      widget.worker['${widget.fieldKey}_name'] = _mediaFileName ?? '';
      return _mediaDataUrl;
    }

    final mediaValue = val.isNotEmpty ? val : widget.currentValue.trim();

    if (mediaValue.startsWith('data:')) {
      widget.worker['${widget.fieldKey}_name'] = _extractFileName(
        mediaValue,
        widget.fieldKey,
      );
      return mediaValue;
    }

    setState(() {
      _isValidatingMedia = true;
      _dialogError = null;
    });

    final mediaError = await validateRemoteWorkerMediaLink(
      field: widget.fieldKey,
      url: mediaValue,
    );

    if (!mounted) return null;

    if (mediaError != null) {
      setState(() {
        _isValidatingMedia = false;
        _dialogError = mediaError;
      });
      return null;
    }

    widget.worker['${widget.fieldKey}_name'] = _extractFileName(
      mediaValue,
      widget.fieldKey,
    );
    return mediaValue;
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

      return switch (fieldKey) {
        'profileImage' => 'profile.jpg',
        'frontId' => 'front_id.jpg',
        'backId' => 'back_id.jpg',
        'cv' => 'document.pdf',
        _ => 'file',
      };
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
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
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildInputSection(),
                  if (fieldHint(widget.fieldKey).isNotEmpty) _buildHintRow(),
                  if (_dialogError != null) _buildErrorRow(),
                  _buildActionBar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
              fontFamily: 'SF Pro Display',
            ),
          ),
          const SizedBox(height: 8),
          if (isDateField(widget.fieldKey))
            buildDateField(
              context: context,
              fieldKey: widget.fieldKey,
              currentValue: _controller.text,
              label: widget.label,
              setDialogState: setState,
              onDateSelected: (dateStr) => _controller.text = dateStr,
            )
          else
            Container(
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD1D5DB), width: 1.2),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: _controller,
                readOnly: isDateField(widget.fieldKey),
                autofocus: true,
                maxLines: _isMediaField ? 1 : null,
                minLines: 1,
                keyboardType: keyboardTypeForField(widget.fieldKey),
                inputFormatters: inputFormattersForField(widget.fieldKey),
                style: TextStyle(
                  fontSize: 15,
                  fontFamily: 'SF Pro Display',
                  color:
                      (_isMediaField &&
                          (_mediaDataUrl != null || _hasExistingUpload))
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFF111827),
                  overflow: TextOverflow.ellipsis,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  hintText: _isLeavesField
                      ? '0'
                      : _isMediaField
                      ? mediaFieldHint(widget.fieldKey)
                      : 'edit_cell_enter_value'.tr(
                          namedArgs: {'label': widget.label},
                        ),
                  hintStyle: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 15,
                    fontFamily: 'SF Pro Display',
                  ),
                  prefixText: widget.fieldKey == 'salaryAmount'
                      ? '${CurrencyUtils.symbolFor(CurrencyUtils.companyCurrency)} '
                      : null,
                  prefixStyle: const TextStyle(
                    color: Color(0xFF374151),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'SF Pro Display',
                  ),
                  suffixIcon: _isMediaField ? _buildMediaPickerButton() : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMediaPickerButton() {
    return GestureDetector(
      onTap: _pickMediaFile,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.fieldKey == 'cv'
                  ? Icons.attach_file_rounded
                  : widget.fieldKey == 'profileImage'
                  ? Icons.add_a_photo_rounded
                  : Icons.badge_rounded,
              size: 18,
              color: const Color(0xFF0247C4),
            ),
            const SizedBox(width: 4),
            Text(
              widget.fieldKey == 'cv' ? 'upload_cv'.tr() : 'upload_image'.tr(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0247C4),
                fontFamily: 'SF Pro Display',
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHintRow() {
    return Padding(
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
              fieldHint(widget.fieldKey),
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF9CA3AF),
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorRow() {
    return Padding(
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
              _dialogError!,
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
    );
  }

  Widget _buildActionBar() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6B7280),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            onPressed: _onSave,
            child: _isValidatingMedia
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Row(
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
    );
  }
}

class _SaveResult {
  final int importedCount;
  final BulkWorkerResult? bulkResult;
  final int guestSkippedDuplicates;

  const _SaveResult({
    required this.importedCount,
    this.bulkResult,
    this.guestSkippedDuplicates = 0,
  });
}
