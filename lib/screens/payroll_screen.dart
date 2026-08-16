import 'dart:async';
import 'dart:ui';
import '../utils/ui_helpers.dart';
import '../utils/helpers.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../providers.dart';
import '../services/auth_service.dart';
import '../services/dummy_data.dart';
import '../services/error_reporter.dart';
import '../services/firestore_service.dart';
import '../services/invoice_service.dart';
import '../services/payroll_service.dart';
import '../services/preferences_service.dart';
import '../services/salary_day_scheduler.dart';
import '../utils/utils.dart';
import '../widgets/amount_text.dart';
import '../widgets/clickable_gesture_detector.dart';
import '../widgets/notification_bell.dart';
import 'add_payroll_screen.dart';

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
  // Last (suppressionKey, day) for which the reminder dialog was shown, so a
  // queued re-check or the home-screen global trigger can't re-open it right
  // after the user dismissed it. A new day or a new pay cycle re-arms it, and
  // an explicit user action (force) always re-evaluates.
  String? _lastShownReminderKey;
  DateTime? _lastShownReminderDay;
  bool _workersLoaded = false;
  bool _payrollLoaded = false;

  String _companyCurrency = CurrencyUtils.defaultCode;
  DateTime _payrollMonth = PayrollService.currentPayrollMonth();
  int? _salaryPayDay;
  DateTime _payPeriodStart = PayrollService.payPeriodStart(DateTime.now());
  DateTime _payPeriodEnd = PayrollService.payPeriodEnd(DateTime.now());

  Map<String, dynamic>? _workerForPayroll;

  StreamSubscription? _payrollSub;
  StreamSubscription? _workersSub;
  StreamSubscription? _attendanceSub;
  StreamSubscription? _holidaysSub;
  StreamSubscription<Map<String, dynamic>?>? _profileSub;

  Timer? _attendanceDebounce;

  bool get _isGuest => _authService.currentUser?.isAnonymous ?? false;

  /// Returns true only when today is AT OR AFTER the current active cycle's
  /// due date (_payPeriodEnd). This is the correct gate for Pay All:
  ///
  ///   Active cycle = Aug 16 → Sep 16  (just advanced on Aug 16)
  ///   Today        = Aug 16
  ///   _payPeriodEnd = Sep 16
  ///   → _isCurrentCycleDue = false  ← correct, Sep 16 not reached yet
  ///
  ///   Active cycle = Jul 16 → Aug 16
  ///   Today        = Aug 16
  ///   _payPeriodEnd = Aug 16
  ///   → _isCurrentCycleDue = true   ← correct, due date reached
  ///
  /// Using `today.day == payDay` (the old _isTodayPayDay) was wrong because it
  /// would show Pay All on Aug 16 even after the cycle had already advanced to
  /// Aug16→Sep16, enabling an accidental early double-payment.
  bool get _isCurrentCycleDue {
    if (_salaryPayDay == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(_payPeriodEnd.year, _payPeriodEnd.month, _payPeriodEnd.day);
    return !today.isBefore(dueDate); // today >= dueDate
  }

  bool get isPayrollReminderDataReady => _workersLoaded && _payrollLoaded && _salaryPayDay != null;

  List<Map<String, dynamic>> get _currentPayablePayrollWorkers => _payableWorkersForPeriod(_payrollMonth);

  List<Map<String, dynamic>> get _filteredEmployees {
    final filtered = _payrollDocs.where((doc) {
      final name = (doc['name'] ?? '').toString().toLowerCase();
      final pos = (doc['position'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      if (!name.contains(query) && !pos.contains(query)) return false;
      return _matchesFilter(doc, _selectedFilter);
    }).toList()
      ..sort((a, b) {
        final paidA = a['isPaid'] == true;
        final paidB = b['isPaid'] == true;
        if (paidA != paidB) return paidA ? 1 : -1;
        return (a['name'] ?? '').toString().trim().toLowerCase().compareTo(
              (b['name'] ?? '').toString().trim().toLowerCase(),
            );
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

    if (widget.isActive && (!oldWidget.isActive || widget.activationToken != oldWidget.activationToken)) {
      // Explicit navigation to the Payroll tab (sidebar click) always
      // re-evaluates the reminder, even if it was already shown today.
      _schedulePayrollReminderCheck(force: true);
    }

    if (!_initialized || !_isGuest) return;

    final latestWorkers = List<Map<String, dynamic>>.from(DummyData.workers);
    final currentIds = _workersList.map((w) => w['id']?.toString() ?? '').toSet();
    final latestIds = latestWorkers.map((w) => w['id']?.toString() ?? '').toSet();
    if (currentIds.length == latestIds.length && currentIds.containsAll(latestIds)) return;

    _workersList = latestWorkers;
    _combinePayroll();
    _scheduleAttendanceFetch();
  }

  @override
  void dispose() {
    _attendanceDebounce?.cancel();
    _payrollSub?.cancel();
    _workersSub?.cancel();
    _attendanceSub?.cancel();
    _holidaysSub?.cancel();
    _profileSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _payableWorkersForPeriod(DateTime month) {
    return PayrollService.payableWorkersForPeriod(
      _workersList,
      _rawPayrollDocs,
      month: month,
      companyCurrency: _companyCurrency,
      periodStart: month.year == _payrollMonth.year && month.month == _payrollMonth.month ? _payPeriodStart : null,
      periodEnd: month.year == _payrollMonth.year && month.month == _payrollMonth.month ? _payPeriodEnd : null,
    );
  }

  int? _payDayFromProfile(Map<String, dynamic>? profile) {
    final value = profile?['salaryPayDay'] ?? profile?['salary_pay_day'];
    final day = value is num ? value.toInt() : int.tryParse('$value');
    return day != null && day >= 1 && day <= 31 ? day : null;
  }

  PayrollPeriod? _persistedCycleFromProfile(Map<String, dynamic>? profile, int payDay, {DateTime? referenceDate}) {
    final savedStart = AppDateUtils.dateFromValue(profile?['payrollCycleStart']);
    final savedEnd = AppDateUtils.dateFromValue(profile?['payrollCycleEnd']);
    final normalizedPayDay = payDay.clamp(1, 28);

    // Only accept the persisted cycle if it's reasonably recent relative to a reference date.
    // This prevents a stale cycle from a previous month (e.g. April) from being used
    // when the current cycle is different (e.g. August), which would cause the payroll
    // period to incorrectly jump backward.
    final referenceMonth = referenceDate?.month ?? 0;
    final savedStartMonth = savedStart?.month ?? 0;
    final monthDifference = (savedStartMonth - referenceMonth).abs();
    // Allow a difference of at most 1 month (the cycle could have just advanced).
    // Larger differences indicate a stale cycle from a different pay period.
    final isStaleByMonth = monthDifference > 1;

    if (savedStart != null &&
        savedEnd != null &&
        savedStart.isBefore(savedEnd) &&
        savedStart.day == normalizedPayDay &&
        savedEnd.day == normalizedPayDay &&
        savedEnd.difference(savedStart).inDays >= 25 &&
        savedEnd.difference(savedStart).inDays <= 35 &&
        !isStaleByMonth) {
      return PayrollPeriod(
        start: DateTime(savedStart.year, savedStart.month, savedStart.day),
        end: DateTime(savedEnd.year, savedEnd.month, savedEnd.day),
      );
    }
    return null;
  }

  PayrollPeriod _periodFromProfile(Map<String, dynamic>? profile, int payDay) {
    // Initial resolve (before payroll/workers are tailed) must never advance;
    // _reconcilePayrollPeriod performs the exact one-cycle advance later.
    // ALWAYS pass the current date as reference: gating it on _salaryPayDay
    // made it null on first load, so _persistedCycleFromProfile treated every
    // persisted cycle as stale and rejected it. Honouring the persisted cycle
    // (e.g. an overdue Jul16→Aug16) keeps _payPeriodEnd on the due date so the
    // reminder/overdue popup still fires on app start.
    final referenceDate = DateTime.now();
    return _resolveCurrentPayrollPeriod(
      payDay: payDay,
      persisted: _persistedCycleFromProfile(profile, payDay, referenceDate: referenceDate),
      advanceIfFullyPaid: false,
    );
  }

  // Central, idempotent current-cycle resolver. It only ever returns the cycle
  // containing today, or that cycle + EXACTLY ONE advance when every eligible
  // worker for it is Paid at/after the payday boundary.
  PayrollPeriod _resolveCurrentPayrollPeriod({
    int? payDay,
    PayrollPeriod? persisted,
    bool advanceIfFullyPaid = true,
    DateTime? referenceDate,
  }) {
    return PayrollService.resolveCurrentPayrollPeriod(
      workersList: _workersList,
      payrollRecords: _rawPayrollDocs,
      payDay: payDay ?? _salaryPayDay ?? DateTime.now().day,
      companyCurrency: _companyCurrency,
      referenceDate: referenceDate,
      persistedCycle: persisted,
      advanceIfFullyPaid: advanceIfFullyPaid,
    );
  }

  Future<void> _reconcilePayrollPeriod() async {
    if (!mounted || !_workersLoaded || !_payrollLoaded || _salaryPayDay == null) return;

    // The resolver is idempotent for the same Firebase state, so repeated
    // stream events can never advance more than one cycle.
    var resolved = _resolveCurrentPayrollPeriod(
      payDay: _salaryPayDay,
      persisted: PayrollPeriod(start: _payPeriodStart, end: _payPeriodEnd),
    );
    if (!mounted) return;

    // ── Post-resolver overdue correction ──────────────────────────────
    // During initial load the resolver runs with empty worker/payroll
    // data, so it cannot detect unpaid workers in the previous cycle and
    // returns `base` (the next cycle).  When data later arrives the
    // resolver's built-in overdue check is blocked because the anchor
    // matches base (persisted == base from the initial load).  This block
    // catches that case: if the resolved cycle starts at/after the payday
    // boundary AND the immediately previous cycle has unpaid workers, the
    // cycle is overdue and must be corrected — unless the user explicitly
    // advanced it via Ignore/Confirm.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final normalizedPayDay = _salaryPayDay!.clamp(1, 28);
    final lastDay = DateTime(today.year, today.month + 1, 0).day;
    final currentMonthPayday = DateTime(today.year, today.month, normalizedPayDay.clamp(1, lastDay));

    if (today.isAfter(currentMonthPayday) &&
        !resolved.start.isBefore(currentMonthPayday) &&
        PayrollService.payrollPeriodsEqual(
            resolved, PayrollPeriod(start: _payPeriodStart, end: _payPeriodEnd))) {
      final prevCycleEnd = resolved.start;
      final prevMonth = DateTime(prevCycleEnd.year, prevCycleEnd.month - 1, 1);
      final prevLastDay = DateTime(prevMonth.year, prevMonth.month + 1, 0).day;
      final prevCycleStart = DateTime(prevMonth.year, prevMonth.month, normalizedPayDay.clamp(1, prevLastDay));

      final prevPayable = PayrollService.payableWorkersForPeriod(
        _workersList,
        _rawPayrollDocs,
        month: DateTime(prevCycleEnd.year, prevCycleEnd.month, 1),
        allowUndatedRecords: true,
        companyCurrency: _companyCurrency,
        periodStart: prevCycleStart,
        periodEnd: prevCycleEnd,
      );

      if (prevPayable.isNotEmpty &&
          !PayrollService.payrollPeriodsEqual(
              resolved, PayrollPeriod(start: prevCycleStart, end: prevCycleEnd))) {
        // Previous cycle has unpaid workers.  Only override if the cycle
        // was NOT explicitly advanced via Ignore/Confirm.
        final prevWindow = PayrollReminderWindow(
          payrollMonth: DateTime(prevCycleEnd.year, prevCycleEnd.month, 1),
          dueDate: prevCycleEnd,
          dayOffset: 0,
        );
        final isIgnored =
            await PreferencesService.isPayrollReminderIgnored(prevWindow.suppressionKey);
        if (!isIgnored && mounted) {
          resolved = PayrollPeriod(start: prevCycleStart, end: prevCycleEnd);
        }
      }
    }

    final changed = PayrollService.periodDateKey(resolved.start) != PayrollService.periodDateKey(_payPeriodStart) ||
        PayrollService.periodDateKey(resolved.end) != PayrollService.periodDateKey(_payPeriodEnd);
    if (!changed) return;

    if (!_isGuest) {
      await _firestore.updateUserProfile({
        'payrollCycleStart': resolved.start.toIso8601String(),
        'payrollCycleEnd': resolved.end.toIso8601String(),
      });
    }

    if (!mounted) return;
    setState(() {
      _payPeriodStart = resolved.start;
      _payPeriodEnd = resolved.end;
      _payrollMonth = DateTime(resolved.end.year, resolved.end.month, 1);
      _selectedFilter = 'All';
      _combinePayroll();
    });
    _scheduleAttendanceFetch();
  }

  Future<PayrollPeriod> _periodForProfile(Map<String, dynamic>? profile, int? salaryPayDay) async {
    if (salaryPayDay == null) {
      return PayrollPeriod(
        start: PayrollService.payPeriodStart(DateTime.now()),
        end: PayrollService.payPeriodEnd(DateTime.now()),
      );
    }
    return _periodFromProfile(profile, salaryPayDay);
  }

  void _applyCompanySettings({required String companyCurrency, required int? salaryPayDay, required PayrollPeriod period}) {
    setState(() {
      _companyCurrency = companyCurrency;
      _salaryPayDay = salaryPayDay;
      _payPeriodStart = period.start;
      _payPeriodEnd = period.end;
      _payrollMonth = DateTime(period.end.year, period.end.month, 1);
      _combinePayroll();
    });
    _scheduleAttendanceFetch();
    // Re-run the cycle resolver now that the pay day is known. Catches the
    // app-start ordering where the workers/payroll streams emitted BEFORE the
    // profile loaded: the earlier _reconcilePayrollPeriod() calls no-oped on a
    // null pay day, so without this the overdue cycle is never restored and the
    // reminder/overdue popup never appears.
    _reconcilePayrollPeriod();
  }

  Future<void> _loadCompanySettings() async {
    final profile = _isGuest ? await PreferencesService.getGuestProfileData() : await _firestore.getUserProfile();
    if (!mounted) return;

    var companyCurrency = CurrencyUtils.normalize(profile?['currency']);
    final salaryPayDay = _payDayFromProfile(profile);
    final rawProfileCurrency = profile?['currency']?.toString().trim();

    if (companyCurrency == CurrencyUtils.defaultCode && (rawProfileCurrency == null || rawProfileCurrency.isEmpty)) {
      final cached = PreferencesService.cachedCompanyCurrency;
      if (cached != null && cached.isNotEmpty) companyCurrency = CurrencyUtils.normalize(cached);
    } else {
      PreferencesService.setCompanyCurrency(companyCurrency).catchError((_) {});
    }

    final period = await _periodForProfile(profile, salaryPayDay);
    if (!mounted) return;
    _applyCompanySettings(companyCurrency: companyCurrency, salaryPayDay: salaryPayDay, period: period);
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
    _profileSub = _firestore.userProfileStream.listen((profile) async {
      if (!mounted || profile == null) return;
      try {
        final currency = CurrencyUtils.normalize(profile['currency']);
        final salaryPayDay = _payDayFromProfile(profile);
        final period = await _periodForProfile(profile, salaryPayDay);

        if (currency == _companyCurrency &&
            salaryPayDay == _salaryPayDay &&
            PayrollService.periodDateKey(period.start) == PayrollService.periodDateKey(_payPeriodStart) &&
            PayrollService.periodDateKey(period.end) == PayrollService.periodDateKey(_payPeriodEnd)) {
          return;
        }

        if (!mounted) return;
        _applyCompanySettings(companyCurrency: currency, salaryPayDay: salaryPayDay, period: period);
      } catch (error, stackTrace) {
        ErrorReporter.report(error, stackTrace, context: 'PayrollProfileStream');
      }
    }, onError: _handlePayrollStreamError);

    _workersSub = _firestore.workersStream.listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _workersLoaded = true;
        _workersList = snapshot.docs.map((d) => {...?d.data() as Map<String, dynamic>?, 'id': d.id}).toList();
        _combinePayroll();
      });
      _scheduleAttendanceFetch();
      _reconcilePayrollPeriod();
    }, onError: _handlePayrollStreamError);

    _payrollSub = _firestore.payrollStream.listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _payrollLoaded = true;
        _rawPayrollDocs = snapshot.docs.map((d) => {...?d.data() as Map<String, dynamic>?, 'id': d.id}).toList();
        _combinePayroll();
      });
      _scheduleAttendanceFetch();
      _reconcilePayrollPeriod();
    }, onError: _handlePayrollStreamError);

    _attendanceSub = _firestore.attendanceStream.listen((snapshot) {
      if (!mounted) return;
      _liveAttendanceRecords = snapshot.docs
          .map((doc) => {...?doc.data() as Map<String, dynamic>?, 'id': doc.id})
          .toList();
      _scheduleAttendanceFetch();
    }, onError: _handlePayrollStreamError);

    _holidaysSub = _firestore.holidaysStream.listen((_) {
      if (mounted) _scheduleAttendanceFetch();
    }, onError: _handlePayrollStreamError);
  }

  void _handlePayrollStreamError(Object error, StackTrace stackTrace) {
    ErrorReporter.report(error, stackTrace, context: 'PayrollScreenStream');
    if (mounted) setState(() => _isLoading = false);
  }

  void _combinePayroll() {
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
        doc['overtimeAmount'] = '0';
        doc['salary'] = doc['salary'] ?? zeroAmount;
        doc['netSalary'] = zeroAmount;
      }
    }

    _isLoading = false;
    if (_selectedFilter == 'Pay' && _currentPayablePayrollWorkers.isEmpty) _selectedFilter = 'All';
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

  void _scheduleAttendanceFetch() {
    _attendanceDebounce?.cancel();
    _attendanceDebounce = Timer(const Duration(milliseconds: 600), () {
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
        workingDays = await _firestore.getMonthlyWorkingDays(month: month, startDate: _payPeriodStart, endDate: _payPeriodEnd);
      } catch (_) {
        workingDays = 22;
      }
    }

    if (!mounted) { _isLoadingAttendance = false; return; }

    final futures = <Future<void>>[];
    for (final doc in _payrollDocs) {
      final status = (doc['status'] ?? '').toString().trim().toLowerCase();
      final isPaid = doc['isPaid'] == true || doc['hasPaidPayrollRecord'] == true || status == 'paid';
      if (isPaid) continue;

      final email = (doc['email'] ?? '').toString();
      final workerId = (doc['workerId'] ?? doc['id'] ?? '').toString();
      if (email.isEmpty && workerId.isEmpty) continue;

      futures.add(_fetchAndApplyAttendance(doc, email, workerId, month, workingDays));
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
  ) async {
    final status = (doc['status'] ?? '').toString().trim().toLowerCase();
    final isPaid = doc['isPaid'] == true || doc['hasPaidPayrollRecord'] == true || status == 'paid';
    if (isPaid) return;

    try {
      Map<String, int> attendance;

      if (_isGuest) {
        final matched = DummyData.attendance.where((att) {
          final attDate = AppDateUtils.attendanceRecordDate(att);
          if (attDate == null || attDate.year != month.year || attDate.month != month.month) return false;
          final attWorkerId = (att['workerId'] ?? '').toString().trim();
          final attEmail = (att['email'] ?? '').toString().trim().toLowerCase();
          if (workerId.isNotEmpty && attWorkerId.isNotEmpty) return workerId == attWorkerId;
          return email.isNotEmpty && attEmail == email.toLowerCase();
        }).toList();

        attendance = {
          'absents': matched.where((a) => a['status'] == 'Absent').length,
          'paidLeaves': matched.where((a) => a['status'] == 'Leave').length,
          'unpaidLeaves': 0,
          'leaves': matched.where((a) => a['status'] == 'Leave').length,
        };
      } else {
        // Pass the exact pay-period boundaries so attendance is counted
        // inclusively for payPeriodStart <= date <= payPeriodEnd.
        // Without startDate/endDate the service falls back to the calendar
        // month, which drops Jul 16–Jul 31 records for a Jul16→Aug16 cycle.
        attendance = await _firestore.getWorkerMonthlyAttendance(
          email,
          workerId: workerId,
          month: month,
          startDate: _payPeriodStart,
          endDate: _payPeriodEnd,
          preFetchedRecords: _liveAttendanceRecords,
        );
      }

      doc['absents'] = (attendance['absents'] ?? 0).toString();
      doc['paidLeaves'] = (attendance['paidLeaves'] ?? 0).toString();
      doc['unpaidLeaves'] = (attendance['unpaidLeaves'] ?? 0).toString();
      doc['leaves'] = (attendance['leaves'] ?? 0).toString();
      doc['totalWorkDays'] = workingDays.toString();
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'PayrollAttendanceFetch($email)');
    }
  }

  bool _matchesFilter(Map<String, dynamic> doc, String filter) {
    return switch (filter) {
      'All' => true,
      'Pay' => doc['isPaid'] != true,
      'Paid' => doc['isPaid'] == true,
      'Today' => PayrollService.wasPaidOn(doc, DateTime.now()),
      _ => (doc['position'] ?? '').toString().toLowerCase().contains(filter.toLowerCase()),
    };
  }

  bool _requirePayableSalary(Map<String, dynamic> worker) {
    final salary = PayrollService.extractSalary(PayrollService.currentSalaryDisplay(worker, companyCurrency: _companyCurrency));
    if (salary > 0) return true;
    FlashySnackBar.show(context, message: 'please_enter_salary'.tr(), isError: true);
    return false;
  }

  String _payPeriodLabelFor(DateTime month) {
    final isCurrent = month.year == _payrollMonth.year && month.month == _payrollMonth.month;
    final start = isCurrent ? _payPeriodStart : PayrollService.payPeriodStart(month);
    final end = isCurrent ? _payPeriodEnd : PayrollService.payPeriodEnd(month);
    return PayrollService.formatPayPeriodRange(start, end, locale: context.locale.toString());
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
    if (_isRunningPayroll || _payableWorkersForPeriod(payrollMonth).isEmpty) return;
    setState(() => _isRunningPayroll = true);
    try {
      final summary = await PayrollRunner().payAll(
        context,
        payrollMonth: payrollMonth,
        payPeriodStart: _payPeriodStart,
        payPeriodEnd: _payPeriodEnd,
      );
      if (summary != null && mounted) {
        FlashySnackBar.show(context, message: 'payroll_run_complete'.tr(namedArgs: {'count': '${summary.successCount}'}));
      }
    } catch (error) {
      if (mounted) {
        final msg = error is StateError && error.message.isNotEmpty
            ? error.message
            : error.toString().isNotEmpty ? error.toString() : 'failed_to_save_record'.tr();
        FlashySnackBar.show(context, message: msg, isError: true);
      }
    } finally {
      if (mounted) setState(() => _isRunningPayroll = false);
    }
  }

  Widget _desktopDialogButton({required String label, required VoidCallback onTap, bool primary = false}) {
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
          child: Text(label,
              style: TextStyle(
                color: primary ? const Color(0xFFFFFFFF) : const Color(0xFF0F172A),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              )),
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
            boxShadow: [BoxShadow(color: const Color(0xFF000000).withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 10))],
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
                        onTap: () => Navigator.of(dialogContext).pop(),
                        child: const SizedBox(width: 32, height: 32, child: Icon(Icons.close_rounded, color: Color(0xFFFFFFFF), size: 21)),
                      ),
                    ),
                    Expanded(
                      child: Text(title, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 17, fontWeight: FontWeight.w700, fontFamily: 'SF Pro Display')),
                    ),
                    const SizedBox(width: 32),
                  ],
                ),
              ),
              Padding(padding: const EdgeInsets.all(24), child: content),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 1))),
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

  Widget _buildBlurDialog({required BuildContext dialogContext, required Widget Function(CurvedAnimation) builder, required Animation<double> animation}) {
    final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
    return Stack(
      fit: StackFit.expand,
      children: [
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10 * animation.value, sigmaY: 10 * animation.value),
          child: Container(color: const Color(0xFF0F172A).withValues(alpha: 0.35 * animation.value)),
        ),
        FadeTransition(opacity: animation, child: ScaleTransition(scale: curve, child: builder(curve))),
      ],
    );
  }

  Future<void> _maybeShowPayrollReminder({bool force = false}) async {
    if (!widget.isActive || _isLoading || !_workersLoaded || !_payrollLoaded || _reminderDialogOpen) return;

    // If the user explicitly asked for the reminder (force) while an automatic
    // check is still in flight, let the pending force check do the showing —
    // otherwise the automatic check would open the dialog and the force re-check
    // would open it a second time right after.
    if (!force && _reminderCheckForcePending) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final offset = today.difference(_payPeriodEnd).inDays;

    // Pre-payday window: show reminders from 3 days before until payday.
    // Post-payday overdue window: show for up to 7 days after payday.
    if (offset < -3 || offset > 7) return;

    final window = PayrollReminderWindow(payrollMonth: _payrollMonth, dueDate: _payPeriodEnd, dayOffset: offset);

    // Honour "Remind me later" / "Ignore" only for AUTOMATIC checks: a
    // snoozed or ignored pay cycle must not keep re-prompting on its own
    // (e.g. right after Pay All finished). An explicit user action (force —
    // clicking Payroll in the sidebar) always re-shows the reminder when the
    // payday is today or within the overdue window, exactly as the user asked.
    if (!force) {
      if (await PreferencesService.isPayrollReminderIgnored(window.suppressionKey)) return;
      if (await PreferencesService.isPayrollReminderSnoozed(window.suppressionKey, now: now)) return;
    }

    final payableWorkers = _payableWorkersForPeriod(window.payrollMonth);
    if (payableWorkers.isEmpty) return;
    if (!mounted || !widget.isActive) return;

    // Show the reminder at most once per day per pay cycle for AUTOMATIC
    // checks. Both the payroll screen's own scheduling and the home screen's
    // global trigger funnel here; without this guard a queued re-check or the
    // global trigger would open the dialog a second time immediately after the
    // first one was dismissed. An explicit user action (force, e.g. clicking
    // Payroll in the sidebar) always re-evaluates and re-shows when due.
    if (!force && _lastShownReminderKey == window.suppressionKey && _lastShownReminderDay == today) return;
    _lastShownReminderKey = window.suppressionKey;
    _lastShownReminderDay = today;

    _reminderDialogOpen = true;

    final status = offset < -1
        ? 'payroll_due_in_days'.tr(namedArgs: {'days': '${offset.abs()}'})
        : offset == -1 ? 'payroll_due_tomorrow'.tr()
        : offset == 0 ? 'payroll_due_today'.tr()
        : offset == 1 ? 'payroll_overdue_one_day'.tr()
        : 'payroll_overdue_days'.tr(namedArgs: {'days': '$offset'});

    final dueDate = AppDateUtils.fromValueLocalized(window.dueDate, locale: context.locale.toString());

    final action = await showGeneralDialog<_PayrollReminderAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'PayrollReminderDialog',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, _, _) => const SizedBox(),
      transitionBuilder: (dialogContext, animation, _, _) => _buildBlurDialog(
        dialogContext: dialogContext,
        animation: animation,
        builder: (_) => _desktopDialogShell(
          dialogContext: dialogContext,
          title: offset > 0 ? 'overdue_payroll'.tr() : 'pay_due_reminder'.tr(),
          width: 560,
          content: _buildReminderContent(offset, status, dueDate, payableWorkers),
          actions: [
            _desktopDialogButton(label: 'remind_me_later'.tr(), onTap: () => Navigator.pop(dialogContext, _PayrollReminderAction.remindLater)),
            if (offset > 0) _desktopDialogButton(label: 'ignore'.tr(), onTap: () => Navigator.pop(dialogContext, _PayrollReminderAction.ignore)),
            _desktopDialogButton(label: 'pay'.tr(), primary: true, onTap: () => Navigator.pop(dialogContext, _PayrollReminderAction.viewPayable)),
          ],
        ),
      ),
    );

    _reminderDialogOpen = false;

    switch (action) {
      case _PayrollReminderAction.remindLater:
        await PreferencesService.snoozePayrollReminder(window.suppressionKey, now: now);
        if (mounted) setState(() => _selectedFilter = 'All');
      case _PayrollReminderAction.ignore:
        if (await _confirmAndAdvanceOverdueCycle(window)) {
          await PreferencesService.ignorePayrollReminder(window.suppressionKey);
        }
        if (mounted) setState(() => _selectedFilter = 'All');
      case _PayrollReminderAction.viewPayable:
        if (mounted) {
          setState(() { _payrollMonth = window.payrollMonth; _selectedFilter = 'Pay'; _combinePayroll(); });
          _scheduleAttendanceFetch();
          await _handlePayAllForMonth(window.payrollMonth);
        }
      case null:
        if (mounted) setState(() => _selectedFilter = 'All');
    }
  }

  Widget _buildReminderContent(int offset, String status, String dueDate, List<Map<String, dynamic>> payableWorkers) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: offset > 0 ? const Color(0xFFFEF2F2) : const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: offset > 0 ? const Color(0xFFFECACA) : const Color(0xFFBFDBFE)),
          ),
          child: Row(
            children: [
              Icon(Icons.notifications_active_rounded, color: offset > 0 ? const Color(0xFFEF4444) : const Color(0xFF004FDE), size: 22),
              const SizedBox(width: 12),
              Expanded(child: Text(status,
                  style: TextStyle(color: offset > 0 ? const Color(0xFFDC2626) : const Color(0xFF004FDE), fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'SF Pro Display'))),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'payroll_due_message'.tr(namedArgs: {'count': '${payableWorkers.length}', 'date': dueDate}),
          style: const TextStyle(color: Color(0xFF334155), fontSize: 14, height: 1.4, fontFamily: 'SF Pro Display'),
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
              final imageUrl = (worker['profileImage'] ?? worker['profilePic'] ?? worker['imageUrl'])?.toString();

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    WorkerAvatar(imageUrl: imageUrl, name: name.isEmpty ? 'Worker' : name, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name.isEmpty ? 'Worker' : name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'SF Pro Display')),
                          if (position.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(LocalizationHelper.localizePosition(position), maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontFamily: 'SF Pro Display')),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(20)),
                      child: Text('payable'.tr(), style: const TextStyle(color: Color(0xFF004FDE), fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'SF Pro Display')),
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

  Future<bool> _confirmAndAdvanceOverdueCycle(PayrollReminderWindow reminderWindow) async {
    if (!mounted || _salaryPayDay == null) return false;

    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'ConfirmPayrollOverdueIgnore',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => const SizedBox(),
      transitionBuilder: (dialogContext, animation, _, _) => _buildBlurDialog(
        dialogContext: dialogContext,
        animation: animation,
        builder: (_) => _desktopDialogShell(
          dialogContext: dialogContext,
          title: 'overdue_payroll'.tr(),
          width: 500,
          content: const Text(
            'The current workers will remain payable. The payroll cycle will move to the next pay period. Do you want to continue?',
            style: TextStyle(color: Color(0xFF334155), fontSize: 14, height: 1.45, fontFamily: 'SF Pro Display'),
          ),
          actions: [
            _desktopDialogButton(label: 'cancel'.tr(), onTap: () => Navigator.pop(dialogContext, false)),
            _desktopDialogButton(label: 'ignore'.tr(), primary: true, onTap: () => Navigator.pop(dialogContext, true)),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return false;

    final next = PayrollService.nextPayDayPeriod(PayrollPeriod(start: _payPeriodStart, end: _payPeriodEnd), _salaryPayDay!);
    await _firestore.updateUserProfile({
      'payrollCycleStart': next.start.toIso8601String(),
      'payrollCycleEnd': next.end.toIso8601String(),
      'payrollCycleAdvancedAt': DateTime.now().toIso8601String(),
      'payrollCyclePreviousDueDate': reminderWindow.dueDate.toIso8601String(),
    });
    await PreferencesService.ignorePayrollReminder(reminderWindow.suppressionKey);

    if (!mounted) return true;
    setState(() {
      _payPeriodStart = next.start;
      _payPeriodEnd = next.end;
      _payrollMonth = DateTime(next.end.year, next.end.month, 1);
      _selectedFilter = 'All';
      _combinePayroll();
    });
    _scheduleAttendanceFetch();
    return true;
  }

  Future<void> _showSetPayDayDialog() async {
    if (_isGuest) { showGuestRestrictionDialog(context); return; }

    var selectedDay = _salaryPayDay ?? DateTime.now().day;
    final day = await showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'SetPayDayDialog',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, _, _) => const SizedBox(),
      transitionBuilder: (dialogContext, animation, _, _) => _buildBlurDialog(
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
                Text('salary_day_help'.tr(), style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.35, fontFamily: 'SF Pro Display')),
                const SizedBox(height: 18),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.2),
                  itemCount: 28,
                  itemBuilder: (context, index) {
                    final value = index + 1;
                    final selected = value == selectedDay;
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => setDialogState(() => selectedDay = value),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFF004FDE) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: selected ? const Color(0xFF004FDE) : const Color(0xFFE5E7EB)),
                          ),
                          child: Text('$value',
                              style: TextStyle(
                                color: selected ? const Color(0xFFFFFFFF) : const Color(0xFF0F172A),
                                fontSize: 14,
                                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                fontFamily: 'SF Pro Display',
                              )),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            actions: [
              _desktopDialogButton(label: 'cancel'.tr(), onTap: () => Navigator.pop(dialogContext)),
              _desktopDialogButton(label: 'Clear Pay Day', onTap: () => Navigator.pop(dialogContext, 0)),
              _desktopDialogButton(label: 'save'.tr(), primary: true, onTap: () => Navigator.pop(dialogContext, selectedDay)),
            ],
          ),
        ),
      ),
    );

    if (day == null || !mounted) return;
