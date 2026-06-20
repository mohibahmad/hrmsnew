import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' as io;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_file_plus/open_file_plus.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../utils/snackbar_utils.dart';

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

  Future<void> _downloadTemplate() async {
    const String templateStr =
        'Full Name,Contact Number,Email Address,Father Name/Husband Name,National ID,Professed Religion,Date of Birth,Gender,Address,Relationship Status,Job Position,Employee Type,Work Model,Experience Level,Education,Salary Type,Currency,Salary Amount,Leave Policy,Annual Leaves,Sick Leaves,Casual Leaves,Joining Date,Profile Image URL\n'
        'John Doe,1234567890,john@example.com,Robert Doe,37405-1234567-1,Christianity,1990-05-15,Male,123 Street California,Single,Software Engineer,Full-Time,On-Site,Mid-Level,Bachelor\'s,Monthly,USD,5000,Standard,15,10,10,January 9, 2026,\n'
        'Jane Smith,0987654321,jane@example.com,David Smith,37405-7654321-2,Islam,1995-10-20,Female,456 Avenue New York,Married,UI Designer,Part-Time,Remote,Senior,Bachelor\'s,Monthly,USD,6000,Standard,15,10,10,January 9, 2026,https://i.pravatar.cc/150?u=jane\n'
        'Michael Johnson,1122334455,michael@example.com,Alan Johnson,37405-1122334-3,None,1988-02-28,Male,789 Road Texas,Single,Project Manager,Contract,Hybrid,Senior,Master\'s,Monthly,USD,7500,Standard,15,10,10,January 9, 2026,';

    try {
      if (io.Platform.isMacOS || io.Platform.isWindows || io.Platform.isLinux) {
        String? outputFile = await FilePicker.saveFile(
          dialogTitle: 'Save Worker Template',
          fileName: 'worker_template.csv',
          type: FileType.custom,
          allowedExtensions: ['csv'],
        );

        if (outputFile == null) return; // User canceled the picker

        final file = io.File(outputFile);
        await file.writeAsString(templateStr);

        if (mounted) {
          await OpenFile.open(file.path);
          FlashySnackBar.show(context, message: 'Template saved successfully!');
        }
      } else {
        final directory = await getTemporaryDirectory();
        final file = io.File('${directory.path}/worker_template.csv');
        await file.writeAsString(templateStr);

        if (mounted) {
          await Share.shareXFiles([
            XFile(file.path),
          ], text: 'HRMS worker template');
          await OpenFile.open(file.path);
          FlashySnackBar.show(context, message: 'Template saved successfully!');
        }
      }
    } catch (e) {
      debugPrint('Error generating template: $e');
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'could_not_save_worker'.tr(),
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
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await io.File(file.path!).readAsBytes();
      }

      if (bytes == null) return;

      // BOM strip + UTF-8 safe + normalize line endings
      var csvString = utf8.decode(bytes, allowMalformed: true);
      if (csvString.isNotEmpty && csvString.codeUnitAt(0) == 0xFEFF) {
        csvString = csvString.substring(1);
      }
      csvString = csvString.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

      final rows = Csv(dynamicTyping: false).decode(csvString);

      if (!mounted) return;
      _processCsvData(rows);
    } catch (e) {
      debugPrint('Error picking CSV: $e');
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'Error picking CSV',
          isError: true,
        );
      }
    }
  }

  void _processCsvData(List<List<dynamic>> rows) {
    if (rows.isEmpty) return;

    final headers = rows.first
        .map((e) => e.toString().trim().toLowerCase())
        .toList();

    final Map<String, String> headerMap = {
      'full name': 'name',
      'contact number': 'phone',
      'email address': 'email',
      'father name/husband name': 'fatherName',
      'father name': 'fatherName',
      'national id': 'nationalId',
      'professed religion': 'religion',
      'date of birth': 'dob',
      'relationship status': 'relationshipStatus',
      'job position': 'position',
      'employee type': 'type1',
      'work model': 'type2',
      'experience level': 'experienceLevel',
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
    };

    // Check basic required columns
    bool hasName = false;
    bool hasPhone = false;
    for (var h in headers) {
      final m = headerMap[h] ?? h;
      if (m == 'name') hasName = true;
      if (m == 'phone') hasPhone = true;
    }

    if (!hasName || !hasPhone) {
      FlashySnackBar.show(
        context,
        message:
            'CSV must contain at least "Full Name" and "Contact Number" columns.',
        isError: true,
      );
      return;
    }

    List<Map<String, dynamic>> parsedWorkers = [];

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

      // Ensure required fields
      if (workerData['name'] == null || workerData['name'].toString().isEmpty)
        continue;
      if (workerData['phone'] == null || workerData['phone'].toString().isEmpty)
        continue;

      parsedWorkers.add(workerData);
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
        message: 'No valid workers found in CSV.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final isGuest = AuthService().currentUser?.isAnonymous ?? false;

    try {
      if (isGuest) {
        for (var i = 0; i < _validWorkers.length; i++) {
          final data = _validWorkers[i];
          final newId = 'dummy_${DateTime.now().microsecondsSinceEpoch}_$i';
          DummyData.workers.insert(0, {...data, 'id': newId});
        }
      } else {
        await FirestoreService().addBulkWorkers(_validWorkers);
      }

      if (mounted) {
        FlashySnackBar.show(
          context,
          message: '${_validWorkers.length} workers added successfully!',
        );
        widget.onBack?.call();
      }
    } catch (e) {
      debugPrint('Error saving bulk workers: $e');
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
                          'Upload a CSV to add multiple workers at once'.tr(),
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
                    final bool canSave = isSaveReady && !_isSaving;

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
                                'Save All',
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
                        label: const Text("Download Template"),
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
                        label: const Text("Upload CSV File"),
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
                            color: const Color(0xFF000000).withOpacity(0.02),
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
                              color: const Color(0xFF34D399).withOpacity(0.15),
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
                                'Preview: ${_validWorkers.length} valid workers found.',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1E293B),
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Review the details below. Click "Save All" at the top to import them.',
                                style: TextStyle(
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
                            color: const Color(0xFF000000).withOpacity(0.03),
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
                                    _buildHeaderCell('Full Name', 200),
                                    _buildHeaderCell('Contact Number', 120),
                                    _buildHeaderCell('Email Address', 200),
                                    _buildHeaderCell('Job Position', 150),
                                    _buildHeaderCell('Salary Type', 120),
                                    _buildHeaderCell('Currency', 100),
                                    _buildHeaderCell('Salary Amount', 120),
                                    _buildHeaderCell('Father Name', 150),
                                    _buildHeaderCell('National ID', 150),
                                    _buildHeaderCell('Religion', 120),
                                    _buildHeaderCell('Date of Birth', 120),
                                    _buildHeaderCell('Gender', 100),
                                    _buildHeaderCell('Address', 250),
                                    _buildHeaderCell(
                                      'Relationship Status',
                                      140,
                                    ),
                                    _buildHeaderCell('Employee Type', 120),
                                    _buildHeaderCell('Work Model', 120),
                                    _buildHeaderCell('Experience Level', 130),
                                    _buildHeaderCell('Education', 150),
                                    _buildHeaderCell('Leave Policy', 120),
                                    _buildHeaderCell('Annual Leaves', 100),
                                    _buildHeaderCell('Sick Leaves', 100),
                                    _buildHeaderCell('Casual Leaves', 100),
                                    _buildHeaderCell('Joining Date', 150),
                                    _buildHeaderCell('Profile Image URL', 200),
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
                                  final salary =
                                      worker['salaryAmount']?.toString() ?? '';
                                  final currency =
                                      worker['currency']?.toString() ?? 'USD';
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
                                  final colorIdx =
                                      name.length % bgColors.length;

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
                                                    ? 'Employee'
                                                    : position,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF475569),
                                                  fontFamily: 'SF Pro Display',
                                                ),
                                                overflow: TextOverflow.ellipsis,
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
                                          worker['type1']?.toString() ?? '',
                                          120,
                                        ),
                                        _buildDataCell(
                                          worker['type2']?.toString() ?? '',
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
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
