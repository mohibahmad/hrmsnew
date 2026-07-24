import 'dart:async';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'payroll_service.dart';
import 'preferences_service.dart';
import 'dummy_data.dart';
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

    // 2. Calculate payroll for each worker.
    final results = <AutoPayrollResult>[];
    for (final worker in workers) {
      final name = (worker['name'] ?? '').toString();
      final email = (worker['email'] ?? '').toString();
      final salaryStr = PayrollService.currentSalaryDisplay(worker);
      final totalWorkDays = (worker['totalWorkDays'] ?? '').toString();
      final workDays = int.tryParse(totalWorkDays) ?? 22;

      // Auto-fetch real attendance from Firestore (same as _fetchMonthlyAttendance)
      int absents = 0;
      int leaves = 0;
      if (!isGuest && email.trim().isNotEmpty) {
        try {
          final attendance = await Provider.of<FirestoreService>(context, listen: false)
              .getWorkerMonthlyAttendance(email);
          absents = attendance['absents'] ?? 0;
          leaves = attendance['leaves'] ?? 0;
        } catch (_) {
          // Fallback: use values from worker record if any.
          final att = PayrollService.attendanceCounts(worker);
          absents = att['absents'] ?? 0;
          leaves = att['leaves'] ?? 0;
        }
      } else {
        final att = PayrollService.attendanceCounts(worker);
        absents = att['absents'] ?? 0;
        leaves = att['leaves'] ?? 0;
      }

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
    } else {
      await _commitPayrollRun(summary, isGuest, context);
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

      if (isGuest) {
        DummyData.payroll.add({
          ...record,
          'id': DateTime.now().microsecondsSinceEpoch.toString(),
        });
      } else {
        try {
            await Provider.of<FirestoreService>(context, listen: false).addPayrollRecord(record);
        } catch (_) {
          // Individual record failures are non‑fatal.
        }
      }

      // Also create an expense entry for the salary payment.
      final netAmount = PayrollService.extractSalary(r.netSalary);
      if (netAmount > 0) {
        final expenseRecord = {
          'name': r.workerName,
          'date': summary.runDate,
          'category': 'Salary',
          'amount': netAmount,
          'description':
              'Salary payment for ${r.workerName} (${summary.periodLabel})',
        };
        if (isGuest) {
          final expenseId =
              'dummy_e${DateTime.now().microsecondsSinceEpoch}_${r.email.hashCode}';
          DummyData.expenses.insert(0, {...expenseRecord, 'id': expenseId});
        } else {
          try {
            await Provider.of<FirestoreService>(context, listen: false).addExpense(expenseRecord);
          } catch (_) {}
        }
      }
    }

    if (isGuest) {
      await DummyData.saveToPrefs();
    }
  }

  /// Returns the list of selected results, or null if cancelled.
  Future<List<AutoPayrollResult>?> _showReviewDialog(
    BuildContext context,
    PayrollRunSummary summary,
  ) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 600 ? screenWidth * 0.95 : 700.0;
    final dialogHeight = screenWidth < 600 ? 550.0 : 600.0;

    String searchQuery = '';
    AutoPayrollResult? selectedWorker;
    Set<int> _selectedIndices = {};

    for (int i = 0; i < summary.results.length; i++) {
      if (summary.results[i].success) {
        _selectedIndices.add(i);
      }
    }

    return showDialog<List<AutoPayrollResult>>(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filteredResults = searchQuery.isEmpty
              ? summary.results
              : summary.results
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

          final totalSelected = _selectedIndices.length;

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
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: selectedWorker != null
                    ? _buildWorkerDetailView(
                        context,
                        selectedWorker!,
                        setDialogState,
                        () => setDialogState(() => selectedWorker = null),
                      )
                    : Column(
                        children: [
                          // Header
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            decoration: const BoxDecoration(
                              color: Color(0xFF004FDE),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(10),
                                topRight: Radius.circular(10),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.payments_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'payroll_run_review'.tr(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => Navigator.of(ctx).pop(),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Search bar
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                            child: SizedBox(
                              height: 40,
                              child: TextField(
                                onChanged: (val) {
                                  setDialogState(() => searchQuery = val);
                                },
                                decoration: InputDecoration(
                                  hintText: 'search_by_workers_name'.tr(),
                                  hintStyle: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFFBDBDBD),
                                    fontFamily: 'SF Pro Display',
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    size: 20,
                                    color: Color(0xFFBDBDBD),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFE0E0E0),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFE0E0E0),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF0247C4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Summary info with select all
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
                            child: Row(
                              children: [
                                _summaryChip(
                                  Icons.people_outline,
                                  'workers_count'.tr(
                                    namedArgs: {
                                      'count': '${summary.totalWorkers}',
                                    },
                                  ),
                                  const Color(0xFF0247C4),
                                ),
                                const SizedBox(width: 10),
                                _summaryChip(
                                  Icons.check_circle_outline,
                                  'payroll_success_count'.tr(
                                    namedArgs: {
                                      'count': '${summary.successCount}',
                                    },
                                  ),
                                  const Color(0xFF27AE60),
                                ),
                                if (summary.failCount > 0) ...[
                                  const SizedBox(width: 10),
                                  _summaryChip(
                                    Icons.error_outline,
                                    'payroll_fail_count'.tr(
                                      namedArgs: {
                                        'count': '${summary.failCount}',
                                      },
                                    ),
                                    const Color(0xFFE74C3C),
                                  ),
                                ],
                                const Spacer(),
                                Text(
                                  '${totalSelected} selected',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0247C4),
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Select All / Deselect All row
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    setDialogState(() {
                                      if (_selectedIndices.length ==
                                          summary.results.length) {
                                        _selectedIndices.clear();
                                      } else {
                                        _selectedIndices = {
                                          for (
                                            int i = 0;
                                            i < summary.results.length;
                                            i++
                                          )
                                            if (summary.results[i].success) i,
                                        };
                                      }
                                    });
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _selectedIndices.length ==
                                                summary.results.length
                                            ? Icons.check_box
                                            : Icons.check_box_outline_blank,
                                        size: 18,
                                        color: const Color(0xFF0247C4),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _selectedIndices.length ==
                                                summary.results.length
                                            ? 'Deselect All'
                                            : 'Select All',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF0247C4),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 8),
                          // Scrollable results
                          Expanded(
                            child: filteredResults.isEmpty
                                ? Center(
                                    child: Text(
                                      'no_results'.tr(),
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    itemCount: filteredResults.length,
                                    separatorBuilder: (_, _) => const Divider(
                                      height: 1,
                                      color: Color(0xFFF0F0F0),
                                    ),
                                    itemBuilder: (_, i) {
                                      final r = filteredResults[i];
                                      final originalIndex = summary.results
                                          .indexOf(r);
                                      final isSelected = _selectedIndices
                                          .contains(originalIndex);

                                      return InkWell(
                                        onTap: () {
                                          setDialogState(
                                            () => selectedWorker = r,
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(6),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 6,
                                            horizontal: 4,
                                          ),
                                          child: Row(
                                            children: [
                                              GestureDetector(
                                                onTap: () {
                                                  setDialogState(() {
                                                    if (isSelected) {
                                                      _selectedIndices.remove(
                                                        originalIndex,
                                                      );
                                                    } else {
                                                      _selectedIndices.add(
                                                        originalIndex,
                                                      );
                                                    }
                                                  });
                                                },
                                                child: Icon(
                                                  isSelected
                                                      ? Icons.check_box
                                                      : Icons
                                                            .check_box_outline_blank,
                                                  size: 20,
                                                  color: isSelected
                                                      ? const Color(0xFF0247C4)
                                                      : const Color(0xFFBDBDBD),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      r.workerName,
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontFamily:
                                                            'SF Pro Display',
                                                      ),
                                                    ),
                                                    if (r.email.isNotEmpty) ...[
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        r.email,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Color(
                                                            0xFF64748B,
                                                          ),
                                                          fontFamily:
                                                              'SF Pro Display',
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                r.netSalary,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  fontFamily: 'SF Pro Display',
                                                  color: r.success
                                                      ? const Color(0xFF0247C4)
                                                      : const Color(0xFFE74C3C),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Icon(
                                                r.success
                                                    ? Icons.check_circle
                                                    : Icons.cancel,
                                                size: 18,
                                                color: r.success
                                                    ? const Color(0xFF27AE60)
                                                    : const Color(0xFFE74C3C),
                                              ),
                                              const SizedBox(width: 4),
                                              const Icon(
                                                Icons.chevron_right,
                                                size: 18,
                                                color: Color(0xFFBDBDBD),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          // Actions
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: Text(
                                    'cancel'.tr(),
                                    style: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0247C4),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                  ),
                                  onPressed: () {
                                    final selected = _selectedIndices
                                        .map((i) => summary.results[i])
                                        .toList();
                                    // If nothing selected, don't proceed
                                    if (selected.isEmpty) return;
                                    Navigator.of(ctx).pop(selected);
                                  },
                                  icon: const Icon(Icons.check, size: 18),
                                  label: Text(
                                    'confirm_and_process'.tr(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
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

  Widget _buildWorkerDetailView(
    BuildContext context,
    AutoPayrollResult r,
    void Function(VoidCallback) setDialogState,
    VoidCallback onBack,
  ) {
    return Column(
      children: [
        // Header with back button
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: const BoxDecoration(
            color: Color(0xFF004FDE),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(10),
              topRight: Radius.circular(10),
            ),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: onBack,
                child: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  r.workerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'SF Pro Display',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(Icons.close, color: Colors.white, size: 22),
              ),
            ],
          ),
        ),
        // Worker info
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          decoration: const BoxDecoration(
            color: Color(0xFFF8F9FA),
            border: Border(
              bottom: BorderSide(color: Color(0xFFE8E8E8), width: 1),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF0247C4).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Center(
                  child: Text(
                    r.workerName.isNotEmpty
                        ? r.workerName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Color(0xFF0247C4),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.workerName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF333333),
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                    if (r.email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        r.email,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF666666),
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                r.netSalary,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0247C4),
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ],
          ),
        ),
        // Detail metrics
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _detailCard(
                        icon: Icons.person_off_rounded,
                        title: 'absents_label'.tr(),
                        value: '${r.absents}',
                        color: const Color(0xFFE74C3C),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _detailCard(
                        icon: Icons.event_busy_rounded,
                        title: 'leaves_label'.tr(),
                        value: '${r.leaves}',
                        color: const Color(0xFFF39C12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _detailCard(
                        icon: Icons.remove_circle_outline,
                        title: 'absent_deduction_per_day'.tr(),
                        value: r.absentDeduction,
                        color: const Color(0xFF0247C4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _detailCard(
                        icon: Icons.remove_circle_outline,
                        title: 'leave_deduction_per_day'.tr(),
                        value: r.leaveDeduction,
                        color: const Color(0xFF0247C4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _detailCard(
                        icon: Icons.timer_rounded,
                        title: 'overtime_amount'.tr(),
                        value: r.overtimeAmount.isNotEmpty
                            ? r.overtimeAmount
                            : '0',
                        color: const Color(0xFF27AE60),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _detailCard(
                        icon: Icons.account_balance_wallet,
                        title: 'salary_after_deduction'.tr(),
                        value: r.netSalary,
                        color: const Color(0xFF0247C4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _detailCard(
                        icon: Icons.payments,
                        title: 'salary'.tr(),
                        value: r.salary,
                        color: const Color(0xFF0247C4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _detailCard(
                        icon: Icons.work_history_rounded,
                        title: 'total_work_days'.tr(),
                        value: r.totalWorkDays,
                        color: const Color(0xFF0247C4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Back button
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0247C4),
                side: const BorderSide(color: Color(0xFF0247C4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text(
                'back_to_list'.tr(),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E8E8), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
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
                const SizedBox(height: 2),
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
}
