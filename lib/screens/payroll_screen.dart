import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:easy_localization/easy_localization.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/payroll_service.dart';
import '../services/invoice_service.dart';
import '../services/preferences_service.dart';
import '../services/error_reporter.dart';
import '../utils/image_utils.dart';
import '../utils/snackbar_utils.dart';
import '../utils/svg_fill_color_mapper.dart';
import '../utils/guest_restriction.dart';
import '../utils/date_utils.dart';
import '../utils/currency_utils.dart';
import 'add_payroll_screen.dart';
import '../services/salary_day_scheduler.dart';
import '../widgets/notification_bell.dart';
import '../widgets/amount_text.dart';

class PayrollScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;
  final VoidCallback? onAssignTimeOff;
  final VoidCallback? onNotificationTap;

  const PayrollScreen({
    super.key,
    required this.onLogout,
    required this.onProfileTap,
    this.onAssignTimeOff,
    this.onNotificationTap,
  });

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  late AuthService _authService;
  late FirestoreService _firestore;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'All';
  List<Map<String, dynamic>> _payrollDocs = [];
  List<Map<String, dynamic>> _workersList = [];
  List<Map<String, dynamic>> _rawPayrollDocs = [];
  bool _isLoading = true;
  bool _isSalaryDaySaving = false;
  int? _salaryPaymentDay;
  String _companyCurrency = CurrencyUtils.defaultCode;
  DateTime _payrollMonth = PayrollService.currentPayrollMonth();
  bool _payrollPeriodLoaded = false;
  bool _workersLoaded = false;
  bool _payrollLoaded = false;
  bool _isAdvancingPayrollPeriod = false;

  StreamSubscription? _payrollSub;
  StreamSubscription? _workersSub;

  bool _isAddingPayroll = false;
  Map<String, dynamic>? _workerForPayroll;
  bool _isRunningPayroll = false;
  bool _initialized = false;
  bool _isLoadingAttendance = false;
  bool _attendanceFetchPending = false;
  Timer? _attendanceDebounce;

  bool get _isPayDate {
    return PayrollService.isPayrollDue(DateTime.now(), _salaryPaymentDay);
  }

  @override
  void dispose() {
    _attendanceDebounce?.cancel();
    _payrollSub?.cancel();
    _workersSub?.cancel();
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
  }

  void _scheduleAttendanceFetch() {
    _attendanceDebounce?.cancel();
    _attendanceDebounce = Timer(const Duration(seconds: 2), () {
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
        );
      }

      doc['absents'] = (attendance['absents'] ?? 0).toString();
      doc['paidLeaves'] = (attendance['paidLeaves'] ?? 0).toString();
      doc['unpaidLeaves'] = (attendance['unpaidLeaves'] ?? 0).toString();
      doc['leaves'] = (attendance['leaves'] ?? 0).toString();
      doc['totalWorkDays'] = workingDays.toString();
    } catch (_) {}
  }

  Future<void> _loadCompanySettings() async {
    int? salaryDay;
    String? savedPayrollPeriod;
    String companyCurrency = CurrencyUtils.defaultCode;
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      salaryDay = await PreferencesService.getCompanySalaryDay();
      savedPayrollPeriod = await PreferencesService.getActivePayrollPeriod();
      final profile = await PreferencesService.getGuestProfileData();
      companyCurrency = CurrencyUtils.normalize(profile?['currency']);
    } else {
      final profile = await _firestore.getUserProfile();
      final rawDay = profile?['salaryPaymentDay'];
      savedPayrollPeriod = profile?['activePayrollPeriod']?.toString();
      salaryDay = rawDay is num
          ? rawDay.toInt()
          : int.tryParse(rawDay?.toString() ?? '');
      if (salaryDay != null && (salaryDay < 1 || salaryDay > 31)) {
        salaryDay = null;
      }
      companyCurrency = CurrencyUtils.normalize(profile?['currency']);
    }
    final savedMonth = PayrollService.parsePayrollPeriodLabel(
      savedPayrollPeriod,
    );
    final calendarMonth = PayrollService.currentPayrollMonth();
    final savedMonthIsFuture =
        savedMonth != null &&
        PayrollService.isMonthBefore(calendarMonth, savedMonth);
    final activeMonth = savedMonth == null || savedMonthIsFuture
        ? calendarMonth
        : savedMonth;
    if (savedMonth == null || savedMonthIsFuture) {
      try {
        await _saveActivePayrollPeriod(activeMonth);
      } catch (error, stackTrace) {
        ErrorReporter.report(
          error,
          stackTrace,
          context: 'InitializePayrollPeriod',
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _salaryPaymentDay = salaryDay;
      _companyCurrency = companyCurrency;
      _payrollMonth = activeMonth;
      _payrollPeriodLoaded = true;
      _combinePayroll();
    });
    _scheduleAttendanceFetch();
    _maybeAdvancePayrollPeriod();
  }

  Future<void> _saveActivePayrollPeriod(DateTime month) async {
    final label = PayrollService.payrollPeriodLabel(month);
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      await PreferencesService.setActivePayrollPeriod(label);
    } else {
      await _firestore.updateUserProfile({'activePayrollPeriod': label});
    }
  }

  Future<void> _maybeAdvancePayrollPeriod() async {
    if (!_payrollPeriodLoaded ||
        !_workersLoaded ||
        !_payrollLoaded ||
        _isAdvancingPayrollPeriod) {
      return;
    }
    final calendarMonth = PayrollService.currentPayrollMonth();
    if (!PayrollService.isMonthBefore(_payrollMonth, calendarMonth)) return;
    if (!PayrollService.allWorkersPaidForMonth(
      _workersList,
      _rawPayrollDocs,
      _payrollMonth,
    )) {
      return;
    }

    _isAdvancingPayrollPeriod = true;
    final nextMonth = PayrollService.nextPayrollMonth(_payrollMonth);
    var advanced = false;
    try {
      await _saveActivePayrollPeriod(nextMonth);
      if (!mounted) return;
      setState(() {
        _payrollMonth = nextMonth;
        _combinePayroll();
      });
      advanced = true;
      _scheduleAttendanceFetch();
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'AdvancePayrollPeriod');
    } finally {
      _isAdvancingPayrollPeriod = false;
    }
    if (mounted && advanced) _maybeAdvancePayrollPeriod();
  }

  Future<void> _saveCompanySalaryDay(int? day) async {
    if (_isSalaryDaySaving) return;
    setState(() => _isSalaryDaySaving = true);
    try {
      final isGuest = _authService.currentUser?.isAnonymous ?? false;
      if (isGuest) {
        await PreferencesService.setCompanySalaryDay(day);
      } else {
        if (day == null) {
          await _firestore.updateUserProfile({'salaryPaymentDay': null});
        } else {
          await _firestore.updateUserProfile({'salaryPaymentDay': day});
        }
      }
      if (!mounted) return;
      setState(() => _salaryPaymentDay = day);
      FlashySnackBar.show(context, message: 'salary_day_saved'.tr());
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'unexpected_error'.tr(),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSalaryDaySaving = false);
    }
  }

  Future<void> _showSalaryDayDialog() async {
    final now = DateTime.now();
    final daysInCurrentMonth = DateTime(now.year, now.month + 1, 0).day;

    int selectedDay = _salaryPaymentDay ?? -1;
    final result = await showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'SalaryDayDialog',
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
                builder: (context, setDialogState) => AlertDialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  title: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0247C4).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          Icons.calendar_month_rounded,
                          color: Color(0xFF0247C4),
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'set_salary_day'.tr(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                    ],
                  ),
                  content: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'salary_day_help'.tr(),
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 14,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const SizedBox(height: 20),
                        DropdownButtonFormField<int>(
                          initialValue: selectedDay,
                          dropdownColor: Colors.white,
                          decoration: InputDecoration(
                            labelText: 'salary_day_of_month'.tr(),
                            prefixIcon: const Icon(
                              Icons.account_balance_wallet,
                              color: Color(0xFF0247C4),
                              size: 22,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          items: [
                            DropdownMenuItem<int>(
                              value: -1,
                              child: Text('none'.tr()),
                            ),
                            ...List.generate(
                              daysInCurrentMonth,
                              (index) => DropdownMenuItem<int>(
                                value: index + 1,
                                child: Text('${index + 1}'),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => selectedDay = value);
                            }
                          },
                        ),
                        const SizedBox(height: 14),
                        if (selectedDay != -1)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'salary_day_schedule'.tr(
                                namedArgs: {'day': '$selectedDay'},
                              ),
                              style: const TextStyle(
                                color: Color(0xFF334155),
                                fontWeight: FontWeight.w600,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('cancel'.tr()),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0247C4),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(selectedDay),
                      child: Text('save'.tr()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (result != null && mounted) {
      await _saveCompanySalaryDay(result == -1 ? null : result);
    }
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

    _authService = Provider.of<AuthService>(context, listen: false);
    _firestore = Provider.of<FirestoreService>(context, listen: false);
    _loadCompanySettings();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startPayrollListeners();
    });
  }

  @override
  void didUpdateWidget(covariant PayrollScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
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
      _workersSub = _firestore.workersStream.listen((snapshot) {
        if (mounted) {
          setState(() {
            _workersList = snapshot.docs
                .map((d) => {...?d.data() as Map<String, dynamic>?, 'id': d.id})
                .toList();
            _workersLoaded = true;
            _combinePayroll();
          });
          _scheduleAttendanceFetch();
          _maybeAdvancePayrollPeriod();
        }
      }, onError: _handlePayrollStreamError);
      _payrollSub = _firestore.payrollStream.listen((snapshot) {
        if (mounted) {
          setState(() {
            _rawPayrollDocs = snapshot.docs
                .map((d) => {...?d.data() as Map<String, dynamic>?, 'id': d.id})
                .toList();
            _payrollLoaded = true;
            _combinePayroll();
          });
          _scheduleAttendanceFetch();
          _maybeAdvancePayrollPeriod();
        }
      }, onError: _handlePayrollStreamError);
    } else {
      setState(() {
        _workersList = List<Map<String, dynamic>>.from(DummyData.workers);
        _rawPayrollDocs = List<Map<String, dynamic>>.from(DummyData.payroll);
        _workersLoaded = true;
        _payrollLoaded = true;
        _combinePayroll();
        _scheduleAttendanceFetch();
      });
      _maybeAdvancePayrollPeriod();
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

  Future<void> _handlePayAll() async {
    if (_isRunningPayroll) return;
    setState(() => _isRunningPayroll = true);
    try {
      final positionFilter = _selectedFilter != 'All' ? _selectedFilter : null;
      final summary = await SalaryDayScheduler().payAll(
        context,
        payrollMonth: _payrollMonth,
        positionFilter: positionFilter,
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
        FlashySnackBar.show(
          context,
          message: 'failed_to_save_record'.tr(),
          isError: true,
        );
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
        onNotificationTap: widget.onNotificationTap,
        onProfileTap: widget.onProfileTap,
        onBack: () {
          setState(() {
            _isAddingPayroll = false;
            _workerForPayroll = null;
          });
        },
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'pay_roll_list'.tr(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF000000),
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                      if (_isPayDate)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: ElevatedButton.icon(
                            onPressed: _isRunningPayroll
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
                              foregroundColor: const Color(0xFFFFFFFF),
                              minimumSize: const Size(32, 50),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
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
                      ElevatedButton.icon(
                        onPressed: _isSalaryDaySaving
                            ? null
                            : () {
                                final isGuest =
                                    _authService.currentUser?.isAnonymous ??
                                    false;
                                if (isGuest) {
                                  showGuestRestrictionDialog(context);
                                  return;
                                }
                                _showSalaryDayDialog();
                              },
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
                        icon: _isSalaryDaySaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFFFFFFFF),
                                ),
                              )
                            : const Icon(
                                Icons.calendar_month_rounded,
                                size: 22,
                                color: Color(0xFFFFFFFF),
                              ),
                        label: Text(
                          _salaryPaymentDay == null
                              ? 'set_salary_day'.tr()
                              : 'salary_day_value'.tr(
                                  namedArgs: {'day': '$_salaryPaymentDay'},
                                ),
                          style: const TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'SF Pro Display',
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
              SizedBox(height: 4),
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
                hintText: 'search_by_workers_name'.tr(),
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
      final statusA = (a['status'] ?? '').toString();
      final statusB = (b['status'] ?? '').toString();
      if (statusA == 'Paid' && statusB != 'Paid') return -1;
      if (statusA != 'Paid' && statusB == 'Paid') return 1;
      return 0;
    });

    return filtered;
  }

  Widget _buildFilterTabs() {
    const defaultPositions = [
      'Designer',
      'Developer',
      'Engineering',
      'Sales',
      'Management',
    ];
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
      ...positionsToShow.map((p) => {'key': p, 'label': p}),
    ];
    return Container(
      width: 550,
      height: 46,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
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
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 12 : 16,
          vertical: 8,
        ),
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0D4CC6) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          displayLabel,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
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
    double dynamicHeight = MediaQuery.of(context).size.height - 450;
    if (dynamicHeight < 300) dynamicHeight = 300;
    return SizedBox(
      width: double.infinity,
      height: dynamicHeight,
      child: Center(
        child: Column(
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
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Text(
                      'worker_name_header'.tr(),
                      style: _headerStyle(),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Text('position'.tr(), style: _headerStyle()),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Text('contact_no'.tr(), style: _headerStyle()),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Text('status_header'.tr(), style: _headerStyle()),
                  ),
                ),
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
    return GestureDetector(
      onTap: () {
        final isGuest = _authService.currentUser?.isAnonymous ?? false;
        if (isGuest) {
          showGuestRestrictionDialog(context);
          return;
        }
        final isPaid = (doc['status'] ?? '').toString().toLowerCase() == 'paid';
        final hasData = (doc['totalWorkDays'] ?? '').toString().isNotEmpty;
        if (isPaid && hasData) {
          _showPayrollDataDialog(context, doc, index);
        } else {
          setState(() {
            _isAddingPayroll = true;
            _workerForPayroll = doc;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FA),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
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
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(right: 24.0),
                child: Text(
                  (doc['position'] ?? '').toString(),
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
                  (doc['phone'] ?? doc['contact'] ?? '').toString(),
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
              child: Align(
                alignment: Alignment.centerLeft,
                child: Builder(
                  builder: (context) {
                    final isPaid =
                        (doc['status'] ?? '').toString().toLowerCase() ==
                        'paid';
                    final hasData = (doc['totalWorkDays'] ?? '')
                        .toString()
                        .isNotEmpty;
                    return InkWell(
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
                          setState(() {
                            _isAddingPayroll = true;
                            _workerForPayroll = doc;
                          });
                        }
                      },
                      mouseCursor: SystemMouseCursors.click,
                      borderRadius: BorderRadius.circular(6),
                      child: Text(
                        isPaid ? 'paid'.tr() : 'pay'.tr(),
                        style: TextStyle(
                          color: isPaid
                              ? const Color(0xFF27AE60)
                              : const Color(0xFFE74C3C),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
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
      final unpaidLeaves = (counts['unpaidLeaves'] ?? 0).toString();
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
      final prefix = currency.isEmpty ? '' : '$currency ';

      final grossSalary = PayrollService.extractSalary(
        calculation['formattedGross'],
      );
      final absentDeductionTotal = deductionsAreTotals
          ? PayrollService.extractSalary(rawAbsentDeduction)
          : PayrollService.extractSalary(calculation['formattedAbsentDeduct']);
      final leaveDeductionTotal = deductionsAreTotals
          ? PayrollService.extractSalary(rawLeaveDeduction)
          : PayrollService.extractSalary(calculation['formattedLeaveDeduct']);
      final overtimeValue = PayrollService.extractSalary(overtime);
      final totalDeductions = absentDeductionTotal + leaveDeductionTotal;
      final netSalary = (grossSalary + overtimeValue - totalDeductions).clamp(
        0.0,
        double.infinity,
      );

      Map<String, dynamic> companyProfile = const {};
      try {
        companyProfile = await _firestore.getUserProfile() ?? const {};
      } catch (_) {}
      final period = (data['payrollPeriod'] ?? '').toString().trim();
      final payPeriod = period.isNotEmpty
          ? period
          : PayrollService.payrollPeriodLabel(_payrollMonth);
      final bytes = await InvoiceService.generatePayrollInvoice(
        employeeName: (data['name'] ?? '').toString(),
        email: (data['email'] ?? '').toString(),
        position: (data['position'] ?? '').toString(),
        payPeriod: payPeriod,
        totalWorkDays: totalWorkDays,
        daysWorked: '$workedDays',
        absents: absents,
        leaves: unpaidLeaves,
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
                    'HRMS Company')
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
    final String unpaidLeaves = (attendanceCounts['unpaidLeaves'] ?? 0)
        .toString();
    final String deductionLeaveDays = (attendanceCounts['unpaidLeaves'] ?? 0)
        .toString();
    final String rawAbsentDeduction = (data['absentDeduction'] ?? '0')
        .toString();
    final String rawLeaveDeduction = (data['leaveDeduction'] ?? '0').toString();
    final String rawOvertimeAmount = (data['overtimeAmount'] ?? '0').toString();
    final deductionsAreTotals = data['deductionsAreTotals'] == true;
    final String overtimeAmount = AmountText.formatFull(rawOvertimeAmount);
    final String salary = AmountText.formatFull(
      PayrollService.currentSalaryDisplay(
        data,
        companyCurrency: _companyCurrency,
      ),
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
              data['netSalary'] ??
              data['salaryAfterDeduction'] ??
              '0')
          .toString(),
    );
    final String absentDeduction = AmountText.formatFull(
      (deductionsAreTotals
              ? rawAbsentDeduction
              : previewCalculation['formattedAbsentDeduct'] ??
                    rawAbsentDeduction)
          .toString(),
    );
    final totalLeaves =
        PayrollService.parseIntSafe(paidLeaves) +
        PayrollService.parseIntSafe(unpaidLeaves);
    final presentDays =
        (totalDaysValue - PayrollService.parseIntSafe(absents) - totalLeaves)
            .clamp(0, totalDaysValue);
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
                    height: 535,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF000000).withValues(alpha: 0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
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
                                child: Text(
                                  'payroll_data_preview'.tr(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFFFFFFF),
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () =>
                                        Navigator.of(context).pop('edit'),
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: SvgPicture.asset(
                                          'assets/edit_icon.svg',
                                          height: 22,
                                          width: 22,
                                          colorFilter: const ColorFilter.mode(
                                            Color(0xFFFFFFFF),
                                            BlendMode.srcIn,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () async {
                                      await _downloadPayrollInvoice(data);
                                    },
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: SvgPicture.asset(
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
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        _buildWorkerPreviewHeader(
                          name: name,
                          email: email,
                          imageUrl: data['profileImage']?.toString(),
                        ),
                        Expanded(
                          child: Container(
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
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                16,
                                20,
                                16,
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildMetricCard(
                                          icon: _buildPresentsIcon(),
                                          title: 'presents'.tr(),
                                          value: '$presentDays',
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildMetricCard(
                                          icon: _buildAbsentsIcon(),
                                          title: 'absents_label'.tr(),
                                          value: absents,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildMetricCard(
                                          icon: _buildLeavesIcon(),
                                          title: 'leaves_label'.tr(),
                                          value: paidLeaves,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildMetricCard(
                                          icon: _buildUnpaidLeavesIcon(),
                                          title: 'unpaid_leaves_label'.tr(),
                                          value: unpaidLeaves,
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
                                          icon: _buildOvertimeDaysIcon(),
                                          title: 'overtime_amount'.tr(),
                                          value: overtimeAmount,
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
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildMetricCard(
                                          icon: const Icon(
                                            Icons.calendar_view_day_rounded,
                                            color: Color(0xFF004FDE),
                                            size: 20,
                                          ),
                                          title: 'total_working_days'.tr(),
                                          value: totalWorkDays,
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
                                ],
                              ),
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
        color: Color(0xFFFFFFFF),
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

  Widget _buildPresentsIcon() {
    return SvgPicture.asset(
      'assets/present_worker.svg',
      width: 20,
      height: 20,
      colorMapper: const SvgFillColorMapper(
        source: Color(0xFF00FF2A),
        replacement: Color(0xFF004FDE),
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

  Widget _buildUnpaidLeavesIcon() {
    return const Icon(
      Icons.event_busy_rounded,
      color: Color(0xFF004FDE),
      size: 20,
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
