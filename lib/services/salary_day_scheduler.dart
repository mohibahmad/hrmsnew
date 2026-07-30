import 'dart:async';
import 'dart:ui';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'payroll_service.dart';
import 'preferences_service.dart';
import 'dummy_data.dart';
import 'invoice_service.dart';
import '../utils/currency_formatter.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/amount_text.dart';

/// Result of a single automated payroll run for one worker.
class AutoPayrollResult {
  final String workerId;
  final String workerName;
  final String email;
  String netSalary;
  final bool success;
  final String? error;
  final int absents;
  final int leaves;
  final int paidLeaves;
  final int unpaidLeaves;
  String absentDeduction;
  String leaveDeduction;
  bool deductionsAreTotals;
  String overtimeAmount;
  String customDeduction;
  double rawNetSalaryValue;
  final String salary;
  final String totalWorkDays;
  final String position;
  final String salaryType;
  final String? imageUrl;

  AutoPayrollResult({
    this.workerId = '',
    required this.workerName,
    required this.email,
    required this.netSalary,
    required this.success,
    this.error,
    this.absents = 0,
    this.leaves = 0,
    this.paidLeaves = 0,
    this.unpaidLeaves = 0,
    this.absentDeduction = '',
    this.leaveDeduction = '',
    this.deductionsAreTotals = false,
    this.overtimeAmount = '',
    this.customDeduction = '',
    this.rawNetSalaryValue = 0,
    this.salary = '',
    this.totalWorkDays = '',
    this.position = '',
    this.salaryType = 'Monthly',
    this.imageUrl,
  });

  AutoPayrollResult copy() => AutoPayrollResult(
    workerId: workerId,
    workerName: workerName,
    email: email,
    netSalary: netSalary,
    success: success,
    error: error,
    absents: absents,
    leaves: leaves,
    paidLeaves: paidLeaves,
    unpaidLeaves: unpaidLeaves,
    absentDeduction: absentDeduction,
    leaveDeduction: leaveDeduction,
    deductionsAreTotals: deductionsAreTotals,
    overtimeAmount: overtimeAmount,
    customDeduction: customDeduction,
    rawNetSalaryValue: rawNetSalaryValue,
    salary: salary,
    totalWorkDays: totalWorkDays,
    position: position,
    salaryType: salaryType,
    imageUrl: imageUrl,
  );
}

class PayrollRunSummary {
  final DateTime runDate;
  final int totalWorkers;
  final int successCount;
  final int failCount;
  final List<AutoPayrollResult> results;
  final String periodLabel;

  PayrollRunSummary({
    required this.runDate,
    required this.totalWorkers,
    required this.successCount,
    required this.failCount,
    required this.results,
    required this.periodLabel,
  });
}

class SalaryDayScheduler {
  static const String _lastRunKey = 'salary_day_last_run';

  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------
  static final SalaryDayScheduler _instance = SalaryDayScheduler._();
  factory SalaryDayScheduler() => _instance;
  SalaryDayScheduler._();

  // ---------------------------------------------------------------------------
  // Check & trigger
  // ---------------------------------------------------------------------------

  /// Call this at app startup. Returns `true` if a payroll run was performed
  /// (or offered to the user).
  Future<bool> checkAndRunIfDue(BuildContext context) async {
    final salaryDay = await _loadSalaryDay(context);
    if (salaryDay == null) return false; // No salary day configured.

    final today = DateTime.now();

    if (!PayrollService.isPayrollDue(today, salaryDay)) return false;

    final period = PayrollService.payrollPeriodLabel(
      PayrollService.completedPayrollMonth(referenceDate: today),
    );
    if (await _alreadyRanForPeriod(period)) return false;

    // Offer the run (semi‑auto by default).
    final summary = await runPayroll(context, autoMode: false);
    return summary != null;
  }

