import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' as io;
import 'dart:math';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../utils/localization_helper.dart';
import '../utils/snackbar_utils.dart';
import '../utils/rate_us_helper.dart';
import '../utils/date_utils.dart';
import '../utils/currency_utils.dart';
import '../utils/worker_identity.dart';
import '../utils/image_utils.dart';
import '../widgets/amount_text.dart';

class AddBulkWorkerScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const AddBulkWorkerScreen({super.key, this.onBack});

  @override
  State<AddBulkWorkerScreen> createState() => _AddBulkWorkerScreenState();
}

class _AddBulkWorkerScreenState extends State<AddBulkWorkerScreen> {
  static const List<String> _requiredFields = [
    'name',
    'phone',
    'email',
    'fatherName',
    'nationalId',
    'religion',
    'dob',
    'gender',
    'address',
    'relationshipStatus',
    'position',
    'type1',
    'type2',
    'experienceLevel',
    'education',
    'salaryType',
    'currency',
    'salaryAmount',
    'leavePolicy',
    'annualLeaves',
    'sickLeaves',
    'casualLeaves',
    'joiningDate',
    'frontId',
    'backId',
    'cv',
  ];

  static const Map<String, String> _fieldLabels = {
    'name': 'Full Name',
    'phone': 'Contact Number',
    'email': 'Email Address',
    'fatherName': 'Father Name',
    'nationalId': 'National ID',
    'religion': 'Religion',
    'dob': 'Date of Birth',
    'gender': 'Gender',
    'address': 'Address',
    'relationshipStatus': 'Relationship Status',
    'position': 'Job Position',
    'type1': 'Employee Type',
    'type2': 'Work Model',
    'experienceLevel': 'Experience Level',
    'education': 'Education',
    'salaryType': 'Salary Type',
    'currency': 'Currency',
    'salaryAmount': 'Salary Amount',
    'leavePolicy': 'Leave Policy',
    'annualLeaves': 'Annual Leaves',
    'sickLeaves': 'Sick Leaves',
    'casualLeaves': 'Casual Leaves',
    'joiningDate': 'Joining Date',
    'profileImage': 'Profile Image URL',
    'frontId': 'Front ID Image URL',
    'backId': 'Back ID Image URL',
    'cv': 'CV URL',
  };

  bool _isSaving = false;
  List<Map<String, dynamic>> _validWorkers = [];
  bool _hasParsedFile = false;
  int _invalidDobCount = 0;
  int _invalidGenderCount = 0;
  int _missingRequiredCount = 0;
  int _duplicateCount = 0;
  String? _lastFileHash;

  Map<String, String> _fieldErrors(Map<String, dynamic> worker) {
    final errors = worker['_fieldErrors'];
    if (errors is Map) {
      return errors.map((key, value) => MapEntry('$key', '$value'));
    }
    return const {};
  }

  bool _hasFieldError(Map<String, dynamic> worker, String field) =>
      _fieldErrors(worker).containsKey(field);

  bool _hasWorkerErrors(Map<String, dynamic> worker) =>
      _fieldErrors(worker).isNotEmpty;

  List<Map<String, dynamic>> get _workersReadyToSave =>
      _validWorkers.where((worker) => !_hasWorkerErrors(worker)).map((worker) {
        final cleanWorker = Map<String, dynamic>.from(worker);
        cleanWorker.remove('_fieldErrors');
        cleanWorker.remove('_rowNumber');
        return cleanWorker;
      }).toList();

  @override
  void initState() {
    super.initState();
  }

