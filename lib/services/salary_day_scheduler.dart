import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/file_utils.dart';
import '../utils/localization_helper.dart';
import 'dart:io';
import 'firestore_service.dart';
import 'payroll_service.dart';
import 'preferences_service.dart';
import 'dummy_data.dart';
import 'invoice_service.dart';
import 'error_reporter.dart';
import '../utils/currency_utils.dart';
import '../utils/ui_utils.dart';
import '../utils/company_profile_helper.dart';
import '../widgets/amount_text.dart';

Uint8List _encodePayrollInvoiceZip(List<Map<String, Object>> files) {
  final archive = Archive();
  for (final file in files) {
    final name = file['name']! as String;
    final bytes = file['bytes']! as Uint8List;
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  final encoded = ZipEncoder().encode(archive);
  if (encoded.isEmpty) throw StateError('ZIP encoding failed');
  return Uint8List.fromList(encoded);
}

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
  final String employmentType;
  final String salaryType;
  final String? imageUrl;
  double prorationFactor;

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
    this.employmentType = '',
    this.salaryType = 'Monthly',
    this.imageUrl,
    this.prorationFactor = 1.0,
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
    employmentType: employmentType,
    salaryType: salaryType,
    imageUrl: imageUrl,
    prorationFactor: prorationFactor,
  );

  Map<String, dynamic> toCanonicalPayrollRecord({
    required String payrollKey,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime runDate,
  }) {
    final effectiveName = workerName.trim().isNotEmpty
        ? workerName.trim()
        : (email.trim().isNotEmpty ? email.trim() : 'Worker');
    return {
      'workerId': workerId,
      'name': effectiveName,
      'email': email,
      'position': position,
      if (employmentType.trim().isNotEmpty) 'type1': employmentType.trim(),
      if (imageUrl?.trim().isNotEmpty ?? false) 'profileImage': imageUrl,
      'status': 'Paid',
      'totalWorkDays': int.tryParse(totalWorkDays) ?? 0,
      'absents': absents,
      'halfDays': halfDays,
      'paidLeaves': paidLeaves,
      'unpaidLeaves': unpaidLeaves,
      'leaves': leaves,
      'overtimeAmount': PayrollService.extractSalary(overtimeAmount),
      'absentDeduction': PayrollService.extractSalary(absentDeduction),
      'leaveDeduction': PayrollService.extractSalary(leaveDeduction),
      'customDeduction': PayrollService.extractSalary(customDeduction),
      'deductionsAreTotals': true,
      'salary': salary,
      'currency': currency,
      'salaryType': salaryType,
      'netSalary': netSalary,
      'netSalaryAmount': rawNetSalaryValue,
      'netSalaryFormatted': netSalary,
      'prorationFactor': prorationFactor,
      'payrollKey': payrollKey,
      'payPeriod': periodEnd,
      'payPeriodStart': periodStart,
      'payPeriodEnd': periodEnd,
      'dueDate': periodEnd,
      'cancelledAt': null,
      'lastModified': runDate,
      'payrollDate': runDate,
      'paidAt': runDate,
    };
  }
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

class PayrollRunner {
  static final PayrollRunner _instance = PayrollRunner._();
  factory PayrollRunner() => _instance;
  PayrollRunner._();

  bool _runInProgress = false;

