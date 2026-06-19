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
        'name,phone,email,fatherName,nationalId,religion,dob,gender,address,relationshipStatus,position,type1,type2,experienceLevel,education,salaryType,currency,salaryAmount,leavePolicy,annualLeaves,sickLeaves,casualLeaves,joiningDate\n'
        'John Doe,1234567890,john@example.com,Robert Doe,37405-1234567-1,Christianity,1990-05-15,Male,123 Street California,Single,Software Engineer,Full-Time,On-Site,Mid-Level,Bachelor\'s,Monthly,USD,5000,Standard,15,10,10,January 9, 2026\n'
        'Jane Smith,0987654321,jane@example.com,David Smith,37405-7654321-2,Islam,1995-10-20,Female,456 Avenue New York,Married,UI Designer,Part-Time,Remote,Senior,Bachelor\'s,Monthly,USD,6000,Standard,15,10,10,January 9, 2026\n'
        'Michael Johnson,1122334455,michael@example.com,Alan Johnson,37405-1122334-3,None,1988-02-28,Male,789 Road Texas,Single,Project Manager,Contract,Hybrid,Senior,Master\'s,Monthly,USD,7500,Standard,15,10,10,January 9, 2026';

    try {
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

    // Check basic required columns
    if (!headers.contains('name') || !headers.contains('phone')) {
      FlashySnackBar.show(
        context,
        message: 'CSV must contain at least "name" and "phone" columns.',
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
        'joiningDate': 'January 9, 2026',
      };

      for (int j = 0; j < headers.length && j < row.length; j++) {
        final key = headers[j];
        final val = row[j].toString().trim();
        if (val.isNotEmpty) {
          String matchedKey = key;
          for (final existingKey in workerData.keys) {
            if (existingKey.toLowerCase() == key) {
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                              children: const [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    'Name',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Color(0xFF475569),
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'Phone',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Color(0xFF475569),
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    'Email',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Color(0xFF475569),
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'Position',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Color(0xFF475569),
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'Salary',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Color(0xFF475569),
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Table Body (ListView of items)
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _validWorkers.length,
                            separatorBuilder: (context, index) => const Divider(
                              height: 1,
                              color: Color(0xFFF1F5F9),
                            ),
                            itemBuilder: (context, index) {
                              final worker = _validWorkers[index];
                              final name = worker['name']?.toString() ?? '';
                              final phone = worker['phone']?.toString() ?? '';
                              final email = worker['email']?.toString() ?? '';
                              final position =
                                  worker['position']?.toString() ?? '';
                              final salary =
                                  worker['salaryAmount']?.toString() ?? '';
                              final currency =
                                  worker['currency']?.toString() ?? 'USD';

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
                              final colorIdx = name.length % bgColors.length;

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    // Name with Avatar
                                    Expanded(
                                      flex: 3,
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor: bgColors[colorIdx],
                                            child: Text(
                                              initials,
                                              style: TextStyle(
                                                color: textColors[colorIdx],
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                fontFamily: 'SF Pro Display',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: Color(0xFF0F172A),
                                                fontFamily: 'SF Pro Display',
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Phone
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        phone,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Color(0xFF334155),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ),
                                    // Email
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        email,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Color(0xFF334155),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // Position Chip
                                    Expanded(
                                      flex: 2,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
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
                                    // Salary
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        salary.isEmpty
                                            ? '-'
                                            : '$currency $salary',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F172A),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
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
}
