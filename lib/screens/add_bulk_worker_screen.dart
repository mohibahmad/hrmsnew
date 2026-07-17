import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' as io;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:open_file_plus/open_file_plus.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../utils/localization_helper.dart';
import '../utils/snackbar_utils.dart';
import '../utils/date_utils.dart';
import '../utils/rate_us_helper.dart';
import '../widgets/amount_text.dart';

class AddBulkWorkerScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const AddBulkWorkerScreen({super.key, this.onBack});

  @override
  State<AddBulkWorkerScreen> createState() => _AddBulkWorkerScreenState();
}

class _AddBulkWorkerScreenState extends State<AddBulkWorkerScreen> {
  bool _isSaving = false;
  List<Map<String, dynamic>> _validWorkers = [];
  bool _hasParsedFile = false;
  int _invalidDobCount = 0;
  int _invalidGenderCount = 0;
  int _missingRequiredCount = 0;
  int _duplicateCount = 0;
  String? _lastFileHash;

  @override
  void initState() {
    super.initState();
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

      final fileHash = bytes.hashCode.toString();
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

      // BOM strip + UTF-8 safe + normalize line endings
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

    // Check ALL required columns
    final requiredFields = [
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
      'profileImage',
      'frontId',
      'backId',
      'cv',
    ];
    Set<String> foundFields = {};
    for (var h in headers) {
      final m = headerMap[h] ?? h;
      if (requiredFields.contains(m)) foundFields.add(m);
    }

    final missingFields = requiredFields
        .where((f) => !foundFields.contains(f))
        .toList();
    if (missingFields.isNotEmpty) {
      FlashySnackBar.show(
        context,
        message: 'csv_required_columns_error'.tr(),
        isError: true,
      );
      return;
    }

    // Fetch existing names and emails
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    Set<String> existingEmails = {};
    Set<String> existingNames = {};

    if (isGuest) {
      existingEmails = DummyData.workers
          .map((w) => w['email']?.toString().toLowerCase().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toSet();
      existingNames = DummyData.workers
          .map((w) => w['name']?.toString().toLowerCase().trim() ?? '')
          .where((n) => n.isNotEmpty)
          .toSet();
    } else {
      try {
        final snapshot = await FirestoreService().getWorkersOnce();
        existingEmails = snapshot.docs
            .map(
              (d) =>
                  (d.data() as Map<String, dynamic>)['email']
                      ?.toString()
                      .toLowerCase()
                      .trim() ??
                  '',
            )
            .where((e) => e.isNotEmpty)
            .toSet();
        existingNames = snapshot.docs
            .map(
              (d) =>
                  (d.data() as Map<String, dynamic>)['name']
                      ?.toString()
                      .toLowerCase()
                      .trim() ??
                  '',
            )
            .where((n) => n.isNotEmpty)
            .toSet();
      } catch (e) {}
    }

    if (!mounted) return;

    List<Map<String, dynamic>> parsedWorkers = [];
    Set<String> csvEmails = {};
    Set<String> csvNames = {};

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty ||
          row.every((element) => element.toString().trim().isEmpty))
        continue;

      Map<String, dynamic> workerData = {
        'name': '',
        'phone': '',
        'fatherName': '',
        'email': '',
        'nationalId': '',
        'religion': '',
        'dob': '',
        'gender': 'Male',
        'address': '',
        'relationshipStatus': 'Single',
        'type1': 'Full-Time',
        'position': 'Employee',
        'type2': 'On-Site',
        'experienceLevel': 'Mid-Level',
        'education': 'Bachelor\'s',
        'salaryType': 'Monthly',
        'currency': 'USD',
        'salaryAmount': '',
        'leavePolicy': 'Standard',
        'annualLeaves': '',
        'sickLeaves': '',
        'casualLeaves': '',
        'joiningDate':
            '${DateTime.now().month}/${DateTime.now().day}/${DateTime.now().year}',
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

      // Ensure ALL required fields are filled
      bool hasEmptyRequired = false;
      String emptyFieldName = '';
      for (var field in requiredFields) {
        if (workerData[field] == null ||
            workerData[field].toString().trim().isEmpty) {
          hasEmptyRequired = true;
          emptyFieldName = field;
          break;
        }
      }
      if (hasEmptyRequired) {
        _missingRequiredCount++;
        final workerName =
            workerData['name']?.toString().trim() ?? 'Row ${i + 1}';
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'field_missing_for_worker'.tr(
              namedArgs: {'field': emptyFieldName, 'name': workerName},
            ),
            isError: true,
          );
        }
        continue;
      }

