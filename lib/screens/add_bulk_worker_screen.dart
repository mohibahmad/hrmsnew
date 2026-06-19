import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' as io;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart' show Csv;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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
    final String templateStr =
        'name,email,phone,position,salaryAmount,gender,experienceLevel,education,leavePolicy\n'
        'John Doe,john@example.com,1234567890,Software Engineer,5000,Male,Mid-Level,Bachelor\'s,Standard\n'
        'Jane Smith,jane@example.com,0987654321,Designer,4500,Female,Junior,Bachelor\'s,Standard';

    try {
      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/worker_template.csv';
      final file = io.File(path);
      await file.writeAsString(templateStr);

      await Share.shareXFiles([XFile(path)], text: 'worker_template'.tr());
    } catch (e) {
      debugPrint('Error generating template: $e');
      if (mounted) {
        FlashySnackBar.show(context, message: 'could_not_save_worker'.tr(), isError: true);
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

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = io.File(file.path!).readAsBytesSync();
        }

        if (bytes != null) {
          final csvString = utf8.decode(bytes);
          final rows = Csv().decode(csvString);
          _processCsvData(rows);
        }
      }
    } catch (e) {
      debugPrint('Error picking CSV: $e');
      if (mounted) {
        FlashySnackBar.show(context, message: 'Error picking CSV', isError: true);
      }
    }
  }

  void _processCsvData(List<List<dynamic>> rows) {
    if (rows.isEmpty) return;

    final headers = rows.first.map((e) => e.toString().trim().toLowerCase()).toList();
    
    // Check basic required columns
    if (!headers.contains('name') || !headers.contains('phone')) {
      FlashySnackBar.show(context, message: 'CSV must contain at least "name" and "phone" columns.', isError: true);
      return;
    }

    List<Map<String, dynamic>> parsedWorkers = [];

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.every((element) => element.toString().trim().isEmpty)) continue;

      Map<String, dynamic> workerData = {
        'fatherName': '',
        'email': 'worker@email.com',
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
          // Map to known keys or just keep as string
          if (workerData.containsKey(key)) {
            workerData[key] = val;
          } else {
            workerData[key] = val; // allows arbitrary keys if needed
          }
        }
      }
      
      // Ensure required fields
      if (workerData['name'] == null || workerData['name'].toString().isEmpty) continue;
      if (workerData['phone'] == null || workerData['phone'].toString().isEmpty) continue;

      parsedWorkers.add(workerData);
    }

    setState(() {
      _validWorkers = parsedWorkers;
      _hasParsedFile = true;
    });
  }

  Future<void> _saveBulkWorkers() async {
    if (_validWorkers.isEmpty) {
      FlashySnackBar.show(context, message: 'No valid workers found in CSV.', isError: true);
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final isGuest = AuthService().currentUser?.isAnonymous ?? false;

    try {
      if (isGuest) {
        for (var data in _validWorkers) {
          final newId = 'dummy_${DateTime.now().millisecondsSinceEpoch}_${data['name']}';
          DummyData.workers.insert(0, {...data, 'id': newId});
        }
      } else {
        await FirestoreService().addBulkWorkers(_validWorkers);
      }

      if (mounted) {
        FlashySnackBar.show(context, message: '${_validWorkers.length} workers added successfully!');
        widget.onBack?.call();
      }
    } catch (e) {
      debugPrint('Error saving bulk workers: $e');
      if (mounted) {
        FlashySnackBar.show(context, message: 'could_not_save_worker'.tr(), isError: true);
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
                          'Upload a CSV to add multiple workers at once',
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
                Builder(builder: (context) {
                  final bool isSaveReady = _validWorkers.isNotEmpty;
                  final bool canSave = isSaveReady && !_isSaving;
                  
                  return GestureDetector(
                    onTap: canSave ? _saveBulkWorkers : null,
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      decoration: BoxDecoration(
                        color: isSaveReady ? const Color(0xFF0B50C3) : const Color(0xFFE6EAEF),
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
                                color: isSaveReady ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                    ),
                  );
                }),
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
                        label: const Text("Upload CSV File"),
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
                  ),
                  const SizedBox(height: 32),
                  if (_hasParsedFile) ...[
                    Text(
                      'Preview: ${_validWorkers.length} valid workers found.',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFEEEEEE)),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(const Color(0xFFF7F8FA)),
                          columns: const [
                            DataColumn(label: Text('Name')),
                            DataColumn(label: Text('Phone')),
                            DataColumn(label: Text('Email')),
                            DataColumn(label: Text('Position')),
                            DataColumn(label: Text('Salary')),
                          ],
                          rows: _validWorkers.map((worker) {
                            return DataRow(cells: [
                              DataCell(Text(worker['name']?.toString() ?? '')),
                              DataCell(Text(worker['phone']?.toString() ?? '')),
                              DataCell(Text(worker['email']?.toString() ?? '')),
                              DataCell(Text(worker['position']?.toString() ?? '')),
                              DataCell(Text(worker['salaryAmount']?.toString() ?? '')),
                            ]);
                          }).toList(),
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
}
