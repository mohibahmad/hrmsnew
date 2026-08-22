import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:csv/csv.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shimmer/shimmer.dart';
import 'package:hrms/riverpod_providers.dart';
import 'package:hrms/services/core/auth_service.dart';
import 'package:hrms/services/core/dummy_data.dart';
import 'package:hrms/services/core/error_reporter.dart';
import 'package:hrms/services/core/firestore_service.dart';
import 'package:hrms/services/payroll/invoice_service.dart';
import 'package:hrms/services/payroll/payroll_service.dart';
import 'package:hrms/services/payroll/payroll_cycle_service.dart';
import 'package:hrms/services/core/preferences_service.dart';
import 'package:hrms/services/payroll/salary_day_scheduler.dart';
import 'package:hrms/core/utils/utils.dart';
import 'package:hrms/widgets/components/amount_text.dart';
import 'package:hrms/widgets/components/clickable_gesture_detector.dart';
import 'package:hrms/widgets/components/notification_bell.dart';
import 'package:hrms/widgets/components/screen_table_shimmer.dart';
import 'package:hrms/screens/payroll/add_payroll_screen.dart';

String _generateCsvString(List<List<dynamic>> rows) {
  return '\ufeff${const CsvEncoder().convert(rows)}';
}

enum _PayrollReminderAction { remindLater, ignore, viewPayable }

class PayrollScreen extends ConsumerStatefulWidget {
  final VoidCallback onLogout;
  final bool isActive;
  final int activationToken;
  final VoidCallback onProfileTap;
  final VoidCallback? onAssignTimeOff;
  final VoidCallback? onNotificationTap;

  const PayrollScreen({
    super.key,
    this.isActive = true,
    this.activationToken = 0,
    required this.onLogout,
    required this.onProfileTap,
    this.onAssignTimeOff,
    this.onNotificationTap,
  });

  @override
  ConsumerState<PayrollScreen> createState() => PayrollScreenState();
}

class PayrollScreenState extends ConsumerState<PayrollScreen> {
  late final AuthService _authService;
  late final FirestoreService _firestore;

  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'All';

  List<Map<String, dynamic>> _payrollDocs = [];
  List<Map<String, dynamic>> _workersList = [];
  List<Map<String, dynamic>> _rawPayrollDocs = [];
  List<Map<String, dynamic>>? _liveAttendanceRecords;

  bool _isLoading = true;
  bool _isAddingPayroll = false;
  bool _isViewOnly = false;
  bool _isRunningPayroll = false;
  bool _initialized = false;
  bool _isLoadingAttendance = false;
  bool _attendanceFetchPending = false;
  bool _reminderCheckScheduled = false;
  bool _reminderCheckPending = false;
  bool _reminderCheckForcePending = false;
  bool _reminderDialogOpen = false;
  bool _snoozedThisVisit = false;

  /// Overdue/due alerts dismissed during this visit. They intentionally return
  /// on the next visit/day until the payroll is actually resolved (#5, #6).
  final Set<String> _sessionDismissedAlertKeys = {};

  String? _lastShownReminderKey;
  DateTime? _lastShownReminderDay;
  bool _workersLoaded = false;
  bool _payrollLoaded = false;

  String _companyCurrency = CurrencyUtils.defaultCode;
  DateTime _payrollMonth = PayrollService.currentPayrollMonth();
  int? _salaryPayDay;
  DateTime _payPeriodStart = PayrollService.payPeriodStart(DateTime.now());
  DateTime _payPeriodEnd = PayrollService.payPeriodEnd(DateTime.now());
  bool _isUserSelectedCycle = false;
  bool _payDayJustChanged = false;
  List<PayrollPeriod> _ignoredPeriods = [];

  Map<String, dynamic>? _workerForPayroll;

  Timer? _attendanceDebounce;

  bool get _isGuest => _authService.currentUser?.isAnonymous ?? false;

  bool get isPayrollReminderDataReady => _workersLoaded && _payrollLoaded;

  List<Map<String, dynamic>> get _currentPayablePayrollWorkers => _payrollDocs
      .where(
        (worker) =>
            !PayrollService.isPayrollRecordPaid(worker) &&
            PayrollService.workerEmployedDuringPeriod(worker, _payPeriodEnd) &&
            PayrollService.hasPayableSalary(
              worker,
              companyCurrency: _companyCurrency,
            ),
      )
      .toList(growable: false);

  List<Map<String, dynamic>> get _filteredEmployees {
    final filtered =
        _payrollDocs.where((doc) {
          final name = (doc['name'] ?? '').toString().toLowerCase();
          final pos = (doc['position'] ?? '').toString().toLowerCase();
          final query = _searchQuery.toLowerCase();
          if (!name.contains(query) && !pos.contains(query)) return false;
          return _matchesFilter(doc, _selectedFilter);
        }).toList()..sort((a, b) {
          final isPaidA = PayrollService.isPayrollRecordPaid(a);
          final isPaidB = PayrollService.isPayrollRecordPaid(b);

          if (isPaidA != isPaidB) {
            return isPaidA ? 1 : -1;
          }

          final nameA = (a['name'] ?? '').toString().trim().toLowerCase();
          final nameB = (b['name'] ?? '').toString().trim().toLowerCase();
          return nameA.compareTo(nameB);
        });
    return filtered;
  }