      // Validate DOB - must be 18+
      final dobStr = (workerData['dob'] ?? '').toString().trim();
      final dob = AppDateUtils.parseDateString(dobStr);
      final workerName =
          workerData['name']?.toString().trim() ?? 'Row ${i + 1}';
      if (dob == null) {
        _invalidDobCount++;
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'invalid_dob_for_worker'.tr(
              namedArgs: {'name': workerName, 'value': dobStr},
            ),
            isError: true,
          );
        }
        continue;
      }
      final cutoff = DateTime.now().subtract(const Duration(days: 365 * 18));
      if (dob.isAfter(cutoff)) {
        _invalidDobCount++;
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'worker_too_young'.tr(namedArgs: {'name': workerName}),
            isError: true,
          );
        }
        continue;
      }

      // Validate gender - only Male or Female allowed
      final gender = workerData['gender']?.toString().trim() ?? '';
      if (!gender.toLowerCase().contains('male') &&
          !gender.toLowerCase().contains('female')) {
        _invalidGenderCount++;
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'invalid_gender_for_worker'.tr(
              namedArgs: {'name': workerName, 'value': gender},
            ),
            isError: true,
          );
        }
        continue;
      }

      // Validate email format
      final email = workerData['email']?.toString().toLowerCase().trim() ?? '';
      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
        _missingRequiredCount++;
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'invalid_email_for_worker'.tr(
              namedArgs: {'name': workerName, 'email': email},
            ),
            isError: true,
          );
        }
        continue;
      }

      final name = workerData['name']?.toString().toLowerCase().trim() ?? '';

      bool isDuplicate = false;
      if (email.isNotEmpty &&
          (existingEmails.contains(email) || csvEmails.contains(email))) {
        isDuplicate = true;
      } else if (email.isEmpty &&
          name.isNotEmpty &&
          (existingNames.contains(name) || csvNames.contains(name))) {
        isDuplicate = true;
      }

      if (isDuplicate) {
        _duplicateCount++;
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'duplicate_worker_skipped'.tr(
              namedArgs: {'name': name.isNotEmpty ? name : email},
            ),
            isError: true,
          );
        }
        continue;
      }

      if (email.isNotEmpty) csvEmails.add(email);
      if (name.isNotEmpty) csvNames.add(name);

      workerData['availableAnnualLeaves'] =
          int.tryParse(workerData['annualLeaves']?.toString() ?? '0') ?? 0;
      workerData['availableCasualLeaves'] =
          int.tryParse(workerData['casualLeaves']?.toString() ?? '0') ?? 0;
      workerData['availableSickLeaves'] =
          int.tryParse(workerData['sickLeaves']?.toString() ?? '0') ?? 0;

      parsedWorkers.add(workerData);
    }

    if (_duplicateCount > 0 && mounted) {
      FlashySnackBar.show(
        context,
        message: 'skipped_duplicates_message'.tr(
          namedArgs: {'count': _duplicateCount.toString()},
        ),
      );
    }
    if (_invalidDobCount > 0 && mounted) {
      FlashySnackBar.show(
        context,
        message: 'skipped_invalid_dob_message'.tr(
          namedArgs: {'count': _invalidDobCount.toString()},
        ),
      );
    }
    if (_invalidGenderCount > 0 && mounted) {
      FlashySnackBar.show(
        context,
        message: 'skipped_invalid_gender_message'.tr(
          namedArgs: {'count': _invalidGenderCount.toString()},
        ),
      );
    }
    if (_missingRequiredCount > 0 && mounted) {
      FlashySnackBar.show(
        context,
        message: 'skipped_missing_required_message'.tr(
          namedArgs: {'count': _missingRequiredCount.toString()},
        ),
      );
    }

    setState(() {
      _validWorkers = parsedWorkers;
      _hasParsedFile = true;
    });
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

    final hasValidationErrors =
        _missingRequiredCount > 0 ||
        _invalidDobCount > 0 ||
        _invalidGenderCount > 0 ||
        _duplicateCount > 0;

    if (hasValidationErrors) {
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
        );
      }
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final isGuest = AuthService().currentUser?.isAnonymous ?? false;

    _showBulkProgressDialog();

    try {
      if (isGuest) {
        for (var i = 0; i < _validWorkers.length; i++) {
          final data = _validWorkers[i];
          final newId = 'dummy_${DateTime.now().microsecondsSinceEpoch}_$i';
          DummyData.workers.insert(0, {...data, 'id': newId});
        }
        await DummyData.saveToPrefs();
      } else {
        await FirestoreService().addBulkWorkers(_validWorkers);
      }

      if (mounted) {
        Navigator.of(context).pop();
        FlashySnackBar.show(
          context,
          message: 'workers_added_successfully'.tr(
            namedArgs: {'count': _validWorkers.length.toString()},
          ),
        );
        tryShowFirstMilestoneRateUs(context, 'bulk_worker');

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

        widget.onBack?.call();
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
                Builder(
                  builder: (context) {
                    final bool isSaveReady = _validWorkers.isNotEmpty;
                    final bool hasValidationErrors =
                        _missingRequiredCount > 0 ||
                        _invalidDobCount > 0 ||
                        _invalidGenderCount > 0 ||
                        _duplicateCount > 0;
                    final bool canSave =
                        isSaveReady && !_isSaving && !hasValidationErrors;

                    return GestureDetector(
                      onTap: canSave ? _saveBulkWorkers : null,
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
                                'save_all'.tr(),
                                style: TextStyle(
                                  color: isSaveReady
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

          // Main Content
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
                    // Preview Header Card
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
                              color: const Color(
                                0xFF34D399,
                              ).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF059669),
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'preview_valid_workers_found'.tr(
                                  namedArgs: {
                                    'count': _validWorkers.length.toString(),
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
                                'review_details_save_all'.tr(),
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
                    // Custom Premium Table
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFE2E8F0),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF000000,
                            ).withValues(alpha: 0.03),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: MediaQuery.of(context).size.width - 80,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Table Header
                              Container(
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
                                    _buildHeaderCell(
                                      'contact_number'.tr(),
                                      120,
                                    ),
                                    _buildHeaderCell('email_address'.tr(), 200),
                                    _buildHeaderCell('job_position'.tr(), 150),
                                    _buildHeaderCell('salary_type'.tr(), 120),
                                    _buildHeaderCell(
                                      'currency_title'.tr(),
                                      100,
                                    ),
                                    _buildHeaderCell('salary_amount'.tr(), 120),
                                    _buildHeaderCell('father_name'.tr(), 150),
                                    _buildHeaderCell(
                                      'national_id_title'.tr(),
                                      150,
                                    ),
                                    _buildHeaderCell(
                                      'religion_title'.tr(),
                                      120,
                                    ),
                                    _buildHeaderCell('date_of_birth'.tr(), 120),
                                    _buildHeaderCell('gender_title'.tr(), 100),
                                    _buildHeaderCell('address_title'.tr(), 250),
                                    _buildHeaderCell(
                                      'relationship_status_title'.tr(),
                                      140,
                                    ),
                                    _buildHeaderCell('employee_type'.tr(), 120),
                                    _buildHeaderCell('work_model'.tr(), 120),
                                    _buildHeaderCell(
                                      'experience_level_title'.tr(),
                                      130,
                                    ),
                                    _buildHeaderCell(
                                      'education_title'.tr(),
                                      150,
                                    ),
                                    _buildHeaderCell('leave_policy'.tr(), 120),
                                    _buildHeaderCell(
                                      'annual_leaves_title'.tr(),
                                      100,
                                    ),
                                    _buildHeaderCell(
                                      'sick_leaves_title'.tr(),
                                      100,
                                    ),
                                    _buildHeaderCell(
                                      'casual_leaves_title'.tr(),
                                      100,
                                    ),
                                    _buildHeaderCell(
                                      'joining_date_title'.tr(),
                                      150,
                                    ),
                                    _buildHeaderCell(
                                      'profile_image_url'.tr(),
                                      200,
                                    ),
                                    _buildHeaderCell(
                                      'front_id_image_url'.tr(),
                                      200,
                                    ),
                                    _buildHeaderCell(
                                      'back_id_image_url'.tr(),
                                      200,
                                    ),
                                    _buildHeaderCell('cv_url'.tr(), 200),
                                  ],
                                ),
                              ),
                              // Table Body
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _validWorkers.asMap().entries.map((
                                  entry,
                                ) {
                                  final index = entry.key;
                                  final worker = entry.value;
                                  final name = worker['name']?.toString() ?? '';
                                  final phone =
                                      worker['phone']?.toString() ?? '';
                                  final email =
                                      worker['email']?.toString() ?? '';
                                  final position =
                                      worker['position']?.toString() ?? '';
                                  final rawSalary =
                                      worker['salaryAmount']?.toString() ?? '';
                                  final salary = rawSalary.isNotEmpty
                                      ? AmountText.formatCompact(rawSalary)
                                      : '';
                                  final profileImageUrl =
                                      worker['profileImage']?.toString() ?? '';

                                  // Generate clean initials for Avatar
                                  String initials = '';
                                  if (name.isNotEmpty) {
                                    final parts = name.split(' ');
                                    if (parts.isNotEmpty) {
                                      initials = parts.first[0].toUpperCase();
                                      if (parts.length > 1) {
                                        initials += parts[1][0].toUpperCase();
                                      }
                                    }
                                  }

                                  // Soft colors for initials background
                                  final List<Color> bgColors = [
                                    const Color(0xFFEFF6FF),
                                    const Color(0xFFECFDF5),
                                    const Color(0xFFFDF2F8),
                                    const Color(0xFFFFF7ED),
                                  ];
                                  final List<Color> textColors = [
                                    const Color(0xFF1D4ED8),
                                    const Color(0xFF047857),
                                    const Color(0xFFBE185D),
                                    const Color(0xFFC2410C),
                                  ];
                                  final colorIdx = index % bgColors.length;

                                  final rowWidget = Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 14,
                                    ),
                                    child: Row(
                                      children: [
                                        // Name with Avatar
                                        SizedBox(
                                          width: 200,
                                          child: Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 18,
                                                backgroundColor:
                                                    bgColors[colorIdx],
                                                backgroundImage:
                                                    profileImageUrl
                                                            .isNotEmpty &&
                                                        profileImageUrl
                                                            .startsWith('http')
                                                    ? NetworkImage(
                                                        profileImageUrl,
                                                      )
                                                    : null,
                                                child:
                                                    profileImageUrl.isEmpty ||
                                                        !profileImageUrl
                                                            .startsWith('http')
                                                    ? Text(
                                                        initials,
                                                        style: TextStyle(
                                                          color:
                                                              textColors[colorIdx],
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 13,
                                                          fontFamily:
                                                              'SF Pro Display',
                                                        ),
                                                      )
                                                    : null,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color: Color(0xFF0F172A),
                                                    fontFamily:
                                                        'SF Pro Display',
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Phone
                                        _buildDataCell(phone, 120),
                                        // Email
                                        _buildDataCell(email, 200),
                                        // Position Chip
                                        SizedBox(
                                          width: 150,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF1F5F9),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                position.isEmpty
                                                    ? 'employee_default_chip'
                                                          .tr()
                                                    : position,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF475569),
                                                  fontFamily: 'SF Pro Display',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Salary Type
                                        _buildDataCell(
                                          worker['salaryType']?.toString() ??
                                              '',
                                          120,
                                        ),
                                        // Currency
                                        _buildDataCell(
                                          worker['currency']?.toString() ?? '',
                                          100,
                                        ),
                                        // Salary Amount
                                        _buildDataCell(
                                          salary.isEmpty ? '-' : salary,
                                          120,
                                          isBold: true,
                                        ),
                                        // Additional fields
                                        _buildDataCell(
                                          worker['fatherName']?.toString() ??
                                              '',
                                          150,
                                        ),
                                        _buildDataCell(
                                          worker['nationalId']?.toString() ??
                                              '',
                                          150,
                                        ),
                                        _buildDataCell(
                                          worker['religion']?.toString() ?? '',
                                          120,
                                        ),
                                        _buildDataCell(
                                          worker['dob']?.toString() ?? '',
                                          120,
                                        ),
                                        _buildDataCell(
                                          worker['gender']?.toString() ?? '',
                                          100,
                                        ),
                                        _buildDataCell(
                                          worker['address']?.toString() ?? '',
                                          250,
                                        ),
                                        _buildDataCell(
                                          worker['relationshipStatus']
                                                  ?.toString() ??
                                              '',
                                          140,
                                        ),
                                        _buildDataCell(
                                          LocalizationHelper.localizeType1(
                                            worker['type1']?.toString() ?? '',
                                          ),
                                          120,
                                        ),
                                        _buildDataCell(
                                          LocalizationHelper.localizeType2(
                                            worker['type2']?.toString() ?? '',
                                          ),
                                          120,
                                        ),
                                        _buildDataCell(
                                          worker['experienceLevel']
                                                  ?.toString() ??
                                              '',
                                          130,
                                        ),
                                        _buildDataCell(
                                          worker['education']?.toString() ?? '',
                                          150,
                                        ),
                                        _buildDataCell(
                                          worker['leavePolicy']?.toString() ??
                                              '',
                                          120,
                                        ),
                                        _buildDataCell(
                                          worker['annualLeaves']?.toString() ??
                                              '',
                                          100,
                                        ),
                                        _buildDataCell(
                                          worker['sickLeaves']?.toString() ??
                                              '',
                                          100,
                                        ),
                                        _buildDataCell(
                                          worker['casualLeaves']?.toString() ??
                                              '',
                                          100,
                                        ),
                                        _buildDataCell(
                                          worker['joiningDate']?.toString() ??
                                              '',
                                          150,
                                        ),
                                        _buildDataCell(
                                          profileImageUrl.isEmpty
                                              ? '-'
                                              : profileImageUrl,
                                          200,
                                        ),
                                        _buildDataCell(
                                          worker['frontId']
                                                      ?.toString()
                                                      .isEmpty ==
                                                  true
                                              ? '-'
                                              : worker['frontId']?.toString() ??
                                                    '-',
                                          200,
                                        ),
                                        _buildDataCell(
                                          worker['backId']
                                                      ?.toString()
                                                      .isEmpty ==
                                                  true
                                              ? '-'
                                              : worker['backId']?.toString() ??
                                                    '-',
                                          200,
                                        ),
                                        _buildDataCell(
                                          worker['cv']?.toString().isEmpty ==
                                                  true
                                              ? '-'
                                              : worker['cv']?.toString() ?? '-',
                                          200,
                                        ),
                                      ],
                                    ),
                                  );

                                  if (index < _validWorkers.length - 1) {
                                    return Column(
                                      children: [
                                        rowWidget,
                                        const Divider(
                                          height: 1,
                                          color: Color(0xFFF1F5F9),
                                        ),
                                      ],
                                    );
                                  }

                                  return rowWidget;
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
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

  Widget _buildDataCell(String text, double width, {bool isBold = false}) {
    return SizedBox(
      width: width,
      child: Text(
        text.isEmpty ? '-' : text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: isBold ? const Color(0xFF0F172A) : const Color(0xFF334155),
          fontFamily: 'SF Pro Display',
        ),
      ),
    );
  }
}
