import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/file_opener.dart';
import 'dart:io';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'payroll_service.dart';
import 'preferences_service.dart';
import 'dummy_data.dart';
import 'invoice_service.dart';
import 'error_reporter.dart';
import '../utils/currency_formatter.dart';
import '../utils/currency_utils.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/amount_text.dart';

class AutoPayrollResult {
  final String workerId;
  final String workerName;
  final String email;
  String netSalary;
  final bool success;
  final String? error;
  final int absents;
  final int halfDays;
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
  final String currency;
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
    this.halfDays = 0,
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
    this.currency = CurrencyUtils.defaultCode,
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
    halfDays: halfDays,
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
    currency: currency,
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

  static final SalaryDayScheduler _instance = SalaryDayScheduler._();
  factory SalaryDayScheduler() => _instance;
  SalaryDayScheduler._();

  bool _runInProgress = false;

  Future<bool> checkAndRunIfDue(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isGuest = authService.currentUser?.isAnonymous ?? false;
    final salaryDay = await _loadSalaryDay(context);
    if (salaryDay == null) return false;

    final today = DateTime.now();

    if (!PayrollService.isPayrollDue(today, salaryDay)) return false;
    if (!context.mounted) return false;

    final payrollMonth = await _loadActivePayrollMonth(context, today);
    final period = PayrollService.payrollPeriodLabel(payrollMonth);
    if (await _alreadyRanForPeriod(
      period,
      isGuest: isGuest,
      userId: authService.currentUser?.uid,
    )) {
      return false;
    }

    if (!context.mounted) return false;
    final summary = await runPayroll(
      context,
      autoMode: false,
      payrollMonth: payrollMonth,
    );
    return summary != null;
  }

  Future<PayrollRunSummary?> runPayroll(
    BuildContext context, {
    bool autoMode = false,
    DateTime? payrollMonth,
    String? positionFilter,
  }) async {
    final isGuest =
        Provider.of<AuthService>(
          context,
          listen: false,
        ).currentUser?.isAnonymous ??
        false;
    if (isGuest) {
      return _runPayrollInternal(
        context,
        autoMode: autoMode,
        payrollMonth: payrollMonth,
        positionFilter: positionFilter,
      );
    }
    if (_runInProgress) return null;
    _runInProgress = true;
    try {
      return await _runPayrollInternal(
        context,
        autoMode: autoMode,
        payrollMonth: payrollMonth,
        positionFilter: positionFilter,
      );
    } finally {
      _runInProgress = false;
    }
  }

  Future<PayrollRunSummary?> _runPayrollInternal(
    BuildContext context, {
    required bool autoMode,
    DateTime? payrollMonth,
    String? positionFilter,
  }) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isGuest = authService.currentUser?.isAnonymous ?? false;
    final firestoreService = Provider.of<FirestoreService>(
      context,
      listen: false,
    );

    List<Map<String, dynamic>> workers;