  String _computeFileHash(Uint8List bytes) {
    int hash = 0;
    final minLen = min(bytes.length, 8192);
    for (int i = 0; i < minLen; i++) {
      hash = ((hash << 5) + hash + bytes[i]) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  Future<void> _downloadTemplate() async {
    final String headerRow = [
      'Full Name',
      'Contact Number',
      'Email Address',
      'Father Name',
      'National ID',
      'Religion',
      'Date of Birth',
      'Gender',
      'Address',
      'Relationship Status',
      'Job Position',
      'Employee Type',
      'Work Model',
      'Experience Level',
      'Education',
      'Salary Type',
      'Currency',
      'Salary Amount',
      'Leave Policy',
      'Annual Leaves',
      'Sick Leaves',
      'Casual Leaves',
      'Joining Date',
      'Profile Image URL',
      'Front ID Image URL',
      'Back ID Image URL',
      'CV URL',
    ].join(',');
    final String dataRows =
        'John Doe,1234567890,john@example.com,Robert Doe,37405-1234567-1,Christianity,1990-05-15,Male,123 Street California,Single,Software Engineer,Full-Time,On-Site,Mid-Level,Bachelor\'s,Monthly,USD,5000,Standard,15,10,10,1/15/2025,https://i.pravatar.cc/150?u=john,https://example.com/front_id.jpg,https://example.com/back_id.jpg,https://example.com/cv/john.pdf\n'
        'Jane Smith,0987654321,jane@example.com,David Smith,37405-7654321-2,Islam,1995-10-20,Female,456 Avenue New York,Married,UI Designer,Part-Time,Remote,Senior,Bachelor\'s,Monthly,USD,6000,Standard,15,10,10,1/15/2025,https://i.pravatar.cc/150?u=jane,https://example.com/front_id2.jpg,https://example.com/back_id2.jpg,https://example.com/cv/jane.pdf\n'
        'Michael Johnson,1122334455,michael@example.com,Alan Johnson,37405-1122334-3,None,1988-02-28,Male,789 Road Texas,Single,Project Manager,Contract,Hybrid,Senior,Master\'s,Monthly,USD,7500,Standard,15,10,10,1/15/2025,https://i.pravatar.cc/150?u=michael,https://example.com/front_id3.jpg,https://example.com/back_id3.jpg,https://example.com/cv/michael.pdf\n'
        'Emily Brown,5551234567,emily@example.com,Thomas Brown,37405-9988776-5,Christianity,1992-07-08,Female,321 Oak Avenue Chicago,Married,Marketing Manager,Full-Time,On-Site,Senior,Master\'s,Monthly,USD,8500,Standard,20,12,10,1/20/2025,https://i.pravatar.cc/150?u=emily,https://example.com/front_id4.jpg,https://example.com/back_id4.jpg,https://example.com/cv/emily.pdf\n'
        'Carlos Garcia,5559876543,carlos@example.com,Luis Garcia,37405-4433221-4,Catholic,1985-03-22,Male,654 Pine Road Miami,Single,DevOps Engineer,Full-Time,On-Site,Senior,Bachelor\'s,Monthly,USD,9500,Standard,18,12,10,2/1/2025,https://i.pravatar.cc/150?u=carlos,https://example.com/front_id5.jpg,https://example.com/back_id5.jpg,https://example.com/cv/carlos.pdf\n'
        'Aisha Khan,5552468135,aisha@example.com,Imran Khan,37405-5566778-7,Islam,1993-11-12,Female,789 Maple Drive Houston,Single,Data Analyst,Full-Time,Hybrid,Mid-Level,Bachelor\'s,Monthly,USD,7000,Standard,15,10,10,2/5/2025,https://i.pravatar.cc/150?u=aisha,https://example.com/front_id6.jpg,https://example.com/back_id6.jpg,https://example.com/cv/aisha.pdf\n'
        'Robert Wilson,5553691479,robert@example.com,James Wilson,37405-1122334-8,None,1980-09-05,Male,147 Elm Street Seattle,Married,HR Director,Full-Time,On-Site,Senior,Master\'s,Annual,USD,110000,Standard,20,15,12,1/10/2025,https://i.pravatar.cc/150?u=robert,https://example.com/front_id7.jpg,https://example.com/back_id7.jpg,https://example.com/cv/robert.pdf';
    final String templateStr = '$headerRow\n$dataRows';

    try {
      String? outputFile = await FilePicker.saveFile(
        dialogTitle: 'save_worker_template'.tr(),
        fileName: 'worker_template.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: Uint8List.fromList(utf8.encode(templateStr)),
      );

      if (outputFile == null) return;

      final file = io.File(outputFile);
      await file.writeAsString(templateStr);

      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'template_saved_successfully'.tr(),
        );
      }
    } catch (e) {
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
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes != null && file.bytes!.length > 5 * 1024 * 1024) {
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'file_too_large'.tr(namedArgs: {'size': '5MB'}),
            isError: true,
          );
        }
        return;
      }
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        final diskFile = io.File(file.path!);
        final fileSize = await diskFile.length();
        if (fileSize > 5 * 1024 * 1024) {
          if (mounted) {
            FlashySnackBar.show(
              context,
              message: 'file_too_large'.tr(namedArgs: {'size': '5MB'}),
              isError: true,
            );
          }
          return;
        }
        bytes = await diskFile.readAsBytes();
      }

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


      var csvString = utf8.decode(bytes, allowMalformed: true);
      if (csvString.isNotEmpty && csvString.codeUnitAt(0) == 0xFEFF) {
        csvString = csvString.substring(1);
      }
      csvString = csvString.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

      final rows = Csv(dynamicTyping: false).decode(csvString);

      if (!mounted) return;
      await _processCsvData(rows);
      _lastFileHash = fileHash;
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'error_picking_csv'.tr(),
          isError: true,
        );
      }
    }
  }

  Future<void> _processCsvData(List<List<dynamic>> rows) async {
    if (rows.isEmpty) return;

    setState(() {
      _invalidDobCount = 0;
      _invalidGenderCount = 0;
      _missingRequiredCount = 0;
      _duplicateCount = 0;
    });

    final headers = rows.first
        .map((e) => e.toString().trim().toLowerCase())
        .toList();

    final Map<String, String> headerMap = {
      'full name': 'name',
      'contact number': 'phone',
      'company no': 'phone',
      'email address': 'email',
      'father name/husband name': 'fatherName',
      'father name': 'fatherName',
      'national id': 'nationalId',
      'professed religion': 'religion',
      'date of birth': 'dob',
      'gender': 'gender',
      'address': 'address',
      'relationship status': 'relationshipStatus',
      'job position': 'position',
      'employee type': 'type1',
      'work model': 'type2',
      'experience level': 'experienceLevel',
      'education': 'education',
      'salary type': 'salaryType',
      'salary amount': 'salaryAmount',
      'leave policy': 'leavePolicy',
      'annual leaves': 'annualLeaves',
      'sick leaves': 'sickLeaves',
      'casual leaves': 'casualLeaves',
      'joining date': 'joiningDate',
      'profile image url': 'profileImage',
      'profile image': 'profileImage',
      'profile pic': 'profileImage',
      'image url': 'profileImage',
      'front id image url': 'frontId',
      'front id': 'frontId',
      'back id image url': 'backId',
      'back id': 'backId',
      'cv url': 'cv',
      'cv': 'cv',
      'currency': 'currency',
    };



    Set<String> foundFields = {};
    for (var h in headers) {
      final m = headerMap[h] ?? h;
      if (_requiredFields.contains(m)) foundFields.add(m);
    }

    final missingFields = _requiredFields
        .where((f) => !foundFields.contains(f))
        .toList();


    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    Set<String> existingEmails = {};
    Set<String> existingNames = {};
    Set<String> existingNationalIds = {};
    Set<String> existingFrontIds = {};
    Set<String> existingBackIds = {};

    if (isGuest) {
      existingEmails = DummyData.workers
          .map((w) => WorkerIdentity.normalizeEmail(w['email']))
          .where((e) => e.isNotEmpty)
          .toSet();
      existingNames = DummyData.workers
          .map((w) => WorkerIdentity.normalizeName(w['name']))
          .where((n) => n.isNotEmpty)
          .toSet();
      existingNationalIds = DummyData.workers
          .map((w) => WorkerIdentity.normalizeNationalId(w['nationalId']))
          .where((n) => n.isNotEmpty)
          .toSet();
      existingFrontIds = DummyData.workers
          .map((w) => WorkerIdentity.normalizeDocumentUrl(w['frontId']))
          .where((url) => url.isNotEmpty)
          .toSet();
      existingBackIds = DummyData.workers
          .map((w) => WorkerIdentity.normalizeDocumentUrl(w['backId']))
          .where((url) => url.isNotEmpty)
          .toSet();
    } else {
      try {
        final snapshot = await FirestoreService().getWorkersOnce();
        existingEmails = snapshot.docs
            .map(
              (d) => WorkerIdentity.normalizeEmail(
                (d.data() as Map<String, dynamic>)['email'],
              ),
            )
            .where((e) => e.isNotEmpty)
            .toSet();
        existingNames = snapshot.docs
            .map(
              (d) => WorkerIdentity.normalizeName(
                (d.data() as Map<String, dynamic>)['name'],
              ),
            )
            .where((n) => n.isNotEmpty)
            .toSet();
        existingNationalIds = snapshot.docs
            .map(
              (d) => WorkerIdentity.normalizeNationalId(
                (d.data() as Map<String, dynamic>)['nationalId'],
              ),
            )
            .where((n) => n.isNotEmpty)
            .toSet();
        existingFrontIds = snapshot.docs
            .map(
              (d) => WorkerIdentity.normalizeDocumentUrl(
                (d.data() as Map<String, dynamic>)['frontId'],
              ),
            )
            .where((url) => url.isNotEmpty)
            .toSet();
        existingBackIds = snapshot.docs
            .map(
              (d) => WorkerIdentity.normalizeDocumentUrl(
                (d.data() as Map<String, dynamic>)['backId'],
              ),
            )
            .where((url) => url.isNotEmpty)
            .toSet();
      } catch (_) {
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'could_not_validate_csv_duplicates'.tr(),
            isError: true,
          );
        }
        return;
      }
    }

    if (!mounted) return;

    List<Map<String, dynamic>> parsedWorkers = [];
    Set<String> csvEmails = {};
    Set<String> csvNames = {};
    Set<String> csvNationalIds = {};
    Set<String> csvFrontIds = {};
    Set<String> csvBackIds = {};

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty ||
          row.every((element) => element.toString().trim().isEmpty)) {
        continue;
      }

      Map<String, dynamic> workerData = {
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
        'salaryType': '',
        'currency': '',
        'salaryAmount': '',
        'leavePolicy': '',
        'annualLeaves': '',
        'sickLeaves': '',
        'casualLeaves': '',
        'joiningDate': '',
        'profileImage': '',
        'frontId': '',
        'backId': '',
        'cv': '',
      };

      for (int j = 0; j < headers.length && j < row.length; j++) {
        final rawKey = headers[j];
        final val = row[j].toString().trim();
        if (val.isNotEmpty) {
          final mappedKey = headerMap[rawKey] ?? rawKey;
          String matchedKey = mappedKey;
          for (final existingKey in workerData.keys) {
            if (existingKey.toLowerCase() == mappedKey.toLowerCase()) {
              matchedKey = existingKey;
              break;
            }
          }
          workerData[matchedKey] = val;
        }
      }

      final fieldErrors = <String, String>{};
      final missingForWorker = _requiredFields.where((field) {
        return workerData[field] == null ||
            workerData[field].toString().trim().isEmpty;
      }).toList();
      for (final field in missingForWorker) {
        fieldErrors[field] = 'Required';
      }
      if (missingForWorker.isNotEmpty) _missingRequiredCount++;

      final currency = (workerData['currency'] ?? '').toString().trim();
      if (currency.isNotEmpty) {
        if (!CurrencyUtils.isSupported(currency)) {
          fieldErrors['currency'] = 'invalid_currency_value'.tr();
        } else {
          workerData['currency'] = CurrencyUtils.normalize(currency);
        }
      }


      final dobStr = (workerData['dob'] ?? '').toString().trim();
      if (dobStr.isNotEmpty) {
        final dob = AppDateUtils.parseDateString(dobStr);
        if (dob == null) {
          fieldErrors['dob'] = 'Invalid date';
          _invalidDobCount++;
        } else {
          final cutoff = DateTime.now().subtract(
            const Duration(days: 365 * 18),
          );
          if (dob.isAfter(cutoff)) {
            fieldErrors['dob'] = 'Worker must be at least 18';
            _invalidDobCount++;
          }
        }
      }


      final gender = workerData['gender']?.toString().trim() ?? '';
      final normalizedGender = gender.toLowerCase();
      if (gender.isNotEmpty &&
          normalizedGender != 'male' &&
          normalizedGender != 'female' &&
          normalizedGender != 'other' &&
          normalizedGender != 'others') {
        fieldErrors['gender'] = 'Only Male, Female, or Other is allowed';
        _invalidGenderCount++;
      } else if (normalizedGender == 'others') {
        workerData['gender'] = 'Other';
      }


      final email = WorkerIdentity.normalizeEmail(workerData['email']);
      if (email.isNotEmpty &&
          !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
        fieldErrors['email'] = 'Invalid email address';
      }

      final name = WorkerIdentity.normalizeName(workerData['name']);
      final nationalId = WorkerIdentity.normalizeNationalId(
        workerData['nationalId'],
      );
      final frontId = WorkerIdentity.normalizeDocumentUrl(
        workerData['frontId'],
      );
      final backId = WorkerIdentity.normalizeDocumentUrl(workerData['backId']);

      if (name.isNotEmpty &&
          (existingNames.contains(name) || csvNames.contains(name))) {
        fieldErrors['name'] = 'Duplicate worker name';
      }
      if (email.isNotEmpty &&
          (existingEmails.contains(email) || csvEmails.contains(email))) {
        fieldErrors['email'] = 'Duplicate email address';
      }
      if (nationalId.isNotEmpty &&
          (existingNationalIds.contains(nationalId) ||
              csvNationalIds.contains(nationalId))) {
        fieldErrors['nationalId'] = 'Duplicate National ID';
      }
      if (frontId.isNotEmpty &&
          (existingFrontIds.contains(frontId) ||
              existingBackIds.contains(frontId) ||
              csvFrontIds.contains(frontId) ||
              csvBackIds.contains(frontId))) {
        fieldErrors['frontId'] = 'Duplicate front ID card image';
      }
      if (backId.isNotEmpty &&
          (backId == frontId ||
              existingFrontIds.contains(backId) ||
              existingBackIds.contains(backId) ||
              csvFrontIds.contains(backId) ||
              csvBackIds.contains(backId))) {
        fieldErrors['backId'] = 'Duplicate back ID card image';
      }

      if (fieldErrors.values.any((reason) => reason.startsWith('Duplicate'))) {
        _duplicateCount++;
      }

      if (email.isNotEmpty) csvEmails.add(email);
      if (name.isNotEmpty) csvNames.add(name);
      if (nationalId.isNotEmpty) csvNationalIds.add(nationalId);
      if (frontId.isNotEmpty) csvFrontIds.add(frontId);
      if (backId.isNotEmpty) csvBackIds.add(backId);

      workerData['availableAnnualLeaves'] =
          int.tryParse(workerData['annualLeaves']?.toString() ?? '0') ?? 0;
      workerData['availableCasualLeaves'] =
          int.tryParse(workerData['casualLeaves']?.toString() ?? '0') ?? 0;
      workerData['availableSickLeaves'] =
          int.tryParse(workerData['sickLeaves']?.toString() ?? '0') ?? 0;

      workerData['_rowNumber'] = i + 1;
      workerData['_fieldErrors'] = fieldErrors;

      parsedWorkers.add(workerData);
    }

    setState(() {
      _validWorkers = parsedWorkers;
      _hasParsedFile = true;
    });

    if (!mounted) return;

    // Collect unique field names that are EMPTY across any worker (only "Required" errors)
    final Set<String> allMissingFieldNames = {};
    for (final worker in parsedWorkers) {
      final errors = _fieldErrors(worker);
      for (final entry in errors.entries) {
        if (entry.value == 'Required') {
          allMissingFieldNames.add(entry.key);
        }
      }
    }

    final int duplicateWorkers = parsedWorkers.where((w) {
      final errors = _fieldErrors(w);
      return errors.values.any((r) => r.startsWith('Duplicate'));
    }).length;

    final bool hasAnyIssue = allMissingFieldNames.isNotEmpty ||
        missingFields.isNotEmpty ||
        duplicateWorkers > 0;

    if (hasAnyIssue) {
      final snackParts = <String>[];

      // Line 1: total workers found
      snackParts.add(
        '${parsedWorkers.length} worker(s) found in CSV',
      );

      // Line 2: entire columns missing from the CSV header
      if (missingFields.isNotEmpty) {
        final colNames = missingFields
            .map((f) => _fieldLabels[f] ?? f)
            .join(', ');
        snackParts.add('⚠ Missing columns: $colNames');
      }

      // Line 3: fields that are empty/blank in some rows (grouped by field name)
      if (allMissingFieldNames.isNotEmpty) {
        final fieldNames = allMissingFieldNames
            .map((f) => _fieldLabels[f] ?? f)
            .join(', ');
        snackParts.add('❌ Empty fields found: $fieldNames');
      }

      // Line 4: duplicate workers
      if (duplicateWorkers > 0) {
        snackParts.add(
          '🔁 $duplicateWorkers duplicate(s) — same Email or National ID already exists',
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
  }

  Future<void> _saveBulkWorkers() async {
    if (_validWorkers.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'no_valid_workers_found_in_csv'.tr(),
        isError: true,
      );
      return;
    }

    final workersWithErrors = _validWorkers.where(_hasWorkerErrors).toList();
    final workersReadyToSave = _workersReadyToSave;

    if (workersReadyToSave.isEmpty) {
      // All workers have errors — nothing to upload
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
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'csv_validation_errors_found'.tr(
            namedArgs: {'errors': parts.join('\n')},
          ),
          isError: true,
          displayDuration: const Duration(seconds: 10),
        );
      }
      return;
    }

    // Count how many are skipped due to errors
    int localDuplicateCount = 0;
    int localMissingCount = 0;
    int localInvalidDobCount = 0;
    int localInvalidGenderCount = 0;
    for (final w in workersWithErrors) {
      final errors = _fieldErrors(w);
      if (errors.values.any((r) => r.startsWith('Duplicate'))) {
        localDuplicateCount++;
      } else {
        if (errors.containsKey('dob')) localInvalidDobCount++;
        if (errors.containsKey('gender')) localInvalidGenderCount++;
        localMissingCount++;
      }
    }

    setState(() {
      _isSaving = true;
    });

    final isGuest = AuthService().currentUser?.isAnonymous ?? false;

    _showBulkProgressDialog();

    try {
      var importedCount = workersReadyToSave.length;
      int finalSkippedDuplicates = localDuplicateCount;
      if (isGuest) {
        for (var i = 0; i < workersReadyToSave.length; i++) {
          final data = workersReadyToSave[i];
          final newId = 'dummy_${DateTime.now().microsecondsSinceEpoch}_$i';
          DummyData.workers.insert(0, {...data, 'id': newId});
        }
        await DummyData.saveToPrefs();
      } else {
        final result = await FirestoreService().addBulkWorkers(workersReadyToSave);
        importedCount = result.imported;
        if (result.skipped > 0) {
          finalSkippedDuplicates += result.skipped;
        }
      }

      if (mounted) {
        Navigator.of(context).pop();

        // Build detailed result message
        final summaryParts = <String>[];
        summaryParts.add(
          'workers_added_successfully'.tr(
            namedArgs: {'count': importedCount.toString()},
          ),
        );
        if (finalSkippedDuplicates > 0) {
          summaryParts.add(
            'skipped_duplicates_message'.tr(
              namedArgs: {'count': finalSkippedDuplicates.toString()},
            ),
          );
        }
        if (localMissingCount > 0 || localInvalidDobCount > 0 || localInvalidGenderCount > 0) {
          final errorParts = <String>[];
          if (localMissingCount > 0) {
            errorParts.add(
              'skipped_missing_required_message'.tr(
                namedArgs: {'count': localMissingCount.toString()},
              ),
            );
          }
          if (localInvalidDobCount > 0) {
            errorParts.add(
              'skipped_invalid_dob_message'.tr(
                namedArgs: {'count': localInvalidDobCount.toString()},
              ),
            );
          }
          if (localInvalidGenderCount > 0) {
            errorParts.add(
              'skipped_invalid_gender_message'.tr(
                namedArgs: {'count': localInvalidGenderCount.toString()},
              ),
            );
          }
          summaryParts.addAll(errorParts);
        }

        final hasSkipped = finalSkippedDuplicates > 0 ||
            localMissingCount > 0 ||
            localInvalidDobCount > 0 ||
            localInvalidGenderCount > 0;

        FlashySnackBar.show(
          context,
          title: importedCount > 0
              ? 'csv_uploaded_title'.tr()
              : 'csv_uploaded_with_issues_title'.tr(),
          message: summaryParts.join('\n'),
          isError: hasSkipped && importedCount == 0,
          maxLines: null,
          displayDuration: hasSkipped
              ? const Duration(seconds: 10)
              : const Duration(seconds: 5),
        );

        final dialogShown = await tryShowFirstMilestoneRateUs(
          context,
          'bulk_worker',
        );
        if (isGuest) {
          setState(() {
            _validWorkers = [];
            _hasParsedFile = false;
          });
          DummyData.loadFromPrefs();
        } else {
          setState(() {
            _validWorkers = [];
            _hasParsedFile = false;
          });
          FirestoreService().workersStream.listen((snapshot) {
            if (mounted) {
              setState(() {});
            }
          });
        }

        if (!dialogShown && mounted) {
          widget.onBack?.call();
        }
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'could_not_save_worker'.tr(),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showBulkProgressDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
                      onTap: () => widget.onBack?.call(),
                      child: const Padding(
                        padding: EdgeInsets.all(8.0),
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
                if (_hasParsedFile)
                  Builder(
                    builder: (context) {
                      // canSave = true when at least one worker has no errors
                      final bool hasAnyValidWorker =
                          _validWorkers.any((w) => !_hasWorkerErrors(w));
                      final bool canSave =
                          hasAnyValidWorker && !_isSaving;

                      return GestureDetector(
                        onTap: canSave ? _saveBulkWorkers : null,
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          decoration: BoxDecoration(
                            color: canSave
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
                                  'save_all'.tr(),
                                  style: TextStyle(
                                    color: canSave
                                        ? const Color(0xFFFFFFFF)
                                        : const Color(0xFF000000),
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
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  if (_hasParsedFile) ...[

                    Container(
                      padding: const EdgeInsets.all(20),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEBF5FF), Color(0xFFF3F9FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFD0E5FF),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF000000,
                            ).withValues(alpha: 0.02),
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
                                  (_validWorkers.any(_hasWorkerErrors)
                                          ? const Color(0xFFEF4444)
                                          : const Color(0xFF34D399))
                                      .withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _validWorkers.any(_hasWorkerErrors)
                                  ? Icons.error_outline_rounded
                                  : Icons.check_circle_rounded,
                              color: _validWorkers.any(_hasWorkerErrors)
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
                                    'errors': _validWorkers
                                        .where(_hasWorkerErrors)
                                        .length
                                        .toString(),
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
                                (_validWorkers.any(_hasWorkerErrors)
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
                    ),

                    Builder(
                      builder: (context) {
                        // Shared controller so header and rows scroll together horizontally
                        final hScroll = ScrollController();

                        const double rowH = 65.0;
                        const double tableContentWidth = 3978;
                        final int count = _validWorkers.length;
                        // show at most 600px of rows (≈9 rows); grows up to 70% of screen
                        final double listH = (rowH * count)
                            .clamp(0.0, MediaQuery.of(context).size.height * 0.70);

                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFE2E8F0),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF000000).withValues(alpha: 0.03),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── Sticky header (synced with body scroll) ──
                              SingleChildScrollView(
                                controller: hScroll,
                                scrollDirection: Axis.horizontal,
                                physics: const NeverScrollableScrollPhysics(),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: MediaQuery.of(context).size.width - 80,
                                      maxWidth: tableContentWidth,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 16,
                                      ),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.only(
                                          topLeft: Radius.circular(12),
                                          topRight: Radius.circular(12),
                                        ),
                                        border: Border(
                                          bottom: BorderSide(
                                            color: Color(0xFFE2E8F0),
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          _buildHeaderCell('full_name'.tr(), 200),
                                        _buildHeaderCell('contact_number'.tr(), 120),
                                        _buildHeaderCell('email_address'.tr(), 200),
                                        _buildHeaderCell('job_position'.tr(), 150),
                                        _buildHeaderCell('salary_type'.tr(), 120),
                                        _buildHeaderCell('currency_title'.tr(), 100),
                                        _buildHeaderCell('salary_amount'.tr(), 120),
                                        _buildHeaderCell('father_name'.tr(), 150),
                                        _buildHeaderCell('national_id_title'.tr(), 150),
                                        _buildHeaderCell('religion_title'.tr(), 120),
                                        _buildHeaderCell('date_of_birth'.tr(), 120),
                                        _buildHeaderCell('gender_title'.tr(), 100),
                                        _buildHeaderCell('address_title'.tr(), 250),
                                        _buildHeaderCell('relationship_status_title'.tr(), 140),
                                        _buildHeaderCell('employee_type'.tr(), 120),
                                        _buildHeaderCell('work_model'.tr(), 120),
                                        _buildHeaderCell('experience_level_title'.tr(), 130),
                                        _buildHeaderCell('education_title'.tr(), 150),
                                        _buildHeaderCell('leave_policy'.tr(), 120),
                                        _buildHeaderCell('annual_leaves_title'.tr(), 100),
                                        _buildHeaderCell('sick_leaves_title'.tr(), 100),
                                        _buildHeaderCell('casual_leaves_title'.tr(), 100),
                                        _buildHeaderCell('joining_date_title'.tr(), 150),
                                        _buildHeaderCell('profile_image_url'.tr(), 200),
                                        _buildHeaderCell('front_id_image_url'.tr(), 200),
                                        _buildHeaderCell('back_id_image_url'.tr(), 200),
                                        _buildHeaderCell('cv_url'.tr(), 200),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              // ── Virtualized rows ──
                              SizedBox(
                                height: listH,
                                child: Scrollbar(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    controller: hScroll,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minWidth: MediaQuery.of(context).size.width - 80,
                                        maxWidth: tableContentWidth,
                                      ),
                                      child: ListView.builder(
                                        itemCount: count,
                                        itemExtent: rowH,
                                        itemBuilder: (ctx, index) {
                                          final worker = _validWorkers[index];
                                          return RepaintBoundary(
                                            child: _buildWorkerRow(worker, index),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerRow(Map<String, dynamic> worker, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: index.isEven
          ? const BoxDecoration(color: Color(0xFFFAFBFC))
          : null,
      child: Row(
        children: [
          _buildDataCell(worker['name']?.toString() ?? '', 200,
              hasError: _hasFieldError(worker, 'name'),
              isBold: true),
          _buildDataCell(worker['phone']?.toString() ?? '', 120,
              hasError: _hasFieldError(worker, 'phone')),
          _buildDataCell(worker['email']?.toString() ?? '', 200,
              hasError: _hasFieldError(worker, 'email')),
          _buildDataCell(worker['position']?.toString() ?? '', 150,
              hasError: _hasFieldError(worker, 'position')),
          _buildDataCell(worker['salaryType']?.toString() ?? '', 120,
              hasError: _hasFieldError(worker, 'salaryType')),
          _buildDataCell(worker['currency']?.toString() ?? '', 100,
              hasError: _hasFieldError(worker, 'currency')),
          _buildDataCell(worker['salaryAmount']?.toString() ?? '', 120,
              hasError: _hasFieldError(worker, 'salaryAmount')),
          _buildDataCell(worker['fatherName']?.toString() ?? '', 150,
              hasError: _hasFieldError(worker, 'fatherName')),
          _buildDataCell(worker['nationalId']?.toString() ?? '', 150,
              hasError: _hasFieldError(worker, 'nationalId')),
          _buildDataCell(worker['religion']?.toString() ?? '', 120,
              hasError: _hasFieldError(worker, 'religion')),
          _buildDataCell(worker['dob']?.toString() ?? '', 120,
              hasError: _hasFieldError(worker, 'dob')),
          _buildDataCell(worker['gender']?.toString() ?? '', 100,
              hasError: _hasFieldError(worker, 'gender')),
          _buildDataCell(worker['address']?.toString() ?? '', 250,
              hasError: _hasFieldError(worker, 'address')),
          _buildDataCell(worker['relationshipStatus']?.toString() ?? '', 140,
              hasError: _hasFieldError(worker, 'relationshipStatus')),
          _buildDataCell(worker['type1']?.toString() ?? '', 120,
              hasError: _hasFieldError(worker, 'type1')),
          _buildDataCell(worker['type2']?.toString() ?? '', 120,
              hasError: _hasFieldError(worker, 'type2')),
          _buildDataCell(worker['experienceLevel']?.toString() ?? '', 130,
              hasError: _hasFieldError(worker, 'experienceLevel')),
          _buildDataCell(worker['education']?.toString() ?? '', 150,
              hasError: _hasFieldError(worker, 'education')),
          _buildDataCell(worker['leavePolicy']?.toString() ?? '', 120,
              hasError: _hasFieldError(worker, 'leavePolicy')),
          _buildDataCell(worker['annualLeaves']?.toString() ?? '', 100,
              hasError: _hasFieldError(worker, 'annualLeaves')),
          _buildDataCell(worker['sickLeaves']?.toString() ?? '', 100,
              hasError: _hasFieldError(worker, 'sickLeaves')),
          _buildDataCell(worker['casualLeaves']?.toString() ?? '', 100,
              hasError: _hasFieldError(worker, 'casualLeaves')),
          _buildDataCell(worker['joiningDate']?.toString() ?? '', 150,
              hasError: _hasFieldError(worker, 'joiningDate')),
          _buildDataCell(worker['profileImage']?.toString() ?? '', 200,
              hasError: _hasFieldError(worker, 'profileImage')),
          _buildDataCell(worker['frontId']?.toString() ?? '', 200,
              hasError: _hasFieldError(worker, 'frontId')),
          _buildDataCell(worker['backId']?.toString() ?? '', 200,
              hasError: _hasFieldError(worker, 'backId')),
          _buildDataCell(worker['cv']?.toString() ?? '', 200,
              hasError: _hasFieldError(worker, 'cv')),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, double width) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: Color(0xFF475569),
          fontFamily: 'SF Pro Display',
        ),
      ),
    );
  }

  BoxDecoration? _fieldDecoration(bool hasError) => hasError
      ? BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFEF4444)),
        )
      : null;

  Widget _buildDataCell(
    String text,
    double width, {
    bool isBold = false,
    bool hasError = false,
  }) {
    final displayText = hasError && (text.isEmpty || text == '-')
        ? 'required_field'.tr()
        : (text.isEmpty ? '-' : text);
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: _fieldDecoration(hasError),
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
    );
  }
}
