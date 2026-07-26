import 'dart:async';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
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
import '../utils/snackbar_utils.dart';

/// Result of a single automated payroll run for one worker.
class AutoPayrollResult {
  final String workerName;
  final String email;
  final String netSalary;
  final bool success;
  final String? error;
  final int absents;
  final int leaves;
  final String absentDeduction;
  final String leaveDeduction;
  final String overtimeAmount;
  final String salary;
  final String totalWorkDays;
  final String position;

  AutoPayrollResult({
    required this.workerName,
    required this.email,
    required this.netSalary,
    required this.success,
    this.error,
    this.absents = 0,
    this.leaves = 0,
    this.absentDeduction = '',
    this.leaveDeduction = '',
    this.overtimeAmount = '',
    this.salary = '',
    this.totalWorkDays = '22',
    this.position = '',
  });
}

/// Tracks the overall outcome of a salary-day payroll run.
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

/// Responsible for scheduling and executing automated payroll on the
/// configured salary day of each month.
///
/// Supports two modes:
///   - **Semi‑auto** (default): calculates everything and shows a review
///     dialog before finalising.
///   - **Fully auto**: processes immediately without user intervention.
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

    // Only run on the configured day.
    if (today.day != salaryDay) return false;

    // Guard against running more than once per day.
    if (await _alreadyRanToday()) return false;

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
    final isGuest = Provider.of<AuthService>(context, listen: false).currentUser?.isAnonymous ?? false;

    // 1. Gather workers.
    List<Map<String, dynamic>> workers;

    if (isGuest) {
      workers = List<Map<String, dynamic>>.from(DummyData.workers);
    } else {
      try {
        final workerSnap = await Provider.of<FirestoreService>(context, listen: false).getWorkersOnce();
        workers = workerSnap.docs
            .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
            .toList();
      } catch (e) {
        if (context.mounted) {
          FlashySnackBar.show(
            context,
            message: 'Failed to load worker data: $e',
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
    final periodLabel = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    // 2. Fetch attendance for all workers in parallel (fixes N+1 query problem).
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final attendanceFutures = <Future<Map<String, int>>>[];
    for (final worker in workers) {
      final email = (worker['email'] ?? '').toString();
      if (!isGuest && email.trim().isNotEmpty) {
        attendanceFutures.add(
          firestoreService.getWorkerMonthlyAttendance(email).catchError((_) {
            final att = PayrollService.attendanceCounts(worker);
            return <String, int>{'absents': att['absents'] ?? 0, 'leaves': att['leaves'] ?? 0};
          }),
        );
      } else {
        final att = PayrollService.attendanceCounts(worker);
        attendanceFutures.add(Future.value(<String, int>{'absents': att['absents'] ?? 0, 'leaves': att['leaves'] ?? 0}));
      }
    }
    final attendanceResults = await Future.wait(attendanceFutures);

    // 3. Calculate payroll for each worker using pre-fetched attendance.
    final results = <AutoPayrollResult>[];
    for (int i = 0; i < workers.length; i++) {
      final worker = workers[i];
      final name = (worker['name'] ?? '').toString();
      final email = (worker['email'] ?? '').toString();
      final salaryStr = PayrollService.currentSalaryDisplay(worker);
      final totalWorkDays = (worker['totalWorkDays'] ?? '').toString();
      final workDays = int.tryParse(totalWorkDays) ?? 22;

      int absents = attendanceResults[i]['absents'] ?? 0;
      int leaves = attendanceResults[i]['leaves'] ?? 0;

      // Use worker's configured absent/leave deduction per day if available.
      // If not configured, default both to daily rate so that every absent or
      // leave day is itemised as a deduction.  This matches the individual
      // payroll screen where the HR normally enters these values manually.
      final rawSalary = PayrollService.extractSalary(salaryStr);
      final dailyRate = workDays > 0
          ? (rawSalary / workDays).toStringAsFixed(2)
          : '0';
      final absentDeductionPerDay = (worker['absentDeduction'] ?? '')
          .toString()
          .trim();
      final leaveDeductionPerDay = (worker['leaveDeduction'] ?? '')
          .toString()
          .trim();
      final effectiveAbsentDeduction = absentDeductionPerDay.isNotEmpty
          ? absentDeductionPerDay
          : dailyRate;
      final effectiveLeaveDeduction = leaveDeductionPerDay.isNotEmpty
          ? leaveDeductionPerDay
          : dailyRate;

      // Match _recalc() in AddPayrollScreen: when a per-day deduction is
      // configured for leaves, those leave days also reduce worked days.
      // Absents always reduce worked days irrespective of deduction config.
      final hasLeaveDeduction = effectiveLeaveDeduction.isNotEmpty;
      final effectiveDays =
          workDays - absents - (hasLeaveDeduction ? leaves : 0);

      String netSalary;
      try {
        final calc = PayrollService.calculatePayroll(
          salary: salaryStr,
          totalWorkDays: workDays.toString(),
          daysWorked: effectiveDays > 0 ? effectiveDays.toString() : '0',
          absents: absents.toString(),
          leaves: leaves.toString(),
          overtimeAmount: (worker['overtimeAmount'] ?? '').toString(),
          absentDeductionPerDay: effectiveAbsentDeduction,
          leaveDeductionPerDay: effectiveLeaveDeduction,
          salaryType: (worker['salaryType'] ?? 'Monthly').toString(),
        );
        netSalary = calc['formattedNet'] as String? ?? '0';
      } catch (e) {
        results.add(
          AutoPayrollResult(
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
          workerName: name,
          email: email,
          netSalary: netSalary,
          success: true,
          absents: absents,
          leaves: leaves,
          absentDeduction: effectiveAbsentDeduction,
          leaveDeduction: effectiveLeaveDeduction,
          overtimeAmount: (worker['overtimeAmount'] ?? '').toString(),
          salary: salaryStr,
          totalWorkDays: workDays.toString(),
          position: (worker['position'] ?? '').toString(),
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

      await _commitPayrollRun(filteredSummary, isGuest, context);

      // Auto-download ZIP if more than 1 worker was paid.
      if (filteredSummary.successCount > 1 && context.mounted) {
        final paidResults = filteredSummary.results
            .where((r) => r.success)
            .toList();
        await _generateAndSaveZip(context, paidResults, filteredSummary.periodLabel);
      }
    } else {
      await _commitPayrollRun(summary, isGuest, context);

      // Auto-download ZIP if more than 1 worker was paid.
      if (summary.successCount > 1 && context.mounted) {
        final paidResults = summary.results
            .where((r) => r.success)
            .toList();
        await _generateAndSaveZip(context, paidResults, summary.periodLabel);
      }
    }

    await _markRunComplete();

    if (context.mounted && autoMode) {
      FlashySnackBar.show(
        context,
        message: 'payroll_run_complete'.tr(
          namedArgs: {'count': '$successCount'},
        ),
      );
    }

    return summary;
  }

  Future<PayrollRunSummary?> payAll(BuildContext context) async {
    // Note: No loading dialog here because runPayroll(autoMode: false)
    // will show its own review dialog (_showReviewDialog). A loading
    // dialog shown first would block the review dialog from appearing.
    final result = await runPayroll(context, autoMode: false);
    return result;
  }

  Future<int?> _loadSalaryDay(BuildContext context) async {
    final isGuest = Provider.of<AuthService>(context, listen: false).currentUser?.isAnonymous ?? false;
    if (isGuest) {
      return PreferencesService.getCompanySalaryDay();
    }
    final profile = await Provider.of<FirestoreService>(context, listen: false).getUserProfile();
    final raw = profile?['salaryPaymentDay'];
    final day = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
    if (day != null && (day < 1 || day > 31)) return null;
    return day;
  }

  Future<bool> _alreadyRanToday() async {
    final prefs = await SharedPreferences.getInstance();
    final lastRun = prefs.getString(_lastRunKey);
    if (lastRun == null) return false;
    final today = DateTime.now();
    final last = DateTime.tryParse(lastRun);
    if (last == null) return false;
    return last.year == today.year &&
        last.month == today.month &&
        last.day == today.day;
  }

  Future<void> _markRunComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastRunKey, DateTime.now().toIso8601String());
  }

  Future<void> _commitPayrollRun(
    PayrollRunSummary summary,
    bool isGuest,
    BuildContext context,
  ) async {
    if (isGuest) {
      for (final r in summary.results) {
        if (!r.success) continue;
        final record = {
          'name': r.workerName,
          'email': r.email,
          'status': 'Paid',
          'totalWorkDays': r.totalWorkDays,
          'absents': r.absents.toString(),
          'leaves': r.leaves.toString(),
          'overtimeAmount': r.overtimeAmount,
          'absentDeduction': r.absentDeduction,
          'leaveDeduction': r.leaveDeduction,
          'salary': r.salary,
          'netSalary': r.netSalary,
          'lastModified': DateTime.now(),
          'createdAt': FieldValue.serverTimestamp(),
          'payrollDate': summary.runDate,
        };
        DummyData.payroll.add({
          ...record,
          'id': DateTime.now().microsecondsSinceEpoch.toString(),
        });
        final netAmount = PayrollService.extractSalary(r.netSalary);
        if (netAmount > 0) {
          final expenseRecord = {
            'name': r.workerName,
            'date': summary.runDate,
            'category': 'Salary',
            'amount': netAmount,
            'description': 'Salary payment for ${r.workerName} (${summary.periodLabel})',
          };
          final expenseId = 'dummy_e${DateTime.now().microsecondsSinceEpoch}_${r.email.hashCode}';
          DummyData.expenses.insert(0, {...expenseRecord, 'id': expenseId});
        }
      }
      await DummyData.saveToPrefs();
      return;
    }

    // Batch Firestore writes for better performance.
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final successfulResults = summary.results.where((r) => r.success).toList();

    // Prepare payroll records
    final payrollRecords = <Map<String, dynamic>>[];
    final expenseRecords = <Map<String, dynamic>>[];
    final notifications = <Map<String, dynamic>>[];

    for (final r in successfulResults) {
      final record = {
        'name': r.workerName,
        'email': r.email,
        'status': 'Paid',
        'totalWorkDays': r.totalWorkDays,
        'absents': r.absents.toString(),
        'leaves': r.leaves.toString(),
        'overtimeAmount': r.overtimeAmount,
        'absentDeduction': r.absentDeduction,
        'leaveDeduction': r.leaveDeduction,
        'salary': r.salary,
        'netSalary': r.netSalary,
        'lastModified': DateTime.now(),
        'payrollDate': summary.runDate,
      };
      payrollRecords.add(record);

      // Prepare expense record
      final netAmount = PayrollService.extractSalary(r.netSalary);
      if (netAmount > 0) {
        expenseRecords.add({
          'name': r.workerName,
          'date': summary.runDate,
          'category': 'Salary',
          'amount': netAmount,
          'description': 'Salary payment for ${r.workerName} (${summary.periodLabel})',
        });
      }

      // Prepare notification
      final amount = r.netSalary;
      if (r.workerName.isNotEmpty) {
        notifications.add({
          'type': 'payroll_added',
          'title': 'notif_title_payroll'.tr(namedArgs: {'name': r.workerName}),
          'message': amount.isNotEmpty
              ? 'notif_msg_payroll_amount'.tr(namedArgs: {'amount': '\$$amount', 'name': r.workerName})
              : 'notif_msg_payroll'.tr(namedArgs: {'name': r.workerName}),
          'data': {'name': r.workerName, 'amount': amount.isNotEmpty ? '\$$amount' : ''},
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
      FlashySnackBar.show(context, message: 'Generating invoices...');
    }

    try {
      final archive = Archive();
      final now = DateTime.now();
      final payPeriod = periodLabel.isNotEmpty
          ? periodLabel
          : '${now.year}-${now.month.toString().padLeft(2, '0')}';

      for (final r in selected) {
        if (!r.success) continue;
        final rawSalary = PayrollService.extractSalary(r.salary);
        final workDays = int.tryParse(r.totalWorkDays) ?? 22;
        final dailyRate = workDays > 0
            ? (rawSalary / workDays).toStringAsFixed(2)
            : '0';
        final absentsInt = r.absents;
        final leavesInt = r.leaves;
        final absentDeductionAmt = double.tryParse(r.absentDeduction) ?? 0.0;
        final leaveDeductionAmt = double.tryParse(r.leaveDeduction) ?? 0.0;
        final overtimeAmt = double.tryParse(r.overtimeAmount) ?? 0.0;
        final absentTotal = absentDeductionAmt * absentsInt;
        final leaveTotal = leaveDeductionAmt * leavesInt;
        final totalDeductions = absentTotal + leaveTotal;
        final hasLeaveDeduction = leaveDeductionAmt > 0;
        final effectiveDays = workDays - absentsInt - (hasLeaveDeduction ? leavesInt : 0);
        final grossPay = rawSalary > 0 && workDays > 0
            ? (rawSalary / workDays * effectiveDays).toStringAsFixed(2)
            : '0';

        final pdfBytes = await InvoiceService.generatePayrollInvoice(
          employeeName: r.workerName,
          email: r.email,
          position: r.position,
          payPeriod: payPeriod,
          totalWorkDays: r.totalWorkDays,
          daysWorked: effectiveDays.toString(),
          absents: absentsInt.toString(),
          leaves: leavesInt.toString(),
          overtimeAmount: overtimeAmt > 0 ? 'Rs ${overtimeAmt.toStringAsFixed(0)}' : '0',
          salary: r.salary,
          dailyRate: 'Rs ${double.tryParse(dailyRate)?.toStringAsFixed(0) ?? dailyRate}',
          grossPay: 'Rs ${double.tryParse(grossPay)?.toStringAsFixed(0) ?? grossPay}',
          overtimePay: overtimeAmt > 0 ? 'Rs ${overtimeAmt.toStringAsFixed(0)}' : '0',
          absentDeduction: absentTotal > 0 ? 'Rs ${absentTotal.toStringAsFixed(0)}' : '0',
          leaveDeduction: leaveTotal > 0 ? 'Rs ${leaveTotal.toStringAsFixed(0)}' : '0',
          totalDeductions: totalDeductions > 0 ? 'Rs ${totalDeductions.toStringAsFixed(0)}' : '0',
          netSalary: r.netSalary,
        );

        final safeName = r.workerName.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
        archive.addFile(ArchiveFile('${safeName}_invoice_$payPeriod.pdf', pdfBytes.length, pdfBytes));
      }

      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes.isEmpty) throw Exception('ZIP encoding failed');

      final zipData = Uint8List.fromList(zipBytes);
      final fileName = 'payroll_invoices_$payPeriod.zip';

      final result = await FilePicker.saveFile(
        dialogTitle: 'Save Payroll Invoices ZIP',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: zipData,
      );

      if (result != null) {
        final file = File(result);
        await file.writeAsBytes(zipData);
        if (context.mounted) {
          FlashySnackBar.show(context, message: 'ZIP saved: $fileName');
        }
      }
    } catch (e) {
      if (context.mounted) {
        FlashySnackBar.show(
          context,
          message: 'Failed to generate ZIP: $e',
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
    Set<int> expandedIndices = {};
    Set<int> selectedIndices = {};
    bool isZipLoading = false;

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

    return showDialog<List<AutoPayrollResult>>(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          List<AutoPayrollResult> posFiltered = positionFilter == 'All'
              ? summary.results
              : summary.results
                    .where(
                      (r) =>
                          r.position.toLowerCase().trim() ==
                          positionFilter.toLowerCase().trim(),
                    )
                    .toList();

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
              .where((r) => selectedIndices.contains(summary.results.indexOf(r)))
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
                      color: const Color(0xFF0247C4).withValues(alpha: 0.18),
                      blurRadius: 40,
                      spreadRadius: 0,
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
                  children: [
                    // ── Header ──────────────────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF0040C8),
                            Color(0xFF1565E8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.payments_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'payroll_run_review'.tr(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'SF Pro Display',
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${summary.totalWorkers} workers · ${summary.periodLabel}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontSize: 12,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.of(ctx).pop(),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),

                        ],
                      ),
                    ),

                    // ── Search bar ──────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: SizedBox(
                        height: 44,
                        child: TextField(
                          onChanged: (val) {
                            setDialogState(() => searchQuery = val);
                          },
                          style: const TextStyle(
                            fontSize: 14,
                            fontFamily: 'SF Pro Display',
                          ),
                          decoration: InputDecoration(
                            hintText: 'search_by_workers_name'.tr(),
                            hintStyle: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFFBDBDBD),
                              fontFamily: 'SF Pro Display',
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 20,
                              color: Color(0xFFBDBDBD),
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8F9FC),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFFE8ECF2),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFFE8ECF2),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFF0247C4),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ── Position Filter Chips ───────────────────────────
                    if (allPositions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: SizedBox(
                          height: 34,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _posFilterChip(
                                'All',
                                positionFilter,
                                setDialogState,
                                (v) => positionFilter = v,
                              ),
                              ...allPositions.map(
                                (pos) => _posFilterChip(
                                  pos,
                                  positionFilter,
                                  setDialogState,
                                  (v) => positionFilter = v,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // ── Summary + Select/Deselect All ───────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Row(
                        children: [
                          // Selected count text
                          Text(
                            '$filteredSelectedCount Selected Worker',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0247C4),
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                          const Spacer(),
                          if (summary.failCount > 0) ...[
                            _summaryChip(
                              Icons.error_outline,
                              '${summary.failCount} Fail',
                              const Color(0xFFE74C3C),
                            ),
                            const SizedBox(width: 8),
                          ],
                          // Select All / Deselect All button
                          InkWell(
                            onTap: () {
                              setDialogState(() {
                                final filteredIndices = filteredResults
                                    .map((r) => summary.results.indexOf(r))
                                    .toSet();
                                final allFilteredSelected = filteredIndices
                                    .every((i) => selectedIndices.contains(i));
                                if (allFilteredSelected) {
                                  selectedIndices.removeAll(filteredIndices);
                                } else {
                                  selectedIndices.addAll(filteredIndices);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: filteredSelectedCount == filteredResults.length &&
                                        filteredResults.isNotEmpty
                                    ? const Color(0xFFE74C3C).withValues(alpha: 0.1)
                                    : const Color(0xFF0247C4).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: filteredSelectedCount == filteredResults.length &&
                                          filteredResults.isNotEmpty
                                      ? const Color(0xFFE74C3C).withValues(alpha: 0.3)
                                      : const Color(0xFF0247C4).withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    filteredSelectedCount == filteredResults.length &&
                                            filteredResults.isNotEmpty
                                        ? Icons.deselect
                                        : Icons.select_all,
                                    size: 16,
                                    color: filteredSelectedCount == filteredResults.length &&
                                            filteredResults.isNotEmpty
                                        ? const Color(0xFFE74C3C)
                                        : const Color(0xFF0247C4),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    filteredSelectedCount == filteredResults.length &&
                                            filteredResults.isNotEmpty
                                        ? 'Deselect All'
                                        : 'Select All',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: filteredSelectedCount == filteredResults.length &&
                                              filteredResults.isNotEmpty
                                          ? const Color(0xFFE74C3C)
                                          : const Color(0xFF0247C4),
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
                      height: 1,
                      color: const Color(0xFFEEF1F6),
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
                              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                              itemCount: filteredResults.length,
                              itemBuilder: (_, i) {
                                final r = filteredResults[i];
                                final originalIndex = summary.results.indexOf(r);
                                final isSelected = selectedIndices.contains(originalIndex);
                                final isExpanded = expandedIndices.contains(originalIndex);

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFF0247C4).withValues(alpha: 0.04)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF0247C4).withValues(alpha: 0.3)
                                            : const Color(0xFFE8ECF2),
                                        width: 1.2,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        // ── Worker Row ──────────────
                                        InkWell(
                                          onTap: () {
                                            setDialogState(() {
                                              if (isExpanded) {
                                                expandedIndices.remove(originalIndex);
                                              } else {
                                                expandedIndices.add(originalIndex);
                                              }
                                            });
                                          },
                                          borderRadius: BorderRadius.circular(12),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                              horizontal: 12,
                                            ),
                                            child: Row(
                                              children: [
                                                // Checkbox
                                                GestureDetector(
                                                  onTap: () {
                                                    setDialogState(() {
                                                      if (isSelected) {
                                                        selectedIndices.remove(originalIndex);
                                                      } else {
                                                        selectedIndices.add(originalIndex);
                                                      }
                                                    });
                                                  },
                                                  child: Icon(
                                                    isSelected
                                                        ? Icons.check_box_rounded
                                                        : Icons.check_box_outline_blank_rounded,
                                                    size: 22,
                                                    color: isSelected
                                                        ? const Color(0xFF0247C4)
                                                        : const Color(0xFFCBD5E1),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                // Avatar
                                                Container(
                                                  width: 38,
                                                  height: 38,
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [
                                                        const Color(0xFF0247C4).withValues(alpha: 0.15),
                                                        const Color(0xFF0247C4).withValues(alpha: 0.08),
                                                      ],
                                                    ),
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      r.workerName.isNotEmpty
                                                          ? r.workerName[0].toUpperCase()
                                                          : '?',
                                                      style: const TextStyle(
                                                        color: Color(0xFF0247C4),
                                                        fontSize: 15,
                                                        fontWeight: FontWeight.w700,
                                                        fontFamily: 'SF Pro Display',
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                // Name + email
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        r.workerName,
                                                        style: const TextStyle(
                                                          fontSize: 14,
                                                          fontWeight: FontWeight.w600,
                                                          fontFamily: 'SF Pro Display',
                                                          color: Color(0xFF1A1F36),
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      if (r.email.isNotEmpty) ...[
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          r.email,
                                                          style: const TextStyle(
                                                            fontSize: 12,
                                                            color: Color(0xFF64748B),
                                                            fontFamily: 'SF Pro Display',
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                // Net salary
                                                Text(
                                                  r.netSalary,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                    fontFamily: 'SF Pro Display',
                                                    color: r.success
                                                        ? const Color(0xFF0247C4)
                                                        : const Color(0xFFE74C3C),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                // Expand arrow
                                                AnimatedRotation(
                                                  turns: isExpanded ? 0.5 : 0,
                                                  duration: const Duration(milliseconds: 200),
                                                  child: const Icon(
                                                    Icons.keyboard_arrow_down_rounded,
                                                    size: 22,
                                                    color: Color(0xFF94A3B8),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),

                                        // ── Expanded Detail Panel ────
                                        if (isExpanded)
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                                            child: Column(
                                              children: [
                                                Container(
                                                  height: 1,
                                                  color: const Color(0xFFEEF1F6),
                                                  margin: const EdgeInsets.only(bottom: 12),
                                                ),
                                                _buildDetailGrid(r),
                                                const SizedBox(height: 12),
                                                // Pay button inside expanded
                                                if (r.success)
                                                  SizedBox(
                                                    width: double.infinity,
                                                    height: 40,
                                                    child: ElevatedButton.icon(
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: const Color(0xFF27AE60),
                                                        foregroundColor: Colors.white,
                                                        elevation: 0,
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                      ),
                                                      onPressed: () {
                                                        Navigator.of(ctx).pop([r]);
                                                      },
                                                      icon: const Icon(Icons.payment_rounded, size: 18),
                                                      label: Text(
                                                        'pay'.tr(),
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.w700,
                                                          fontSize: 14,
                                                          fontFamily: 'SF Pro Display',
                                                        ),
                                                      ),
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

                    // ── Bottom Actions ──────────────────────────────────
                    Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8F9FC),
                        border: Border(
                          top: BorderSide(color: Color(0xFFEEF1F6), width: 1),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Row(
                        children: [
                          const Spacer(),
                          // Pay All button
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0247C4),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              minimumSize: const Size(0, 42),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                            ),
                            onPressed: filteredSelectedCount == 0
                                ? null
                                : () {
                                    final selected = filteredResults
                                        .where((r) => selectedIndices.contains(summary.results.indexOf(r)))
                                        .toList();
                                    Navigator.of(ctx).pop(selected);
                                  },
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: Text(
                              'Pay All ($filteredSelectedCount)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                fontFamily: 'SF Pro Display',
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
          );
        },
      ),
    );
  }

  Widget _buildDetailGrid(AutoPayrollResult r) {
    final totalWorkDays = int.tryParse(r.totalWorkDays) ?? 22;
    final presents = totalWorkDays - r.absents - r.leaves;

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _detailCard(
              icon: Icons.check_circle_rounded,
              title: 'Presents',
              value: '$presents',
              color: const Color(0xFF27AE60),
            )),
            const SizedBox(width: 8),
            Expanded(child: _detailCard(
              icon: Icons.person_off_rounded,
              title: 'Absents',
              value: '${r.absents}',
              color: const Color(0xFFE74C3C),
            )),
            const SizedBox(width: 8),
            Expanded(child: _detailCard(
              icon: Icons.event_busy_rounded,
              title: 'Leaves',
              value: '${r.leaves}',
              color: const Color(0xFFF39C12),
            )),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _detailCard(
              icon: Icons.payments,
              title: 'Salary',
              value: r.salary,
              color: const Color(0xFF0247C4),
            )),
            const SizedBox(width: 8),
            Expanded(child: _detailCard(
              icon: Icons.work_history_rounded,
              title: 'Work Days',
              value: r.totalWorkDays,
              color: const Color(0xFF0247C4),
            )),
            const SizedBox(width: 8),
            Expanded(child: _detailCard(
              icon: Icons.timer_rounded,
              title: 'Overtime',
              value: r.overtimeAmount.isNotEmpty ? r.overtimeAmount : '0',
              color: const Color(0xFF27AE60),
            )),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _detailCard(
              icon: Icons.remove_circle_outline,
              title: 'Absent Ded.',
              value: r.absentDeduction.isNotEmpty ? r.absentDeduction : '0',
              color: const Color(0xFFE74C3C),
            )),
            const SizedBox(width: 8),
            Expanded(child: _detailCard(
              icon: Icons.remove_circle_outline,
              title: 'Leave Ded.',
              value: r.leaveDeduction.isNotEmpty ? r.leaveDeduction : '0',
              color: const Color(0xFFF39C12),
            )),
            const SizedBox(width: 8),
            Expanded(child: _detailCard(
              icon: Icons.account_balance_wallet,
              title: 'Net Salary',
              value: r.netSalary,
              color: const Color(0xFF0247C4),
            )),
          ],
        ),
      ],
    );
  }

  Widget _detailCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E8E8), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                    fontFamily: 'SF Pro Display',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF000000),
              fontWeight: FontWeight.bold,
              fontFamily: 'SF Pro Display',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ],
      ),
    );
  }

  Widget _posFilterChip(
    String label,
    String currentFilter,
    void Function(VoidCallback) setDialogState,
    void Function(String) onSelect,
  ) {
    final isActive = currentFilter == label;
    return GestureDetector(
      onTap: () => setDialogState(() => onSelect(label)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF0247C4) : const Color(0xFFF0F4FF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? const Color(0xFF0247C4)
                : const Color(0xFFD6E0FF),
            width: 1.2,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: const Color(0xFF0247C4).withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : const Color(0xFF0247C4),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ),
    );
  }
}
