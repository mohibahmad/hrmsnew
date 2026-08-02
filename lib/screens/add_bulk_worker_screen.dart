import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:ui' as ui;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart' hide GestureDetector;
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter/services.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import '../utils/file_opener.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/upload_service.dart';
import '../services/error_reporter.dart';
import '../utils/snackbar_utils.dart';
import '../utils/rate_us_helper.dart';
import '../utils/date_utils.dart';
import '../utils/currency_utils.dart';
import '../utils/localization_helper.dart';
import '../utils/worker_identity.dart';
import '../utils/validators.dart';
import 'package:provider/provider.dart';

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

  const AddBulkWorkerScreen({super.key, this.onBack});

  @override
  AddBulkWorkerScreenState createState() => AddBulkWorkerScreenState();
}

class AddBulkWorkerScreenState extends State<AddBulkWorkerScreen> {
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

  ScrollController? _hScrollController;
  StreamSubscription? _workersSubscription;

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

  Future<List<Map<String, dynamic>>> _uploadEmbeddedWorkerMedia(
    List<Map<String, dynamic>> workers, {
    void Function(int completed, int total, String currentFile)? onProgress,
  }) async {
    final prepared = workers
        .map((worker) => Map<String, dynamic>.from(worker))
        .toList();
    const mediaFields = ['profileImage', 'frontId', 'backId', 'cv'];
    const downloadBatchSize = 10;
    const uploadBatchSize = 8;

    var totalMedia = 0;
    for (final worker in workers) {
      for (final field in mediaFields) {
        final value = (worker[field] ?? '').toString().trim();
        if (value.isNotEmpty) totalMedia++;
      }
    }

    final embeddedFiles = <UploadFile>[];
    final embeddedTargets = <({int workerIndex, String field})>[];
    final remoteItems =
        <int, ({int workerIndex, String field, String url, String folder, String fallbackName, String fallbackMime})>{};

    for (var workerIndex = 0; workerIndex < prepared.length; workerIndex++) {
      final worker = prepared[workerIndex];
      for (final field in mediaFields) {
        final value = (worker[field] ?? '').toString().trim();
        final isEmbeddedFile =
            value.startsWith('data:') && value.contains(';base64,');
        final uri = Uri.tryParse(value);
        final isRemoteFile =
            uri != null &&
            uri.hasAuthority &&
            (uri.scheme == 'http' || uri.scheme == 'https');
        if (!isEmbeddedFile && !isRemoteFile) {
          if (value.isNotEmpty) {
            final workerName = (worker['name'] ?? 'Worker').toString();
            throw StateError(
              '$workerName — ${_mediaFieldName(field)}: '
              '${'bulk_media_invalid_url'.tr()}',
            );
          }
          continue;
        }

        final storedName = (worker['${field}_name'] ?? '').toString().trim();
        final folder = field == 'profileImage'
            ? 'profile_images'
            : field == 'cv'
            ? 'worker_cvs'
            : 'identity_documents';

        if (isEmbeddedFile) {
          final separator = value.indexOf(';base64,');
          final mimeType = value.substring(5, separator);
          final bytes = base64Decode(value.substring(separator + 8));
          if (!_isSupportedMediaType(field, mimeType)) {
            final workerName = (worker['name'] ?? 'Worker').toString();
            throw StateError(
              '$workerName — ${_mediaFieldName(field)}: '
              '${_supportedMediaMessage(field, mimeType)}',
            );
          }
          final fallbackExtension = switch (mimeType) {
            'application/pdf' => 'pdf',
            'application/msword' || 'application/doc' => 'doc',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
            'application/docx' => 'docx',
            'image/png' => 'png',
            'image/webp' => 'webp',
            _ => 'jpg',
          };
          embeddedFiles.add(
            UploadFile(
              folder: folder,
              fileName: storedName.isNotEmpty
                  ? storedName
                  : '${field}_$workerIndex.$fallbackExtension',
              bytes: bytes,
              mimeType: mimeType,
            ),
          );
          embeddedTargets.add((workerIndex: workerIndex, field: field));
        } else {
          final key =
              workerIndex * mediaFields.length + mediaFields.indexOf(field);
          remoteItems[key] = (
            workerIndex: workerIndex,
            field: field,
            url: value,
            folder: folder,
            fallbackName: storedName.isNotEmpty
                ? storedName
                : '${field}_$workerIndex.${field == 'cv' ? 'pdf' : 'jpg'}',
            fallbackMime: field == 'cv' ? 'application/pdf' : 'image/jpeg',
          );
        }
      }
    }

    var completedCount = 0;

    Future<List<UploadResult>> uploadBatch(
      List<UploadFile> batchFiles,
    ) async {
      if (batchFiles.isEmpty) return [];
      final batchResults = await UploadService.uploadFiles(
        files: batchFiles,
        maxConcurrent: uploadBatchSize,
        onProgress: (completed, total) {
          final idx = completed - 1;
          final name =
              idx >= 0 && idx < batchFiles.length
                  ? batchFiles[idx].fileName
                  : '';
          onProgress?.call(completedCount + completed, totalMedia, name);
        },
      );
      final failed = batchResults.indexWhere(
        (r) => !r.isSuccess || r.url == null,
      );
      if (failed != -1) {
        throw StateError(
          '${batchFiles[failed].fileName} upload: '
          '${_readableSaveError(batchResults[failed].error ?? 'bulk_media_upload_failed'.tr())}',
        );
      }
      completedCount += batchFiles.length;
      return batchResults;
    }

    Future<List<UploadFile>> downloadBatchRemote(List<int> keys) async {
      final futures = keys.map((k) {
        final item = remoteItems[k]!;
        return UploadService.downloadRemoteFile(
          url: item.url,
          folder: item.folder,
          fallbackFileName: item.fallbackName,
          fallbackMimeType: item.fallbackMime,
        );
      }).toList();
      return Future.wait(futures);
    }

    if (embeddedFiles.isNotEmpty) {
      onProgress?.call(0, totalMedia, 'uploading_embedded');
      final embedResults = await uploadBatch(embeddedFiles);
      for (var i = 0; i < embedResults.length; i++) {
        final t = embeddedTargets[i];
        prepared[t.workerIndex][t.field] = embedResults[i].url;
      }
    }

    final remoteKeys = remoteItems.keys.toList();
    final totalBatches = (remoteKeys.length / downloadBatchSize).ceil();

    if (totalBatches > 0) {
      var nextDownload = downloadBatchRemote(
        remoteKeys.sublist(0, downloadBatchSize.clamp(0, remoteKeys.length)),
      );

      for (var b = 0; b < totalBatches; b++) {
        final currentDownload = nextDownload;

        if (b + 1 < totalBatches) {
          final start = (b + 1) * downloadBatchSize;
          final end = (start + downloadBatchSize).clamp(0, remoteKeys.length);
          nextDownload = downloadBatchRemote(remoteKeys.sublist(start, end));
        }

        final downloaded = await currentDownload;

        final batchKeys = remoteKeys.sublist(
          b * downloadBatchSize,
          (b * downloadBatchSize + downloaded.length).clamp(
            0,
            remoteKeys.length,
          ),
        );

        for (var j = 0; j < downloaded.length; j++) {
          final key = batchKeys[j];
          final item = remoteItems[key]!;
          if (!_isSupportedMediaType(item.field, downloaded[j].mimeType)) {
            final workerName =
                (prepared[item.workerIndex]['name'] ?? 'Worker').toString();
            throw StateError(
              '$workerName — ${_mediaFieldName(item.field)} link: '
              '${_supportedMediaMessage(item.field, downloaded[j].mimeType)}',
            );
          }
        }

        if (b + 1 < totalBatches) {
          final uploadFuture = uploadBatch(downloaded);
          final downloadFuture = nextDownload;
          final results = await Future.wait([uploadFuture, downloadFuture]);
          final batchResults = results[0] as List<UploadResult>;
          for (var j = 0; j < batchResults.length; j++) {
            final key = batchKeys[j];
            final item = remoteItems[key]!;
            prepared[item.workerIndex][item.field] = batchResults[j].url;
          }
        } else {
          final batchResults = await uploadBatch(downloaded);
          for (var j = 0; j < batchResults.length; j++) {
            final key = batchKeys[j];
            final item = remoteItems[key]!;
            prepared[item.workerIndex][item.field] = batchResults[j].url;
          }
        }
      }
    }

    return prepared;
  }