  /// Execute a full payroll run for all active workers.
  ///
  /// When [autoMode] is `false` (semi‑auto), a review dialog is shown before
  /// committing.  When `true`, the run completes silently in the background.
  Future<PayrollRunSummary?> runPayroll(
    BuildContext context, {
    bool autoMode = false,
  }) async {
    final isGuest =
        Provider.of<AuthService>(
          context,
          listen: false,
        ).currentUser?.isAnonymous ??
        false;

    // 1. Gather workers.
    List<Map<String, dynamic>> workers;

    if (isGuest) {
      workers = List<Map<String, dynamic>>.from(DummyData.workers);
    } else {
      try {
        final workerSnap = await Provider.of<FirestoreService>(
          context,
          listen: false,
        ).getWorkersOnce();
        workers = workerSnap.docs
            .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
            .where((w) {
              final name = (w['name'] ?? '').toString().trim();
              final workerId = (w['id'] ?? '').toString().trim();
              final email = (w['email'] ?? '').toString().trim();
              return name.isNotEmpty &&
                  (workerId.isNotEmpty || email.isNotEmpty);
            })
            .toList();
      } catch (e) {
        if (context.mounted) {
          FlashySnackBar.show(
            context,
            message: 'failed_to_load_worker_data'.tr(
              namedArgs: {'error': '$e'},
            ),
            isError: true,
          );
        }
        return null;
      }
    }

    if (workers.isEmpty) {
      if (context.mounted && !autoMode) {
        FlashySnackBar.show(
          context,
          message: 'no_workers_found'.tr(),
          isError: true,
        );
      }
      return null;
    }

    final now = DateTime.now();
    final payrollMonth = PayrollService.completedPayrollMonth(
      referenceDate: now,
    );
    final periodLabel = PayrollService.payrollPeriodLabel(payrollMonth);

    final firestoreService = Provider.of<FirestoreService>(
      context,
      listen: false,
    );
    final attendanceFutures = <Future<Map<String, int>>>[];
    for (final worker in workers) {
      final email = (worker['email'] ?? '').toString();
      final workerId = (worker['id'] ?? '').toString();
      if (!isGuest && (email.trim().isNotEmpty || workerId.isNotEmpty)) {
        attendanceFutures.add(
          firestoreService
              .getWorkerMonthlyAttendance(
                email,
                workerId: workerId,
                month: payrollMonth,
              )
              .catchError((_) {
                final att = PayrollService.attendanceCounts(worker);
                return <String, int>{
                  'absents': att['absents'] ?? 0,
                  'paidLeaves': att['paidLeaves'] ?? 0,
                  'unpaidLeaves': att['unpaidLeaves'] ?? 0,
                  'leaves': att['leaves'] ?? 0,
                };
              }),
        );
      } else {
        final att = PayrollService.attendanceCounts(worker);
        attendanceFutures.add(
          Future.value(<String, int>{
            'absents': att['absents'] ?? 0,
            'paidLeaves': att['paidLeaves'] ?? 0,
            'unpaidLeaves': att['unpaidLeaves'] ?? 0,
            'leaves': att['leaves'] ?? 0,
          }),
        );
      }
    }
    final attendanceResults = await Future.wait(attendanceFutures);

    final autoWorkDays = await firestoreService.getMonthlyWorkingDays(
      month: payrollMonth,
    );

    final results = <AutoPayrollResult>[];
    for (int i = 0; i < workers.length; i++) {
      final worker = workers[i];
      final workerId = (worker['id'] ?? '').toString();
      final name = (worker['name'] ?? '').toString();
      final email = (worker['email'] ?? '').toString();
      final salaryStr = PayrollService.currentSalaryDisplay(worker);
      final totalWorkDays = (worker['totalWorkDays'] ?? '').toString();
      final workDays = int.tryParse(totalWorkDays) ?? autoWorkDays;

      int absents = attendanceResults[i]['absents'] ?? 0;
      int paidLeaves = attendanceResults[i]['paidLeaves'] ?? 0;
      int unpaidLeaves = attendanceResults[i]['unpaidLeaves'] ?? 0;
      int leaves = attendanceResults[i]['leaves'] ?? 0;

      final absentDeductionPerDay = (worker['absentDeduction'] ?? '')
          .toString()
          .trim();
      final leaveDeductionPerDay = (worker['leaveDeduction'] ?? '')
          .toString()
          .trim();
      final effectiveAbsentDeduction = absentDeductionPerDay.isNotEmpty
          ? absentDeductionPerDay
          : '0';
      final effectiveLeaveDeduction = leaveDeductionPerDay.isNotEmpty
          ? leaveDeductionPerDay
          : '0';
      final absentDeductionTotal =
          PayrollService.extractSalary(effectiveAbsentDeduction) * absents;
      final leaveDeductionTotal =
          PayrollService.extractSalary(effectiveLeaveDeduction) * unpaidLeaves;

      final effectiveDays = workDays - absents - unpaidLeaves;

      String netSalary;
      double rawNetVal = 0;
      try {
        final calc = PayrollService.calculatePayroll(
          salary: salaryStr,
          totalWorkDays: workDays.toString(),
          daysWorked: effectiveDays > 0 ? effectiveDays.toString() : '0',
          absents: absents.toString(),
          leaves: unpaidLeaves.toString(),
          overtimeAmount: (worker['overtimeAmount'] ?? '').toString(),
          absentDeductionPerDay: effectiveAbsentDeduction,
          leaveDeductionPerDay: effectiveLeaveDeduction,
          salaryType: (worker['salaryType'] ?? 'Monthly').toString(),
        );
        netSalary = calc['formattedNet'] as String? ?? '0';
        rawNetVal = (calc['netSalary'] as num?)?.toDouble() ?? 0;
      } catch (e) {
        results.add(
          AutoPayrollResult(
            workerId: workerId,
            workerName: name,
            email: email,
            netSalary: '0',
            success: false,
            error: e.toString(),
          ),
        );
        continue;
      }

      results.add(
        AutoPayrollResult(
          workerId: workerId,
          workerName: name,
          email: email,
          netSalary: netSalary,
          rawNetSalaryValue: rawNetVal,
          success: true,
          absents: absents,
          leaves: leaves,
          paidLeaves: paidLeaves,
          unpaidLeaves: unpaidLeaves,
          absentDeduction: _editableAmount(absentDeductionTotal),
          leaveDeduction: _editableAmount(leaveDeductionTotal),
          deductionsAreTotals: true,
          overtimeAmount: (worker['overtimeAmount'] ?? '').toString(),
          salary: salaryStr,
          totalWorkDays: workDays.toString(),
          position: (worker['position'] ?? '').toString(),
          salaryType: (worker['salaryType'] ?? 'Monthly').toString(),
          imageUrl: (worker['profileImage'] ?? '').toString().isNotEmpty
              ? (worker['profileImage'] ?? '').toString()
              : null,
        ),
      );
    }

    final successCount = results.where((r) => r.success).length;
    final failCount = results.where((r) => !r.success).length;

    final summary = PayrollRunSummary(
      runDate: now,
      totalWorkers: workers.length,
      successCount: successCount,
      failCount: failCount,
      results: results,
      periodLabel: periodLabel,
    );
    var committedSummary = summary;

    if (!autoMode && context.mounted) {
      final selectedResults = await _showReviewDialog(context, summary);
      if (selectedResults == null) return null;

      final filteredSummary = PayrollRunSummary(
        runDate: summary.runDate,
        totalWorkers: selectedResults.length,
        successCount: selectedResults.where((r) => r.success).length,
        failCount: selectedResults.where((r) => !r.success).length,
        results: selectedResults,
        periodLabel: summary.periodLabel,
      );
      committedSummary = filteredSummary;

      await _commitPayrollRun(filteredSummary, isGuest, context);

      // Auto-download ZIP if more than 1 worker was paid.
      if (filteredSummary.successCount > 1 && context.mounted) {
        final paidResults = filteredSummary.results
            .where((r) => r.success)
            .toList();
        await _generateAndSaveZip(
          context,
          paidResults,
          filteredSummary.periodLabel,
        );
      }
    } else {
      await _commitPayrollRun(summary, isGuest, context);

      // Auto-download ZIP if more than 1 worker was paid.
      if (summary.successCount > 1 && context.mounted) {
        final paidResults = summary.results.where((r) => r.success).toList();
        await _generateAndSaveZip(context, paidResults, summary.periodLabel);
      }
    }

    await _markRunComplete(periodLabel);

    if (context.mounted && autoMode) {
      FlashySnackBar.show(
        context,
        message: 'payroll_run_complete'.tr(
          namedArgs: {'count': '${committedSummary.successCount}'},
        ),
      );
    }

    return committedSummary;
  }

  Future<PayrollRunSummary?> payAll(BuildContext context) async {
    final result = await runPayroll(context, autoMode: false);
    return result;
  }

  Future<int?> _loadSalaryDay(BuildContext context) async {
    final isGuest =
        Provider.of<AuthService>(
          context,
          listen: false,
        ).currentUser?.isAnonymous ??
        false;
    if (isGuest) {
      return PreferencesService.getCompanySalaryDay();
    }
    final profile = await Provider.of<FirestoreService>(
      context,
      listen: false,
    ).getUserProfile();
    final raw = profile?['salaryPaymentDay'];
    final day = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
    if (day != null && (day < 1 || day > 31)) return null;
    return day;
  }

  Future<bool> _alreadyRanForPeriod(String periodLabel) async {
    final prefs = await SharedPreferences.getInstance();
    final lastRun = prefs.getString(_lastRunKey);
    return lastRun == periodLabel;
  }