    if (isGuest) {
      workers = List<Map<String, dynamic>>.from(DummyData.workers);
    } else {
      try {
        final workerSnap = await firestoreService.getWorkersOnce();
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

    if (positionFilter != null && positionFilter.trim().isNotEmpty) {
      final filter = positionFilter.trim();
      workers = workers.where((worker) {
        final position = (worker['position'] ?? '').toString().trim();
        return position.isNotEmpty &&
            position.toLowerCase().contains(filter.toLowerCase());
      }).toList();
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
    }

    final now = DateTime.now();
    final effectivePayrollMonth =
        payrollMonth ?? PayrollService.currentPayrollMonth(referenceDate: now);
    final periodLabel = PayrollService.payrollPeriodLabel(
      effectivePayrollMonth,
    );

    Map<String, dynamic>? companyProfile;
    try {
      companyProfile = isGuest
          ? await PreferencesService.getGuestProfileData()
          : await firestoreService.getUserProfile();
    } catch (error, stackTrace) {
      ErrorReporter.report(
        error,
        stackTrace,
        context: 'SalaryDayCompanyCurrency',
      );
    }
    final companyCurrency = CurrencyUtils.normalize(
      companyProfile?['currency'],
    );

    if (!isGuest) {
      try {
        final payrollSnapshot = await firestoreService.payrollStream.first
            .timeout(const Duration(seconds: 20));
        final existingPayroll = payrollSnapshot.docs
            .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
            .toList();
        workers = workers.where((worker) {
          return !existingPayroll.any(
            (record) => _isPaidPayrollForWorker(
              record: record,
              worker: worker,
              month: effectivePayrollMonth,
            ),
          );
        }).toList();
      } catch (error, stackTrace) {
        ErrorReporter.report(
          error,
          stackTrace,
          context: 'SalaryDayExistingPayrollCheck',
        );
        if (context.mounted) {
          FlashySnackBar.show(
            context,
            message: 'error_occurred'.tr(
              namedArgs: {'error': error.toString()},
            ),
            isError: true,
          );
        }
        return null;
      }

      if (workers.isEmpty) {
        await _markRunComplete(
          periodLabel,
          isGuest: false,
          userId: authService.currentUser?.uid,
        );
        return null;
      }
    }

    final eligibleWorkerCount = workers.length;
    late final List<Map<String, dynamic>> attendanceResults;

    if (isGuest) {
      final attendanceFutures = <Future<Map<String, dynamic>>>[];
      for (final worker in workers) {
        final att = PayrollService.attendanceCounts(worker);
        attendanceFutures.add(
          Future.value(<String, dynamic>{
            'absents': att['absents'] ?? 0,
            'paidLeaves': att['paidLeaves'] ?? 0,
            'unpaidLeaves': att['unpaidLeaves'] ?? 0,
            'leaves': att['leaves'] ?? 0,
          }),
        );
      }
      attendanceResults = await Future.wait(attendanceFutures);
    } else {
      final attendanceFutures = <Future<Map<String, dynamic>>>[];
      for (final worker in workers) {
        final email = (worker['email'] ?? '').toString();
        final workerId = (worker['id'] ?? worker['workerId'] ?? '')
            .toString()
            .trim();
        attendanceFutures.add(() async {
          try {
            final attendance = await firestoreService
                .getWorkerMonthlyAttendance(
                  email,
                  workerId: workerId,
                  month: effectivePayrollMonth,
                );
            return <String, dynamic>{...attendance};
          } catch (error, stackTrace) {
            ErrorReporter.report(
              error,
              stackTrace,
              context: 'SalaryDayAttendanceFetch:$workerId',
            );
            return <String, dynamic>{'_error': error.toString()};
          }
        }());
      }
      attendanceResults = await Future.wait(attendanceFutures);
    }

    int autoWorkDays;
    try {
      autoWorkDays = await firestoreService.getMonthlyWorkingDays(
        month: effectivePayrollMonth,
      );
    } catch (_) {
      autoWorkDays = 30;
    }

    final results = <AutoPayrollResult>[];
    for (int i = 0; i < workers.length; i++) {
      final worker = workers[i];
      final workerId = isGuest
          ? (worker['id'] ?? '').toString()
          : (worker['id'] ?? worker['workerId'] ?? '').toString().trim();
      final name = (worker['name'] ?? '').toString();
      final email = (worker['email'] ?? '').toString();
      final salaryStr = PayrollService.currentSalaryDisplay(
        worker,
        companyCurrency: companyCurrency,
      );
      final totalWorkDays = (worker['totalWorkDays'] ?? '').toString();
      final workDays =
          int.tryParse(totalWorkDays) ?? (autoWorkDays > 0 ? autoWorkDays : 30);
      final attendance = attendanceResults[i];
      final attendanceError = (attendance['_error'] ?? '').toString();

      if (!isGuest && attendanceError.isNotEmpty) {
        results.add(
          AutoPayrollResult(
            workerId: workerId,
            workerName: name,
            email: email,
            netSalary: '0',
            success: false,
            error: attendanceError,
            salary: salaryStr,
            currency: companyCurrency,
            totalWorkDays: workDays.toString(),
            position: (worker['position'] ?? '').toString(),
            salaryType: (worker['salaryType'] ?? 'Monthly').toString(),
            imageUrl: (worker['profileImage'] ?? '').toString().isNotEmpty
                ? (worker['profileImage'] ?? '').toString()
                : null,
          ),
        );
        continue;
      }

      final absents = _intValue(attendance['absents']);
      final halfDays = _intValue(attendance['halfDays']);
      final paidLeaves = _intValue(attendance['paidLeaves']);
      final unpaidLeaves = _intValue(attendance['unpaidLeaves']);
      final leaves = _intValue(attendance['leaves']);
      final overtimeAmount = (worker['overtimeAmount'] ?? '').toString();
      final salaryType = (worker['salaryType'] ?? 'Monthly').toString();

      late double absentDeductionTotal;
      late double leaveDeductionTotal;
      String netSalary;
      double rawNetVal = 0;

      try {
        final enteredSalary = PayrollService.extractSalary(salaryStr);
        final periodSalary = salaryType.trim().toLowerCase() == 'annual'
            ? enteredSalary / 12
            : enteredSalary;

        final dailyRate = workDays > 0 ? periodSalary / workDays : 0.0;
        if (isGuest) {
          final absentDeductionPerDay = (worker['absentDeduction'] ?? '')
              .toString()
              .trim();
          final leaveDeductionPerDay = (worker['leaveDeduction'] ?? '')
              .toString()
              .trim();

          absentDeductionTotal = absentDeductionPerDay.isEmpty
              ? dailyRate * absents
              : PayrollService.extractSalary(absentDeductionPerDay) * absents;
          leaveDeductionTotal = leaveDeductionPerDay.isEmpty
              ? dailyRate * unpaidLeaves
              : PayrollService.extractSalary(leaveDeductionPerDay) *
                    unpaidLeaves;
          final effectiveDays = workDays - absents - unpaidLeaves;
          final calc = PayrollService.calculatePayroll(
            salary: salaryStr,
            totalWorkDays: workDays.toString(),
            daysWorked: effectiveDays > 0 ? effectiveDays.toString() : '0',
            absents: absents.toString(),
            leaves: unpaidLeaves.toString(),
            overtimeAmount: overtimeAmount,
            absentDeductionPerDay: absentDeductionPerDay,
            leaveDeductionPerDay: leaveDeductionPerDay,
            salaryType: salaryType,
          );
          netSalary = calc['formattedNet'] as String? ?? '0';
          rawNetVal = (calc['netSalary'] as num?)?.toDouble() ?? 0;
        } else {
          absentDeductionTotal = dailyRate * (absents + (halfDays * 0.5));
          leaveDeductionTotal = dailyRate * unpaidLeaves;
          rawNetVal = PayrollService.calculateNetFromTotals(
            salary: salaryStr,
            overtimeAmount: overtimeAmount,
            absentDeduction: absentDeductionTotal.toString(),
            leaveDeduction: leaveDeductionTotal.toString(),
            salaryType: salaryType,
          );
          final currency = PayrollService.getCurrencyPrefix(salaryStr);
          final prefix = currency.isNotEmpty ? '$currency ' : '';
          netSalary = '$prefix${PayrollService.formatFullNumber(rawNetVal)}';
        }
      } catch (error, stackTrace) {
        if (!isGuest) {
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'SalaryDayPayrollCalculation:$workerId',
          );
        }
        results.add(
          AutoPayrollResult(
            workerId: workerId,
            workerName: name,
            email: email,
            netSalary: '0',
            success: false,
            error: error.toString(),
            absents: absents,
            halfDays: halfDays,
            leaves: leaves,
            paidLeaves: paidLeaves,
            unpaidLeaves: unpaidLeaves,
            salary: salaryStr,
            currency: companyCurrency,
            totalWorkDays: workDays.toString(),
            position: (worker['position'] ?? '').toString(),
            salaryType: salaryType,
            imageUrl: (worker['profileImage'] ?? '').toString().isNotEmpty
                ? (worker['profileImage'] ?? '').toString()
                : null,
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
          halfDays: halfDays,
          leaves: leaves,
          paidLeaves: paidLeaves,
          unpaidLeaves: unpaidLeaves,
          absentDeduction: _editableAmount(absentDeductionTotal),
          leaveDeduction: _editableAmount(leaveDeductionTotal),
          deductionsAreTotals: true,
          overtimeAmount: overtimeAmount,
          salary: salaryStr,
          currency: companyCurrency,
          totalWorkDays: workDays.toString(),
          position: (worker['position'] ?? '').toString(),
          salaryType: salaryType,
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
    var committedCount = 0;

    if (!autoMode) {
      if (!context.mounted) return null;
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
      if (!context.mounted) return null;
      try {
        committedCount = await _commitPayrollRun(
          filteredSummary,
          isGuest,
          context,
        );
      } catch (error, stackTrace) {
        if (!isGuest) {
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'SalaryDayPayrollCommit',
          );
        }
        if (context.mounted) {
          FlashySnackBar.show(
            context,
            message: 'failed_to_save_record'.tr(),
            isError: true,
          );
        }
        return null;
      }

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
      if (!context.mounted) return null;
      try {
        committedCount = await _commitPayrollRun(summary, isGuest, context);
      } catch (error, stackTrace) {
        if (!isGuest) {
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'SalaryDayPayrollCommit',
          );
        }
        if (context.mounted) {
          FlashySnackBar.show(
            context,
            message: 'failed_to_save_record'.tr(),
            isError: true,
          );
        }
        return null;
      }

      if (summary.successCount > 1 && context.mounted) {
        final paidResults = summary.results.where((r) => r.success).toList();
        await _generateAndSaveZip(context, paidResults, summary.periodLabel);
      }
    }

    final completedAllEligible =
        committedCount == committedSummary.successCount &&
        committedSummary.successCount == eligibleWorkerCount &&
        summary.failCount == 0;
    if (isGuest || completedAllEligible) {
      await _markRunComplete(
        periodLabel,
        isGuest: isGuest,
        userId: authService.currentUser?.uid,
      );
    }

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

  Future<PayrollRunSummary?> payAll(
    BuildContext context, {
    DateTime? payrollMonth,
    String? positionFilter,
  }) async {
    final result = await runPayroll(
      context,
      autoMode: false,
      payrollMonth: payrollMonth,
      positionFilter: positionFilter,
    );
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

  Future<DateTime> _loadActivePayrollMonth(
    BuildContext context,
    DateTime referenceDate,
  ) async {
    final fallback = PayrollService.currentPayrollMonth(
      referenceDate: referenceDate,
    );
    final isGuest =
        Provider.of<AuthService>(
          context,
          listen: false,
        ).currentUser?.isAnonymous ??
        false;
    final firestoreService = isGuest
        ? null
        : Provider.of<FirestoreService>(context, listen: false);
    final rawPeriod = isGuest
        ? await PreferencesService.getActivePayrollPeriod()
        : (await firestoreService!.getUserProfile())?['activePayrollPeriod'];
    return PayrollService.parsePayrollPeriodLabel(rawPeriod) ?? fallback;
  }

  String _lastRunPreferenceKey({required bool isGuest, String? userId}) {
    if (isGuest) return _lastRunKey;
    final normalizedUserId = (userId ?? '').trim();
    return normalizedUserId.isEmpty
        ? '${_lastRunKey}_authenticated'
        : '${_lastRunKey}_$normalizedUserId';
  }

  Future<bool> _alreadyRanForPeriod(
    String periodLabel, {
    required bool isGuest,
    String? userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _lastRunPreferenceKey(isGuest: isGuest, userId: userId);
    final lastRun = prefs.getString(key);
    return lastRun == periodLabel;
  }

  Future<void> _markRunComplete(
    String periodLabel, {
    required bool isGuest,
    String? userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _lastRunPreferenceKey(isGuest: isGuest, userId: userId);
    await prefs.setString(key, periodLabel);
  }

  bool _isPaidPayrollForWorker({
    required Map<String, dynamic> record,
    required Map<String, dynamic> worker,
    required DateTime month,
  }) {
    final status = (record['status'] ?? '').toString().trim().toLowerCase();
    if (status != 'paid') return false;
    if (!PayrollService.isRecordInMonth(record, month)) return false;

    final workerId = (worker['id'] ?? worker['workerId'] ?? '')
        .toString()
        .trim();
    final recordWorkerId = (record['workerId'] ?? '').toString().trim();
    if (recordWorkerId.isNotEmpty) {
      return workerId.isNotEmpty && recordWorkerId == workerId;
    }

    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final recordEmail = (record['email'] ?? record['workerEmail'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return workerEmail.isNotEmpty &&
        recordEmail.isNotEmpty &&
        workerEmail == recordEmail;
  }

  Future<int> _commitPayrollRun(
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
          'currency': r.currency,
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
      return summary.results.where((result) => result.success).length;
    }

    final firestoreService = Provider.of<FirestoreService>(
      context,
      listen: false,
    );
    final successfulResults = summary.results.where((r) => r.success).toList();
    final payPeriodDate = DateTime.parse('${summary.periodLabel}-01');
    final latestPayrollSnapshot = await firestoreService.payrollStream.first
        .timeout(const Duration(seconds: 20));
    final latestPayrollRecords = latestPayrollSnapshot.docs
        .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
        .toList();
    final paidSelectionExists = successfulResults.any(
      (result) => latestPayrollRecords.any(
        (record) => _isPaidPayrollForWorker(
          record: record,
          worker: {'id': result.workerId, 'email': result.email},
          month: payPeriodDate,
        ),
      ),
    );
    if (paidSelectionExists) {
      throw StateError('A selected payroll record is already paid');
    }

    final payrollRecords = <Map<String, dynamic>>[];
    final expenseRecords = <Map<String, dynamic>>[];
    final notifications = <Map<String, dynamic>>[];

    for (final r in successfulResults) {
      final payrollIdentity = r.workerId.isNotEmpty
          ? r.workerId
          : r.email.trim().toLowerCase();
      if (payrollIdentity.isEmpty) continue;
      final payrollKey = '${payrollIdentity}_${summary.periodLabel}';
      final record = {
        'workerId': r.workerId,
        'name': r.workerName,
        'email': r.email,
        'status': 'Paid',
        'totalWorkDays': r.totalWorkDays,
        'absents': r.absents.toString(),
        'halfDays': r.halfDays,
        'paidLeaves': r.paidLeaves,
        'unpaidLeaves': r.unpaidLeaves,
        'leaves': r.leaves.toString(),
        'overtimeAmount': r.overtimeAmount,
        'absentDeduction': r.absentDeduction,
        'leaveDeduction': r.leaveDeduction,
        'deductionsAreTotals': r.deductionsAreTotals,
        'salary': r.salary,
        'currency': r.currency,
        'salaryType': r.salaryType,
        'netSalary': r.netSalary,
        'netSalaryAmount': r.rawNetSalaryValue,
        'netSalaryFormatted': r.netSalary,
        'payrollKey': payrollKey,
        'payPeriod': payPeriodDate,
        'cancelledAt': null,
        'lastModified': summary.runDate,
        'payrollDate': summary.runDate,
        'paidAt': summary.runDate,
      };
      payrollRecords.add(record);

      final netAmount = r.rawNetSalaryValue;
      if (netAmount > 0) {
        expenseRecords.add({
          'workerId': r.workerId,
          'workerEmail': r.email.trim().toLowerCase(),
          'name': r.workerName,
          'date': summary.runDate,
          'paidAt': summary.runDate,
          'payPeriod': payPeriodDate,
          'category': 'Salary',
          'amount': netAmount,
          'description':
              'Salary payment for ${r.workerName} (${summary.periodLabel})',
          'payrollKey': payrollKey,
        });
      }

      final amount = r.netSalary;
      if (r.workerName.isNotEmpty) {
        notifications.add({
          'notificationKey': 'payroll_$payrollKey',
          'type': 'payroll_added',
          'title': 'notif_title_payroll'.tr(namedArgs: {'name': r.workerName}),
          'message': amount.isNotEmpty
              ? 'notif_msg_payroll_amount'.tr(
                  namedArgs: {'amount': amount, 'name': r.workerName},
                )
              : 'notif_msg_payroll'.tr(namedArgs: {'name': r.workerName}),
          'data': {'name': r.workerName, 'amount': amount},
        });
      }
    }

    if (payrollRecords.isEmpty) return 0;

    final payrollCount = await firestoreService.addBulkPayrollRecords(
      payrollRecords,
    );
    if (payrollCount != payrollRecords.length) {
      await _rollbackPayrollRecords(firestoreService, payrollRecords);
      throw StateError('Not all payroll records could be saved');
    }

    try {
      await Future.wait(
        expenseRecords.map(
          (expense) => firestoreService.upsertPayrollExpense(
            expense,
            payrollKey: (expense['payrollKey'] ?? '').toString(),
          ),
        ),
      );
    } catch (error) {
      await _rollbackPayrollRecords(firestoreService, payrollRecords);
      rethrow;
    }

    try {
      await firestoreService.addBulkNotifications(notifications);
    } catch (error, stackTrace) {
      ErrorReporter.report(
        error,
        stackTrace,
        context: 'SalaryDayPayrollNotifications',
      );
    }

    return payrollCount;
  }

  Future<void> _rollbackPayrollRecords(
    FirestoreService firestoreService,
    List<Map<String, dynamic>> payrollRecords,
  ) async {
    for (final record in payrollRecords) {
      final payrollKey = (record['payrollKey'] ?? '').toString().trim();
      if (payrollKey.isEmpty) continue;
      try {
        await firestoreService.cancelPayrollRecord(
          payrollId: payrollKey.replaceAll('/', '_'),
          payrollKey: payrollKey,
        );
      } catch (error, stackTrace) {
        ErrorReporter.report(
          error,
          stackTrace,
          context: 'SalaryDayPayrollRollback:$payrollKey',
        );
      }
    }
  }

  Future<void> _generateAndSaveZip(
    BuildContext context,
    List<AutoPayrollResult> selected,
    String periodLabel,
  ) async {
    if (selected.isEmpty) return;

    if (context.mounted) {
      FlashySnackBar.show(context, message: 'generating_invoices'.tr());
    }

    try {
      final archive = Archive();
      final now = DateTime.now();
      Map<String, dynamic> companyProfile = const {};
      try {
        companyProfile =
            await context.read<FirestoreService>().getUserProfile() ?? const {};
      } catch (_) {}
      final payPeriod = periodLabel.isNotEmpty
          ? periodLabel
          : '${now.year}-${now.month.toString().padLeft(2, '0')}';

      for (var index = 0; index < selected.length; index++) {
        final r = selected[index];
        if (!r.success) continue;
        final enteredSalary = PayrollService.extractSalary(r.salary);
        final rawSalary = r.salaryType.trim().toLowerCase() == 'annual'
            ? enteredSalary / 12
            : enteredSalary;
        final workDays = int.tryParse(r.totalWorkDays) ?? 30;
        final dailyRate = workDays > 0 ? rawSalary / workDays : 0.0;
        final absentsInt = r.absents;
        final deductibleLeaves = r.unpaidLeaves;
        final absentEquivalent = absentsInt + (r.halfDays * 0.5);
        final overtimeAmt = PayrollService.extractSalary(r.overtimeAmount);

        final payableDays =
            (workDays - absentsInt - deductibleLeaves - (r.halfDays * 0.5))
                .clamp(0, workDays)
                .toDouble();
        final grossSalary = rawSalary;
        final absentDeductionTotal = PayrollService.extractSalary(
          r.absentDeduction,
        );
        final leaveDeductionTotal = PayrollService.extractSalary(
          r.leaveDeduction,
        );
        final netSalary =
            (grossSalary +
                    overtimeAmt -
                    absentDeductionTotal -
                    leaveDeductionTotal)
                .clamp(0.0, double.infinity);
        final currency = PayrollService.getCurrencySymbol(r.currency);

        final pdfBytes = await InvoiceService.generatePayrollInvoice(
          employeeName: r.workerName,
          email: r.email,
          position: r.position,
          payPeriod: payPeriod,
          totalWorkDays: r.totalWorkDays,
          daysWorked: _formatDayCount(payableDays),
          absents: _formatDayCount(absentEquivalent),
          leaves: deductibleLeaves.toString(),
          overtimeAmount: _invoiceMoney(overtimeAmt, currency),
          salary: r.salary,
          dailyRate: _invoiceMoney(dailyRate, currency),
          grossPay: _invoiceMoney(grossSalary, currency),
          overtimePay: _invoiceMoney(overtimeAmt, currency),
          absentDeduction: _invoiceMoney(absentDeductionTotal, currency),
          leaveDeduction: _invoiceMoney(leaveDeductionTotal, currency),
          totalDeductions: _invoiceMoney(
            absentDeductionTotal + leaveDeductionTotal,
            currency,
          ),
          netSalary: _invoiceMoney(netSalary, currency),
          currency: currency,
          companyName:
              (companyProfile['businessName'] ??
                      companyProfile['companyName'] ??
                      'HRMS Company')
                  .toString(),
          companyAddress: (companyProfile['address'] ?? '').toString(),
          companyEmail: (companyProfile['email'] ?? '').toString(),
          companyPhone:
              (companyProfile['contact1'] ?? companyProfile['phone'] ?? '')
                  .toString(),
          companyId:
              (companyProfile['companyId'] ??
                      companyProfile['businessId'] ??
                      '')
                  .toString(),
          companyStampImageUrl: (companyProfile['companyStampUrl'] ?? '')
              .toString(),
        );

        final sanitizedName = r.workerName
            .replaceAll(RegExp(r'[^\w\s]'), '')
            .trim()
            .replaceAll(RegExp(r'\s+'), '_');
        final safeName = sanitizedName.isNotEmpty
            ? sanitizedName
            : 'worker_${index + 1}';
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
          await FileOpener.open(result);
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

  Future<List<AutoPayrollResult>?> _showReviewDialog(
    BuildContext context,
    PayrollRunSummary summary,
  ) async {
    final isGuest =
        Provider.of<AuthService>(
          context,
          listen: false,
        ).currentUser?.isAnonymous ??
        false;
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

    final positionNormalizer = <String, String>{};
    for (final r in summary.results) {
      final pos = r.position.trim();
      if (pos.isNotEmpty) {
        final key = pos.toLowerCase();
        if (!positionNormalizer.containsKey(key)) {
          positionNormalizer[key] = pos;
        }
      }
    }
    final allPositions = positionNormalizer.values.toList()..sort();

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

                  final filteredSelectedCount = filteredResults
                      .where(
                        (r) => selectedIndices.contains(
                          summary.results.indexOf(r),
                        ),
                      )
                      .length;
                  final filteredPayCount = filteredResults
                      .where(
                        (r) =>
                            r.success &&
                            selectedIndices.contains(
                              summary.results.indexOf(r),
                            ),
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

                                                    _workerAvatar(
                                                      imageUrl: r.imageUrl,
                                                      name: r.workerName,
                                                      size: 44,
                                                      backgroundColor:
                                                          avatarColors[colorIdx
                                                                  .abs() %
                                                              5],
                                                      textColor:
                                                          avatarTextColors[colorIdx
                                                                  .abs() %
                                                              5],
                                                      fontSize: 18,
                                                      allowExtendedSources:
                                                          !isGuest,
                                                    ),
                                                    const SizedBox(width: 14),

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
                                              }
                                            }
                                          }
                                          final value =
                                              PayrollService.formatNumber(
                                                total,
                                              );
                                          return prefix.isEmpty
                                              ? value
                                              : '$prefix $value';
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

                                      GestureDetector(
                                        onTap: filteredPayCount == 0
                                            ? null
                                            : () {
                                                final selected = filteredResults
                                                    .where(
                                                      (r) =>
                                                          r.success &&
                                                          selectedIndices
                                                              .contains(
                                                                summary.results
                                                                    .indexOf(r),
                                                              ),
                                                    )
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
                                            color: filteredPayCount == 0
                                                ? const Color(
                                                    0xFF0247C4,
                                                  ).withValues(alpha: 0.4)
                                                : const Color(0xFF0247C4),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            boxShadow: filteredPayCount > 0
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
                                                    'count':
                                                        '$filteredPayCount',
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

  Future<AutoPayrollResult?> _showWorkerPayrollDetails({
    required BuildContext context,
    required AutoPayrollResult result,
    required int originalIndex,
    required Map<int, TextEditingController> overtimeControllers,
    required PayrollRunSummary summary,
    required double dialogWidth,
    required double dialogHeight,
  }) {
    final isGuest =
        Provider.of<AuthService>(
          context,
          listen: false,
        ).currentUser?.isAnonymous ??
        false;
    final totalWorkDays = int.tryParse(result.totalWorkDays) ?? 30;
    final presents =
        (totalWorkDays -
                result.absents -
                result.leaves -
                (result.halfDays * 0.5))
            .clamp(0, totalWorkDays)
            .toDouble();

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
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
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

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    _workerAvatar(
                                      imageUrl: result.imageUrl,
                                      name: result.workerName,
                                      size: 60,
                                      backgroundColor: const Color(0xFF0F70FF),
                                      textColor: Colors.white,
                                      fontSize: 28,
                                      allowExtendedSources: !isGuest,
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
                                        '${_formatDayCount(presents)} ${'days_suffix'.tr()}',
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
                                            : _zeroAmount(result.salary),
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
                                            : _zeroAmount(result.salary),
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
      r.netSalary = '$p${PayrollService.formatFullNumber(netPayment)}';
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

    _recalcWithDeductions(r, r.customDeduction, onUpdated);
  }

  int _intValue(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '0').toString()) ?? 0;
  }

  String _formatDayCount(num value) {
    final numeric = value.toDouble();
    return numeric == numeric.roundToDouble()
        ? numeric.toStringAsFixed(0)
        : numeric.toStringAsFixed(1);
  }

  String _invoiceMoney(double amount, String currency) {
    if (!amount.isFinite || amount <= 0) return '0';
    final value = PayrollService.formatFullNumber(amount);
    return currency.trim().isEmpty ? value : '${currency.trim()} $value';
  }

  String _zeroAmount(String salary) {
    final currency = PayrollService.getCurrencyPrefix(salary);
    return currency.isEmpty ? '0' : '$currency 0';
  }

  Widget _workerAvatar({
    required String? imageUrl,
    required String name,
    required double size,
    required Color backgroundColor,
    required Color textColor,
    required double fontSize,
    required bool allowExtendedSources,
  }) {
    Widget fallback() {
      return Container(
        width: size,
        height: size,
        color: backgroundColor,
        alignment: Alignment.center,
        child: Text(
          name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?',
          style: TextStyle(
            color: textColor,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            fontFamily: 'SF Pro Display',
          ),
        ),
      );
    }

    final value = (imageUrl ?? '').trim();
    if (value.isEmpty) {
      return ClipOval(child: fallback());
    }

    Widget image;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      image = Image.network(
        value,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : fallback(),
      );
    } else if (!allowExtendedSources) {
      return ClipOval(child: fallback());
    } else if (value.startsWith('data:image')) {
      try {
        final commaIndex = value.indexOf(',');
        if (commaIndex < 0 || commaIndex == value.length - 1) {
          return ClipOval(child: fallback());
        }
        image = Image.memory(
          base64Decode(value.substring(commaIndex + 1)),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback(),
        );
      } catch (_) {
        return ClipOval(child: fallback());
      }
    } else if (value.startsWith('assets/')) {
      image = Image.asset(
        value,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
      );
    } else {
      try {
        final uri = Uri.tryParse(value);
        final path = uri != null && uri.scheme == 'file'
            ? uri.toFilePath()
            : value;
        image = Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback(),
        );
      } catch (_) {
        return ClipOval(child: fallback());
      }
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(child: image),
    );
  }

  String _editableAmount(num amount) {
    return amount % 1 == 0
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }
}