  String _mediaFieldName(String field) {
    return switch (field) {
      'profileImage' => 'media_field_profile_image'.tr(),
      'frontId' => 'media_field_front_id'.tr(),
      'backId' => 'media_field_back_id'.tr(),
      'cv' => 'media_field_cv'.tr(),
      _ => field,
    };
  }

  bool _isSupportedMediaType(String field, String mimeType) {
    final raw = mimeType.toLowerCase().split(';').first.trim();
    final normalized = switch (raw) {
      'image/jpg' => 'image/jpeg',
      'application/doc' => 'application/msword',
      'application/docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      _ => raw,
    };
    const supportedImages = {'image/jpeg', 'image/png'};
    if (field != 'cv') return supportedImages.contains(normalized);
    return supportedImages.contains(normalized) ||
        normalized == 'application/pdf' ||
        normalized == 'application/msword' ||
        normalized ==
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }

  String _supportedMediaMessage(String field, [String? received]) {
    if (field == 'cv') {
      return 'bulk_media_cv_format_error'.tr();
    }
    return 'bulk_media_image_format_error'.tr(
      namedArgs: {'received': received ?? ''},
    );
  }

  String _readableSaveError(Object error) {
    if (error is TimeoutException) {
      return error.message ?? 'bulk_media_download_timeout'.tr();
    }
    if (error is io.HttpException) return error.message;
    if (error is io.SocketException) return error.message;
    if (error is io.FileSystemException) return error.message;
    if (error is FormatException) return error.message;

    var message = error.toString().trim();
    for (final prefix in [
      'Bad state: ',
      'Exception: ',
      'FirebaseException: ',
    ]) {
      if (message.startsWith(prefix)) {
        message = message.substring(prefix.length).trim();
      }
    }
    if (message.isEmpty) return 'bulk_media_unknown_error'.tr();
    return message.length > 220 ? '${message.substring(0, 220)}…' : message;
  }