  Future<PayrollRunSummary?> runPayroll(
    BuildContext context, {
    bool autoMode = false,
    DateTime? payrollMonth,
    DateTime? payPeriodStart,
    DateTime? payPeriodEnd,
    String? positionFilter,
  }) async {
    final isGuest =
        ProviderScope.containerOf(
          context,
        ).read(authServiceProvider).currentUser?.isAnonymous ??
        false;
    if (isGuest) {
      return _runPayrollInternal(
        context,
        autoMode: autoMode,
        payrollMonth: payrollMonth,
        payPeriodStart: payPeriodStart,
        payPeriodEnd: payPeriodEnd,
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
        payPeriodStart: payPeriodStart,
        payPeriodEnd: payPeriodEnd,
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
    DateTime? payPeriodStart,
    DateTime? payPeriodEnd,
    String? positionFilter,
  }) async {
    final authService = ProviderScope.containerOf(
      context,
    ).read(authServiceProvider);
    final isGuest = authService.currentUser?.isAnonymous ?? false;
    final firestoreService = ProviderScope.containerOf(
      context,
    ).read(firestoreServiceProvider);

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
                  (workerId.isNotEmpty || email.isNotEmpty) &&
                  PayrollService.isWorkerEligibleForPayroll(w);
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
    final effectivePeriodStart =
        payPeriodStart ?? PayrollService.payPeriodStart(effectivePayrollMonth);
    final effectivePeriodEnd =
        payPeriodEnd ?? PayrollService.payPeriodEnd(effectivePayrollMonth);

    // ── Parallel fetch: company profile + payroll snapshot + working days ──
    Map<String, dynamic>? companyProfile;
    List<Map<String, dynamic>> existingPayroll = const [];
    List<Map<String, dynamic>>? preFetchedAttendance;
    int autoWorkDays = 0;

    try {
      if (isGuest) {
        companyProfile = await PreferencesService.getGuestProfileData();
        existingPayroll = List<Map<String, dynamic>>.from(DummyData.payroll);
        autoWorkDays = await firestoreService.getMonthlyWorkingDays(
          month: effectivePayrollMonth,
        );
      } else {
        final results = await Future.wait([
          firestoreService.getUserProfile().catchError((e, st) {
            ErrorReporter.report(
              e,
              st,
              context: 'PayrollRunnerCompanyCurrency',
            );
            return <String, dynamic>{};
          }),
          firestoreService.payrollStream.first.timeout(
            const Duration(seconds: 20),
          ),
          firestoreService
              .getMonthlyWorkingDays(month: effectivePayrollMonth)
              .then((v) => {'_days': v}),
          // Use the same live collection snapshot as Add Payroll. Filtering
          // the Firestore query by month can miss legacy records whose saved
          // attendance date is not a Timestamp, even though the attendance
          // screen and Add Payroll can already see those records.
          firestoreService.attendanceStream.first
              .timeout(const Duration(seconds: 20))
              .then(
                (snapshot) => {
                  '_attendance': snapshot.docs
                      .map(
                        (doc) => {
                          ...doc.data() as Map<String, dynamic>,
                          'id': doc.id,
                        },
                      )
                      .toList(),
                },
              ),
        ]);
        companyProfile = results[0] as Map<String, dynamic>?;
        final payrollDocs = (results[1] as dynamic).docs as List<dynamic>;
        existingPayroll = payrollDocs
            .map(
              (doc) => {
                ...doc.data() as Map<String, dynamic>,
                'id': doc.id as String,
              },
            )
            .toList();
        final daysMap = results[2] as Map<String, dynamic>;
        autoWorkDays = (daysMap['_days'] as int?) ?? 0;
        final attendanceMap = results[3] as Map<String, dynamic>;
        preFetchedAttendance =
            (attendanceMap['_attendance'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
      }
    } catch (error, stackTrace) {
      ErrorReporter.report(
        error,
        stackTrace,
        context: 'PayrollRunnerParallelFetch',
      );
      if (context.mounted) {
        FlashySnackBar.show(
          context,
          message: 'error_occurred'.tr(namedArgs: {'error': error.toString()}),
          isError: true,
        );
      }
      return null;
    }

    if (autoWorkDays <= 0) {
      if (context.mounted) {
        FlashySnackBar.show(
          context,
          message: 'invalid_working_days'.tr(
            namedArgs: {'days': '$autoWorkDays'},
          ),
          isError: true,
        );
      }
      return null;
    }

    final companyCurrency = CurrencyUtils.normalize(
      companyProfile?['currency'],
    );

    List<Map<String, dynamic>> workers2;
    try {
      final payableWorkers = PayrollService.payableWorkersForPeriod(
        workers,
        existingPayroll,
        month: effectivePayrollMonth,
        allowUndatedRecords: isGuest,
        companyCurrency: companyCurrency,
        periodStart: effectivePeriodStart,
        periodEnd: effectivePeriodEnd,
      );
      workers2 = payableWorkers;
    } catch (error, stackTrace) {
      ErrorReporter.report(
        error,
        stackTrace,
        context: 'PayrollRunnerExistingPayrollCheck',
      );
      if (context.mounted) {
        FlashySnackBar.show(
          context,
          message: 'error_occurred'.tr(namedArgs: {'error': error.toString()}),
          isError: true,
        );
      }
      return null;
    }
    workers = workers2;

    final prevPayrollByWorkerId = <String, Map<String, dynamic>>{};
    final prevPayrollByEmail = <String, Map<String, dynamic>>{};
    for (final record in existingPayroll) {
      if (!PayrollService.isRecordInMonth(record, effectivePayrollMonth)) {
        continue;
      }
      final rWorkerId = (record['workerId'] ?? '').toString().trim();
      final rEmail = (record['email'] ?? record['workerEmail'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (rWorkerId.isNotEmpty) prevPayrollByWorkerId[rWorkerId] = record;
      if (rEmail.isNotEmpty) prevPayrollByEmail[rEmail] = record;
    }

    if (workers.isEmpty) return null;

    // ── Attendance fetch — all workers concurrently (max 15 at a time) ──
    late final List<Map<String, dynamic>> attendanceResults;

    if (isGuest) {
      attendanceResults = workers.map((worker) {
        final att = PayrollService.attendanceCounts(worker);
        return <String, dynamic>{
          'absents': att['absents'] ?? 0,
          'paidLeaves': att['paidLeaves'] ?? 0,
          'unpaidLeaves': att['unpaidLeaves'] ?? 0,
          'leaves': att['leaves'] ?? 0,
        };
      }).toList();
    } else {
      attendanceResults = <Map<String, dynamic>>[];
      const maxConcurrent = 15;
      for (var i = 0; i < workers.length; i += maxConcurrent) {
        final batch = workers.skip(i).take(maxConcurrent);
        final batchFutures = batch.map((worker) async {
          final email = (worker['email'] ?? '').toString();
          final workerId = (worker['workerId'] ?? worker['id'] ?? '')
              .toString()
              .trim();
          try {
            final attendance = await firestoreService
                .getWorkerMonthlyAttendance(
                  email,
                  workerId: workerId,
                  month: effectivePayrollMonth,
                  startDate: effectivePeriodStart,
                  endDate: effectivePeriodEnd,
                  preFetchedRecords: preFetchedAttendance,
                );
            return <String, dynamic>{...attendance};
          } catch (error, stackTrace) {
            ErrorReporter.report(
              error,
              stackTrace,
              context: 'PayrollRunnerAttendanceFetch:$workerId',
            );
            return <String, dynamic>{'_error': error.toString()};
          }
        });
        final batchResults = await Future.wait(batchFutures);
        attendanceResults.addAll(batchResults);
      }
    }

    final results = <AutoPayrollResult>[];
    for (int i = 0; i < workers.length; i++) {
      final worker = workers[i];
      final workerId = isGuest
          ? (worker['id'] ?? '').toString()
          : (worker['workerId'] ?? worker['id'] ?? '').toString().trim();
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

      if (PayrollService.extractSalary(salaryStr) <= 0) {
        results.add(
          AutoPayrollResult(
            workerId: workerId,
            workerName: name,
            email: email,
            netSalary: '0',
            success: false,
            error: 'please_enter_salary'.tr(),
            salary: salaryStr,
            currency: companyCurrency,
            totalWorkDays: totalWorkDays,
            position: (worker['position'] ?? '').toString(),
            employmentType: PayrollService.workerEmploymentType(worker),
            salaryType: (worker['salaryType'] ?? 'Monthly').toString(),
            imageUrl: (worker['profileImage'] ?? '').toString().isNotEmpty
                ? (worker['profileImage'] ?? '').toString()
                : null,
          ),
        );
        continue;
      }

      const prorationFactor = 1.0;

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
            employmentType: PayrollService.workerEmploymentType(worker),
            salaryType: (worker['salaryType'] ?? 'Monthly').toString(),
            prorationFactor: prorationFactor,
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

      Map<String, dynamic>? prevRecord;
      if (workerId.isNotEmpty) {
        prevRecord = prevPayrollByWorkerId[workerId];
      }
      if (prevRecord == null && email.isNotEmpty) {
        prevRecord = prevPayrollByEmail[email.toLowerCase()];
      }

      final workerOvertime = (worker['overtimeAmount'] ?? '').toString().trim();
      final prevOvertime = (prevRecord?['overtimeAmount'] ?? '')
          .toString()
          .trim();
      final overtimeAmount = workerOvertime.isNotEmpty
          ? workerOvertime
          : prevOvertime;
      final salaryType = (worker['salaryType'] ?? 'Monthly').toString();
      final prevCustomDeduction = PayrollService.extractSalary(
        (prevRecord?['customDeduction'] ?? '0').toString(),
      );

      double absentDeductionTotal = 0;
      late double leaveDeductionTotal;
      String netSalary;
      double rawNetVal = 0;

      try {
        final enteredSalary = PayrollService.extractSalary(salaryStr);
        final periodSalary = salaryType.trim().toLowerCase() == 'annual'
            ? enteredSalary / 12
            : enteredSalary;
        final dailyRate = workDays > 0 ? periodSalary / workDays : 0.0;
        leaveDeductionTotal = dailyRate * unpaidLeaves;

        // Absence attendance enables the editable deduction field, but HR is
        // responsible for choosing the amount. Never infer it from daily rate
        // or carry it forward from a previous payroll period.
        absentDeductionTotal = 0;
        rawNetVal = PayrollService.calculateNetFromTotals(
          salary: salaryStr,
          overtimeAmount: overtimeAmount,
          absentDeduction: '0',
          leaveDeduction: leaveDeductionTotal.toString(),
          customDeduction: prevCustomDeduction.toString(),
          salaryType: salaryType,
          prorationFactor: prorationFactor,
        );
        final currency = PayrollService.getCurrencyPrefix(salaryStr);
        final prefix = currency.isNotEmpty ? '$currency ' : '';
        netSalary = '$prefix${PayrollService.formatFullNumber(rawNetVal)}';
      } catch (error, stackTrace) {
        if (!isGuest) {
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'PayrollRunnerCalculation:$workerId',
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
            employmentType: PayrollService.workerEmploymentType(worker),
            salaryType: salaryType,
            prorationFactor: prorationFactor,
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
          customDeduction: _editableAmount(prevCustomDeduction),
          deductionsAreTotals: true,
          overtimeAmount: overtimeAmount,
          salary: salaryStr,
          currency: companyCurrency,
          totalWorkDays: workDays.toString(),
          position: (worker['position'] ?? '').toString(),
          employmentType: PayrollService.workerEmploymentType(worker),
          salaryType: salaryType,
          prorationFactor: prorationFactor,
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
      FlashySnackBar.show(context, message: 'processing_payroll'.tr());
      try {
        await _commitPayrollRun(
          filteredSummary,
          isGuest,
          context,
          periodStart: effectivePeriodStart,
          periodEnd: effectivePeriodEnd,
        );
      } catch (error, stackTrace) {
        if (!isGuest) {
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'PayrollRunnerCommit',
          );
        }
        if (context.mounted) {
          final msg = error is StateError && error.message.isNotEmpty
              ? error.message
              : (error.toString().isNotEmpty
                    ? error.toString()
                    : 'failed_to_save_record'.tr());
          FlashySnackBar.show(context, message: msg, isError: true);
        }
        return null;
      }

      if (filteredSummary.successCount >= 1 && context.mounted) {
        final paidResults = filteredSummary.results
            .where((r) => r.success)
            .toList();
        await _generateAndSaveZip(
          context,
          paidResults,
          filteredSummary.periodLabel,
          companyProfile ?? const <String, dynamic>{},
          periodStart: effectivePeriodStart,
          periodEnd: effectivePeriodEnd,
        );
      }
    } else {
      if (!context.mounted) return null;
      try {
        await _commitPayrollRun(
          summary,
          isGuest,
          context,
          periodStart: effectivePeriodStart,
          periodEnd: effectivePeriodEnd,
        );
      } catch (error, stackTrace) {
        if (!isGuest) {
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'PayrollRunnerCommit',
          );
        }
        if (context.mounted) {
          final msg = error is StateError && error.message.isNotEmpty
              ? error.message
              : (error.toString().isNotEmpty
                    ? error.toString()
                    : 'failed_to_save_record'.tr());
          FlashySnackBar.show(context, message: msg, isError: true);
        }
        return null;
      }

      if (summary.successCount >= 1 && context.mounted) {
        final paidResults = summary.results.where((r) => r.success).toList();
        await _generateAndSaveZip(
          context,
          paidResults,
          summary.periodLabel,
          companyProfile ?? const <String, dynamic>{},
          periodStart: effectivePeriodStart,
          periodEnd: effectivePeriodEnd,
        );
      }
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
    DateTime? payPeriodStart,
    DateTime? payPeriodEnd,
    String? positionFilter,
  }) async {
    final result = await runPayroll(
      context,
      autoMode: false,
      payrollMonth: payrollMonth,
      payPeriodStart: payPeriodStart,
      payPeriodEnd: payPeriodEnd,
      positionFilter: positionFilter,
    );
    return result;
  }

  bool _isPaidPayrollForWorker({
    required Map<String, dynamic> record,
    required Map<String, dynamic> worker,
    required DateTime month,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) {
    final status = (record['status'] ?? '').toString().trim().toLowerCase();
    if (status != 'paid') return false;
    if (periodStart != null && periodEnd != null) {
      if (!PayrollService.isRecordInPayPeriod(record, periodStart, periodEnd)) {
        return false;
      }
    } else if (!PayrollService.isRecordInMonth(record, month)) {
      return false;
    }

    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    final recordWorkerId = (record['workerId'] ?? '').toString().trim();
    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final recordEmail = (record['email'] ?? record['workerEmail'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    final idMatches =
        workerId.isNotEmpty &&
        recordWorkerId.isNotEmpty &&
        recordWorkerId == workerId;
    final emailMatches =
        workerEmail.isNotEmpty &&
        recordEmail.isNotEmpty &&
        workerEmail == recordEmail;
    return idMatches || emailMatches;
  }

  Future<int> _commitPayrollRun(
    PayrollRunSummary summary,
    bool isGuest,
    BuildContext context, {
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    if (isGuest) {
      final savedPayroll = DummyData.payroll.toList();
      final savedExpenses = DummyData.expenses.toList();
      try {
        for (final r in summary.results) {
          if (!r.success) continue;
          final payrollIdentity = r.workerId.isNotEmpty
              ? r.workerId
              : r.email.trim().toLowerCase();
          final payrollKey = PayrollService.payrollKeyForPeriod(
            payrollIdentity,
            periodStart,
            periodEnd,
          );
          final nowIso = DateTime.now().toIso8601String();
          final canonicalRecord = r.toCanonicalPayrollRecord(
            payrollKey: payrollKey,
            periodStart: periodStart,
            periodEnd: periodEnd,
            runDate: summary.runDate,
          );
          final record = {
            ...canonicalRecord,
            'payPeriod': periodEnd.toIso8601String(),
            'payPeriodStart': periodStart.toIso8601String(),
            'payPeriodEnd': periodEnd.toIso8601String(),
            'dueDate': periodEnd.toIso8601String(),
            'lastModified': summary.runDate.toIso8601String(),
            'createdAt': nowIso,
            'payrollDate': summary.runDate.toIso8601String(),
            'paidAt': summary.runDate.toIso8601String(),
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
              'date': summary.runDate.toIso8601String(),
              'category': 'Salary',
              'amount': netAmount,
              'description':
                  'Salary payment for ${r.workerName} (${summary.periodLabel})',
              'payrollKey': payrollKey,
            };
            final expenseId =
                'dummy_e${DateTime.now().microsecondsSinceEpoch}_${r.email.hashCode}';
            final expenseIndex = DummyData.expenses.indexWhere(
              (expense) =>
                  (expense['payrollKey'] ?? '').toString() == payrollKey,
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
      } catch (_) {
        DummyData.payroll
          ..clear()
          ..addAll(savedPayroll);
        DummyData.expenses
          ..clear()
          ..addAll(savedExpenses);
        rethrow;
      }
      return summary.results.where((result) => result.success).length;
    }

    final firestoreService = ProviderScope.containerOf(
      context,
    ).read(firestoreServiceProvider);
    final successfulResults = summary.results.where((r) => r.success).toList();
    final payPeriodDate = periodEnd;
    final latestPayrollSnapshot = await firestoreService.payrollStream.first
        .timeout(const Duration(seconds: 20));
    final latestPayrollRecords = latestPayrollSnapshot.docs
        .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
        .toList();
    final unpaidResults = successfulResults.where((result) {
      final isAlreadyPaid = latestPayrollRecords.any(
        (record) => _isPaidPayrollForWorker(
          record: record,
          worker: {'id': result.workerId, 'email': result.email},
          month: payPeriodDate,
          periodStart: periodStart,
          periodEnd: periodEnd,
        ),
      );
      return !isAlreadyPaid;
    }).toList();

    if (unpaidResults.isEmpty) {
      throw StateError(
        'selected_workers_already_paid'.tr().isNotEmpty
            ? 'selected_workers_already_paid'.tr()
            : 'Selected workers are already paid for this period',
      );
    }

    final payrollRecords = <Map<String, dynamic>>[];
    final expenseRecords = <Map<String, dynamic>>[];
    final notifications = <Map<String, dynamic>>[];

    for (final r in unpaidResults) {
      final payrollIdentity = r.workerId.isNotEmpty
          ? r.workerId
          : r.email.trim().toLowerCase();
      if (payrollIdentity.isEmpty) continue;
      final payrollKey = PayrollService.payrollKeyForPeriod(
        payrollIdentity,
        periodStart,
        periodEnd,
      );
      final record = r.toCanonicalPayrollRecord(
        payrollKey: payrollKey,
        periodStart: periodStart,
        periodEnd: periodEnd,
        runDate: summary.runDate,
      );
      payrollRecords.add(record);

      final effectiveWorkerName = r.workerName.trim().isNotEmpty
          ? r.workerName.trim()
          : (r.email.trim().isNotEmpty ? r.email.trim() : 'Worker');

      final netAmount = r.rawNetSalaryValue;
      if (netAmount > 0) {
        expenseRecords.add({
          'workerId': r.workerId,
          'workerEmail': r.email.trim().toLowerCase(),
          'name': effectiveWorkerName,
          'date': summary.runDate,
          'paidAt': summary.runDate,
          'payPeriod': periodEnd,
          'payPeriodStart': periodStart,
          'payPeriodEnd': periodEnd,
          'category': 'Salary',
          'amount': netAmount,
          'description':
              'Salary payment for $effectiveWorkerName (${summary.periodLabel})',
          'payrollKey': payrollKey,
        });
      }

      final amount = r.netSalary;
      notifications.add({
        'notificationKey': 'payroll_$payrollKey',
        'type': 'payroll_added',
        'title': 'notif_title_payroll'.tr(
          namedArgs: {'name': effectiveWorkerName},
        ),
        'message': amount.isNotEmpty
            ? 'notif_msg_payroll_amount'.tr(
                namedArgs: {'amount': amount, 'name': effectiveWorkerName},
              )
            : 'notif_msg_payroll'.tr(namedArgs: {'name': effectiveWorkerName}),
        'data': {'name': effectiveWorkerName, 'amount': amount},
      });
    }

    if (payrollRecords.isEmpty) return 0;

    final payrollCount = await firestoreService.addBulkPayrollRecords(
      payrollRecords,
    );
    if (payrollCount != payrollRecords.length) {
      await _rollbackPayrollRecords(firestoreService, payrollRecords);
      throw StateError('Not all payroll records could be saved');
    }

    final notificationFuture = firestoreService
        .addBulkNotifications(notifications)
        .catchError((error, stackTrace) {
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'PayrollRunnerNotifications',
          );
        });

    try {
      await firestoreService.upsertBulkPayrollExpenses(expenseRecords);
    } catch (error) {
      await _rollbackPayrollRecords(firestoreService, payrollRecords);
      rethrow;
    }
    await notificationFuture;

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
          context: 'PayrollRunnerRollback:$payrollKey',
        );
      }
    }
  }

  Future<void> _generateAndSaveZip(
    BuildContext context,
    List<AutoPayrollResult> selected,
    String periodLabel,
    Map<String, dynamic> companyProfile, {
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    if (selected.isEmpty) return;

    if (context.mounted) {
      FlashySnackBar.show(context, message: 'generating_invoices'.tr());
    }

    try {
      final now = DateTime.now();
      final payPeriod = periodLabel.isNotEmpty
          ? periodLabel
          : '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final periodDisplay = PayrollService.formatPayPeriodRange(
        periodStart,
        periodEnd,
      );

      final companyLogoUrl = (companyProfile['profilePicUrl'] ?? '').toString();
      final companyStampUrl = (companyProfile['companyStampUrl'] ?? '')
          .toString();
      final sharedAssets = await Future.wait<Uint8List?>([
        InvoiceService.resolveCompanyLogoBytes(companyLogoUrl),
        InvoiceService.resolveCompanyStampBytes(companyStampUrl),
      ]);
      final companyLogoBytes = sharedAssets[0];
      final companyStampBytes = sharedAssets[1];

      Future<Map<String, Object>> generateInvoice(
        int index,
        AutoPayrollResult r,
      ) async {
        final enteredSalary = PayrollService.extractSalary(r.salary);
        final rawSalary = r.salaryType.trim().toLowerCase() == 'annual'
            ? enteredSalary / 12
            : enteredSalary;
        final workDays = int.tryParse(r.totalWorkDays) ?? 30;
        final absentsInt = r.absents;
        final deductibleLeaves = r.unpaidLeaves;
        final absentEquivalent = absentsInt + (r.halfDays * 0.5);
        final overtimeAmt = PayrollService.extractSalary(r.overtimeAmount);

        final payableDays =
            (workDays - absentsInt - deductibleLeaves - (r.halfDays * 0.5))
                .clamp(0, workDays)
                .toDouble();
        final grossSalary = rawSalary * r.prorationFactor;
        final absentDeductionTotal = PayrollService.extractSalary(
          r.absentDeduction,
        );
        final leaveDeductionTotal = PayrollService.extractSalary(
          r.leaveDeduction,
        );
        final totalDeductions =
            PayrollService.extractSalary(r.customDeduction) +
            absentDeductionTotal +
            leaveDeductionTotal;
        final netSalary = (grossSalary + overtimeAmt - totalDeductions).clamp(
          0.0,
          double.infinity,
        );
        final currency = PayrollService.getCurrencySymbol(r.currency);

        final pdfBytes = await InvoiceService.generatePayrollInvoice(
          employeeName: r.workerName,
          email: r.email,
          position: r.position,
          payPeriod: periodDisplay,
          totalWorkDays: r.totalWorkDays,
          daysWorked: _formatDayCount(payableDays),
          absents: _formatDayCount(absentEquivalent),
          leaves: r.leaves.toString(),
          paidLeaves: r.paidLeaves.toString(),
          unpaidLeaves: r.unpaidLeaves.toString(),
          overtimeAmount: _invoiceMoney(overtimeAmt, currency),
          salary: r.salary,
          dailyRate: _invoiceMoney(
            workDays > 0 ? grossSalary / workDays : 0.0,
            currency,
          ),
          grossPay: _invoiceMoney(grossSalary, currency),
          overtimePay: _invoiceMoney(overtimeAmt, currency),
          absentDeduction: _invoiceMoney(absentDeductionTotal, currency),
          leaveDeduction: _invoiceMoney(leaveDeductionTotal, currency),
          totalDeductions: _invoiceMoney(totalDeductions, currency),
          netSalary: _invoiceMoney(netSalary, currency),
          currency: currency,
          companyName: CompanyProfileHelper.companyNameOrFallback(
            companyProfile['companyName'],
          ),
          companyAddress: (companyProfile['address'] ?? '').toString(),
          companyEmail: (companyProfile['email'] ?? '').toString(),
          companyPhone: (companyProfile['phone'] ?? '').toString(),
          companyId: (companyProfile['companyId'] ?? '').toString(),
          companyLogoBytes: companyLogoBytes,
          companyStampBytes: companyStampBytes,
          workerId: r.workerId,
        );

        final sanitizedName = r.workerName
            .replaceAll(RegExp(r'[^\w\s]'), '')
            .trim()
            .replaceAll(RegExp(r'\s+'), '_');
        final safeName = sanitizedName.isNotEmpty
            ? sanitizedName
            : 'worker_${index + 1}';
        return <String, Object>{
          // Keep every invoice unique even when workers share the same name.
          'name': '${safeName}_${index + 1}_invoice_$payPeriod.pdf',
          'bytes': pdfBytes,
        };
      }

      final successful = selected.where((result) => result.success).toList();
      final invoiceFiles = <Map<String, Object>>[];
      const maxParallelPdfs = 4;
      for (var start = 0; start < successful.length; start += maxParallelPdfs) {
        final end = (start + maxParallelPdfs)
            .clamp(0, successful.length)
            .toInt();
        final generated = await Future.wait(
          List.generate(
            end - start,
            (offset) =>
                generateInvoice(start + offset, successful[start + offset]),
          ),
        );
        invoiceFiles.addAll(generated);
      }
      if (invoiceFiles.isEmpty) return;

      // ZIP compression is CPU-heavy; keep it off the desktop UI isolate.
      final zipData = await compute(_encodePayrollInvoiceZip, invoiceFiles);
      final fileName = 'payroll_invoices_$payPeriod.zip';

      final result = await FilePicker.saveFile(
        dialogTitle: 'save_payroll_invoices_zip'.tr(),
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: zipData,
      );

      if (result != null) {
        // file_picker writes the supplied bytes on desktop. Verify the result
        // before reporting success and repair an incomplete write if needed.
        final savedZip = File(result);
        final exists = await savedZip.exists();
        final savedLength = exists ? await savedZip.length() : 0;
        if (!exists || savedLength != zipData.length) {
          await savedZip.writeAsBytes(zipData, flush: true);
        }

        if (context.mounted) {
          FlashySnackBar.show(
            context,
            message: 'zip_saved'.tr(namedArgs: {'fileName': fileName}),
          );
        }
        unawaited(FileOpener.open(result));
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
        ProviderScope.containerOf(
          context,
        ).read(authServiceProvider).currentUser?.isAnonymous ??
        false;
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 600 ? screenWidth * 0.95 : 580.0;
    final dialogHeight = screenWidth < 600 ? 540.0 : 560.0;

    String searchQuery = '';
    String positionFilter = 'All';
    Set<int> selectedIndices = {};
    int? activeDetailIndex;
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
          positionNormalizer[key] = pos
              .split(' ')
              .map((word) {
                if (word.isEmpty) return word;
                return word[0].toUpperCase() + word.substring(1);
              })
              .join(' ');
        }
      }
    }
    final allPositions = positionNormalizer.values.toList()..sort();

    return showGeneralDialog<List<AutoPayrollResult>>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'PayrollReviewDialog',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: 10 * animation.value,
                sigmaY: 10 * animation.value,
              ),
              child: Container(
                color: const Color(
                  0xFF0F172A,
                ).withValues(alpha: 0.35 * animation.value),
              ),
            ),
            FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: curve,
                child: StatefulBuilder(
                  builder: (context, setDialogState) {
                    List<AutoPayrollResult> posFiltered;
                    if (positionFilter == 'All') {
                      posFiltered =
                          List<AutoPayrollResult>.from(summary.results)..sort(
                            (a, b) => a.workerName
                                .trim()
                                .toLowerCase()
                                .compareTo(b.workerName.trim().toLowerCase()),
                          );
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
                            borderRadius: BorderRadius.circular(6),
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
                              Container(
                                height: 48,
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                color: const Color(0xFF004FDE),
                                child: Row(
                                  children: [
                                    MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: GestureDetector(
                                        onTap: () {
                                          if (activeDetailIndex != null) {
                                            setDialogState(
                                              () => activeDetailIndex = null,
                                            );
                                          } else {
                                            Navigator.of(context).pop();
                                          }
                                        },
                                        child: SizedBox(
                                          width: 32,
                                          height: 32,
                                          child: Icon(
                                            activeDetailIndex != null
                                                ? Icons.arrow_back_rounded
                                                : Icons.close_rounded,
                                            color: const Color(0xFFFFFFFF),
                                            size: 21,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Center(
                                        child: Text(
                                          activeDetailIndex != null
                                              ? 'payroll_details_title'
                                                    .tr(
                                                      namedArgs: {
                                                        'name': summary
                                                            .results[activeDetailIndex!]
                                                            .workerName,
                                                      },
                                                    )
                                                    .trim()
                                              : 'payroll_run_review'.tr(),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFFFFFFF),
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 32),
                                  ],
                                ),
                              ),
                              if (activeDetailIndex != null)
                                Expanded(
                                  child: _buildInlineWorkerDetailView(
                                    context: context,
                                    result: summary.results[activeDetailIndex!],
                                    originalIndex: activeDetailIndex!,
                                    overtimeControllers: overtimeControllers,
                                    onBack: () => setDialogState(
                                      () => activeDetailIndex = null,
                                    ),
                                    isGuest: isGuest,
                                    setDialogState: setDialogState,
                                  ),
                                )
                              else ...[
                                const SizedBox(height: 12),

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
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 8,
                                              horizontal: 12,
                                            ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFE5E7EB),
                                            width: 1,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFE5E7EB),
                                            width: 1,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                                            selectedColor: const Color(
                                              0xFF0C51C1,
                                            ),
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
                                              fontWeight:
                                                  positionFilter == 'All'
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
                                          ...allPositions.map(
                                            (pos) => Padding(
                                              padding: const EdgeInsets.only(
                                                left: 8,
                                              ),
                                              child: ChoiceChip(
                                                label: Text(
                                                  LocalizationHelper.localizePosition(
                                                    pos,
                                                  ),
                                                ),
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
                                                checkmarkColor:
                                                    Colors.transparent,
                                                showCheckmark: false,
                                                side: positionFilter == pos
                                                    ? null
                                                    : const BorderSide(
                                                        color: Color(
                                                          0xFFE5E7EB,
                                                        ),
                                                      ),
                                                labelStyle: TextStyle(
                                                  color: positionFilter == pos
                                                      ? Colors.white
                                                      : const Color(0xFF111827),
                                                  fontSize: 12,
                                                  fontWeight:
                                                      positionFilter == pos
                                                      ? FontWeight.w600
                                                      : FontWeight.w500,
                                                  fontFamily: 'SF Pro Display',
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
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
                                              borderRadius:
                                                  BorderRadius.circular(12),
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
                                            final filteredIndices =
                                                filteredResults
                                                    .map(
                                                      (r) => summary.results
                                                          .indexOf(r),
                                                    )
                                                    .toSet();
                                            final allFilteredSelected =
                                                filteredIndices.every(
                                                  (i) => selectedIndices
                                                      .contains(i),
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
                                                  (r) =>
                                                      selectedIndices.contains(
                                                        summary.results.indexOf(
                                                          r,
                                                        ),
                                                      ),
                                                )
                                                ? const Color(0xFFFEE2E2)
                                                : const Color(0xFFEEF2FF),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                filteredResults.every(
                                                      (r) => selectedIndices
                                                          .contains(
                                                            summary.results
                                                                .indexOf(r),
                                                          ),
                                                    )
                                                    ? Icons.deselect
                                                    : Icons.select_all,
                                                size: 15,
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
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                filteredResults.every(
                                                      (r) => selectedIndices
                                                          .contains(
                                                            summary.results
                                                                .indexOf(r),
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
                                            final originalIndex = summary
                                                .results
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
                                                posLower.contains(
                                                  'freelance',
                                                ) ||
                                                stLower.contains('contract') ||
                                                stLower.contains('freelance') ||
                                                (stLower != 'monthly' &&
                                                    stLower.isNotEmpty);
                                            final storedEmploymentType = r
                                                .employmentType
                                                .trim();
                                            final typeLabel =
                                                storedEmploymentType.isNotEmpty
                                                ? LocalizationHelper.localizeType1(
                                                    storedEmploymentType,
                                                  ).toUpperCase()
                                                : isContractorWorker
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
                                                          ).withValues(
                                                            alpha: 0.3,
                                                          )
                                                        : const Color(
                                                            0xFFE5E7EB,
                                                          ),
                                                    width: 1.2,
                                                  ),
                                                ),
                                                child: InkWell(
                                                  onTap: () {
                                                    setDialogState(() {
                                                      activeDetailIndex =
                                                          originalIndex;
                                                    });
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
                                                                color:
                                                                    isSelected
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
                                                        const SizedBox(
                                                          width: 14,
                                                        ),

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
                                                        const SizedBox(
                                                          width: 14,
                                                        ),

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
                                                                            FontWeight.bold,
                                                                        fontFamily:
                                                                            'SF Pro Display',
                                                                        color: Color(
                                                                          0xFF111827,
                                                                        ),
                                                                      ),
                                                                      maxLines:
                                                                          1,
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  Container(
                                                                    padding: const EdgeInsets.symmetric(
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
                                                                            FontWeight.w700,
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
                                                                          : 'no_email'.tr(),
                                                                      style: const TextStyle(
                                                                        fontSize:
                                                                            13,
                                                                        color: Color(
                                                                          0xFF6B7280,
                                                                        ),
                                                                        fontFamily:
                                                                            'SF Pro Display',
                                                                      ),
                                                                      maxLines:
                                                                          1,
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
                                                        const SizedBox(
                                                          width: 10,
                                                        ),

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
                                                                    FontWeight
                                                                        .w600,
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
                                                                    horizontal:
                                                                        14,
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
                                                                  locale: context
                                                                      .locale
                                                                      .toString(),
                                                                ),
                                                                style: TextStyle(
                                                                  fontSize: 14,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  fontFamily:
                                                                      'SF Pro Display',
                                                                  color:
                                                                      r.success
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
                                                        const SizedBox(
                                                          width: 6,
                                                        ),

                                                        const Icon(
                                                          Icons
                                                              .chevron_right_rounded,
                                                          size: 22,
                                                          color: Color(
                                                            0xFF9CA3AF,
                                                          ),
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
                                              for (final r in filteredResults) {
                                                final idx = summary.results
                                                    .indexOf(r);
                                                if (selectedIndices.contains(
                                                      idx,
                                                    ) &&
                                                    r.success &&
                                                    r
                                                        .rawNetSalaryValue
                                                        .isFinite) {
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
                                                    locale: context.locale
                                                        .toString(),
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
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 22,
                                                  ),
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF1F5F9),
                                                borderRadius:
                                                    BorderRadius.circular(8),
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
                                                                    summary
                                                                        .results
                                                                        .indexOf(
                                                                          r,
                                                                        ),
                                                                  ),
                                                        )
                                                        .toList();
                                                    Navigator.of(
                                                      context,
                                                    ).pop(selected);
                                                  },
                                            child: Container(
                                              height: 48,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 22,
                                                  ),
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: filteredPayCount == 0
                                                    ? const Color(
                                                        0xFF0247C4,
                                                      ).withValues(alpha: 0.4)
                                                    : const Color(0xFF0247C4),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                boxShadow: filteredPayCount > 0
                                                    ? [
                                                        BoxShadow(
                                                          color:
                                                              const Color(
                                                                0xFF0247C4,
                                                              ).withValues(
                                                                alpha: 0.2,
                                                              ),
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
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontFamily:
                                                          'SF Pro Display',
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
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInlineWorkerDetailView({
    required BuildContext context,
    required AutoPayrollResult result,
    required int originalIndex,
    required Map<int, TextEditingController> overtimeControllers,
    required VoidCallback onBack,
    required bool isGuest,
    required StateSetter setDialogState,
  }) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _workerAvatar(
                          imageUrl: result.imageUrl,
                          name: result.workerName,
                          size: 52,
                          backgroundColor: const Color(0xFF0F70FF),
                          textColor: Colors.white,
                          fontSize: 24,
                          allowExtendedSources: !isGuest,
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              result.workerName,
                              style: const TextStyle(
                                fontSize: 18,
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
                          'net_pay'.tr(),
                          style: const TextStyle(
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
                            locale: context.locale.toString(),
                          ),
                          style: const TextStyle(
                            fontSize: 28,
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

                const SizedBox(height: 24),

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
                            'absents'.tr(),
                            '${result.absents}',
                            const Color(0xFFF9FAFB),
                            const Color(0xFF6B7280),
                            const Color(0xFF111827),
                          ),
                          _metricRow(
                            'leaves_label'.tr(),
                            '${result.paidLeaves}',
                            const Color(0xFFF9FAFB),
                            const Color(0xFF6B7280),
                            const Color(0xFF111827),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
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
                                    locale: context.locale.toString(),
                                  )
                                : _zeroAmount(result.salary),
                            const Color(0xFFF9FAFB),
                            const Color(0xFF6B7280),
                            const Color(0xFF111827),
                          ),
                          _metricRow(
                            'overtime_amount'.tr(),
                            AmountText.formatCompact(
                              '${CurrencyUtils.symbolFor(result.currency)} '
                              '${PayrollService.extractSalary(result.overtimeAmount)}',
                              locale: context.locale.toString(),
                            ),
                            const Color(0xFFECFDF5),
                            const Color(0xFF10B981),
                            const Color(0xFF10B981),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
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
                            currencySymbol: CurrencyUtils.symbolFor(
                              result.currency,
                            ),
                            enabled:
                                (result.absents > 0 || result.halfDays > 0) &&
                                _maximumAbsentDeduction(result) > 0,
                            maximumValue: _maximumAbsentDeduction(result),
                            onChanged: (val) {
                              result.absentDeduction = val;
                              _recalcWithDeductions(
                                result,
                                result.customDeduction,
                                () => setDialogState(() {}),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: const Color(0xFFF3F4F6),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
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
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.more_time,
                          color: Color(0xFF0F70FF),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'adjust_overtime'.tr(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF111827),
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'apply_additional_hours'.tr(),
                              style: const TextStyle(
                                fontSize: 11,
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
                        setDialogState,
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
            border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: onBack,
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0247C4),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0247C4).withValues(alpha: 0.2),
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
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
    required String currencySymbol,
    required bool enabled,
    required double maximumValue,
    required void Function(String) onChanged,
  }) {
    if (!controllers.containsKey(controllerKey)) {
      final initialValue = PayrollService.extractSalary(value);
      controllers[controllerKey] = TextEditingController(
        text: enabled && initialValue > 0
            ? value.replaceAll(RegExp(r'[^0-9.]'), '')
            : '',
      );
    }
    final controller = controllers[controllerKey]!;
    final currentValue = PayrollService.extractSalary(controller.text);
    if (!enabled || currentValue > maximumValue) {
      final normalizedValue = enabled ? maximumValue : 0.0;
      final normalizedText = _editableAmount(normalizedValue);
      controller.value = TextEditingValue(
        text: normalizedText,
        selection: TextSelection.collapsed(offset: normalizedText.length),
      );
    }
    final accentColor = enabled
        ? const Color(0xFFEF4444)
        : const Color(0xFF9CA3AF);
    final borderColor = enabled
        ? const Color(0xFFFECACA)
        : const Color(0xFFE5E7EB);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFFFEF2F2) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: accentColor,
                fontFamily: 'SF Pro Display',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: TextField(
              controller: controller,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                CommaCurrencyFormatter(),
                LengthLimitingTextInputFormatter(14),
              ],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: 'SF Pro Display',
                color: accentColor,
              ),
              textAlign: TextAlign.end,
              decoration: InputDecoration(
                prefixText: '$currencySymbol ',
                prefixStyle: TextStyle(
                  color: accentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'SF Pro Display',
                ),
                hintText: '0',
                hintStyle: TextStyle(
                  color: accentColor.withValues(alpha: 0.4),
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
                  borderSide: BorderSide(color: borderColor, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: borderColor, width: 1),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: borderColor, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(
                    color: Color(0xFFEF4444),
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: (rawValue) {
                final requested = PayrollService.extractSalary(rawValue);
                final capped = requested.clamp(0.0, maximumValue).toDouble();
                if (capped != requested) {
                  final cappedText = _editableAmount(capped);
                  controller.value = TextEditingValue(
                    text: cappedText,
                    selection: TextSelection.collapsed(
                      offset: cappedText.length,
                    ),
                  );
                }
                onChanged(_editableAmount(capped));
              },
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
      final overtimeValue = PayrollService.extractSalary(r.overtimeAmount);
      controllers[controllerKey] = TextEditingController(
        text: overtimeValue > 0
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
              prefixText: '${CurrencyUtils.symbolFor(r.currency)} ',
              prefixStyle: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
              ),
              hintText: 'amount_hint'.tr(),
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
      final absentDeduction = PayrollService.cappedAbsentDeduction(
        hasAbsences: r.absents > 0 || r.halfDays > 0,
        requestedDeduction: PayrollService.extractSalary(r.absentDeduction),
        salary: r.salary,
        overtimeAmount: r.overtimeAmount,
        leaveDeduction: r.leaveDeduction,
        customDeduction: deductionVal,
        salaryType: r.salaryType,
        prorationFactor: r.prorationFactor,
      );
      r.absentDeduction = _editableAmount(absentDeduction);
      final netPayment = PayrollService.calculateNetFromTotals(
        salary: r.salary,
        overtimeAmount: r.overtimeAmount,
        absentDeduction: r.absentDeduction,
        leaveDeduction: r.leaveDeduction,
        customDeduction: deductionVal,
        salaryType: r.salaryType,
        prorationFactor: r.prorationFactor,
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

  double _maximumAbsentDeduction(AutoPayrollResult r) {
    if (r.absents <= 0 && r.halfDays <= 0) return 0.0;
    return PayrollService.maximumAbsentDeduction(
      salary: r.salary,
      overtimeAmount: r.overtimeAmount,
      leaveDeduction: r.leaveDeduction,
      customDeduction: r.customDeduction,
      salaryType: r.salaryType,
      prorationFactor: r.prorationFactor,
    );
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
        errorBuilder: (_, _, _) => fallback(),
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
          errorBuilder: (_, _, _) => fallback(),
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
        errorBuilder: (_, _, _) => fallback(),
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
          errorBuilder: (_, _, _) => fallback(),
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