if (day == 0) {
  try {
    await _firestore.updateUserProfile({
      'salaryPayDay': null,
      'payrollCycleStart': null,
      'payrollCycleEnd': null,
    });

    if (!mounted) return;

    final now = DateTime.now();

    setState(() {
      _salaryPayDay = null;
      _payPeriodStart = PayrollService.payPeriodStart(now);
      _payPeriodEnd = PayrollService.payPeriodEnd(now);
      _payrollMonth = DateTime(now.year, now.month, 1);
      _selectedFilter = 'All';
      _combinePayroll();
    });

    FlashySnackBar.show(
      context,
      message: 'Pay Day cleared successfully.',
    );
  } catch (error, stackTrace) {
    ErrorReporter.report(
      error,
      stackTrace,
      context: 'ClearSalaryPayDay',
    );

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
    try {
      final hasPaidInCurrentCycle = _payrollDocs.any(
        (rec) => rec['isPaid'] == true || (rec['status'] ?? '').toString().toLowerCase() == 'paid',
      );

      PayrollPeriod period;
      if (hasPaidInCurrentCycle) {
        period = PayrollPeriod(start: _payPeriodStart, end: _payPeriodEnd);
        FlashySnackBar.show(context, message: 'Salary Day updated! It will take effect starting from the next cycle.');
      } else if (day == _salaryPayDay) {
        period = PayrollPeriod(start: _payPeriodStart, end: _payPeriodEnd);
        FlashySnackBar.show(context, message: 'salary_day_saved'.tr());
      } else {
        // Recompute the cycle around today with the NEW salary day, using the
        // same central resolver (it never drifts backwards or forward).
        period = _resolveCurrentPayrollPeriod(payDay: day, advanceIfFullyPaid: false);
        if (!mounted) return;
        FlashySnackBar.show(context, message: 'salary_day_saved'.tr());
      }

      await _firestore.updateUserProfile({
        'salaryPayDay': day,
        'payrollCycleStart': period.start.toIso8601String(),
        'payrollCycleEnd': period.end.toIso8601String(),
      });

      if (!mounted) return;
      setState(() {
        _salaryPayDay = day;
        _payPeriodStart = period.start;
        _payPeriodEnd = period.end;
        _payrollMonth = DateTime(period.end.year, period.end.month, 1);
      });
      _schedulePayrollReminderCheck();
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'SaveSalaryPayDay');
      if (mounted) FlashySnackBar.show(context, message: 'failed_to_save_record'.tr(), isError: true);
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
        readOnly: _isViewOnly,
        onNotificationTap: widget.onNotificationTap,
        onProfileTap: widget.onProfileTap,
        onBack: () => setState(() { _isAddingPayroll = false; _workerForPayroll = null; _isViewOnly = false; }),
      );
    }

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
                  _buildSearchBar(),
                  const SizedBox(height: 10),
                  const SizedBox(height: 10),
                  _buildFilterTabs(),
                  const SizedBox(height: 20),
                  _buildListHeader(),
                  const SizedBox(height: 20),
                  _isLoading
                      ? const Padding(padding: EdgeInsets.symmetric(vertical: 80), child: Center(child: CircularProgressIndicator()))
                      : _filteredEmployees.isEmpty ? _buildEmptyState() : _buildTable(),
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
              Text('workforce'.tr(), style: const TextStyle(color: Color(0xFF000000), fontSize: 28, fontWeight: FontWeight.w800, fontFamily: 'SF Pro Display')),
              const SizedBox(height: 2),
            ],
          ),
          const Spacer(),
          NotificationBell(onTap: widget.onNotificationTap),
          const SizedBox(width: 20),
          MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: widget.onProfileTap, child: const UserAvatar())),
        ],
      ),
    );
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
          SvgPicture.asset('assets/search icon.svg', width: 24, height: 24, colorFilter: const ColorFilter.mode(Color(0xFFBDBDBD), BlendMode.srcIn)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'search_workers_name_position'.tr(),
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontFamily: 'SF Pro Display'),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () { _searchController.clear(); setState(() => _searchQuery = ''); },
                child: Padding(padding: const EdgeInsets.only(left: 8), child: Icon(Icons.close, size: 18, color: Colors.grey[400])),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildListHeader() {
    final hasCurrentPayable = _currentPayablePayrollWorkers.isNotEmpty;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('pay_roll_list'.tr(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF000000), fontFamily: 'SF Pro Display')),
              const SizedBox(height: 5),
              Text(
                'current_pay_period_label'.tr(namedArgs: {'period': _payPeriodLabelFor(_payrollMonth)}),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Color(0xFF667085), fontFamily: 'SF Pro Display'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: ElevatedButton.icon(
            onPressed: _showSetPayDayDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0247C4), foregroundColor: const Color(0xFFFFFFFF),
              minimumSize: const Size(32, 50), padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), elevation: 0,
            ),
            icon: const Icon(Icons.calendar_month_rounded, size: 21, color: Color(0xFFFFFFFF)),
            label: Text(_payDayButtonLabel(), style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 16, fontWeight: FontWeight.w500, fontFamily: 'SF Pro Display')),
          ),
        ),
        if (_isCurrentCycleDue)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: _isRunningPayroll || !hasCurrentPayable
                  ? null
                  : () {
                      if (_isGuest) { showGuestRestrictionDialog(context); return; }
                      _handlePayAll();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF27AE60),
                disabledBackgroundColor: const Color(0xFF27AE60).withValues(alpha: 0.4),
                foregroundColor: const Color(0xFFFFFFFF),
                disabledForegroundColor: const Color(0xFFFFFFFF).withValues(alpha: 0.7),
                minimumSize: const Size(32, 50), padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), elevation: 0,
              ),
              icon: _isRunningPayroll
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFFFFF)))
                  : SvgPicture.asset('assets/payroll_icon.svg', width: 22, height: 22, colorFilter: const ColorFilter.mode(Color(0xFFFFFFFF), BlendMode.srcIn)),
              label: Text('pay_all'.tr(), style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 16, fontWeight: FontWeight.w500, fontFamily: 'SF Pro Display')),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: Colors.grey.shade200, width: 1)),
      color: const Color(0xFFFFFFFF),
      elevation: 4,
      itemBuilder: (context) {
        final filters = [
          {'value': 'All', 'label': 'all_filter'.tr()},
          {'value': 'Pay', 'label': 'payable'.tr()},
          {'value': 'Paid', 'label': 'paid'.tr()},
        ];
        return filters.map((f) {
          final currentVal = _selectedFilter == 'Pay' || _selectedFilter == 'Paid' ? _selectedFilter : 'All';
          final selected = currentVal == f['value'];
          return PopupMenuItem<String>(
            value: f['value'],
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? const Color(0xFF0247C4) : Colors.grey.shade300, width: 2),
                    color: selected ? const Color(0xFF0247C4) : Colors.transparent,
                  ),
                  child: selected ? const Icon(Icons.check, size: 12, color: Color(0xFFFFFFFF)) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(f['label']!,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        color: selected ? const Color(0xFF0247C4) : const Color(0xFF000000),
                        fontFamily: 'SF Pro Display',
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        height: 43,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: const Color(0xFF0247C4), borderRadius: BorderRadius.circular(6)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/filter.png', width: 22, height: 22, color: const Color(0xFFFFFFFF)),
            const SizedBox(width: 8),
            Text(
              _selectedFilter == 'Pay' ? 'payable'.tr() : _selectedFilter == 'Paid' ? 'paid'.tr() : 'all_filter'.tr(),
              style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 16, fontWeight: FontWeight.w500, fontFamily: 'SF Pro Display'),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, color: Color(0xFFFFFFFF), size: 22),
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
      if (pos.isNotEmpty) positionNormalizer.putIfAbsent(pos.toLowerCase(), () => pos);
    }

    final sortedPositions = positionNormalizer.values.toList()..sort();
    final positionsToShow = <String>[...sortedPositions];
    for (final position in defaultPositions) {
      final alreadyIncluded = positionsToShow.any(
        (item) => item.toLowerCase().contains(position.toLowerCase()) || position.toLowerCase().contains(item.toLowerCase()),
      );
      if (!alreadyIncluded) positionsToShow.add(position);
    }

    final filters = <Map<String, String>>[
      {'key': 'All', 'label': 'all_filter'.tr()},
      ...positionsToShow.map((p) => {'key': p, 'label': LocalizationHelper.localizePosition(p)}),
    ];

    return Container(
      width: double.infinity,
      height: 46,
      decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(6)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: filters.map((f) => _buildFilterTab(f['key']!, f['label']!)).toList(),
        ),
      ),
    );
  }

  Widget _buildFilterTab(String filterKey, String displayLabel) {
    final isSelected = _selectedFilter == filterKey;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = filterKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0D4CC6) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(displayLabel, maxLines: 1, softWrap: false,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 14,
              fontFamily: 'SF Pro Display',
            )),
      ),
    );
  }

  Widget _buildEmptyState() {
    final dynamicHeight = (MediaQuery.of(context).size.height - 329).clamp(440.0, 1200.0);
    return Container(
      width: double.infinity,
      height: dynamicHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(6)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset('assets/placeholder_workers.svg', width: 120, height: 100, colorFilter: const ColorFilter.mode(Color(0xFFCBCBCB), BlendMode.srcIn)),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty ? 'no_search_results'.tr() : 'no_payroll_records'.tr(),
            style: const TextStyle(color: Color(0xFF0247C4), fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'SF Pro Display'),
            overflow: TextOverflow.ellipsis, maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    final tableHeight = (MediaQuery.of(context).size.height - 329).clamp(440.0, 1200.0);

    return Container(
      height: tableHeight,
      decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(6)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 24, 40, 12),
            child: Row(
              children: [
                Expanded(flex: 3, child: Padding(padding: const EdgeInsets.only(right: 24), child: Text('worker_name_header'.tr(), style: _headerStyle()))),
                Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(right: 24), child: Text('position'.tr(), style: _headerStyle()))),
                Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(right: 24), child: Text('contact_no'.tr(), style: _headerStyle()))),
                Expanded(flex: 2, child: Text('status_header'.tr(), style: _headerStyle())),
                const SizedBox(width: 24, child: Center(child: Text(''))),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFF7F8FC)),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _filteredEmployees.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, index) => _buildEmployeeRow(_filteredEmployees[index]),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _headerStyle() => const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black, fontFamily: 'SF Pro Display');

  Widget _buildEmployeeRow(Map<String, dynamic> doc) {
    final isPaid = doc['isPaid'] == true;
    final hasData = (doc['totalWorkDays'] ?? '').toString().isNotEmpty;
    final contactNo = (doc['phone'] ?? '').toString().trim().isEmpty
        ? (doc['contact'] ?? '').toString()
        : (doc['phone'] ?? '').toString();

    void onRowTap() {
      if (_isGuest) { showGuestRestrictionDialog(context); return; }
      if (isPaid && hasData) {
        _showPayrollDataDialog(context, doc, 0);
      } else {
        if (!_requirePayableSalary(doc)) return;
        setState(() { _isAddingPayroll = true; _workerForPayroll = doc; });
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFFF6F8FA), borderRadius: BorderRadius.circular(6)),
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
                      WorkerAvatar(imageUrl: doc['profileImage']?.toString(), name: (doc['name'] ?? '').toString(), size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text((doc['name'] ?? '').toString(),
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'SF Pro Display'), maxLines: 2),
                            const SizedBox(height: 4),
                            Text((doc['email'] ?? '').toString(),
                                style: const TextStyle(fontSize: 14, color: Colors.black, fontFamily: 'SF Pro Display')),
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
              child: Text(LocalizationHelper.localizePosition((doc['position'] ?? '').toString()),
                  style: const TextStyle(fontSize: 15, color: Colors.black, fontFamily: 'SF Pro Display'), maxLines: 2),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Text(contactNo, style: const TextStyle(fontSize: 15, color: Colors.black, fontFamily: 'SF Pro Display'), maxLines: 1),
            ),
          ),
          Expanded(
            flex: 2,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onRowTap,
                child: Text(
                  isPaid ? 'paid'.tr() : 'payable'.tr(),
                  style: TextStyle(
                    color: isPaid ? const Color(0xFF27AE60) : const Color(0xFFE74C3C),
                    fontSize: 16, fontWeight: FontWeight.w500, fontFamily: 'SF Pro Display',
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

  Future<void> _downloadPayrollInvoice(Map<String, dynamic> data) async {
    if (!mounted) return;
    FlashySnackBar.show(context, message: 'generating_invoices'.tr());
    try {
      final counts = PayrollService.attendanceCounts(data);
      final totalWorkDays = (data['totalWorkDays'] ?? '0').toString();
      final absents = (counts['absents'] ?? 0).toString();
      final paidLeaves = (counts['paidLeaves'] ?? 0).toString();
      final unpaidLeaves = (counts['unpaidLeaves'] ?? 0).toString();
      final totalLeaves = (counts['leaves'] ?? 0).toString();
      final deductionsAreTotals = data['deductionsAreTotals'] == true;
      final rawAbsentDeduction = (data['absentDeduction'] ?? '0').toString();
      final rawLeaveDeduction = (data['leaveDeduction'] ?? '0').toString();
      final overtime = (data['overtimeAmount'] ?? '0').toString();
      final salary = PayrollService.currentSalaryDisplay(data, companyCurrency: _companyCurrency);

      final calculation = PayrollService.calculatePayroll(
        salary: salary, totalWorkDays: totalWorkDays, absents: absents, leaves: unpaidLeaves,
        overtimeAmount: overtime,
        absentDeductionPerDay: deductionsAreTotals ? '' : rawAbsentDeduction,
        leaveDeductionPerDay: deductionsAreTotals ? '' : rawLeaveDeduction,
        salaryType: (data['salaryType'] ?? 'Monthly').toString(),
      );

      final currency = PayrollService.getCurrencyPrefix(salary);
      final prefix = _companyCurrency.isNotEmpty ? '${PayrollService.getCurrencySymbol(_companyCurrency)} ' : (currency.isEmpty ? '' : '$currency ');
      final grossSalary = PayrollService.extractSalary(calculation['formattedGross']);
      final absentDeductionTotal = deductionsAreTotals ? PayrollService.extractSalary(rawAbsentDeduction) : (calculation['absentDeduction'] as double? ?? 0.0);
      final leaveDeductionTotal = deductionsAreTotals ? PayrollService.extractSalary(rawLeaveDeduction) : (calculation['leaveDeduction'] as double? ?? 0.0);
      final overtimeValue = PayrollService.extractSalary(overtime);
      final totalDeductions = absentDeductionTotal + leaveDeductionTotal;
      final savedNetSalary = data['netSalaryAmount'];
      final netSalary = savedNetSalary is num
          ? savedNetSalary.toDouble()
          : (grossSalary + overtimeValue - totalDeductions).clamp(0.0, double.infinity).toDouble();

      final savedPeriodStart = AppDateUtils.dateFromValue(data['payPeriodStart']);
      final savedPeriodEnd = AppDateUtils.dateFromValue(data['payPeriodEnd']);
      final payPeriod = savedPeriodStart != null && savedPeriodEnd != null
          ? PayrollService.formatPayPeriodRange(savedPeriodStart, savedPeriodEnd, locale: context.locale.toString())
          : _payPeriodLabelFor(_payrollMonth);

      Map<String, dynamic> companyProfile = const {};
      try { companyProfile = await _firestore.getUserProfile() ?? const {}; } catch (_) {}

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
        dailyRate: (calculation['formattedDailyRate'] ?? '${prefix}0.00').toString(),
        grossPay: '$prefix${PayrollService.formatFullNumber(grossSalary)}',
        overtimePay: (calculation['formattedOvertime'] ?? '${prefix}0.00').toString(),
        absentDeduction: '$prefix${PayrollService.formatFullNumber(absentDeductionTotal)}',
        leaveDeduction: '$prefix${PayrollService.formatFullNumber(leaveDeductionTotal)}',
        totalDeductions: '$prefix${PayrollService.formatFullNumber(totalDeductions)}',
        netSalary: '$prefix${PayrollService.formatFullNumber(netSalary)}',
        currency: _companyCurrency,
        companyName: (companyProfile['businessName'] ?? companyProfile['companyName'] ?? 'HRMS').toString(),
        companyAddress: (companyProfile['address'] ?? '').toString(),
        companyEmail: (companyProfile['email'] ?? '').toString(),
        companyPhone: (companyProfile['contact1'] ?? companyProfile['phone'] ?? '').toString(),
        companyId: (companyProfile['companyId'] ?? companyProfile['businessId'] ?? '').toString(),
        companyStampImageUrl: (companyProfile['companyStampUrl'] ?? '').toString(),
        companyLogoUrl: (companyProfile['profilePic'] ?? '').toString(),
        invoiceNo: (data['invoiceNo'] ?? data['invoiceNumber'] ?? '').toString(),
        workerId: (data['workerId'] ?? data['id'] ?? '').toString(),
      );

      final safeName = (data['name'] ?? 'worker').toString().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final safePeriod = payPeriod.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final fileName = 'payroll_${safeName}_$safePeriod.pdf';
      final saved = await InvoiceService.shareInvoice(bytes, fileName);
      if (saved && mounted) {
        FlashySnackBar.show(context, message: 'file_saved_and_opened'.tr(namedArgs: {'file': fileName}));
      }
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'PayrollPreviewInvoice');
      if (mounted) FlashySnackBar.show(context, message: 'unexpected_error'.tr(), isError: true);
    }
  }

  void _showPayrollDataDialog(BuildContext context, Map<String, dynamic> data, int index) async {
    final name = (data['name'] ?? '').toString();
    final email = (data['email'] ?? '').toString();
    final totalWorkDays = (data['totalWorkDays'] ?? '0').toString();
    final absents = (data['absents'] ?? '0').toString();
    final attendanceCounts = PayrollService.attendanceCounts(data);
    final paidLeaves = (attendanceCounts['paidLeaves'] ?? 0).toString();
    final deductionLeaveDays = (attendanceCounts['unpaidLeaves'] ?? 0).toString();
    final rawAbsentDeduction = (data['absentDeduction'] ?? '0').toString();
    final rawLeaveDeduction = (data['leaveDeduction'] ?? '0').toString();
    final rawOvertimeAmount = (data['overtimeAmount'] ?? '0').toString();
    final deductionsAreTotals = data['deductionsAreTotals'] == true;
    final salaryDisplay = PayrollService.currentSalaryDisplay(data, companyCurrency: _companyCurrency);
    final currencyPrefix = PayrollService.getCurrencyPrefix(salaryDisplay);
    final otPrefix = currencyPrefix.isEmpty ? '' : '$currencyPrefix ';
    final overtimeVal = PayrollService.extractSalary(rawOvertimeAmount);
    final overtimeAmount = '$otPrefix${PayrollService.formatFullNumber(overtimeVal)}';
    final salary = AmountText.formatFull(salaryDisplay, locale: context.locale.toString());
    final hasLeaveDeduction = rawLeaveDeduction.trim().isNotEmpty;
    final totalDaysValue = PayrollService.parseIntSafe(totalWorkDays);
    final effectiveWorkedDays = totalDaysValue - PayrollService.parseIntSafe(absents) - (hasLeaveDeduction ? PayrollService.parseIntSafe(deductionLeaveDays) : 0);

    final baseCalc = totalDaysValue > 0
        ? PayrollService.calculatePayroll(
            salary: salaryDisplay, totalWorkDays: totalWorkDays,
            daysWorked: effectiveWorkedDays > 0 ? effectiveWorkedDays.toString() : '0',
            absents: absents, leaves: deductionLeaveDays, overtimeAmount: rawOvertimeAmount,
            absentDeductionPerDay: deductionsAreTotals ? '' : rawAbsentDeduction,
            leaveDeductionPerDay: deductionsAreTotals ? '' : rawLeaveDeduction,
            salaryType: (data['salaryType'] ?? 'Monthly').toString(),
          )
        : const <String, dynamic>{};

    if (baseCalc.isNotEmpty && !deductionsAreTotals && PayrollService.extractSalary(rawAbsentDeduction) == 0) {
      final autoCalc = baseCalc['absentDeduction'] as double? ?? 0;
      if (autoCalc > 0) {
        baseCalc['absentDeduction'] = 0.0;
        baseCalc['formattedAbsentDeduct'] = '0';
        baseCalc['netSalary'] = (baseCalc['netSalary'] as double? ?? 0) + autoCalc;
        baseCalc['totalDeductions'] = (baseCalc['totalDeductions'] as double? ?? 0) - autoCalc;
        final cur = PayrollService.getCurrencyPrefix(salaryDisplay);
        final pfx = cur.isNotEmpty ? '$cur ' : '';
        final netVal = baseCalc['netSalary'] as double? ?? 0;
        baseCalc['formattedNet'] = '$pfx${PayrollService.formatFullNumber(netVal)}';
        baseCalc['formattedNetSalary'] = baseCalc['formattedNet'];
      }
    }

    final previewCalc = deductionsAreTotals && baseCalc.isNotEmpty
        ? {
            ...baseCalc,
            'formattedNet': () {
              final netPayment = PayrollService.calculateNetFromTotals(
                salary: salaryDisplay, overtimeAmount: rawOvertimeAmount,
                absentDeduction: rawAbsentDeduction, leaveDeduction: rawLeaveDeduction,
                salaryType: (data['salaryType'] ?? 'Monthly').toString(),
              );
              final currency = PayrollService.getCurrencyPrefix(salaryDisplay);
              final pfx = currency.isEmpty ? '' : '$currency ';
              return '$pfx${PayrollService.formatFullNumber(netPayment)}';
            }(),
          }
        : baseCalc;

    final salaryAfterDeduction = AmountText.formatFull(
      (previewCalc['formattedNet'] ?? previewCalc['formattedNetSalary'] ?? '0').toString(),
      locale: context.locale.toString(),
    );
    final absentDeduction = AmountText.formatFull(
      (deductionsAreTotals ? rawAbsentDeduction : previewCalc['formattedAbsentDeduct'] ?? rawAbsentDeduction).toString(),
      locale: context.locale.toString(),
    );

    final paidDate = PayrollService.payrollPaymentDate(data);
    final paidDateText = paidDate == null ? '-' : DateFormat.yMMMd(context.locale.toString()).format(paidDate);
    final dialogWidth = MediaQuery.of(context).size.width < 500 ? MediaQuery.of(context).size.width * 0.9 : 480.0;

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
                boxShadow: [BoxShadow(color: const Color(0xFF000000).withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 10))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 40,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFF004FDE),
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(ctx).pop(),
                          child: const MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close, color: Color(0xFFFFFFFF), size: 22)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('payroll_data_preview'.tr(), textAlign: TextAlign.center, maxLines: 1,
                                style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'SF Pro Display')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () async {
                            final confirmed = await DeleteDialog.show(
                              context: context,
                              title: 'edit_payroll'.tr(),
                              content: 'edit_paid_payroll_confirm'.tr(),
                              confirmButtonText: 'yes',
                            );
                            if (confirmed && ctx.mounted) Navigator.of(ctx).pop('edit');
                          },
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 10, top: 10, bottom: 10, right: 4),
                              child: SvgPicture.asset('assets/edit_icon.svg', height: 20, width: 20, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        _PayrollInvoiceShareButton(onShare: () => _downloadPayrollInvoice(data)),
                      ],
                    ),
                  ),
                  _buildWorkerPreviewHeader(name: name, email: email, imageUrl: data['profileImage']?.toString()),
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFFFFF),
                      border: Border(
                        left: BorderSide(color: Color(0xFFE8E8E8), width: 1.5),
                        right: BorderSide(color: Color(0xFFE8E8E8), width: 1.5),
                        bottom: BorderSide(color: Color(0xFFE8E8E8), width: 1.5),
                      ),
                      borderRadius: BorderRadius.only(bottomLeft: Radius.circular(6), bottomRight: Radius.circular(6)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      child: Column(
                        children: [
                          Row(children: [
                            Expanded(child: _buildMetricCard(icon: _buildAbsentsIcon(), title: 'absents_label'.tr(), value: absents)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildMetricCard(icon: _buildLeavesIcon(), title: 'leaves_label'.tr(), value: paidLeaves)),
                          ]),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: _buildMetricCard(icon: _buildAbsentsIcon(), title: 'absent_deduction'.tr(), value: absentDeduction.isEmpty ? '0' : absentDeduction)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildMetricCard(icon: const Icon(Icons.event_available_rounded, color: Color(0xFF004FDE), size: 20), title: 'paid_on'.tr(), value: paidDateText)),
                          ]),
                          const SizedBox(height: 12),
                          _buildPayrollPreviewBottom(absentDeduction, overtimeAmount, salary, salaryAfterDeduction),
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
      setState(() { _isAddingPayroll = true; _workerForPayroll = data; });
    } else if (result == 'view' && mounted) {
      setState(() { _isAddingPayroll = true; _workerForPayroll = data; _isViewOnly = true; });
    }
  }

  Widget _buildPayrollPreviewBottom(String absentDeduction, String overtimeAmount, String salary, String salaryAfterDeduction) {
    double parseAmount(String val) => double.tryParse(val.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    final hasDeduction = parseAmount(absentDeduction) > 0;
    final hasOvertime = parseAmount(overtimeAmount) > 0;

    final baseRow = Row(children: [
      Expanded(child: _buildMetricCard(icon: _buildOvertimeDaysIcon(), title: 'overtime_amount'.tr(), value: overtimeAmount)),
      const SizedBox(width: 12),
      Expanded(child: _buildMetricCard(icon: _buildSalaryIcon(), title: 'salary'.tr(), value: salary)),
    ]);

    if (!hasDeduction && !hasOvertime) return baseRow;

    return Column(children: [
      baseRow,
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _buildMetricCard(
          icon: const Icon(Icons.account_balance_wallet, color: Color(0xFF004FDE), size: 20),
          title: 'salary_after_deduction'.tr(),
          value: salaryAfterDeduction,
        )),
        const SizedBox(width: 12),
        const Expanded(child: SizedBox()),
      ]),
    ]);
  }

  Widget _buildWorkerPreviewHeader({required String name, required String email, String? imageUrl}) {
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
          WorkerAvatar(imageUrl: imageUrl, name: name, size: 60, border: Border.all(color: const Color(0xFF0A51D0), width: 2)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(name, style: const TextStyle(color: Color(0xFF333333), fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'SF Pro Display'),
                    overflow: TextOverflow.ellipsis, maxLines: 1),
                const SizedBox(height: 4),
                Row(children: [
                  SvgPicture.asset('assets/email.svg', height: 12, width: 12, colorFilter: const ColorFilter.mode(Color(0xFF666666), BlendMode.srcIn)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(email, style: const TextStyle(color: Color(0xFF666666), fontSize: 13, fontWeight: FontWeight.w400, fontFamily: 'SF Pro Display'),
                        overflow: TextOverflow.ellipsis, maxLines: 1),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({required Widget icon, required String title, required String value}) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE8E8E8), width: 1.2)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: const Color(0xFFE5EEFC), borderRadius: BorderRadius.circular(6)),
            child: Center(child: icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, color: Colors.black, fontWeight: FontWeight.w600, fontFamily: 'SF Pro Display'), overflow: TextOverflow.ellipsis, maxLines: 1),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14, color: Color(0xFF000000), fontWeight: FontWeight.bold, fontFamily: 'SF Pro Display'), overflow: TextOverflow.ellipsis, maxLines: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbsentsIcon() => SvgPicture.asset('assets/absent.svg', width: 20, height: 20,
      colorMapper: const SvgFillColorMapper(source: Color(0xFFFF0004), replacement: Color(0xFF004FDE)));

  Widget _buildLeavesIcon() => SvgPicture.asset('assets/leave.svg', width: 20, height: 20,
      colorMapper: const SvgFillColorMapper(source: Color(0xFFFF7B00), replacement: Color(0xFF004FDE)));

  Widget _buildSalaryIcon() => Image.asset('assets/salary.png', width: 20, height: 20, fit: BoxFit.contain, color: const Color(0xFF004FDE), colorBlendMode: BlendMode.srcIn);

  Widget _buildOvertimeDaysIcon() => Image.asset('assets/overtime.png', width: 20, height: 20, fit: BoxFit.contain, color: const Color(0xFF004FDE), colorBlendMode: BlendMode.srcIn);
}

class _PayrollInvoiceShareButton extends StatefulWidget {
  final Future<void> Function() onShare;

  const _PayrollInvoiceShareButton({required this.onShare});

  @override
  State<_PayrollInvoiceShareButton> createState() => _PayrollInvoiceShareButtonState();
}

class _PayrollInvoiceShareButtonState extends State<_PayrollInvoiceShareButton> {
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
          padding: const EdgeInsets.only(left: 4, top: 10, bottom: 10, right: 10),
          child: _isSharing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
              : SvgPicture.asset('assets/share1.svg', height: 22, width: 22, colorFilter: const ColorFilter.mode(Color(0xFFFFFFFF), BlendMode.srcIn)),
        ),
      ),
    );
  }
}