  String _computeFileHash(Uint8List bytes) {
    int hash = 0x811C9DC5;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return '${bytes.length}_${hash.toRadixString(16)}';
  }

  Future<void> _downloadTemplate() async {
    const headerRow =
        'Full Name,Contact Number,Email Address,Father Name,National ID,'
        'Religion,Date of Birth,Gender,Address,Relationship Status,'
        'Job Position,Employee Type,Work Model,Experience Level,Education,'
        'Salary Type,Currency,Salary Amount,Annual Leaves,Joining Date,'
        'Profile Image URL,Front ID Image URL,Back ID Image URL,CV URL';

    const dataRows =
        'John Doe,1234567890,john@gmail.com,Robert Doe,37405-1234567-1,'
        'Christianity,1990-05-15,Male,123 Street California,Single,'
        'Software Engineer,Full-Time,On-Site,Mid-Level,Bachelor\'s,'
        'Monthly,USD,5000,15,1/15/2025,'
        'https://i.pravatar.cc/150?u=john,https://picsum.photos/seed/john_front/400/300,'
        'https://picsum.photos/seed/john_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf\n'
        'Jane Smith,0987654321,jane@gmail.com,David Smith,37405-7654321-2,'
        'Islam,1995-10-20,Female,456 Avenue New York,Married,'
        'UI Designer,Part-Time,Remote,Senior,Bachelor\'s,'
        'Monthly,USD,6000,15,1/15/2025,'
        'https://i.pravatar.cc/150?u=jane,https://picsum.photos/seed/jane_front/400/300,'
        'https://picsum.photos/seed/jane_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf\n'
        'Michael Johnson,1122334455,michael@gmail.com,Alan Johnson,37405-1122334-3,'
        'None,1988-02-28,Male,789 Road Texas,Single,'
        'Project Manager,Contract,Hybrid,Senior,Master\'s,'
        'Monthly,USD,7500,15,1/15/2025,'
        'https://i.pravatar.cc/150?u=michael,https://picsum.photos/seed/michael_front/400/300,'
        'https://picsum.photos/seed/michael_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf\n'
        'Emily Brown,5551234567,emily@gmail.com,Thomas Brown,37405-9988776-5,'
        'Christianity,1992-07-08,Female,321 Oak Avenue Chicago,Married,'
        'Marketing Manager,Full-Time,On-Site,Senior,Master\'s,'
        'Monthly,USD,8500,20,1/20/2025,'
        'https://i.pravatar.cc/150?u=emily,https://picsum.photos/seed/emily_front/400/300,'
        'https://picsum.photos/seed/emily_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf\n'
        'Carlos Garcia,5559876543,carlos@gmail.com,Luis Garcia,37405-4433221-4,'
        'Catholic,1985-03-22,Male,654 Pine Road Miami,Single,'
        'DevOps Engineer,Full-Time,On-Site,Senior,Bachelor\'s,'
        'Monthly,USD,9500,18,2/1/2025,'
        'https://i.pravatar.cc/150?u=carlos,https://picsum.photos/seed/carlos_front/400/300,'
        'https://picsum.photos/seed/carlos_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf\n'
        'Aisha Khan,5552468135,aisha@gmail.com,Imran Khan,37405-5566778-7,'
        'Islam,1993-11-12,Female,789 Maple Drive Houston,Single,'
        'Data Analyst,Full-Time,Hybrid,Mid-Level,Bachelor\'s,'
        'Monthly,USD,7000,15,2/5/2025,'
        'https://i.pravatar.cc/150?u=aisha,https://picsum.photos/seed/aisha_front/400/300,'
        'https://picsum.photos/seed/aisha_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf\n'
        'Robert Wilson,5553691479,robert@gmail.com,James Wilson,37405-1122334-8,'
        'None,1980-09-05,Male,147 Elm Street Seattle,Married,'
        'HR Director,Full-Time,On-Site,Senior,Master\'s,'
        'Monthly,USD,110000,20,1/10/2025,'
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
        await FileOpener.open(outputFile);
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

  Future<void> _pickCsvAndParse() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      const int maxBytes = 5 * 1024 * 1024;

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

  /// Normalizes an education value to its canonical display form
  /// (e.g. "bachelor's", "bachelors" -> "Bachelor"). Returns null when the
  /// value is not a supported education level.
  String? _normalizeEducation(String input) {
    final normalized = input.trim().toLowerCase();
    const valid = {
      'matric',
      'intermediate',
      'bachelor',
      'bachelors',
      "bachelor's",
      'master',
      'masters',
      "master's",
      'other',
    };
    if (!valid.contains(normalized)) return null;
    return switch (normalized) {
      'bachelors' || "bachelor's" => 'Bachelor',
      'masters' || "master's" => 'Master',
      _ => normalized[0].toUpperCase() + normalized.substring(1),
    };
  }

  Map<String, String> _validateWorkerData(
    Map<String, dynamic> workerData, {
    required Set<String> existingEmails,
    required Set<String> existingNationalIds,
    required Set<String> csvEmails,
    required Set<String> csvNationalIds,
  }) {
    final fieldErrors = <String, String>{};
    final requiredMessage = 'validation_required'.tr();

    for (final field in _requiredFields) {
      final value = workerData[field]?.toString().trim() ?? '';
      if (value.isEmpty) {
        fieldErrors[field] = requiredMessage;
      }
    }

    final currency = workerData['currency']?.toString().trim() ?? '';
    if (currency.isNotEmpty) {
      if (!CurrencyUtils.isSupported(currency)) {
        fieldErrors['currency'] = 'invalid_currency_value'.tr();
      } else {
        workerData['currency'] = CurrencyUtils.normalize(currency);
      }
    }

    final dobStr = workerData['dob']?.toString().trim() ?? '';
    if (dobStr.isNotEmpty) {
      final dob = AppDateUtils.parseDateString(dobStr);
      if (dob == null) {
        fieldErrors['dob'] = 'validation_invalid_date'.tr();
      } else if (!_isAtLeast18(dob)) {
        fieldErrors['dob'] = 'validation_min_age'.tr();
      }
    }

    final gender = workerData['gender']?.toString().trim() ?? '';
    if (gender.isNotEmpty) {
      final normalizedGender = gender.toLowerCase();
      const validGenders = {'male', 'female', 'other', 'others'};
      if (!validGenders.contains(normalizedGender)) {
        fieldErrors['gender'] = 'validation_invalid_gender'.tr();
      } else {
        workerData['gender'] = normalizedGender == 'male'
            ? 'Male'
            : normalizedGender == 'female'
            ? 'Female'
            : 'Other';
      }
    }

    final experienceLevel =
        workerData['experienceLevel']?.toString().trim() ?? '';
    if (experienceLevel.isNotEmpty) {
      final normalized = experienceLevel.toLowerCase();
      const valid = {'fresher', 'junior', 'mid-level', 'mid level', 'senior'};
      if (!valid.contains(normalized)) {
        fieldErrors['experienceLevel'] = 'validation_invalid_experience_level'
            .tr();
      } else {
        workerData['experienceLevel'] = normalized == 'fresher'
            ? 'Fresher'
            : normalized == 'junior'
            ? 'Junior'
            : normalized == 'mid-level' || normalized == 'mid level'
            ? 'Mid-Level'
            : 'Senior';
      }
    }

    final education = workerData['education']?.toString().trim() ?? '';
    if (education.isNotEmpty) {
      final normalizedEducation = _normalizeEducation(education);
      if (normalizedEducation == null) {
        fieldErrors['education'] = 'validation_invalid_education'.tr();
      } else {
        workerData['education'] = normalizedEducation;
      }
    }

    final relationshipStatus =
        workerData['relationshipStatus']?.toString().trim() ?? '';
    if (relationshipStatus.isNotEmpty) {
      final normalized = relationshipStatus.toLowerCase();
      const valid = {'single', 'married'};
      if (!valid.contains(normalized)) {
        fieldErrors['relationshipStatus'] = 'validation_invalid_relationship'
            .tr();
      } else {
        workerData['relationshipStatus'] =
            normalized[0].toUpperCase() + normalized.substring(1);
      }
    }

    final employeeType = workerData['type1']?.toString().trim() ?? '';
    if (employeeType.isNotEmpty) {
      final normalized = employeeType.toLowerCase();
      const valid = {
        'full-time',
        'full time',
        'part-time',
        'part time',
        'contract',
        'intern',
      };
      if (!valid.contains(normalized)) {
        fieldErrors['type1'] = 'validation_invalid_employee_type'.tr();
      } else if (normalized == 'full-time' || normalized == 'full time') {
        workerData['type1'] = 'Full-Time';
      } else if (normalized == 'part-time' || normalized == 'part time') {
        workerData['type1'] = 'Part-Time';
      } else if (normalized == 'contract') {
        workerData['type1'] = 'Contract';
      } else {
        workerData['type1'] = 'Intern';
      }
    }

    final workModel = workerData['type2']?.toString().trim() ?? '';
    if (workModel.isNotEmpty) {
      final normalized = workModel.toLowerCase();
      const valid = {'on-site', 'on site', 'onsite', 'remote', 'hybrid'};
      if (!valid.contains(normalized)) {
        fieldErrors['type2'] = 'validation_invalid_work_model'.tr();
      } else if (normalized == 'remote') {
        workerData['type2'] = 'Remote';
      } else if (normalized == 'hybrid') {
        workerData['type2'] = 'Hybrid';
      } else {
        workerData['type2'] = 'On-Site';
      }
    }

    final salaryType = workerData['salaryType']?.toString().trim() ?? '';
    if (salaryType.isNotEmpty) {
      final normalized = salaryType.toLowerCase();
      const valid = {'monthly', 'hourly', 'contract'};
      if (!valid.contains(normalized)) {
        fieldErrors['salaryType'] = 'validation_invalid_salary_type'.tr();
      } else {
        workerData['salaryType'] =
            normalized[0].toUpperCase() + normalized.substring(1);
      }
    }

    final leavePolicy = workerData['leavePolicy']?.toString().trim() ?? '';
    if (leavePolicy.isEmpty) {
      workerData['leavePolicy'] = 'Standard';
    }

    final email = WorkerIdentity.normalizeEmail(workerData['email']);
    if (email.isEmpty) {
      if ((workerData['email']?.toString().trim() ?? '').isNotEmpty) {
        fieldErrors['email'] = requiredMessage;
      }
    } else if (!Validators.isValidEmail(email)) {
      fieldErrors['email'] = 'validation_invalid_email'.tr();
    } else {
      workerData['email'] = email;
      if (existingEmails.contains(email) || csvEmails.contains(email)) {
        fieldErrors['email'] = 'validation_duplicate_email'.tr();
      }
    }

    final nationalId = WorkerIdentity.normalizeNationalId(
      workerData['nationalId'],
    );
    if (nationalId.isNotEmpty &&
        (existingNationalIds.contains(nationalId) ||
            csvNationalIds.contains(nationalId))) {
      fieldErrors['nationalId'] = 'validation_duplicate_national_id'.tr();
    }

    final salaryText = workerData['salaryAmount']?.toString().trim() ?? '';
    if (salaryText.isNotEmpty) {
      final amount = Validators.parseAmount(salaryText);
      if (amount == null) {
        fieldErrors['salaryAmount'] = 'valid_amount_required'.tr();
      } else if (amount <= 0) {
        fieldErrors['salaryAmount'] = 'amount_must_be_positive'.tr();
      }
    }

    final annualLeavesText =
        workerData['annualLeaves']?.toString().trim() ?? '';
    if (annualLeavesText.isNotEmpty) {
      final annualLeaves = int.tryParse(annualLeavesText);
      if (annualLeaves == null || annualLeaves < 0 || annualLeaves > 366) {
        fieldErrors['annualLeaves'] = 'invalid_number'.tr();
        workerData['availableAnnualLeaves'] = 0;
      } else {
        workerData['annualLeaves'] = annualLeaves.toString();
        workerData['availableAnnualLeaves'] = annualLeaves;
      }
    } else {
      workerData['availableAnnualLeaves'] = 0;
    }
    workerData['leavesUsed'] = 0;

    final joiningDateText = workerData['joiningDate']?.toString().trim() ?? '';
    if (joiningDateText.isNotEmpty) {
      final joiningDate = AppDateUtils.parseDateString(joiningDateText);
      if (joiningDate == null) {
        fieldErrors['joiningDate'] = 'validation_invalid_date'.tr();
      } else {
        final today = DateTime.now();
        final todayOnly = DateTime(today.year, today.month, today.day);
        final joiningOnly = DateTime(
          joiningDate.year,
          joiningDate.month,
          joiningDate.day,
        );
        if (joiningOnly.isAfter(todayOnly)) {
          fieldErrors['joiningDate'] = 'joining_date_cannot_be_future'.tr();
        }
      }
    }

    return fieldErrors;
  }

  ({int missing, int invalidDob, int invalidGender, int duplicate})
  _validationCounts(List<Map<String, dynamic>> workers) {
    final requiredMessage = 'validation_required'.tr();
    final duplicateEmailMessage = 'validation_duplicate_email'.tr();
    final duplicateNationalIdMessage = 'validation_duplicate_national_id'.tr();

    int missing = 0;
    int invalidDob = 0;
    int invalidGender = 0;
    int duplicate = 0;

    for (final worker in workers) {
      final errors = _fieldErrors(worker);
      if (errors.values.contains(requiredMessage)) {
        missing++;
      }
      if (errors.containsKey('dob') && errors['dob'] != requiredMessage) {
        invalidDob++;
      }
      if (errors.containsKey('gender') && errors['gender'] != requiredMessage) {
        invalidGender++;
      }
      if (errors['email'] == duplicateEmailMessage ||
          errors['nationalId'] == duplicateNationalIdMessage) {
        duplicate++;
      }
    }

    return (
      missing: missing,
      invalidDob: invalidDob,
      invalidGender: invalidGender,
      duplicate: duplicate,
    );
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

  Future<bool> _processCsvData(List<List<dynamic>> rows) async {
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
      final mapped = _headerMap[header] ?? header;
      if (_requiredFields.contains(mapped)) {
        foundFields.add(mapped);
      }
    }

    final missingColumns = _requiredFields
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
        final value = row[j].toString().trim();
        if (value.isEmpty) continue;

        final mappedKey = _headerMap[headers[j]] ?? headers[j];
        String matchedKey = mappedKey;
        for (final key in workerData.keys) {
          if (key.toLowerCase() == mappedKey.toLowerCase()) {
            matchedKey = key;
            break;
          }
        }
        workerData[matchedKey] = value;
      }

      final fieldErrors = _validateWorkerData(
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
      parsedWorkers.add(workerData);
    }

    if (parsedWorkers.isEmpty) {
      setState(() {
        _validWorkers = [];
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

    final counts = _validationCounts(parsedWorkers);

    setState(() {
      _validWorkers = parsedWorkers;
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
      for (final entry in _fieldErrors(worker).entries) {
        if (entry.value == requiredMessage) {
          allMissingFieldNames.add(entry.key);
        }
      }
    }

    final duplicateWorkers = parsedWorkers.where((worker) {
      final errors = _fieldErrors(worker);
      return errors['email'] == duplicateEmailMessage ||
          errors['nationalId'] == duplicateNationalIdMessage;
    }).length;

    final hasAnyIssue =
        missingColumns.isNotEmpty || parsedWorkers.any(_hasWorkerErrors);

    if (hasAnyIssue) {
      final snackParts = <String>[
        'csv_workers_found'.tr(namedArgs: {'count': '${parsedWorkers.length}'}),
      ];
      if (missingColumns.isNotEmpty) {
        final columns = missingColumns
            .map((field) => _fieldLabels[field] ?? field)
            .join(', ');
        snackParts.add(
          'csv_missing_columns'.tr(namedArgs: {'columns': columns}),
        );
      }
      if (allMissingFieldNames.isNotEmpty) {
        final fields = allMissingFieldNames
            .map((field) => _fieldLabels[field] ?? field)
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
      final fieldErrors = _validateWorkerData(
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

      workerData['_fieldErrors'] = fieldErrors;
    }

    final counts = _validationCounts(_validWorkers);

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

    final workersWithErrors = _validWorkers.where(_hasWorkerErrors).toList();
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
          .expand((worker) => _fieldErrors(worker).keys)
          .toSet()
          .map((field) => _fieldLabels[field] ?? field)
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
      final errors = _fieldErrors(worker);
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
    _showBulkProgressDialog();

    try {
      int importedCount = workersReadyToSave.length;
      BulkWorkerResult? bulkResult;

      if (isGuest) {
        for (int i = 0; i < workersReadyToSave.length; i++) {
          final newId = 'dummy_${DateTime.now().microsecondsSinceEpoch}_$i';
          DummyData.workers.insert(0, {...workersReadyToSave[i], 'id': newId});
        }
        await DummyData.saveToPrefs();
      } else {
        workersReadyToSave = await _uploadEmbeddedWorkerMedia(
          workersReadyToSave,
        );
        bulkResult = await _firestore.addBulkWorkers(workersReadyToSave);
        importedCount = bulkResult.imported;
      }

      if (!mounted) return;
      Navigator.of(context).pop();

      final serverDuplicateCount =
          bulkResult?.skipReasons.where((reason) {
            return reason.trim().toLowerCase().startsWith('duplicate ');
          }).length ??
          0;
      final finalSkippedDuplicates = localDuplicateCount + serverDuplicateCount;

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
          workersWithErrors.isNotEmpty || (bulkResult?.skipped ?? 0) > 0;

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
      debugPrint('Add bulk worker save failed: ${_readableSaveError(error)}');
      ErrorReporter.report(
        error,
        stackTrace,
        context: 'AddBulkWorkerScreen.save',
      );
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        FlashySnackBar.show(
          context,
          message:
              '${'could_not_save_worker'.tr()}\n'
              '${_readableSaveError(error)}',
          isError: true,
          maxLines: null,
          displayDuration: const Duration(seconds: 10),
        );
      }
    } finally {
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

  bool _isDateField(String fieldKey) =>
      fieldKey == 'dob' || fieldKey == 'joiningDate';

  DateTime? _parseDate(String dateStr) {
    if (dateStr.trim().isEmpty) return null;
    return AppDateUtils.parseDateString(dateStr.trim());
  }

  bool _isAtLeast18(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age >= 18;
  }

  String _formatDateForField(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  Widget _buildDateField({
    required BuildContext context,
    required String fieldKey,
    required String currentValue,
    required String label,
    required void Function(VoidCallback) setDialogState,
    required void Function(String) onDateSelected,
  }) {
    final parsed = _parseDate(currentValue);
    final displayText = currentValue.isNotEmpty
        ? currentValue
        : 'Tap to select date';
    final hasError =
        (fieldKey == 'dob' && parsed != null && !_isAtLeast18(parsed)) ||
        (fieldKey == 'joiningDate' &&
            parsed != null &&
            parsed.isAfter(DateTime.now()));

    return GestureDetector(
      onTap: () => _showCupertinoDatePicker(
        context: context,
        fieldKey: fieldKey,
        label: label,
        currentDate: parsed,
        setDialogState: setDialogState,
        onDateSelected: onDateSelected,
      ),
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasError ? const Color(0xFFDC2626) : const Color(0xFFD1D5DB),
            width: 1.2,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.calendar,
              size: 18,
              color: Color(0xFF9CA3AF),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  displayText,
                  style: TextStyle(
                    fontSize: 15,
                    fontFamily: 'SF Pro Display',
                    fontWeight: FontWeight.w500,
                    color: currentValue.isEmpty
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF374151),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCupertinoDatePicker({
    required BuildContext context,
    required String fieldKey,
    required String label,
    required DateTime? currentDate,
    required void Function(VoidCallback) setDialogState,
    required void Function(String) onDateSelected,
  }) {
    final now = DateTime.now();
    final minimumDate = fieldKey == 'dob' ? DateTime(1920) : DateTime(2000);
    // Workers must be at least 18 years old, so a DOB cannot be later than
    // 18 years ago. Clamp only the day when the target date doesn't exist
    // (e.g. Feb 29 in a non-leap year) so the max stays the exact anniversary.
    final DateTime maximumDate;
    if (fieldKey == 'dob') {
      final targetYear = now.year - 18;
      final daysInMonth = DateTime(targetYear, now.month + 1, 0).day;
      final maxDay = now.day > daysInMonth ? daysInMonth : now.day;
      maximumDate = DateTime(targetYear, now.month, maxDay);
    } else {
      maximumDate = now;
    }
    DateTime selected =
        currentDate ?? (fieldKey == 'dob' ? DateTime(2000, 1, 1) : now);
    if (selected.isBefore(minimumDate)) {
      selected = minimumDate;
    }
    if (selected.isAfter(maximumDate)) {
      selected = maximumDate;
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Date Picker',
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
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
                                Icon(
                                  CupertinoIcons.calendar,
                                  size: 20,
                                  color: const Color(0xFF0247C4),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  label,
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
                          if (fieldKey == 'dob')
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
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
                              initialDateTime: selected,
                              minimumDate: minimumDate,
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
                                      if (fieldKey == 'dob' &&
                                          !_isAtLeast18(selected)) {
                                        FlashySnackBar.show(
                                          context,
                                          message: 'worker_must_be_18'.tr(),
                                          isError: true,
                                        );
                                        return;
                                      }
                                      if (fieldKey == 'joiningDate' &&
                                          selected.isAfter(DateTime.now())) {
                                        FlashySnackBar.show(
                                          context,
                                          message:
                                              'joining_date_cannot_be_future'
                                                  .tr(),
                                          isError: true,
                                        );
                                        return;
                                      }
                                      final dateStr = _formatDateForField(
                                        selected,
                                      );
                                      onDateSelected(dateStr);
                                      setDialogState(() {});
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

  Widget _buildCurrencyDropdown({
    required String label,
    required TextEditingController controller,
    required void Function(VoidCallback) setDialogState,
  }) {
    final currentCode = controller.text.trim().toUpperCase();

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD1D5DB), width: 1.2),
      ),
      child: PopupMenuButton<String>(
        tooltip: '',
        onSelected: (val) {
          setDialogState(() {
            controller.text = val;
          });
        },
        offset: const Offset(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
        color: const Color(0xFFFFFFFF),
        elevation: 4,
        itemBuilder: (context) {
          return CurrencyUtils.supportedCodes.map((code) {
            final isSelected = code == currentCode;
            return PopupMenuItem<String>(
              value: code,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 18,
                    color: isSelected
                        ? const Color(0xFF0247C4)
                        : const Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      LocalizationHelper.localizeCurrency(code),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isSelected
                            ? const Color(0xFF0247C4)
                            : const Color(0xFF111827),
                        fontFamily: 'SF Pro Display',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  currentCode.isEmpty
                      ? 'edit_cell_enter_value'.tr(
                          namedArgs: {'label': label},
                        )
                      : CurrencyUtils.isSupported(currentCode)
                      ? LocalizationHelper.localizeCurrency(currentCode)
                      : currentCode,
                  style: TextStyle(
                    fontSize: 15,
                    fontFamily: 'SF Pro Display',
                    color: const Color(0xFF9CA3AF),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(
                Icons.arrow_drop_down,
                color: Color(0xFF9CA3AF),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editCell(int workerIndex, String fieldKey) async {
    if (workerIndex >= _validWorkers.length) return;

    final worker = _validWorkers[workerIndex];
    final currentValue = (worker[fieldKey] ?? '').toString();
    final label = _fieldLabels[fieldKey] ?? fieldKey;

    // Load existing emails/national IDs so the dialog can reject values that
    // duplicate workers already saved in the database (not just other rows
    // in the current CSV). Only needed for these two identity fields.
    final existingEmails = <String>{};
    final existingNationalIds = <String>{};
    final bool needsExistingIdentity =
        fieldKey == 'email' || fieldKey == 'nationalId';
    if (needsExistingIdentity) {
      try {
        final existing = await _loadExistingIdentitySets();
        existingEmails.addAll(existing.emails);
        existingNationalIds.addAll(existing.nationalIds);
      } catch (_) {
        // Fall back to CSV-only duplicate checks if the DB lookup fails.
      }
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

        TextInputType? keyboardTypeForField() {
          if (fieldKey == 'phone') return TextInputType.phone;
          if (fieldKey == 'email') return TextInputType.emailAddress;
          if (fieldKey == 'salaryAmount') {
            return const TextInputType.numberWithOptions(decimal: true);
          }
          if (fieldKey == 'annualLeaves' || fieldKey == 'nationalId') {
            return TextInputType.number;
          }
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
              LengthLimitingTextInputFormatter(20),
            ];
          }
          if (fieldKey == 'email') {
            return [LengthLimitingTextInputFormatter(100)];
          }
          if (fieldKey == 'religion') {
            return [LengthLimitingTextInputFormatter(30)];
          }
          if (fieldKey == 'gender') {
            return [LengthLimitingTextInputFormatter(10)];
          }
          if (fieldKey == 'relationshipStatus') {
            return [LengthLimitingTextInputFormatter(10)];
          }
          if (fieldKey == 'name' || fieldKey == 'fatherName') {
            return [LengthLimitingTextInputFormatter(50)];
          }
          if (fieldKey == 'position') {
            return [LengthLimitingTextInputFormatter(60)];
          }
          if (fieldKey == 'type1' ||
              fieldKey == 'type2' ||
              fieldKey == 'experienceLevel' ||
              fieldKey == 'education' ||
              fieldKey == 'salaryType') {
            return [LengthLimitingTextInputFormatter(50)];
          }
          if (fieldKey == 'address') {
            return [LengthLimitingTextInputFormatter(500)];
          }
          if (fieldKey == 'annualLeaves') {
            return [
              LengthLimitingTextInputFormatter(3),
              TextInputFormatter.withFunction((oldValue, newValue) {
                if (newValue.text.isEmpty) return newValue;
                final value = int.tryParse(newValue.text);
                if (value == null || value > 366) {
                  return oldValue;
                }
                return newValue;
              }),
            ];
          }
          if (fieldKey == 'profileImage' ||
              fieldKey == 'frontId' ||
              fieldKey == 'backId' ||
              fieldKey == 'cv') {
            return [LengthLimitingTextInputFormatter(500)];
          }
          if (fieldKey == 'salaryAmount') {
            return [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              LengthLimitingTextInputFormatter(15),
            ];
          }
          if (fieldKey == 'annualLeaves') {
            return [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
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
                                if (_isDateField(fieldKey))
                                  _buildDateField(
                                    context: ctx,
                                    fieldKey: fieldKey,
                                    currentValue: controller.text,
                                    label: label,
                                    setDialogState: setDialogState,
                                    onDateSelected: (dateStr) {
                                      controller.text = dateStr;
                                    },
                                  )
                                else if (fieldKey == 'currency')
                                  _buildCurrencyDropdown(
                                    label: label,
                                    controller: controller,
                                    setDialogState: setDialogState,
                                  )
                                else if (isMediaField &&
                                    fieldKey == 'profileImage' &&
                                    !hasExistingUpload &&
                                    mediaDataUrl == null)
                                  GestureDetector(
                                    onTap: () => _pickMediaFile(),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 24,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF9FAFB),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: const Color(0xFFD1D5DB),
                                          width: 1.2,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Container(
                                            width: 56,
                                            height: 56,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEEF2FF),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.add_a_photo_rounded,
                                              size: 26,
                                              color: Color(0xFF0247C4),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            'tap_to_upload_profile_image'.tr(),
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF0247C4),
                                              fontFamily: 'SF Pro Display',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
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
                                      keyboardType: keyboardTypeForField(),
                                      inputFormatters:
                                          inputFormattersForField(),
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
                                          _normalizeEducation(val);
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
                                    } else if (fieldKey == 'salaryType') {
                                      final normalized = val
                                          .toLowerCase()
                                          .trim();
                                      const valid = {
                                        'monthly',
                                        'hourly',
                                        'contract',
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
                                    } else if (fieldKey == 'currency') {
                                      if (!CurrencyUtils.isSupported(val)) {
                                        setDialogState(() {
                                          dialogError = 'invalid_currency_value'
                                              .tr();
                                        });
                                      } else {
                                        Navigator.of(
                                          ctx,
                                        ).pop(CurrencyUtils.normalize(val));
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
                                    } else if (fieldKey == 'annualLeaves') {
                                      final annualLeaves = int.tryParse(val);
                                      if (annualLeaves == null ||
                                          annualLeaves < 0 ||
                                          annualLeaves > 366) {
                                        setDialogState(() {
                                          dialogError = 'invalid_number'.tr();
                                        });
                                      } else {
                                        Navigator.of(
                                          ctx,
                                        ).pop(annualLeaves.toString());
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
                                      } else if (!_isAtLeast18(dob)) {
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
                                          worker['${fieldKey}_name'] = val
                                              .split('/')
                                              .last;
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

    if (result != null && mounted) {
      setState(() {
        _validWorkers[workerIndex][fieldKey] = result;
        if (fieldKey == 'annualLeaves') {
          final annualLeaves = int.tryParse(result) ?? 0;
          _validWorkers[workerIndex]['availableAnnualLeaves'] = annualLeaves;
          _validWorkers[workerIndex]['leavesUsed'] = 0;
        }
        _hasUnsavedChanges = true;
      });
      await _revalidateAllWorkers();
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

    // Keep the preview row single-line even if a value somehow contains line
    // breaks (e.g. pasted multi-line text or a quoted CSV cell).
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
    const cvFallback = Icon(
      Icons.description_outlined,
      size: 18,
      color: Color(0xFF64748B),
    );
    const fallback = Icon(
      Icons.insert_drive_file_outlined,
      size: 18,
      color: Color(0xFF64748B),
    );
    if (fieldKey == 'cv' && !value.startsWith('data:image/')) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: Center(child: cvFallback),
      );
    }

    ImageProvider? provider;
    try {
      if (value.startsWith('data:image/') && value.contains(';base64,')) {
        provider = MemoryImage(base64Decode(value.split(';base64,').last));
      } else {
        final uri = Uri.tryParse(value);
        if (uri != null &&
            uri.hasAuthority &&
            (uri.scheme == 'http' || uri.scheme == 'https')) {
          provider = NetworkImage(value);
        }
      }
    } catch (_) {
      provider = null;
    }
    if (provider == null) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: Center(child: fallback),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image(
        image: provider,
        width: 24,
        height: 24,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox(
          width: 24,
          height: 24,
          child: Center(child: fallback),
        ),
      ),
    );
  }
}