  @override
  void initState() {
    super.initState();
    _payrollDocs = [];
    _workersList = [];
    _rawPayrollDocs = [];
    _isLoading = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);
    _loadCompanySettings();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startPayrollListeners();
    });
  }

  @override
  void didUpdateWidget(covariant PayrollScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isActive &&
        (!oldWidget.isActive ||
            widget.activationToken != oldWidget.activationToken)) {
      _snoozedThisVisit = false;
      _lastShownReminderKey = null;
      _lastShownReminderDay = null;
      _schedulePayrollReminderCheck(force: false);
      if (!_isGuest && _payrollDocs.isNotEmpty) _scheduleAttendanceFetch();
    }

    if (!_initialized || !_isGuest) return;

    final latestWorkers = List<Map<String, dynamic>>.from(DummyData.workers);
    final currentIds = _workersList
        .map((w) => w['id']?.toString() ?? '')
        .toSet();
    final latestIds = latestWorkers
        .map((w) => w['id']?.toString() ?? '')
        .toSet();
    if (currentIds.length == latestIds.length &&
        currentIds.containsAll(latestIds)) {
      return;
    }

    _workersList = latestWorkers;
    _combinePayroll();
    _scheduleAttendanceFetch();
  }

  @override
  void dispose() {
    _attendanceDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _payableWorkersForPeriod(DateTime month) {
    if (month.year == _payrollMonth.year && month.month == _payrollMonth.month) {
      return _payableWorkersForCycle(
        PayrollPeriod(start: _payPeriodStart, end: _payPeriodEnd),
      );
    }
    return PayrollService.payableWorkersForPeriod(
      _workersList,
      _rawPayrollDocs,
      month: month,
      companyCurrency: _companyCurrency,
    );
  }

  /// Payable (unpaid, employed, salary > 0) workers for an exact cycle,
  /// always using the cycle's real boundaries — never calendar-month guesses.
  List<Map<String, dynamic>> _payableWorkersForCycle(PayrollPeriod cycle) {
    return PayrollService.payableWorkersForPeriod(
      _workersList,
      _rawPayrollDocs,
      month: DateTime(cycle.end.year, cycle.end.month, 1),
      allowUndatedRecords: _isGuest,
      companyCurrency: _companyCurrency,
      periodStart: cycle.start,
      periodEnd: cycle.end,
    );
  }

  /// Suppression key for a cycle's reminder/overdue popup.
  String _suppressionKeyFor(PayrollPeriod cycle) {
    return PayrollReminderWindow(
      payrollMonth: DateTime(cycle.end.year, cycle.end.month, 1),
      dueDate: cycle.end,
      dayOffset: 0,
    ).suppressionKey;
  }

  int? _payDayFromProfile(Map<String, dynamic>? profile) {
    final value = profile?['salaryPayDay'] ?? profile?['salary_pay_day'];
    final day = value is num ? value.toInt() : int.tryParse('$value');
    return day != null && day >= 1 && day <= 28 ? day : null;
  }

  PayrollPeriod _periodFromProfile(
    Map<String, dynamic>? profile,
    int payDay,
  ) {
    final startStr = profile?['payrollCycleStart']?.toString();
    final endStr = profile?['payrollCycleEnd']?.toString();
    PayrollPeriod? persisted;
    if (startStr != null &&
        endStr != null &&
        startStr.isNotEmpty &&
        endStr.isNotEmpty) {
      final start = AppDateUtils.dateFromValue(startStr);
      final end = AppDateUtils.dateFromValue(endStr);
      if (start != null && end != null && end.isAfter(start)) {
        persisted = PayrollPeriod(start: start, end: end);
      }
    }
    // Single source of truth — see [PayrollCycleService.resolveActiveCycle].
    return PayrollCycleService.resolveActiveCycle(
      salaryPayDay: payDay,
      persistedCycle: persisted,
      now: DateTime.now(),
    );
  }

  Future<void> _reconcilePayrollPeriod() async {
    if (!mounted ||
        !_workersLoaded ||
        !_payrollLoaded ||
        _isUserSelectedCycle) {
      return;
    }

    final newPeriod = _trueCurrentPayrollCycle();

    if (!PayrollService.payrollPeriodsEqual(
      newPeriod,
      PayrollPeriod(start: _payPeriodStart, end: _payPeriodEnd),
    )) {
      setState(() {
        _payPeriodStart = newPeriod.start;
        _payPeriodEnd = newPeriod.end;
        _payrollMonth = DateTime(newPeriod.end.year, newPeriod.end.month, 1);
        _combinePayroll();
      });
    }
  }

  Future<PayrollPeriod> _periodForProfile(
    Map<String, dynamic>? profile,
    int? salaryPayDay,
  ) async {
    if (salaryPayDay == null) {
      return PayrollCycleService.calendarMonthCycle(DateTime.now());
    }
    return _periodFromProfile(profile, salaryPayDay);
  }

  void _applyCompanySettings({
    required String companyCurrency,
    required int? salaryPayDay,
    required PayrollPeriod period,
  }) {
    setState(() {
      _companyCurrency = companyCurrency;
      _salaryPayDay = salaryPayDay;
      _payPeriodStart = period.start;
      _payPeriodEnd = period.end;
      _payrollMonth = DateTime(period.end.year, period.end.month, 1);
      _combinePayroll();
    });
    _scheduleAttendanceFetch();
    _reconcilePayrollPeriod();
  }

  Future<void> _loadCompanySettings() async {
    final profile = _isGuest
        ? await PreferencesService.getGuestProfileData()
        : await _firestore.getUserProfile();
    final ignored = await PreferencesService.getIgnoredPeriods();
    if (!mounted) return;
    setState(() {
      _ignoredPeriods = ignored;
    });

    var companyCurrency = CurrencyUtils.normalize(profile?['currency']);
    final salaryPayDay = _payDayFromProfile(profile);
    final rawProfileCurrency = profile?['currency']?.toString().trim();

    if (companyCurrency == CurrencyUtils.defaultCode &&
        (rawProfileCurrency == null || rawProfileCurrency.isEmpty)) {
      final cached = PreferencesService.cachedCompanyCurrency;
      if (cached != null && cached.isNotEmpty) {
        companyCurrency = CurrencyUtils.normalize(cached);
      }
    } else {
      PreferencesService.setCompanyCurrency(companyCurrency).catchError((_) {});
    }

    final period = await _periodForProfile(profile, salaryPayDay);
    if (!mounted) return;
    _applyCompanySettings(
      companyCurrency: companyCurrency,
      salaryPayDay: salaryPayDay,
      period: period,
    );
  }

  void _startPayrollListeners() {
    if (_isGuest) {
      _startGuestListeners();
    } else {
      _startFirestoreListeners();
    }
  }

  void _startGuestListeners() {
    setState(() {
      _workersLoaded = true;
      _payrollLoaded = true;
      _workersList = List<Map<String, dynamic>>.from(DummyData.workers);
      _rawPayrollDocs = List<Map<String, dynamic>>.from(DummyData.payroll);
      _combinePayroll();
      _scheduleAttendanceFetch();
    });
    _reconcilePayrollPeriod();
  }

  void _startFirestoreListeners() {
    ref.listenAsync(userProfileProvider, (profile) async {
      if (!mounted || profile == null) return;
      try {
        final currency = CurrencyUtils.normalize(profile['currency']);
        final salaryPayDay = _payDayFromProfile(profile);
    final period = await _periodForProfile(profile, salaryPayDay);

        // Don't overwrite a period the user manually selected from the
        // dropdown — only update when the cycle actually changed in Firestore
        // (e.g. after Pay All advanced it).
        if (_isUserSelectedCycle &&
            currency == _companyCurrency &&
            salaryPayDay == _salaryPayDay) {
          return;
        }

        // Pay day was just saved by _changeSalaryPayDay — the local state
        // already has the correct cycle.  Skip to avoid overwriting with a
        // stale persisted cycle from Firestore.
        if (_payDayJustChanged) {
          _payDayJustChanged = false;
          return;
        }

        if (currency == _companyCurrency &&
            salaryPayDay == _salaryPayDay &&
            PayrollService.payrollPeriodsEqual(
              period,
              PayrollPeriod(start: _payPeriodStart, end: _payPeriodEnd),
            )) {
          return;
        }

        if (!mounted) return;
        _applyCompanySettings(
          companyCurrency: currency,
          salaryPayDay: salaryPayDay,
          period: period,
        );
        // Reset the flag once Firestore delivers the real current cycle.
        _isUserSelectedCycle = false;
      } catch (error, stackTrace) {
        ErrorReporter.report(
          error,
          stackTrace,
          context: 'PayrollProfileStream',
        );
      }
    }, onError: _handlePayrollStreamError);

    ref.listenAsync(workersProvider, (records) {
      if (!mounted) return;
      setState(() {
        _workersLoaded = true;
        _workersList = records;
        _combinePayroll();
      });
      _scheduleAttendanceFetch();
      _reconcilePayrollPeriod();
    }, onError: _handlePayrollStreamError);

    ref.listenAsync(payrollProvider, (records) {
      if (!mounted) return;
      setState(() {
        _payrollLoaded = true;
        _rawPayrollDocs = records;
        _combinePayroll();
      });
      _scheduleAttendanceFetch();
      _reconcilePayrollPeriod();
    }, onError: _handlePayrollStreamError);

    ref.listenAsync(attendanceProvider, (records) {
      if (!mounted) return;
      _liveAttendanceRecords = records;
      _scheduleAttendanceFetch();
    }, onError: _handlePayrollStreamError);

    ref.listenAsync(holidaysProvider, (_) {
      if (mounted) _scheduleAttendanceFetch();
    }, onError: _handlePayrollStreamError);
  }

  void _handlePayrollStreamError(Object error, StackTrace stackTrace) {
    ErrorReporter.report(error, stackTrace, context: 'PayrollScreenStream');
    if (mounted) setState(() => _isLoading = false);
  }

  void _combinePayroll() {
    if (!_workersLoaded || !_payrollLoaded) {
      _isLoading = true;
      return;
    }

    _payrollDocs = PayrollService.combinePayroll(
      _workersList,
      _rawPayrollDocs,
      month: _payrollMonth,
      allowUndatedRecords: _isGuest,
      companyCurrency: _companyCurrency,
      periodStart: _payPeriodStart,
      periodEnd: _payPeriodEnd,
    );

    final zeroAmount = '${CurrencyUtils.symbolFor(_companyCurrency)} 0';
    for (final doc in _payrollDocs) {
      if ((doc['totalWorkDays'] ?? '').toString().isEmpty) {
        doc['status'] = 'Unpaid';
        doc['totalWorkDays'] = '0';
        doc['absents'] = '0';
        doc['leaves'] = '0';
        doc['paidLeaves'] = '0';
        doc['unpaidLeaves'] = '0';
        doc['overtimeAmount'] = '';
        doc['salary'] = doc['salary'] ?? zeroAmount;
        doc['netSalary'] = zeroAmount;
      }
    }

    _isLoading = !(_workersLoaded && _payrollLoaded);
    if (_selectedFilter == 'Pay' && _currentPayablePayrollWorkers.isEmpty) {
      _selectedFilter = 'All';
    }
    _schedulePayrollReminderCheck();
  }

  void _schedulePayrollReminderCheck({bool force = false}) {
    if (!widget.isActive) return;

    if (_reminderCheckScheduled) {
      _reminderCheckPending = true;
      _reminderCheckForcePending = _reminderCheckForcePending || force;
      return;
    }

    _reminderCheckScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (mounted) {
          await _maybeShowPayrollReminder(force: force);
        }
      } finally {
        _reminderCheckScheduled = false;

        if (_reminderCheckPending && mounted) {
          _reminderCheckPending = false;
          final pendingForce = _reminderCheckForcePending;
          _reminderCheckForcePending = false;
          _schedulePayrollReminderCheck(force: pendingForce);
        }
      }
    });
  }

  Future<void> triggerGlobalPayrollReminder() async {
    if (!mounted || _reminderCheckScheduled || _reminderDialogOpen) return;
    _reminderCheckScheduled = true;
    try {
      await _maybeShowPayrollReminder();
    } finally {
      _reminderCheckScheduled = false;
    }
  }

  void onSidebarPayrollClicked() {
    _snoozedThisVisit = false;
    _lastShownReminderKey = null;
    _lastShownReminderDay = null;
    _schedulePayrollReminderCheck(force: true);
  }

  void _scheduleAttendanceFetch() {
    _attendanceDebounce?.cancel();
    _attendanceDebounce = Timer(const Duration(milliseconds: 75), () {
      if (_isLoadingAttendance) {
        _attendanceFetchPending = true;
        return;
      }
      _fetchAttendanceForPayroll();
    });
  }

  Future<void> _fetchAttendanceForPayroll() async {
    if (_payrollDocs.isEmpty || _isLoadingAttendance) return;

    _isLoadingAttendance = true;
    final month = _payrollMonth;

    int workingDays;
    if (_isGuest) {
      workingDays = 22;
    } else {
      try {
        workingDays = await _firestore.getMonthlyWorkingDays(
          month: month,
          startDate: _payPeriodStart,
          endDate: _payPeriodEnd,
        );
      } catch (_) {
        workingDays = 22;
      }
    }

    if (!mounted) {
      _isLoadingAttendance = false;
      return;
    }

    List<Map<String, dynamic>>? timeOffRecords;
    Set<DateTime>? holidayDates;
    if (!_isGuest) {
      try {
        final shared = await Future.wait([
          _firestore.getTimeOffRecords(),
          _firestore.getHolidayDatesForRange(_payPeriodStart, _payPeriodEnd),
        ]);
        timeOffRecords = shared[0] as List<Map<String, dynamic>>;
        holidayDates = shared[1] as Set<DateTime>;
      } catch (_) {}
    }

    final futures = <Future<void>>[];
    for (final doc in _payrollDocs) {
      if (PayrollService.isPayrollRecordPaid(doc)) continue;

      final email = (doc['email'] ?? '').toString();
      final workerId = (doc['workerId'] ?? doc['id'] ?? '').toString();
      if (email.isEmpty && workerId.isEmpty) continue;

      futures.add(
        _fetchAndApplyAttendance(
          doc,
          email,
          workerId,
          month,
          workingDays,
          timeOffRecords,
          holidayDates,
        ),
      );
    }

    await Future.wait(futures);
    _isLoadingAttendance = false;

    if (mounted) setState(() {});
    if (_attendanceFetchPending || month != _payrollMonth) {
      _attendanceFetchPending = false;
      _scheduleAttendanceFetch();
    }
  }

  Future<void> _fetchAndApplyAttendance(
    Map<String, dynamic> doc,
    String email,
    String workerId,
    DateTime month,
    int workingDays,
    List<Map<String, dynamic>>? timeOffRecords,
    Set<DateTime>? holidayDates,
  ) async {
    if (PayrollService.isPayrollRecordPaid(doc)) return;

    try {
      Map<String, int> attendance;

      if (_isGuest) {
        final matched = DummyData.attendance.where((att) {
          final attDate = AppDateUtils.attendanceRecordDate(att);
          if (attDate == null ||
              attDate.year != month.year ||
              attDate.month != month.month) {
            return false;
          }
          final attWorkerId = (att['workerId'] ?? '').toString().trim();
          final attEmail = (att['email'] ?? '').toString().trim().toLowerCase();
          if (workerId.isNotEmpty && attWorkerId.isNotEmpty) {
            return workerId == attWorkerId;
          }
          return email.isNotEmpty && attEmail == email.toLowerCase();
        }).toList();

        attendance = {
          'absents': matched.where((a) => a['status'] == 'Absent').length,
          'paidLeaves': matched.where((a) => a['status'] == 'Leave').length,
          'unpaidLeaves': 0,
          'leaves': matched.where((a) => a['status'] == 'Leave').length,
        };
      } else {
        attendance = await _firestore.getWorkerMonthlyAttendance(
          email,
          workerId: workerId,
          month: month,
          startDate: _payPeriodStart,
          endDate: _payPeriodEnd,
          preFetchedRecords: _liveAttendanceRecords,
          preFetchedTimeOffRecords: timeOffRecords,
          preFetchedHolidayDates: holidayDates,
        );
      }

      doc['absents'] = (attendance['absents'] ?? 0).toString();
      doc['paidLeaves'] = (attendance['paidLeaves'] ?? 0).toString();
      doc['unpaidLeaves'] = (attendance['unpaidLeaves'] ?? 0).toString();
      doc['leaves'] = (attendance['leaves'] ?? 0).toString();
      doc['totalWorkDays'] = workingDays.toString();
    } catch (error, stackTrace) {
      ErrorReporter.report(
        error,
        stackTrace,
        context: 'PayrollAttendanceFetch($email)',
      );
    }
  }

  bool _matchesFilter(Map<String, dynamic> doc, String filter) {
    return switch (filter) {
      'All' => true,
      'Pay' =>
        doc['isPaid'] != true &&
            PayrollService.workerEmployedDuringPeriod(doc, _payPeriodEnd),
      'Paid' => doc['isPaid'] == true,
      'Today' => PayrollService.wasPaidOn(doc, DateTime.now()),
      _ => (doc['position'] ?? '').toString().toLowerCase().contains(
        filter.toLowerCase(),
      ),
    };
  }

  bool _requirePayableSalary(Map<String, dynamic> worker) {
    if (PayrollService.hasPayableSalary(
      worker,
      companyCurrency: _companyCurrency,
    )) {
      return true;
    }
    FlashySnackBar.show(
      context,
      message: 'please_enter_salary'.tr(),
      isError: true,
    );
    return false;
  }

  String _payPeriodLabelFor(DateTime month) {
    return PayrollService.formatPayPeriodRange(
      _payPeriodStart,
      _payPeriodEnd,
      locale: context.locale.toString(),
    );
  }

  String _payDayButtonLabel() {
    final day = _salaryPayDay;
    if (day == null) return 'set_salary_day'.tr();

    var formattedDay = '$day';
    if (context.locale.languageCode.toLowerCase() == 'en') {
      final remainder = day % 100;
      final suffix = remainder >= 11 && remainder <= 13
          ? 'th'
          : switch (day % 10) {
              1 => 'st',
              2 => 'nd',
              3 => 'rd',
              _ => 'th',
            };
      formattedDay = '$day$suffix';
    }
    return 'salary_day_value'.tr(namedArgs: {'day': formattedDay});
  }

  Future<void> _handlePayAll() => _handlePayAllForMonth(_payrollMonth);

  Future<void> _handlePayAllForMonth(DateTime payrollMonth) async {
    if (_isRunningPayroll || _payableWorkersForPeriod(payrollMonth).isEmpty) {
      return;
    }

    setState(() => _isRunningPayroll = true);

    FlashySnackBar.dismiss();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      final summary = await PayrollRunner().payAll(
        context,
        payrollMonth: payrollMonth,
        payPeriodStart: _payPeriodStart,
        payPeriodEnd: _payPeriodEnd,
        onBeforeReviewDialog: () {
          if (mounted) {
            setState(() => _isRunningPayroll = false);
          }
        },
      );
      if (summary != null && mounted) {
        FlashySnackBar.show(
          context,
          message: 'payroll_run_complete'.tr(
            namedArgs: {'count': '${summary.successCount}'},
          ),
        );

        await _refreshPayrollAfterCommit();
      } else if (mounted) {
        FlashySnackBar.dismiss();
      }
    } catch (error) {
      if (mounted) {
        final msg = error is StateError && error.message.isNotEmpty
            ? error.message
            : error.toString().isNotEmpty
            ? error.toString()
            : 'failed_to_save_record'.tr();
        FlashySnackBar.show(context, message: msg, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRunningPayroll = false;

          if (_isGuest) {
            _rawPayrollDocs = List<Map<String, dynamic>>.from(
              DummyData.payroll,
            );
            _combinePayroll();
          }
        });
      }
    }
  }

  Future<void> _refreshPayrollAfterCommit() async {
    if (_isGuest || !mounted) return;
    try {
      final snap = await _firestore.getPayrollOnce();
      if (!mounted) return;
      setState(() {
        _rawPayrollDocs = snap.docs
            .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
            .toList();
        _combinePayroll();
      });
      final didAdvance = await _advanceCycleIfAllPaid();
      if (!didAdvance) {
        await _reconcilePayrollPeriod();
      }
    } catch (error, stackTrace) {
      ErrorReporter.report(
        error,
        stackTrace,
        context: 'refreshPayrollAfterCommit',
      );
    }
  }

  Future<bool> _advanceCycleIfAllPaid() async {
    if (_isGuest || !mounted) return false;

    if (PayrollService.payableWorkersForPeriod(
      _workersList,
      _rawPayrollDocs,
      month: _payrollMonth,
      companyCurrency: _companyCurrency,
      periodStart: _payPeriodStart,
      periodEnd: _payPeriodEnd,
    ).isNotEmpty) {
      return false;
    }

    final current = PayrollPeriod(start: _payPeriodStart, end: _payPeriodEnd);

    if (!_periodHasAnyPaidRecord(current)) return false;

    // The next cycle starts from the actual payment date (today), not the
    // original pay day anchor.  E.g. pay day 23, cycle Jul 23 – Aug 23,
    // payment on Aug 21 -> next cycle Aug 21 – Sep 21 (pay day becomes 21).
    final paymentDate = DateTime.now();
    final newPayDay = paymentDate.day;
    final next = PayrollCycleService.nextCycleFromPaymentDate(
      paymentDate,
      _salaryPayDay,
    );

    if (PayrollService.payrollPeriodsEqual(next, current)) return false;

    try {
      await _firestore.updateUserProfile({
        'payrollCycleStart': next.start.toIso8601String(),
        'payrollCycleEnd': next.end.toIso8601String(),
        'salaryPayDay': newPayDay,
      });
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'advancePayrollCycle');
    }
    if (!mounted) return false;

    // Clear the pay-day-change guard so the Firestore listener can pick up
    // the new cycle we just saved (advanceCycle is not a user-initiated
    // pay-day change).
    _payDayJustChanged = false;

    setState(() {
      _payPeriodStart = next.start;
      _payPeriodEnd = next.end;
      _payrollMonth = DateTime(next.end.year, next.end.month, 1);
      _salaryPayDay = newPayDay;
      _selectedFilter = 'All';
      _combinePayroll();
    });
    _scheduleAttendanceFetch();
    return true;
  }

  bool _periodHasAnyPaidRecord(PayrollPeriod period) {
    for (final record in _rawPayrollDocs) {
      if (!PayrollService.isPayrollRecordPaid(record)) continue;
      final s = AppDateUtils.dateFromValue(record['payPeriodStart']);
      final e = AppDateUtils.dateFromValue(record['payPeriodEnd']);
      if (s != null &&
          e != null &&
          PayrollService.payrollPeriodsEqual(
            PayrollPeriod(start: s, end: e),
            period,
          )) {
        return true;
      }
    }
    return false;
  }

  PayrollPeriod _nextCycleAfter(PayrollPeriod current, int? payDay) {
    // Single source of truth — see [PayrollCycleService.nextCycleAfter].
    return PayrollCycleService.nextCycleAfter(current, payDay);
  }

  Widget _desktopDialogButton({
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary ? const Color(0xFF004FDE) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: primary
                  ? const Color(0xFFFFFFFF)
                  : const Color(0xFF0F172A),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _desktopDialogShell({
    required BuildContext dialogContext,
    required String title,
    required Widget content,
    required List<Widget> actions,
    double width = 540,
  }) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: Container(
          width: width,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 48,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                color: const Color(0xFF004FDE),
                child: Row(
                  children: [
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          final route = ModalRoute.of(dialogContext);
                          if (route != null && route.isCurrent) {
                            Navigator.of(dialogContext).pop();
                          }
                        },
                        child: const SizedBox(
                          width: 32,
                          height: 32,
                          child: Icon(
                            Icons.close_rounded,
                            color: Color(0xFFFFFFFF),
                            size: 21,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFFFFFF),
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 32),
                  ],
                ),
              ),
              Padding(padding: const EdgeInsets.all(24), child: content),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFFE5E7EB), width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (int i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      actions[i],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlurDialog({
    required BuildContext dialogContext,
    required Widget Function(CurvedAnimation) builder,
    required Animation<double> animation,
  }) {
    final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 12 * animation.value,
              sigmaY: 12 * animation.value,
            ),
            child: FadeTransition(
              opacity: animation,
              child: Container(
                color: const Color(0xFF0247C4).withValues(alpha: 0.18),
              ),
            ),
          ),
        ),
        FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: curve, child: builder(curve)),
        ),
      ],
    );
  }

  Future<void> _maybeShowPayrollReminder({bool force = false}) async {
    if (!widget.isActive ||
        _isLoading ||
        !_workersLoaded ||
        !_payrollLoaded ||
        _reminderDialogOpen) {
      return;
    }

    if (!force && _reminderCheckForcePending) {
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // ---- Alert target selection (all dates via PayrollCycleService) --------
    // #4: pre-due reminders start exactly 3 days before the due date and only
    //     while workers are still waiting to be paid.
    // #5: due/overdue alerts persist indefinitely — there is no 7-day expiry.
    // #6: outstanding previous cycles keep alerting even after the active
    //     cycle advanced.
    PayrollPeriod alertCycle;
    var alertIsPreviousCycle = false;

    final displayed = PayrollPeriod(start: _payPeriodStart, end: _payPeriodEnd);
    final displayedOffset =
        today.difference(PayrollCycleService.dueDateOf(displayed)).inDays;
    final displayedHasPayable =
        displayedOffset >= -PayrollCycleService.reminderLeadDays &&
        _payableWorkersForCycle(displayed).isNotEmpty;

    if (displayedHasPayable) {
      alertCycle = displayed;
    } else {
      PayrollPeriod? previous;
      for (final cycle in PayrollCycleService.getOutstandingPreviousCycles(
        workersList: _workersList,
        rawPayrollDocs: _rawPayrollDocs,
        activeCycle: _trueCurrentPayrollCycle(),
        companyCurrency: _companyCurrency,
        allowUndatedRecords: _isGuest,
        extraCandidates: _ignoredPeriods,
      )) {
        if (_sessionDismissedAlertKeys.contains(_suppressionKeyFor(cycle))) {
          continue;
        }
        if (_payableWorkersForCycle(cycle).isEmpty) continue;
        previous = cycle;
        break;
      }
      if (previous == null) {
        return;
      }
      alertCycle = previous;
      alertIsPreviousCycle = true;
    }

    final offset =
        today.difference(PayrollCycleService.dueDateOf(alertCycle)).inDays;

    final window = PayrollReminderWindow(
      payrollMonth: DateTime(alertCycle.end.year, alertCycle.end.month, 1),
      dueDate: alertCycle.end,
      dayOffset: offset,
    );

    if (!force) {
      if (_sessionDismissedAlertKeys.contains(window.suppressionKey)) {
        return;
      }
      // "Remind me later" only suppresses the pre-due reminder for the rest of
      // this visit. Due-day and overdue alerts keep coming back every day
      // until the payroll is actually settled (#5).
      if (_snoozedThisVisit && offset < 0) {
        return;
      }
      if (offset < 0) {
        final ignored = await PreferencesService.isPayrollReminderIgnored(
          window.suppressionKey,
        );
        if (ignored) return;
        final snoozed = await PreferencesService.isPayrollReminderSnoozed(
          window.suppressionKey,
          now: now,
        );
        if (snoozed) {
          await PreferencesService.clearPayrollSnooze(window.suppressionKey);
        }
      }
    }

    final payableWorkers = _payableWorkersForCycle(alertCycle);
    if (payableWorkers.isEmpty) {
      return;
    }
    if (!mounted || !widget.isActive) {
      return;
    }

    final excludedLateJoiners = PayrollService.excludedLateJoinersForPeriod(
      _workersList,
      _rawPayrollDocs,
      month: window.payrollMonth,
      allowUndatedRecords: _isGuest,
      companyCurrency: _companyCurrency,
      periodStart: alertCycle.start,
      periodEnd: alertCycle.end,
    );

    if (!force &&
        _lastShownReminderKey == window.suppressionKey &&
        _lastShownReminderDay == today) {
      return;
    }
    _lastShownReminderKey = window.suppressionKey;
    _lastShownReminderDay = today;

    _reminderDialogOpen = true;

    final status = offset < -1
        ? 'payroll_due_in_days'.tr(namedArgs: {'days': '${offset.abs()}'})
        : offset == -1
        ? 'payroll_due_tomorrow'.tr()
        : offset == 0
        ? 'payroll_due_today'.tr()
        : offset == 1
        ? 'payroll_overdue_one_day'.tr()
        : 'payroll_overdue_days'.tr(namedArgs: {'days': '$offset'});

    final dueDate = AppDateUtils.fromValueLocalized(
      window.dueDate,
      locale: context.locale.toString(),
    );

    final action = await showGeneralDialog<_PayrollReminderAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'PayrollReminderDialog',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, _, _) => const SizedBox(),
      transitionBuilder: (dialogContext, animation, _, _) {
        void safePop<T>([T? result]) {
          final route = ModalRoute.of(dialogContext);
          if (route != null && route.isCurrent) {
            Navigator.of(dialogContext).pop(result);
          }
        }

        return _buildBlurDialog(
          dialogContext: dialogContext,
          animation: animation,
          builder: (_) => _desktopDialogShell(
            dialogContext: dialogContext,
            title: offset > 0
                ? 'overdue_payroll'.tr()
                : 'pay_due_reminder'.tr(),
            width: 560,
            content: _buildReminderContent(
              offset,
              status,
              dueDate,
              payableWorkers,
            ),
            actions: [
              _desktopDialogButton(
                label: 'remind_me_later'.tr(),
                onTap: () => safePop(_PayrollReminderAction.remindLater),
              ),
              if (offset > 0 && !alertIsPreviousCycle)
                _desktopDialogButton(
                  label: 'ignore'.tr(),
                  onTap: () => safePop(_PayrollReminderAction.ignore),
                ),
              _desktopDialogButton(
                label: 'pay'.tr(),
                primary: true,
                onTap: () => safePop(_PayrollReminderAction.viewPayable),
              ),
            ],
          ),
        );
      },
    );

    _reminderDialogOpen = false;

    switch (action) {
      case _PayrollReminderAction.remindLater:
        if (mounted) {
          setState(() {
            _snoozedThisVisit = true;
            _selectedFilter = 'All';
          });
        }
        // Quiet for the rest of this visit; returns on the next visit/day
        // while workers remain unpaid (#4).
        _sessionDismissedAlertKeys.add(window.suppressionKey);
      case _PayrollReminderAction.ignore:
        // Only offered for the ACTIVE cycle's overdue popup. Skipping starts
        // the next anchored cycle. The skipped cycle keeps its own dates and
        // overdue status — its unpaid workers stay accessible/payable from
        // history and are never moved into the new cycle or deleted (#6).
        final nextPeriod = _nextCycleAfter(
          PayrollPeriod(start: _payPeriodStart, end: _payPeriodEnd),
          _salaryPayDay,
        );
        final confirmed = await DeleteDialog.show(
          context: context,
          title: 'confirm_ignore_payroll'.tr(),
          content: 'confirm_ignore_payroll_message'.tr(
            namedArgs: {
              'range': PayrollService.formatPayPeriodRange(
                nextPeriod.start,
                nextPeriod.end,
                locale: context.locale.toString(),
              ),
            },
          ),
          confirmButtonText: 'yes',
        );
        if (!confirmed || !mounted) break;

        await PreferencesService.saveIgnoredPeriod(
          window.suppressionKey,
          _payPeriodStart,
          _payPeriodEnd,
        );
        _sessionDismissedAlertKeys.add(window.suppressionKey);
        if (!_isGuest) {
          await _firestore.updateUserProfile({
            'payrollCycleStart': nextPeriod.start.toIso8601String(),
            'payrollCycleEnd': nextPeriod.end.toIso8601String(),
          });
        }
        if (!mounted) break;
        setState(() {
          _ignoredPeriods.add(
            PayrollPeriod(start: _payPeriodStart, end: _payPeriodEnd),
          );
          _payPeriodStart = nextPeriod.start;
          _payPeriodEnd = nextPeriod.end;
          _payrollMonth = DateTime(
            nextPeriod.end.year,
            nextPeriod.end.month,
            1,
          );
          _selectedFilter = 'All';
          _combinePayroll();
        });
        _scheduleAttendanceFetch();
      case _PayrollReminderAction.viewPayable:
        if (mounted) {
          setState(() {
            // Show the exact alerted cycle so HR can act on overdue history.
            _payPeriodStart = alertCycle.start;
            _payPeriodEnd = alertCycle.end;
            _payrollMonth = DateTime(
              alertCycle.end.year,
              alertCycle.end.month,
              1,
            );
            _isUserSelectedCycle = alertIsPreviousCycle;
            _selectedFilter = 'Pay';
            _combinePayroll();
          });
          _scheduleAttendanceFetch();

          // If 4+ payable workers, open Pay All review dialog directly.
          // Otherwise just show the filtered payable list.
          if (payableWorkers.length >= 4) {
            _handlePayAll();
          }
        }
      case null:
        if (mounted) setState(() => _selectedFilter = 'All');
        // Dismissing a due/overdue alert keeps it quiet for this visit only —
        // it comes back on the next visit/day until resolved (#5). There is
        // no expiry of any kind.
        if (offset >= 0) _sessionDismissedAlertKeys.add(window.suppressionKey);
    }

    if (mounted && excludedLateJoiners.isNotEmpty) {
      final names = excludedLateJoiners
          .map((w) => (w['name'] ?? '').toString().trim())
          .where((n) => n.isNotEmpty)
          .join(', ');
      if (names.isNotEmpty) {
        FlashySnackBar.show(
          context,
          message: 'late_joiners_excluded'.tr(namedArgs: {'names': names}),
          isError: true,
        );
      }
    }
  }

  Widget _buildReminderContent(
    int offset,
    String status,
    String dueDate,
    List<Map<String, dynamic>> payableWorkers,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: offset > 0
                ? const Color(0xFFFEF2F2)
                : const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: offset > 0
                  ? const Color(0xFFFECACA)
                  : const Color(0xFFBFDBFE),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.notifications_active_rounded,
                color: offset > 0
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF004FDE),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  status,
                  style: TextStyle(
                    color: offset > 0
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF004FDE),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'payroll_due_message'.tr(
            namedArgs: {'count': '${payableWorkers.length}', 'date': dueDate},
          ),
          style: const TextStyle(
            color: Color(0xFF334155),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: payableWorkers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final worker = payableWorkers[index];
              final name = (worker['name'] ?? 'Worker').toString().trim();
              final position = (worker['position'] ?? '').toString().trim();
              final imageUrl =
                  (worker['profileImage'] ??
                          worker['profilePic'] ??
                          worker['imageUrl'])
                      ?.toString();

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    WorkerAvatar(
                      imageUrl: imageUrl,
                      name: name.isEmpty ? 'Worker' : name,
                      size: 36,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isEmpty ? 'Worker' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (position.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              LocalizationHelper.localizePosition(position),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'payable'.tr(),
                        style: const TextStyle(
                          color: Color(0xFF004FDE),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showSetPayDayDialog() async {
    if (_isGuest) {
      showGuestRestrictionDialog(context);
      return;
    }

    var selectedDay = (_salaryPayDay ?? DateTime.now().day)
        .clamp(1, 28)
        .toInt();
    final day = await showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'SetPayDayDialog',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, _, _) => const SizedBox(),
      transitionBuilder: (dialogContext, animation, _, _) {
        void safePop<T>([T? result]) {
          final route = ModalRoute.of(dialogContext);
          if (route != null && route.isCurrent) {
            Navigator.of(dialogContext).pop(result);
          }
        }

        return _buildBlurDialog(
          dialogContext: dialogContext,
          animation: animation,
          builder: (_) => StatefulBuilder(
            builder: (_, setDialogState) => _desktopDialogShell(
              dialogContext: dialogContext,
              title: 'set_salary_day'.tr(),
              width: 540,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'salary_day_help'.tr(),
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 18),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1.2,
                        ),
                    itemCount: 28,
                    itemBuilder: (context, index) {
                      final value = index + 1;
                      final selected = value == selectedDay;
                      return MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () =>
                              setDialogState(() => selectedDay = value),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF004FDE)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFF004FDE)
                                    : const Color(0xFFE5E7EB),
                              ),
                            ),
                            child: Text(
                              '$value',
                              style: TextStyle(
                                color: selected
                                    ? const Color(0xFFFFFFFF)
                                    : const Color(0xFF0F172A),
                                fontSize: 14,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              actions: [
                _desktopDialogButton(
                  label: 'cancel'.tr(),
                  onTap: () => safePop(),
                ),

                if (_salaryPayDay != null)
                  _desktopDialogButton(
                    label: 'Clear Pay Day',
                    onTap: () => safePop(0),
                  ),
                _desktopDialogButton(
                  label: 'save'.tr(),
                  primary: true,
                  onTap: () => safePop(selectedDay),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (day == null || !mounted) return;
    if (day == 0) {
      try {
        // Clear Pay Day but preserve existing cycle dates so payroll records
        // are not disturbed.  resolveActiveCycle with salaryPayDay == null
        // returns calendar-month mode automatically.
        await _firestore.updateUserProfile({
          'salaryPayDay': null,
        });

        if (!mounted) return;

        // Clear Pay Day immediately restores calendar-month mode (#9):
        // cycleStart = 1st of the current month, due = its real last day.
        final now = DateTime.now();
        final calendarCycle = PayrollCycleService.calendarMonthCycle(now);

        setState(() {
          _salaryPayDay = null;
          _payPeriodStart = calendarCycle.start;
          _payPeriodEnd = calendarCycle.end;
          _payrollMonth = DateTime(now.year, now.month, 1);
          _selectedFilter = 'All';
          _combinePayroll();
        });

        FlashySnackBar.show(context, message: 'Pay Day cleared successfully.');
      } catch (error, stackTrace) {
        ErrorReporter.report(error, stackTrace, context: 'ClearSalaryPayDay');

        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'failed_to_save_record'.tr(),
            isError: true,
          );
        }
      }

      return;
    }

    if (day == _salaryPayDay) return;

    try {
      final payDay = day.clamp(1, 28);

      // Re-anchor the current cycle to the new pay day instead of calling
      // resolveActiveCycle from scratch.  This keeps the cycle in the same
      // month range the user is already working in.
      //   Aug 22 – Sep 22, change to 24 → Aug 24 – Sep 24
      //   Aug 22 – Sep 22, change to 10 → Aug 10 – Sep 10
      var newStart = PayrollCycleService.anchorInMonth(
        _payPeriodStart,
        payDay,
      );
      var newEnd = PayrollCycleService.anchorInMonth(
        DateTime(_payPeriodEnd.year, _payPeriodEnd.month, 1),
        payDay,
      );
      var period = PayrollPeriod(start: newStart, end: newEnd);

      // If the re-anchored cycle is in the past (e.g. viewing a paid historical
      // cycle like Jul 9 – Aug 9, change to 5 → Jul 5 – Aug 5, but today is
      // Aug 22), advance forward until today falls inside the cycle.
      final today = DateTime.now();
      while (today.isAfter(period.end)) {
        period = PayrollCycleService.nextCycleAfter(period, payDay);
      }

      await _firestore.updateUserProfile({
        'salaryPayDay': day,
        'payrollCycleStart': period.start.toIso8601String(),
        'payrollCycleEnd': period.end.toIso8601String(),
      });

      if (!mounted) return;
      _isUserSelectedCycle = false;
      _payDayJustChanged = true;
      setState(() {
        _salaryPayDay = day;
        _payPeriodStart = period.start;
        _payPeriodEnd = period.end;
        _payrollMonth = DateTime(period.end.year, period.end.month, 1);
        _combinePayroll();
      });
      _schedulePayrollReminderCheck();

      final rangeLabel = PayrollService.formatPayPeriodRange(
        period.start,
        period.end,
        locale: context.locale.toString(),
      );
      FlashySnackBar.show(
        context,
        message: 'Pay Day updated. Current pay period: $rangeLabel',
      );
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'SaveSalaryPayDay');
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'failed_to_save_record'.tr(),
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isAddingPayroll && _workerForPayroll != null) {
      return AddPayrollScreen(
        workerData: _workerForPayroll!,
        payrollMonth: _payrollMonth,
        payPeriodStart: _payPeriodStart,
        payPeriodEnd: _payPeriodEnd,
        salaryPayDay: _salaryPayDay,
        readOnly: _isViewOnly,
        onNotificationTap: widget.onNotificationTap,
        onProfileTap: widget.onProfileTap,
        onBack: () async {
          setState(() {
            _isAddingPayroll = false;
            _workerForPayroll = null;
            _isViewOnly = false;
          });
          if (!_isGuest) {
            try {
              final snap = await _firestore.getPayrollOnce();
              if (!mounted) return;
              setState(() {
                _rawPayrollDocs = snap.docs
                    .map(
                      (d) => {...d.data() as Map<String, dynamic>, 'id': d.id},
                    )
                    .toList();
                _combinePayroll();
              });
              _scheduleAttendanceFetch();
              _isUserSelectedCycle = false;
              final didAdvance = await _advanceCycleIfAllPaid();
              if (!didAdvance) {
                _reconcilePayrollPeriod();
              }
            } catch (_) {}
          }
        },
      );
    }

    final filteredEmployees = _isLoading
        ? const <Map<String, dynamic>>[]
        : _filteredEmployees;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPayPeriodBar(),
                  const SizedBox(height: 16),
                  _buildSearchBar(),
                  const SizedBox(height: 10),
                  _buildFilterTabs(),
                  const SizedBox(height: 20),
                  _buildListHeader(),
                  const SizedBox(height: 20),
                  _isLoading
                      ? _buildShimmerTable()
                      : filteredEmployees.isEmpty
                      ? _buildEmptyState()
                      : _buildTable(filteredEmployees),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'workforce'.tr(),
                style: const TextStyle(
                  color: Color(0xFF000000),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
            ],
          ),
          const Spacer(),
          NotificationBell(onTap: widget.onNotificationTap),
          const SizedBox(width: 20),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onProfileTap,
              child: const UserAvatar(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayPeriodBar() {
    final periodText = _payPeriodLabelFor(_payrollMonth);
    final isCurrent = _isViewingCurrentCycle;
    final hasCurrentPayable = _currentPayablePayrollWorkers.isNotEmpty;
    // Pay All shows after the cycle starts; clicking is gated by the due-date
    // check in [_handlePayAllForMonth] until the Pay Day arrives.
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final periodStart = DateTime(
      _payPeriodStart.year,
      _payPeriodStart.month,
      _payPeriodStart.day,
    );
    final periodEnd = DateTime(
      _payPeriodEnd.year,
      _payPeriodEnd.month,
      _payPeriodEnd.day,
    );
    final hasStarted = !normalizedToday.isBefore(periodStart);
    final payAllEnabled =
        !_isRunningPayroll && hasCurrentPayable && isCurrent && hasStarted;

    return Row(
      children: [
        Builder(
          builder: (anchorContext) => MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _showPaidWorkersDropdown(anchorContext),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    periodText,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF000000),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: Color(0xFF000000),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Spacer(),
        if (hasCurrentPayable && isCurrent && hasStarted)
          MouseRegion(
            cursor: payAllEnabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: GestureDetector(
              onTap: payAllEnabled
                  ? () {
                      if (_isGuest) {
                        showGuestRestrictionDialog(context);
                        return;
                      }
                      _handlePayAll();
                    }
                  : null,
              child: Container(
                height: 43,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF27AE60),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _isRunningPayroll
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Color(0xFFFFFFFF),
                            ),
                          )
                        : SvgPicture.asset(
                            'assets/payroll_icon.svg',
                            width: 18,
                            height: 18,
                            colorFilter: const ColorFilter.mode(
                              Color(0xFFFFFFFF),
                              BlendMode.srcIn,
                            ),
                          ),
                    const SizedBox(width: 8),
                    Text(
                      'pay_all'.tr(),
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(width: 12),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _showSetPayDayDialog,
            child: Container(
              height: 43,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0247C4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    size: 18,
                    color: const Color(0xFFFFFFFF),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _payDayButtonLabel(),
                    style: TextStyle(
                      color: const Color(0xFFFFFFFF),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _handleExportPayroll,
            child: Container(
              height: 43,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    'assets/share1.svg',
                    width: 18,
                    height: 18,
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF0247C4),
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Export',
                    style: TextStyle(
                      color: Color(0xFF0247C4),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Map<String, dynamic>? _paidWorkerRecord(Map<String, dynamic> record) {
    if (!PayrollService.isPayrollRecordPaid(record)) return null;
    Map<String, dynamic> worker = const {};
    final recordId = (record['workerId'] ?? '').toString().trim();
    final recordEmail = (record['email'] ?? '').toString().trim().toLowerCase();
    if (recordId.isNotEmpty || recordEmail.isNotEmpty) {
      for (final w in _workersList) {
        final wId = (w['workerId'] ?? w['id'] ?? '').toString().trim();
        final wEmail = (w['email'] ?? '').toString().trim().toLowerCase();
        if ((wId.isNotEmpty && recordId.isNotEmpty && wId == recordId) ||
            (wEmail.isNotEmpty &&
                recordEmail.isNotEmpty &&
                wEmail == recordEmail)) {
          worker = w;
          break;
        }
      }
    }
    return {...record, if (worker.isNotEmpty) ...worker};
  }

  List<Map<String, dynamic>> _allPaidWorkers() {
    return _rawPayrollDocs
        .map(_paidWorkerRecord)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  String _csvAmount(dynamic value) {
    final amount = PayrollService.extractSalary((value ?? 0).toString());
    return amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }

  String _recordPeriodText(Map<String, dynamic> record) {
    final start = AppDateUtils.dateFromValue(record['payPeriodStart']);
    final end = AppDateUtils.dateFromValue(record['payPeriodEnd']);
    if (start != null && end != null) {
      return PayrollService.formatPayPeriodRange(start, end);
    }

    return PayrollService.formatPayPeriodRange(_payPeriodStart, _payPeriodEnd);
  }

  Future<void> _handleExportPayroll() async {
    if (_isGuest) {
      showGuestRestrictionDialog(context);
      return;
    }

    final allRecords = _payrollDocs;
    if (allRecords.isEmpty) {
      FlashySnackBar.show(context, message: 'No payroll data to export yet.');
      return;
    }

    try {
      final rows = <List<dynamic>>[
        [
          'Name',
          'Position',
          'Pay Period',
          'Status',
          'Paid On',
          'Salary',
          'Total Work Days',
          'Absents',
          'Leaves',
          'Overtime',
          'Absent Deduction',
          'Leave Deduction',
          'Other Deduction',
          'Total Deductions',
          'Net Salary',
          'Currency',
        ],
      ];

      for (final worker in allRecords) {
        final name = (worker['name'] ?? '').toString().trim();
        final position = (worker['position'] ?? '').toString().trim();
        final totalWorkDays = (worker['totalWorkDays'] ?? 0).toString();
        final absents = (worker['absents'] ?? 0).toString();
        final leaves = (worker['leaves'] ?? 0).toString();
        final overtime = _csvAmount(worker['overtimeAmount']);
        final absentDeduction = _csvAmount(worker['absentDeduction']);
        final leaveDeduction = _csvAmount(worker['leaveDeduction']);
        final customDeduction = _csvAmount(worker['customDeduction']);
        final totalDeductions = _csvAmount(
          PayrollService.sumDeductions(worker),
        );
        final salary = _csvAmount(worker['salary']);
        final netSalary = _csvAmount(
          worker['netSalary'] ??
              worker['netSalaryFormatted'] ??
              worker['salaryAfterDeduction'],
        );
        final isPaid = PayrollService.isPayrollRecordPaid(worker);
        final paidDate = PayrollService.payrollPaymentDate(worker);
        final paidOn = paidDate == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(paidDate);
        final currencyCode =
            (_companyCurrency.isNotEmpty
                    ? _companyCurrency
                    : (worker['currency'] ?? '').toString())
                .trim();

        rows.add([
          name,
          position,
          _recordPeriodText(worker),
          isPaid ? 'Paid' : 'Unpaid',
          paidOn,
          salary,
          totalWorkDays,
          absents,
          leaves,
          overtime,
          absentDeduction,
          leaveDeduction,
          customDeduction,
          totalDeductions,
          netSalary,
          currencyCode,
        ]);
      }

      final csvString = await compute(_generateCsvString, rows);
      final csvBytes = Uint8List.fromList(utf8.encode(csvString));
      final monthStr = DateFormat('MMM_yyyy').format(_payPeriodEnd);
      final fileName = 'Payroll_Export_$monthStr.csv';

      final outputFile = await FilePicker.saveFile(
        dialogTitle: 'Export Payroll Cycle Data',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: csvBytes,
      );

      if (outputFile == null) return;
      await File(outputFile).writeAsBytes(csvBytes);

      if (mounted) {
        FlashySnackBar.show(context, message: 'CSV exported: $fileName');
        unawaited(FileOpener.open(outputFile));
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'Failed to export CSV: $e',
          isError: true,
        );
      }
    }
  }

  List<({
    PayrollPeriod period,
    String label,
    int paidCount,
    bool isCurrent,
    DateTime? latestPaidAt,
  })>
  _payPeriodOptions() {
    final map = <String, ({
      PayrollPeriod period,
      int paidCount,
      DateTime? latestPaidAt,
    })>{};

    for (final worker in _allPaidWorkers()) {
      final start = AppDateUtils.dateFromValue(worker['payPeriodStart']);
      final end = AppDateUtils.dateFromValue(worker['payPeriodEnd']);
      if (start == null || end == null) continue;
      final period = PayrollPeriod(start: start, end: end);
      final key = PayrollService.periodKeyPair(start, end);

      final paidAt = PayrollService.payrollPaymentDate(worker);
      final existing = map[key];
      final existingPaidAt = existing?.latestPaidAt;
      final newerPaidAt = paidAt != null &&
              (existingPaidAt == null || paidAt.isAfter(existingPaidAt))
          ? paidAt
          : existingPaidAt;
      map[key] = (
        period: period,
        paidCount: (existing?.paidCount ?? 0) + 1,
        latestPaidAt: newerPaidAt,
      );
    }

    for (final period in _ignoredPeriods) {
      final key = PayrollService.periodKeyPair(period.start, period.end);
      if (!map.containsKey(key)) {
        map[key] = (period: period, paidCount: 0, latestPaidAt: null);
      }
    }

    // The "current" cycle in the dropdown is whatever the screen is showing
    // right now — not a recalculated value from resolveActiveCycle.
    final currentKey = PayrollService.periodKeyPair(
      _payPeriodStart,
      _payPeriodEnd,
    );
    if (!map.containsKey(currentKey)) {
      map[currentKey] = (
        period: PayrollPeriod(start: _payPeriodStart, end: _payPeriodEnd),
        paidCount: 0,
        latestPaidAt: null,
      );
    }

    final options = map.values.toList()
      ..sort((a, b) => b.period.end.compareTo(a.period.end));
    final limited = options.length > 2 ? options.sublist(0, 2) : options;
    return limited.map((o) {
      final key = PayrollService.periodKeyPair(o.period.start, o.period.end);
      return (
        period: o.period,
        label: PayrollService.formatPayPeriodRange(
          o.period.start,
          o.period.end,
        ),
        paidCount: o.paidCount,
        isCurrent: key == currentKey,
        latestPaidAt: o.latestPaidAt,
      );
    }).toList();
  }

  Future<void> _showPaidWorkersDropdown(BuildContext anchor) async {
    final options = _payPeriodOptions();
    final selectedKey = PayrollService.periodKeyPair(
      _payPeriodStart,
      _payPeriodEnd,
    );

    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final overlaySize = overlayBox?.size ?? MediaQuery.of(context).size;
    final box = anchor.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final anchorRect = Rect.fromPoints(
      box.localToGlobal(
        Offset.zero,
        ancestor: overlay.context.findRenderObject(),
      ),
      box.localToGlobal(
        box.size.bottomRight(Offset.zero),
        ancestor: overlay.context.findRenderObject(),
      ),
    );

    final selected =
        await showMenu<
          ({
            PayrollPeriod period,
            String label,
            int paidCount,
            bool isCurrent,
            DateTime? latestPaidAt,
          })
        >(
          context: context,

          position: RelativeRect.fromRect(
            anchorRect.translate(0, anchorRect.height + 6),
            Offset.zero & overlaySize,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFE5E5E5), width: 1),
          ),
          color: const Color(0xFFFFFFFF),
          elevation: 4,
          items: [
            for (final option in options)
              PopupMenuItem(
                value: option,
                height: 44,
                child: Row(
                  children: [
                    Icon(
                      PayrollService.periodKeyPair(
                                option.period.start,
                                option.period.end,
                              ) ==
                              selectedKey
                          ? Icons.check_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 16,
                      color:
                          PayrollService.periodKeyPair(
                                option.period.start,
                                option.period.end,
                              ) ==
                              selectedKey
                          ? const Color(0xFF0247C4)
                          : const Color(0xFF9CA3AF),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        option.label,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (option.paidCount > 0) ...[
                      const SizedBox(width: 12),
                      Builder(builder: (context) {
                        final dueDate = option.period.end;
                        final paidAt = option.latestPaidAt;
                        final isLate = paidAt != null &&
                            paidAt.isAfter(dueDate);
                        final label = isLate
                            ? 'Paid late on ${DateFormat('d MMM').format(paidAt)}'
                            : 'Paid';
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isLate
                                ? const Color(0xFFFEE2E2)
                                : const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                             label,
                             style: TextStyle(
                               color: isLate
                                   ? const Color(0xFFDC2626)
                                   : const Color(0xFF004FDE),
                               fontSize: 11,
                               fontWeight: FontWeight.w600,
                             ),
                           ),
                         );
                      }),
                    ],
                  ],
                ),
              ),
          ],
        );

    if (selected == null || !mounted) return;
    _isUserSelectedCycle = true;

    setState(() {
      _payPeriodStart = selected.period.start;
      _payPeriodEnd = selected.period.end;
      _payrollMonth = DateTime(
        selected.period.end.year,
        selected.period.end.month,
        1,
      );
      _selectedFilter = 'All';
      _combinePayroll();
    });
    _scheduleAttendanceFetch();
  }

  Widget _buildSearchBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/search icon.svg',
            width: 24,
            height: 24,
            colorFilter: const ColorFilter.mode(
              Color(0xFFBDBDBD),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'search_workers_name_position'.tr(),
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.close, size: 18, color: Colors.grey[400]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildListHeader() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'pay_roll_list'.tr(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF000000),
            ),
          ),
        ),
        _buildFilterDropdown(),
      ],
    );
  }

  Widget _buildFilterDropdown() {
    return PopupMenuButton<String>(
      tooltip: '',
      onSelected: (val) => setState(() => _selectedFilter = val),
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      color: const Color(0xFFFFFFFF),
      elevation: 4,
      itemBuilder: (context) {
        final filters = [
          {'value': 'All', 'label': 'all_filter'.tr()},
          {'value': 'Pay', 'label': 'payable'.tr()},
          {'value': 'Paid', 'label': 'paid'.tr()},
        ];
        return filters.map((f) {
          final currentVal =
              _selectedFilter == 'Pay' || _selectedFilter == 'Paid'
              ? _selectedFilter
              : 'All';
          final selected = currentVal == f['value'];
          return PopupMenuItem<String>(
            value: f['value'],
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF0247C4)
                          : Colors.grey.shade300,
                      width: 2,
                    ),
                    color: selected
                        ? const Color(0xFF0247C4)
                        : Colors.transparent,
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check,
                          size: 12,
                          color: Color(0xFFFFFFFF),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    f['label']!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: selected
                          ? const Color(0xFF0247C4)
                          : const Color(0xFF000000),
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
        height: 43,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0247C4),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/filter.png',
              width: 22,
              height: 22,
              color: const Color(0xFFFFFFFF),
            ),
            const SizedBox(width: 8),
            Text(
              _selectedFilter == 'Pay'
                  ? 'payable'.tr()
                  : _selectedFilter == 'Paid'
                  ? 'paid'.tr()
                  : 'all_filter'.tr(),
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_drop_down,
              color: Color(0xFFFFFFFF),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTabs() {
    const defaultPositions = LocalizationHelper.defaultJobPositions;
    final positionNormalizer = <String, String>{};
    for (final w in _workersList) {
      final pos = (w['position'] ?? '').toString().trim();
      if (pos.isNotEmpty) {
        positionNormalizer.putIfAbsent(pos.toLowerCase(), () => pos);
      }
    }

    final sortedPositions = positionNormalizer.values.toList()..sort();
    final positionsToShow = <String>[...sortedPositions];
    for (final position in defaultPositions) {
      final alreadyIncluded = positionsToShow.any(
        (item) =>
            item.toLowerCase().contains(position.toLowerCase()) ||
            position.toLowerCase().contains(item.toLowerCase()),
      );
      if (!alreadyIncluded) positionsToShow.add(position);
    }

    final filters = <Map<String, String>>[
      {'key': 'All', 'label': 'all_filter'.tr()},
      ...positionsToShow.map(
        (p) => {'key': p, 'label': LocalizationHelper.localizePosition(p)},
      ),
    ];

    return Container(
      width: double.infinity,
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (int i = 0; i < filters.length; i++) ...[
              _buildFilterTab(filters[i]['key']!, filters[i]['label']!),
              if (i < filters.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Container(
                    width: 1,
                    height: 16,
                    color: const Color(0xFFE5E7EB).withValues(alpha: 0.5),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTab(String filterKey, String displayLabel) {
    final isSelected = filterKey == 'All'
        ? _selectedFilter == 'All' ||
              _selectedFilter == 'Pay' ||
              _selectedFilter == 'Paid' ||
              _selectedFilter == 'Today'
        : _selectedFilter == filterKey;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = filterKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0D4CC6) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          displayLabel,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final dynamicHeight = (MediaQuery.of(context).size.height - 329).clamp(
      440.0,
      1200.0,
    );
    return Container(
      width: double.infinity,
      height: dynamicHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/placeholder_workers.svg',
            width: 120,
            height: 100,
            colorFilter: const ColorFilter.mode(
              Color(0xFFCBCBCB),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'no_search_results'.tr()
                : 'no_payroll_records'.tr(),
            style: const TextStyle(
              color: Color(0xFF0247C4),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> employees) {
    final tableHeight = (MediaQuery.of(context).size.height - 329).clamp(
      440.0,
      1200.0,
    );

    return Container(
      height: tableHeight,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 24, 40, 12),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 24),
                    child: Text(
                      'worker_name_header'.tr(),
                      style: _headerStyle(),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 24),
                    child: Text('position'.tr(), style: _headerStyle()),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 24),
                    child: Text('contact_no'.tr(), style: _headerStyle()),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text('status_header'.tr(), style: _headerStyle()),
                ),
                const SizedBox(width: 24, child: Center(child: Text(''))),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFF7F8FC)),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: employees.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, index) => _buildEmployeeRow(employees[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerTable() {
    final tableHeight = (MediaQuery.of(context).size.height - 329).clamp(
      440.0,
      1200.0,
    );

    return ExcludeSemantics(
      child: IgnorePointer(
        child: Container(
          height: tableHeight,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 24, 40, 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: Text(
                          'worker_name_header'.tr(),
                          style: _headerStyle(),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: Text('position'.tr(), style: _headerStyle()),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: Text('contact_no'.tr(), style: _headerStyle()),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('status_header'.tr(), style: _headerStyle()),
                    ),
                    const SizedBox(width: 24),
                  ],
                ),
              ),
              Container(height: 1, color: const Color(0xFFF7F8FC)),
              Expanded(
                child: DelayedShimmer(
                  child: Shimmer.fromColors(
                    baseColor: screenShimmerBaseColor,
                    highlightColor: screenShimmerHighlightColor,
                    period: screenShimmerPeriod,
                    direction: ShimmerDirection.ltr,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 6,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, _) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6F8FA),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Padding(
                                padding: EdgeInsets.only(right: 24),
                                child: Row(
                                  children: [
                                    _PayrollShimmerBlock(
                                      width: 40,
                                      height: 40,
                                      radius: 20,
                                    ),
                                    SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _PayrollShimmerBlock(
                                          width: 110,
                                          height: 14,
                                        ),
                                        SizedBox(height: 7),
                                        _PayrollShimmerBlock(
                                          width: 150,
                                          height: 11,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Padding(
                                padding: EdgeInsets.only(right: 24),
                                child: _PayrollShimmerBlock(
                                  width: 96,
                                  height: 14,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Padding(
                                padding: EdgeInsets.only(right: 24),
                                child: _PayrollShimmerBlock(
                                  width: 105,
                                  height: 14,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: _PayrollShimmerBlock(
                                width: 70,
                                height: 14,
                              ),
                            ),
                            SizedBox(width: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _headerStyle() => const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: Colors.black,
  );

  Widget _buildEmployeeRow(Map<String, dynamic> doc) {
    final isPaid = doc['isPaid'] == true;
    final isEmployedInPeriod = PayrollService.workerEmployedDuringPeriod(
      doc,
      _payPeriodEnd,
    );
    final hasData = (doc['totalWorkDays'] ?? '').toString().isNotEmpty;
    final contactNo = (doc['phone'] ?? '').toString().trim().isEmpty
        ? (doc['contact'] ?? '').toString()
        : (doc['phone'] ?? '').toString();

    void onRowTap() {
      if (_isGuest) {
        showGuestRestrictionDialog(context);
        return;
      }
      if (isPaid && hasData) {
        _showPayrollDataDialog(context, doc, 0);
      } else {
        if (!_requirePayableSalary(doc)) return;
        setState(() {
          _isAddingPayroll = true;
          _workerForPayroll = doc;
        });
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onRowTap,
                child: Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: Row(
                    children: [
                      WorkerAvatar(
                        imageUrl: doc['profileImage']?.toString(),
                        name: (doc['name'] ?? '').toString(),
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (doc['name'] ?? '').toString(),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              (doc['email'] ?? '').toString(),
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black,
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
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Text(
                LocalizationHelper.localizePosition(
                  (doc['position'] ?? '').toString(),
                ),
                style: const TextStyle(fontSize: 15, color: Colors.black),
                maxLines: 2,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Text(
                contactNo,
                style: const TextStyle(fontSize: 15, color: Colors.black),
                maxLines: 1,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onRowTap,
                child: Text(
                  isPaid
                      ? 'paid'.tr()
                      : (isEmployedInPeriod ? 'payable'.tr() : '—'),
                  style: TextStyle(
                    color: isPaid
                        ? const Color(0xFF27AE60)
                        : (isEmployedInPeriod
                              ? const Color(0xFFE74C3C)
                              : const Color(0xFF9CA3AF)),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 24, child: SizedBox.shrink()),
        ],
      ),
    );
  }

  Future<Map<String, int>> _attendanceCountsForRecord(
    Map<String, dynamic> data,
  ) async {
    final workerId = (data['workerId'] ?? data['id'] ?? '').toString().trim();
    final email = (data['email'] ?? '').toString().trim();
    final start =
        AppDateUtils.dateFromValue(data['payPeriodStart']) ?? _payPeriodStart;
    final end =
        AppDateUtils.dateFromValue(data['payPeriodEnd']) ?? _payPeriodEnd;

    if (email.isEmpty && workerId.isEmpty) {
      return PayrollService.attendanceCounts(data);
    }

    try {
      final month = DateTime(end.year, end.month, 1);
      final fresh = await _firestore.getWorkerMonthlyAttendance(
        email,
        workerId: workerId,
        month: month,
        startDate: start,
        endDate: end,
        preFetchedRecords: _liveAttendanceRecords,
      );
      return {
        'absents': fresh['absents'] ?? 0,
        'paidLeaves': fresh['paidLeaves'] ?? 0,
        'unpaidLeaves': fresh['unpaidLeaves'] ?? 0,
        'leaves': fresh['leaves'] ?? 0,
      };
    } catch (_) {
      return PayrollService.attendanceCounts(data);
    }
  }

  Future<void> _downloadPayrollInvoice(Map<String, dynamic> data) async {
    if (!mounted) return;
    FlashySnackBar.show(context, message: 'generating_invoices'.tr());
    try {
      final counts = await _attendanceCountsForRecord(data);
      final totalWorkDays = (data['totalWorkDays'] ?? '0').toString();
      final absents = (counts['absents'] ?? 0).toString();
      final paidLeaves = (counts['paidLeaves'] ?? 0).toString();
      final unpaidLeaves = (counts['unpaidLeaves'] ?? 0).toString();
      final totalLeaves = (counts['leaves'] ?? 0).toString();
      final deductionsAreTotals = data['deductionsAreTotals'] == true;
      final rawAbsentDeduction = (data['absentDeduction'] ?? '0').toString();
      final rawLeaveDeduction = (data['leaveDeduction'] ?? '0').toString();
      final overtime = (data['overtimeAmount'] ?? '0').toString();
      final salary = PayrollService.currentSalaryDisplay(
        data,
        companyCurrency: _companyCurrency,
      );

      final calculation = PayrollService.calculatePayroll(
        salary: salary,
        totalWorkDays: totalWorkDays,
        absents: absents,
        leaves: unpaidLeaves,
        overtimeAmount: overtime,
        absentDeductionPerDay: deductionsAreTotals ? '' : rawAbsentDeduction,
        leaveDeductionPerDay: deductionsAreTotals ? '' : rawLeaveDeduction,
        salaryType: (data['salaryType'] ?? 'Monthly').toString(),
      );

      final currency = PayrollService.getCurrencyPrefix(salary);
      final prefix = _companyCurrency.isNotEmpty
          ? '${PayrollService.getCurrencySymbol(_companyCurrency)} '
          : (currency.isEmpty ? '' : '$currency ');
      final grossSalary = PayrollService.extractSalary(
        calculation['formattedGross'],
      );
      final absentDeductionTotal = deductionsAreTotals
          ? PayrollService.extractSalary(rawAbsentDeduction)
          : (calculation['absentDeduction'] as double? ?? 0.0);
      final leaveDeductionTotal = deductionsAreTotals
          ? PayrollService.extractSalary(rawLeaveDeduction)
          : (calculation['leaveDeduction'] as double? ?? 0.0);
      final overtimeValue = PayrollService.extractSalary(overtime);
      final totalDeductions = absentDeductionTotal + leaveDeductionTotal;
      final savedNetSalary = data['netSalaryAmount'];
      final netSalary = savedNetSalary is num
          ? savedNetSalary.toDouble()
          : (grossSalary + overtimeValue - totalDeductions)
                .clamp(0.0, double.infinity)
                .toDouble();

      final savedPeriodStart = AppDateUtils.dateFromValue(
        data['payPeriodStart'],
      );
      final savedPeriodEnd = AppDateUtils.dateFromValue(data['payPeriodEnd']);
      final payPeriod = savedPeriodStart != null && savedPeriodEnd != null
          ? PayrollService.formatPayPeriodRange(
              savedPeriodStart,
              savedPeriodEnd,
              locale: context.locale.toString(),
            )
          : _payPeriodLabelFor(_payrollMonth);

      final companyProfile =
          await CompanyProfileHelper.getCompanyProfileWithFirestore(_firestore);
      final companyLogoUrl =
          (companyProfile['profilePicUrl'] ??
                  companyProfile['profilePic'] ??
                  '')
              .toString();
      final companyStampUrl =
          (companyProfile['companyStampUrl'] ??
                  companyProfile['stampUrl'] ??
                  '')
              .toString();

      final results = await Future.wait([
        InvoiceService.resolveCompanyLogoBytes(companyLogoUrl),
        InvoiceService.resolveCompanyStampBytes(companyStampUrl),
      ]);
      final companyLogoBytes = results[0];
      final companyStampBytes = results[1];

      Uint8List? employeeImageBytes;

      final bytes = await InvoiceService.generatePayrollInvoice(
        employeeName: (data['name'] ?? '').toString(),
        email: (data['email'] ?? '').toString(),
        position: (data['position'] ?? '').toString(),
        payPeriod: payPeriod,
        totalWorkDays: totalWorkDays,
        absents: absents,
        leaves: totalLeaves,
        paidLeaves: paidLeaves,
        unpaidLeaves: unpaidLeaves,
        overtimeAmount: AmountText.formatFull(overtime),
        salary: AmountText.formatFull(salary),
        dailyRate: (calculation['formattedDailyRate'] ?? '${prefix}0.00')
            .toString(),
        grossPay: '$prefix${PayrollService.formatFullNumber(grossSalary)}',
        overtimePay: (calculation['formattedOvertime'] ?? '${prefix}0.00')
            .toString(),
        absentDeduction:
            '$prefix${PayrollService.formatFullNumber(absentDeductionTotal)}',
        leaveDeduction:
            '$prefix${PayrollService.formatFullNumber(leaveDeductionTotal)}',
        totalDeductions:
            '$prefix${PayrollService.formatFullNumber(totalDeductions)}',
        netSalary: '$prefix${PayrollService.formatFullNumber(netSalary)}',
        currency: _companyCurrency,
        companyName: CompanyProfileHelper.companyNameOrFallback(
          companyProfile['companyName'] ?? companyProfile['businessName'],
        ),
        companyAddress: (companyProfile['address'] ?? '').toString(),
        companyEmail: (companyProfile['email'] ?? '').toString(),
        companyPhone:
            (companyProfile['phone'] ??
                    companyProfile['contact1'] ??
                    companyProfile['contact'] ??
                    '')
                .toString(),
        companyId:
            (companyProfile['companyId'] ?? companyProfile['businessId'] ?? '')
                .toString(),
        companyStampImageUrl: companyStampUrl,
        companyStampBytes: companyStampBytes,
        companyLogoUrl: companyLogoUrl,
        companyLogoBytes: companyLogoBytes,
        invoiceNo: (data['invoiceNo'] ?? data['invoiceNumber'] ?? '')
            .toString(),
        workerId: (data['workerId'] ?? data['id'] ?? '').toString(),
        employeeImageBytes: employeeImageBytes,
      );

      final safeName = (data['name'] ?? 'worker').toString().replaceAll(
        RegExp(r'[^a-zA-Z0-9_-]'),
        '_',
      );
      final safePeriod = payPeriod.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final fileName = 'payroll_${safeName}_$safePeriod.pdf';
      final saved = await InvoiceService.shareInvoice(bytes, fileName);
      if (saved && mounted) {
        FlashySnackBar.show(
          context,
          message: 'file_saved_and_opened'.tr(namedArgs: {'file': fileName}),
        );
      }
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'PayrollPreviewInvoice');
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'unexpected_error'.tr(),
          isError: true,
        );
      }
    }
  }

  bool get _isViewingCurrentCycle {
    final active = _trueCurrentPayrollCycle();
    return PayrollService.payrollPeriodsEqual(
      PayrollPeriod(start: _payPeriodStart, end: _payPeriodEnd),
      active,
    );
  }

  PayrollPeriod _trueCurrentPayrollCycle() {
    final persisted = PayrollPeriod(start: _payPeriodStart, end: _payPeriodEnd);
    // Single source of truth — see [PayrollCycleService.resolveActiveCycle].
    // A persisted overdue cycle (one behind the containing cycle) is kept only
    // while it still holds unpaid workers, so overdue never silently expires.
    return PayrollCycleService.resolveActiveCycle(
      salaryPayDay: _salaryPayDay,
      persistedCycle: persisted,
      now: DateTime.now(),
      persistedHasUnpaidWorkers: _payableWorkersForCycle(persisted).isNotEmpty,
    );
  }

  bool _recordInCurrentPayrollCycle(Map<String, dynamic> data) {
    final active = _trueCurrentPayrollCycle();
    final displayedCycle = PayrollPeriod(
      start: _payPeriodStart,
      end: _payPeriodEnd,
    );
    if (!PayrollService.payrollPeriodsEqual(displayedCycle, active)) {
      return false;
    }
    final start = AppDateUtils.dateFromValue(data['payPeriodStart']);
    final end = AppDateUtils.dateFromValue(data['payPeriodEnd']);
    if (start != null && end != null && start.isBefore(end)) {
      return PayrollService.payrollPeriodsEqual(
        PayrollPeriod(start: start, end: end),
        active,
      );
    }
    return false;
  }

  void _showPayrollDataDialog(
    BuildContext context,
    Map<String, dynamic> data,
    int index, {
    bool readOnly = false,
  }) async {
    final canEdit = !readOnly && _recordInCurrentPayrollCycle(data);
    final name = (data['name'] ?? '').toString();
    final email = (data['email'] ?? '').toString();
    final totalWorkDays = (data['totalWorkDays'] ?? '0').toString();

    final isPaidRecord = PayrollService.isPayrollRecordPaid(data);
    final attendanceCounts = isPaidRecord
        ? PayrollService.attendanceCounts(data)
        : await _attendanceCountsForRecord(data);
    final absents = (attendanceCounts['absents'] ?? 0).toString();
    final paidLeaves = (attendanceCounts['paidLeaves'] ?? 0).toString();
    final deductionLeaveDays = (attendanceCounts['unpaidLeaves'] ?? 0)
        .toString();
    final rawAbsentDeduction = (data['absentDeduction'] ?? '0').toString();
    final rawLeaveDeduction = (data['leaveDeduction'] ?? '0').toString();
    final rawOvertimeAmount = (data['overtimeAmount'] ?? '0').toString();
    final deductionsAreTotals = data['deductionsAreTotals'] == true;
    final salaryDisplay = PayrollService.currentSalaryDisplay(
      data,
      companyCurrency: _companyCurrency,
    );
    final currencyPrefix = PayrollService.getCurrencyPrefix(salaryDisplay);
    final otPrefix = currencyPrefix.isEmpty ? '' : '$currencyPrefix ';
    final overtimeVal = PayrollService.extractSalary(rawOvertimeAmount);
    final overtimeAmount =
        '$otPrefix${PayrollService.formatFullNumber(overtimeVal)}';
    final salary = AmountText.formatFull(
      salaryDisplay,
      locale: context.locale.toString(),
    );
    final hasLeaveDeduction = rawLeaveDeduction.trim().isNotEmpty;
    final totalDaysValue = PayrollService.parseIntSafe(totalWorkDays);
    final effectiveWorkedDays =
        totalDaysValue -
        PayrollService.parseIntSafe(absents) -
        (hasLeaveDeduction
            ? PayrollService.parseIntSafe(deductionLeaveDays)
            : 0);

    final baseCalc = totalDaysValue > 0
        ? PayrollService.calculatePayroll(
            salary: salaryDisplay,
            totalWorkDays: totalWorkDays,
            daysWorked: effectiveWorkedDays > 0
                ? effectiveWorkedDays.toString()
                : '0',
            absents: absents,
            leaves: deductionLeaveDays,
            overtimeAmount: rawOvertimeAmount,
            absentDeductionPerDay: deductionsAreTotals
                ? ''
                : rawAbsentDeduction,
            leaveDeductionPerDay: deductionsAreTotals ? '' : rawLeaveDeduction,
            salaryType: (data['salaryType'] ?? 'Monthly').toString(),
          )
        : const <String, dynamic>{};

    if (baseCalc.isNotEmpty &&
        !deductionsAreTotals &&
        PayrollService.extractSalary(rawAbsentDeduction) == 0) {
      final autoCalc = baseCalc['absentDeduction'] as double? ?? 0;
      if (autoCalc > 0) {
        baseCalc['absentDeduction'] = 0.0;
        baseCalc['formattedAbsentDeduct'] = '0';
        baseCalc['netSalary'] =
            (baseCalc['netSalary'] as double? ?? 0) + autoCalc;
        baseCalc['totalDeductions'] =
            (baseCalc['totalDeductions'] as double? ?? 0) - autoCalc;
        final cur = PayrollService.getCurrencyPrefix(salaryDisplay);
        final pfx = cur.isNotEmpty ? '$cur ' : '';
        final netVal = baseCalc['netSalary'] as double? ?? 0;
        baseCalc['formattedNet'] =
            '$pfx${PayrollService.formatFullNumber(netVal)}';
        baseCalc['formattedNetSalary'] = baseCalc['formattedNet'];
      }
    }

    final previewCalc = deductionsAreTotals && baseCalc.isNotEmpty
        ? {
            ...baseCalc,
            'formattedNet': () {
              final netPayment = PayrollService.calculateNetFromTotals(
                salary: salaryDisplay,
                overtimeAmount: rawOvertimeAmount,
                absentDeduction: rawAbsentDeduction,
                leaveDeduction: rawLeaveDeduction,
                salaryType: (data['salaryType'] ?? 'Monthly').toString(),
              );
              final currency = PayrollService.getCurrencyPrefix(salaryDisplay);
              final pfx = currency.isEmpty ? '' : '$currency ';
              return '$pfx${PayrollService.formatFullNumber(netPayment)}';
            }(),
          }
        : baseCalc;

    final salaryAfterDeduction = AmountText.formatFull(
      (previewCalc['formattedNet'] ?? previewCalc['formattedNetSalary'] ?? '0')
          .toString(),
      locale: context.locale.toString(),
    );
    final absentDeduction = AmountText.formatFull(
      (deductionsAreTotals
              ? rawAbsentDeduction
              : previewCalc['formattedAbsentDeduct'] ?? rawAbsentDeduction)
          .toString(),
      locale: context.locale.toString(),
    );

    final paidDate = PayrollService.payrollPaymentDate(data);
    final paidDateText = paidDate == null
        ? '-'
        : DateFormat.yMMMd(context.locale.toString()).format(paidDate);
    final dialogWidth = MediaQuery.of(context).size.width < 500
        ? MediaQuery.of(context).size.width * 0.9
        : 480.0;

    final result = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'PayrollDataDialog',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, _, _) => const SizedBox(),
      transitionBuilder: (ctx, animation, _, _) => _buildBlurDialog(
        dialogContext: ctx,
        animation: animation,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(
            child: Container(
              width: dialogWidth,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF000000).withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 40,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFF004FDE),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(6),
                        topRight: Radius.circular(6),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(ctx).pop(),
                          child: const MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                Icons.close,
                                color: Color(0xFFFFFFFF),
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'payroll_data_preview'.tr(),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: const TextStyle(
                                color: Color(0xFFFFFFFF),
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (canEdit)
                          GestureDetector(
                            onTap: () async {
                              final confirmed = await DeleteDialog.show(
                                context: context,
                                title: 'edit_payroll'.tr(),
                                content: 'edit_paid_payroll_confirm'.tr(),
                                confirmButtonText: 'yes',
                              );
                              if (confirmed && ctx.mounted) {
                                Navigator.of(ctx).pop('edit');
                              }
                            },
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: 10,
                                  top: 10,
                                  bottom: 10,
                                  right: 4,
                                ),
                                child: SvgPicture.asset(
                                  'assets/edit_icon.svg',
                                  height: 20,
                                  width: 20,
                                  colorFilter: const ColorFilter.mode(
                                    Colors.white,
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(width: 2),
                        _PayrollInvoiceShareButton(
                          onShare: () => _downloadPayrollInvoice(data),
                        ),
                      ],
                    ),
                  ),
                  _buildWorkerPreviewHeader(
                    name: name,
                    email: email,
                    imageUrl: data['profileImage']?.toString(),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFFFFF),
                      border: Border(
                        left: BorderSide(color: Color(0xFFE8E8E8), width: 1.5),
                        right: BorderSide(color: Color(0xFFE8E8E8), width: 1.5),
                        bottom: BorderSide(
                          color: Color(0xFFE8E8E8),
                          width: 1.5,
                        ),
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(6),
                        bottomRight: Radius.circular(6),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildMetricCard(
                                  icon: _buildAbsentsIcon(),
                                  title: 'absents_label'.tr(),
                                  value: absents,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildMetricCard(
                                  icon: _buildLeavesIcon(),
                                  title: 'leaves_label'.tr(),
                                  value: paidLeaves,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildMetricCard(
                                  icon: _buildAbsentsIcon(),
                                  title: 'absent_deduction'.tr(),
                                  value: absentDeduction.isEmpty
                                      ? '0'
                                      : absentDeduction,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildMetricCard(
                                  icon: const Icon(
                                    Icons.event_available_rounded,
                                    color: Color(0xFF004FDE),
                                    size: 20,
                                  ),
                                  title: 'paid_on'.tr(),
                                  value: paidDateText,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildPayrollPreviewBottom(
                            absentDeduction,
                            overtimeAmount,
                            salary,
                            salaryAfterDeduction,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result == 'edit' && mounted) {
      setState(() {
        _isAddingPayroll = true;
        _workerForPayroll = data;
      });
    } else if (result == 'view' && mounted) {
      setState(() {
        _isAddingPayroll = true;
        _workerForPayroll = data;
        _isViewOnly = true;
      });
    }
  }

  Widget _buildPayrollPreviewBottom(
    String absentDeduction,
    String overtimeAmount,
    String salary,
    String salaryAfterDeduction,
  ) {
    double parseAmount(String val) =>
        double.tryParse(val.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    final hasDeduction = parseAmount(absentDeduction) > 0;
    final hasOvertime = parseAmount(overtimeAmount) > 0;

    final baseRow = Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            icon: _buildOvertimeDaysIcon(),
            title: 'overtime_amount'.tr(),
            value: overtimeAmount,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            icon: _buildSalaryIcon(),
            title: 'salary'.tr(),
            value: salary,
          ),
        ),
      ],
    );

    if (!hasDeduction && !hasOvertime) return baseRow;

    return Column(
      children: [
        baseRow,
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                icon: const Icon(
                  Icons.account_balance_wallet,
                  color: Color(0xFF004FDE),
                  size: 20,
                ),
                title: 'salary_after_deduction'.tr(),
                value: salaryAfterDeduction,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(child: SizedBox()),
          ],
        ),
      ],
    );
  }

  Widget _buildWorkerPreviewHeader({
    required String name,
    required String email,
    String? imageUrl,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(32, 16, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(bottom: BorderSide(color: Color(0xFFE8E8E8), width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          WorkerAvatar(
            imageUrl: imageUrl,
            name: name,
            size: 60,
            border: Border.all(color: const Color(0xFF0A51D0), width: 2),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Color(0xFF333333),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    SvgPicture.asset(
                      'assets/email.svg',
                      height: 12,
                      width: 12,
                      colorFilter: const ColorFilter.mode(
                        Color(0xFF666666),
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        email,
                        style: const TextStyle(
                          color: Color(0xFF666666),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required Widget icon,
    required String title,
    required String value,
  }) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE8E8E8), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE5EEFC),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(child: icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF000000),
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbsentsIcon() => SvgPicture.asset(
    'assets/absent.svg',
    width: 20,
    height: 20,
    colorMapper: const SvgFillColorMapper(
      source: Color(0xFFFF0004),
      replacement: Color(0xFF004FDE),
    ),
  );

  Widget _buildLeavesIcon() => SvgPicture.asset(
    'assets/leave.svg',
    width: 20,
    height: 20,
    colorMapper: const SvgFillColorMapper(
      source: Color(0xFFFF7B00),
      replacement: Color(0xFF004FDE),
    ),
  );

  Widget _buildSalaryIcon() => Image.asset(
    'assets/salary.png',
    width: 20,
    height: 20,
    fit: BoxFit.contain,
    color: const Color(0xFF004FDE),
    colorBlendMode: BlendMode.srcIn,
  );

  Widget _buildOvertimeDaysIcon() => Image.asset(
    'assets/overtime.png',
    width: 20,
    height: 20,
    fit: BoxFit.contain,
    color: const Color(0xFF004FDE),
    colorBlendMode: BlendMode.srcIn,
  );
}

class _PayrollShimmerBlock extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _PayrollShimmerBlock({
    required this.width,
    required this.height,
    this.radius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _PayrollInvoiceShareButton extends StatefulWidget {
  final Future<void> Function() onShare;

  const _PayrollInvoiceShareButton({required this.onShare});

  @override
  State<_PayrollInvoiceShareButton> createState() =>
      _PayrollInvoiceShareButtonState();
}

class _PayrollInvoiceShareButtonState
    extends State<_PayrollInvoiceShareButton> {
  bool _isSharing = false;

  Future<void> _share() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      await widget.onShare();
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isSharing ? null : _share,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.only(
            left: 4,
            top: 10,
            bottom: 10,
            right: 10,
          ),
          child: _isSharing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : SvgPicture.asset(
                  'assets/share1.svg',
                  height: 22,
                  width: 22,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFFFFFFFF),
                    BlendMode.srcIn,
                  ),
                ),
        ),
      ),
    );
  }
}
