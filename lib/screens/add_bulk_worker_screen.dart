import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' as io;
import 'dart:ui' as ui;
import 'dart:math';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter/services.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../utils/snackbar_utils.dart';
import '../utils/rate_us_helper.dart';
import '../utils/date_utils.dart';
import '../utils/currency_utils.dart';
import '../utils/worker_identity.dart';
import '../utils/validators.dart';
import 'package:provider/provider.dart';

class AddBulkWorkerScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const AddBulkWorkerScreen({super.key, this.onBack});

  @override
  AddBulkWorkerScreenState createState() => AddBulkWorkerScreenState();
}

class AddBulkWorkerScreenState extends State<AddBulkWorkerScreen> {
  // ─────────────────────────────────────────────────────────────
  //  Constants
  // ─────────────────────────────────────────────────────────────
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
    'annualLeaves',
    'joiningDate',
    'frontId',
    'backId',
    'cv',
  ];

  static const Map<String, String> _fieldKeys = {
    'name': 'field_full_name',
    'phone': 'field_contact_number',
    'email': 'field_email_address',
    'fatherName': 'field_father_name',
    'nationalId': 'field_national_id',
    'religion': 'field_religion',
    'dob': 'field_date_of_birth',
    'gender': 'field_gender',
    'address': 'field_address',
    'relationshipStatus': 'field_relationship_status',
    'position': 'field_job_position',
    'type1': 'field_employee_type',
    'type2': 'field_work_model',
    'experienceLevel': 'field_experience_level',
    'education': 'field_education',
    'salaryType': 'field_salary_type',
    'currency': 'field_currency',
    'salaryAmount': 'field_salary_amount',
    'annualLeaves': 'field_annual_leaves',
    'joiningDate': 'field_joining_date',
    'profileImage': 'field_profile_image_url',
    'frontId': 'field_front_id_image_url',
    'backId': 'field_back_id_image_url',
    'cv': 'field_cv_url',
  };

  static Map<String, String> get _fieldLabels =>
      _fieldKeys.map((k, v) => MapEntry(k, v.tr()));

  static const Map<String, String> _headerMap = {
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

  static const double _tableContentWidth = 3522;
  static const double _rowHeight = 65.0;

  // ─────────────────────────────────────────────────────────────
  //  State
  // ─────────────────────────────────────────────────────────────
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

  ScrollController? _hScrollController;
  StreamSubscription? _workersSubscription;

  // ─────────────────────────────────────────────────────────────
  //  Lifecycle
  // ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestore = Provider.of<FirestoreService>(context, listen: false);
  }

  @override
  void dispose() {
    _hScrollController?.dispose();
    _workersSubscription?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  //  Unsaved changes guard
  // ─────────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────
  //  Helpers – error accessors
  // ─────────────────────────────────────────────────────────────
  Set<String> _errorFieldNames() {
    final fields = <String>{};
    for (final worker in _validWorkers) {
      final errors = worker['_fieldErrors'];
      if (errors is Map) {
        fields.addAll(errors.keys.cast<String>());
      }
    }
    return fields;
  }

  Map<String, String> _fieldErrors(Map<String, dynamic> worker) {
    final errors = worker['_fieldErrors'];
    if (errors is Map<String, String>) return errors;
    return const {};
  }

  bool _hasFieldError(Map<String, dynamic> worker, String field) {
    final errors = worker['_fieldErrors'];
    return errors is Map && errors.containsKey(field);
  }

  bool _hasWorkerErrors(Map<String, dynamic> worker) {
    final errors = worker['_fieldErrors'];
    return errors is Map && errors.isNotEmpty;
  }

  List<Map<String, dynamic>> get _workersReadyToSave =>
      _validWorkers.where((w) => !_hasWorkerErrors(w)).map((w) {
        final clean = Map<String, dynamic>.from(w);
        clean.remove('_fieldErrors');
        clean.remove('_rowNumber');
        return clean;
      }).toList();

  // ─────────────────────────────────────────────────────────────
  //  File hash
  // ─────────────────────────────────────────────────────────────
  String _computeFileHash(Uint8List bytes) {
    int hash = 0;
    final minLen = min(bytes.length, 8192);
    for (int i = 0; i < minLen; i++) {
      hash = ((hash << 5) + hash + bytes[i]) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  // ─────────────────────────────────────────────────────────────
  //  Download template
  // ─────────────────────────────────────────────────────────────
  Future<void> _downloadTemplate() async {
    const headerRow =
        'Full Name,Contact Number,Email Address,Father Name,National ID,'
        'Religion,Date of Birth,Gender,Address,Relationship Status,'
        'Job Position,Employee Type,Work Model,Experience Level,Education,'
        'Salary Type,Currency,Salary Amount,Annual Leaves,Joining Date,'
        'Profile Image URL,Front ID Image URL,Back ID Image URL,CV URL';

    const dataRows =
        'John Doe,1234567890,john@example.com,Robert Doe,37405-1234567-1,'
        'Christianity,1990-05-15,Male,123 Street California,Single,'
        'Software Engineer,Full-Time,On-Site,Mid-Level,Bachelor\'s,'
        'Monthly,USD,5000,15,1/15/2025,'
        'https://i.pravatar.cc/150?u=john,https://picsum.photos/seed/john_front/400/300,'
        'https://picsum.photos/seed/john_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf\n'
        'Jane Smith,0987654321,jane@example.com,David Smith,37405-7654321-2,'
        'Islam,1995-10-20,Female,456 Avenue New York,Married,'
        'UI Designer,Part-Time,Remote,Senior,Bachelor\'s,'
        'Monthly,USD,6000,15,1/15/2025,'
        'https://i.pravatar.cc/150?u=jane,https://picsum.photos/seed/jane_front/400/300,'
        'https://picsum.photos/seed/jane_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf\n'
        'Michael Johnson,1122334455,michael@example.com,Alan Johnson,37405-1122334-3,'
        'None,1988-02-28,Male,789 Road Texas,Single,'
        'Project Manager,Contract,Hybrid,Senior,Master\'s,'
        'Monthly,USD,7500,15,1/15/2025,'
        'https://i.pravatar.cc/150?u=michael,https://picsum.photos/seed/michael_front/400/300,'
        'https://picsum.photos/seed/michael_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf\n'
        'Emily Brown,5551234567,emily@example.com,Thomas Brown,37405-9988776-5,'
        'Christianity,1992-07-08,Female,321 Oak Avenue Chicago,Married,'
        'Marketing Manager,Full-Time,On-Site,Senior,Master\'s,'
        'Monthly,USD,8500,20,1/20/2025,'
        'https://i.pravatar.cc/150?u=emily,https://picsum.photos/seed/emily_front/400/300,'
        'https://picsum.photos/seed/emily_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf\n'
        'Carlos Garcia,5559876543,carlos@example.com,Luis Garcia,37405-4433221-4,'
        'Catholic,1985-03-22,Male,654 Pine Road Miami,Single,'
        'DevOps Engineer,Full-Time,On-Site,Senior,Bachelor\'s,'
        'Monthly,USD,9500,18,2/1/2025,'
        'https://i.pravatar.cc/150?u=carlos,https://picsum.photos/seed/carlos_front/400/300,'
        'https://picsum.photos/seed/carlos_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf\n'
        'Aisha Khan,5552468135,aisha@example.com,Imran Khan,37405-5566778-7,'
        'Islam,1993-11-12,Female,789 Maple Drive Houston,Single,'
        'Data Analyst,Full-Time,Hybrid,Mid-Level,Bachelor\'s,'
        'Monthly,USD,7000,15,2/5/2025,'
        'https://i.pravatar.cc/150?u=aisha,https://picsum.photos/seed/aisha_front/400/300,'
        'https://picsum.photos/seed/aisha_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf\n'
        'Robert Wilson,5553691479,robert@example.com,James Wilson,37405-1122334-8,'
        'None,1980-09-05,Male,147 Elm Street Seattle,Married,'
        'HR Director,Full-Time,On-Site,Senior,Master\'s,'
        'Annual,USD,110000,20,1/10/2025,'
        'https://i.pravatar.cc/150?u=robert,https://picsum.photos/seed/robert_front/400/300,'
        'https://picsum.photos/seed/robert_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf';

    const templateStr = '$headerRow\n$dataRows';

    try {
      final String? outputFile = await FilePicker.saveFile(
        dialogTitle: 'save_worker_template'.tr(),
        fileName: 'worker_template.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: Uint8List.fromList(utf8.encode(templateStr)),
      );

      if (outputFile == null) return;

      await io.File(outputFile).writeAsString(templateStr);

      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'template_saved_successfully'.tr(),
        );
      }
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

  // ─────────────────────────────────────────────────────────────
  //  Pick & parse CSV
  // ─────────────────────────────────────────────────────────────
  Future<void> _pickCsvAndParse() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      const int maxBytes = 5 * 1024 * 1024; // 5 MB

      // Size guard (in-memory bytes)
      if (file.bytes != null && file.bytes!.length > maxBytes) {
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

      // Fallback: read from disk
      if (bytes == null && file.path != null) {
        final diskFile = io.File(file.path!);
        if (await diskFile.length() > maxBytes) {
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

      // Duplicate-file guard
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

      // Decode & normalise line endings, strip BOM
      var csvString = utf8.decode(bytes, allowMalformed: true);
      if (csvString.isNotEmpty && csvString.codeUnitAt(0) == 0xFEFF) {
        csvString = csvString.substring(1);
      }
      csvString = csvString.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

      final rows = Csv(dynamicTyping: false).decode(csvString);

      if (!mounted) return;
      await _processCsvData(rows);
      _lastFileHash = fileHash;
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

  // ─────────────────────────────────────────────────────────────
  //  Process CSV rows
  // ─────────────────────────────────────────────────────────────
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

    // Which required fields are present in the header row?
    final Set<String> foundFields = {};
    for (final h in headers) {
      final mapped = _headerMap[h] ?? h;
      if (_requiredFields.contains(mapped)) foundFields.add(mapped);
    }
    final List<String> missingColumns = _requiredFields
        .where((f) => !foundFields.contains(f))
        .toList();

    // ── Fetch existing workers for duplicate checks ──
    final bool isGuest = _authService.currentUser?.isAnonymous ?? false;
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
          .where((u) => u.isNotEmpty)
          .toSet();
      existingBackIds = DummyData.workers
          .map((w) => WorkerIdentity.normalizeDocumentUrl(w['backId']))
          .where((u) => u.isNotEmpty)
          .toSet();
    } else {
      try {
        final snapshot = await _firestore.getWorkersOnce();
        Map<String, dynamic> d(doc) => doc.data() as Map<String, dynamic>;
        existingEmails = snapshot.docs
            .map((doc) => WorkerIdentity.normalizeEmail(d(doc)['email']))
            .where((e) => e.isNotEmpty)
            .toSet();
        existingNames = snapshot.docs
            .map((doc) => WorkerIdentity.normalizeName(d(doc)['name']))
            .where((n) => n.isNotEmpty)
            .toSet();
        existingNationalIds = snapshot.docs
            .map(
              (doc) => WorkerIdentity.normalizeNationalId(d(doc)['nationalId']),
            )
            .where((n) => n.isNotEmpty)
            .toSet();
        existingFrontIds = snapshot.docs
            .map(
              (doc) => WorkerIdentity.normalizeDocumentUrl(d(doc)['frontId']),
            )
            .where((u) => u.isNotEmpty)
            .toSet();
        existingBackIds = snapshot.docs
            .map((doc) => WorkerIdentity.normalizeDocumentUrl(d(doc)['backId']))
            .where((u) => u.isNotEmpty)
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

    // ── Parse rows ──
    final List<Map<String, dynamic>> parsedWorkers = [];
    final Set<String> csvEmails = {};
    final Set<String> csvNames = {};
    final Set<String> csvNationalIds = {};
    final Set<String> csvFrontIds = {};
    final Set<String> csvBackIds = {};

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.every((e) => e.toString().trim().isEmpty)) {
        continue;
      }

      // Default empty worker map
      final Map<String, dynamic> workerData = {
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

      // Map CSV columns → worker fields
      for (int j = 0; j < headers.length && j < row.length; j++) {
        final val = row[j].toString().trim();
        if (val.isEmpty) continue;

        final mappedKey = _headerMap[headers[j]] ?? headers[j];
        // Case-insensitive match against existing keys
        String matchedKey = mappedKey;
        for (final key in workerData.keys) {
          if (key.toLowerCase() == mappedKey.toLowerCase()) {
            matchedKey = key;
            break;
          }
        }
        workerData[matchedKey] = val;
      }

      final fieldErrors = <String, String>{};

      // ── Required field check ──
      final missingForWorker = _requiredFields
          .where(
            (f) =>
                workerData[f] == null ||
                workerData[f].toString().trim().isEmpty,
          )
          .toList();
      if (missingForWorker.isNotEmpty) {
        _missingRequiredCount++;
        for (final f in missingForWorker) {
          fieldErrors[f] = 'validation_required'.tr();
        }
      }

      // ── Currency validation ──
      final currency = workerData['currency'].toString().trim();
      if (currency.isNotEmpty) {
        if (!CurrencyUtils.isSupported(currency)) {
          fieldErrors['currency'] = 'invalid_currency_value'.tr();
        } else {
          workerData['currency'] = CurrencyUtils.normalize(currency);
        }
      }

      // ── Date of birth validation ──
      final dobStr = workerData['dob'].toString().trim();
      if (dobStr.isNotEmpty) {
        final dob = AppDateUtils.parseDateString(dobStr);
        if (dob == null) {
          fieldErrors['dob'] = 'validation_invalid_date'.tr();
          _invalidDobCount++;
        } else {
          final cutoff = DateTime.now().subtract(
            const Duration(days: 365 * 18),
          );
          if (dob.isAfter(cutoff)) {
            fieldErrors['dob'] = 'validation_min_age'.tr();
            _invalidDobCount++;
          }
        }
      }

      // ── Gender validation ──
      final gender = workerData['gender'].toString().trim();
      final normalizedGender = gender.toLowerCase();
      if (gender.isNotEmpty) {
        const validGenders = {'male', 'female', 'other', 'others'};
        if (!validGenders.contains(normalizedGender)) {
          fieldErrors['gender'] = 'validation_invalid_gender'.tr();
          _invalidGenderCount++;
        } else if (normalizedGender == 'others') {
          workerData['gender'] = 'Other';
        }
      }

      // ── Email format validation ──
      final email = WorkerIdentity.normalizeEmail(workerData['email']);
      if (email.isNotEmpty && !Validators.isValidEmail(email)) {
        fieldErrors['email'] = 'validation_invalid_email'.tr();
      }

      // ── Duplicate checks ──
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
        fieldErrors['name'] = 'validation_duplicate_name'.tr();
      }
      if (email.isNotEmpty &&
          (existingEmails.contains(email) || csvEmails.contains(email))) {
        fieldErrors['email'] = 'validation_duplicate_email'.tr();
      }
      if (nationalId.isNotEmpty &&
          (existingNationalIds.contains(nationalId) ||
              csvNationalIds.contains(nationalId))) {
        fieldErrors['nationalId'] = 'validation_duplicate_national_id'.tr();
      }
      if (frontId.isNotEmpty &&
          (existingFrontIds.contains(frontId) ||
              existingBackIds.contains(frontId) ||
              csvFrontIds.contains(frontId) ||
              csvBackIds.contains(frontId))) {
        fieldErrors['frontId'] = 'validation_duplicate_front_id'.tr();
      }
      if (backId.isNotEmpty &&
          (backId == frontId ||
              existingFrontIds.contains(backId) ||
              existingBackIds.contains(backId) ||
              csvFrontIds.contains(backId) ||
              csvBackIds.contains(backId))) {
        fieldErrors['backId'] = 'validation_duplicate_back_id'.tr();
      }

      final duplicateFields = {
        'name',
        'email',
        'nationalId',
        'frontId',
        'backId',
      };
      if (fieldErrors.keys.any(
        (k) => duplicateFields.contains(k) && fieldErrors[k] != null,
      )) {
        _duplicateCount++;
      }

      // Track CSV-level uniqueness
      if (email.isNotEmpty) csvEmails.add(email);
      if (name.isNotEmpty) csvNames.add(name);
      if (nationalId.isNotEmpty) csvNationalIds.add(nationalId);
      if (frontId.isNotEmpty) csvFrontIds.add(frontId);
      if (backId.isNotEmpty) csvBackIds.add(backId);

      // Derived leave counts
      workerData['availableAnnualLeaves'] =
          int.tryParse(workerData['annualLeaves'].toString()) ?? 0;
      workerData['availableCasualLeaves'] =
          int.tryParse(workerData['casualLeaves'].toString()) ?? 0;
      workerData['availableSickLeaves'] =
          int.tryParse(workerData['sickLeaves'].toString()) ?? 0;

      workerData['_rowNumber'] = i + 1;
      workerData['_fieldErrors'] = fieldErrors;

      parsedWorkers.add(workerData);
    }

    setState(() {
      _validWorkers = parsedWorkers;
      _hasParsedFile = true;
      _hasUnsavedChanges = true;
    });

    if (!mounted) return;

    // ── Build snack-bar summary ──
    final Set<String> allMissingFieldNames = {};
    for (final w in parsedWorkers) {
      for (final entry in _fieldErrors(w).entries) {
        if (entry.value == 'Required') allMissingFieldNames.add(entry.key);
      }
    }

    final int duplicateWorkers = parsedWorkers.where((w) {
      return _fieldErrors(w).values.any((r) => r.startsWith('Duplicate'));
    }).length;

    final bool hasAnyIssue =
        allMissingFieldNames.isNotEmpty ||
        missingColumns.isNotEmpty ||
        duplicateWorkers > 0;

    if (hasAnyIssue) {
      final snackParts = <String>[
        'csv_workers_found'.tr(namedArgs: {'count': '${parsedWorkers.length}'}),
      ];
      if (missingColumns.isNotEmpty) {
        final cols = missingColumns.map((f) => _fieldLabels[f] ?? f).join(', ');
        snackParts.add('csv_missing_columns'.tr(namedArgs: {'columns': cols}));
      }
      if (allMissingFieldNames.isNotEmpty) {
        final fields = allMissingFieldNames
            .map((f) => _fieldLabels[f] ?? f)
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
  }

  // ─────────────────────────────────────────────────────────────
  //  Save bulk workers
  // ─────────────────────────────────────────────────────────────
  Future<void> _saveBulkWorkers() async {
    // Reset stuck saving state
    if (_isSaving && mounted) {
      setState(() => _isSaving = false);
    }

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
      // Nothing uploadable — show per-issue breakdown
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

    // Count skips by category
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

    setState(() => _isSaving = true);

    final bool isGuest = _authService.currentUser?.isAnonymous ?? false;
    _showBulkProgressDialog();

    try {
      int importedCount = workersReadyToSave.length;
      int finalSkippedDuplicates = localDuplicateCount;
      BulkWorkerResult? bulkResult;

      if (isGuest) {
        for (int i = 0; i < workersReadyToSave.length; i++) {
          final newId = 'dummy_${DateTime.now().microsecondsSinceEpoch}_$i';
          DummyData.workers.insert(0, {...workersReadyToSave[i], 'id': newId});
        }
        await DummyData.saveToPrefs();
      } else {
        bulkResult = await _firestore.addBulkWorkers(workersReadyToSave);
        importedCount = bulkResult.imported;
        if (bulkResult.skipped > 0)
          finalSkippedDuplicates += bulkResult.skipped;
      }

      if (!mounted) return;
      Navigator.of(context).pop(); // close progress dialog

      // Build result summary with skip reasons
      final summaryParts = <String>[
        'workers_added_successfully'.tr(
          namedArgs: {'count': importedCount.toString()},
        ),
      ];
      if (bulkResult != null && bulkResult.skipReasons.isNotEmpty) {
        summaryParts.add(
          'skipped_duplicates_message'.tr(
            namedArgs: {'count': '${bulkResult.skipReasons.length}'},
          ),
        );
        final reasonCounts = <String, int>{};
        for (final reason in bulkResult.skipReasons) {
          final key = reason.contains('Duplicate') ? 'Duplicate' : 'Validation';
          reasonCounts[key] = (reasonCounts[key] ?? 0) + 1;
        }
        reasonCounts.forEach((key, count) {
          summaryParts.add('  • $count $key');
        });
      } else if (finalSkippedDuplicates > 0) {
        summaryParts.add(
          'skipped_duplicates_message'.tr(
            namedArgs: {'count': finalSkippedDuplicates.toString()},
          ),
        );
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
          finalSkippedDuplicates > 0 ||
          localMissingCount > 0 ||
          localInvalidDobCount > 0 ||
          localInvalidGenderCount > 0;

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

      await tryShowFirstMilestoneRateUs(context, 'bulk_worker');

      setState(() {
        _validWorkers = [];
        _hasParsedFile = false;
        _hasUnsavedChanges = false;
      });

      if (!isGuest) {
        _workersSubscription?.cancel();
        _workersSubscription = _firestore.workersStream.listen((_) {
          if (mounted) setState(() {});
        });
      } else {
        DummyData.loadFromPrefs();
      }

      widget.onBack?.call();
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'could_not_save_worker'.tr(),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  Progress dialog
  // ─────────────────────────────────────────────────────────────
  void _showBulkProgressDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
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

  // ─────────────────────────────────────────────────────────────
  //  Edit cell dialog
  // ─────────────────────────────────────────────────────────────
  Future<void> _editCell(int workerIndex, String fieldKey) async {
    if (workerIndex >= _validWorkers.length) return;

    final worker = _validWorkers[workerIndex];
    final currentValue = (worker[fieldKey] ?? '').toString();
    final label = _fieldLabels[fieldKey] ?? fieldKey;
    final result = await showDialog<String>(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (ctx) {
        // ✅ Controller created INSIDE the dialog builder — its lifecycle
        //    is naturally tied to the dialog. No manual dispose needed.
        final controller = TextEditingController(text: currentValue);
        String? dialogError;

        // For media fields: store actual data URL separately, show filename in text field
        final isMediaField =
            fieldKey == 'profileImage' ||
            fieldKey == 'frontId' ||
            fieldKey == 'backId' ||
            fieldKey == 'cv';
        String? mediaDataUrl;
        String? mediaFileName;
        bool hasExistingUpload = false;
        if (isMediaField && currentValue.isNotEmpty) {
          hasExistingUpload = currentValue.startsWith('data:');
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

        // ── Per-field input configuration ──
        TextInputType? keyboardTypeForField() {
          if (fieldKey == 'phone') return TextInputType.phone;
          if (fieldKey == 'email') return TextInputType.emailAddress;
          if (fieldKey == 'salaryAmount' || fieldKey == 'annualLeaves') {
            return const TextInputType.numberWithOptions(decimal: true);
          }
          if (fieldKey == 'nationalId') return TextInputType.number;
          return null;
        }

        List<TextInputFormatter>? inputFormattersForField() {
          if (fieldKey == 'phone') {
            return [
              FilteringTextInputFormatter.allow(RegExp(r'^[\d+\-\s()]*')),
              LengthLimitingTextInputFormatter(20),
            ];
          }
          if (fieldKey == 'nationalId') {
            return [
              FilteringTextInputFormatter.allow(RegExp(r'^[\d-]*')),
              LengthLimitingTextInputFormatter(15),
            ];
          }
          if (fieldKey == 'email') {
            return [LengthLimitingTextInputFormatter(100)];
          }
          if (fieldKey == 'religion') {
            return [LengthLimitingTextInputFormatter(30)];
          }
          if (fieldKey == 'currency') {
            return [LengthLimitingTextInputFormatter(5)];
          }
          if (fieldKey == 'gender') {
            return [LengthLimitingTextInputFormatter(10)];
          }
          if (fieldKey == 'relationshipStatus') {
            return [LengthLimitingTextInputFormatter(10)];
          }
          if (fieldKey == 'name' || fieldKey == 'fatherName') {
            return [LengthLimitingTextInputFormatter(100)];
          }
          if (fieldKey == 'position' ||
              fieldKey == 'type1' ||
              fieldKey == 'type2' ||
              fieldKey == 'experienceLevel' ||
              fieldKey == 'education' ||
              fieldKey == 'salaryType') {
            return [LengthLimitingTextInputFormatter(50)];
          }
          if (fieldKey == 'address') {
            return [LengthLimitingTextInputFormatter(200)];
          }
          if (fieldKey == 'profileImage' ||
              fieldKey == 'frontId' ||
              fieldKey == 'backId' ||
              fieldKey == 'cv') {
            return [LengthLimitingTextInputFormatter(500)];
          }
          if (fieldKey == 'salaryAmount' || fieldKey == 'annualLeaves') {
            return [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              LengthLimitingTextInputFormatter(15),
            ];
          }
          return null;
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
                      if (result != null && result.files.isNotEmpty) {
                        final file = result.files.first;
                        if (file.bytes != null &&
                            file.bytes!.length > 10 * 1024 * 1024) {
                          setDialogState(() {
                            dialogError = 'file_too_large'.tr(
                              namedArgs: {'size': '10MB'},
                            );
                          });
                          return;
                        }
                        Uint8List? bytes = file.bytes;
                        if (bytes == null && file.path != null) {
                          bytes = io.File(file.path!).readAsBytesSync();
                        }
                        if (bytes != null) {
                          final ext = file.name.split('.').last.toLowerCase();
                          const mimeMap = {
                            'pdf': 'application/pdf',
                            'doc': 'application/msword',
                            'docx':
                                'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
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
                          // ── Input ──
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
                                    keyboardType: keyboardTypeForField(),
                                    inputFormatters: inputFormattersForField(),
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
                                      hintText: 'edit_cell_enter_value'.tr(
                                        namedArgs: {'label': label},
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
                                                      ? const Color(0xFFDCFCE7)
                                                      : const Color(0xFFEEF2FF),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
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
                                                          : Icons.badge_rounded,
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
                                                          : 'upload_image'.tr(),
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
                                                      overflow:
                                                          TextOverflow.ellipsis,
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

                          // ── Hint ──
                          if (_fieldHint(fieldKey).isNotEmpty)
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
                                      _fieldHint(fieldKey),
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

                          // ── Inline error ──
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

                          // ── Actions ──
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
                                    final val = controller.text.trim();
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
                                      )) {
                                        setDialogState(() {
                                          dialogError =
                                              'validation_invalid_email'.tr();
                                        });
                                      } else {
                                        final isDuplicate = _validWorkers
                                            .asMap()
                                            .entries
                                            .any((entry) {
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
                                          Navigator.of(ctx).pop(val);
                                        }
                                      }
                                    } else if (fieldKey == 'nationalId' &&
                                        val.isNotEmpty) {
                                      final normalizedId =
                                          WorkerIdentity.normalizeNationalId(
                                            val,
                                          );
                                      final isDuplicate = _validWorkers
                                          .asMap()
                                          .entries
                                          .any((entry) {
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
                                      const valid = {
                                        'single',
                                        'married',
                                        'divorced',
                                        'widowed',
                                      };
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
                                      } else {
                                        final display = normalized.replaceAll(
                                          ' ',
                                          '-',
                                        );
                                        Navigator.of(ctx).pop(display);
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
                                      } else {
                                        final display = normalized.replaceAll(
                                          ' ',
                                          '-',
                                        );
                                        Navigator.of(ctx).pop(display);
                                      }
                                    } else if (fieldKey == 'salaryType') {
                                      final normalized = val
                                          .toLowerCase()
                                          .trim();
                                      const valid = {
                                        'monthly',
                                        'hourly',
                                        'contract',
                                        'annual',
                                      };
                                      if (normalized.isEmpty) {
                                        setDialogState(() {
                                          dialogError =
                                              'edit_cell_cannot_be_empty'.tr();
                                        });
                                      } else if (!valid.contains(normalized)) {
                                        setDialogState(() {
                                          dialogError =
                                              'validation_invalid_salary_type'
                                                  .tr();
                                        });
                                      } else {
                                        final display =
                                            normalized[0].toUpperCase() +
                                            normalized.substring(1);
                                        Navigator.of(ctx).pop(display);
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
                                      } else {
                                        final cutoff = DateTime.now().subtract(
                                          const Duration(days: 365 * 18),
                                        );
                                        if (dob.isAfter(cutoff)) {
                                          setDialogState(() {
                                            dialogError = 'validation_min_age'
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
                                          // Update display name but keep existing data URL
                                          worker['${fieldKey}_name'] = val
                                              .split('/')
                                              .last;
                                          Navigator.of(ctx).pop(currentValue);
                                        } else if (val.isNotEmpty &&
                                            !val.startsWith('data:')) {
                                          // Manually typed URL - validate file extension
                                          final ext = val
                                              .split('.')
                                              .last
                                              .split('?')
                                              .first
                                              .toLowerCase();
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
                                            'gif',
                                            'bmp',
                                            'webp',
                                          };
                                          if (fieldKey == 'cv' &&
                                              !cvExts.contains(ext)) {
                                            setDialogState(() {
                                              dialogError =
                                                  'Only PDF, DOC, DOCX and image formats (JPG, JPEG, PNG, etc.) are accepted for CV';
                                            });
                                          } else if (fieldKey != 'cv' &&
                                              !imageExts.contains(ext)) {
                                            setDialogState(() {
                                              dialogError =
                                                  'Only PNG, JPEG, JPG formats are accepted for images';
                                            });
                                          } else {
                                            worker['${fieldKey}_name'] = val
                                                .split('/')
                                                .last;
                                            Navigator.of(ctx).pop(val);
                                          }
                                        } else {
                                          worker['${fieldKey}_name'] = val
                                              .split('/')
                                              .last;
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

    // ❌ No manual dispose needed — the controller is created inside the
    //    dialog builder and will be garbage-collected when the dialog is
    //    dismissed. The old delayed-dispose hack caused TextField rebuilds
    //    (e.g. during close animation) to use a disposed controller.

    if (result != null && mounted) {
      setState(() {
        _validWorkers[workerIndex][fieldKey] = result;
        _hasUnsavedChanges = true;
        final errors = _validWorkers[workerIndex]['_fieldErrors'];
        if (errors is Map<String, String>) {
          errors.remove(fieldKey);
          // Re-validate gender to ensure consistency
          if (fieldKey == 'gender') {
            final normalized = result.toLowerCase();
            const validGenders = {'male', 'female', 'other', 'others'};
            if (!validGenders.contains(normalized)) {
              errors['gender'] = 'Only Male, Female, or Other is allowed';
            }
          }
        }
      });
    }
  }

  String _fieldHint(String fieldKey) {
    const hintKeys = <String, String>{
      'name': 'hint_enter_full_name',
      'email': 'hint_enter_email',
      'phone': 'hint_enter_phone',
      'fatherName': 'hint_enter_father_name',
      'nationalId': 'hint_enter_national_id',
      'religion': 'hint_enter_religion',
      'gender': 'hint_enter_gender',
      'dob': 'hint_enter_dob',
      'address': 'hint_enter_address',
      'relationshipStatus': 'hint_enter_relationship',
      'position': 'hint_enter_position',
      'type1': 'hint_enter_type1',
      'type2': 'hint_enter_type2',
      'experienceLevel': 'hint_enter_experience',
      'education': 'hint_enter_education',
      'salaryType': 'hint_enter_salary_type',
      'currency': 'hint_enter_currency',
      'salaryAmount': 'hint_enter_salary_amount',
      'annualLeaves': 'hint_enter_annual_leaves',
      'joiningDate': 'hint_enter_joining_date',
      'profileImage': 'hint_enter_profile_image',
      'frontId': 'hint_enter_front_id',
      'backId': 'hint_enter_back_id',
      'cv': 'hint_enter_cv',
    };
    final key = hintKeys[fieldKey];
    return key != null ? key.tr() : '';
  }

  // ─────────────────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────
  //  Top bar
  // ─────────────────────────────────────────────────────────────
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
          // ── Back + title ──
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

          // ── Save All button (only when all rows are clean) ──
          if (_hasParsedFile &&
              _validWorkers.isNotEmpty &&
              _validWorkers.every((w) => !_hasWorkerErrors(w)))
            _buildSaveAllButton(),
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

  // ─────────────────────────────────────────────────────────────
  //  Action buttons row
  // ─────────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────
  //  Summary card
  // ─────────────────────────────────────────────────────────────
  Widget _buildSummaryCard() {
    final bool anyErrors = _validWorkers.any(_hasWorkerErrors);
    final int errorCount = _validWorkers.where(_hasWorkerErrors).length;

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

  // ─────────────────────────────────────────────────────────────
  //  Worker table
  // ─────────────────────────────────────────────────────────────
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
          // ── Scrollable header + rows share one controller ──
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
          _buildHeaderCell('salary_type'.tr(), 130, fieldKey: 'salaryType'),
          _buildHeaderCell('currency_title'.tr(), 100, fieldKey: 'currency'),
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
            'joining_date_title'.tr(),
            130,
            fieldKey: 'joiningDate',
          ),
          _buildHeaderCell(
            'profile_image_url'.tr(),
            130,
            fieldKey: 'profileImage',
          ),
          _buildHeaderCell('front_id_image_url'.tr(), 130, fieldKey: 'frontId'),
          _buildHeaderCell('back_id_image_url'.tr(), 130, fieldKey: 'backId'),
          _buildHeaderCell('cv_url'.tr(), 130, fieldKey: 'cv'),
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

  // ─────────────────────────────────────────────────────────────
  //  Row & cell builders
  // ─────────────────────────────────────────────────────────────
  Widget _buildWorkerRow(Map<String, dynamic> worker, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      color: index.isEven ? const Color(0xFFFAFBFC) : Colors.white,
      child: Row(
        children: [
          _buildDataCell(
            worker['name']?.toString() ?? '',
            150,
            hasError: _hasFieldError(worker, 'name'),
            fieldKey: 'name',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['phone']?.toString() ?? '',
            130,
            hasError: _hasFieldError(worker, 'phone'),
            fieldKey: 'phone',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['email']?.toString() ?? '',
            150,
            hasError: _hasFieldError(worker, 'email'),
            fieldKey: 'email',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['position']?.toString() ?? '',
            130,
            hasError: _hasFieldError(worker, 'position'),
            fieldKey: 'position',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['salaryType']?.toString() ?? '',
            130,
            hasError: _hasFieldError(worker, 'salaryType'),
            fieldKey: 'salaryType',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['currency']?.toString() ?? '',
            100,
            hasError: _hasFieldError(worker, 'currency'),
            fieldKey: 'currency',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['salaryAmount']?.toString() ?? '',
            130,
            hasError: _hasFieldError(worker, 'salaryAmount'),
            fieldKey: 'salaryAmount',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['fatherName']?.toString() ?? '',
            150,
            hasError: _hasFieldError(worker, 'fatherName'),
            fieldKey: 'fatherName',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['nationalId']?.toString() ?? '',
            130,
            hasError: _hasFieldError(worker, 'nationalId'),
            fieldKey: 'nationalId',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['religion']?.toString() ?? '',
            120,
            hasError: _hasFieldError(worker, 'religion'),
            fieldKey: 'religion',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['dob']?.toString() ?? '',
            120,
            hasError: _hasFieldError(worker, 'dob'),
            fieldKey: 'dob',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['gender']?.toString() ?? '',
            100,
            hasError: _hasFieldError(worker, 'gender'),
            fieldKey: 'gender',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['address']?.toString() ?? '',
            130,
            hasError: _hasFieldError(worker, 'address'),
            fieldKey: 'address',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['relationshipStatus']?.toString() ?? '',
            130,
            hasError: _hasFieldError(worker, 'relationshipStatus'),
            fieldKey: 'relationshipStatus',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['type1']?.toString() ?? '',
            130,
            hasError: _hasFieldError(worker, 'type1'),
            fieldKey: 'type1',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['type2']?.toString() ?? '',
            130,
            hasError: _hasFieldError(worker, 'type2'),
            fieldKey: 'type2',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['experienceLevel']?.toString() ?? '',
            130,
            hasError: _hasFieldError(worker, 'experienceLevel'),
            fieldKey: 'experienceLevel',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['education']?.toString() ?? '',
            130,
            hasError: _hasFieldError(worker, 'education'),
            fieldKey: 'education',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['annualLeaves']?.toString() ?? '',
            120,
            hasError: _hasFieldError(worker, 'annualLeaves'),
            fieldKey: 'annualLeaves',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['joiningDate']?.toString() ?? '',
            130,
            hasError: _hasFieldError(worker, 'joiningDate'),
            fieldKey: 'joiningDate',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['profileImage']?.toString() ?? '',
            130,
            hasError: _hasFieldError(worker, 'profileImage'),
            fieldKey: 'profileImage',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['frontId']?.toString() ?? '',
            130,
            hasError: _hasFieldError(worker, 'frontId'),
            fieldKey: 'frontId',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['backId']?.toString() ?? '',
            130,
            hasError: _hasFieldError(worker, 'backId'),
            fieldKey: 'backId',
            workerIndex: index,
          ),
          _buildDataCell(
            worker['cv']?.toString() ?? '',
            130,
            hasError: _hasFieldError(worker, 'cv'),
            fieldKey: 'cv',
            workerIndex: index,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, double width, {String? fieldKey}) {
    final bool hasError =
        fieldKey != null && _errorFieldNames().contains(fieldKey);
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
                color: hasError
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF475569),
                fontFamily: 'SF Pro Display',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasError) ...[
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
      // Use stored filename from worker data
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
          displayText = text.split('/').last;
        }
      } else if (text.startsWith('data:')) {
        final mime = text.split(';').first.split(':').last;
        displayText = mime == 'application/pdf' ? 'document.pdf' : 'image.jpg';
      } else {
        displayText = text.split('/').last;
      }
    } else if (text.isEmpty) {
      displayText = '-';
    } else {
      displayText = text;
    }

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      margin: const EdgeInsets.only(right: 16),
      child: Row(
        children: [
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
}