  Future<void> _markRunComplete(String periodLabel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastRunKey, periodLabel);
  }

  Future<void> _commitPayrollRun(
    PayrollRunSummary summary,
    bool isGuest,
    BuildContext context,
  ) async {
    if (isGuest) {
      for (final r in summary.results) {
        if (!r.success) continue;
        final payrollIdentity = r.workerId.isNotEmpty ? r.workerId : r.email;
        final payrollKey = '${payrollIdentity}_${summary.periodLabel}';
        final record = {
          'workerId': r.workerId,
          'name': r.workerName,
          'email': r.email,
          'status': 'Paid',
          'totalWorkDays': r.totalWorkDays,
          'absents': r.absents.toString(),
          'paidLeaves': r.paidLeaves,
          'unpaidLeaves': r.unpaidLeaves,
          'leaves': r.leaves.toString(),
          'overtimeAmount': r.overtimeAmount,
          'absentDeduction': r.absentDeduction,
          'leaveDeduction': r.leaveDeduction,
          'deductionsAreTotals': r.deductionsAreTotals,
          'salary': r.salary,
          'salaryType': r.salaryType,
          'netSalary': r.netSalary,
          'netSalaryAmount': r.rawNetSalaryValue,
          'netSalaryFormatted': r.netSalary,
          'payrollKey': payrollKey,
          'payPeriod': '${summary.periodLabel}-01',
          'cancelledAt': null,
          'lastModified': DateTime.now(),
          'createdAt': FieldValue.serverTimestamp(),
          'payrollDate': summary.runDate,
        };
        final existingPayrollIndex = DummyData.payroll.indexWhere(
          (payroll) => (payroll['payrollKey'] ?? '').toString() == payrollKey,
        );
        if (existingPayrollIndex == -1) {
          DummyData.payroll.add({
            ...record,
            'id': DateTime.now().microsecondsSinceEpoch.toString(),
          });
        } else {
          DummyData.payroll[existingPayrollIndex] = {
            ...DummyData.payroll[existingPayrollIndex],
            ...record,
          };
        }
        final netAmount = r.rawNetSalaryValue;
        if (netAmount > 0) {
          final expenseRecord = {
            'name': r.workerName,
            'date': summary.runDate,
            'category': 'Salary',
            'amount': netAmount,
            'description':
                'Salary payment for ${r.workerName} (${summary.periodLabel})',
            'payrollKey': payrollKey,
          };
          final expenseId =
              'dummy_e${DateTime.now().microsecondsSinceEpoch}_${r.email.hashCode}';
          final expenseIndex = DummyData.expenses.indexWhere(
            (expense) => (expense['payrollKey'] ?? '').toString() == payrollKey,
          );
          if (expenseIndex == -1) {
            DummyData.expenses.insert(0, {...expenseRecord, 'id': expenseId});
          } else {
            DummyData.expenses[expenseIndex] = {
              ...DummyData.expenses[expenseIndex],
              ...expenseRecord,
            };
          }
        }
      }
      await DummyData.saveToPrefs();
      return;
    }

    final firestoreService = Provider.of<FirestoreService>(
      context,
      listen: false,
    );
    final successfulResults = summary.results.where((r) => r.success).toList();

    // Prepare payroll records
    final payrollRecords = <Map<String, dynamic>>[];
    final expenseRecords = <Map<String, dynamic>>[];
    final notifications = <Map<String, dynamic>>[];

    for (final r in successfulResults) {
      final payrollIdentity = r.workerId.isNotEmpty ? r.workerId : r.email;
      final payrollKey = '${payrollIdentity}_${summary.periodLabel}';
      final record = {
        'workerId': r.workerId,
        'name': r.workerName,
        'email': r.email,
        'status': 'Paid',
        'totalWorkDays': r.totalWorkDays,
        'absents': r.absents.toString(),
        'paidLeaves': r.paidLeaves,
        'unpaidLeaves': r.unpaidLeaves,
        'leaves': r.leaves.toString(),
        'overtimeAmount': r.overtimeAmount,
        'absentDeduction': r.absentDeduction,
        'leaveDeduction': r.leaveDeduction,
        'deductionsAreTotals': r.deductionsAreTotals,
        'salary': r.salary,
        'salaryType': r.salaryType,
        'netSalary': r.netSalary,
        'netSalaryAmount': r.rawNetSalaryValue,
        'netSalaryFormatted': r.netSalary,
        'payrollKey': payrollKey,
        'payPeriod': '${summary.periodLabel}-01',
        'cancelledAt': null,
        'lastModified': DateTime.now(),
        'payrollDate': summary.runDate,
      };
      payrollRecords.add(record);

      // Prepare expense record
      final netAmount = r.rawNetSalaryValue;
      if (netAmount > 0) {
        expenseRecords.add({
          'name': r.workerName,
          'date': summary.runDate,
          'category': 'Salary',
          'amount': netAmount,
          'description':
              'Salary payment for ${r.workerName} (${summary.periodLabel})',
          'payrollKey': payrollKey,
        });
      }

      // Prepare notification
      final amount = r.netSalary;
      if (r.workerName.isNotEmpty) {
        notifications.add({
          'notificationKey': 'payroll_$payrollKey',
          'type': 'payroll_added',
          'title': 'notif_title_payroll'.tr(namedArgs: {'name': r.workerName}),
          'message': amount.isNotEmpty
              ? 'notif_msg_payroll_amount'.tr(
                  namedArgs: {'amount': '\$$amount', 'name': r.workerName},
                )
              : 'notif_msg_payroll'.tr(namedArgs: {'name': r.workerName}),
          'data': {
            'name': r.workerName,
            'amount': amount.isNotEmpty ? '\$$amount' : '',
          },
        });
      }
    }

    // Execute batch writes in parallel
    await Future.wait([
      firestoreService.addBulkPayrollRecords(payrollRecords),
      firestoreService.addBulkExpenses(expenseRecords),
      firestoreService.addBulkNotifications(notifications),
    ]);
  }

  /// Generates individual PDF invoices for selected results and saves as a ZIP.
  Future<void> _generateAndSaveZip(
    BuildContext context,
    List<AutoPayrollResult> selected,
    String periodLabel,
  ) async {
    if (selected.isEmpty) return;

    // Show loading snackbar
    if (context.mounted) {
      FlashySnackBar.show(context, message: 'generating_invoices'.tr());
    }

    try {
      final archive = Archive();
      final now = DateTime.now();
      final payPeriod = periodLabel.isNotEmpty
          ? periodLabel
          : '${now.year}-${now.month.toString().padLeft(2, '0')}';

      for (final r in selected) {
        if (!r.success) continue;
        final enteredSalary = PayrollService.extractSalary(r.salary);
        final rawSalary = r.salaryType.trim().toLowerCase() == 'annual'
            ? enteredSalary / 12
            : enteredSalary;
        final workDays = int.tryParse(r.totalWorkDays) ?? 22;
        final dailyRate = workDays > 0
            ? (rawSalary / workDays).toStringAsFixed(2)
            : '0';
        final absentsInt = r.absents;
        final leavesInt = r.leaves;
        final deductibleLeaves = r.unpaidLeaves;
        final absentDeductionAmt = PayrollService.extractSalary(
          r.absentDeduction,
        );
        final leaveDeductionAmt = PayrollService.extractSalary(
          r.leaveDeduction,
        );
        final overtimeAmt = PayrollService.extractSalary(r.overtimeAmount);
        final absentTotal = r.deductionsAreTotals
            ? absentDeductionAmt
            : absentDeductionAmt * absentsInt;
        final leaveTotal = r.deductionsAreTotals
            ? leaveDeductionAmt
            : leaveDeductionAmt * deductibleLeaves;
        final totalDeductions = absentTotal + leaveTotal;
        final effectiveDays = (workDays - absentsInt - leavesInt).clamp(
          0,
          workDays,
        );
        final grossPay = rawSalary.toStringAsFixed(2);

        final pdfBytes = await InvoiceService.generatePayrollInvoice(
          employeeName: r.workerName,
          email: r.email,
          position: r.position,
          payPeriod: payPeriod,
          totalWorkDays: r.totalWorkDays,
          daysWorked: effectiveDays.toString(),
          absents: absentsInt.toString(),
          leaves: leavesInt.toString(),
          overtimeAmount: overtimeAmt > 0
              ? 'Rs ${overtimeAmt.toStringAsFixed(0)}'
              : '0',
          salary: r.salary,
          dailyRate:
              'Rs ${double.tryParse(dailyRate)?.toStringAsFixed(0) ?? dailyRate}',
          grossPay:
              'Rs ${double.tryParse(grossPay)?.toStringAsFixed(0) ?? grossPay}',
          overtimePay: overtimeAmt > 0
              ? 'Rs ${overtimeAmt.toStringAsFixed(0)}'
              : '0',
          absentDeduction: absentTotal > 0
              ? 'Rs ${absentTotal.toStringAsFixed(0)}'
              : '0',
          leaveDeduction: leaveTotal > 0
              ? 'Rs ${leaveTotal.toStringAsFixed(0)}'
              : '0',
          totalDeductions: totalDeductions > 0
              ? 'Rs ${totalDeductions.toStringAsFixed(0)}'
              : '0',
          netSalary: r.netSalary,
        );

        final safeName = r.workerName
            .replaceAll(RegExp(r'[^\w\s]'), '')
            .replaceAll(' ', '_');
        archive.addFile(
          ArchiveFile(
            '${safeName}_invoice_$payPeriod.pdf',
            pdfBytes.length,
            pdfBytes,
          ),
        );
      }

      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes.isEmpty) throw Exception('ZIP encoding failed');

      final zipData = Uint8List.fromList(zipBytes);
      final fileName = 'payroll_invoices_$payPeriod.zip';

      final result = await FilePicker.saveFile(
        dialogTitle: 'save_payroll_invoices_zip'.tr(),
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: zipData,
      );

      if (result != null) {
        final file = File(result);
        await file.writeAsBytes(zipData);
        if (context.mounted) {
          FlashySnackBar.show(
            context,
            message: 'zip_saved'.tr(namedArgs: {'fileName': fileName}),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        FlashySnackBar.show(
          context,
          message: 'failed_to_generate_zip'.tr(namedArgs: {'error': '$e'}),
          isError: true,
        );
      }
    }
  }

  /// Returns the list of selected results, or null if cancelled.
  Future<List<AutoPayrollResult>?> _showReviewDialog(
    BuildContext context,
    PayrollRunSummary summary,
  ) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 600 ? screenWidth * 0.95 : 720.0;
    final dialogHeight = screenWidth < 600 ? 620.0 : 700.0;

    String searchQuery = '';
    String positionFilter = 'All';
    Set<int> selectedIndices = {};
    final Map<int, TextEditingController> overtimeControllers = {};

    for (int i = 0; i < summary.results.length; i++) {
      if (summary.results[i].success) {
        selectedIndices.add(i);
      }
    }

    final allPositions = <String>{
      for (final r in summary.results)
        if (r.position.trim().isNotEmpty) r.position.trim(),
    }.toList();
    allPositions.sort();

    return showGeneralDialog<List<AutoPayrollResult>>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'PayrollReviewDialog',
      barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.3),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 12 * animation.value,
            sigmaY: 12 * animation.value,
          ),
          child: FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: curve,
              child: StatefulBuilder(
                builder: (context, setDialogState) {
                  Widget avatarInitials(String name, Color color) {
                    return Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    );
                  }

                  List<AutoPayrollResult> posFiltered;
                  if (positionFilter == 'All') {
                    posFiltered = summary.results;
                  } else {
                    posFiltered = summary.results
                        .where(
                          (r) =>
                              r.position.toLowerCase().trim() ==
                              positionFilter.toLowerCase().trim(),
                        )
                        .toList();
                  }

                  final filteredResults = searchQuery.isEmpty
                      ? posFiltered
                      : posFiltered
                            .where(
                              (r) =>
                                  r.workerName.toLowerCase().contains(
                                    searchQuery.toLowerCase(),
                                  ) ||
                                  r.email.toLowerCase().contains(
                                    searchQuery.toLowerCase(),
                                  ),
                            )
                            .toList();

                  // Count only filtered workers that are also selected.
                  final filteredSelectedCount = filteredResults
                      .where(
                        (r) => selectedIndices.contains(
                          summary.results.indexOf(r),
                        ),
                      )
                      .length;
                  final selectedCount = selectedIndices
                      .where(
                        (index) =>
                            index >= 0 &&
                            index < summary.results.length &&
                            summary.results[index].success,
                      )
                      .length;

                  return Dialog(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    insetPadding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: Container(
                        width: dialogWidth,
                        height: dialogHeight,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF0F172A,
                              ).withValues(alpha: 0.12),
                              blurRadius: 32,
                              offset: const Offset(0, 16),
                            ),
                            BoxShadow(
                              color: const Color(
                                0xFF0F172A,
                              ).withValues(alpha: 0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // ── Header ────────────────────────────────────────────
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 14.0,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        'payroll_run_review'.tr(),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF111827),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Close button
                                  GestureDetector(
                                    onTap: () => Navigator.of(context).pop(),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      child: const Icon(
                                        Icons.close,
                                        size: 18,
                                        color: Color(0xFF9CA3AF),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // ── Search Bar (Full Width, just outline) ─────────
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: SizedBox(
                                height: 38,
                                child: TextField(
                                  onChanged: (val) {
                                    setDialogState(() => searchQuery = val);
                                  },
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontFamily: 'SF Pro Display',
                                    color: Color(0xFF111827),
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'search_workers_hint'.tr(),
                                    hintStyle: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFFBDBDBD),
                                      fontFamily: 'SF Pro Display',
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      size: 18,
                                      color: Color(0xFF6B7280),
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFF9FAFB),
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                      horizontal: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFE5E7EB),
                                        width: 1,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFE5E7EB),
                                        width: 1,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF0F70FF),
                                        width: 1.5,
                                      ),
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ),

                            // ── Filter Chips ─────────────────────────────────
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  8,
                                  24,
                                  0,
                                ),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ChoiceChip(
                                        label: Text('all_filter'.tr()),
                                        selected: positionFilter == 'All',
                                        onSelected: (_) {
                                          setDialogState(
                                            () => positionFilter = 'All',
                                          );
                                        },
                                        selectedColor: const Color(0xFF0C51C1),
                                        backgroundColor: Colors.white,
                                        checkmarkColor: Colors.transparent,
                                        showCheckmark: false,
                                        side: positionFilter == 'All'
                                            ? null
                                            : const BorderSide(
                                                color: Color(0xFFE5E7EB),
                                              ),
                                        labelStyle: TextStyle(
                                          color: positionFilter == 'All'
                                              ? Colors.white
                                              : const Color(0xFF111827),
                                          fontSize: 12,
                                          fontWeight: positionFilter == 'All'
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      ...allPositions.map(
                                        (pos) => Padding(
                                          padding: const EdgeInsets.only(
                                            left: 8,
                                          ),
                                          child: ChoiceChip(
                                            label: Text(pos),
                                            selected: positionFilter == pos,
                                            onSelected: (_) {
                                              setDialogState(
                                                () => positionFilter = pos,
                                              );
                                            },
                                            selectedColor: const Color(
                                              0xFF0C51C1,
                                            ),
                                            backgroundColor: Colors.white,
                                            checkmarkColor: Colors.transparent,
                                            showCheckmark: false,
                                            side: positionFilter == pos
                                                ? null
                                                : const BorderSide(
                                                    color: Color(0xFFE5E7EB),
                                                  ),
                                            labelStyle: TextStyle(
                                              color: positionFilter == pos
                                                  ? Colors.white
                                                  : const Color(0xFF111827),
                                              fontSize: 12,
                                              fontWeight: positionFilter == pos
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                              fontFamily: 'SF Pro Display',
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // ── Selection Status ─────────────────────────────────
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                14,
                                24,
                                12,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEEF2FF),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          '$filteredSelectedCount ${'selected'.tr()}',
                                          style: const TextStyle(
                                            color: Color(0xFF0247C4),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'processing_for_cycle'.tr(
                                          namedArgs: {
                                            'period': summary.periodLabel,
                                          },
                                        ),
                                        style: const TextStyle(
                                          color: Color(0xFF6B7280),
                                          fontSize: 13,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ],
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      setDialogState(() {
                                        final filteredIndices = filteredResults
                                            .map(
                                              (r) => summary.results.indexOf(r),
                                            )
                                            .toSet();
                                        final allFilteredSelected =
                                            filteredIndices.every(
                                              (i) =>
                                                  selectedIndices.contains(i),
                                            );
                                        if (allFilteredSelected) {
                                          selectedIndices.removeAll(
                                            filteredIndices,
                                          );
                                        } else {
                                          selectedIndices.addAll(
                                            filteredIndices,
                                          );
                                        }
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            filteredResults.every(
                                              (r) => selectedIndices.contains(
                                                summary.results.indexOf(r),
                                              ),
                                            )
                                            ? const Color(0xFFFEE2E2)
                                            : const Color(0xFFEEF2FF),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            filteredResults.every(
                                                  (r) =>
                                                      selectedIndices.contains(
                                                        summary.results.indexOf(
                                                          r,
                                                        ),
                                                      ),
                                                )
                                                ? Icons.deselect
                                                : Icons.select_all,
                                            size: 15,
                                            color:
                                                filteredResults.every(
                                                  (r) =>
                                                      selectedIndices.contains(
                                                        summary.results.indexOf(
                                                          r,
                                                        ),
                                                      ),
                                                )
                                                ? const Color(0xFFEF4444)
                                                : const Color(0xFF0247C4),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            filteredResults.every(
                                                  (r) =>
                                                      selectedIndices.contains(
                                                        summary.results.indexOf(
                                                          r,
                                                        ),
                                                      ),
                                                )
                                                ? 'deselect_all'.tr()
                                                : 'select_all'.tr(),
                                            style: TextStyle(
                                              color:
                                                  filteredResults.every(
                                                    (r) => selectedIndices
                                                        .contains(
                                                          summary.results
                                                              .indexOf(r),
                                                        ),
                                                  )
                                                  ? const Color(0xFFEF4444)
                                                  : const Color(0xFF0247C4),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
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

                            Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              height: 1,
                              color: const Color(0xFFE5E7EB),
                            ),

                            // ── Worker List ──────────────────────────────────────
                            Expanded(
                              child: filteredResults.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.search_off_rounded,
                                            size: 48,
                                            color: Colors.grey.shade300,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'no_results'.tr(),
                                            style: const TextStyle(
                                              color: Color(0xFF64748B),
                                              fontFamily: 'SF Pro Display',
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.fromLTRB(
                                        24,
                                        10,
                                        24,
                                        10,
                                      ),
                                      itemCount: filteredResults.length,
                                      itemBuilder: (_, i) {
                                        final r = filteredResults[i];
                                        final originalIndex = summary.results
                                            .indexOf(r);
                                        final isSelected = selectedIndices
                                            .contains(originalIndex);
                                        // Avatar color based on name
                                        final avatarColors = [
                                          const Color(0xFFE4F0FF),
                                          const Color(0xFFEFE4FF),
                                          const Color(0xFFE4FFE8),
                                          const Color(0xFFFFE4E4),
                                          const Color(0xFFFFF0E4),
                                        ];
                                        final avatarTextColors = [
                                          const Color(0xFF0F70FF),
                                          const Color(0xFF6A00FF),
                                          const Color(0xFF22C55E),
                                          const Color(0xFFEF4444),
                                          const Color(0xFFF97316),
                                        ];
                                        final colorIdx =
                                            r.workerName.hashCode.abs() % 5;

                                        // Determine worker type for badge
                                        final posLower = r.position
                                            .toLowerCase()
                                            .trim();
                                        final stLower = r.salaryType
                                            .toLowerCase()
                                            .trim();
                                        final isContractorWorker =
                                            posLower.contains('contract') ||
                                            posLower.contains('freelance') ||
                                            stLower.contains('contract') ||
                                            stLower.contains('freelance') ||
                                            (stLower != 'monthly' &&
                                                stLower.isNotEmpty);
                                        final typeLabel = isContractorWorker
                                            ? 'type_contractor'.tr()
                                            : 'type_full_time'.tr();

                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: isSelected
                                                    ? const Color(
                                                        0xFF0F70FF,
                                                      ).withValues(alpha: 0.3)
                                                    : const Color(0xFFE5E7EB),
                                                width: 1.2,
                                              ),
                                            ),
                                            child: InkWell(
                                              onTap: () async {
                                                final controllerKeys = [
                                                  originalIndex * 10,
                                                  originalIndex * 10 + 1,
                                                  originalIndex * 10 + 2,
                                                ];
                                                for (final key
                                                    in controllerKeys) {
                                                  overtimeControllers
                                                      .remove(key)
                                                      ?.dispose();
                                                }
                                                final updated =
                                                    await _showWorkerPayrollDetails(
                                                      context: context,
                                                      result: r.copy(),
                                                      originalIndex:
                                                          originalIndex,
                                                      overtimeControllers:
                                                          overtimeControllers,
                                                      summary: summary,
                                                      dialogWidth: dialogWidth,
                                                      dialogHeight:
                                                          dialogHeight,
                                                    );
                                                for (final key
                                                    in controllerKeys) {
                                                  overtimeControllers
                                                      .remove(key)
                                                      ?.dispose();
                                                }
                                                if (updated != null) {
                                                  summary.results[originalIndex] =
                                                      updated;
                                                }
                                                if (context.mounted) {
                                                  setDialogState(() {});
                                                }
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 14,
                                                      horizontal: 14,
                                                    ),
                                                child: Row(
                                                  children: [
                                                    // Custom Checkbox (tiny, fits inside container)
                                                    GestureDetector(
                                                      onTap: () {
                                                        setDialogState(() {
                                                          if (isSelected) {
                                                            selectedIndices
                                                                .remove(
                                                                  originalIndex,
                                                                );
                                                          } else {
                                                            selectedIndices.add(
                                                              originalIndex,
                                                            );
                                                          }
                                                        });
                                                      },
                                                      child: Container(
                                                        width: 12,
                                                        height: 12,
                                                        decoration: BoxDecoration(
                                                          border: Border.all(
                                                            color: isSelected
                                                                ? const Color(
                                                                    0xFF0F70FF,
                                                                  )
                                                                : const Color(
                                                                    0xFFD1D5DB,
                                                                  ),
                                                            width: 1,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                2,
                                                              ),
                                                          color: isSelected
                                                              ? const Color(
                                                                  0xFF0F70FF,
                                                                )
                                                              : Colors
                                                                    .transparent,
                                                        ),
                                                        child: isSelected
                                                            ? const Icon(
                                                                Icons.check,
                                                                size: 8,
                                                                color: Colors
                                                                    .white,
                                                              )
                                                            : null,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 14),
                                                    // Avatar with image or initials (circular, no dot)
                                                    Container(
                                                      width: 44,
                                                      height: 44,
                                                      decoration: BoxDecoration(
                                                        color:
                                                            avatarColors[colorIdx
                                                                    .abs() %
                                                                5],
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child:
                                                          r.imageUrl != null &&
                                                              r
                                                                  .imageUrl!
                                                                  .isNotEmpty
                                                          ? ClipRRect(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    22,
                                                                  ),
                                                              child: Image.network(
                                                                r.imageUrl!,
                                                                width: 44,
                                                                height: 44,
                                                                fit: BoxFit
                                                                    .cover,
                                                                errorBuilder:
                                                                    (
                                                                      _,
                                                                      __,
                                                                      ___,
                                                                    ) => avatarInitials(
                                                                      r.workerName,
                                                                      avatarTextColors[colorIdx
                                                                              .abs() %
                                                                          5],
                                                                    ),
                                                                loadingBuilder:
                                                                    (
                                                                      _,
                                                                      child,
                                                                      progress,
                                                                    ) {
                                                                      if (progress ==
                                                                          null)
                                                                        return child;
                                                                      return avatarInitials(
                                                                        r.workerName,
                                                                        avatarTextColors[colorIdx.abs() %
                                                                            5],
                                                                      );
                                                                    },
                                                              ),
                                                            )
                                                          : avatarInitials(
                                                              r.workerName,
                                                              avatarTextColors[colorIdx
                                                                      .abs() %
                                                                  5],
                                                            ),
                                                    ),
                                                    const SizedBox(width: 14),
                                                    // Name + type badge + email
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Row(
                                                            children: [
                                                              Flexible(
                                                                child: Text(
                                                                  r.workerName,
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        15,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    fontFamily:
                                                                        'SF Pro Display',
                                                                    color: Color(
                                                                      0xFF111827,
                                                                    ),
                                                                  ),
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                              Container(
                                                                padding:
                                                                    const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          7,
                                                                      vertical:
                                                                          2,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color: const Color(
                                                                    0xFFF3F4F6,
                                                                  ),
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        4,
                                                                      ),
                                                                ),
                                                                child: Text(
                                                                  typeLabel,
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        10,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    color: Color(
                                                                      0xFF4B5563,
                                                                    ),
                                                                    letterSpacing:
                                                                        0.5,
                                                                    fontFamily:
                                                                        'SF Pro Display',
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          const SizedBox(
                                                            height: 5,
                                                          ),
                                                          Row(
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .mail_outline_rounded,
                                                                size: 13,
                                                                color: Colors
                                                                    .grey
                                                                    .shade400,
                                                              ),
                                                              const SizedBox(
                                                                width: 4,
                                                              ),
                                                              Flexible(
                                                                child: Text(
                                                                  r.email.isNotEmpty
                                                                      ? r.email
                                                                      : 'no_email'
                                                                            .tr(),
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        13,
                                                                    color: Color(
                                                                      0xFF6B7280,
                                                                    ),
                                                                    fontFamily:
                                                                        'SF Pro Display',
                                                                  ),
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    // Salary block
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .end,
                                                      children: [
                                                        Text(
                                                          'net_salary'.tr(),
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: Color(
                                                              0xFF6B7280,
                                                            ),
                                                            fontFamily:
                                                                'SF Pro Display',
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 5,
                                                        ),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 14,
                                                                vertical: 6,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: r.success
                                                                ? const Color(
                                                                    0xFFF0F6FF,
                                                                  )
                                                                : const Color(
                                                                    0xFFFEE2E2,
                                                                  ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  20,
                                                                ),
                                                          ),
                                                          child: Text(
                                                            AmountText.formatCompact(
                                                              r.netSalary,
                                                            ),
                                                            style: TextStyle(
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              fontFamily:
                                                                  'SF Pro Display',
                                                              color: r.success
                                                                  ? const Color(
                                                                      0xFF0F70FF,
                                                                    )
                                                                  : const Color(
                                                                      0xFFEF4444,
                                                                    ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(width: 6),
                                                    // Chevron right
                                                    const Icon(
                                                      Icons
                                                          .chevron_right_rounded,
                                                      size: 22,
                                                      color: Color(0xFF9CA3AF),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),

                            // ── Bottom Footer ───────────────────────────────────
                            Container(
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                border: Border(
                                  top: BorderSide(
                                    color: Color(0xFFE5E7EB),
                                    width: 1,
                                  ),
                                ),
                              ),
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                12,
                                24,
                                14,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  // Total Disbursement
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'total_disbursement'.tr(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF6B7280),
                                          letterSpacing: 0.5,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        () {
                                          double total = 0;
                                          String prefix = '';
                                          for (final idx in selectedIndices) {
                                            if (idx < 0 ||
                                                idx >= summary.results.length) {
                                              continue;
                                            }
                                            final r = summary.results[idx];
                                            if (r.success &&
                                                r.rawNetSalaryValue.isFinite) {
                                              total += r.rawNetSalaryValue;
                                              if (prefix.isEmpty) {
                                                prefix =
                                                    PayrollService.getCurrencyPrefix(
                                                      r.netSalary,
                                                    );
                                                if (prefix.isEmpty) {
                                                  prefix = '\$';
                                                }
                                              }
                                            }
                                          }
                                          return '$prefix ${PayrollService.formatNumber(total)}';
                                        }(),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF111827),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      // Save Draft button
                                      GestureDetector(
                                        onTap: () =>
                                            Navigator.of(context).pop(),
                                        child: Container(
                                          height: 48,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 22,
                                          ),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
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
                                      const SizedBox(width: 14),
                                      // Pay All button
                                      GestureDetector(
                                        onTap: selectedCount == 0
                                            ? null
                                            : () {
                                                final selected = selectedIndices
                                                    .where(
                                                      (index) =>
                                                          index >= 0 &&
                                                          index <
                                                              summary
                                                                  .results
                                                                  .length,
                                                    )
                                                    .map(
                                                      (index) => summary
                                                          .results[index],
                                                    )
                                                    .where((r) => r.success)
                                                    .toList();
                                                Navigator.of(
                                                  context,
                                                ).pop(selected);
                                              },
                                        child: Container(
                                          height: 48,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 22,
                                          ),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: selectedCount == 0
                                                ? const Color(
                                                    0xFF0247C4,
                                                  ).withValues(alpha: 0.4)
                                                : const Color(0xFF0247C4),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            boxShadow: selectedCount > 0
                                                ? [
                                                    BoxShadow(
                                                      color: const Color(
                                                        0xFF0247C4,
                                                      ).withValues(alpha: 0.2),
                                                      blurRadius: 8,
                                                      offset: const Offset(
                                                        0,
                                                        4,
                                                      ),
                                                    ),
                                                  ]
                                                : null,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.check_circle_outline,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'pay_all_count'.tr(
                                                  namedArgs: {
                                                    'count': '$selectedCount',
                                                  },
                                                ),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'SF Pro Display',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
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
  }

  /// Opens a separate dialog with the Payroll Details for a specific worker.
  /// Uses the same dialog dimensions as the parent review dialog for consistency.
  Future<AutoPayrollResult?> _showWorkerPayrollDetails({
    required BuildContext context,
    required AutoPayrollResult result,
    required int originalIndex,
    required Map<int, TextEditingController> overtimeControllers,
    required PayrollRunSummary summary,
    required double dialogWidth,
    required double dialogHeight,
  }) {
    final totalWorkDays = int.tryParse(result.totalWorkDays) ?? 22;
    final presents = totalWorkDays - result.absents - result.leaves;

    return showDialog<AutoPayrollResult>(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.3),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: StatefulBuilder(
          builder: (detailContext, setDetailState) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 30,
            ),
            child: Center(
              child: Container(
                width: dialogWidth,
                height: dialogHeight,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.12),
                      blurRadius: 32,
                      offset: const Offset(0, 16),
                    ),
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // ── Scrollable Content ─────────────────────────────
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ── Top Bar: Back Button + Title ────────────
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () =>
                                      Navigator.of(detailContext).pop(),
                                  child: const Icon(
                                    Icons.arrow_back_rounded,
                                    color: Color(0xFF000000),
                                    size: 22,
                                  ),
                                ),
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      'payroll_details_title'
                                          .tr(namedArgs: {'name': ''})
                                          .trim(),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF111827),
                                        fontFamily: 'SF Pro Display',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 22),
                              ],
                            ),

                            const SizedBox(height: 28),

                            // ── 1. Header: Avatar + Name/Email + Total Net Payment ────
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    // Large Avatar with image or initials (circular)
                                    Container(
                                      width: 60,
                                      height: 60,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF0F70FF),
                                        shape: BoxShape.circle,
                                      ),
                                      child:
                                          result.imageUrl != null &&
                                              result.imageUrl!.isNotEmpty
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(30),
                                              child: Image.network(
                                                result.imageUrl!,
                                                width: 60,
                                                height: 60,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    Center(
                                                      child: Text(
                                                        result
                                                                .workerName
                                                                .isNotEmpty
                                                            ? result
                                                                  .workerName[0]
                                                                  .toUpperCase()
                                                            : '?',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 28,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontFamily:
                                                              'SF Pro Display',
                                                        ),
                                                      ),
                                                    ),
                                                loadingBuilder: (_, child, progress) {
                                                  if (progress == null)
                                                    return child;
                                                  return Center(
                                                    child: Text(
                                                      result
                                                              .workerName
                                                              .isNotEmpty
                                                          ? result.workerName[0]
                                                                .toUpperCase()
                                                          : '?',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 28,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontFamily:
                                                            'SF Pro Display',
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            )
                                          : Center(
                                              child: Text(
                                                result.workerName.isNotEmpty
                                                    ? result.workerName[0]
                                                          .toUpperCase()
                                                    : '?',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'SF Pro Display',
                                                ),
                                              ),
                                            ),
                                    ),
                                    const SizedBox(width: 16),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          result.workerName,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF111827),
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          result.email.isNotEmpty
                                              ? result.email
                                              : 'no_email'.tr(),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFF6B7280),
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'total_net_payment'.tr(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF6B7280),
                                        letterSpacing: 0.8,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      AmountText.formatCompact(
                                        result.netSalary,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0247C4),
                                        letterSpacing: -1.0,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            const SizedBox(height: 32),

                            // ── 2. 3-Column Metrics Grid ───────────────────────────
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _metricColumn(
                                    title: 'attendance'.tr(),
                                    icon: Icons.calendar_today_outlined,
                                    iconColor: const Color(0xFF3B82F6),
                                    rows: [
                                      _metricRow(
                                        'presents'.tr(),
                                        '$presents ${'days_suffix'.tr()}',
                                        const Color(0xFFF9FAFB),
                                        const Color(0xFF6B7280),
                                        const Color(0xFF111827),
                                      ),
                                      _metricRow(
                                        'absents'.tr(),
                                        '${result.absents} ${'days_suffix'.tr()}',
                                        const Color(0xFFF9FAFB),
                                        const Color(0xFF6B7280),
                                        const Color(0xFF111827),
                                      ),
                                      _metricRow(
                                        'leaves'.tr(),
                                        '${result.leaves} ${'days_suffix'.tr()}',
                                        const Color(0xFFF9FAFB),
                                        const Color(0xFF6B7280),
                                        const Color(0xFF111827),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: _metricColumn(
                                    title: 'earnings'.tr(),
                                    icon: Icons.payments_outlined,
                                    iconColor: const Color(0xFF10B981),
                                    rows: [
                                      _metricRow(
                                        'base_salary'.tr(),
                                        result.salary.isNotEmpty
                                            ? AmountText.formatCompact(
                                                result.salary,
                                              )
                                            : '\$0',
                                        const Color(0xFFF9FAFB),
                                        const Color(0xFF6B7280),
                                        const Color(0xFF111827),
                                      ),
                                      _metricRow(
                                        'working_days'.tr(),
                                        result.totalWorkDays,
                                        const Color(0xFFF9FAFB),
                                        const Color(0xFF6B7280),
                                        const Color(0xFF111827),
                                      ),
                                      _metricRow(
                                        'overtime_bonus'.tr(),
                                        result.overtimeAmount.isNotEmpty
                                            ? AmountText.formatCompact(
                                                result.overtimeAmount,
                                              )
                                            : '\$0.00',
                                        const Color(0xFFECFDF5),
                                        const Color(0xFF10B981),
                                        const Color(0xFF10B981),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: _metricColumn(
                                    title: 'deductions'.tr(),
                                    icon: Icons.remove_circle_outline,
                                    iconColor: const Color(0xFFEF4444),
                                    rows: [
                                      _editableDeductionRow(
                                        label: 'absent_deduction'.tr(),
                                        value: result.absentDeduction,
                                        controllerKey: originalIndex * 10 + 1,
                                        controllers: overtimeControllers,
                                        onChanged: (val) {
                                          result.absentDeduction = val;
                                          _recalcWithDeductions(
                                            result,
                                            result.customDeduction,
                                            () => setDetailState(() {}),
                                          );
                                        },
                                      ),
                                      _editableDeductionRow(
                                        label: 'leave_deduction'.tr(),
                                        value: result.leaveDeduction,
                                        controllerKey: originalIndex * 10 + 2,
                                        controllers: overtimeControllers,
                                        onChanged: (val) {
                                          result.leaveDeduction = val;
                                          _recalcWithDeductions(
                                            result,
                                            result.customDeduction,
                                            () => setDetailState(() {}),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 32),

                            // ── 3. Adjust Overtime Section ─────────────────────────
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                  color: const Color(0xFFF3F4F6),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.01),
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
                                      border: Border.all(
                                        color: const Color(0xFFE5E7EB),
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.more_time,
                                      color: Color(0xFF0F70FF),
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'adjust_overtime'.tr(),
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF111827),
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'apply_additional_hours'.tr(),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFF6B7280),
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _buildOvertimeInlineField(
                                    result,
                                    originalIndex,
                                    setDetailState,
                                    overtimeControllers,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── 4. Fixed Footer ─────────────────────────────────────
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          top: BorderSide(color: Color(0xFFE5E7EB), width: 1),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (result.success)
                            GestureDetector(
                              onTap: () => Navigator.of(context).pop(result),
                              child: Container(
                                height: 48,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0247C4),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF0247C4,
                                      ).withValues(alpha: 0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.check_circle_outline,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'confirm_review'.tr(),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _metricColumn({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> rows,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6B7280),
                letterSpacing: 0.8,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ...rows.map(
          (row) =>
              Padding(padding: const EdgeInsets.only(bottom: 12), child: row),
        ),
      ],
    );
  }

  Widget _metricRow(
    String label,
    String value,
    Color bgColor,
    Color labelColor,
    Color valueColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: labelColor,
              fontFamily: 'SF Pro Display',
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: valueColor,
                fontFamily: 'SF Pro Display',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  /// Editable custom deduction row shown above Absent/Leave deduction.
  /// Editable deduction row for absent/leave deduction per day.
  Widget _editableDeductionRow({
    required String label,
    required String value,
    required int controllerKey,
    required Map<int, TextEditingController> controllers,
    required void Function(String) onChanged,
  }) {
    if (!controllers.containsKey(controllerKey)) {
      controllers[controllerKey] = TextEditingController(
        text: value.replaceAll(RegExp(r'[^0-9.]'), ''),
      );
    }
    final controller = controllers[controllerKey]!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA), width: 1),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFEF4444),
                fontFamily: 'SF Pro Display',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                CommaCurrencyFormatter(),
                LengthLimitingTextInputFormatter(14),
              ],
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: 'SF Pro Display',
                color: Color(0xFFEF4444),
              ),
              textAlign: TextAlign.end,
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: TextStyle(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'SF Pro Display',
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(
                    color: Color(0xFFFECACA),
                    width: 1,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(
                    color: Color(0xFFFECACA),
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(
                    color: Color(0xFFEF4444),
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  /// Inline overtime input field used inside the Adjust Overtime section.
  Widget _buildOvertimeInlineField(
    AutoPayrollResult r,
    int index,
    void Function(VoidCallback) setDialogState,
    Map<int, TextEditingController> controllers,
  ) {
    final controllerKey = index * 10;
    if (!controllers.containsKey(controllerKey)) {
      controllers[controllerKey] = TextEditingController(
        text: r.overtimeAmount.isNotEmpty && r.overtimeAmount != '0'
            ? r.overtimeAmount.replaceAll(RegExp(r'[^0-9.]'), '')
            : '',
      );
    }
    final controller = controllers[controllerKey]!;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 250,
          height: 44,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              CommaCurrencyFormatter(),
              LengthLimitingTextInputFormatter(14),
            ],
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFamily: 'SF Pro Display',
              color: Color(0xFF111827),
            ),
            decoration: InputDecoration(
              hintText: '0',
              hintStyle: TextStyle(
                color: const Color(0xFF6B7280).withValues(alpha: 0.6),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFFE5E7EB),
                  width: 1.5,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFFE5E7EB),
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFF0F70FF),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 44,
          child: ElevatedButton(
            onPressed: () {
              final clean = controller.text.replaceAll(RegExp(r'[^0-9.]'), '');
              _recalcOvertime(r, clean, () => setDialogState(() {}));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0247C4),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            child: Text(
              'apply'.tr(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _recalcWithDeductions(
    AutoPayrollResult r,
    String deductionVal,
    VoidCallback onUpdated,
  ) {
    r.customDeduction = deductionVal;
    try {
      final netPayment = PayrollService.calculateNetFromTotals(
        salary: r.salary,
        overtimeAmount: r.overtimeAmount,
        absentDeduction: r.absentDeduction,
        leaveDeduction: r.leaveDeduction,
        customDeduction: deductionVal,
        salaryType: r.salaryType,
      );
      final currency = PayrollService.getCurrencyPrefix(r.salary);
      final p = currency.isNotEmpty ? '$currency ' : '';
      r.netSalary = '$p${PayrollService.formatNumber(netPayment)}';
      r.rawNetSalaryValue = netPayment;
      r.deductionsAreTotals = true;
    } catch (e) {
      debugPrint('_recalcWithDeductions error: $e');
    }
    onUpdated();
  }

  void _recalcOvertime(
    AutoPayrollResult r,
    String overtimeVal,
    VoidCallback onUpdated,
  ) {
    r.overtimeAmount = overtimeVal;
    // Always re-apply custom deduction so the two don't conflict
    _recalcWithDeductions(r, r.customDeduction, onUpdated);
  }

  String _editableAmount(num amount) {
    return amount % 1 == 0
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }
}
