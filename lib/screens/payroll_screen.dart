import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:easy_localization/easy_localization.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/payroll_service.dart';
import '../services/preferences_service.dart';
import '../services/error_reporter.dart';
import '../utils/file_utils.dart';
import '../utils/ui_utils.dart';
import '../utils/guest_restriction.dart';
import '../utils/dialog_utils.dart';
import '../utils/date_time_utils.dart';
import '../utils/currency_utils.dart';
import '../utils/localization_helper.dart';
import '../services/invoice_service.dart';
import '../widgets/amount_text.dart';
import 'add_payroll_screen.dart';
import '../services/salary_day_scheduler.dart';
import '../widgets/notification_bell.dart';

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
  ConsumerState<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends ConsumerState<PayrollScreen> {
  late AuthService _authService;
  late FirestoreService _firestore;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'All';
  List<Map<String, dynamic>> _payrollDocs = [];
  List<Map<String, dynamic>> _workersList = [];
  List<Map<String, dynamic>> _rawPayrollDocs = [];
  List<Map<String, dynamic>>? _liveAttendanceRecords;
  bool _isLoading = true;
  String _companyCurrency = CurrencyUtils.defaultCode;
  DateTime _payrollMonth = PayrollService.currentPayrollMonth();
  int? _salaryPayDay;

  StreamSubscription? _payrollSub;
  StreamSubscription? _workersSub;
  StreamSubscription? _attendanceSub;
  StreamSubscription? _holidaysSub;
  StreamSubscription<Map<String, dynamic>?>? _profileSub;

  bool _isAddingPayroll = false;
  bool _isViewOnly = false;
  Map<String, dynamic>? _workerForPayroll;
  bool _isRunningPayroll = false;
  bool _initialized = false;
  bool _isLoadingAttendance = false;
  bool _attendanceFetchPending = false;
  bool _reminderCheckScheduled = false;
  bool _reminderHandledForActivation = false;
  bool _forceReminderForActivation = false;
  bool _reminderDialogOpen = false;
  bool _workersLoaded = false;
  bool _payrollLoaded = false;
  Timer? _attendanceDebounce;
  List<Map<String, dynamic>> _payableWorkersForPeriod(DateTime month) {
    return PayrollService.payableWorkersForPeriod(
      _workersList,
      _rawPayrollDocs,
      month: month,
      companyCurrency: _companyCurrency,
    );
  }

  List<Map<String, dynamic>> get _currentPayablePayrollWorkers =>
      _payableWorkersForPeriod(_payrollMonth);

  int? _payDayFromProfile(Map<String, dynamic>? profile) {
    final value = profile?['salaryPayDay'] ?? profile?['salary_pay_day'];
    final day = value is num ? value.toInt() : int.tryParse('$value');
    return day != null && day >= 1 && day <= 31 ? day : null;
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
              fontFamily: 'SF Pro Display',
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
                        onTap: () => Navigator.of(dialogContext).pop(),
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
                          fontFamily: 'SF Pro Display',
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
                    for (var index = 0; index < actions.length; index++) ...[
                      if (index > 0) const SizedBox(width: 10),
                      actions[index],
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

  bool _requirePayableSalary(Map<String, dynamic> worker) {
    final salary = PayrollService.extractSalary(
      PayrollService.currentSalaryDisplay(
        worker,
        companyCurrency: _companyCurrency,
      ),
    );
    if (salary > 0) return true;
    FlashySnackBar.show(
      context,
      message: 'please_enter_salary'.tr(),
      isError: true,
    );
    return false;
  }

  String _payPeriodLabelFor(DateTime month) {
    final start = PayrollService.payPeriodStart(month);
    final end = PayrollService.payPeriodEnd(month);
    return PayrollService.formatPayPeriodRange(
      start,
      end,
      locale: context.locale.toString(),
    );
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

  void _combinePayroll() {
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    _payrollDocs = PayrollService.combinePayroll(
      _workersList,
      _rawPayrollDocs,
      month: _payrollMonth,
      allowUndatedRecords: isGuest,
      companyCurrency: _companyCurrency,
    );

    final zeroAmount = '${CurrencyUtils.symbolFor(_companyCurrency)} 0';
    for (var doc in _payrollDocs) {
      if (doc['totalWorkDays'] == null ||
          doc['totalWorkDays'].toString().isEmpty) {
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
    if (_selectedFilter == 'Pay' && _currentPayablePayrollWorkers.isEmpty) {
      _selectedFilter = 'All';
    }
    _schedulePayrollReminderCheck();
  }

  void _schedulePayrollReminderCheck() {
    if (!widget.isActive ||
        _reminderCheckScheduled ||
        _reminderHandledForActivation) {
      return;
    }
    _reminderCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (mounted) await _maybeShowPayrollReminder();
      } finally {
        _reminderCheckScheduled = false;
      }
    });
  }

  Future<void> _maybeShowPayrollReminder() async {
    if (!widget.isActive ||
        _isLoading ||
        !_workersLoaded ||
        !_payrollLoaded ||
        _reminderHandledForActivation ||
        _reminderDialogOpen) {
      return;
    }

    final now = DateTime.now();
    final forceReminder = _forceReminderForActivation;
    _forceReminderForActivation = false;

    PayrollReminderWindow? window;
    if (forceReminder) {
      // A direct Payroll sidebar click always checks the current pay period.
      // If payable workers remain, show a reminder before/on pay day and an
      // overdue message after pay day, regardless of prior dismissal.
      final today = DateTime(now.year, now.month, now.day);
      final payrollMonth = PayrollService.currentPayrollMonth(
        referenceDate: today,
      );
      final dueDate = _salaryPayDay == null
          ? PayrollService.payPeriodEnd(payrollMonth)
          : PayrollService.payrollDueDate(payrollMonth, _salaryPayDay!);
      window = PayrollReminderWindow(
        payrollMonth: payrollMonth,
        dueDate: dueDate,
        dayOffset: today.difference(dueDate).inDays,
      );
    } else {
      window = PayrollService.reminderWindowForDate(
        now,
        payDay: _salaryPayDay,
        overdueDays: 0,
      );
    }
    if (window == null) {
      _reminderHandledForActivation = true;
      return;
    }
    final reminderWindow = window;
    final payableWorkers = _payableWorkersForPeriod(
      reminderWindow.payrollMonth,
    );
    if (payableWorkers.isEmpty) {
      _reminderHandledForActivation = true;
      return;
    }
    if (!forceReminder &&
        await PreferencesService.isPayrollReminderSuppressed(
          reminderWindow.suppressionKey,
          now: now,
        )) {
      _reminderHandledForActivation = true;
      return;
    }
    if (!mounted || !widget.isActive) return;

    _reminderHandledForActivation = true;
    _reminderDialogOpen = true;
    final offset = reminderWindow.dayOffset;
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
      reminderWindow.dueDate,
      locale: context.locale.toString(),
    );
    final action = await showGeneralDialog<_PayrollReminderAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'PayrollReminderDialog',
      barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.3),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, _, _) => const SizedBox(),
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
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
              child: _desktopDialogShell(
                dialogContext: dialogContext,
                title: offset > 0
                    ? 'overdue_payroll'.tr()
                    : 'pay_due_reminder'.tr(),
                width: 560,
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
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
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'payroll_due_message'.tr(
                        namedArgs: {
                          'count': '${payableWorkers.length}',
                          'date': dueDate,
                        },
                      ),
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        fontSize: 14,
                        height: 1.4,
                        fontFamily: 'SF Pro Display',
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
                          final name = (worker['name'] ?? 'Worker')
                              .toString()
                              .trim();
                          final position = (worker['position'] ?? '')
                              .toString()
                              .trim();
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
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                              ),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name.isEmpty ? 'Worker' : name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF0F172A),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                      if (position.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          LocalizationHelper.localizePosition(
                                            position,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF64748B),
                                            fontSize: 12,
                                            fontFamily: 'SF Pro Display',
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
                                      fontFamily: 'SF Pro Display',
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
                ),
                actions: [
                  _desktopDialogButton(
                    label: 'remind_me_later'.tr(),
                    onTap: () => Navigator.pop(
                      dialogContext,
                      _PayrollReminderAction.remindLater,
                    ),
                  ),
                  _desktopDialogButton(
                    label: 'ignore'.tr(),
                    onTap: () => Navigator.pop(
                      dialogContext,
                      _PayrollReminderAction.ignore,
                    ),
                  ),
                  _desktopDialogButton(
                    label: 'payable'.tr(),
                    primary: true,
                    onTap: () => Navigator.pop(
                      dialogContext,
                      _PayrollReminderAction.viewPayable,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    _reminderDialogOpen = false;

    switch (action) {
      case _PayrollReminderAction.remindLater:
        await PreferencesService.snoozePayrollReminder(
          reminderWindow.suppressionKey,
          now: now,
        );
        if (mounted) setState(() => _selectedFilter = 'All');
        break;
      case _PayrollReminderAction.ignore:
        await PreferencesService.ignorePayrollReminder(
          reminderWindow.suppressionKey,
        );
        break;
      case _PayrollReminderAction.viewPayable:
        if (mounted) {
          setState(() {
            _payrollMonth = reminderWindow.payrollMonth;
            _selectedFilter = 'Pay';
            _combinePayroll();
          });
          _scheduleAttendanceFetch();
        }
        break;
      case null:
        if (mounted) setState(() => _selectedFilter = 'Paid');
        break;
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
    final isGuest = _authService.currentUser?.isAnonymous ?? false;

    int workingDays;
    if (isGuest) {
      workingDays = 22;
    } else {
      try {
        workingDays = await _firestore.getMonthlyWorkingDays(month: month);
      } catch (_) {
        workingDays = 22;
      }
    }

    if (!mounted) {
      _isLoadingAttendance = false;
      return;
    }

    final futures = <Future<void>>[];
    for (final doc in _payrollDocs) {
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
          isGuest,
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
    bool isGuest,
  ) async {
    try {
      Map<String, int> attendance;
      if (isGuest) {
        final monthAttendance = DummyData.attendance.where((att) {
          final attDate = AppDateUtils.attendanceRecordDate(att);
          return attDate != null &&
              attDate.year == month.year &&
              attDate.month == month.month;
        }).toList();
        final matched = monthAttendance.where((att) {
          final attWorkerId = (att['workerId'] ?? '').toString().trim();
          final attEmail = (att['email'] ?? '').toString().trim().toLowerCase();
          if (workerId.isNotEmpty && attWorkerId.isNotEmpty) {
            return workerId == attWorkerId;
          }
          return email.isNotEmpty && attEmail == email.toLowerCase();
        }).toList();
        final absentCount = matched
            .where((a) => (a['status'] ?? '') == 'Absent')
            .length;
        final leaveCount = matched
            .where((a) => (a['status'] ?? '') == 'Leave')
            .length;
        attendance = {
          'absents': absentCount,
          'paidLeaves': leaveCount,
          'unpaidLeaves': 0,
          'leaves': leaveCount,
        };
      } else {
        attendance = await _firestore.getWorkerMonthlyAttendance(
          email,
          workerId: workerId,
          month: month,
          preFetchedRecords: _liveAttendanceRecords,
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

  Future<void> _loadCompanySettings() async {
    String companyCurrency = CurrencyUtils.defaultCode;
    int? salaryPayDay;
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      final profile = await PreferencesService.getGuestProfileData();
      companyCurrency = CurrencyUtils.normalize(profile?['currency']);
      salaryPayDay = _payDayFromProfile(profile);
    } else {
      final profile = await _firestore.getUserProfile();
      companyCurrency = CurrencyUtils.normalize(profile?['currency']);
      salaryPayDay = _payDayFromProfile(profile);

      final rawProfileCurrency = profile?['currency']?.toString().trim();
      if (companyCurrency == CurrencyUtils.defaultCode &&
          (rawProfileCurrency == null || rawProfileCurrency.isEmpty)) {
        final cached = PreferencesService.cachedCompanyCurrency;
        if (cached != null && cached.isNotEmpty) {
          companyCurrency = CurrencyUtils.normalize(cached);
        }
      } else {
        PreferencesService.setCompanyCurrency(
          companyCurrency,
        ).catchError((_) {});
      }
    }
    if (!mounted) return;
    setState(() {
      _companyCurrency = companyCurrency;
      _salaryPayDay = salaryPayDay;
      _payrollMonth = PayrollService.currentPayrollMonth();
      _combinePayroll();
    });
    _scheduleAttendanceFetch();
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
    if (!widget.isActive) {
      _reminderHandledForActivation = false;
      _forceReminderForActivation = false;
    } else if (!oldWidget.isActive ||
        widget.activationToken != oldWidget.activationToken) {
      _reminderHandledForActivation = false;
      _forceReminderForActivation =
          widget.activationToken != oldWidget.activationToken;
      _schedulePayrollReminderCheck();
    }

    if (!_initialized || !(_authService.currentUser?.isAnonymous ?? false)) {
      return;
    }

    final latestWorkers = List<Map<String, dynamic>>.from(DummyData.workers);
    final currentIds = _workersList
        .map((worker) => worker['id']?.toString() ?? '')
        .toSet();
    final latestIds = latestWorkers
        .map((worker) => worker['id']?.toString() ?? '')
        .toSet();
    if (currentIds.length == latestIds.length &&
        currentIds.containsAll(latestIds)) {
      return;
    }

    _workersList = latestWorkers;
    _combinePayroll();
    _scheduleAttendanceFetch();
  }

  void _startPayrollListeners() {
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (!isGuest) {
      _profileSub = _firestore.userProfileStream.listen((profile) {
        if (!mounted || profile == null) return;
        final currency = CurrencyUtils.normalize(profile['currency']);
        final salaryPayDay = _payDayFromProfile(profile);
        if (currency == _companyCurrency && salaryPayDay == _salaryPayDay) {
          return;
        }
        final shouldResetReminder =
            salaryPayDay != _salaryPayDay &&
            !_reminderCheckScheduled &&
            !_reminderDialogOpen;
        setState(() {
          _companyCurrency = currency;
          _salaryPayDay = salaryPayDay;
          if (shouldResetReminder) {
            _reminderHandledForActivation = false;
          }
          _combinePayroll();
        });
        _scheduleAttendanceFetch();
      }, onError: _handlePayrollStreamError);
      _workersSub = _firestore.workersStream.listen((snapshot) {
        if (mounted) {
          setState(() {
            _workersLoaded = true;
            _workersList = snapshot.docs
                .map((d) => {...?d.data() as Map<String, dynamic>?, 'id': d.id})
                .toList();
            _combinePayroll();
          });
          _scheduleAttendanceFetch();
        }
      }, onError: _handlePayrollStreamError);
      _payrollSub = _firestore.payrollStream.listen((snapshot) {
        if (mounted) {
          setState(() {
            _payrollLoaded = true;
            _rawPayrollDocs = snapshot.docs
                .map((d) => {...?d.data() as Map<String, dynamic>?, 'id': d.id})
                .toList();
            _combinePayroll();
          });
          _scheduleAttendanceFetch();
        }
      }, onError: _handlePayrollStreamError);

      _attendanceSub = _firestore.attendanceStream.listen((snapshot) {
        if (!mounted) return;
        _liveAttendanceRecords = snapshot.docs
            .map(
              (doc) => {...?doc.data() as Map<String, dynamic>?, 'id': doc.id},
            )
            .toList();
        _scheduleAttendanceFetch();
      }, onError: _handlePayrollStreamError);

      _holidaysSub = _firestore.holidaysStream.listen((_) {
        if (mounted) _scheduleAttendanceFetch();
      }, onError: _handlePayrollStreamError);
    } else {
      setState(() {
        _workersLoaded = true;
        _payrollLoaded = true;
        _workersList = List<Map<String, dynamic>>.from(DummyData.workers);
        _rawPayrollDocs = List<Map<String, dynamic>>.from(DummyData.payroll);
        _combinePayroll();
        _scheduleAttendanceFetch();
      });
    }
  }

  void _handlePayrollStreamError(Object error, StackTrace stackTrace) {
    ErrorReporter.report(error, stackTrace, context: 'PayrollScreenStream');
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _showSetPayDayDialog() async {
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      showGuestRestrictionDialog(context);
      return;
    }

    var selectedDay = _salaryPayDay ?? DateTime.now().day;
    final day = await showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'SetPayDayDialog',
      barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.3),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, _, _) => const SizedBox(),
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
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
                builder: (dialogContext, setDialogState) => _desktopDialogShell(
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
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                      const SizedBox(height: 18),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 1.2,
                            ),
                        itemCount: 31,
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
                                    fontFamily: 'SF Pro Display',
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
                      onTap: () => Navigator.pop(dialogContext),
                    ),
                    _desktopDialogButton(
                      label: 'save'.tr(),
                      primary: true,
                      onTap: () => Navigator.pop(dialogContext, selectedDay),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (day == null || !mounted) return;

    try {
      await _firestore.updateUserProfile({'salaryPayDay': day});
      if (!mounted) return;
      final shouldResetReminder =
          !_reminderCheckScheduled && !_reminderDialogOpen;
      setState(() {
        _salaryPayDay = day;
        if (shouldResetReminder) {
          _reminderHandledForActivation = false;
        }
      });
      FlashySnackBar.show(context, message: 'salary_day_saved'.tr());
      _schedulePayrollReminderCheck();
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

  Future<void> _handlePayAll() async {
    await _handlePayAllForMonth(_payrollMonth);
  }

  Future<void> _handlePayAllForMonth(DateTime payrollMonth) async {
    if (_isRunningPayroll || _payableWorkersForPeriod(payrollMonth).isEmpty) {
      return;
    }
    setState(() => _isRunningPayroll = true);
    try {
      final summary = await PayrollRunner().payAll(
        context,
        payrollMonth: payrollMonth,
      );
      if (summary != null && mounted) {
        FlashySnackBar.show(
          context,
          message: 'payroll_run_complete'.tr(
            namedArgs: {'count': '${summary.successCount}'},
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        final msg = error is StateError && error.message.isNotEmpty
            ? error.message
            : (error.toString().isNotEmpty
                  ? error.toString()
                  : 'failed_to_save_record'.tr());
        FlashySnackBar.show(context, message: msg, isError: true);
      }
    } finally {
      if (mounted) setState(() => _isRunningPayroll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isAddingPayroll && _workerForPayroll != null) {
      return AddPayrollScreen(
        workerData: _workerForPayroll!,
        payrollMonth: _payrollMonth,
        readOnly: _isViewOnly,
        onNotificationTap: widget.onNotificationTap,
        onProfileTap: widget.onProfileTap,
        onBack: () {
          setState(() {
            _isAddingPayroll = false;
            _workerForPayroll = null;
            _isViewOnly = false;
          });
        },
      );
    }

    final hasCurrentPayableWorkers = _currentPayablePayrollWorkers.isNotEmpty;

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
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'pay_roll_list'.tr(),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF000000),
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'current_pay_period_label'.tr(
                                namedArgs: {
                                  'period': _payPeriodLabelFor(_payrollMonth),
                                },
                              ),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF667085),
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: ElevatedButton.icon(
                          onPressed: _showSetPayDayDialog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0247C4),
                            foregroundColor: const Color(0xFFFFFFFF),
                            minimumSize: const Size(32, 50),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            elevation: 0,
                          ),
                          icon: const Icon(
                            Icons.calendar_month_rounded,
                            size: 21,
                            color: Color(0xFFFFFFFF),
                          ),
                          label: Text(
                            _payDayButtonLabel(),
                            style: const TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: ElevatedButton.icon(
                          onPressed:
                              _isRunningPayroll || !hasCurrentPayableWorkers
                              ? null
                              : () {
                                  final isGuest =
                                      _authService.currentUser?.isAnonymous ??
                                      false;
                                  if (isGuest) {
                                    showGuestRestrictionDialog(context);
                                    return;
                                  }
                                  _handlePayAll();
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF27AE60),
                            disabledBackgroundColor: const Color(
                              0xFF27AE60,
                            ).withValues(alpha: 0.4),
                            foregroundColor: const Color(0xFFFFFFFF),
                            disabledForegroundColor: const Color(
                              0xFFFFFFFF,
                            ).withValues(alpha: 0.7),
                            minimumSize: const Size(32, 50),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            elevation: 0,
                          ),
                          icon: _isRunningPayroll
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFFFFFFF),
                                  ),
                                )
                              : SvgPicture.asset(
                                  'assets/payroll_icon.svg',
                                  width: 22,
                                  height: 22,
                                  colorFilter: const ColorFilter.mode(
                                    Color(0xFFFFFFFF),
                                    BlendMode.srcIn,
                                  ),
                                ),
                          label: Text(
                            'pay_all'.tr(),
                            style: const TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: '',
                        onSelected: (val) {
                          setState(() {
                            _selectedFilter = val;
                          });
                        },
                        offset: const Offset(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                          side: BorderSide(
                            color: Colors.grey.shade200,
                            width: 1,
                          ),
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
                            final String currentVal =
                                _selectedFilter == 'Pay' ||
                                    _selectedFilter == 'Paid'
                                ? _selectedFilter
                                : 'All';
                            final bool selected = currentVal == f['value'];
                            return PopupMenuItem<String>(
                              value: f['value'],
                              height: 50,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
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
                                        fontFamily: 'SF Pro Display',
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
                                  fontFamily: 'SF Pro Display',
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
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _isLoading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 80),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : (_filteredEmployees.isEmpty
                            ? _buildEmptyState()
                            : _buildTable()),
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
                style: TextStyle(
                  color: Color(0xFF000000),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'SF Pro Display',
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

  Widget _buildSearchBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
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
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              decoration: InputDecoration(
                hintText: 'search_workers_name_position'.tr(),
                hintStyle: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                  fontFamily: 'SF Pro Display',
                ),
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
                  setState(() {
                    _searchQuery = '';
                  });
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

  bool _matchesFilter(Map<String, dynamic> doc, String filter) {
    if (filter == 'All') return true;
    if (filter == 'Pay') {
      return doc['isPaid'] != true;
    }
    if (filter == 'Paid') {
      return doc['isPaid'] == true;
    }
    if (filter == 'Today') {
      return PayrollService.wasPaidOn(doc, DateTime.now());
    }
    final position = (doc['position'] ?? '').toString();
    return position.toLowerCase().contains(filter.toLowerCase());
  }

  List<Map<String, dynamic>> get _filteredEmployees {
    final filtered = _payrollDocs.where((doc) {
      final name = (doc['name'] ?? '').toString().toLowerCase();
      final pos = (doc['position'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      final matchesSearch = name.contains(query) || pos.contains(query);

      if (!matchesSearch) return false;
      return _matchesFilter(doc, _selectedFilter);
    }).toList();

    filtered.sort((a, b) {
      final paidA = a['isPaid'] == true;
      final paidB = b['isPaid'] == true;
      if (paidA != paidB) return paidA ? 1 : -1;
      final nameA = (a['name'] ?? '').toString().trim().toLowerCase();
      final nameB = (b['name'] ?? '').toString().trim().toLowerCase();
      return nameA.compareTo(nameB);
    });

    return filtered;
  }

  Widget _buildFilterTabs() {
    const defaultPositions = LocalizationHelper.defaultJobPositions;
    final actualPositions = <String>{};
    final positionNormalizer = <String, String>{};
    for (final w in _workersList) {
      final pos = (w['position'] ?? '').toString().trim();
      if (pos.isNotEmpty) {
        final key = pos.toLowerCase();
        if (!positionNormalizer.containsKey(key)) {
          positionNormalizer[key] = pos;
          actualPositions.add(pos);
        }
      }
    }
    final sortedPositions = actualPositions.toList()..sort();

    final positionsToShow = <String>[...sortedPositions];
    for (final position in defaultPositions) {
      final alreadyIncluded = positionsToShow.any(
        (item) =>
            item.toLowerCase().contains(position.toLowerCase()) ||
            position.toLowerCase().contains(item.toLowerCase()),
      );
      if (!alreadyIncluded) {
        positionsToShow.add(position);
      }
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
            for (int i = 0; i < filters.length; i++)
              _buildFilterTab(filters[i]['key']!, filters[i]['label']!),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTab(String filterKey, String displayLabel) {
    final bool isSelected = _selectedFilter == filterKey;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedFilter = filterKey;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        margin: const EdgeInsets.only(right: 6),
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
            fontFamily: 'SF Pro Display',
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final bool isSearchEmpty = _searchQuery.isNotEmpty;
    final double dynamicHeight = (MediaQuery.of(context).size.height - 329)
        .clamp(440.0, 1200.0);
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
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
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
            isSearchEmpty
                ? 'no_search_results'.tr()
                : 'no_payroll_records'.tr(),
            style: TextStyle(
              color: Color(0xFF0247C4),
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'SF Pro Display',
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    final double tableHeight = (MediaQuery.of(context).size.height - 329).clamp(
      440.0,
      1200.0,
    );

    return Container(
      height: tableHeight,
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
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
                    padding: const EdgeInsets.only(right: 24.0),
                    child: Text(
                      'worker_name_header'.tr(),
                      style: _headerStyle(),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 24.0),
                    child: Text('position'.tr(), style: _headerStyle()),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 24.0),
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
              itemCount: _filteredEmployees.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _buildEmployeeRow(_filteredEmployees[index], index),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _headerStyle() {
    return const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: Colors.black,
      fontFamily: 'SF Pro Display',
    );
  }

  Widget _buildEmployeeRow(Map<String, dynamic> doc, int index) {
    final isPaid = doc['isPaid'] == true;
    final hasData = (doc['totalWorkDays'] ?? '').toString().isNotEmpty;

    final contactNo = (doc['phone'] ?? '').toString().trim().isEmpty
        ? (doc['contact'] ?? '').toString()
        : (doc['phone'] ?? '').toString();

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
                onTap: () {
                  final isGuest =
                      _authService.currentUser?.isAnonymous ?? false;
                  if (isGuest) {
                    showGuestRestrictionDialog(context);
                    return;
                  }
                  if (isPaid && hasData) {
                    _showPayrollDataDialog(context, doc, index);
                  } else {
                    if (!_requirePayableSalary(doc)) return;
                    setState(() {
                      _isAddingPayroll = true;
                      _workerForPayroll = doc;
                    });
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 24.0),
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
                                fontFamily: 'SF Pro Display',
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              (doc['email'] ?? '').toString(),
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black,
                                fontFamily: 'SF Pro Display',
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
              padding: const EdgeInsets.only(right: 24.0),
              child: Text(
                LocalizationHelper.localizePosition(
                  (doc['position'] ?? '').toString(),
                ),
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black,
                  fontFamily: 'SF Pro Display',
                ),
                maxLines: 2,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 24.0),
              child: Text(
                contactNo,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black,
                  fontFamily: 'SF Pro Display',
                ),
                maxLines: 1,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 0.0),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    final isGuest =
                        _authService.currentUser?.isAnonymous ?? false;
                    if (isGuest) {
                      showGuestRestrictionDialog(context);
                      return;
                    }
                    if (isPaid && hasData) {
                      _showPayrollDataDialog(context, doc, index);
                    } else {
                      if (!_requirePayableSalary(doc)) return;
                      setState(() {
                        _isAddingPayroll = true;
                        _workerForPayroll = doc;
                      });
                    }
                  },
                  child: Text(
                    isPaid ? 'paid'.tr() : 'payable'.tr(),
                    style: TextStyle(
                      color: isPaid
                          ? const Color(0xFF27AE60)
                          : const Color(0xFFE74C3C),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 24, child: const SizedBox.shrink()),
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
      final totalDays = PayrollService.parseIntSafe(totalWorkDays);
      final workedDays =
          (totalDays -
                  PayrollService.parseIntSafe(absents) -
                  PayrollService.parseIntSafe(unpaidLeaves))
              .clamp(0, totalDays);
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
        daysWorked: '$workedDays',
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

      Map<String, dynamic> companyProfile = const {};
      try {
        companyProfile = await _firestore.getUserProfile() ?? const {};
      } catch (_) {}
      final bytes = await InvoiceService.generatePayrollInvoice(
        employeeName: (data['name'] ?? '').toString(),
        email: (data['email'] ?? '').toString(),
        position: (data['position'] ?? '').toString(),
        payPeriod: payPeriod,
        totalWorkDays: totalWorkDays,
        daysWorked: '$workedDays',
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
        companyName:
            (companyProfile['businessName'] ??
                    companyProfile['companyName'] ??
                    'HRMS')
                .toString(),
        companyAddress: (companyProfile['address'] ?? '').toString(),
        companyEmail: (companyProfile['email'] ?? '').toString(),
        companyPhone:
            (companyProfile['contact1'] ?? companyProfile['phone'] ?? '')
                .toString(),
        companyId:
            (companyProfile['companyId'] ?? companyProfile['businessId'] ?? '')
                .toString(),
        companyStampImageUrl: (companyProfile['companyStampUrl'] ?? '')
            .toString(),
        companyLogoUrl: (companyProfile['profilePic'] ?? '').toString(),
        workerId: (data['workerId'] ?? data['id'] ?? '').toString(),
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

  void _showPayrollDataDialog(
    BuildContext context,
    Map<String, dynamic> data,
    int index,
  ) async {
    final String name = (data['name'] ?? '').toString();
    final String email = (data['email'] ?? '').toString();
    final String totalWorkDays = (data['totalWorkDays'] ?? '0').toString();
    final String absents = (data['absents'] ?? '0').toString();
    final attendanceCounts = PayrollService.attendanceCounts(data);
    final String paidLeaves = (attendanceCounts['paidLeaves'] ?? 0).toString();
    final String deductionLeaveDays = (attendanceCounts['unpaidLeaves'] ?? 0)
        .toString();
    final String rawAbsentDeduction = (data['absentDeduction'] ?? '0')
        .toString();
    final String rawLeaveDeduction = (data['leaveDeduction'] ?? '0').toString();
    final String rawOvertimeAmount = (data['overtimeAmount'] ?? '0').toString();
    final deductionsAreTotals = data['deductionsAreTotals'] == true;
    final salaryDisplay = PayrollService.currentSalaryDisplay(
      data,
      companyCurrency: _companyCurrency,
    );
    final currencyPrefix = PayrollService.getCurrencyPrefix(salaryDisplay);
    final otPrefix = currencyPrefix.isEmpty ? '' : '$currencyPrefix ';
    final overtimeVal = PayrollService.extractSalary(rawOvertimeAmount);
    final String overtimeAmount =
        '$otPrefix${PayrollService.formatFullNumber(overtimeVal)}';
    final String salary = AmountText.formatFull(
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
    final basePreviewCalculation = totalDaysValue > 0
        ? PayrollService.calculatePayroll(
            salary: PayrollService.currentSalaryDisplay(
              data,
              companyCurrency: _companyCurrency,
            ),
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
    final previewCalculation =
        deductionsAreTotals && basePreviewCalculation.isNotEmpty
        ? {
            ...basePreviewCalculation,
            'formattedNet': () {
              final netPayment = PayrollService.calculateNetFromTotals(
                salary: PayrollService.currentSalaryDisplay(
                  data,
                  companyCurrency: _companyCurrency,
                ),
                overtimeAmount: rawOvertimeAmount,
                absentDeduction: rawAbsentDeduction,
                leaveDeduction: rawLeaveDeduction,
                salaryType: (data['salaryType'] ?? 'Monthly').toString(),
              );
              final currency = PayrollService.getCurrencyPrefix(
                PayrollService.currentSalaryDisplay(
                  data,
                  companyCurrency: _companyCurrency,
                ),
              );
              final prefix = currency.isEmpty ? '' : '$currency ';
              return '$prefix${PayrollService.formatFullNumber(netPayment)}';
            }(),
          }
        : basePreviewCalculation;
    final String salaryAfterDeduction = AmountText.formatFull(
      (previewCalculation['formattedNet'] ??
              previewCalculation['formattedNetSalary'] ??
              '0')
          .toString(),
      locale: context.locale.toString(),
    );
    final String absentDeduction = AmountText.formatFull(
      (deductionsAreTotals
              ? rawAbsentDeduction
              : previewCalculation['formattedAbsentDeduct'] ??
                    rawAbsentDeduction)
          .toString(),
      locale: context.locale.toString(),
    );

    final paidDate = PayrollService.payrollPaymentDate(data);
    final paidDateText = paidDate == null
        ? '-'
        : DateFormat.yMMMd(context.locale.toString()).format(paidDate);

    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 500 ? screenWidth * 0.9 : 480.0;

    final result = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'PayrollDataDialog',
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
              child: Dialog(
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
                          color: const Color(
                            0xFF000000,
                          ).withValues(alpha: 0.15),
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
                                onTap: () => Navigator.of(context).pop(),
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: const Padding(
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
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
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
                                  if (confirmed && context.mounted) {
                                    Navigator.of(context).pop('edit');
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
                              left: BorderSide(
                                color: Color(0xFFE8E8E8),
                                width: 1.5,
                              ),
                              right: BorderSide(
                                color: Color(0xFFE8E8E8),
                                width: 1.5,
                              ),
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
                                Builder(
                                  builder: (context) {
                                    final hasDeduction =
                                        (double.tryParse(
                                              absentDeduction.replaceAll(
                                                RegExp(r'[^0-9.]'),
                                                '',
                                              ),
                                            ) ??
                                            0.0) >
                                        0;
                                    final hasOvertime =
                                        (double.tryParse(
                                              overtimeAmount.replaceAll(
                                                RegExp(r'[^0-9.]'),
                                                '',
                                              ),
                                            ) ??
                                            0.0) >
                                        0;
                                    final showNetCard =
                                        hasDeduction || hasOvertime;

                                    if (showNetCard) {
                                      return Column(
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _buildMetricCard(
                                                  icon:
                                                      _buildOvertimeDaysIcon(),
                                                  title: 'overtime_amount'.tr(),
                                                  value: overtimeAmount,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: _buildMetricCard(
                                                  icon: const Icon(
                                                    Icons
                                                        .account_balance_wallet,
                                                    color: Color(0xFF004FDE),
                                                    size: 20,
                                                  ),
                                                  title:
                                                      'salary_after_deduction'
                                                          .tr(),
                                                  value: salaryAfterDeduction,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _buildMetricCard(
                                                  icon: _buildSalaryIcon(),
                                                  title: 'salary'.tr(),
                                                  value: salary,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              const Expanded(child: SizedBox()),
                                            ],
                                          ),
                                        ],
                                      );
                                    } else {
                                      return Row(
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
                                    }
                                  },
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
          ),
        );
      },
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
                    fontFamily: 'SF Pro Display',
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
                          fontFamily: 'SF Pro Display',
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
                    fontFamily: 'SF Pro Display',
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
                    fontFamily: 'SF Pro Display',
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

  Widget _buildAbsentsIcon() {
    return SvgPicture.asset(
      'assets/absent.svg',
      width: 20,
      height: 20,
      colorMapper: const SvgFillColorMapper(
        source: Color(0xFFFF0004),
        replacement: Color(0xFF004FDE),
      ),
    );
  }

  Widget _buildLeavesIcon() {
    return SvgPicture.asset(
      'assets/leave.svg',
      width: 20,
      height: 20,
      colorMapper: const SvgFillColorMapper(
        source: Color(0xFFFF7B00),
        replacement: Color(0xFF004FDE),
      ),
    );
  }

  Widget _buildSalaryIcon() {
    return Image.asset(
      'assets/salary.png',
      width: 20,
      height: 20,
      fit: BoxFit.contain,
      color: const Color(0xFF004FDE),
      colorBlendMode: BlendMode.srcIn,
    );
  }

  Widget _buildOvertimeDaysIcon() {
    return Image.asset(
      'assets/overtime.png',
      width: 20,
      height: 20,
      fit: BoxFit.contain,
      color: const Color(0xFF004FDE),
      colorBlendMode: BlendMode.srcIn,
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
